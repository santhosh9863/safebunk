class DailyAttendanceModel {
  final String attendanceDate;
  final String subjectName;
  final String attendanceStatus;
  final String staffName;

  const DailyAttendanceModel({
    required this.attendanceDate,
    required this.subjectName,
    required this.attendanceStatus,
    required this.staffName,
  });

  /// Status 1 = Present
  bool get isPresent => attendanceStatus == '1';

  /// Status 0 = Absent
  bool get isAbsent => attendanceStatus == '0';

  /// Status 2 = Approved Leave (leave granted by college)
  bool get isLeave => attendanceStatus == '2';

  /// Status 3 = Duty Leave (official college duty — counts as present in some colleges)
  bool get isDutyLeave => attendanceStatus == '3';

  factory DailyAttendanceModel.fromJson(Map<String, dynamic> json) {
    final date = _pick(json, ['attendance_date', 'attendanceDate', 'date']);
    final subject = _pick(json, ['subjectName', 'subject_name', 'subject']);
    final status = _pick(json, ['attendanceStatus', 'attendance_status', 'status']);
    final staff = _pick(json, ['staffName', 'staff_name', 'staff']);

    return DailyAttendanceModel(
      attendanceDate: date,
      subjectName: subject.isNotEmpty ? subject : 'Unknown',
      attendanceStatus: status.isNotEmpty ? status : '0',
      staffName: staff,
    );
  }

  static String _pick(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v is String) return v;
      if (v is num) return v.toString();
    }
    return '';
  }
}
