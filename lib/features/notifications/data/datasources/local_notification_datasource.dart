import '../../../../core/notifications/notification_constants.dart';
import '../../../../core/notifications/notification_models.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../domain/entities/notification_message.dart';
import '../../domain/enums/notification_priority.dart';

/// Port for delivering notifications to the platform.
///
/// The Android implementation reuses the existing [NotificationService]
/// (single flutter_local_notifications plugin instance) — nothing is
/// duplicated.
abstract class LocalNotificationDatasource {
  Future<bool> requestPermissions();

  /// Show a notification immediately.
  Future<void> showImmediate({
    required int id,
    required NotificationMessage message,
    required NotificationPriority priority,
  });

  /// Schedule a notification for an exact future instant.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required NotificationMessage message,
    required NotificationPriority priority,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

class AndroidLocalNotificationDatasource implements LocalNotificationDatasource {
  final NotificationService _service;

  AndroidLocalNotificationDatasource(this._service);

  @override
  Future<bool> requestPermissions() async {
    final granted = await _service.requestPermission();
    await _service.requestExactAlarmsPermission();
    return granted;
  }

  @override
  Future<void> showImmediate({
    required int id,
    required NotificationMessage message,
    required NotificationPriority priority,
  }) async {
    await _service.show(
      id: id,
      channelId: _channelFor(priority),
      content: NotificationContent(title: message.title, body: message.body),
    );
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required NotificationMessage message,
    required NotificationPriority priority,
  }) async {
    await _service.schedule(
      id: id,
      when: when,
      channelId: _channelFor(priority),
      content: NotificationContent(title: message.title, body: message.body),
    );
  }

  @override
  Future<void> cancel(int id) => _service.cancel(id);

  @override
  Future<void> cancelAll() => _service.cancelAll();

  /// Priority → channel mapping (channel importance reflects priority).
  static String _channelFor(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.critical:
      case NotificationPriority.high:
        return NotificationChannels.attendanceAlerts.id;
      case NotificationPriority.normal:
        return NotificationChannels.reminders.id;
      case NotificationPriority.low:
        return NotificationChannels.summaries.id;
    }
  }
}

/// No-op datasource used when notifications are unavailable (e.g. init
/// failed); keeps the pipeline safe without null checks everywhere.
class NoopNotificationDatasource implements LocalNotificationDatasource {
  const NoopNotificationDatasource();

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> showImmediate({
    required int id,
    required NotificationMessage message,
    required NotificationPriority priority,
  }) async {}

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required NotificationMessage message,
    required NotificationPriority priority,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}
