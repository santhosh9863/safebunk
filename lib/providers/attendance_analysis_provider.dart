import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/calculations/attendance_analysis.dart';
import '../services/normalizers/attendance_analysis_mapper.dart';
import 'attendance_provider.dart';
import 'subject_wise_attendance_provider.dart';

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
      if (models.isNotEmpty) {
        try {
          final items = models.map((m) => AttendanceAnalysisItem(
            subjectName: m.subjectName,
            analysis: AttendanceAnalysisMapper.mapCourseAttendance(m),
          )).toList();
          return AsyncValue.data(items);
        } catch (e, st) {
          return AsyncValue.error(e, st);
        }
      }

      // Daily pipeline has no records (e.g. Linways returned no active date
      // range for the current term). Fall back to the official subject-wise
      // report — same synchronized dataset the Subjects screen uses — so the
      // Dashboard never shows a false "No attendance data yet".
      return ref.watch(subjectWiseAttendanceProvider).when(
        data: (subjectModels) {
          try {
            final items = subjectModels.map((s) {
              final course = AttendanceAnalysisMapper.mapSubjectWiseToCourseAttendance(s);
              return AttendanceAnalysisItem(
                subjectName: s.subjectName,
                analysis: AttendanceAnalysisMapper.mapCourseAttendance(course),
              );
            }).toList();
            return AsyncValue.data(items);
          } catch (e, st) {
            return AsyncValue.error(e, st);
          }
        },
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
    },
    loading: () {
      return const AsyncValue.loading();
    },
    error: (e, st) {
      return AsyncValue.error(e, st);
    },
  );
});
