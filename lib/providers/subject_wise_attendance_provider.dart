import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api/subject_wise_attendance_model.dart';
import '../services/api/subject_wise_attendance_service.dart';
import '../storage/session_storage.dart';

/// Isolated provider for official subject-wise API data.
/// Does NOT replace the existing attendance system.
/// Provides comparison data for UI verification.
final subjectWiseAttendanceProvider = FutureProvider<List<SubjectWiseAttendanceModel>>((ref) async {
  final studentId = (await SessionStorage().getStudentId()) ?? '4286';
  final service = SubjectWiseAttendanceService();
  final result = await service.fetchSubjectWiseAttendance(studentId: studentId);
  print('[SUBJECT_PROVIDER] Loaded ${result.length} official subject records');
  return result;
});
