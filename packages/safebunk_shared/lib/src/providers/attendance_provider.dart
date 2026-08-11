import 'package:riverpod/riverpod.dart';
import '../models/attendance/attendance.dart';
import '../repositories/attendance_repository.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  throw UnimplementedError('attendanceRepositoryProvider must be overridden');
});

final dailyAttendanceProvider = FutureProvider<List<DailyAttendance>>((ref) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.getDailyAttendance();
});

final subjectAttendanceProvider = FutureProvider<List<SubjectAttendance>>((ref) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.getSubjectAttendance();
});
