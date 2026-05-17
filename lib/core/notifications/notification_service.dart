import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_models.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService(this._plugin);

  static const _alertsChannelId = 'attendance_alerts';
  static const _remindersChannelId = 'reminders';
  static const _summariesChannelId = 'summaries';

  static Future<NotificationService> create() async {
    final plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await plugin.initialize(initSettings);

    final service = NotificationService(plugin);
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

