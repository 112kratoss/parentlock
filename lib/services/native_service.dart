/// Native Service
/// 
/// Bridge to native platform code via MethodChannel.
/// Handles communication with Android (Kotlin) and iOS (Swift) code for:
/// - Usage statistics
/// - Monitoring service
/// - App blocking
library;

import 'package:flutter/services.dart';

class NativeService {
  static const MethodChannel _channel = MethodChannel('com.parentlock.parentlock/native');

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
      throw Exception('Failed to get usage stats: ${e.message}');
    }
  }

  /// Get full usage statistics including display names
  /// Returns list of maps with packageName, displayName, minutesUsed
  Future<List<Map<String, dynamic>>> getFullUsageStats() async {
    try {
      final result = await _channel.invokeMethod('getUsageStats');
      
      if (result is List) {
        return result.map((item) {
          if (item is Map) {
            return {
              'packageName': item['app_package_name'] as String? ?? '',
              'displayName': item['app_display_name'] as String? ?? '',
              'minutesUsed': item['minutes_used'] as int? ?? 0,
            };
          }
          return <String, dynamic>{};
        }).where((m) => m['packageName'] != '').toList().cast<Map<String, dynamic>>();
      }
      return [];
    } on PlatformException catch (e) {
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

  /// Check if required permissions are granted
  /// 
  /// Android: PACKAGE_USAGE_STATS, SYSTEM_ALERT_WINDOW
  /// iOS: Screen Time authorization
  Future<bool> checkPermissions() async {
    final status = await getPermissionStatus();
    return status['usageStats'] == true && status['overlay'] == true;
  }

  /// Get detailed permission status
  Future<Map<String, bool>> getPermissionStatus() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      if (result is Map) {
        return Map<String, bool>.from(result.map((key, value) => MapEntry(key.toString(), value as bool)));
      }
      return {
        'usageStats': result as bool? ?? false,
        'overlay': result as bool? ?? false,
        'batteryOptimization': false,
      };
    } on PlatformException {
      return {
        'usageStats': false,
        'overlay': false,
        'batteryOptimization': false,
      };
    }
  }

  /// Check if battery optimization is ignored
  Future<bool> checkBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      if (result is Map) {
        return result['batteryOptimization'] as bool? ?? false;
      }
      return false;
    } on PlatformException {
      return false;
    }
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
      throw Exception('Failed to request battery optimization exemption: ${e.message}');
    }
  }

  /// Block a specific app
  /// 
  /// Shows a full-screen overlay blocking the app
  Future<void> blockApp(String packageName) async {
    try {
      await _channel.invokeMethod('blockApp', {
        'packageName': packageName,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to block app: ${e.message}');
    }
  }

  /// Unblock a specific app
  Future<void> unblockApp(String packageName) async {
    try {
      await _channel.invokeMethod('unblockApp', {
        'packageName': packageName,
      });
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
    } on PlatformException {
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
