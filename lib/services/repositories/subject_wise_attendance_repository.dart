import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../models/api/subject_wise_attendance_model.dart';
import '../api/subject_wise_attendance_service.dart';

class SubjectWiseAttendanceRepository {
  final SubjectWiseAttendanceService _service;
  final MemoryCache<List<SubjectWiseAttendanceModel>> _cache;

  SubjectWiseAttendanceRepository({
    required SubjectWiseAttendanceService service,
    required MemoryCache<List<SubjectWiseAttendanceModel>> cache,
  })  : _service = service,
        _cache = cache;

  Future<List<SubjectWiseAttendanceModel>> fetchSubjectWiseAttendance({
    required String studentId,
    String termId = '4',
    String startDate = '2026-02-03',
    String endDate = '2026-05-30',
  }) async {
    final cached = _cache.get(studentId);
    if (cached != null) {
      return cached;
    }

    final persisted = PersistentCache.getSubjectWiseAttendance(
      studentId,
      SubjectWiseAttendanceModel.fromJson,
    );
    if (persisted != null) {
      _cache.set(studentId, persisted);
      return persisted;
    }

    final result = await _service.fetchSubjectWiseAttendance(
      studentId: studentId,
      termId: termId,
      startDate: startDate,
      endDate: endDate,
    );

    _cache.set(studentId, result);
    await _persistSubjectWiseAttendance(studentId, result);
    return result;
  }

  void clearCache() {
    _cache.clear();
  }

  Future<void> _persistSubjectWiseAttendance(
    String studentId,
    List<SubjectWiseAttendanceModel> records,
  ) async {
    final jsonList = records.map((r) => r.toJson()).toList();
    await PersistentCache.setSubjectWiseAttendance(studentId, jsonList);
  }
}
