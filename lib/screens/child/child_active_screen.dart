/// Child Active Screen
///
/// Main screen for child devices showing monitoring status.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../models/device_health.dart';
import '../../models/native_platform_status.dart';
import '../../services/auth_service.dart';
import '../../services/background_service.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/native_service.dart';
import '../../services/notification_service.dart';
import '../../services/schedule_enforcer.dart';
import '../../services/schedule_service.dart';
import 'lock_screen.dart';
import 'tamper_lock_screen.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen>
    with WidgetsBindingObserver {
  final _authService = AuthService();
  final _nativeService = NativeService();
  final _databaseService = DatabaseService();
  final _locationService = LocationService();
  final _scheduleEnforcer = ScheduleEnforcer();
  final _notificationService = NotificationService();

  bool _isMonitoring = false;
  bool _isLimitedProtectionMode = false;
  bool _isStartingMonitoring = false;
  bool _isShowingLockScreen = false;
  String _status = 'Initializing...';

  Timer? _syncTimer;
  Timer? _healthTimer;
  RealtimeChannel? _blockSubscription;
  Completer<void>? _resumeCompleter;
  NativePlatformStatus? _platformStatus;
  List<String> _databaseBlockedApps = [];
  List<String> _scheduleBlockedApps = [];
  List<String> _appliedBlockedApps = [];
  DateTime? _lastPolicySyncAt;
  DateTime? _lastHealthSyncAt;
  DeviceHealthStatus? _lastDeviceHealthStatus;
  bool _isShowingTamperScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startMonitoring());
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _healthTimer?.cancel();
    _blockSubscription?.unsubscribe();
    _scheduleEnforcer.stopEnforcing();
    unawaited(_locationService.stopTracking());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _resumeCompleter != null &&
        !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }

    if (state == AppLifecycleState.resumed && _isMonitoring) {
      unawaited(_pollProtectionHealth(forceSync: true));
    }
  }

  Future<void> _waitForResume() async {
    _resumeCompleter = Completer<void>();
    await _resumeCompleter!.future;
    _resumeCompleter = null;
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> _configureNativeMonitoringSession(String childId) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return;
    }

    await _nativeService.configureMonitoringSession(
      childId: childId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      supabaseUrl: SupabaseConfig.supabaseUrl,
      supabaseAnonKey: SupabaseConfig.supabaseAnonKey,
    );
  }

  void _startProtectionHealthLoop(String childId) {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_pollProtectionHealth(childId: childId));
    });
  }

  DeviceHealthStatus _buildDeviceHealthStatus({
    required String childId,
    required NativePlatformStatus platformStatus,
    required bool locationAllowed,
  }) {
    final now = DateTime.now().toUtc();
    final monitoringActive =
        platformStatus.monitoringSupported && platformStatus.monitoringActive;
    final notificationsGranted = platformStatus.notificationsGranted;
    final isManagedDevice = platformStatus.enrollmentMode == 'managed_device';

    DeviceTamperState tamperState = parseTamperState(platformStatus.tamperState);
    String? tamperReason = platformStatus.tamperReason;

    if (tamperState == DeviceTamperState.healthy ||
        tamperState == DeviceTamperState.degraded) {
      if (platformStatus.monitoringSupported && !monitoringActive) {
        tamperState = DeviceTamperState.tampered;
        tamperReason ??= 'Monitoring service is not running.';
      } else if (platformStatus.usageStatsSupported &&
          !platformStatus.usageStatsGranted) {
        tamperState = DeviceTamperState.tampered;
        tamperReason ??= 'Usage access was revoked.';
      } else if (platformStatus.overlayPermissionRequired &&
          !platformStatus.overlayGranted) {
        tamperState = DeviceTamperState.tampered;
        tamperReason ??= 'Overlay permission was revoked.';
      } else if (platformStatus.batteryOptimizationSupported &&
          !platformStatus.batteryOptimizationExempt) {
        tamperState = DeviceTamperState.tampered;
        tamperReason ??=
            'Battery optimization is blocking reliable monitoring.';
      } else if (isManagedDevice && !platformStatus.deviceOwner) {
        tamperState = DeviceTamperState.tampered;
        tamperReason ??= 'Managed device control was removed.';
      } else if (!notificationsGranted || !locationAllowed) {
        tamperState = DeviceTamperState.degraded;
        tamperReason = !notificationsGranted
            ? 'Notifications are disabled, so parent alerts may be delayed.'
            : 'Background location access is reduced.';
      } else {
        tamperState = DeviceTamperState.healthy;
        tamperReason = null;
      }
    }

    return DeviceHealthStatus(
      childId: childId,
      enrollmentMode: parseEnrollmentMode(platformStatus.enrollmentMode),
      tamperState: tamperState,
      tamperReason: tamperReason,
      lastHeartbeatAt: now,
      lastServiceSeenAt: monitoringActive ? now : null,
      lastPolicySyncAt: _lastPolicySyncAt,
      lastPermissionSnapshot: {
        'usageStatsGranted': platformStatus.usageStatsGranted,
        'overlayGranted': platformStatus.overlayGranted,
        'batteryOptimizationExempt': platformStatus.batteryOptimizationExempt,
        'notificationsGranted': notificationsGranted,
        'backgroundLocationAllowed': locationAllowed,
        'deviceOwner': platformStatus.deviceOwner,
        'criticalPermissionsOk': platformStatus.criticalPermissionsOk,
      },
      deviceOwner: platformStatus.deviceOwner,
      criticalPermissionsOk: platformStatus.criticalPermissionsOk,
      monitoringActive: monitoringActive,
      appVersion: null,
      lastHealthyAt: tamperState == DeviceTamperState.healthy ? now : null,
      lastAlertSentAt: null,
      lastReminderSentAt: null,
      updatedAt: now,
    );
  }

  bool _shouldSyncDeviceHealth(DeviceHealthStatus status, {bool force = false}) {
    if (force || _lastHealthSyncAt == null || _lastDeviceHealthStatus == null) {
      return true;
    }

    final hasStateChanged =
        _lastDeviceHealthStatus!.tamperState != status.tamperState ||
        _lastDeviceHealthStatus!.tamperReason != status.tamperReason ||
        _lastDeviceHealthStatus!.enrollmentMode != status.enrollmentMode ||
        _lastDeviceHealthStatus!.monitoringActive != status.monitoringActive;

    if (hasStateChanged) {
      return true;
    }

    return DateTime.now().toUtc().difference(_lastHealthSyncAt!) >=
        const Duration(seconds: 60);
  }

  Future<void> _pollProtectionHealth({
    String? childId,
    bool forceSync = false,
  }) async {
    final resolvedChildId = childId ?? _authService.currentUser?.id;
    if (resolvedChildId == null) {
      return;
    }

    final platformStatus = await _nativeService.getPlatformStatus();
    final locationPermission = await Geolocator.checkPermission();
    final locationAllowed =
        locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;

    if (mounted) {
      setState(() => _platformStatus = platformStatus);
    }

    final healthStatus = _buildDeviceHealthStatus(
      childId: resolvedChildId,
      platformStatus: platformStatus,
      locationAllowed: locationAllowed,
    );

    if (mounted && healthStatus.tamperState == DeviceTamperState.tampered) {
      setState(() {
        _status = healthStatus.tamperReason ?? 'Protection interrupted.';
      });
    }

    if (_shouldSyncDeviceHealth(healthStatus, force: forceSync)) {
      await _configureNativeMonitoringSession(resolvedChildId);
      await _databaseService.upsertDeviceHealth(healthStatus);
      _lastHealthSyncAt = DateTime.now().toUtc();
      _lastDeviceHealthStatus = healthStatus;

      if (Platform.isAndroid) {
        await _nativeService.syncDeviceHealthNow();
      }
    }

    if (healthStatus.tamperState == DeviceTamperState.tampered &&
        !_isShowingTamperScreen) {
      _showTamperLockScreen(healthStatus);
    }
  }

  Future<void> _startMonitoring() async {
    final tamperActive =
        _lastDeviceHealthStatus?.tamperState == DeviceTamperState.tampered;
    if (_isStartingMonitoring ||
        (_isMonitoring && !tamperActive) ||
        _isLimitedProtectionMode) {
      return;
    }

    final childId = _authService.currentUser?.id;
    if (childId == null) {
      if (mounted) {
        setState(() => _status = 'Please sign in again to continue.');
      }
      return;
    }

    _isStartingMonitoring = true;
    if (mounted) {
      setState(() => _status = 'Checking device capabilities...');
    }

    try {
      var platformStatus = await _nativeService.getPlatformStatus();
      if (mounted) {
        setState(() => _platformStatus = platformStatus);
      }

      if (Platform.isAndroid) {
        await _configureNativeMonitoringSession(childId);
      }

      final notificationsGranted = await _ensureNotificationPermission();
      final locationGranted = await _ensureLocationPermission();
      if (!locationGranted) {
        return;
      }

      if (Platform.isIOS) {
        final familyControlsAuthorized =
            await _ensureFamilyControlsAuthorization(platformStatus);
        if (familyControlsAuthorized) {
          platformStatus = await _nativeService.getPlatformStatus();
          if (mounted) {
            setState(() => _platformStatus = platformStatus);
          }
        }
        await _startIosLimitedProtection(
          childId: childId,
          platformStatus: platformStatus,
          notificationsGranted: notificationsGranted,
        );
        return;
      }

      final usageAccessGranted = await _ensureUsageStatsPermission();
      if (!usageAccessGranted) {
        return;
      }

      final overlayGranted = await _ensureOverlayPermission();
      if (!overlayGranted) {
        return;
      }

      await _ensureBatteryOptimizationExemption();

      final isMonitoringActive = await _nativeService.isMonitoringActive();
      if (!isMonitoringActive) {
        await _nativeService.startMonitoringService([]);
      }

      if (platformStatus.deviceOwner) {
        await _nativeService.applyManagedDevicePolicies();
        platformStatus = await _nativeService.getPlatformStatus();
        if (mounted) {
          setState(() => _platformStatus = platformStatus);
        }
      }

      await _startAndroidProtection(childId, notificationsGranted);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: ${e.toString()}');
      }
    } finally {
      _isStartingMonitoring = false;
    }
  }

  Future<void> _startAndroidProtection(
    String childId,
    bool notificationsGranted,
  ) async {
    if (mounted) {
      setState(() => _status = 'Starting child protection...');
    }

    await _locationService.startTracking(childId);
    await _scheduleEnforcer.startEnforcing(
      childId: childId,
      onLockStateChange: _handleLockStateChange,
    );
    BackgroundService().registerPeriodicTask();
    _subscribeToManualBlocks(childId);
    _startProtectionHealthLoop(childId);

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_syncUsageToDatabase());
    });

    await _syncUsageToDatabase();
    await _pollProtectionHealth(childId: childId, forceSync: true);

    final isManagedDevice = _platformStatus?.isManagedDevice == true;
    final statusMessage = isManagedDevice
        ? notificationsGranted
              ? 'Protection active'
              : 'Protection active. Enable notifications for alerts.'
        : notificationsGranted
        ? 'Monitoring active, tamper detection only.'
        : 'Monitoring active, tamper detection only. Enable notifications for alerts.';

    if (mounted) {
      setState(() {
        _isMonitoring = true;
        _isLimitedProtectionMode = false;
        _status = statusMessage;
      });
    }
  }

  Future<void> _startIosLimitedProtection({
    required String childId,
    required NativePlatformStatus platformStatus,
    required bool notificationsGranted,
  }) async {
    if (mounted) {
      setState(() => _status = 'Starting location safety services...');
    }

    await _locationService.startTracking(childId);
    _startProtectionHealthLoop(childId);
    await _databaseService.upsertDeviceHealth(
      _buildDeviceHealthStatus(
        childId: childId,
        platformStatus: platformStatus,
        locationAllowed: true,
      ),
    );
    _lastHealthSyncAt = DateTime.now().toUtc();
    _lastDeviceHealthStatus = _buildDeviceHealthStatus(
      childId: childId,
      platformStatus: platformStatus,
      locationAllowed: true,
    );

    if (mounted) {
      setState(() {
        _platformStatus = platformStatus;
        _isMonitoring = false;
        _isLimitedProtectionMode = true;
        _status = _buildIosStatusMessage(
          platformStatus: platformStatus,
          notificationsGranted: notificationsGranted,
        );
      });
    }
  }

  String _buildIosStatusMessage({
    required NativePlatformStatus platformStatus,
    required bool notificationsGranted,
  }) {
    final buffer = StringBuffer(
      'Location safety is active on this iPhone build.',
    );

    if (!notificationsGranted) {
      buffer.write(' Enable notifications to receive parent alerts.');
    }

    if (platformStatus.familyControlsSupported &&
        !platformStatus.familyControlsAuthorized) {
      buffer.write(
        ' Screen Time permission is still needed before app blocking can be wired up.',
      );
    } else {
      buffer.write(
        ' App blocking still needs the Screen Time extension targets enabled in Xcode.',
      );
    }

    return buffer.toString();
  }

  Future<bool> _ensureNotificationPermission() async {
    if (mounted) {
      setState(() => _status = 'Checking notification permissions...');
    }
    return _notificationService.ensureUserPermission();
  }

  Future<bool> _ensureLocationPermission() async {
    if (mounted) {
      setState(() => _status = 'Checking location permissions...');
    }

    var locationPermission = await Geolocator.checkPermission();

    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
      if (locationPermission == LocationPermission.denied) {
        if (mounted) {
          setState(
            () => _status =
                'Location permission denied. Enable it in Settings to continue.',
          );
        }
        return false;
      }
    }

    if (locationPermission == LocationPermission.deniedForever) {
      final shouldOpenSettings = await _showPermissionDialog(
        title: 'Location Required',
        content:
            'ParentLock needs background location access to share live location, geofence alerts, and SOS details with your parent.',
        buttonLabel: 'Open Settings',
      );

      if (!shouldOpenSettings) {
        return false;
      }

      await Geolocator.openAppSettings();
      await _waitForResume();
      locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _status = 'Background location permission missing.');
        }
        return false;
      }
    }

    if (locationPermission == LocationPermission.whileInUse) {
      final shouldOpenSettings = await _showPermissionDialog(
        title: 'Allow All The Time',
        content:
            'For reliable location safety in the background, change Location permission to "Allow all the time" in Settings.',
        buttonLabel: 'Open Settings',
      );

      if (shouldOpenSettings) {
        await Geolocator.openAppSettings();
        await _waitForResume();
        locationPermission = await Geolocator.checkPermission();
      }

      if (locationPermission == LocationPermission.whileInUse) {
        if (mounted) {
          setState(
            () => _status =
                'Background location is still limited. Monitoring will be less reliable.',
          );
        }
      }
    }

    return true;
  }

  Future<bool> _ensureUsageStatsPermission() async {
    var platformStatus = await _nativeService.getPlatformStatus();
    if (mounted) {
      setState(() => _platformStatus = platformStatus);
      setState(() => _status = 'Checking usage access...');
    }

    if (platformStatus.usageStatsGranted) {
      return true;
    }

    final shouldOpenSettings = await _showPermissionDialog(
      title: 'Usage Access Required',
      content:
          'Find "ParentLock" in the system list and enable "Permit usage access" so the app can measure usage and enforce limits.',
      buttonLabel: 'Go to Settings',
    );

    if (!shouldOpenSettings) {
      return false;
    }

    await _nativeService.requestUsageStatsPermission();
    await _waitForResume();

    platformStatus = await _nativeService.getPlatformStatus();
    if (mounted) {
      setState(() => _platformStatus = platformStatus);
    }

    if (!platformStatus.usageStatsGranted && mounted) {
      setState(() => _status = 'Usage access denied. Monitoring inactive.');
    }

    return platformStatus.usageStatsGranted;
  }

  Future<bool> _ensureOverlayPermission() async {
    var platformStatus = await _nativeService.getPlatformStatus();
    if (mounted) {
      setState(() => _platformStatus = platformStatus);
      setState(() => _status = 'Checking overlay permissions...');
    }

    if (!platformStatus.overlayPermissionRequired ||
        platformStatus.overlayGranted) {
      return true;
    }

    final shouldOpenSettings = await _showPermissionDialog(
      title: 'Display Over Other Apps',
      content:
          'Allow ParentLock to display over other apps so blocked apps can be intercepted immediately.',
      buttonLabel: 'Go to Settings',
    );

    if (!shouldOpenSettings) {
      return false;
    }

    await _nativeService.requestOverlayPermission();
    await _waitForResume();

    platformStatus = await _nativeService.getPlatformStatus();
    if (mounted) {
      setState(() => _platformStatus = platformStatus);
    }

    if (!platformStatus.overlayGranted && mounted) {
      setState(
        () => _status = 'Overlay permission denied. Blocking will not work.',
      );
    }

    return platformStatus.overlayGranted;
  }

  Future<void> _ensureBatteryOptimizationExemption() async {
    final platformStatus = await _nativeService.getPlatformStatus();
    if (mounted) {
      setState(() => _platformStatus = platformStatus);
      setState(() => _status = 'Checking battery optimization settings...');
    }

    if (!platformStatus.batteryOptimizationSupported ||
        platformStatus.batteryOptimizationExempt) {
      return;
    }

    final shouldRequest = await _showPermissionDialog(
      title: 'Keep Monitoring Running',
      content:
          'Allow ParentLock to ignore battery optimization so monitoring stays alive when the child device is idle.',
      buttonLabel: 'Allow',
    );

    if (shouldRequest) {
      await _nativeService.requestIgnoreBatteryOptimizations();
    }
  }

  Future<bool> _ensureFamilyControlsAuthorization(
    NativePlatformStatus platformStatus,
  ) async {
    if (!platformStatus.familyControlsSupported ||
        platformStatus.familyControlsAuthorized) {
      return platformStatus.familyControlsAuthorized;
    }

    if (mounted) {
      setState(() => _status = 'Requesting Screen Time authorization...');
    }

    final shouldRequest = await _showPermissionDialog(
      title: 'Screen Time Permission',
      content:
          'Allow Screen Time permission so this child device is ready for iOS app-blocking once the Xcode extension targets are enabled.',
      buttonLabel: 'Continue',
    );

    if (!shouldRequest) {
      return false;
    }

    final authorized = await _nativeService.authorizeFamilyControls();
    if (!authorized && mounted) {
      setState(
        () => _status =
            'Screen Time permission was not granted. Location safety will stay active without app blocking.',
      );
    }
    return authorized;
  }

  Future<bool> _showPermissionDialog({
    required String title,
    required String content,
    required String buttonLabel,
  }) async {
    if (!mounted) return false;

    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );

    return shouldContinue ?? false;
  }

  void _handleLockStateChange(
    bool isLocked,
    LockScreenInfo? info,
    List<String> blockedApps,
  ) {
    _scheduleBlockedApps = List<String>.from(blockedApps);
    unawaited(_applyBlockedApps());

    if (!mounted) return;

    if (isLocked && !_isShowingLockScreen && info != null) {
      _isShowingLockScreen = true;
      _showLockScreen(info);
    }
  }

  Future<void> _subscribeToManualBlocks(String childId) async {
    await _blockSubscription?.unsubscribe();
    _blockSubscription = _databaseService.subscribeToBlockedApps(
      childId: childId,
      onBlockedAppsChanged: (blockedApps) async {
        _databaseBlockedApps = List<String>.from(blockedApps);
        await _applyBlockedApps();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'App limits updated: ${blockedApps.length} apps blocked',
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  Future<void> _applyBlockedApps() async {
    final blockedApps = {..._databaseBlockedApps, ..._scheduleBlockedApps}
      ..removeWhere((packageName) => packageName.trim().isEmpty);

    final sortedBlockedApps = blockedApps.toList()..sort();

    if (_listsEqual(sortedBlockedApps, _appliedBlockedApps)) {
      return;
    }

    _appliedBlockedApps = List<String>.from(sortedBlockedApps);

    if (_platformStatus?.appBlockingSupported != true) {
      return;
    }

    await _nativeService.updateBlockedApps(sortedBlockedApps);
    _lastPolicySyncAt = DateTime.now().toUtc();
    await _nativeService.recordPolicySync();
  }

  bool _listsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  void _showLockScreen(LockScreenInfo info) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) =>
                LockScreen(info: info, onEmergencyCall: () {}),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          _isShowingLockScreen = false;
        });
  }

  void _showTamperLockScreen(DeviceHealthStatus healthStatus) {
    if (!mounted) {
      return;
    }

    _isShowingTamperScreen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => TamperLockScreen(
              tamperReason:
                  healthStatus.tamperReason ??
                  'ParentLock detected that core protections were interrupted.',
              isManagedDevice:
                  healthStatus.enrollmentMode ==
                  DeviceEnrollmentMode.managedDevice,
              onReviewProtection: () async {
                Navigator.of(context).pop();
                await _startMonitoring();
              },
            ),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          _isShowingTamperScreen = false;
        });
  }

  Future<void> _syncUsageToDatabase() async {
    if (_platformStatus?.usageStatsSupported != true) {
      return;
    }

    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        return;
      }

      final fullUsageStats = await _nativeService.getFullUsageStats();
      await _databaseService.syncAllUsageStats(
        childId: userId,
        fullUsageStats: fullUsageStats,
      );

      final blockedApps = await _databaseService.getBlockedApps(userId);
      _databaseBlockedApps = List<String>.from(blockedApps);
      await _applyBlockedApps();
      _lastPolicySyncAt = DateTime.now().toUtc();
      await _pollProtectionHealth(childId: userId);
    } catch (e) {
      debugPrint('Child usage sync failed: $e');
    }
  }

  String _headlineText() {
    if (_isMonitoring) {
      return _platformStatus?.isManagedDevice == true
          ? 'Protection Active'
          : 'Monitoring Active';
    }
    if (_isLimitedProtectionMode) {
      return 'Safety Mode Active';
    }
    return 'Setting Up...';
  }

  String _footerText() {
    if (_isMonitoring) {
      if (_platformStatus?.isManagedDevice == true) {
        return 'Managed-device protection is active. ParentLock will keep watching for tampering and alert the parent if protections are interrupted.';
      }
      return 'This device is in standard monitoring mode. ParentLock can detect tampering quickly, but stock Android can still allow some system stop actions.';
    }
    if (_isLimitedProtectionMode) {
      return 'Location updates and SOS alerts are active. Finish the iOS Screen Time setup in Xcode to enable app blocking later.';
    }
    return 'ParentLock is preparing this device for monitoring.';
  }

  List<Widget> _buildInfoCards() {
    if (_isMonitoring) {
      final isManagedDevice = _platformStatus?.isManagedDevice == true;
      return [
        _InfoCard(
          icon: isManagedDevice ? Icons.shield : Icons.visibility,
          title: isManagedDevice ? 'Managed Protection' : 'Usage Tracked',
          subtitle: isManagedDevice
              ? 'Managed-device policies are helping resist tampering'
              : 'This device is being monitored in standard mode',
        ),
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.timer,
          title: 'Limits Applied',
          subtitle: 'App limits and schedules are active',
        ),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.notifications_active,
          title: 'Alerts Enabled',
          subtitle: isManagedDevice
              ? 'Parents are alerted if protection is interrupted'
              : 'Tamper alerts are sent when monitoring is interrupted',
        ),
      ];
    }

    if (_isLimitedProtectionMode) {
      return const [
        _InfoCard(
          icon: Icons.location_on,
          title: 'Location Tracked',
          subtitle: 'Live location, geofences, and SOS remain active',
        ),
        SizedBox(height: 12),
        _InfoCard(
          icon: Icons.notifications_active,
          title: 'Alerts Enabled',
          subtitle: 'Parent notifications can still be delivered',
        ),
        SizedBox(height: 12),
        _InfoCard(
          icon: Icons.phone_iphone,
          title: 'iOS Setup Needed',
          subtitle: 'Finish the Screen Time extension setup to enable blocking',
        ),
      ];
    }

    return const [];
  }

  Widget? _buildProtectionModeCallout() {
    if (!_isMonitoring || _platformStatus == null) {
      return null;
    }

    if (_platformStatus!.isManagedDevice) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Managed-device mode is active. ParentLock is applying the strongest anti-tamper protections available on Android.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Standard mode is active. ParentLock will detect tampering quickly, but stock Android can still allow some stop actions.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await _nativeService.requestDeviceAdmin();
            },
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text('Harden Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childId = _authService.currentUser?.id ?? '';
    final isProtectionEnabled = _isMonitoring || _isLimitedProtectionMode;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isProtectionEnabled ? Colors.green : Colors.orange,
                  isProtectionEnabled
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ParentLock',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Icon(
                          _platformStatus?.isManagedDevice == true
                              ? Icons.verified_user
                              : Icons.shield_outlined,
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isProtectionEnabled
                            ? Icons.shield_outlined
                            : Icons.hourglass_empty,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _headlineText(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 40),
                    ..._buildInfoCards(),
                    if (_buildProtectionModeCallout() != null) ...[
                      const SizedBox(height: 20),
                      _buildProtectionModeCallout()!,
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.white70),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _footerText(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if ((_isMonitoring || _isLimitedProtectionMode) && childId.isNotEmpty)
            Positioned(
              right: 24,
              bottom: 100,
              child: SosButtonWidget(childId: childId, onSosSent: () {}),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
