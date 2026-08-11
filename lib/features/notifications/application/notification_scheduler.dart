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
  List<ClassNotificationPlan> planDueNow({
    required List<TimetableEntry> entries,
    required DateTime now,
    required ClassReminderTiming timing,
  }) {
    if (entries.isEmpty) return const [];

    final parsed = _parse(entries, now);
    if (parsed.isEmpty) return const [];

    final plans = <ClassNotificationPlan>[];

    for (final (entry, start, end) in parsed) {
      final minutes = start.difference(now).inMinutes;

      if (minutes == timing.minutes) {
        plans.add(_plan(entry, _reminderTypeFor(timing), null,
            priority: NotificationPriority.normal));
      }
      if (timing != ClassReminderTiming.minutes5 && minutes == 5) {
        plans.add(_plan(entry, NotificationType.classReminder5Min, null,
            priority: NotificationPriority.normal));
      }
      if (minutes <= 2 && minutes >= -3) {
        plans.add(_plan(entry, NotificationType.classStarting, null,
            priority: NotificationPriority.high));
      }
      // A class counts as missed once it has ENDED (within the last 45 min)
      // and no attendance was marked for it.
      {
        final endedAgo = now.difference(end).inMinutes;
        if (endedAgo >= 0 && endedAgo <= 45 && !_isMarked(entry)) {
          plans.add(_plan(entry, NotificationType.classMissed, null,
              priority: NotificationPriority.high));
        }
      }
    }

    final upcoming = parsed.where((t) => t.$2.isAfter(now)).toList();
    if (upcoming.isNotEmpty) {
      final (nextEntry, nextStart, _) = upcoming.first;
      final minutes = nextStart.difference(now).inMinutes;
      if (minutes > 30) {
        plans.add(_plan(nextEntry, NotificationType.nextClass, null,
            metadata: {'minutes': minutes}));
      }
    }

    plans.addAll(_dayFacts(parsed));

    return plans;
  }

  /// Reminders to PRE-SCHEDULE for every upcoming class, so they fire at the
  /// exact lead-time instant even when the app is backgrounded.
  ///
  /// deliverAt = class start − lead time (and start − 5 min as a second
  /// stage when a different lead time is configured).
  List<ClassNotificationPlan> planFutureReminders({
    required List<TimetableEntry> entries,
    required DateTime now,
    required ClassReminderTiming timing,
  }) {
    if (entries.isEmpty) return const [];

    final parsed = _parse(entries, now);
    final plans = <ClassNotificationPlan>[];

    for (final (entry, start, _) in parsed) {
      if (!start.isAfter(now)) continue;

      final leadAt = start.subtract(Duration(minutes: timing.minutes));
      if (leadAt.isAfter(now)) {
        plans.add(_plan(entry, _reminderTypeFor(timing), leadAt,
            priority: NotificationPriority.normal));
      }

      if (timing != ClassReminderTiming.minutes5) {
        final fiveAt = start.subtract(const Duration(minutes: 5));
        if (fiveAt.isAfter(now)) {
          plans.add(_plan(entry, NotificationType.classReminder5Min, fiveAt,
              priority: NotificationPriority.normal));
        }
      }
    }

    return plans;
  }

  // ─────────────────────────────────────────────────────────────

  /// Exactly ONE day-level fact per day (heavy > light > early > gap).
  List<ClassNotificationPlan> _dayFacts(
    List<(TimetableEntry, DateTime, DateTime)> parsed,
  ) {
    final count = parsed.length;
    final dateKey = _dateKey(parsed.first.$1, parsed.first.$2);

    if (count >= 5) {
      return [
        ClassNotificationPlan(
          event: NotificationEvent(
            type: NotificationType.heavyClassDay,
            metadata: {'classCount': count},
          ),
          date: dateKey,
          priority: NotificationPriority.low,
        ),
      ];
    }
    if (count <= 3) {
      return [
        ClassNotificationPlan(
          event: NotificationEvent(
            type: NotificationType.lightClassDay,
            metadata: {'classCount': count},
          ),
          date: dateKey,
          priority: NotificationPriority.low,
        ),
      ];
    }

    final first = parsed.reduce((a, b) => a.$2.isBefore(b.$2) ? a : b);
    if (first.$2.hour < 9) {
      return [
        ClassNotificationPlan(
          event: NotificationEvent(
            type: NotificationType.earlyClass,
            subjectName: first.$1.subjectName,
            metadata: {'time': _formatClock(first.$2)},
          ),
          date: dateKey,
          priority: NotificationPriority.low,
        ),
      ];
    }

    if (parsed.length > 1) {
      var maxGap = Duration.zero;
      for (var i = 1; i < parsed.length; i++) {
        final gap = parsed[i].$2.difference(parsed[i - 1].$3);
        if (gap > maxGap) maxGap = gap;
      }
      if (maxGap.inMinutes >= 180) {
        return [
          ClassNotificationPlan(
            event: NotificationEvent(
              type: NotificationType.longClassGap,
              metadata: {'duration': _formatDuration(maxGap)},
            ),
            date: dateKey,
            priority: NotificationPriority.low,
          ),
        ];
      }
    }

    return const [];
  }

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

  static bool _isMarked(TimetableEntry entry) {
    final marked = entry.attendanceMarked;
    return marked != null && marked.isNotEmpty && marked != '0';
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

  static String _formatClock(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $period';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
