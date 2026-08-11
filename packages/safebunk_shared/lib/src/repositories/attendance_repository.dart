import '../models/attendance/attendance.dart';

abstract class AttendanceRepository {
  Future<List<DailyAttendance>> getDailyAttendance({bool forceRefresh = false});
  Future<List<SubjectAttendance>> getSubjectAttendance({bool forceRefresh = false});
}
