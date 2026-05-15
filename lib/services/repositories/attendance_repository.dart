import '../../core/calculations/attendance_engine.dart';
import '../../models/api/course_attendance_model.dart';
import '../../models/api/daily_attendance_model.dart';
import '../api/attendance_api_service.dart';

class AttendanceRepository {
  final AttendanceApiService _api;

  AttendanceRepository({required AttendanceApiService api}) : _api = api;

  Future<List<DailyAttendanceModel>> fetchDailyAttendance({
    required String studentId,
    String fromDate = '2026-02-03',
    String toDate = '2026-05-30',
  }) async {
    return _api.fetchDailyAttendance(
      studentId: studentId,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  /// Aggregate daily records into subject-wise CourseAttendanceModel list.
  /// Delegates ALL math to AttendanceEngine.
  List<CourseAttendanceModel> aggregateSubjectAttendance(
    List<DailyAttendanceModel> dailyRecords,
  ) {
    final subjects = AttendanceEngine.aggregate(dailyRecords);

    return subjects.map((s) {
      final stats = AttendanceEngine.computeStats(s);
      return CourseAttendanceModel(
        subjectName: s.subjectName,
        totalAttendance: stats.totalHours,
        totalPresent: stats.presentHours,
        totalAbsent: s.absent,
        totalLeave: s.leave,
        totalDutyLeave: s.dutyLeave,
        attendancePercentage: stats.percentage,
        attendancePercentageWithoutDutyLeave: stats.attendanceWithoutDutyLeave,
      );
    }).toList();
  }
}
