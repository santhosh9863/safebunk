import 'package:dio/dio.dart';

import '../../core/errors/api_exception.dart';
import '../../models/api/login_request.dart';
import '../../models/api/login_response.dart';

class AuthApiService {
  final Dio _dio;

  AuthApiService(this._dio);

  Future<LoginResponse> login(LoginRequest request) async {
    try {
      final response = await _dio.post(
        '/auth/student-login-credentials',
        data: request.toJson(),
      );

      final cookies = _extractCookies(response);

      final loginResponse = response.data is Map<String, dynamic>
          ? LoginResponse.fromJson(response.data as Map<String, dynamic>)
          : const LoginResponse(success: true);

      return loginResponse.copyWith(cookies: cookies);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  String? _extractCookies(Response response) {
    final rawHeaders = response.headers['set-cookie'];
    if (rawHeaders == null || rawHeaders.isEmpty) return null;

    final cookieValues = rawHeaders.map((header) {
      final semicolonIndex = header.indexOf(';');
      if (semicolonIndex == -1) return header.trim();
      return header.substring(0, semicolonIndex).trim();
    });

    return cookieValues.join('; ');
  }

  Exception _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('Connection timed out. Please try again.');
      case DioExceptionType.connectionError:
        return const NetworkException('No internet connection.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = switch (statusCode) {
          401 => 'Invalid credentials. Please try again.',
          500 => 'Server error. Please try again later.',
          _ => e.response?.data?['message'] as String? ?? 'Something went wrong.',
        };
        return ServerException(message, statusCode: statusCode);
      case DioExceptionType.cancel:
        return const NetworkException('Request was cancelled.');
      default:
        return const NetworkException('An unexpected error occurred.');
    }
  }
}
