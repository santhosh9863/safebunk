import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/memory_cache.dart';
import '../core/network/dio_client.dart';
import '../models/api/course_attendance_model.dart';
import '../models/api/daily_attendance_model.dart';
import '../services/api/attendance_api_service.dart';
import '../services/repositories/attendance_repository.dart';
import 'auth_provider.dart';

final _apiServiceProvider = Provider<AttendanceApiService>((ref) {
  return AttendanceApiService(DioClient.instance.dio);
});

final _attendanceCacheProvider = Provider<MemoryCache<List<DailyAttendanceModel>>>((ref) {
  final cache = MemoryCache<List<DailyAttendanceModel>>(ttl: const Duration(minutes: 5));
  ref.watch(cacheManagerProvider).register(cache.clear);
  return cache;
});

final _repositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(
    api: ref.watch(_apiServiceProvider),
    cache: ref.watch(_attendanceCacheProvider),
  );
});

final _studentIdProvider = FutureProvider<String>((ref) async {
  final sessionManager = ref.watch(sessionManagerProvider);
  final id = await sessionManager.getStudentId();
  return id ?? '';
});

final dailyAttendanceProvider = FutureProvider<List<DailyAttendanceModel>>((ref) async {
  final repo = ref.watch(_repositoryProvider);
  final studentId = await ref.watch(_studentIdProvider.future);
  if (studentId.isEmpty) {
    return [];
  }
  try {
    final result = await repo.fetchDailyAttendance(studentId: studentId);
    return result;
  } catch (_) {
    rethrow;
  }
});

final lastUpdatedProvider = StateProvider<DateTime?>((ref) => null);

final subjectAttendanceProvider = FutureProvider<List<CourseAttendanceModel>>((ref) async {
  final repo = ref.watch(_repositoryProvider);
  final studentId = await ref.watch(_studentIdProvider.future);
  if (studentId.isEmpty) {
    return [];
  }
  try {
    final daily = await repo.fetchDailyAttendance(studentId: studentId);
    final result = repo.aggregateSubjectAttendance(daily);
    return result;
  } catch (_) {
    rethrow;
  }
});
