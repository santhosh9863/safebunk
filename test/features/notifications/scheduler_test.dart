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
    );
  }

  /// The real college day: 8:30-9:30, 9:30-10:25, 10:25-10:50 break,
  /// 10:50-11:50, 11:50-12:45, 12:45-1:30 lunch, 1:30-2:30, 2:30-3:30.
  List<TimetableEntry> collegeDay() {
    final slots = <(String, String)>[
      ('08:30', '09:30'),
      ('09:30', '10:25'),
      ('10:50', '11:50'),
      ('11:50', '12:45'),
      ('13:30', '14:30'),
      ('14:30', '15:30'),
    ];
    return [
      for (var i = 0; i < slots.length; i++)
        entry(id: 'c${i + 1}', fromTime: slots[i].$1, toTime: slots[i].$2),
    ];
  }

  List<NotificationType> typesOf(List<ClassNotificationPlan> plans) =>
      plans.map((p) => p.event.type).toList();

  group('planDueNow', () {
    test('signature moments are pre-scheduled, so nothing is due now', () {
      final plans = scheduler.planDueNow(
        entries: collegeDay(),
        now: DateTime(2026, 8, 11, 13, 50),
        timing: ClassReminderTiming.minutes10,
      );

      expect(plans, isEmpty);
    });

    test('no timetable -> no reminders at all', () {
      final plans = scheduler.planDueNow(
        entries: const [],
        now: DateTime(2026, 8, 11, 13, 50),
        timing: ClassReminderTiming.minutes10,
      );

      expect(plans, isEmpty);
    });
  });

  group('planFutureReminders (signature moments)', () {
    test('schedules the 4 daily moments for the real timetable', () {
      final plans = scheduler.planFutureReminders(
        entries: collegeDay(),
        now: DateTime(2026, 8, 11, 8, 0),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classReminder10Min));
      expect(typesOf(plans), contains(NotificationType.nextClass));
      expect(typesOf(plans), contains(NotificationType.dayWrapUp));
      expect(plans, hasLength(4));

      final firstLead = plans
          .where((p) =>
              p.event.type == NotificationType.classReminder10Min &&
              p.classId == 'c1')
          .single;
      expect(firstLead.deliverAt, DateTime(2026, 8, 11, 8, 20));

      final lastLead = plans
          .where((p) =>
              p.event.type == NotificationType.classReminder10Min &&
              p.classId == 'c6')
          .single;
      expect(lastLead.deliverAt, DateTime(2026, 8, 11, 14, 20));

      final next = plans
          .where((p) => p.event.type == NotificationType.nextClass)
          .single;
      // Post-lunch class starts 13:30; reminder 10 minutes before.
      expect(next.deliverAt, DateTime(2026, 8, 11, 13, 20));

      final wrap = plans
          .where((p) => p.event.type == NotificationType.dayWrapUp)
          .single;
      // Last class ends 15:30; wrap-up 15 minutes after.
      expect(wrap.deliverAt, DateTime(2026, 8, 11, 15, 45));
      expect(wrap.event.metadata['totalCount'], 6);
    });

    test('exactly two class-start leads (first + last), no stage noise', () {
      final plans = scheduler.planFutureReminders(
        entries: collegeDay(),
        now: DateTime(2026, 8, 11, 8, 0),
        timing: ClassReminderTiming.minutes10,
      );

      final leads =
          plans.where((p) => p.event.type == NotificationType.classReminder10Min);
      expect(leads, hasLength(2));
      expect(typesOf(plans), isNot(contains(NotificationType.classReminder5Min)));
    });

    test('30-minute timing shifts the leads', () {
      final plans = scheduler.planFutureReminders(
        entries: collegeDay(),
        now: DateTime(2026, 8, 11, 7, 50),
        timing: ClassReminderTiming.minutes30,
      );

      final firstLead = plans
          .where((p) =>
              p.event.type == NotificationType.classReminder30Min &&
              p.classId == 'c1')
          .single;
      expect(firstLead.deliverAt, DateTime(2026, 8, 11, 8, 0));

      final lastLead = plans
          .where((p) =>
              p.event.type == NotificationType.classReminder30Min &&
              p.classId == 'c6')
          .single;
      expect(lastLead.deliverAt, DateTime(2026, 8, 11, 14, 0));

      final next = plans
          .where((p) => p.event.type == NotificationType.nextClass)
          .single;
      // Post-lunch "next class" message is always 10 minutes before the
      // class — independent of the lead-time setting.
      expect(next.deliverAt, DateTime(2026, 8, 11, 13, 20));
    });

    test('when the last class is also the post-lunch class, one lead only', () {
      // Two classes: 8:30-9:30 and 13:30-14:30 (long lunch gap). The 13:30
      // class is both the post-lunch class AND the last class → one lead.
      final plans = scheduler.planFutureReminders(
        entries: [
          entry(id: 'a', fromTime: '08:30', toTime: '09:30'),
          entry(id: 'b', fromTime: '13:30', toTime: '14:30'),
        ],
        now: DateTime(2026, 8, 11, 8, 0),
        timing: ClassReminderTiming.minutes10,
      );

      final leads =
          plans.where((p) => p.event.type == NotificationType.classReminder10Min);
      expect(leads, hasLength(1));
      expect(leads.single.classId, 'a');
      expect(leads.single.deliverAt, DateTime(2026, 8, 11, 8, 20));
      expect(typesOf(plans), contains(NotificationType.nextClass));
      expect(typesOf(plans), contains(NotificationType.dayWrapUp));
    });

    test('single class: lead + wrap-up only', () {
      final plans = scheduler.planFutureReminders(
        entries: [entry()],
        now: DateTime(2026, 8, 11, 13, 0),
        timing: ClassReminderTiming.minutes10,
      );

      expect(typesOf(plans), contains(NotificationType.classReminder10Min));
      expect(typesOf(plans), contains(NotificationType.dayWrapUp));
      expect(typesOf(plans), isNot(contains(NotificationType.nextClass)));
    });

    test('past classes are never pre-scheduled', () {
      final plans = scheduler.planFutureReminders(
        entries: collegeDay(),
        now: DateTime(2026, 8, 11, 16, 0),
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

      final lead = plans.singleWhere(
        (p) => p.event.type == NotificationType.classReminder10Min,
      );
      final id =
          'cls${'stu_42'}_${lead.date}_${lead.classId}_${lead.event.type.name}';

      expect(id, 'clsstu_42_2026-08-11_c1_classReminder10Min');
    });
  });
}