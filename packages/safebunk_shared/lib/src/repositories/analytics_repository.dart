import '../models/analytics/analytics.dart';

abstract class AnalyticsRepository {
  Future<ConsolidatedAnalytics> getAnalytics({bool forceRefresh = false});
  Future<List<HourWiseAttendance>> getHourWiseAttendance({bool forceRefresh = false});
}
