import 'package:safebunk_shared/safebunk_shared.dart';
import '../core/api/http_client.dart';

class WebAttendanceRepository extends AttendanceRepository {
  WebAttendanceRepository(this._client);

  final HttpClient _client;
  List<DailyAttendance>? _dailyCache;
  List<SubjectAttendance>? _subjectCache;
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  @override
  Future<List<DailyAttendance>> getDailyAttendance({bool forceRefresh = false}) async {
    if (!forceRefresh && _dailyCache != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _dailyCache!;
      }
    }

    final response = await _client.get('/attendance/daily');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch daily attendance');
    }

    final data = response.data;
    if (data is List) {
      _dailyCache = data
          .map((e) => DailyAttendance.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      _dailyCache = [];
    }
    _cacheTime = DateTime.now();
    return _dailyCache!;
  }

  @override
  Future<List<SubjectAttendance>> getSubjectAttendance({bool forceRefresh = false}) async {
    if (!forceRefresh && _subjectCache != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _subjectCache!;
      }
    }

    final response = await _client.get('/attendance/subjects');
    if (!response.success) {
      throw Exception(response.message ?? 'Failed to fetch subject attendance');
    }

    final data = response.data;
    if (data is List) {
      _subjectCache = data
          .map((e) => SubjectAttendance.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      _subjectCache = [];
    }
    _cacheTime = DateTime.now();
    return _subjectCache!;
  }
}
