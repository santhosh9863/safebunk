import '../../../models/api/timetable_model.dart';
import '../domain/entities/notification_event.dart';
import '../domain/enums/notification_priority.dart';
import '../domain/enums/notification_type.dart';
import '../data/models/notification_preferences_model.dart';

/// A planned notification derived from the real timetable.
class ClassNotificationPlan {
  final NotificationEvent event;
  final DateTime? deliverAt;

  /// Date key ("yyyy-MM-dd") and timetable class id — used to build
  /// deterministic dedupe ids (`student + date + class + reminderType`).
  final String? classId;
  final String? date;

  final NotificationPriority priority;

  const ClassNotificationPlan({
    required this.event,
    this.deliverAt,
    this.classId,
    this.date,
    required this.priority,
  });
}

/// Decides WHICH class notifications are appropriate, using ONLY real
/// timetable data ([TimetableEntry.fromTime]) and the current clock.
/// Never hardcodes class times.
class ClassReminderScheduler {
  const ClassReminderScheduler();

  /// Events that are due at THIS moment: a reminder whose lead time has
  /// arrived, a class starting/missed, the next class and day-level facts.
  /// All plans here have a null [deliverAt] (show immediately).
  ///
  /// Signature moments are all pre-scheduled via [planFutureReminders], so
  /// there is nothing extra to fire right now — this stays empty to avoid
  /// duplicate/spammy pushes on app open.
  List<ClassNotificationPlan> planDueNow({
    required List<TimetableEntry> entries,
    required DateTime now,
    required ClassReminderTiming timing,
  }) {
    return const [];
  }

  /// Reminders to PRE-SCHEDULE for the day's signature moments, so they fire
  /// at the exact instant even when the app is backgrounded.
  ///
  /// Exactly four plans per day (derived from the real timetable, never
  /// hardcoded times):
  ///   1. First class of the day  → lead reminder
  ///   2. First class after the longest break (lunch) → `nextClass`
  ///   3. Last class of the day   → lead reminder
  ///   4. ~15 min after the last class ends → `dayWrapUp`
  List<ClassNotificationPlan> planFutureReminders({
    required List<TimetableEntry> entries,
    required DateTime now,
    required ClassReminderTiming timing,
  }) {
    if (entries.isEmpty) return const [];

    final parsed = _parse(entries, now)
        .where((p) => p.$2.isAfter(now))
        .toList();
    if (parsed.isEmpty) return const [];

    final plans = <ClassNotificationPlan>[];
    final leadMinutes = timing.minutes;

    // 1. First class of the day → lead reminder.
    final first = parsed.first;
    final firstLeadAt = first.$2.subtract(Duration(minutes: leadMinutes));
    if (firstLeadAt.isAfter(now)) {
      plans.add(_plan(first.$1, _reminderTypeFor(timing), firstLeadAt,
          priority: NotificationPriority.normal));
    }

    // 2. First class after the longest break ≥ 30 min (lunch) → nextClass.
    final postLunch = _postLunchClass(parsed);
    if (postLunch != null) {
      final nextAt = postLunch.$2.subtract(const Duration(minutes: 10));
      if (nextAt.isAfter(now)) {
        plans.add(_plan(postLunch.$1, NotificationType.nextClass, nextAt,
            priority: NotificationPriority.normal,
            metadata: const {'minutes': 10}));
      }
    }

    // 3. Last class of the day → lead reminder (skip if it IS the first class
    //    of a single-class day, or the lunch class).
    final last = parsed.last;
    final isFirstAndOnly = last.$1.id == first.$1.id;
    if (!isFirstAndOnly &&
        (postLunch == null || last.$1.id != postLunch.$1.id)) {
      final lastLeadAt = last.$2.subtract(Duration(minutes: leadMinutes));
      if (lastLeadAt.isAfter(now)) {
        plans.add(_plan(last.$1, _reminderTypeFor(timing), lastLeadAt,
            priority: NotificationPriority.normal));
      }
    }

    // 4. Wrap-up ~15 min after the last class ends.
    final wrapAt = last.$3.add(const Duration(minutes: 15));
    if (wrapAt.isAfter(now)) {
      plans.add(ClassNotificationPlan(
        event: NotificationEvent(
          type: NotificationType.dayWrapUp,
          metadata: {'totalCount': parsed.length},
        ),
        deliverAt: wrapAt,
        date: _dateKey(last.$1, wrapAt),
        priority: NotificationPriority.normal,
      ));
    }

    return plans;
  }

  /// Class right after the longest gap ≥ 30 minutes (the lunch break).
  static (TimetableEntry, DateTime, DateTime)? _postLunchClass(
    List<(TimetableEntry, DateTime, DateTime)> parsed,
  ) {
    if (parsed.length < 2) return null;
    var largestGap = Duration.zero;
    var gapIndex = -1;
    for (var i = 1; i < parsed.length; i++) {
      final gap = parsed[i].$2.difference(parsed[i - 1].$3);
      if (gap > largestGap) {
        largestGap = gap;
        gapIndex = i;
      }
    }
    if (largestGap < const Duration(minutes: 30)) return null;
    return parsed[gapIndex];
  }

  // ─────────────────────────────────────────────────────────────

  ClassNotificationPlan _plan(
    TimetableEntry entry,
    NotificationType type,
    DateTime? deliverAt, {
    NotificationPriority priority = NotificationPriority.normal,
    Map<String, dynamic> metadata = const {},
  }) {
    return ClassNotificationPlan(
      event: NotificationEvent(type: type, subjectName: entry.subjectName, metadata: metadata),
      deliverAt: deliverAt,
      classId: entry.id,
      date: _dateKey(entry, deliverAt),
      priority: priority,
    );
  }

  static NotificationType _reminderTypeFor(ClassReminderTiming timing) {
    switch (timing) {
      case ClassReminderTiming.minutes30:
        return NotificationType.classReminder30Min;
      case ClassReminderTiming.minutes10:
        return NotificationType.classReminder10Min;
      case ClassReminderTiming.minutes5:
        return NotificationType.classReminder5Min;
    }
  }

  static List<(TimetableEntry, DateTime, DateTime)> _parse(
    List<TimetableEntry> entries,
    DateTime now,
  ) {
    final parsed = <(TimetableEntry, DateTime, DateTime)>[];
    for (final entry in entries) {
      final start = _parseStart(entry, now);
      if (start == null) continue;
      parsed.add((entry, start, _parseEnd(entry, start)));
    }
    parsed.sort((a, b) => a.$2.compareTo(b.$2));
    return parsed;
  }

  /// Parse "HH:mm" from the timetable's fromTime onto the entry's date
  /// (falling back to [now]'s date — this is today's schedule).
  static DateTime? _parseStart(TimetableEntry entry, DateTime now) {
    final time = _parseClock(entry.fromTime);
    if (time == null) return null;
    final date = _parseDate(entry.date) ?? now;
    return DateTime(date.year, date.month, date.day, time.$1, time.$2);
  }

  static DateTime _parseEnd(TimetableEntry entry, DateTime start) {
    final time = _parseClock(entry.toTime);
    if (time == null) return start.add(const Duration(hours: 1));
    return DateTime(start.year, start.month, start.day, time.$1, time.$2);
  }

  static String _dateKey(TimetableEntry entry, DateTime? fallback) {
    final parsed = _parseDate(entry.date);
    final date = parsed ?? fallback ?? DateTime.now();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static (int, int)? _parseClock(String raw) {
    if (raw.isEmpty) return null;
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null) return null;
    return (h, m);
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {}
    for (final pattern in [r'(\d{4})-(\d{2})-(\d{2})', r'(\d{2})-(\d{2})-(\d{4})']) {
      final match = RegExp(pattern).firstMatch(raw);
      if (match != null) {
        final a = int.tryParse(match.group(1)!);
        final b = int.tryParse(match.group(2)!);
        final c = int.tryParse(match.group(3)!);
        if (a != null && b != null && c != null) {
          if (a > 31) return DateTime(a, b, c);
          if (c > 31) return DateTime(c, b, a);
          return DateTime(c, b, a);
        }
      }
    }
    return null;
  }
}
