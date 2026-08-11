import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_response_validator.dart';
import '../../core/network/dio_client.dart';
import '../../models/api/timetable_model.dart';

class TimetableApiService {
  final Dio _dio;

  TimetableApiService() : _dio = DioClient.instance.dio;

  Future<List<TimetableDay>> fetchWeeklyTimetable({
    required String batchId,
    required String fromDate,
    required String toDate,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.timetable,
        queryParameters: {
          ApiConstants.batchId: batchId,
          ApiConstants.fromDate: fromDate,
          ApiConstants.toDate: toDate,
          ApiConstants.getDaywise: true,
        },
        options: Options(
          headers: {
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );

      ApiResponseValidator.validateContentType(response);
      return _parseWeeklyTimetable(response.data);
    } on DioException catch (e) {
      debugPrint('[API] weekly timetable failed: ${e.response?.statusCode}');
      throw mapDioException(e);
    }
  }

  Future<List<TimetableDay>> fetchDailyTimetable({
    required String batchId,
    required String date,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.timetable,
        queryParameters: {
          ApiConstants.batchId: batchId,
          ApiConstants.fromDate: date,
          ApiConstants.toDate: date,
          ApiConstants.getDaywise: true,
        },
        options: Options(
          headers: {
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );

      ApiResponseValidator.validateContentType(response);
      return _parseWeeklyTimetable(response.data);
    } on DioException catch (e) {
      debugPrint('[API] daily timetable failed: ${e.response?.statusCode}');
      throw mapDioException(e);
    }
  }

  Future<List<TimetableEntry>> fetchTodaySchedule() async {
    try {
      final response = await _dio.get(
        ApiConstants.studentDailySchedule,
        options: Options(
          headers: {
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );

      ApiResponseValidator.validateContentType(response);
      return _parseDailySchedule(response.data);
    } on DioException catch (e) {
      debugPrint('[API] daily schedule failed: ${e.response?.statusCode}');
      throw mapDioException(e);
    }
  }

  Future<List<DayHourModel>> fetchDayHours() async {
    try {
      final response = await _dio.get(
        ApiConstants.timetableDayHours,
        options: Options(
          headers: {
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );

      ApiResponseValidator.validateContentType(response);
      final rawData = response.data;
      if (rawData is! Map<String, dynamic>) return [];
      final data = rawData['data'];
      if (data is! List) return [];
      return data
          .map((e) => DayHourModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on DioException catch (e) {
      debugPrint('[API] day hours failed: ${e.response?.statusCode}');
      throw mapDioException(e);
    }
  }

  List<TimetableDay> _parseWeeklyTimetable(dynamic rawData) {
    if (rawData is! Map<String, dynamic>) return [];
    if (rawData['status'] != 'success') return [];
    final data = rawData['data'];
    if (data is! List) return [];
    return data
        .map((e) => TimetableDay.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<TimetableEntry> _parseDailySchedule(dynamic rawData) {
    if (rawData is! Map<String, dynamic>) return [];
    if (rawData['success'] != true) return [];
    final data = rawData['data'];
    if (data is! Map<String, dynamic>) return [];
    final classes = data['classes'];
    if (classes is! List) return [];
    return classes
        .map((e) => TimetableEntry.fromTimeTableJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
