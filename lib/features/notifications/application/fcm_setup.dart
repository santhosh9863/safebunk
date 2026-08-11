import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_service.dart';

/// Maps a server event type to the Android notification channel that must be
/// used for local presentation. Mirrors the backend `channelIdFor()` — urgent
/// events (danger zone, missed class) go to the alert channel, everything
/// else to reminders.
String channelIdForFcmType(String? type) {
  switch (type) {
    case 'enteredDangerZone':
    case 'classMissed':
      return 'attendance_alerts';
    default:
      return 'reminders';
  }
}

/// Firebase Cloud Messaging lifecycle for PULSE.
///
/// - Initializes messaging, requests permissions and records the token.
/// - Foreground messages are presented through the existing local
///   [NotificationService] (same channels) so foreground behavior matches
///   background/system behavior. The server's data payload (`type`,
///   `eventId`) picks the right channel and a stable notification id.
/// - Background/terminated/recent-apps-killed delivery is handled entirely by
///   Android's FCM runtime — no app process or timers involved. Taps are
///   forwarded to [onMessageOpened] so the app can navigate.
/// - Token registration with the backend is driven by the auth flow (the
///   backend must be logged in first), via [registerWithBackend].
class FcmController {
  static NotificationService? _service;
  static String? _currentToken;
  static bool _tokenRefreshListenerAttached = false;

  /// Invoked when the user taps a notification that was delivered while the
  /// app was in the background/terminated (or the app was cold-started from
  /// a notification tap).
  static void Function(String? type, String? eventId)? onMessageOpened;

  /// Called once from main() after Firebase + NotificationService init.
  static Future<void> initialize(NotificationService? service) async {
    _service = service;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _currentToken = await messaging.getToken();
      if (_currentToken != null) {
        debugPrint('[FCM] token obtained (${_currentToken!.length} chars)');
      }

      // App in foreground: present through the local notification pipeline,
      // using the server's data payload for channel + stable id.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null || _service == null) return;
        final data = message.data;
        final type = data['type'];
        final eventId = data['eventId'];
        final id = (eventId ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString())
            .hashCode & 0x7fffffff;
        _service!.show(
          id: id,
          channelId: channelIdForFcmType(type),
          content: NotificationContent(
            title: notification.title ?? 'PULSE',
            body: notification.body ?? '',
          ),
        );
      });

      // Tap on a background/terminated notification: forward the event so the
      // app can navigate. The normal auth flow restores the session and lands
      // on the dashboard regardless.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('[FCM] notification opened from background/terminated');
        onMessageOpened?.call(message.data['type'], message.data['eventId']);
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[FCM] launched from notification tap');
        onMessageOpened?.call(initial.data['type'], initial.data['eventId']);
      }
    } catch (e) {
      debugPrint('[FCM] initialization failed (non-fatal): $e');
    }
  }

  static String? get currentToken => _currentToken;

  /// Re-read the token (e.g. after backend login succeeded).
  static Future<String?> refreshToken() async {
    try {
      _currentToken = await FirebaseMessaging.instance.getToken();
      return _currentToken;
    } catch (e) {
      debugPrint('[FCM] token refresh failed: $e');
      return null;
    }
  }

  /// Register the current device token with the PULSE backend. Safe to call
  /// repeatedly — the backend upserts by token.
  static Future<bool> registerWithBackend(Future<bool> Function(String token) register) async {
    final token = await refreshToken();
    if (token == null) return false;
    return register(token);
  }

  /// Attach a one-time token-refresh listener that re-registers the new
  /// token while a session is active (token rotation).
  static void attachTokenRefreshListener(
    Future<void> Function(String newToken) onRotated,
  ) {
    if (_tokenRefreshListenerAttached) return;
    _tokenRefreshListenerAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _currentToken = newToken;
      debugPrint('[FCM] token rotated; re-registering');
      onRotated(newToken);
    });
  }
}
