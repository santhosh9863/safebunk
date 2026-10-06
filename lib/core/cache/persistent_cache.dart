import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class PersistentCache {
  static const _dailyAttendanceBox = 'daily_attendance';
  static const _subjectWiseBox = 'subject_wise_attendance';
  static const _profileBox = 'profile';
  static const _academicTermBox = 'academic_term';
  static const _timetableBox = 'timetable';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_dailyAttendanceBox);
    await Hive.openBox<String>(_subjectWiseBox);
    await Hive.openBox<String>(_profileBox);
    await Hive.openBox<String>(_academicTermBox);
    await Hive.openBox<String>(_timetableBox);
  }

  /// Attendance is re-fetched from Linways once a persisted payload is older
  /// than this, so Hive can never serve indefinitely stale semester totals.
  static const attendanceMaxAge = Duration(hours: 6);

  static List<T>? getDailyAttendance<T>(String studentId, T Function(Map<String, dynamic>) fromJson) {
    try {
      final envelope = _decodeFreshEnvelope(
        Hive.box<String>(_dailyAttendanceBox).get(studentId),
      );
      if (envelope == null) return null;

      return (envelope['items'] as List)
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      _safeDelete(_dailyAttendanceBox, studentId);
      return null;
    }
  }

  static Future<void> setDailyAttendance(String studentId, List<Map<String, dynamic>> items) async {
    try {
      final box = Hive.box<String>(_dailyAttendanceBox);
      await box.put(studentId, _encodeEnvelope(items));
    } catch (_) {}
  }

  static List<T>? getSubjectWiseAttendance<T>(String studentId, T Function(Map<String, dynamic>) fromJson) {
    try {
      final envelope = _decodeFreshEnvelope(
        Hive.box<String>(_subjectWiseBox).get(studentId),
      );
      if (envelope == null) return null;

      return (envelope['items'] as List)
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      _safeDelete(_subjectWiseBox, studentId);
      return null;
    }
  }

  static Future<void> setSubjectWiseAttendance(String studentId, List<Map<String, dynamic>> items) async {
    try {
      final box = Hive.box<String>(_subjectWiseBox);
      await box.put(studentId, _encodeEnvelope(items));
    } catch (_) {}
  }

  static String _encodeEnvelope(List<Map<String, dynamic>> items) {
    return jsonEncode({
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'items': items,
    });
  }

  /// Returns the envelope only when it is still within [attendanceMaxAge].
  /// Anything else — unparseable, missing timestamp, or an expired payload
  /// (including the legacy bare-list format) — is reported as a miss.
  static Map<String, dynamic>? _decodeFreshEnvelope(String? jsonStr) {
    if (jsonStr == null) return null;

    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) return null;

    final envelope = Map<String, dynamic>.from(decoded);
    final cachedAt = envelope['cachedAt'];
    final items = envelope['items'];
    if (cachedAt is! num || items is! List) return null;

    final age = DateTime.now().millisecondsSinceEpoch - cachedAt.toInt();
    if (age < 0 || age >= attendanceMaxAge.inMilliseconds) return null;

    return envelope;
  }

  static T? getProfile<T>(String studentId, T Function(Map<String, dynamic>) fromJson) {
    try {
      final box = Hive.box<String>(_profileBox);
      final jsonStr = box.get(studentId);
      if (jsonStr == null) return null;

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return fromJson(decoded);
    } catch (_) {
      _safeDelete(_profileBox, studentId);
      return null;
    }
  }

  static Future<void> setProfile(String studentId, Map<String, dynamic> data) async {
    try {
      final box = Hive.box<String>(_profileBox);
      await box.put(studentId, jsonEncode(data));
    } catch (_) {}
  }

  static String? getStoredTermId(String studentId) {
    try {
      return Hive.box<String>(_academicTermBox).get(studentId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setStoredTermId(String studentId, String termId) async {
    try {
      await Hive.box<String>(_academicTermBox).put(studentId, termId);
    } catch (_) {}
  }

  static List<T>? getTimetable<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    try {
      final box = Hive.box<String>(_timetableBox);
      final jsonStr = box.get(key);
      if (jsonStr == null) return null;

      final decoded = jsonDecode(jsonStr) as List;
      return decoded
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      _safeDelete(_timetableBox, key);
      return null;
    }
  }

  static Future<void> setTimetable(String key, List<Map<String, dynamic>> items) async {
    try {
      final box = Hive.box<String>(_timetableBox);
      await box.put(key, jsonEncode(items));
    } catch (_) {}
  }

  static Future<void> deleteStudentAttendance(String studentId) async {
    for (final boxName in [_dailyAttendanceBox, _subjectWiseBox]) {
      try {
        final box = Hive.box<String>(boxName);
        for (final key in box.keys.toList()) {
          if (key == studentId || key.startsWith('$studentId:')) {
            await box.delete(key);
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> clearAll() async {
    try {
      await Hive.box<String>(_dailyAttendanceBox).clear();
      await Hive.box<String>(_subjectWiseBox).clear();
      await Hive.box<String>(_profileBox).clear();
      await Hive.box<String>(_academicTermBox).clear();
    } catch (_) {}
  }

  static void _safeDelete(String boxName, String key) {
    try {
      Hive.box<String>(boxName).delete(key);
    } catch (_) {}
  }
}
