library;

enum DeviceEnrollmentMode { managedDevice, standard, limited }

enum DeviceTamperState { healthy, degraded, tampered, offline }

DeviceEnrollmentMode parseEnrollmentMode(String? value) {
  switch (value) {
    case 'managed_device':
      return DeviceEnrollmentMode.managedDevice;
    case 'limited':
      return DeviceEnrollmentMode.limited;
    case 'standard':
    default:
      return DeviceEnrollmentMode.standard;
  }
}

DeviceTamperState parseTamperState(String? value) {
  switch (value) {
    case 'degraded':
      return DeviceTamperState.degraded;
    case 'tampered':
      return DeviceTamperState.tampered;
    case 'offline':
      return DeviceTamperState.offline;
    case 'healthy':
    default:
      return DeviceTamperState.healthy;
  }
}

String enrollmentModeToJson(DeviceEnrollmentMode mode) {
  switch (mode) {
    case DeviceEnrollmentMode.managedDevice:
      return 'managed_device';
    case DeviceEnrollmentMode.limited:
      return 'limited';
    case DeviceEnrollmentMode.standard:
      return 'standard';
  }
}

String tamperStateToJson(DeviceTamperState state) {
  switch (state) {
    case DeviceTamperState.degraded:
      return 'degraded';
    case DeviceTamperState.tampered:
      return 'tampered';
    case DeviceTamperState.offline:
      return 'offline';
    case DeviceTamperState.healthy:
      return 'healthy';
  }
}

class DeviceHealthStatus {
  static const offlineThreshold = Duration(minutes: 3);

  final String childId;
  final DeviceEnrollmentMode enrollmentMode;
  final DeviceTamperState tamperState;
  final String? tamperReason;
  final DateTime lastHeartbeatAt;
  final DateTime? lastServiceSeenAt;
  final DateTime? lastPolicySyncAt;
  final Map<String, dynamic> lastPermissionSnapshot;
  final bool deviceOwner;
  final bool criticalPermissionsOk;
  final bool monitoringActive;
  final String? appVersion;
  final DateTime? lastHealthyAt;
  final DateTime? lastAlertSentAt;
  final DateTime? lastReminderSentAt;
  final DateTime? updatedAt;

  const DeviceHealthStatus({
    required this.childId,
    required this.enrollmentMode,
    required this.tamperState,
    required this.tamperReason,
    required this.lastHeartbeatAt,
    required this.lastServiceSeenAt,
    required this.lastPolicySyncAt,
    required this.lastPermissionSnapshot,
    required this.deviceOwner,
    required this.criticalPermissionsOk,
    required this.monitoringActive,
    required this.appVersion,
    required this.lastHealthyAt,
    required this.lastAlertSentAt,
    required this.lastReminderSentAt,
    required this.updatedAt,
  });

  factory DeviceHealthStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    Map<String, dynamic> parseMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return Map<String, dynamic>.from(
          value.map((key, item) => MapEntry(key.toString(), item)),
        );
      }
      return const {};
    }

    return DeviceHealthStatus(
      childId: json['child_id'] as String,
      enrollmentMode: parseEnrollmentMode(json['enrollment_mode'] as String?),
      tamperState: parseTamperState(json['tamper_state'] as String?),
      tamperReason: json['tamper_reason'] as String?,
      lastHeartbeatAt:
          parseDate(json['last_heartbeat_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastServiceSeenAt: parseDate(json['last_service_seen_at']),
      lastPolicySyncAt: parseDate(json['last_policy_sync_at']),
      lastPermissionSnapshot: parseMap(json['last_permission_snapshot']),
      deviceOwner: json['device_owner'] as bool? ?? false,
      criticalPermissionsOk: json['critical_permissions_ok'] as bool? ?? false,
      monitoringActive: json['monitoring_active'] as bool? ?? false,
      appVersion: json['app_version'] as String?,
      lastHealthyAt: parseDate(json['last_healthy_at']),
      lastAlertSentAt: parseDate(json['last_alert_sent_at']),
      lastReminderSentAt: parseDate(json['last_reminder_sent_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'child_id': childId,
      'enrollment_mode': enrollmentModeToJson(enrollmentMode),
      'tamper_state': tamperStateToJson(tamperState),
      'tamper_reason': tamperReason,
      'last_heartbeat_at': lastHeartbeatAt.toUtc().toIso8601String(),
      'last_service_seen_at': lastServiceSeenAt?.toUtc().toIso8601String(),
      'last_policy_sync_at': lastPolicySyncAt?.toUtc().toIso8601String(),
      'last_permission_snapshot': lastPermissionSnapshot,
      'device_owner': deviceOwner,
      'critical_permissions_ok': criticalPermissionsOk,
      'monitoring_active': monitoringActive,
      'app_version': appVersion,
      'last_healthy_at': lastHealthyAt?.toUtc().toIso8601String(),
      'last_alert_sent_at': lastAlertSentAt?.toUtc().toIso8601String(),
      'last_reminder_sent_at': lastReminderSentAt?.toUtc().toIso8601String(),
    };
  }

  DeviceTamperState effectiveStateAt(DateTime now) {
    if (now.toUtc().difference(lastHeartbeatAt.toUtc()) > offlineThreshold) {
      return DeviceTamperState.offline;
    }
    return tamperState;
  }

  String stateLabelAt(DateTime now) {
    switch (effectiveStateAt(now)) {
      case DeviceTamperState.healthy:
        return enrollmentMode == DeviceEnrollmentMode.managedDevice
            ? 'Protected'
            : enrollmentMode == DeviceEnrollmentMode.limited
            ? 'Limited protection'
            : 'Monitoring only';
      case DeviceTamperState.degraded:
        return 'Attention needed';
      case DeviceTamperState.tampered:
        return 'Tampered';
      case DeviceTamperState.offline:
        return 'Offline';
    }
  }
}

class DeviceHealthEvent {
  final String id;
  final String childId;
  final DeviceEnrollmentMode enrollmentMode;
  final DeviceTamperState tamperState;
  final String? tamperReason;
  final bool isReminder;
  final DateTime createdAt;

  const DeviceHealthEvent({
    required this.id,
    required this.childId,
    required this.enrollmentMode,
    required this.tamperState,
    required this.tamperReason,
    required this.isReminder,
    required this.createdAt,
  });

  factory DeviceHealthEvent.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    final metadataMap = metadata is Map
        ? Map<String, dynamic>.from(
            metadata.map((key, value) => MapEntry(key.toString(), value)),
          )
        : const <String, dynamic>{};

    return DeviceHealthEvent(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      enrollmentMode: parseEnrollmentMode(json['enrollment_mode'] as String?),
      tamperState: parseTamperState(json['tamper_state'] as String?),
      tamperReason: json['tamper_reason'] as String?,
      isReminder: metadataMap['is_reminder'] == true,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
