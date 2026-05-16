import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../core/calculations/attendance_engine.dart';
import '../../models/api/course_attendance_model.dart';
import '../../models/api/daily_attendance_model.dart';
import '../api/attendance_api_service.dart';

class AttendanceRepository {
  final AttendanceApiService _api;
  final MemoryCache<List<DailyAttendanceModel>> _cache;

  AttendanceRepository({
    required AttendanceApiService api,
    required MemoryCache<List<DailyAttendanceModel>> cache,
  })  : _api = api,
        _cache = cache;

  Future<List<DailyAttendanceModel>> fetchDailyAttendance({
    required String studentId,
    String fromDate = '2026-02-03',
    String toDate = '2026-05-30',
  }) async {
    final cached = _cache.get(studentId);
    if (cached != null) {
      return cached;
    }

    final persisted = PersistentCache.getDailyAttendance(
      studentId,
      DailyAttendanceModel.fromJson,
    );
    if (persisted != null) {
      _cache.set(studentId, persisted);
      return persisted;
    }

    final result = await _api.fetchDailyAttendance(
      studentId: studentId,
      fromDate: fromDate,
      toDate: toDate,
    );

    _cache.set(studentId, result);
    await _persistDailyAttendance(studentId, result);
    return result;
  }

  List<CourseAttendanceModel> aggregateSubjectAttendance(
    List<DailyAttendanceModel> dailyRecords,
  ) {
    final subjects = AttendanceEngine.aggregate(dailyRecords);

    return subjects.map((s) {
      final stats = AttendanceEngine.computeStats(s);
      return CourseAttendanceModel(
        subjectName: s.subjectName,
        totalAttendance: stats.totalHours,
        totalPresent: stats.presentHours,
        totalAbsent: s.absent,
        totalLeave: s.leave,
        totalDutyLeave: s.dutyLeave,
        attendancePercentage: stats.percentage,
        attendancePercentageWithoutDutyLeave: stats.attendanceWithoutDutyLeave,
      );
    }).toList();
  }

  void clearCache() {
    _cache.clear();
  }

  Future<void> _persistDailyAttendance(
    String studentId,
    List<DailyAttendanceModel> records,
  ) async {
    final jsonList = records.map((r) => r.toJson()).toList();
    await PersistentCache.setDailyAttendance(studentId, jsonList);
  }
}
