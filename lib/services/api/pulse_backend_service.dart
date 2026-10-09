import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exceptions.dart';
import '../../features/reports/data/models/report_attachment.dart';
import '../../features/reports/data/models/report_model.dart';

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
  static const _genderKey = 'backend_student_gender';

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
          final gender = (data['student'] as Map?)?['gender']?.toString() ?? '';
          if (token != null && token.isNotEmpty) {
            await _storage.write(key: _tokenKey, value: token);
            if (studentId != null) {
              await _storage.write(key: _studentIdKey, value: studentId);
            }
            if (gender.isNotEmpty) {
              await _storage.write(key: _genderKey, value: gender);
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
    required bool bunkEnabled,
    required bool classRemindersEnabled,
    required bool milestonesEnabled,
    required bool timetableEnabled,
    required bool roastingEnabled,
    required int reminderTimingMinutes,
    String gender = '',
    bool wrapUpEnabled = true,
  }) async {
    final token = await _storage.read(key: _tokenKey);
    if (!_enabled || token == null || token.isEmpty) return;
    try {
      await _dio.put(
        '/api/notifications/preferences',
        data: {
          'masterEnabled': masterEnabled,
          'attendanceEnabled': attendanceEnabled,
          'bunkEnabled': bunkEnabled,
          'classRemindersEnabled': classRemindersEnabled,
          'milestonesEnabled': milestonesEnabled,
          'timetableEnabled': timetableEnabled,
          'roastingEnabled': roastingEnabled,
          'reminderTiming': '$reminderTimingMinutes',
          if (gender.isNotEmpty) 'gender': gender,
          'wrapUpEnabled': wrapUpEnabled,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Gender detected from Linways at the last backend login ('' if unknown).
  Future<String> getDetectedGender() async {
    if (!_enabled) return '';
    return (await _storage.read(key: _genderKey)) ?? '';
  }

  /// Quick reachability probe — true when the backend answers. Used by the
  /// app to decide whether the server owns the daily messages (FCM) or the
  /// local scheduler must step in as fallback.
  Future<bool> isReachable() async {
    if (!_enabled) return false;
    try {
      final response = await _dio.get<dynamic>(
        '/',
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (_) => true,
        ),
      );
      return response.statusCode != null && response.statusCode! < 500;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Reports (PULSE backend, AuthGuard-protected)
  //
  // Ownership is enforced server-side from the Bearer session; the client never
  // sends a studentId. These methods reuse the same secure-stored backend token
  // and Dio instance as the notification methods above.
  // ---------------------------------------------------------------------------

  /// `GET /api/reports/my` — the authenticated student's reports (newest first).
  Future<List<ReportModel>> fetchMyReports() {
    return _authed<List<ReportModel>>((token) async {
      final response = await _dio.get<dynamic>(
        '/api/reports/my',
        options: _authOptions(token),
      );
      final data = _unwrap(response.data);
      if (data is! List) {
        throw const BadResponseException('Unexpected reports response');
      }
      return data
          .whereType<Map>()
          .map((e) => ReportModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    });
  }

  /// `GET /api/reports/:id` — a single report owned by the authenticated student.
  /// A report owned by another student returns HTTP 404 (no existence oracle).
  Future<ReportModel> fetchReport(String id) {
    return _authed<ReportModel>((token) async {
      final response = await _dio.get<dynamic>(
        '/api/reports/$id',
        options: _authOptions(token),
      );
      final data = _unwrap(response.data);
      if (data is! Map) {
        throw const BadResponseException('Unexpected report response');
      }
      return ReportModel.fromJson(Map<String, dynamic>.from(data));
    });
  }

  /// `POST /api/reports` — create a report for the authenticated student.
  /// The body deliberately omits studentId (rejected by the backend whitelist).
  /// A photo is referenced by [attachmentId], never by a client-supplied URL.
  Future<ReportModel> createReport({
    required String title,
    required String description,
    String? category,
    String? location,
    String? priority,
    String? attachmentId,
  }) {
    return _authed<ReportModel>((token) async {
      final response = await _dio.post<dynamic>(
        '/api/reports',
        data: {
          'title': title,
          'description': description,
          if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
          if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
          if (priority != null && priority.trim().isNotEmpty) 'priority': priority.trim(),
          if (attachmentId != null && attachmentId.trim().isNotEmpty)
            'attachmentId': attachmentId.trim(),
        },
        options: _authOptions(token),
      );
      final data = _unwrap(response.data);
      if (data is! Map) {
        throw const BadResponseException('Unexpected report response');
      }
      return ReportModel.fromJson(Map<String, dynamic>.from(data));
    });
  }

  /// `POST /api/reports/attachments` — upload a photo (multipart) for the
  /// authenticated student. [onProgress] reports bytes sent / total.
  Future<ReportAttachment> uploadReportImage({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) {
    return _authed<ReportAttachment>((token) async {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      });
      final response = await _dio.post<dynamic>(
        '/api/reports/attachments',
        data: form,
        options: _authOptions(token),
        onSendProgress: onProgress,
      );
      final data = _unwrap(response.data);
      if (data is! Map) {
        throw const BadResponseException('Unexpected attachment response');
      }
      return ReportAttachment.fromJson(Map<String, dynamic>.from(data));
    });
  }

  /// `DELETE /api/reports/attachments/:id` — remove a not-yet-attached photo.
  Future<void> deleteAttachment(String id) {
    return _authed<void>((token) async {
      final response = await _dio.delete<dynamic>(
        '/api/reports/attachments/$id',
        options: _authOptions(token),
      );
      _unwrap(response.data);
    });
  }

  /// Resolves a backend-relative path (e.g. a report's `imageUrl`) to an
  /// absolute URL. Returns null when the backend is not configured or the
  /// value is already absolute.
  String? absoluteUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final value = path.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (!_enabled) return null;
    final base =
        _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return value.startsWith('/') ? '$base$value' : '$base/$value';
  }

  /// Bearer headers needed to fetch an authenticated attachment image.
  Future<Map<String, String>?> imageAuthHeaders() async {
    if (!_enabled) return null;
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  Options _authOptions(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  /// Extract the `data` field from a `{success, data, message, statusCode}`
  /// envelope, surfacing backend error messages as typed exceptions.
  dynamic _unwrap(dynamic body) {
    if (body is Map && body['success'] == true) {
      return body['data'];
    }
    if (body is Map && body['message'] != null) {
      throw ServerException(body['message'].toString());
    }
    throw const BadResponseException();
  }

  /// Runs an authenticated backend call, mapping transport failures to the
  /// app's typed [ApiException] hierarchy.
  Future<T> _authed<T>(Future<T> Function(String token) run) async {
    if (!_enabled) {
      throw const NetworkException(
        'Reports need the PULSE backend. Build with '
        '--dart-define=PULSE_BACKEND_URL=https://<host:port>.',
      );
    }
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      throw const UnauthorizedException(
        'Your PULSE backend session is missing. Please login again.',
      );
    }
    try {
      return await run(token);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
