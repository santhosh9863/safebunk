import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics? _analytics;
  static bool _appOpenFired = false;

  static FirebaseAnalytics get _instance {
    _analytics ??= FirebaseAnalytics.instance;
    return _analytics!;
  }

  static final Map<String, DateTime> _lastFired = {};

  static bool _debounce(String key, Duration duration) {
    final now = DateTime.now();
    final last = _lastFired[key];
    if (last != null && now.difference(last) < duration) return false;
    _lastFired[key] = now;
    return true;
  }

  static Future<void> logAppOpen() async {
    if (_appOpenFired) return;
    _appOpenFired = true;
    try {
      await _instance.logAppOpen();
    } catch (e) {
      debugPrint('[Analytics] logAppOpen failed: $e');
    }
  }

  static Future<void> logLoginSuccess() async {
    if (!_debounce('login_success', const Duration(seconds: 60))) return;
    try {
      await _instance.logEvent(name: 'login_success');
    } catch (e) {
      debugPrint('[Analytics] login_success failed: $e');
    }
  }

  static Future<void> logAttendanceSync() async {
    if (!_debounce('attendance_sync', const Duration(seconds: 30))) return;
    try {
      await _instance.logEvent(name: 'attendance_sync');
    } catch (e) {
      debugPrint('[Analytics] attendance_sync failed: $e');
    }
  }

  static Future<void> logDashboardOpen() async {
    if (!_debounce('dashboard_open', const Duration(seconds: 10))) return;
    try {
      await _instance.logEvent(name: 'dashboard_open');
    } catch (e) {
      debugPrint('[Analytics] dashboard_open failed: $e');
    }
  }
}
