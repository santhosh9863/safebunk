class AttendanceAnalysis {
  final double percentage;
  final int safeBunks;
  final int requiredClasses;
  final bool isDanger;
  final bool isWarning;
  final bool isSafe;
  final int presentHours;
  final int totalHours;
  final int dutyLeaveHours;
  final double attendanceWithoutDutyLeave;

  const AttendanceAnalysis({
    required this.percentage,
    required this.safeBunks,
    required this.requiredClasses,
    required this.isDanger,
    required this.isWarning,
    required this.isSafe,
    required this.presentHours,
    required this.totalHours,
    required this.dutyLeaveHours,
    required this.attendanceWithoutDutyLeave,
  });

  AttendanceAnalysis copyWith({
    double? percentage,
    int? safeBunks,
    int? requiredClasses,
    bool? isDanger,
    bool? isWarning,
    bool? isSafe,
    int? presentHours,
    int? totalHours,
    int? dutyLeaveHours,
    double? attendanceWithoutDutyLeave,
  }) {
    return AttendanceAnalysis(
      percentage: percentage ?? this.percentage,
      safeBunks: safeBunks ?? this.safeBunks,
      requiredClasses: requiredClasses ?? this.requiredClasses,
      isDanger: isDanger ?? this.isDanger,
      isWarning: isWarning ?? this.isWarning,
      isSafe: isSafe ?? this.isSafe,
      presentHours: presentHours ?? this.presentHours,
      totalHours: totalHours ?? this.totalHours,
      dutyLeaveHours: dutyLeaveHours ?? this.dutyLeaveHours,
      attendanceWithoutDutyLeave:
          attendanceWithoutDutyLeave ?? this.attendanceWithoutDutyLeave,
    );
  }
}
