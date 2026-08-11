import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Client for the PULSE NestJS backend (device registration, preferences,
/// FCM-backed events).
///
/// The backend base URL is injected at build time:
///   flutter run --dart-define=PULSE_BACKEND_URL=https://your-backend:3000
///
/// When no URL is configured every call is a no-op and the app keeps working
/// exactly as before (local notifications only). Never throws for that case.
class PulseBackendService {
  static const _baseUrl = String.fromEnvironment('PULSE_BACKEND_URL');

  static const _tokenKey = 'backend_access_token';
  static const _studentIdKey = 'backend_student_id';

  final Dio _dio;
  final FlutterSecureStorage _storage;
  final bool _enabled;

  PulseBackendService({Dio? dio, FlutterSecureStorage? storage})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json'},
            )),
        _storage = storage ?? const FlutterSecureStorage(),
        _enabled = _baseUrl.isNotEmpty;

  bool get isEnabled => _enabled;

  Future<bool> get isLoggedIn async {
    if (!_enabled) return false;
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Authenticate against the backend so it has a live Linways session for
  /// the watchers, and remember the token for device registration.
  Future<bool> login(String username, String password) async {
    if (!_enabled) return false;
    try {
      final response = await _dio.post('/api/auth/login', data: {
        'username': username,
        'password': password,
      });
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) {
          final token = data['accessToken']?.toString();
          final studentId = (data['student'] as Map?)?['studentId']?.toString();
          if (token != null && token.isNotEmpty) {
            await _storage.write(key: _tokenKey, value: token);
            if (studentId != null) {
              await _storage.write(key: _studentIdKey, value: studentId);
            }
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[PULSE backend] login skipped: $e');
    }
    return false;
  }

  Future<void> logout() async {
    if (!_enabled) return;
    final token = await _storage.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) {
      try {
        await _dio.post(
          '/api/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } catch (_) {
        // Best-effort: the backend session will expire on its own.
      }
    }
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _studentIdKey);
  }

  Future<bool> registerDevice(String fcmToken) async {
    final token = await _storage.read(key: _tokenKey);
    if (!_enabled || token == null || token.isEmpty) return false;
    try {
      await _dio.post(
        '/api/notifications/register-device',
        data: {'fcmToken': fcmToken, 'platform': 'android'},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } catch (e) {
      debugPrint('[PULSE backend] register-device failed: $e');
      return false;
    }
  }

  Future<void> unregisterDevice(String fcmToken) async {
    final token = await _storage.read(key: _tokenKey);
    if (!_enabled || token == null || token.isEmpty) return;
    try {
      await _dio.post(
        '/api/notifications/unregister-device',
        data: {'fcmToken': fcmToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Mirror the current notification preferences to the backend so server
  /// delivery respects the user's switches (roasting mode included).
  Future<void> updatePreferences({
    required bool masterEnabled,
    required bool attendanceEnabled,
    required bool classRemindersEnabled,
    required bool milestonesEnabled,
    required bool roastingEnabled,
    required int reminderTimingMinutes,
  }) async {
    final token = await _storage.read(key: _tokenKey);
    if (!_enabled || token == null || token.isEmpty) return;
    try {
      await _dio.put(
        '/api/notifications/preferences',
        data: {
          'masterEnabled': masterEnabled,
          'attendanceEnabled': attendanceEnabled,
          'bunkEnabled': true,
          'classRemindersEnabled': classRemindersEnabled,
          'milestonesEnabled': milestonesEnabled,
          'roastingEnabled': roastingEnabled,
          'reminderTiming': '$reminderTimingMinutes',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Best-effort.
    }
  }
}
