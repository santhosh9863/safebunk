import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  static const _cookieKey = 'session_cookies';
  static const _usernameKey = 'saved_username';
  static const _studentIdKey = 'saved_student_id';

  Future<void> saveCookies(String cookies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieKey, cookies);
  }

  Future<String?> getCookies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cookieKey);
  }

  Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    final cookies = prefs.getString(_cookieKey);
    return cookies != null && cookies.isNotEmpty;
  }

  Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  Future<void> saveStudentId(String studentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_studentIdKey, studentId);
  }

  Future<String?> getStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_studentIdKey);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookieKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_studentIdKey);
  }
}
