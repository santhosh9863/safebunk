import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exceptions.dart';
import '../../features/reports/data/models/report_attachment.dart';
import '../../features/reports/data/models/report_model.dart';
import '../../models/auth/staff_account.dart';
import '../../models/auth/staff_session.dart';
import 'pulse_backend_config.dart';

/// Client for the PULSE NestJS backend (device registration, preferences,
/// FCM-backed events, Reports).
///
/// The backend base URL is injected at build time (local development examples):
///   web / Windows:        --dart-define=PULSE_BACKEND_URL=http://localhost:3000
///   Android emulator:     --dart-define=PULSE_BACKEND_URL=http://10.0.2.2:3000
///   physical Android:     --dart-define=PULSE_BACKEND_URL=http://YOUR_PC_LAN_IP:3000
///
/// A missing or placeholder value is treated as "not configured": notification
/// syncing stays a no-op, while Reports surfaces an actionable configuration
/// error instead of an opaque network failure.
class PulseBackendService {
  static const _baseUrl = String.fromEnvironment(PulseBackendConfig.defineName);

  static const _tokenKey = 'backend_access_token';
  static const _studentIdKey = 'backend_student_id';
  static const _genderKey = 'backend_student_gender';

  final PulseBackendConfig _config;
  final Dio _dio;
  final FlutterSecureStorage _storage;

  PulseBackendService({
    Dio? dio,
    FlutterSecureStorage? storage,
    String? baseUrl,
  }) : this._(PulseBackendConfig.parse(baseUrl ?? _baseUrl), dio, storage);

  PulseBackendService._(this._config, Dio? dio, FlutterSecureStorage? storage)
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _config.baseUrl ?? '',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json'},
            ),
          ),
      _storage = storage ?? const FlutterSecureStorage();

  bool get isEnabled => _config.isEnabled;

  /// Actionable configuration problem, or null when the URL is valid.
  String? get configurationError => _config.error;

  Future<bool> get isLoggedIn async {
    if (!isEnabled) return false;
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Authenticate against the backend so it has a live Linways session for
  /// the watchers, and remember the token for device registration.
  Future<bool> login(String username, String password) async {
    if (!isEnabled) return false;
    // A fresh Linways login must never keep a PULSE token from a previous
    // account/session. Clear first; a failed login leaves Reports asking for
    // a fresh login instead of reusing stale credentials.
    await _clearStoredSession();
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {'username': username, 'password': password},
      );
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
    if (!isEnabled) return;
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
    await _clearStoredSession();
  }

  /// Deletes every persisted PULSE backend credential. Used on logout, on a
  /// fresh login, and when the backend rejects a token as expired.
  Future<void> _clearStoredSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _studentIdKey);
    await _storage.delete(key: _genderKey);
  }

  // ---------------------------------------------------------------------------
  // Staff/admin authentication
  // ---------------------------------------------------------------------------

  /// `POST /api/auth/staff/login` — local staff/admin credentials only.
  ///
  /// The returned role is parsed strictly from the backend response. The token
  /// is deliberately not persisted here: the auth notifier stores the complete
  /// session through the app's secure [SessionManager].
  Future<StaffSession> staffLogin(String username, String password) async {
    if (!isEnabled) {
      throw NetworkException(
        _config.error ?? PulseBackendConfig.missingMessage,
      );
    }

    try {
      final response = await _dio.post<dynamic>(
        '/api/auth/staff/login',
        data: {'username': username, 'password': password},
      );
      final data = _unwrap(response.data);
      if (data is! Map) {
        throw const BadResponseException('Unexpected staff login response');
      }
      try {
        return StaffSession.fromLoginJson(Map<String, dynamic>.from(data));
      } on FormatException {
        throw const BadResponseException('Unexpected staff login response');
      }
    } on DioException catch (e) {
      // A failed login is not an expired session. Use one generic message so
      // the screen does not reveal whether the username exists or is inactive.
      if (e.response?.statusCode == 401) {
        throw const UnauthorizedException('Invalid username or password.');
      }
      if (e.response?.statusCode == 403) {
        throw const UnauthorizedException(
          'This account is not allowed to use staff sign-in.',
        );
      }
      if (e.response?.statusCode == 429) {
        throw ServerException(
          _serverMessage(e.response?.data) ??
              'Too many login attempts. Please try again later.',
          statusCode: 429,
        );
      }
      throw mapDioException(e);
    }
  }

  /// Best-effort revocation of a staff/admin token.
  Future<void> staffLogout(String token) async {
    if (!isEnabled || token.trim().isEmpty) return;
    try {
      await _dio.post<dynamic>(
        '/api/auth/logout',
        options: _authOptions(token),
      );
    } catch (_) {
      // The backend session expires on its own; local state is cleared by the
      // auth notifier regardless.
    }
  }

  /// `GET /api/staff/reports` — staff see their assigned queue; admin sees all.
  Future<List<ReportModel>> fetchStaffReports(String token, {String? status}) {
    return _staffAuthed<List<ReportModel>>(token, (staffToken) async {
      final response = await _dio.get<dynamic>(
        '/api/staff/reports',
        queryParameters: status == null || status.trim().isEmpty
            ? null
            : {'status': status},
        options: _authOptions(staffToken),
      );
      final data = _unwrap(response.data);
      if (data is! List) {
        throw const BadResponseException('Unexpected staff reports response');
      }
      return data
          .whereType<Map>()
          .map((e) => ReportModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    });
  }

  /// `GET /api/staff/reports/:id` — detail plus full status/progress history.
  Future<ReportModel> fetchStaffReport(String token, String reportId) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.get<dynamic>(
        '/api/staff/reports/$reportId',
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  /// `POST /api/staff/reports/:id/assign` — admin assignment/reassignment.
  Future<ReportModel> assignStaffReport(
    String token,
    String reportId, {
    required String staffId,
    String? department,
  }) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.post<dynamic>(
        '/api/staff/reports/$reportId/assign',
        data: {
          'staffId': staffId,
          'department': ?department,
        },
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  /// `POST /api/staff/reports/:id/accept` — assigned staff starts work.
  Future<ReportModel> acceptStaffReport(String token, String reportId) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.post<dynamic>(
        '/api/staff/reports/$reportId/accept',
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  /// `POST /api/staff/reports/:id/progress` — add an internal progress note.
  Future<ReportModel> addStaffProgressNote(
    String token,
    String reportId,
    String note,
  ) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.post<dynamic>(
        '/api/staff/reports/$reportId/progress',
        data: {'note': note},
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  /// `POST /api/staff/reports/:id/resolve` — resolve with required notes.
  Future<ReportModel> resolveStaffReport(
    String token,
    String reportId,
    String resolutionNotes,
  ) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.post<dynamic>(
        '/api/staff/reports/$reportId/resolve',
        data: {'resolutionNotes': resolutionNotes},
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  /// `POST /api/staff/reports/:id/reject` — admin-only rejection with reason.
  Future<ReportModel> rejectStaffReport(
    String token,
    String reportId,
    String reason,
  ) {
    return _staffAuthed<ReportModel>(token, (staffToken) async {
      final response = await _dio.post<dynamic>(
        '/api/staff/reports/$reportId/reject',
        data: {'reason': reason},
        options: _authOptions(staffToken),
      );
      return _parseStaffReport(response.data);
    });
  }

  ReportModel _parseStaffReport(dynamic body) {
    final data = _unwrap(body);
    if (data is! Map) {
      throw const BadResponseException('Unexpected staff report response');
    }
    return ReportModel.fromJson(Map<String, dynamic>.from(data));
  }

  /// `GET /api/staff/users` — admin-only staff account list.
  Future<List<StaffAccount>> fetchStaffAccounts(String token) {
    return _staffAuthed<List<StaffAccount>>(token, (staffToken) async {
      final response = await _dio.get<dynamic>(
        '/api/staff/users',
        options: _authOptions(staffToken),
      );
      final data = _unwrap(response.data);
      if (data is! List) {
        throw const BadResponseException('Unexpected staff accounts response');
      }
      try {
        return data
            .whereType<Map>()
            .map((e) => StaffAccount.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      } on FormatException {
        throw const BadResponseException('Unexpected staff accounts response');
      }
    });
  }

  Future<T> _staffAuthed<T>(
    String token,
    Future<T> Function(String staffToken) run,
  ) async {
    if (!isEnabled) {
      throw NetworkException(
        _config.error ?? PulseBackendConfig.missingMessage,
      );
    }
    if (token.trim().isEmpty) {
      throw const UnauthorizedException(
        'Your staff session is missing. Sign in again.',
      );
    }
    try {
      return await run(token);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const SessionExpiredException(
          'Your staff session expired. Please sign in again.',
        );
      }
      if (e.response?.statusCode == 403) {
        throw const UnauthorizedException(
          'You do not have permission to access this area.',
        );
      }
      throw mapDioException(e);
    }
  }

  Future<bool> registerDevice(String fcmToken) async {
    final token = await _storage.read(key: _tokenKey);
    if (!isEnabled || token == null || token.isEmpty) return false;
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
    if (!isEnabled || token == null || token.isEmpty) return;
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
    if (!isEnabled || token == null || token.isEmpty) return;
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
    if (!isEnabled) return '';
    return (await _storage.read(key: _genderKey)) ?? '';
  }

  /// Quick reachability probe — true when the backend answers. Used by the
  /// app to decide whether the server owns the daily messages (FCM) or the
  /// local scheduler must step in as fallback.
  Future<bool> isReachable() async {
    if (!isEnabled) return false;
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
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          if (location != null && location.trim().isNotEmpty)
            'location': location.trim(),
          if (priority != null && priority.trim().isNotEmpty)
            'priority': priority.trim(),
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
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (!isEnabled) return null;
    final base = _config.baseUrl!;
    return value.startsWith('/') ? '$base$value' : '$base/$value';
  }

  /// Bearer headers needed to fetch an authenticated attachment image.
  Future<Map<String, String>?> imageAuthHeaders() async {
    if (!isEnabled) return null;
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

  String? _serverMessage(dynamic body) {
    if (body is Map && body['message'] != null) {
      return body['message'].toString();
    }
    return null;
  }

  /// Runs an authenticated backend call, mapping transport failures to the
  /// app's typed [ApiException] hierarchy.
  Future<T> _authed<T>(Future<T> Function(String token) run) async {
    if (!isEnabled) {
      throw NetworkException(
        _config.error ?? PulseBackendConfig.missingMessage,
      );
    }
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      throw const UnauthorizedException(
        'Your PULSE backend session is missing. Log out and sign in again '
        'to reconnect Reports.',
      );
    }
    try {
      return await run(token);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // The PULSE session expired or was revoked. Drop the stale token so
        // it is never reused, and tell the user how to reconnect Reports.
        await _clearStoredSession();
        throw const SessionExpiredException(
          'Your PULSE backend session expired. Log out and sign in again '
          'to reconnect Reports.',
        );
      }
      throw mapDioException(e);
    }
  }
}
