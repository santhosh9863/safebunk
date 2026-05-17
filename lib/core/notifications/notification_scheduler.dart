import 'notification_constants.dart';
import 'notification_rules.dart';
import 'notification_service.dart';
import 'notification_state_store.dart';

class NotificationScheduler {
  final NotificationService _service;
  final NotificationStateStore _store;

  NotificationScheduler({
    required NotificationService service,
    required NotificationStateStore store,
  })  : _service = service,
        _store = store;

  /// Evaluate all notification rules and trigger eligible notifications.
  ///
  /// Must be called after attendance data changes. Respects user settings
  /// via the [settings] parameter.
  Future<void> evaluate({
    required double overallPercentage,
    required int safeBunks,
    required double attendanceTarget,
    required DateTime now,
    required NotificationSettings settings,
  }) async {
    // ── First-run: store baselines silently ──
    if (!settings.notificationsEnabled) return;

    if (!_store.isFirstRunComplete()) {
      await _initBaselines(
        percentage: overallPercentage,
        safeBunks: safeBunks,
        now: now,
      );
      return;
    }

    await _evaluateLowAttendance(
      percentage: overallPercentage,
      target: attendanceTarget,
      enabled: settings.lowAttendanceEnabled,
    );

    await _evaluateSafeLeaves(
      currentBunks: safeBunks,
      enabled: settings.lowAttendanceEnabled,
    );

    await _evaluateDailyReminder(
      now: now,
      enabled: settings.dailyReminderEnabled,
    );

    await _evaluateWeeklySummary(
      percentage: overallPercentage,
      now: now,
      enabled: settings.weeklySummaryEnabled,
    );

    await _store.setLastProcessedPercentage(overallPercentage);
  }

  Future<void> _initBaselines({
    required double percentage,
    required int safeBunks,
    required DateTime now,
  }) async {
    await _store.setFirstRunComplete();
    await _store.setLastProcessedPercentage(percentage);
    await _store.setLastNotifiedSafeBunks(safeBunks);
    await _store.setLastDailyReminderDate(NotificationRules.todayString(now));
    await _store.setLastSummaryMonday(NotificationRules.mondayOfWeek(now));
  }

  Future<void> _evaluateLowAttendance({
    required double percentage,
    required double target,
    required bool enabled,
  }) async {
    if (!enabled) return;

    final lastPct = _store.getLastProcessedPercentage();
    final cooldownUntil = _store.getLowWarningCooldownUntil();
    final cooldownActive = _isCooldownActive(cooldownUntil);

    final result = NotificationRules.evaluateLowAttendance(
      currentPercentage: percentage,
      attendanceTarget: target,
      lastPercentage: lastPct,
      cooldownActive: cooldownActive,
    );

    if (result.shouldNotify) {
      await _service.show(
        id: NotificationIds.lowAttendance,
        channelId: NotificationChannels.attendanceAlerts.id,
        content: NotificationRules.contentForLowAttendance(),
      );
      await _store.setLowWarningActive(true);
      await _store.setLowWarningCooldownUntil(
        DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      );
    }

    if (result.recovered) {
      await _store.setLowWarningActive(false);
      await _store.clearLowWarningCooldown();
    }
  }

  bool _isCooldownActive(String? cooldownUntil) {
    if (cooldownUntil == null || cooldownUntil.isEmpty) return false;
    final cooldownTime = DateTime.tryParse(cooldownUntil);
    if (cooldownTime == null) return false;
    return DateTime.now().isBefore(cooldownTime);
  }

  Future<void> _evaluateSafeLeaves({
    required int currentBunks,
    required bool enabled,
  }) async {
    if (!enabled) return;

    final lastNotified = _store.getLastNotifiedSafeBunks();
    final result = NotificationRules.evaluateSafeLeaves(
      currentSafeBunks: currentBunks,
      lastNotifiedBunks: lastNotified,
    );

    if (result.shouldNotify) {
      final content = NotificationRules.contentForSafeLeaves(currentBunks);
      await _service.show(
        id: NotificationIds.safeLeaveAvailable,
        channelId: NotificationChannels.attendanceAlerts.id,
        content: content,
      );
    }

    await _store.setLastNotifiedSafeBunks(result.newLastNotifiedBunks);
  }

  Future<void> _evaluateDailyReminder({
    required DateTime now,
    required bool enabled,
  }) async {
    if (!enabled) return;

    final today = NotificationRules.todayString(now);
    final lastDate = _store.getLastDailyReminderDate();
    final result = NotificationRules.evaluateDailyReminder(
      todayDate: today,
      lastReminderDate: lastDate,
    );

    if (result.shouldNotify) {
      final content = NotificationRules.contentForDailyReminder();
      await _service.show(
        id: NotificationIds.dailyReminder,
        channelId: NotificationChannels.reminders.id,
        content: content,
      );
    }

    if (result.shouldUpdateDate) {
      await _store.setLastDailyReminderDate(today);
    }
  }

  Future<void> _evaluateWeeklySummary({
    required double percentage,
    required DateTime now,
    required bool enabled,
  }) async {
    if (!enabled) return;

    final currentMonday = NotificationRules.mondayOfWeek(now);
    final lastMonday = _store.getLastSummaryMonday();
    final result = NotificationRules.evaluateWeeklySummary(
      currentMonday: currentMonday,
      lastSummaryMonday: lastMonday,
    );

    if (result.shouldNotify) {
      final content = NotificationRules.contentForWeeklySummary(percentage);
      await _service.show(
        id: NotificationIds.weeklySummary,
        channelId: NotificationChannels.summaries.id,
        content: content,
      );
    }

    if (result.shouldUpdateWeek) {
      await _store.setLastSummaryMonday(currentMonday);
    }
  }
}

class NotificationSettings {
  final bool notificationsEnabled;
  final bool lowAttendanceEnabled;
  final bool dailyReminderEnabled;
  final bool weeklySummaryEnabled;

  const NotificationSettings({
    required this.notificationsEnabled,
    required this.lowAttendanceEnabled,
    required this.dailyReminderEnabled,
    required this.weeklySummaryEnabled,
  });
}
