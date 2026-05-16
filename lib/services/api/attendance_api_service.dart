import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_response_validator.dart';
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
        ApiConstants.dailyAttendance,
        queryParameters: {
          'toDate': toDate,
          'fromDate': fromDate,
          'emitAsResetWhileReset': 'true',
          'studentId': studentId,
        },
      );

      ApiResponseValidator.validateContentType(response);
      return _parseDailyResponse(response.data);
    } on DioException catch (e) {
      debugPrint('[API] daily attendance failed: ${e.response?.statusCode}');
      throw mapDioException(e);
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
          final status = _s(subjectEntry['attendanceStatus'], '');
          final subject = _s(subjectEntry['subjectName'], 'Unknown');
          models.add(DailyAttendanceModel(
            attendanceDate: date,
            subjectName: subject,
            attendanceStatus: status.isNotEmpty ? status : '0',
            staffName: _s(subjectEntry['staffName']),
          ));
        }
      }
    }

    return models;
  }

  static String _s(dynamic v, [String fallback = '']) =>
      v is String ? v : (v?.toString() ?? fallback);
}
