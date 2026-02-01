/// Child Active Screen
/// 
/// Main screen for child devices showing monitoring status
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/native_service.dart';
import '../../services/location_service.dart';
import '../../services/schedule_enforcer.dart';
import '../../services/schedule_service.dart';
import '../../services/background_service.dart';
import 'lock_screen.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _nativeService = NativeService();
  final _databaseService = DatabaseService();
  final _locationService = LocationService();
  final _scheduleEnforcer = ScheduleEnforcer();
  
  bool _isMonitoring = false;
  String _status = 'Initializing...';
  Timer? _syncTimer;
  bool _isShowingLockScreen = false;
  RealtimeChannel? _blockSubscription;
  Completer<void>? _resumeCompleter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMonitoring();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _blockSubscription?.unsubscribe();
    _scheduleEnforcer.stopEnforcing();
    _locationService.stopTracking();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
  }

  Future<void> _waitForResume() async {
    _resumeCompleter = Completer<void>();
    await _resumeCompleter!.future;
    _resumeCompleter = null;
    // Allow systems to update status
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> _startMonitoring() async {
    setState(() => _status = 'Starting monitoring service...');

    try {
      // 1. Location Permissions
      setState(() => _status = 'Checking location permissions...');
      LocationPermission locationPermission = await Geolocator.checkPermission();
      
      if (locationPermission == LocationPermission.denied) {
        setState(() => _status = 'Requesting location permissions...');
        locationPermission = await Geolocator.requestPermission();
        if (locationPermission == LocationPermission.denied) {
          setState(() => _status = 'Location permission denied. Please enable in settings.');
          // Retry logic can be added here or just return
          return;
        }
      }
      
      if (locationPermission == LocationPermission.deniedForever) {
        if (mounted) {
           await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Location Required'),
              content: const Text('Please enable "Allow all the time" or "Allow while using the app" for location to track activity properly.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        await Geolocator.openAppSettings();
        await _waitForResume();
        // Check again
        locationPermission = await Geolocator.checkPermission();
        if (locationPermission == LocationPermission.denied || locationPermission == LocationPermission.deniedForever) {
           setState(() => _status = 'Location permission missing.');
           return;
        }
      }

      // 2. Check Native Permissions Status
      var perms = await _nativeService.getPermissionStatus();
      
      // 3. Usage Access
      if (perms['usageStats'] != true) {
        setState(() => _status = 'Checking usage access...');
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Usage Access Required'),
              content: const Text('Find "ParentLock" in the list and enable "Permit usage access". This is needed to monitor app usage.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go to Settings'),
                ),
              ],
            ),
          );
        }
        
        await _nativeService.requestUsageStatsPermission();
        await _waitForResume();
        
        perms = await _nativeService.getPermissionStatus();
        if (perms['usageStats'] != true) {
           setState(() => _status = 'Usage access denied. Monitoring inactive.');
           return;
        }
      }

      // 4. Overlay Permission (Display over other apps)
      if (perms['overlay'] != true) {
         setState(() => _status = 'Checking overlay permission...');
         if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Display Over Other Apps'),
              content: const Text('Find "ParentLock" and enable "Allow display over other apps". This is required to block restricted apps.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go to Settings'),
                ),
              ],
            ),
          );
        }
        
        await _nativeService.requestOverlayPermission();
        await _waitForResume();

        perms = await _nativeService.getPermissionStatus();
        if (perms['overlay'] != true) {
           setState(() => _status = 'Overlay permission denied. Blocking wont work.');
        }
      }

      // 5. Battery Optimization
      try {
        final isIgnoringBattery = await _nativeService.checkBatteryOptimization();
        if (!isIgnoringBattery) {
           // Optional: Show dialog explaining why
           await _nativeService.requestIgnoreBatteryOptimizations();
           // No wait needed as it's a system dialog
        }
      } catch (e) {
        debugPrint('Battery optimization check failed: $e');
      }

      // Now we can safely start the monitoring service
      setState(() => _status = 'Starting monitoring...');
      await _nativeService.startMonitoringService([]);
      
      final userId = _authService.currentUser?.id;
      if (userId != null) {
        setState(() => _status = 'Starting services...');
        await _locationService.startTracking(userId);
        
        await _scheduleEnforcer.startEnforcing(
          childId: userId,
          onLockStateChange: _handleLockStateChange,
        );
        
        BackgroundService().registerPeriodicTask();
        _subscribeToManualBlocks(userId);
      }
      
      if (mounted) {
        setState(() {
          _isMonitoring = true;
          _status = 'Monitoring active';
        });
      }

      _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _syncUsageToDatabase();
      });
      
      await _syncUsageToDatabase();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: ${e.toString()}';
        });
      }
    }
  }

  /// Handle lock state changes from schedule enforcer
  void _handleLockStateChange(bool isLocked, LockScreenInfo? info) {
    if (!mounted) return;
    
    if (isLocked && !_isShowingLockScreen && info != null) {
      // Show lock screen
      _isShowingLockScreen = true;
      _showLockScreen(info);
    }
  }

  /// Show the full-screen lock overlay
  Future<void> _subscribeToManualBlocks(String childId) async {
    _blockSubscription = _databaseService.subscribeToBlockedApps(
      childId: childId,
      onBlockedAppsChanged: (blockedApps) async {
        debugPrint('RT: Blocked apps updated: $blockedApps');
        await _nativeService.updateBlockedApps(blockedApps);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('App limits updated: ${blockedApps.length} apps blocked'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  void _showLockScreen(LockScreenInfo info) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LockScreen(
          info: info,
          onEmergencyCall: () {
            // Handle emergency call - could open phone dialer
            debugPrint('Emergency call requested');
          },
        ),
        fullscreenDialog: true,
      ),
    ).then((_) {
      _isShowingLockScreen = false;
    });
  }

  Future<void> _syncUsageToDatabase() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        debugPrint('Sync: No user ID, skipping');
        return;
      }

      debugPrint('Sync: Starting sync for user $userId');

      // Get full usage stats from native service (includes display names)
      final fullUsageStats = await _nativeService.getFullUsageStats();
      debugPrint('Sync: Got ${fullUsageStats.length} apps from native');
      
      // Sync ALL apps to database (creates entries for new apps too)
      await _databaseService.syncAllUsageStats(
        childId: userId,
        fullUsageStats: fullUsageStats,
      );
      
      debugPrint('Sync: Database sync completed');

      // After sync, check for apps that have exceeded their limits and block them
      final blockedApps = await _databaseService.getBlockedApps(userId);
      debugPrint('Sync: Found ${blockedApps.length} blocked apps: $blockedApps');
      
      if (blockedApps.isNotEmpty) {
        debugPrint('Sync: Sending blocked apps to native service');
        await _nativeService.updateBlockedApps(blockedApps);
        debugPrint('Sync: Native service updated with blocked apps');
      }
    } catch (e) {
      debugPrint('Sync ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final childId = _authService.currentUser?.id ?? '';
    
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _isMonitoring ? Colors.green : Colors.orange,
                  _isMonitoring ? Colors.green.shade700 : Colors.orange.shade700,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Header
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
                        IconButton(
                          onPressed: () async {
                            await _authService.logout();
                            if (context.mounted) context.go('/login');
                          },
                          icon: const Icon(Icons.logout, color: Colors.white),
                        ),
                      ],
                    ),
                    
                    const Spacer(),
                    
                    // Status Icon
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isMonitoring 
                            ? Icons.shield_outlined 
                            : Icons.hourglass_empty,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Status Text
                    Text(
                      _isMonitoring ? 'Protection Active' : 'Setting Up...',
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
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Info Cards
                    if (_isMonitoring) ...[
                      _InfoCard(
                        icon: Icons.visibility,
                        title: 'Usage Tracked',
                        subtitle: 'Your screen time is being monitored',
                      ),
                      const SizedBox(height: 12),
                      _InfoCard(
                        icon: Icons.timer,
                        title: 'Limits Applied',
                        subtitle: 'App limits set by parent are active',
                      ),
                      const SizedBox(height: 12),
                      _InfoCard(
                        icon: Icons.notifications_active,
                        title: 'Alerts Enabled',
                        subtitle: 'You\'ll be notified before limits are reached',
                      ),
                    ],
                    
                    const Spacer(),
                    
                    // Note
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Keep this app running in the background for monitoring to work properly.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
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
          
          // SOS Button (bottom right)
          if (_isMonitoring && childId.isNotEmpty)
            Positioned(
              right: 24,
              bottom: 100,
              child: SosButtonWidget(
                childId: childId,
                onSosSent: () {
                  // Optionally show confirmation
                },
              ),
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
        color: Colors.white.withOpacity(0.15),
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
                    color: Colors.white.withOpacity(0.8),
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
