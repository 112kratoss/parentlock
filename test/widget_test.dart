// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parentlock/models/schedule.dart';
import 'package:parentlock/screens/child/lock_screen.dart';
import 'package:parentlock/services/schedule_service.dart';

void main() {
  testWidgets('Lock screen smoke test', (WidgetTester tester) async {
    final info = LockScreenInfo(
      scheduleName: 'Bedtime',
      scheduleType: ScheduleType.bedtime,
      unlockTime: DateTime(2026, 3, 24, 7),
      message: "It's bedtime! Get some rest.",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(info: info, onEmergencyCall: () {}),
      ),
    );

    expect(find.text("It's Bedtime!"), findsOneWidget);
    expect(find.textContaining('Resumes at'), findsOneWidget);
    expect(find.text('Emergency Call'), findsOneWidget);
  });
}
