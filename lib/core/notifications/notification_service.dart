import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_models.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  void Function(String? payload)? onNotificationTap;

  NotificationService(this._plugin);

  static const _alertsChannelId = 'attendance_alerts';
  static const _remindersChannelId = 'reminders';
  static const _summariesChannelId = 'summaries';

  static Future<NotificationService> create() async {
    final plugin = FlutterLocalNotificationsPlugin();
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    final service = NotificationService(plugin);

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        service.onNotificationTap?.call(response.payload);
      },
    );

    await service._createChannels();
    return service;
  }

  Future<void> _createChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertsChannelId,
        'Attendance Alerts',
        description: 'Notifications about attendance threshold changes.',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _remindersChannelId,
        'Reminders',
        description: 'Gentle reminders to check your attendance.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _summariesChannelId,
        'Summaries',
        description: 'Weekly attendance summary notifications.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  Future<bool> requestPermission() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    try {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('[Notifications] Permission request failed: $e');
      return false;
    }
  }

  Future<void> show({
    required int id,
    required String channelId,
    required NotificationContent content,
  }) async {
    final importance = channelId == _alertsChannelId
        ? Importance.defaultImportance
        : Importance.low;

    final priority = channelId == _alertsChannelId
        ? Priority.defaultPriority
        : Priority.low;

    final playSound = channelId == _alertsChannelId;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      channelDescription: _channelDescription(channelId),
      importance: importance,
      priority: priority,
      playSound: playSound,
      enableVibration: false,
    );

    const iosDetails = DarwinNotificationDetails();

    await _plugin.show(
      id,
      content.title,
      content.body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// Schedule a notification for an exact future instant.
  ///
  /// The delivery time is converted to a TZDateTime preserving the absolute
  /// instant (the plugin rejects UTC zone datetimes). The 5-minute reminder
  /// and class-start notifications use this so they arrive even when the app
  /// is backgrounded.
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String channelId,
    required NotificationContent content,
  }) async {
    if (!when.isAfter(DateTime.now())) {
      await show(id: id, channelId: channelId, content: content);
      return;
    }

    final tzWhen = tz.TZDateTime.from(when, tz.getLocation('Asia/Kolkata'));

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      channelDescription: _channelDescription(channelId),
      importance: _importanceFor(channelId),
      priority: _priorityFor(channelId),
      playSound: channelId == _alertsChannelId,
      enableVibration: false,
    );

    const iosDetails = DarwinNotificationDetails();

    var scheduled = false;
    try {
      await _plugin.zonedSchedule(
        id,
        content.title,
        content.body,
        tzWhen,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: null,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      scheduled = true;
    } catch (e) {
      debugPrint('[Notifications] Exact schedule failed, retrying inexact: $e');
    }

    if (!scheduled) {
      await _plugin.zonedSchedule(
        id,
        content.title,
        content.body,
        tzWhen,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: null,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> requestExactAlarmsPermission() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    try {
      await androidPlugin.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('[Notifications] Exact alarms permission request failed: $e');
    }
  }

  static Importance _importanceFor(String channelId) {
    if (channelId == _alertsChannelId) return Importance.defaultImportance;
    if (channelId == _summariesChannelId) return Importance.low;
    return Importance.low;
  }

  static Priority _priorityFor(String channelId) {
    if (channelId == _alertsChannelId) return Priority.defaultPriority;
    return Priority.low;
  }

  static String _channelName(String channelId) {
    if (channelId == _alertsChannelId) return 'Attendance Alerts';
    if (channelId == _remindersChannelId) return 'Reminders';
    if (channelId == _summariesChannelId) return 'Summaries';
    return 'Attendance Alerts';
  }

  static String _channelDescription(String channelId) {
    if (channelId == _alertsChannelId) {
      return 'Notifications about attendance threshold changes.';
    }
    if (channelId == _remindersChannelId) {
      return 'Gentle reminders to check your attendance.';
    }
    if (channelId == _summariesChannelId) {
      return 'Weekly attendance summary notifications.';
    }
    return 'Notifications about attendance threshold changes.';
  }
}

