import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_constants.dart';

class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> saveCookies(String cookies) async {
    await _storage.write(key: ApiConstants.storageCookies, value: cookies);
  }

  Future<String?> getCookies() async {
    return _storage.read(key: ApiConstants.storageCookies);
  }

  Future<bool> hasCookies() async {
    final cookies = await _storage.read(key: ApiConstants.storageCookies);
    return cookies != null && cookies.isNotEmpty;
  }

  Future<void> saveUsername(String username) async {
    await _storage.write(key: ApiConstants.storageUsername, value: username);
  }

  Future<String?> getUsername() async {
    return _storage.read(key: ApiConstants.storageUsername);
  }

  Future<void> saveStudentId(String studentId) async {
    await _storage.write(key: ApiConstants.storageStudentId, value: studentId);
  }

  Future<String?> getStudentId() async {
    return _storage.read(key: ApiConstants.storageStudentId);
  }

  Future<Map<String, dynamic>?> getStudentData() async {
    final json = await _storage.read(key: ApiConstants.storageStudentData);
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStudentData(Map<String, dynamic> data) async {
    await _storage.write(key: ApiConstants.storageStudentData, value: jsonEncode(data));
  }

  Future<bool> hasSession() async {
    return hasCookies();
  }

  Future<void> clearSession() async {
    await _storage.delete(key: ApiConstants.storageCookies);
    await _storage.delete(key: ApiConstants.storageUsername);
    await _storage.delete(key: ApiConstants.storageStudentId);
    await _storage.delete(key: ApiConstants.storageStudentData);
  }

}
