import '../../../../core/notifications/notification_state_store.dart';

/// Persistence for the notification system.
///
/// Reuses the existing [NotificationStateStore] (same Hive box) — no second
/// storage layer. Stores:
///  - baseline values for deduplication (last processed percentage, safe bunks)
///  - sent-marker ids so an event is delivered at most once
///  - the ids of scheduled class reminders (for cancel + reschedule on
///    timetable changes)
class NotificationRepositoryImpl {
  final NotificationStateStore _store;

  NotificationRepositoryImpl(this._store);

  // ── Baselines ──

  double? getLastProcessedPercentage() => _store.getLastProcessedPercentage();

  Future<void> setLastProcessedPercentage(double value) =>
      _store.setLastProcessedPercentage(value);

  int? getLastSafeBunks() => _store.getLastSafeBunksOrNull();

  Future<void> setLastSafeBunks(int value) => _store.setLastNotifiedSafeBunks(value);

  // ── Dedup markers ──

  bool isDelivered(String dedupeId) => _store.hasSent(dedupeId);

  Future<void> markDelivered(String dedupeId) => _store.markSent(dedupeId);

  // ── Scheduled reminder tracking ──

  Future<List<String>> getScheduledReminderIds() => _store.getScheduledReminderIds();

  Future<void> setScheduledReminderIds(List<String> ids) =>
      _store.setScheduledReminderIds(ids);
}
