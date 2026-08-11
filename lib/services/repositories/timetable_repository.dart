import '../../core/cache/memory_cache.dart';
import '../../core/cache/persistent_cache.dart';
import '../../models/api/timetable_model.dart';
import '../api/timetable_api_service.dart';

class TimetableRepository {
  final TimetableApiService _service;
  final MemoryCache<List<TimetableDay>> _weeklyCache;
  final MemoryCache<List<TimetableEntry>> _todayCache;

  TimetableRepository({
    required TimetableApiService service,
    required MemoryCache<List<TimetableDay>> weeklyCache,
    required MemoryCache<List<TimetableEntry>> todayCache,
  })  : _service = service,
        _weeklyCache = weeklyCache,
        _todayCache = todayCache;

  Future<List<TimetableDay>> fetchWeeklyTimetable({
    required String batchId,
    required String fromDate,
    required String toDate,
  }) async {
    final cacheKey = 'weekly_${batchId}_${fromDate}_$toDate';

    final cached = _weeklyCache.get(cacheKey);
    if (cached != null) return cached;

    final persisted = PersistentCache.getTimetable(
      cacheKey,
      TimetableDay.fromJson,
    );
    if (persisted != null) {
      _weeklyCache.set(cacheKey, persisted);
      return persisted;
    }

    final result = await _service.fetchWeeklyTimetable(
      batchId: batchId,
      fromDate: fromDate,
      toDate: toDate,
    );

    _weeklyCache.set(cacheKey, result);
    await _persistTimetable(cacheKey, result);
    return result;
  }

  Future<List<TimetableEntry>> fetchTodaySchedule() async {
    const cacheKey = 'today_schedule';

    final cached = _todayCache.get(cacheKey);
    if (cached != null) return cached;

    final result = await _service.fetchTodaySchedule();
    _todayCache.set(cacheKey, result);
    return result;
  }

  Future<List<DayHourModel>> fetchDayHours() async {
    return _service.fetchDayHours();
  }

  void clearCache() {
    _weeklyCache.clear();
    _todayCache.clear();
  }

  Future<void> _persistTimetable(String key, List<TimetableDay> days) async {
    final jsonList = days.map((d) => {
      'date': d.date,
      'day': d.day,
      'dayName': d.dayName,
      'hours': d.hours.map((h) => {
        'hour': h.hour,
        'hourName': h.hourName,
        'timeTables': h.timeTables.map((t) => {
          'id': t.id,
          'staffId': t.staffId,
          'day': t.day,
          'hour': t.hour,
          'fromTime': t.fromTime,
          'toTime': t.toTime,
          'date': t.date,
          'subjects': [{'code': t.subjectCode, 'name': t.subjectName}],
          'batches': t.batches.map((b) => {'id': b.id, 'name': b.name}).toList(),
          'isOpenToAll': t.isOpenToAll ? '1' : '0',
          'attendanceMarked': t.attendanceMarked,
        }).toList(),
      }).toList(),
    }).toList();
    await PersistentCache.setTimetable(key, jsonList);
  }
}
