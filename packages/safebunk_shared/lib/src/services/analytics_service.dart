import '../models/api_response.dart';
import '../models/analytics/analytics.dart';

abstract class AnalyticsService {
  Future<ApiResponse<ConsolidatedAnalytics>> getAnalytics();
  Future<ApiResponse<List<HourWiseAttendance>>> getHourWiseAttendance();
}
