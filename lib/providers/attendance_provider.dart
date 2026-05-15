import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/api/course_attendance_model.dart';
import '../models/api/daily_attendance_model.dart';
import '../services/api/attendance_api_service.dart';
import '../services/repositories/attendance_repository.dart';
import '../storage/session_storage.dart';

final _apiServiceProvider = Provider<AttendanceApiService>((ref) {
  return AttendanceApiService(DioClient.instance.dio);
});

final _repositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(api: ref.watch(_apiServiceProvider));
});

final _studentIdProvider = FutureProvider<String>((ref) async {
  return (await SessionStorage().getStudentId()) ?? '4286';
});

final dailyAttendanceProvider = FutureProvider<List<DailyAttendanceModel>>((ref) async {
  final repo = ref.watch(_repositoryProvider);
  final studentId = await ref.watch(_studentIdProvider.future);
  return repo.fetchDailyAttendance(studentId: studentId);
});

final lastUpdatedProvider = StateProvider<DateTime?>((ref) => null);

final subjectAttendanceProvider = FutureProvider<List<CourseAttendanceModel>>((ref) async {
  final repo = ref.watch(_repositoryProvider);
  final studentId = await ref.watch(_studentIdProvider.future);
  final daily = await repo.fetchDailyAttendance(studentId: studentId);
  return repo.aggregateSubjectAttendance(daily);
});
