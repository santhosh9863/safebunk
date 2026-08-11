import 'package:safebunk_shared/safebunk_shared.dart';
import '../core/api/http_client.dart';

class WebTimetableRepository extends TimetableRepository {
  WebTimetableRepository(this._client);

  final HttpClient _client;
  final Map<String, dynamic> _cache = {};
  DateTime? _todayCacheTime;
  static const _todayCacheTtl = Duration(minutes: 2);

  @override
  Future<List<TimetableEntry>> getTodaySchedule({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['today'] != null && _todayCacheTime != null) {
      if (DateTime.now().difference(_todayCacheTime!) < _todayCacheTtl) {
        return _cache['today'] as List<TimetableEntry>;
      }
    }

    final response = await _client.get('/timetable/today');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch today schedule');
    }

    final data = response.data;
    if (data is List) {
      final entries = data
          .map((e) => TimetableEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache['today'] = entries;
      _todayCacheTime = DateTime.now();
      return entries;
    }
    return [];
  }

  @override
  Future<List<TimetableDay>> getWeeklyTimetable({
    required String batchId,
    required String fromDate,
    required String toDate,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'weekly:$batchId:$fromDate:$toDate';
    if (!forceRefresh && _cache[cacheKey] != null) {
      return _cache[cacheKey] as List<TimetableDay>;
    }

    final response = await _client.get(
      '/timetable/weekly',
      queryParams: {
        'batchId': batchId,
        'fromDate': fromDate,
        'toDate': toDate,
      },
    );

    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch weekly timetable');
    }

    final data = response.data;
    if (data is List) {
      final days = data
          .map((e) => TimetableDay.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache[cacheKey] = days;
      return days;
    }
    return [];
  }

  @override
  Future<List<DayHourModel>> getDayHours({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['dayHours'] != null) {
      return _cache['dayHours'] as List<DayHourModel>;
    }

    final response = await _client.get('/timetable/day-hours');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch day hours');
    }

    final data = response.data;
    if (data is List) {
      final hours = data
          .map((e) => DayHourModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache['dayHours'] = hours;
      return hours;
    }
    return [];
  }

  @override
  Future<List<DayOrderModel>> getDayOrders({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['dayOrders'] != null) {
      return _cache['dayOrders'] as List<DayOrderModel>;
    }

    final response = await _client.get('/timetable/day-orders');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch day orders');
    }

    final data = response.data;
    if (data is List) {
      final orders = data
          .map((e) => DayOrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache['dayOrders'] = orders;
      return orders;
    }
    return [];
  }
}
