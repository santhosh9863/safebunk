import '../../../core/calculations/attendance_engine.dart';
import '../../../core/calculations/attendance_utils.dart';
import '../../../models/api/timetable_model.dart';
import '../../../services/api/pulse_backend_service.dart';
import '../data/datasources/local_notification_datasource.dart';
import '../data/models/notification_preferences_model.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../domain/entities/notification_event.dart';
import '../domain/enums/notification_priority.dart';
import '../domain/enums/notification_type.dart';
import '../domain/services/notification_content_service.dart';
import '../domain/services/notification_rule_engine.dart';
import 'notification_scheduler.dart';

/// Orchestrates the notification pipeline:
///
///   state → rule engine → event → content service → datasource
///
/// with deduplication handled through deterministic ids derived from
/// (student, date, class, reminderType). Never called from UI widgets —
/// the application layer (NotificationObserver) drives it.
class NotificationManager {
  final NotificationRuleEngine _engine;
  final NotificationContentService _contentService;
  final ClassReminderScheduler _scheduler;
  final LocalNotificationDatasource _datasource;
  final NotificationRepositoryImpl _repository;
  final PulseBackendService? _backend;

  NotificationManager({
    required NotificationRuleEngine engine,
    required NotificationContentService contentService,
    required ClassReminderScheduler scheduler,
    required LocalNotificationDatasource datasource,
    required NotificationRepositoryImpl repository,
    PulseBackendService? backend,
  })  : _engine = engine,
        _contentService = contentService,
        _scheduler = scheduler,
        _datasource = datasource,
        _repository = repository,
        _backend = backend;

  // ── Attendance ──────────────────────────────────────────────

  Future<void> evaluateAttendance({
    required int present,
    required int total,
    required String studentId,
    required DateTime now,
    required NotificationPreferences settings,
    required double target,
    required double dangerThreshold,
  }) async {
    final percentage = _overallPercentage(present, total);
    final safeBunks = AttendanceEngine.calculateSafeBunks(present, total);
    final previous = _repository.getLastProcessedPercentage();

    if (previous == null) {
      // First sync after login: store the baseline silently.
      await _repository.setLastProcessedPercentage(percentage);
      await _repository.setLastSafeBunks(safeBunks);
      return;
    }

    final events = <NotificationEvent>[
      ..._engine.evaluateAttendance(
        currentPercentage: percentage,
        previousPercentage: previous,
        target: target,
        dangerThreshold: dangerThreshold,
      ),
      if (settings.milestonesEnabled)
        ..._engine.evaluateMilestones(
          currentPercentage: percentage,
          previousPercentage: previous,
        ),
    ];

    // A milestone already celebrates the climb — drop the generic
    // "improved" event so the user gets one message, not two.
    final hasMilestone = events.any((e) => _isMilestone(e.type));
    final finalEvents = hasMilestone
        ? events.where((e) => e.type != NotificationType.attendanceImproved).toList()
        : events;

    for (final event in finalEvents) {
      final enabled = settings.masterEnabled && settings.attendanceEnabled;
      if (!enabled) continue;
      await _deliver(
        event,
        studentId: studentId,
        now: now,
        idPrefix: 'att',
        priority: _priorityFor(event.type),
        roasting: settings.roastingEnabled,
        gender: settings.gender,
      );
    }

    await _repository.setLastProcessedPercentage(percentage);
    await _repository.setLastSafeBunks(safeBunks);
  }

  // ── Bunks ───────────────────────────────────────────────────

  Future<void> evaluateBunks({
    required int safeBunks,
    required int present,
    required int total,
    required String studentId,
    required DateTime now,
    required NotificationPreferences settings,
    required double target,
    required double dangerThreshold,
  }) async {
    final previous = _repository.getLastSafeBunks();
    if (previous == null) {
      await _repository.setLastSafeBunks(safeBunks);
      return;
    }

    final events = _engine.evaluateBunks(
      safeBunks: safeBunks,
      previousSafeBunks: previous,
      present: present,
      total: total,
      target: target,
      dangerThreshold: dangerThreshold,
    );

    for (final event in events) {
      if (!settings.masterEnabled || !settings.bunkEnabled) continue;
      await _deliver(
        event,
        studentId: studentId,
        now: now,
        idPrefix: 'bunk',
        priority: _priorityFor(event.type),
        roasting: settings.roastingEnabled,
        gender: settings.gender,
      );
    }

    await _repository.setLastSafeBunks(safeBunks);
  }

  // ── Timetable / class reminders ─────────────────────────────

  /// Called when the timetable SOURCE changes (new fetch).
  ///
  /// Weekdays: pre-schedules the day's signature moments (first class,
  /// post-lunch, last class, wrap-up) — unless the PULSE backend is
  /// reachable, in which case the backend owns delivery and the app stays
  /// silent to avoid doubles.
  /// Saturdays: nothing. Sundays: exactly one chill message at 10:00.
  Future<void> syncTimetable({
    required List<TimetableEntry> entries,
    required String studentId,
    required DateTime now,
    required NotificationPreferences settings,
  }) async {
    final tracked = await _repository.getScheduledReminderIds();

    final isSaturday = now.weekday == DateTime.saturday;
    final isSunday = now.weekday == DateTime.sunday;
    final backendOwns = await _backendOwnsDelivery();

    if (!settings.masterEnabled ||
        !settings.classRemindersEnabled ||
        isSaturday ||
        isSunday ||
        backendOwns) {
      for (final id in tracked) {
        await _datasource.cancel(_stableHash(id));
      }
      await _repository.setScheduledReminderIds(const []);
      if (isSunday && settings.classRemindersEnabled) {
        await _scheduleSundayChill(studentId, now, settings);
      }
      return;
    }

    final plans = _scheduler.planFutureReminders(
      entries: entries,
      now: now,
      timing: settings.reminderTiming,
    );
    final desiredIds = <String>{
      for (final plan in plans) _classId(plan, studentId),
    };

    // Cancel reminders that are no longer in the (updated) timetable.
    for (final oldId in tracked) {
      if (!desiredIds.contains(oldId)) {
        await _datasource.cancel(_stableHash(oldId));
      }
    }

    // Schedule new ones.
    for (final plan in plans) {
      final id = _classId(plan, studentId);
      if (tracked.contains(id)) continue; // already pending
      final message = _contentService.build(plan.event,
          roasting: settings.roastingEnabled, gender: settings.gender);
      await _datasource.scheduleAt(
        id: _stableHash(id),
        when: plan.deliverAt!,
        message: message,
        priority: plan.priority,
      );
    }

    await _repository.setScheduledReminderIds(desiredIds.toList());
  }

  /// Called periodically (and after timetable changes) to deliver events
  /// that are due right now. Signature moments are pre-scheduled, so on
  /// weekdays there is nothing extra here; weekends stay silent.
  Future<void> checkDueNow({
    required List<TimetableEntry> entries,
    required String studentId,
    required DateTime now,
    required NotificationPreferences settings,
  }) async {
    if (!settings.masterEnabled || !settings.classRemindersEnabled) return;
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return;

    final plans = _scheduler.planDueNow(
      entries: entries,
      now: now,
      timing: settings.reminderTiming,
    );

    for (final plan in plans) {
      final id = _classId(plan, studentId);
      if (_repository.isDelivered(id)) continue;
      final message = _contentService.build(plan.event,
          roasting: settings.roastingEnabled, gender: settings.gender);
      await _datasource.showImmediate(
        id: _stableHash(id),
        message: message,
        priority: plan.priority,
      );
      await _repository.markDelivered(id);
    }
  }

  Future<void> cancelAllScheduled() async {
    final tracked = await _repository.getScheduledReminderIds();
    for (final id in tracked) {
      await _datasource.cancel(_stableHash(id));
    }
    await _repository.setScheduledReminderIds(const []);
  }

  // ── Internals ───────────────────────────────────────────────

  /// True when the PULSE backend is configured AND reachable — in that case
  /// the server owns the 3-4 daily messages (via FCM) and the app's local
  /// scheduler stays quiet to avoid double notifications.
  Future<bool> _backendOwnsDelivery() async {
    final backend = _backend;
    if (backend == null || !backend.isEnabled) return false;
    return backend.isReachable();
  }

  /// The single Sunday message: scheduled at 10:00 local, deduped per week.
  Future<void> _scheduleSundayChill(
    String studentId,
    DateTime now,
    NotificationPreferences settings,
  ) async {
    final id = 'sunday_${studentId}_${_weekKey(now)}';
    if (_repository.isDelivered(id)) return;

    var fireAt = DateTime(now.year, now.month, now.day, 10);
    if (!fireAt.isAfter(now)) {
      fireAt = now.add(const Duration(minutes: 1));
    }

    final message = _contentService.build(
      NotificationEvent(type: NotificationType.sundayChill),
      roasting: settings.roastingEnabled,
      gender: settings.gender,
    );
    await _datasource.scheduleAt(
      id: _stableHash(id),
      when: fireAt,
      message: message,
      priority: NotificationPriority.normal,
    );
    await _repository.markDelivered(id);
  }

  /// Monday-based ISO week key (yyyy-MM-dd of Monday).
  static String _weekKey(DateTime date) {
    final day = date.weekday; // 1 = Monday .. 7 = Sunday
    final monday = date.subtract(Duration(days: day - 1));
    return _dateKey(monday);
  }

  Future<void> _deliver(
    NotificationEvent event, {
    required String studentId,
    required DateTime now,
    required String idPrefix,
    required NotificationPriority priority,
    required bool roasting,
    String gender = '',
  }) async {
    final id = '$idPrefix${studentId}_${_dateKey(now)}_${event.type.name}';
    if (_repository.isDelivered(id)) return;

    final message =
        _contentService.build(event, roasting: roasting, gender: gender);
    await _datasource.showImmediate(
      id: _stableHash(id),
      message: message,
      priority: priority,
    );
    await _repository.markDelivered(id);
  }

  String _classId(ClassNotificationPlan plan, String studentId) {
    final date = plan.date ?? _dateKey(DateTime.now());
    final classPart = plan.classId ?? '';
    return 'cls${studentId}_${date}_${classPart}_${plan.event.type.name}';
  }

  static bool _isMilestone(NotificationType type) {
    switch (type) {
      case NotificationType.reached75:
      case NotificationType.reached80:
      case NotificationType.reached90:
      case NotificationType.reached95:
      case NotificationType.reached100:
        return true;
      default:
        return false;
    }
  }

  static NotificationPriority _priorityFor(NotificationType type) {
    switch (type) {
      case NotificationType.enteredDangerZone:
      case NotificationType.bunkWouldCauseDanger:
        return NotificationPriority.critical;
      case NotificationType.attendanceDropped:
      case NotificationType.enteredWarningZone:
      case NotificationType.leftSafeZone:
      case NotificationType.noSafeBunks:
      case NotificationType.bunkWouldCrossSafeThreshold:
      case NotificationType.classStarting:
      case NotificationType.classMissed:
        return NotificationPriority.high;
      case NotificationType.attendanceImproved:
      case NotificationType.enteredSafeZone:
      case NotificationType.recoveredFromDanger:
      case NotificationType.perfectAttendance:
      case NotificationType.safeToBunk:
      case NotificationType.lastSafeBunk:
      case NotificationType.classReminder30Min:
      case NotificationType.classReminder10Min:
      case NotificationType.classReminder5Min:
      case NotificationType.nextClass:
      case NotificationType.dayWrapUp:
      case NotificationType.sundayChill:
      case NotificationType.syncSuccess:
        return NotificationPriority.normal;
      case NotificationType.reached75:
      case NotificationType.reached80:
      case NotificationType.reached90:
      case NotificationType.reached95:
      case NotificationType.reached100:
      case NotificationType.heavyClassDay:
      case NotificationType.lightClassDay:
      case NotificationType.earlyClass:
      case NotificationType.longClassGap:
      case NotificationType.noClasses:
      case NotificationType.syncFailure:
      case NotificationType.offline:
      case NotificationType.timetableUpdated:
        return NotificationPriority.low;
    }
  }

  static double _overallPercentage(int present, int total) {
    if (total <= 0) return 0.0;
    return AttendanceUtils.roundPercentage(
      AttendanceUtils.clampPercentage(
        AttendanceUtils.safeDivide(present.toDouble(), total.toDouble()) * 100,
      ),
    );
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// FNV-1a 32-bit hash — stable across runs (unlike String.hashCode) so
  /// notification ids remain deterministic for the same dedupe id.
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
