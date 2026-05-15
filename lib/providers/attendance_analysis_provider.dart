import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/calculations/attendance_analysis.dart';
import '../services/normalizers/attendance_analysis_mapper.dart';
import 'attendance_provider.dart';

class AttendanceAnalysisItem {
  final String subjectName;
  final AttendanceAnalysis analysis;

  const AttendanceAnalysisItem({
    required this.subjectName,
    required this.analysis,
  });
}

final attendanceAnalysisProvider = Provider<AsyncValue<List<AttendanceAnalysisItem>>>((ref) {
  final asyncSubjects = ref.watch(subjectAttendanceProvider);

  return asyncSubjects.when(
    data: (models) {
      if (models.isEmpty) return const AsyncValue.data([]);
      try {
        final items = models.map((m) => AttendanceAnalysisItem(
          subjectName: m.subjectName,
          analysis: AttendanceAnalysisMapper.mapCourseAttendance(m),
        )).toList();
        return AsyncValue.data(items);
      } catch (e, st) {
        return AsyncValue.error(e, st);
      }
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});
