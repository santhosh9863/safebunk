import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/notifications/application/notification_scheduler.dart';
import 'package:safebunk_v2/features/notifications/data/models/notification_preferences_model.dart';
import 'package:safebunk_v2/features/notifications/domain/enums/notification_type.dart';
import 'package:safebunk_v2/models/api/timetable_model.dart';

void main() {
  const scheduler = ClassReminderScheduler();
  const date = '2026-08-11';

  TimetableEntry entry({
    String id = 'c1',
    String fromTime = '14:00',
    String toTime = '15:00',
    String? attendanceMarked,
  }) {
    return TimetableEntry(
      id: id,
      staffId: 's1',
      day: '2',
      hour: '1',
      fromTime: fromTime,
      toTime: toTime,
      date: date,
      subjectCode: 'MATH',
      subjectName: 'Mathematics',
      batches: const [],
      attendanceMarked: attendanceMarked,
    );
  }

  List<NotificationType> typesOf(List<ClassNotificationPlan> plans) =>
      plans.map((p) => p.event.type).toList();

  group('planDueNow (spec scenarios)', () {
    test('class at 14:00, now 13:50 -> 10-minute reminder', () {
      final plans = scheduler.planDueNow(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 50),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classReminder10Min));
      expect(typesOf(plans), isNot(contains(NotificationType.classReminder5Min)));
    });

    test('class at 14:00, now 13:55 -> 5-minute reminder', () {
      final plans = scheduler.planDueNow(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 55),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classReminder5Min));
    });

    test('class at 14:00, now 14:00 -> classStarting', () {
      final plans = scheduler.planDueNow(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 14, 0),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classStarting));
    });

    test('no timetable -> no reminders at all', () {
      final plans = scheduler.planDueNow(
        entries: const [],
        now: DateTime(2026, 8, 11, 13, 50),
        timing: ClassReminderTiming.minutes10,
      );

      expect(plans, isEmpty);
    });

    test('5-minute timing fires only the 5-minute stage', () {
      final plans = scheduler.planDueNow(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 55),
        timing: ClassReminderTiming.minutes5,
      );

      expect(typesOf(plans), contains(NotificationType.classReminder5Min));
      expect(typesOf(plans), isNot(contains(NotificationType.classReminder10Min)));
    });

    test('missed class (ended 15 min ago, not marked) -> classMissed', () {
      final plans = scheduler.planDueNow(
        entries: [entry(attendanceMarked: '0')],
        now: DateTime(2026, 8, 11, 15, 15),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classMissed));
    });

    test('missed class with attendance marked -> no classMissed', () {
      final plans = scheduler.planDueNow(
        entries: [entry(attendanceMarked: '1')],
        now: DateTime(2026, 8, 11, 15, 15),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), isNot(contains(NotificationType.classMissed)));
    });

    test('exactly one day fact per day', () {
      final plans = scheduler.planDueNow(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 50),
        timing: ClassReminderTiming.minutes10,
      );

      final dayFacts = plans.where((p) => p.deliverAt == null && p.classId == null).toList();
      expect(dayFacts, hasLength(1));
    });
  });

  group('planFutureReminders', () {
    test('pre-schedules 10-min and 5-min stages at exact lead times', () {
      final plans = scheduler.planFutureReminders(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 0),
        timing: ClassReminderTiming.minutes10,
      );

      final lead = plans.where((p) => p.event.type == NotificationType.classReminder10Min);
      final stage = plans.where((p) => p.event.type == NotificationType.classReminder5Min);

      expect(lead.single.deliverAt, DateTime(2026, 8, 11, 13, 50));
      expect(stage.single.deliverAt, DateTime(2026, 8, 11, 13, 55));
    });

    test('past classes are never pre-scheduled', () {
      final plans = scheduler.planFutureReminders(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 15, 0),
        timing: ClassReminderTiming.minutes10,
      );

      expect(plans, isEmpty);
    });

    test('dedupe ids are deterministic: student + date + class + type', () {
      final plans = scheduler.planFutureReminders(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 0),
        timing: ClassReminderTiming.minutes10,
      );

      final lead = plans.singleWhere((p) => p.event.type == NotificationType.classReminder10Min);
      final id =
          'cls${'stu_42'}_${lead.date}_${lead.classId}_${lead.event.type.name}';

      expect(id, 'clsstu_42_2026-08-11_c1_classReminder10Min');
    });
  });
}
