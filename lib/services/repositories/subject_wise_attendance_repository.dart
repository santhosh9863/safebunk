import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../models/api/subject_wise_attendance_model.dart';
import '../api/attendance_terms_service.dart';
import '../api/subject_wise_attendance_service.dart';

class SubjectWiseAttendanceRepository {
  final SubjectWiseAttendanceService _service;
  final AttendanceTermsService _termsService;
  final MemoryCache<List<SubjectWiseAttendanceModel>> _cache;

  SubjectWiseAttendanceRepository({
    required SubjectWiseAttendanceService service,
    required MemoryCache<List<SubjectWiseAttendanceModel>> cache,
    AttendanceTermsService? termsService,
  })  : _service = service,
        _cache = cache,
        _termsService = termsService ?? AttendanceTermsService() {
    _termsService.addTermChangeListener((_, _) => _cache.clear());
  }

  Future<List<SubjectWiseAttendanceModel>> fetchSubjectWiseAttendance({
    required String studentId,
    String? termId,
    String? startDate,
    String? endDate,
  }) async {
    final currentTerm = await _termsService.fetchCurrentTerm(studentId);
    final resolvedTermId = termId ?? currentTerm?.termId ?? '';
    final resolvedStartDate = startDate ?? currentTerm?.startDate ?? '';
    final resolvedEndDate = endDate ?? currentTerm?.endDate ?? '';

    if (resolvedTermId.isEmpty) {
      return [];
    }

    final cacheKey = '$studentId:$resolvedTermId';
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      return cached;
    }

    final persisted = PersistentCache.getSubjectWiseAttendance(
      cacheKey,
      SubjectWiseAttendanceModel.fromJson,
    );
    if (persisted != null) {
      _cache.set(cacheKey, persisted);
      return persisted;
    }

    final result = await _service.fetchSubjectWiseAttendance(
      studentId: studentId,
      termId: resolvedTermId,
      startDate: resolvedStartDate,
      endDate: resolvedEndDate,
    );

    _cache.set(cacheKey, result);
    await _persistSubjectWiseAttendance(cacheKey, result);
    return result;
  }

  void clearCache() {
    _cache.clear();
  }

  Future<void> _persistSubjectWiseAttendance(
    String cacheKey,
    List<SubjectWiseAttendanceModel> records,
  ) async {
    final jsonList = records.map((r) => r.toJson()).toList();
    await PersistentCache.setSubjectWiseAttendance(cacheKey, jsonList);
  }
}
