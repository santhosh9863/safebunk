import '../../core/calculations/attendance_analysis.dart';
import '../../core/calculations/attendance_engine.dart';
import '../../core/calculations/attendance_rules.dart';
import '../../models/api/course_attendance_model.dart';

class AttendanceAnalysisMapper {
  AttendanceAnalysisMapper._();

  static AttendanceAnalysis mapCourseAttendance(CourseAttendanceModel model) {
    return AttendanceAnalysis(
      percentage: model.attendancePercentage,
      safeBunks: AttendanceEngine.calculateSafeBunks(
        model.totalPresent,
        model.totalAttendance,
      ),
      requiredClasses: AttendanceEngine.calculateRequiredClasses(
        model.totalPresent,
        model.totalAttendance,
      ),
      isDanger: model.attendancePercentage < AttendanceRules.dangerAttendance,
      isWarning: model.attendancePercentage >= AttendanceRules.dangerAttendance &&
          model.attendancePercentage < AttendanceRules.warningAttendance,
      isSafe: model.attendancePercentage >= AttendanceRules.warningAttendance,
      presentHours: model.totalPresent,
      totalHours: model.totalAttendance,
      dutyLeaveHours: model.totalDutyLeave,
      attendanceWithoutDutyLeave: model.attendancePercentageWithoutDutyLeave,
    );
  }
}
