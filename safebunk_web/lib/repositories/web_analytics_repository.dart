import 'package:safebunk_shared/safebunk_shared.dart';
import '../core/api/http_client.dart';

class WebAnalyticsRepository extends AnalyticsRepository {
  WebAnalyticsRepository(this._client);

  final HttpClient _client;
  ConsolidatedAnalytics? _cached;
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  @override
  Future<ConsolidatedAnalytics> getAnalytics({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _cached!;
      }
    }

    final response = await _client.get('/analytics');
    if (!response.success || response.data == null) {
      throw Exception(response.message ?? 'Failed to fetch analytics');
    }

    _cached = ConsolidatedAnalytics.fromJson(response.data as Map<String, dynamic>);
    _cacheTime = DateTime.now();
    return _cached!;
  }

  @override
  Future<List<HourWiseAttendance>> getHourWiseAttendance({bool forceRefresh = false}) async {
    final response = await _client.get('/analytics/hour-wise');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch hour-wise attendance');
    }

    final data = response.data;
    if (data is List) {
      return data
          .map((e) => HourWiseAttendance.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }
}
