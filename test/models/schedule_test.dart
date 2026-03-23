import 'package:flutter_test/flutter_test.dart';
import 'package:parentlock/models/schedule.dart';

void main() {
  Schedule buildSchedule({
    required List<int> daysOfWeek,
    required int startHour,
    required int endHour,
  }) {
    return Schedule(
      id: 'schedule-1',
      parentId: 'parent-1',
      childId: 'child-1',
      name: 'Bedtime',
      scheduleType: ScheduleType.bedtime,
      daysOfWeek: daysOfWeek,
      startTime: TimeOfDayData(hour: startHour, minute: 0),
      endTime: TimeOfDayData(hour: endHour, minute: 0),
      createdAt: DateTime(2026),
    );
  }

  test('same-day schedules stay active only inside the selected window', () {
    final schedule = buildSchedule(
      daysOfWeek: const [1],
      startHour: 9,
      endHour: 17,
    );

    expect(schedule.isActiveNow(DateTime(2026, 3, 23, 10)), isTrue);
    expect(schedule.isActiveNow(DateTime(2026, 3, 23, 17)), isFalse);
    expect(schedule.isActiveNow(DateTime(2026, 3, 24, 10)), isFalse);
  });

  test(
    'overnight schedules stay active after midnight for the previous day',
    () {
      final schedule = buildSchedule(
        daysOfWeek: const [1],
        startHour: 21,
        endHour: 7,
      );

      expect(schedule.isActiveNow(DateTime(2026, 3, 23, 22)), isTrue);
      expect(schedule.isActiveNow(DateTime(2026, 3, 24, 1)), isTrue);
      expect(schedule.isActiveNow(DateTime(2026, 3, 24, 8)), isFalse);
    },
  );

  test(
    'overnight schedules do not activate after midnight without the previous day selected',
    () {
      final schedule = buildSchedule(
        daysOfWeek: const [2],
        startHour: 21,
        endHour: 7,
      );

      expect(schedule.isActiveNow(DateTime(2026, 3, 24, 1)), isFalse);
    },
  );
}
