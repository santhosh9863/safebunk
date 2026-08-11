import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class PersistentCache {
  static const _dailyAttendanceBox = 'daily_attendance';
  static const _subjectWiseBox = 'subject_wise_attendance';
  static const _profileBox = 'profile';
  static const _academicTermBox = 'academic_term';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_dailyAttendanceBox);
    await Hive.openBox<String>(_subjectWiseBox);
    await Hive.openBox<String>(_profileBox);
    await Hive.openBox<String>(_academicTermBox);
  }

  static List<T>? getDailyAttendance<T>(String studentId, T Function(Map<String, dynamic>) fromJson) {
    try {
      final box = Hive.box<String>(_dailyAttendanceBox);
      final jsonStr = box.get(studentId);
      if (jsonStr == null) return null;

      final decoded = jsonDecode(jsonStr) as List;
      return decoded
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
      await box.put(studentId, jsonEncode(items));
    } catch (_) {}
  }

  static List<T>? getSubjectWiseAttendance<T>(String studentId, T Function(Map<String, dynamic>) fromJson) {
    try {
      final box = Hive.box<String>(_subjectWiseBox);
      final jsonStr = box.get(studentId);
      if (jsonStr == null) return null;

      final decoded = jsonDecode(jsonStr) as List;
      return decoded
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
      await box.put(studentId, jsonEncode(items));
    } catch (_) {}
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
