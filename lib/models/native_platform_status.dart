/// Native platform capability and permission status.
///
/// Lets Flutter distinguish what the current platform can do, what the user
/// has already granted, and whether native monitoring is currently active.
library;

class NativePlatformStatus {
  final String platform;
  final bool monitoringSupported;
  final bool monitoringActive;
  final bool usageStatsSupported;
  final bool usageStatsGranted;
  final bool appBlockingSupported;
  final bool overlayPermissionRequired;
  final bool overlayGranted;
  final bool batteryOptimizationSupported;
  final bool batteryOptimizationExempt;
  final bool familyControlsSupported;
  final bool familyControlsAuthorized;
  final bool notificationsGranted;
  final bool backgroundLocationSupported;

  const NativePlatformStatus({
    required this.platform,
    required this.monitoringSupported,
    required this.monitoringActive,
    required this.usageStatsSupported,
    required this.usageStatsGranted,
    required this.appBlockingSupported,
    required this.overlayPermissionRequired,
    required this.overlayGranted,
    required this.batteryOptimizationSupported,
    required this.batteryOptimizationExempt,
    required this.familyControlsSupported,
    required this.familyControlsAuthorized,
    required this.notificationsGranted,
    required this.backgroundLocationSupported,
  });

  factory NativePlatformStatus.fromJson(Map<String, dynamic> json) {
    bool readBool(String key, {bool fallback = false}) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        return value.toLowerCase() == 'true';
      }
      return fallback;
    }

    return NativePlatformStatus(
      platform: (json['platform'] as String?) ?? 'unknown',
      monitoringSupported: readBool('monitoringSupported'),
      monitoringActive: readBool('monitoringActive'),
      usageStatsSupported: readBool('usageStatsSupported'),
      usageStatsGranted: readBool('usageStatsGranted'),
      appBlockingSupported: readBool('appBlockingSupported'),
      overlayPermissionRequired: readBool('overlayPermissionRequired'),
      overlayGranted: readBool('overlayGranted', fallback: true),
      batteryOptimizationSupported: readBool('batteryOptimizationSupported'),
      batteryOptimizationExempt: readBool(
        'batteryOptimizationExempt',
        fallback: true,
      ),
      familyControlsSupported: readBool('familyControlsSupported'),
      familyControlsAuthorized: readBool('familyControlsAuthorized'),
      notificationsGranted: readBool('notificationsGranted'),
      backgroundLocationSupported: readBool(
        'backgroundLocationSupported',
        fallback: true,
      ),
    );
  }

  Map<String, bool> toPermissionMap() {
    return {
      'usageStats': usageStatsGranted,
      'overlay': !overlayPermissionRequired || overlayGranted,
      'batteryOptimization': batteryOptimizationExempt,
      'notification': notificationsGranted,
      'familyControls': familyControlsAuthorized,
      'monitoringSupported': monitoringSupported,
    };
  }

  bool get canEnforceRestrictions =>
      monitoringSupported && appBlockingSupported && usageStatsSupported;
}
