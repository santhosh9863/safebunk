import '../../core/calculations/attendance_analysis.dart';
import '../../core/calculations/attendance_engine.dart';
import '../../core/calculations/attendance_rules.dart';
import '../../models/api/course_attendance_model.dart';
import '../../models/api/subject_wise_attendance_model.dart';

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

  /// Bridges the official subject-wise report into the Dashboard's
  /// course-attendance model using ACTUAL class counts from the API
  /// (never by averaging percentages).
  static CourseAttendanceModel mapSubjectWiseToCourseAttendance(
    SubjectWiseAttendanceModel s,
  ) {
    final totalAttendance = s.totalHours;
    final totalPresent = s.effectivePresent;
    final totalDutyLeave = s.dutyLeave;
    final totalAbsent = totalAttendance - totalPresent - totalDutyLeave;
    return CourseAttendanceModel(
      subjectName: s.subjectName,
      totalAttendance: totalAttendance,
      totalPresent: totalPresent,
      totalAbsent: totalAbsent < 0 ? 0 : totalAbsent,
      totalLeave: 0,
      totalDutyLeave: totalDutyLeave,
      attendancePercentage: s.finalPercentage,
      attendancePercentageWithoutDutyLeave: s.percentageWithoutDL,
    );
  }
}
