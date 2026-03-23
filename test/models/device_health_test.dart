import 'package:flutter_test/flutter_test.dart';
import 'package:parentlock/models/device_health.dart';

void main() {
  test('stale heartbeats are treated as offline', () {
    final status = DeviceHealthStatus(
      childId: 'child-1',
      enrollmentMode: DeviceEnrollmentMode.standard,
      tamperState: DeviceTamperState.healthy,
      tamperReason: null,
      lastHeartbeatAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
      lastServiceSeenAt: null,
      lastPolicySyncAt: null,
      lastPermissionSnapshot: const {},
      deviceOwner: false,
      criticalPermissionsOk: true,
      monitoringActive: true,
      appVersion: '1.0.0',
      lastHealthyAt: null,
      lastAlertSentAt: null,
      lastReminderSentAt: null,
      updatedAt: null,
    );

    expect(status.effectiveStateAt(DateTime.now().toUtc()), DeviceTamperState.offline);
    expect(status.stateLabelAt(DateTime.now().toUtc()), 'Offline');
  });

  test('healthy managed devices show protected label before staleness', () {
    final now = DateTime.now().toUtc();
    final status = DeviceHealthStatus(
      childId: 'child-1',
      enrollmentMode: DeviceEnrollmentMode.managedDevice,
      tamperState: DeviceTamperState.healthy,
      tamperReason: null,
      lastHeartbeatAt: now,
      lastServiceSeenAt: now,
      lastPolicySyncAt: now,
      lastPermissionSnapshot: const {},
      deviceOwner: true,
      criticalPermissionsOk: true,
      monitoringActive: true,
      appVersion: '1.0.0',
      lastHealthyAt: now,
      lastAlertSentAt: null,
      lastReminderSentAt: null,
      updatedAt: now,
    );

    expect(status.effectiveStateAt(now), DeviceTamperState.healthy);
    expect(status.stateLabelAt(now), 'Protected');
  });
}
