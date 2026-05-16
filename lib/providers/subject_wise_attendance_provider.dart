import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/memory_cache.dart';
import '../models/api/subject_wise_attendance_model.dart';
import '../services/api/subject_wise_attendance_service.dart';
import '../services/repositories/subject_wise_attendance_repository.dart';
import 'auth_provider.dart';

final _subjectWiseCacheProvider = Provider<MemoryCache<List<SubjectWiseAttendanceModel>>>((ref) {
  final cache = MemoryCache<List<SubjectWiseAttendanceModel>>(ttl: const Duration(minutes: 5));
  ref.watch(cacheManagerProvider).register(cache.clear);
  return cache;
});

final _subjectWiseRepositoryProvider = Provider<SubjectWiseAttendanceRepository>((ref) {
  return SubjectWiseAttendanceRepository(
    service: SubjectWiseAttendanceService(),
    cache: ref.watch(_subjectWiseCacheProvider),
  );
});

final subjectWiseAttendanceProvider = FutureProvider<List<SubjectWiseAttendanceModel>>((ref) async {
  final sessionManager = ref.watch(sessionManagerProvider);
  final studentId = (await sessionManager.getStudentId()) ?? '';
  if (studentId.isEmpty) {
    return [];
  }
  final repo = ref.watch(_subjectWiseRepositoryProvider);
  try {
    final subjects = await repo.fetchSubjectWiseAttendance(studentId: studentId);
    return subjects;
  } catch (_) {
    rethrow;
  }
});
