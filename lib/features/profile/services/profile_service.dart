import 'package:dio/dio.dart';

import '../../../../core/errors/api_exception.dart';
import '../models/student_profile.dart';

class ProfileService {
  final Dio _dio;

  ProfileService({required Dio dio}) : _dio = dio;

  Future<StudentProfile> fetchProfile(String studentId) async {
    try {
      final response = await _dio.get(
        '/student/get-student-basic-details',
        queryParameters: {'studentId': studentId},
      );

      if (response.data is! Map) {
        throw const ServerException('Invalid profile response');
      }

      return StudentProfile.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutException('Connection timed out');
      case DioExceptionType.connectionError:
        return const NetworkException('No internet connection');
      case DioExceptionType.badResponse:
        return switch (e.response?.statusCode) {
          401 => const UnauthorizedException('Session expired'),
          500 => const ServerException('Server error'),
          _ => const ServerException('Request failed'),
        };
      default:
        return const UnknownException('An unexpected error occurred');
    }
  }
}
