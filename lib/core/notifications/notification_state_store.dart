import 'package:hive_flutter/hive_flutter.dart';

import 'notification_constants.dart';

class NotificationStateStore {
  static const _boxName = 'notification_state';

  Box<String>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
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
}
