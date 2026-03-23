/// Native Service
///
/// Bridge to native platform code via MethodChannel.
/// Handles communication with Android (Kotlin) and iOS (Swift) code for:
/// - Usage statistics
/// - Monitoring service
/// - App blocking
library;

import 'package:flutter/services.dart';
import '../models/native_platform_status.dart';

class NativeService {
  static const MethodChannel _channel = MethodChannel(
    'com.parentlock.parentlock/native',
  );

  Future<NativePlatformStatus> getPlatformStatus() async {
    try {
      final result = await _channel.invokeMethod('getPlatformStatus');
      if (result is Map) {
        return NativePlatformStatus.fromJson(
          Map<String, dynamic>.from(
            result.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    } on PlatformException {
      // Fall through to a safe default.
    }

    return const NativePlatformStatus(
      platform: 'unknown',
      monitoringSupported: false,
      monitoringActive: false,
      enrollmentMode: 'standard',
      deviceOwner: false,
      tamperState: 'healthy',
      tamperReason: null,
      lastHeartbeatAt: null,
      criticalPermissionsOk: false,
      usageStatsSupported: false,
      usageStatsGranted: false,
      appBlockingSupported: false,
      overlayPermissionRequired: false,
      overlayGranted: false,
      batteryOptimizationSupported: false,
      batteryOptimizationExempt: true,
      familyControlsSupported: false,
      familyControlsAuthorized: false,
      notificationsGranted: false,
      backgroundLocationSupported: true,
    );
  }

  /// Get usage statistics from the native platform
  ///
  /// Returns a map of package name to minutes used today
  Future<Map<String, int>> getUsageStats() async {
    try {
      final result = await _channel.invokeMethod('getUsageStats');

      // Android returns List<Map> with app_package_name, app_display_name, minutes_used
      if (result is List) {
        final Map<String, int> usageMap = {};
        for (final item in result) {
          if (item is Map) {
            final packageName = item['app_package_name'] as String?;
            final minutes = item['minutes_used'] as int? ?? 0;
            if (packageName != null) {
              usageMap[packageName] = minutes;
            }
          }
        }
        return usageMap;
      }

      // Fallback for other formats
      return Map<String, int>.from(result as Map);
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return {};
      }
      throw Exception('Failed to get usage stats: ${e.message}');
    }
  }

  /// Get full usage statistics including display names
  /// Returns list of maps with packageName, displayName, minutesUsed
  Future<List<Map<String, dynamic>>> getFullUsageStats() async {
    try {
      final result = await _channel.invokeMethod('getUsageStats');

      if (result is List) {
        return result
            .map((item) {
              if (item is Map) {
                return {
                  'packageName': item['app_package_name'] as String? ?? '',
                  'displayName': item['app_display_name'] as String? ?? '',
                  'minutesUsed': item['minutes_used'] as int? ?? 0,
                  'app_category': item['app_category'] as String? ?? 'other',
                };
              }
              return <String, dynamic>{};
            })
            .where((m) => m['packageName'] != '')
            .toList()
            .cast<Map<String, dynamic>>();
      }
      return [];
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return [];
      }
      throw Exception('Failed to get usage stats: ${e.message}');
    }
  }

  /// Start the native monitoring service
  ///
  /// The service runs in the background and tracks app usage
  Future<void> startMonitoringService(List<String> blockedApps) async {
    try {
      await _channel.invokeMethod('startMonitoringService', {
        'blockedApps': blockedApps,
      });
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        throw Exception(
          'Monitoring is not supported on this device yet. '
          'Finish the iOS Screen Time setup in Xcode to enable it.',
        );
      }
      throw Exception('Failed to start monitoring: ${e.message}');
    }
  }

  /// Stop the native monitoring service
  Future<void> stopMonitoringService() async {
    try {
      await _channel.invokeMethod('stopMonitoringService');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop monitoring: ${e.message}');
    }
  }

  Future<void> configureMonitoringSession({
    required String childId,
    required String accessToken,
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? refreshToken,
  }) async {
    try {
      await _channel.invokeMethod('configureMonitoringSession', {
        'childId': childId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to configure monitoring session: ${e.message}');
    }
  }

  Future<void> recordPolicySync() async {
    try {
      await _channel.invokeMethod('recordPolicySync');
    } on PlatformException catch (e) {
      throw Exception('Failed to record policy sync: ${e.message}');
    }
  }

  Future<void> syncDeviceHealthNow() async {
    try {
      await _channel.invokeMethod('syncDeviceHealthNow');
    } on PlatformException catch (e) {
      throw Exception('Failed to sync device health: ${e.message}');
    }
  }

  Future<void> requestDeviceAdmin() async {
    try {
      await _channel.invokeMethod('requestDeviceAdmin');
    } on PlatformException catch (e) {
      throw Exception('Failed to request device admin access: ${e.message}');
    }
  }

  Future<bool> applyManagedDevicePolicies() async {
    try {
      final result = await _channel.invokeMethod('applyManagedDevicePolicies');
      return result == true;
    } on PlatformException catch (e) {
      throw Exception('Failed to apply managed device policies: ${e.message}');
    }
  }

  /// Check if required permissions are granted
  ///
  /// Android: PACKAGE_USAGE_STATS, SYSTEM_ALERT_WINDOW
  /// iOS: Screen Time authorization
  Future<bool> checkPermissions() async {
    final status = await getPlatformStatus();
    if (status.monitoringSupported) {
      return status.usageStatsGranted &&
          (!status.overlayPermissionRequired || status.overlayGranted);
    }
    if (status.familyControlsSupported) {
      return status.familyControlsAuthorized;
    }
    return false;
  }

  /// Get detailed permission status
  Future<Map<String, bool>> getPermissionStatus() async {
    final status = await getPlatformStatus();
    return status.toPermissionMap();
  }

  /// Check if battery optimization is ignored
  Future<bool> checkBatteryOptimization() async {
    final status = await getPlatformStatus();
    return status.batteryOptimizationExempt;
  }

  /// Request required permissions
  ///
  /// Opens system settings for the user to grant permissions
  Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestPermissions');
    } on PlatformException catch (e) {
      throw Exception('Failed to request permissions: ${e.message}');
    }
  }

  /// Request usage stats permission specifically
  Future<void> requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
    } on PlatformException catch (e) {
      throw Exception('Failed to request usage stats permission: ${e.message}');
    }
  }

  /// Request overlay permission specifically
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      throw Exception('Failed to request overlay permission: ${e.message}');
    }
  }

  /// Request to ignore battery optimizations
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (e) {
      throw Exception(
        'Failed to request battery optimization exemption: ${e.message}',
      );
    }
  }

  /// Block a specific app
  ///
  /// Shows a full-screen overlay blocking the app
  Future<void> blockApp(String packageName) async {
    try {
      await _channel.invokeMethod('blockApp', {'packageName': packageName});
    } on PlatformException catch (e) {
      throw Exception('Failed to block app: ${e.message}');
    }
  }

  /// Unblock a specific app
  Future<void> unblockApp(String packageName) async {
    try {
      await _channel.invokeMethod('unblockApp', {'packageName': packageName});
    } on PlatformException catch (e) {
      throw Exception('Failed to unblock app: ${e.message}');
    }
  }

  /// Update the list of blocked apps
  Future<void> updateBlockedApps(List<String> blockedApps) async {
    try {
      await _channel.invokeMethod('updateBlockedApps', {
        'blockedApps': blockedApps,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to update blocked apps: ${e.message}');
    }
  }

  /// Get the current foreground app package name (Android only)
  Future<String?> getCurrentForegroundApp() async {
    try {
      final result = await _channel.invokeMethod('getCurrentForegroundApp');
      return result as String?;
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        return null;
      }
      return null;
    }
  }

  /// Check if the monitoring service is running
  Future<bool> isMonitoringActive() async {
    try {
      final result = await _channel.invokeMethod('isMonitoringActive');
      return result as bool;
    } on PlatformException {
      return false;
    }
  }

  /// Request to authorize Family Controls (iOS only)
  Future<bool> authorizeFamilyControls() async {
    try {
      final result = await _channel.invokeMethod('authorizeFamilyControls');
      return result as bool;
    } on PlatformException {
      return false;
    }
  }
}
