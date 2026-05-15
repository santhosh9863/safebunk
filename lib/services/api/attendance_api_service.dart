import 'package:dio/dio.dart';

import '../../core/errors/api_exception.dart';
import '../../models/api/daily_attendance_model.dart';

class AttendanceApiService {
  final Dio _dio;

  AttendanceApiService(this._dio);

  Future<List<DailyAttendanceModel>> fetchDailyAttendance({
    required String studentId,
    String fromDate = '2026-02-03',
    String toDate = '2026-05-30',
  }) async {
    try {
      final response = await _dio.get(
        '/attendance/daily-attendance',
        queryParameters: {
          'toDate': toDate,
          'fromDate': fromDate,
          'emitAsResetWhileReset': 'true',
          'studentId': studentId,
        },
      );
      return _parseDailyResponse(response.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  List<DailyAttendanceModel> _parseDailyResponse(dynamic data) {
    if (data == null) return [];

    Map<String, dynamic>? innerData;
    if (data is Map<String, dynamic> && data['data'] is Map) {
      innerData = Map<String, dynamic>.from(data['data'] as Map);
    }
    if (innerData == null) return [];
    if (innerData['report'] is! List) return [];

    final reportList = innerData['report'] as List;
    final models = <DailyAttendanceModel>[];

    for (final reportEntry in reportList) {
      if (reportEntry is! Map) continue;
      final date = _s(reportEntry['attendance_date']);
      final hourDetailsList = reportEntry['hourDetails'];
      if (hourDetailsList is! List) continue;

      for (final hourEntry in hourDetailsList) {
        if (hourEntry is! Map) continue;
        final subjectDetailsList = hourEntry['subjectDetails'];
        if (subjectDetailsList is! List) continue;

        for (final subjectEntry in subjectDetailsList) {
          if (subjectEntry is! Map) continue;
          models.add(DailyAttendanceModel(
            attendanceDate: date,
            subjectName: _s(subjectEntry['subjectName'], 'Unknown'),
            attendanceStatus: _s(subjectEntry['attendanceStatus'], '0'),
            staffName: _s(subjectEntry['staffName']),
          ));
        }
      }
    }

    return models;
  }

  static String _s(dynamic v, [String fallback = '']) =>
      v is String ? v : (v?.toString() ?? fallback);

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutException('Connection timed out');
      case DioExceptionType.connectionError:
        return const NetworkException('No internet connection');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final msg = e.response?.data is Map
            ? (e.response?.data as Map)['message']?.toString()
            : null;
        return switch (code) {
          401 => UnauthorizedException(msg ?? 'Session expired'),
          _ => ServerException(msg ?? 'Request failed', statusCode: code),
        };
      default:
        return const UnknownException('An unexpected error occurred');
    }
  }
}
