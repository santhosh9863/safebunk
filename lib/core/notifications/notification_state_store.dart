import 'package:hive_flutter/hive_flutter.dart';

import 'notification_constants.dart';

class NotificationStateStore {
  static const _boxName = 'notification_state';
  static const _sentBoxName = 'notification_sent';

  Box<String>? _box;
  Box<String>? _sentBox;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _sentBox = await Hive.openBox<String>(_sentBoxName);
  }

  // ── First Run ──

  Future<void> setFirstRunComplete() async {
    await _box?.put(NotificationStoreKeys.firstRunComplete, '1');
  }

  bool isFirstRunComplete() {
    return _box?.get(NotificationStoreKeys.firstRunComplete) == '1';
  }

  // ── Last Processed Percentage ──

  Future<void> setLastProcessedPercentage(double value) async {
    await _box?.put(NotificationStoreKeys.lastProcessedPercentage, value.toStringAsFixed(2));
  }

  double? getLastProcessedPercentage() {
    final raw = _box?.get(NotificationStoreKeys.lastProcessedPercentage);
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  // ── Low Attendance Warning ──

  Future<void> setLowWarningActive(bool active) async {
    await _box?.put(NotificationStoreKeys.lowWarningActive, active ? '1' : '0');
  }

  bool getLowWarningActive() {
    return _box?.get(NotificationStoreKeys.lowWarningActive) == '1';
  }

  Future<void> setLowWarningCooldownUntil(String isoDate) async {
    await _box?.put(NotificationStoreKeys.lowWarningCooldownUntil, isoDate);
  }

  String? getLowWarningCooldownUntil() {
    return _box?.get(NotificationStoreKeys.lowWarningCooldownUntil);
  }

  Future<void> clearLowWarningCooldown() async {
    await _box?.delete(NotificationStoreKeys.lowWarningCooldownUntil);
  }

  // ── Safe Leave Availability ──

  Future<void> setLastNotifiedSafeBunks(int count) async {
    await _box?.put(NotificationStoreKeys.lastSafeBunks, count.toString());
  }

  int getLastNotifiedSafeBunks() {
    final raw = _box?.get(NotificationStoreKeys.lastSafeBunks);
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  // ── Daily Reminder ──

  Future<void> setLastDailyReminderDate(String date) async {
    await _box?.put(NotificationStoreKeys.lastDailyReminder, date);
  }

  String? getLastDailyReminderDate() {
    return _box?.get(NotificationStoreKeys.lastDailyReminder);
  }

  // ── Weekly Summary ──

  Future<void> setLastSummaryMonday(String monday) async {
    await _box?.put(NotificationStoreKeys.lastSummaryMonday, monday);
  }

  String? getLastSummaryMonday() {
    return _box?.get(NotificationStoreKeys.lastSummaryMonday);
  }

  // ── Toggle Persistence ──

  Future<void> setToggleAttendanceAlerts(bool value) async {
    await _box?.put('toggle_attendance_alerts', value ? '1' : '0');
  }

  bool getToggleAttendanceAlerts() {
    final val = _box?.get('toggle_attendance_alerts');
    return val == null ? true : val == '1';
  }

  Future<void> setToggleLowAttendanceWarning(bool value) async {
    await _box?.put('toggle_low_warning', value ? '1' : '0');
  }

  bool getToggleLowAttendanceWarning() {
    final val = _box?.get('toggle_low_warning');
    return val == null ? true : val == '1';
  }

  Future<void> setToggleDailyReminder(bool value) async {
    await _box?.put('toggle_daily_reminder', value ? '1' : '0');
  }

  bool getToggleDailyReminder() {
    final val = _box?.get('toggle_daily_reminder');
    return val == null ? true : val == '1';
  }

  Future<void> setToggleWeeklySummary(bool value) async {
    await _box?.put('toggle_weekly_summary', value ? '1' : '0');
  }

  bool getToggleWeeklySummary() {
    final val = _box?.get('toggle_weekly_summary');
    return val == null ? true : val == '1';
  }

  // ── Safe Leave Milestone ──

  Future<void> setLastSafeLeaveMilestone(int milestone) async {
    await _box?.put('last_safe_leave_milestone', milestone.toString());
  }

  int getLastSafeLeaveMilestone() {
    final raw = _box?.get('last_safe_leave_milestone');
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  // ── Logout Cleanup ──

  Future<void> clearOperationalState() async {
    await _box?.delete(NotificationStoreKeys.firstRunComplete);
    await _box?.delete(NotificationStoreKeys.lastProcessedPercentage);
    await _box?.delete(NotificationStoreKeys.lowWarningActive);
    await _box?.delete(NotificationStoreKeys.lowWarningCooldownUntil);
    await _box?.delete(NotificationStoreKeys.lastSafeBunks);
    await _box?.delete(NotificationStoreKeys.lastDailyReminder);
    await _box?.delete(NotificationStoreKeys.lastSummaryMonday);
    await _box?.delete('last_safe_leave_milestone');
    await _box?.delete('toggle_master');
    await _box?.delete('toggle_class_reminders');
    await _box?.delete('toggle_milestones');
    await _box?.delete('toggle_timetable');
    await _box?.delete('toggle_roasting');
    await _box?.delete('reminder_timing');
    await _box?.delete('scheduled_reminder_ids');
    await _sentBox?.clear();
  }

  // ── Nullable safe-bunk read (baseline detection) ──

  int? getLastSafeBunksOrNull() {
    final raw = _box?.get(NotificationStoreKeys.lastSafeBunks);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  // ── Sent-marker dedup (event → deterministic id) ──

  bool hasSent(String dedupeId) {
    return _sentBox?.get(dedupeId) == '1';
  }

  Future<void> markSent(String dedupeId) async {
    await _sentBox?.put(dedupeId, '1');
  }

  // ── Scheduled reminder id tracking (timetable change → cancel + reschedule) ──

  Future<List<String>> getScheduledReminderIds() async {
    final raw = _box?.get('scheduled_reminder_ids');
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  Future<void> setScheduledReminderIds(List<String> ids) async {
    await _box?.put('scheduled_reminder_ids', ids.join(','));
  }

  // ── New preference toggles ──

  Future<void> setMasterEnabled(bool value) async {
    await _box?.put('toggle_master', value ? '1' : '0');
  }

  bool getMasterEnabled() {
    final val = _box?.get('toggle_master');
    return val == null ? true : val == '1';
  }

  Future<void> setClassRemindersEnabled(bool value) async {
    await _box?.put('toggle_class_reminders', value ? '1' : '0');
  }

  bool getClassRemindersEnabled() {
    final val = _box?.get('toggle_class_reminders');
    return val == null ? true : val == '1';
  }

  Future<void> setMilestonesEnabled(bool value) async {
    await _box?.put('toggle_milestones', value ? '1' : '0');
  }

  bool getMilestonesEnabled() {
    final val = _box?.get('toggle_milestones');
    return val == null ? true : val == '1';
  }

  Future<void> setTimetableEnabled(bool value) async {
    await _box?.put('toggle_timetable', value ? '1' : '0');
  }

  bool getTimetableEnabled() {
    final val = _box?.get('toggle_timetable');
    return val == null ? true : val == '1';
  }

  Future<void> setRoastingEnabled(bool value) async {
    await _box?.put('toggle_roasting', value ? '1' : '0');
  }

  bool getRoastingEnabled() {
    final val = _box?.get('toggle_roasting');
    return val == null ? true : val == '1';
  }

  Future<void> setReminderTimingMinutes(int minutes) async {
    await _box?.put('reminder_timing', minutes.toString());
  }

  int getReminderTimingMinutes() {
    final raw = _box?.get('reminder_timing');
    if (raw == null || raw.isEmpty) return 10;
    return int.tryParse(raw) ?? 10;
  }
}
