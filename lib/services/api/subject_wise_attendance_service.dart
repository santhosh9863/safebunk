import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_response_validator.dart';
import '../../core/network/dio_client.dart';
import '../../models/api/subject_wise_attendance_model.dart';
import 'attendance_terms_service.dart';

class SubjectWiseAttendanceService {
  final Dio _dio;
  final AttendanceTermsService _termsService;

  SubjectWiseAttendanceService({AttendanceTermsService? termsService})
      : _dio = DioClient.instance.dio,
        _termsService = termsService ?? AttendanceTermsService();

  Future<List<SubjectWiseAttendanceModel>> fetchSubjectWiseAttendance({
    required String studentId,
    String? termId,
    String? startDate,
    String? endDate,
  }) async {
    var resolvedTermId = termId;
    var resolvedStartDate = startDate;
    var resolvedEndDate = endDate;

    if (resolvedTermId == null) {
      final currentTerm = await _termsService.fetchCurrentTerm(studentId);
      if (currentTerm != null) {
        resolvedTermId = currentTerm.termId;
        resolvedStartDate = resolvedStartDate ?? currentTerm.startDate;
        resolvedEndDate = resolvedEndDate ?? currentTerm.endDate;
      }
    }

    if (resolvedTermId == null || resolvedTermId.isEmpty) {
      return [];
    }

    debugPrint('[Term] [subject-wise] outgoing request → termId=$resolvedTermId '
        'startDate=${resolvedStartDate ?? ''} endDate=${resolvedEndDate ?? ''}');

    final filter = {
      'firstTime': false,
      'termId': resolvedTermId,
      'startDate': resolvedStartDate,
      'endDate': resolvedEndDate,
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
