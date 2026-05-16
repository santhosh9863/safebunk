import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_response_validator.dart';
import '../../core/network/dio_client.dart';
import '../../models/api/subject_wise_attendance_model.dart';

class SubjectWiseAttendanceService {
  final Dio _dio;

  SubjectWiseAttendanceService() : _dio = DioClient.instance.dio;

  Future<List<SubjectWiseAttendanceModel>> fetchSubjectWiseAttendance({
    required String studentId,
    String termId = '4',
    String startDate = '2026-02-03',
    String endDate = '2026-05-30',
  }) async {
    final filter = {
      'firstTime': false,
      'termId': termId,
      'startDate': startDate,
      'endDate': endDate,
      'studentId': studentId,
      'academicStatus': 'ACTIVE',
      'mapping': 'STUDENT-SUBJECT-WISE',
    };

    final filterJson = jsonEncode(filter);

    try {
      final requestOptions = Options(
        headers: {
          'X-Menu-Code': 'STUDENT_SUBJECT_WISE_ATTENDANCE_METHOD',
          'Referer': 'https://sfcv4.linways.com/academics/',
          'Accept': 'application/json, text/plain, */*',
        },
      );

      final response = await _dio.get(
        ApiConstants.subjectWiseAttendance,
        queryParameters: {'filter': filterJson},
        options: requestOptions,
      );

      ApiResponseValidator.validateContentType(response);
      final parsed = _parseResponse(response.data);

      return parsed;
    } on DioException catch (e) {
      debugPrint('[API] subject-wise attendance failed: ${e.response?.statusCode}');
      throw mapDioException(e);
    }
  }

  List<SubjectWiseAttendanceModel> _parseResponse(dynamic rawData) {
    if (rawData is! Map<String, dynamic>) return [];

    if (rawData['data'] is! Map<String, dynamic>) return [];
    final inner = rawData['data'] as Map<String, dynamic>;

    if (inner['termDetails'] is! List) return [];
    final termList = inner['termDetails'] as List;
    if (termList.isEmpty) return [];

    return termList
        .map((e) {
          if (e is! Map) return null;
          return SubjectWiseAttendanceModel.fromJson(Map<String, dynamic>.from(e));
        })
        .whereType<SubjectWiseAttendanceModel>()
        .toList();
  }
}
