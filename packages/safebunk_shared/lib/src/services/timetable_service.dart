import '../models/api_response.dart';
import '../models/timetable/timetable.dart';

abstract class TimetableService {
  Future<ApiResponse<List<TimetableEntry>>> getTodaySchedule();
  Future<ApiResponse<List<TimetableDay>>> getWeeklyTimetable({
    required String batchId,
    required String fromDate,
    required String toDate,
  });
  Future<ApiResponse<List<DayHourModel>>> getDayHours();
  Future<ApiResponse<List<DayOrderModel>>> getDayOrders();
}
