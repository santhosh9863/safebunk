import '../models/api_response.dart';
import '../models/attendance/attendance.dart';

abstract class AttendanceService {
  Future<ApiResponse<List<DailyAttendance>>> getDailyAttendance();
  Future<ApiResponse<List<SubjectAttendance>>> getSubjectAttendance();
}
