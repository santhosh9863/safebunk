class CourseAttendanceModel {
  final String subjectName;
  final int totalAttendance;
  final int totalPresent;
  final int totalAbsent;
  final int totalLeave;
  final int totalDutyLeave;
  final double attendancePercentage;
  final double attendancePercentageWithoutDutyLeave;

  const CourseAttendanceModel({
    required this.subjectName,
    required this.totalAttendance,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalLeave,
    required this.totalDutyLeave,
    required this.attendancePercentage,
    required this.attendancePercentageWithoutDutyLeave,
  });

  factory CourseAttendanceModel.fromJson(Map<String, dynamic> json) {
    return CourseAttendanceModel(
      subjectName: _s(json['subjectName']),
      totalAttendance: _i(json['totalAttendance']),
      totalPresent: _i(json['totalPresent']),
      totalAbsent: _i(json['totalAbsent']),
      totalLeave: _i(json['totalLeave']),
      totalDutyLeave: _i(json['totalDutyLeave']),
      attendancePercentage: _d(json['attendancePercentage']),
      attendancePercentageWithoutDutyLeave: _d(json['attendancePercentageWithoutDutyLeave']),
    );
  }

  Map<String, dynamic> toJson() => {
    'subjectName': subjectName,
    'totalAttendance': totalAttendance,
    'totalPresent': totalPresent,
    'totalAbsent': totalAbsent,
    'totalLeave': totalLeave,
    'totalDutyLeave': totalDutyLeave,
    'attendancePercentage': attendancePercentage,
    'attendancePercentageWithoutDutyLeave': attendancePercentageWithoutDutyLeave,
  };

  static String _s(dynamic v) => v is String ? v : (v?.toString() ?? '');
  static int _i(dynamic v) => v is int ? v : (v is double ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0));
  static double _d(dynamic v) => v is double ? v : (v is int ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0.0 : 0.0));
}
