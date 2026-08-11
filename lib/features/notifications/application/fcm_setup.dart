import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_service.dart';

/// Firebase Cloud Messaging lifecycle for PULSE.
///
/// - Initializes messaging, requests permissions and records the token.
/// - Foreground messages are presented through the existing local
///   [NotificationService] (same channels) so foreground behavior matches
///   background/system behavior.
/// - Background/terminated/recent-apps-killed delivery is handled entirely by
///   Android's FCM runtime — no app process or timers involved.
/// - Token registration with the backend is driven by the auth flow (the
///   backend must be logged in first), via [registerWithBackend].
class FcmController {
  static NotificationService? _service;
  static String? _currentToken;
  static bool _tokenRefreshListenerAttached = false;

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

      // App in foreground: present through the local notification pipeline.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null || _service == null) return;
        _service!.show(
          id: (message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString())
              .hashCode & 0x7fffffff,
          channelId: 'reminders',
          content: NotificationContent(
            title: notification.title ?? 'PULSE',
            body: notification.body ?? '',
          ),
        );
      });

      // Tap on a background/terminated notification: the normal auth flow
      // restores the session and lands on the dashboard, so no extra
      // navigation is required here.
      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        debugPrint('[FCM] notification opened from background/terminated');
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[FCM] launched from notification tap');
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
