import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../core/calculations/attendance_engine.dart';
import '../../models/api/course_attendance_model.dart';
import '../../models/api/daily_attendance_model.dart';
import '../api/attendance_api_service.dart';
import '../api/attendance_terms_service.dart';

class AttendanceRepository {
  final AttendanceApiService _api;
  final AttendanceTermsService _termsService;
  final MemoryCache<List<DailyAttendanceModel>> _cache;

  AttendanceRepository({
    required AttendanceApiService api,
    required MemoryCache<List<DailyAttendanceModel>> cache,
    AttendanceTermsService? termsService,
  })  : _api = api,
        _cache = cache,
        _termsService = termsService ?? AttendanceTermsService() {
    _termsService.addTermChangeListener((_, _) => _cache.clear());
  }

  Future<List<DailyAttendanceModel>> fetchDailyAttendance({
    required String studentId,
    String? fromDate,
    String? toDate,
  }) async {
    final dateRange = fromDate == null || toDate == null
        ? await _termsService.fetchCurrentDateRange(studentId)
        : null;
    final currentTerm = await _termsService.fetchCurrentTerm(studentId);
    final termId = currentTerm?.termId ?? '';
    final resolvedFromDate = fromDate ?? dateRange?.startDate ?? '';
    final resolvedToDate = toDate ?? dateRange?.endDate ?? '';

    if (resolvedFromDate.isEmpty || resolvedToDate.isEmpty) {
      return [];
    }

    final cacheKey = '$studentId:$termId';
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    final persisted = PersistentCache.getDailyAttendance(
      cacheKey,
      DailyAttendanceModel.fromJson,
    );
    if (persisted != null) {
      _cache.set(cacheKey, persisted);
      return persisted;
    }

    final result = await _api.fetchDailyAttendance(
      studentId: studentId,
      fromDate: resolvedFromDate,
      toDate: resolvedToDate,
    );

    _cache.set(cacheKey, result);
    await _persistDailyAttendance(cacheKey, result);
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
    String cacheKey,
    List<DailyAttendanceModel> records,
  ) async {
    final jsonList = records.map((r) => r.toJson()).toList();
    await PersistentCache.setDailyAttendance(cacheKey, jsonList);
  }
}
