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
    final totalHours = _i(json['totalAttendance']) ?? _i(json['totalHours']) ?? 0;
    final attendedHours = _i(json['totalPresentMarkHour']) ?? _i(json['attendedHours']) ?? 0;
    final dutyLeave = _i(json['totalDutyleave']) ?? _i(json['totalDutyLeave']) ?? _i(json['dutyLeave']) ?? 0;
    final effectivePresent = _i(json['totalPresent']) ?? _i(json['effectivePresent']) ?? 0;
    final pctWithoutDL = _d(json['attendancePercentagewithoutDutyLeave']) ?? _d(json['attendancePercentageWithoutDutyLeave']) ?? _d(json['percentageWithoutDL']) ?? 0.0;
    final finalPct = _d(json['attendancePercentage']) ?? _d(json['finalPercentage']) ?? 0.0;

    return SubjectWiseAttendanceModel(
      subjectName: subjectName,
      totalHours: totalHours,
      attendedHours: attendedHours,
      dutyLeave: dutyLeave,
      effectivePresent: effectivePresent,
      percentageWithoutDL: pctWithoutDL,
      finalPercentage: finalPct,
    );
  }

  Map<String, dynamic> toJson() => {
    'subjectName': subjectName,
    'totalHours': totalHours,
    'attendedHours': attendedHours,
    'dutyLeave': dutyLeave,
    'effectivePresent': effectivePresent,
    'percentageWithoutDL': percentageWithoutDL,
    'finalPercentage': finalPercentage,
  };

  static String? _s(dynamic v) => v is String ? v : (v?.toString());
  static int? _i(dynamic v) => v is int ? v : (v is double ? v.toInt() : (v is String ? int.tryParse(v) : null));
  static double? _d(dynamic v) => v is double ? v : (v is int ? v.toDouble() : (v is String ? double.tryParse(v) : null));
}
