import 'package:dio/dio.dart';

sealed class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class NetworkException extends ApiException {
  const NetworkException(super.message, {super.statusCode});
}

class TimeoutException extends ApiException {
  const TimeoutException(super.message, {super.statusCode});
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message, {super.statusCode});
}

class SessionExpiredException extends UnauthorizedException {
  const SessionExpiredException([super.message = 'Session expired. Please login again.']);
}

class TokenExpiredException extends UnauthorizedException {
  const TokenExpiredException([super.message = 'Token expired. Please login again.']);
}

class ServerException extends ApiException {
  const ServerException(super.message, {super.statusCode});
}

class InvalidDataException extends ApiException {
  const InvalidDataException(super.message, {super.statusCode});
}

class BadResponseException extends InvalidDataException {
  const BadResponseException([super.message = 'Invalid response format from server']);
}

class UnknownException extends ApiException {
  const UnknownException(super.message, {super.statusCode});
}

ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const TimeoutException('Connection timed out. Please try again.');
    case DioExceptionType.connectionError:
      return const NetworkException('No internet connection. Check your network.');
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final message = _extractMessage(body);
      return switch (code) {
        401 => SessionExpiredException(message ?? 'Session expired. Please login again.'),
        403 => UnauthorizedException(message ?? 'Access denied.'),
        404 => ServerException('Resource not found.', statusCode: code),
        422 || 400 => ServerException(message ?? 'Invalid request.', statusCode: code),
        500 => ServerException('Server error. Please try again later.', statusCode: code),
        _ => ServerException(message ?? 'Something went wrong.', statusCode: code),
      };
    case DioExceptionType.cancel:
      return const NetworkException('Request was cancelled.');
    default:
      return const UnknownException('An unexpected error occurred.');
  }
}

String? _extractMessage(dynamic body) {
  if (body is Map<String, dynamic>) {
    final message = body['message'] ?? body['error'] ?? body['detail'];
    return message?.toString();
  }
  if (body is String) return body;
  return null;
}
