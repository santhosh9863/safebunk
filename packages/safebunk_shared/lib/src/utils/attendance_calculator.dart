import '../models/attendance/attendance.dart';

class AttendanceCalculator {
  AttendanceCalculator._();

  static double calculatePercentage(int attended, int total) {
    if (total <= 0) return 0.0;
    return (attended / total) * 100;
  }

  static int totalAttended(List<DailyAttendance> records) {
    return records.where((r) => r.isPresent || r.isDutyLeave).length;
  }

  static int totalAbsent(List<DailyAttendance> records) {
    return records.where((r) => r.isAbsent).length;
  }

  static int totalLeave(List<DailyAttendance> records) {
    return records.where((r) => r.isLeave || r.isDutyLeave).length;
  }

  static double overallPercentage(List<DailyAttendance> records) {
    if (records.isEmpty) return 0.0;
    final attended = totalAttended(records);
    return calculatePercentage(attended, records.length);
  }

  static List<SubjectAttendance> aggregateBySubject(List<DailyAttendance> records) {
    final grouped = <String, List<DailyAttendance>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.subjectName, () => []).add(record);
    }

    return grouped.entries.map((entry) {
      final subjectRecords = entry.value;
      final total = subjectRecords.length;
      final attended = subjectRecords.where((r) => r.isPresent).length;
      final dutyLeave = subjectRecords.where((r) => r.isDutyLeave).length;
      final effectivePresent = attended + dutyLeave;
      final pctNoDL = calculatePercentage(attended, total);
      final pctFinal = calculatePercentage(effectivePresent, total);

      return SubjectAttendance(
        subjectName: entry.key,
        totalHours: total,
        attendedHours: attended,
        dutyLeave: dutyLeave,
        effectivePresent: effectivePresent,
        percentageWithoutDL: pctNoDL,
        finalPercentage: pctFinal,
      );
    }).toList();
  }
}
