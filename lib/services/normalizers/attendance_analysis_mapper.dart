import '../../core/calculations/attendance_analysis.dart';
import '../../core/calculations/attendance_engine.dart';
import '../../models/api/course_attendance_model.dart';

class AttendanceAnalysisMapper {
  AttendanceAnalysisMapper._();

  static AttendanceAnalysis mapCourseAttendance(CourseAttendanceModel model) {
    final subj = SubjectAttendance(
      subjectName: model.subjectName,
      present: model.totalPresent,
      absent: model.totalAbsent,
      leave: model.totalLeave,
      dutyLeave: model.totalDutyLeave,
      totalHours: model.totalAttendance,
    );

    final stats = AttendanceEngine.computeStats(subj);

    return AttendanceAnalysis(
      percentage: stats.percentage,
      safeBunks: stats.safeBunks,
      requiredClasses: stats.classesNeeded,
      isDanger: stats.isDanger,
      isWarning: stats.isWarning,
      isSafe: stats.isSafe,
      presentHours: stats.presentHours,
      totalHours: stats.totalHours,
      dutyLeaveHours: stats.dutyLeaveHours,
      attendanceWithoutDutyLeave: stats.attendanceWithoutDutyLeave,
    );
  }
}
