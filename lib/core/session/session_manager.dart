import '../auth/token_parser.dart';
import '../../models/auth/session_data.dart';
import '../storage/secure_storage_service.dart';

class SessionManager {
  final SecureStorageService _storage;

  SessionManager(this._storage);

  Future<void> saveSession(SessionData session) async {
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

  Future<String?> getStudentId() async {
    return _storage.getStudentId();
  }

  Future<String?> getCookies() async {
    return _storage.getCookies();
  }

  Future<bool> isAuthenticated() async {
    return _storage.hasSession();
  }
}
