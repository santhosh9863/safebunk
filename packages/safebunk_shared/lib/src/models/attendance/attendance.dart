class DailyAttendance {
  final String attendanceDate;
  final String subjectName;
  final String attendanceStatus;
  final String staffName;

  const DailyAttendance({
    required this.attendanceDate,
    required this.subjectName,
    required this.attendanceStatus,
    required this.staffName,
  });

  bool get isPresent => attendanceStatus == '1';
  bool get isAbsent => attendanceStatus == '0';
  bool get isLeave => attendanceStatus == '2';
  bool get isDutyLeave => attendanceStatus == '3';

  factory DailyAttendance.fromJson(Map<String, dynamic> json) => DailyAttendance(
    attendanceDate: _pick(json, ['attendanceDate', 'attendance_date', 'date']),
    subjectName: _pick(json, ['subjectName', 'subject_name', 'subject']),
    attendanceStatus: _pick(json, ['attendanceStatus', 'attendance_status', 'status']),
    staffName: _pick(json, ['staffName', 'staff_name', 'staff']),
  );

  Map<String, dynamic> toJson() => {
    'attendanceDate': attendanceDate,
    'subjectName': subjectName,
    'attendanceStatus': attendanceStatus,
    'staffName': staffName,
  };

  static String _pick(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v is String) return v;
      if (v is num) return v.toString();
    }
    return '';
  }
}

class SubjectAttendance {
  final String subjectName;
  final int totalHours;
  final int attendedHours;
  final int dutyLeave;
  final int effectivePresent;
  final double percentageWithoutDL;
  final double finalPercentage;

  const SubjectAttendance({
    required this.subjectName,
    required this.totalHours,
    required this.attendedHours,
    required this.dutyLeave,
    required this.effectivePresent,
    required this.percentageWithoutDL,
    required this.finalPercentage,
  });

  factory SubjectAttendance.fromJson(Map<String, dynamic> json) {
    return SubjectAttendance(
      subjectName: _s(json['subjectName']) ?? _s(json['courseName']) ?? '',
      totalHours: _i(json['totalHours']) ?? _i(json['totalAttendance']) ?? 0,
      attendedHours: _i(json['attendedHours']) ?? _i(json['totalPresentMarkHour']) ?? 0,
      dutyLeave: _i(json['dutyLeave']) ?? _i(json['totalDutyleave']) ?? _i(json['totalDutyLeave']) ?? 0,
      effectivePresent: _i(json['effectivePresent']) ?? _i(json['totalPresent']) ?? 0,
      percentageWithoutDL: _d(json['percentageWithoutDL']) ?? _d(json['attendancePercentagewithoutDutyLeave']) ?? _d(json['attendancePercentageWithoutDutyLeave']) ?? 0.0,
      finalPercentage: _d(json['finalPercentage']) ?? _d(json['attendancePercentage']) ?? 0.0,
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
