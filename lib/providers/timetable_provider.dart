import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/memory_cache.dart';
import '../core/network/dio_client.dart';
import '../models/api/timetable_model.dart';
import '../services/api/timetable_api_service.dart';
import '../services/repositories/timetable_repository.dart';
import 'auth_provider.dart';

final _timetableWeeklyCacheProvider = Provider<MemoryCache<List<TimetableDay>>>((ref) {
  final cache = MemoryCache<List<TimetableDay>>(ttl: const Duration(minutes: 5));
  ref.watch(cacheManagerProvider).register(cache.clear);
  return cache;
});

final _timetableTodayCacheProvider = Provider<MemoryCache<List<TimetableEntry>>>((ref) {
  final cache = MemoryCache<List<TimetableEntry>>(ttl: const Duration(minutes: 2));
  ref.watch(cacheManagerProvider).register(cache.clear);
  return cache;
});

final _timetableRepositoryProvider = Provider<TimetableRepository>((ref) {
  return TimetableRepository(
    service: TimetableApiService(),
    weeklyCache: ref.watch(_timetableWeeklyCacheProvider),
    todayCache: ref.watch(_timetableTodayCacheProvider),
  );
});

final _timetableApiServiceProvider = Provider<TimetableApiService>((ref) {
  return TimetableApiService();
});

final weeklyTimetableProvider = FutureProvider.family<List<TimetableDay>, WeeklyTimetableRequest>((ref, request) async {
  final repo = ref.watch(_timetableRepositoryProvider);
  try {
    final result = await repo.fetchWeeklyTimetable(
      batchId: request.batchId,
      fromDate: request.fromDate,
      toDate: request.toDate,
    );
    return result;
  } catch (_) {
    rethrow;
  }
});

final todayScheduleProvider = FutureProvider<List<TimetableEntry>>((ref) async {
  final repo = ref.watch(_timetableRepositoryProvider);
  try {
    return await repo.fetchTodaySchedule();
  } catch (_) {
    return [];
  }
});

final dayHoursProvider = FutureProvider<List<DayHourModel>>((ref) async {
  final service = ref.watch(_timetableApiServiceProvider);
  try {
    return await service.fetchDayHours();
  } catch (_) {
    return [];
  }
});

final batchIdTimetableProvider = FutureProvider<String>((ref) async {
  final sessionManager = ref.watch(sessionManagerProvider);
  final dio = DioClient.instance.dio;
  final studentId = await sessionManager.getStudentId();
  if (studentId == null || studentId.isEmpty) return '';

  try {
    final response = await dio.get(
      '/student/get-student-basic-details',
      queryParameters: {'studentId': studentId},
    );
    final data = response.data;
    if (data is Map && data['success'] == true) {
      final properties = data['data']?['properties'] as Map?;
      if (properties != null) {
        return properties['currentBatchId']?.toString() ?? '';
      }
    }
  } catch (_) {}

  return '';
});

class WeeklyTimetableRequest {
  final String batchId;
  final String fromDate;
  final String toDate;

  const WeeklyTimetableRequest({
    required this.batchId,
    required this.fromDate,
    required this.toDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyTimetableRequest &&
          batchId == other.batchId &&
          fromDate == other.fromDate &&
          toDate == other.toDate;

  @override
  int get hashCode => Object.hash(batchId, fromDate, toDate);
}
