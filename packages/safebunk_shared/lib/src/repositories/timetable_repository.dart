import '../models/timetable/timetable.dart';

abstract class TimetableRepository {
  Future<List<TimetableEntry>> getTodaySchedule({bool forceRefresh = false});
  Future<List<TimetableDay>> getWeeklyTimetable({
    required String batchId,
    required String fromDate,
    required String toDate,
    bool forceRefresh = false,
  });
  Future<List<DayHourModel>> getDayHours({bool forceRefresh = false});
  Future<List<DayOrderModel>> getDayOrders({bool forceRefresh = false});
}
