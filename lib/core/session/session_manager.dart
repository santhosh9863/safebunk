import 'dart:convert';

import '../auth/token_parser.dart';
import '../../models/auth/session_data.dart';
import '../../models/auth/staff_session.dart';
import '../storage/secure_storage_service.dart';

class SessionManager {
  final SecureStorageService _storage;

  SessionManager(this._storage);

  /// Persists a Linways student session.
  ///
  /// Student and staff sessions are mutually exclusive: a successful student
  /// login removes any staff session that was left from a previous role.
  Future<void> saveSession(SessionData session) async {
    await _storage.clearStaffSession();
    if (session.cookies != null) {
      await _storage.saveCookies(session.cookies!);
    }
    if (session.username != null) {
      await _storage.saveUsername(session.username!);
    }
    if (session.studentId != null) {
      await _storage.saveStudentId(session.studentId!);
    }
    if (session.studentData != null) {
      await _storage.saveStudentData(session.studentData!);
    }
  }

  Future<SessionData?> restoreSession() async {
    final cookies = await _storage.getCookies();
    if (cookies == null || cookies.isEmpty) {
      return null;
    }
    final username = await _storage.getUsername();
    final studentId = await _storage.getStudentId();
    final studentData = await _storage.getStudentData();

    return SessionData(
      accessToken: TokenParser.extractAccessToken(cookies),
      studentId: studentId,
      username: username,
      cookies: cookies,
      studentData: studentData,
    );
  }

  Future<void> clearSession() async {
    await _storage.clearSession();
  }

  /// Persists a PULSE backend staff/admin session.
  ///
  /// Any Linways student session is removed first so a device can never
  /// present both identities at once.
  Future<void> saveStaffSession(StaffSession session) async {
    await _storage.clearSession();
    await _storage.saveStaffSession(jsonEncode(session.toJson()));
  }

  Future<StaffSession?> restoreStaffSession() async {
    final raw = await _storage.getStaffSession();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored staff session');
      }
      return StaffSession.fromJson(decoded);
    } catch (_) {
      // A malformed or unknown-role session is never restored as a privileged
      // identity. Remove it so the next launch starts cleanly.
      await _storage.clearStaffSession();
      return null;
    }
  }

  Future<void> clearStaffSession() async {
    await _storage.clearStaffSession();
  }

  Future<String?> getStudentId() async {
    return _storage.getStudentId();
  }

  Future<String?> getCookies() async {
    return _storage.getCookies();
  }

  Future<bool> isAuthenticated() async {
    return _storage.hasSession();
  }

  Future<bool> hasStaffSession() async {
    return _storage.hasStaffSession();
  }
}
