class SubjectWiseAttendanceModel {
  final String subjectName;
  final int totalHours;
  final int attendedHours;
  final int dutyLeave;
  final int effectivePresent;
  final double percentageWithoutDL;
  final double finalPercentage;

  const SubjectWiseAttendanceModel({
    required this.subjectName,
    required this.totalHours,
    required this.attendedHours,
    required this.dutyLeave,
    required this.effectivePresent,
    required this.percentageWithoutDL,
    required this.finalPercentage,
  });

  factory SubjectWiseAttendanceModel.fromJson(Map<String, dynamic> json) {
    final subjectName = _s(json['courseName']) ?? _s(json['subjectName']) ?? '';
    final totalHours = _i(json['totalAttendance']);
    final attendedHours = _i(json['totalPresentMarkHour']);
    final dutyLeave = _i(json['totalDutyleave']) ?? _i(json['totalDutyLeave']);
    final effectivePresent = _i(json['totalPresent']);
    final pctWithoutDL = _d(json['attendancePercentagewithoutDutyLeave']) ?? _d(json['attendancePercentageWithoutDutyLeave']);
    final finalPct = _d(json['attendancePercentage']);

    return SubjectWiseAttendanceModel(
      subjectName: subjectName,
      totalHours: totalHours ?? 0,
      attendedHours: attendedHours ?? 0,
      dutyLeave: dutyLeave ?? 0,
      effectivePresent: effectivePresent ?? 0,
      percentageWithoutDL: pctWithoutDL ?? 0.0,
      finalPercentage: finalPct ?? 0.0,
    );
  }

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
  static int? _i(dynamic v) => v is int ? v : (v is double ? v.toInt() : (v is String ? int.tryParse(v) : null));
  static double? _d(dynamic v) => v is double ? v : (v is int ? v.toDouble() : (v is String ? double.tryParse(v) : null));
}
