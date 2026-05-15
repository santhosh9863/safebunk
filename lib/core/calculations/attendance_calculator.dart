import 'attendance_analysis.dart';
import 'attendance_rules.dart';
import 'attendance_utils.dart';

class AttendanceCalculator {
  AttendanceCalculator._();

  static AttendanceAnalysis analyzeAttendance({
    required int presentHours,
    required int totalHours,
    required int dutyLeaveHours,
  }) {
    final p = AttendanceUtils.clampIntToZero(presentHours);
    final t = AttendanceUtils.clampIntToZero(totalHours);
    final d = AttendanceUtils.clampIntToZero(dutyLeaveHours);

    final percentage = _calculatePercentage(p, t);
    final percentageWithoutDL = _calculatePercentageWithoutDutyLeave(p, t, d);
    final safeBunks = _calculateSafeBunks(p, t);
    final requiredClasses = _calculateRequiredClasses(p, t);

    return AttendanceAnalysis(
      percentage: percentage,
      safeBunks: safeBunks,
      requiredClasses: requiredClasses,
      isDanger: percentage < AttendanceRules.dangerAttendance,
      isWarning: percentage >= AttendanceRules.dangerAttendance &&
          percentage < AttendanceRules.warningAttendance,
      isSafe: percentage >= AttendanceRules.warningAttendance,
      presentHours: p,
      totalHours: t,
      dutyLeaveHours: d,
      attendanceWithoutDutyLeave: percentageWithoutDL,
    );
  }

  static double _calculatePercentage(int present, int total) {
    if (total == 0) return 0.0;
    final raw = AttendanceUtils.safeDivide(present.toDouble(), total.toDouble()) * 100;
    return AttendanceUtils.roundPercentage(AttendanceUtils.clampPercentage(raw));
  }

  static double _calculatePercentageWithoutDutyLeave(
    int present,
    int total,
    int dutyLeave,
  ) {
    final adjustedTotal = total - dutyLeave;
    if (adjustedTotal <= 0) return 100.0;
    final raw = AttendanceUtils.safeDivide(present.toDouble(), adjustedTotal.toDouble()) * 100;
    return AttendanceUtils.roundPercentage(AttendanceUtils.clampPercentage(raw));
  }

  static int _calculateSafeBunks(int present, int total) {
    if (total == 0) return 0;
    final m = AttendanceRules.minimumAttendance / 100;
    final ratio = present / m - total;
    if (ratio <= 0) return 0;
    return ratio.floor();
  }

  static int _calculateRequiredClasses(int present, int total) {
    if (total == 0) return 0;
    final m = AttendanceRules.minimumAttendance / 100;
    final needed = (total * m - present) / (1 - m);
    if (needed <= 0) return 0;
    return needed.ceil();
  }
}
