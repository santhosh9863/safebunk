import 'package:dio/dio.dart';

import '../errors/app_exceptions.dart';

class ApiResponseValidator {
  ApiResponseValidator._();

  static void validateContentType(Response response) {
    final contentType = response.headers.value('content-type');
    if (contentType == null || !contentType.contains('application/json')) {
      throw BadResponseException(
        'Invalid content-type: "${contentType ?? 'none'}". Expected application/json.',
      );
    }
  }

  static Map<String, dynamic> validateAndParse(dynamic data) {
    if (data == null) {
      throw const InvalidDataException('Response data is null');
    }
    if (data is! Map<String, dynamic>) {
      throw const BadResponseException('Response data is not a valid object');
    }
    return data;
  }

  static T extractField<T>(
    Map<String, dynamic> data,
    String key, {
    T? fallback,
  }) {
    final value = data[key];
    if (value == null) {
      if (fallback != null) return fallback;
      throw InvalidDataException('Missing required field: $key');
    }
    if (value is! T) {
      if (fallback != null) return fallback;
      throw InvalidDataException(
        'Field "$key" has invalid type. Expected ${T.toString()}, got ${value.runtimeType}',
      );
    }
    return value;
  }

  static String extractString(Map<String, dynamic> data, String key, {String fallback = ''}) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static int extractInt(Map<String, dynamic> data, String key, {int fallback = 0}) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double extractDouble(Map<String, dynamic> data, String key, {double fallback = 0.0}) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool extractBool(Map<String, dynamic> data, String key, {bool fallback = false}) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is int) return value == 1;
    return fallback;
  }

  static List<T> extractList<T>(
    Map<String, dynamic> data,
    String key, {
    T Function(dynamic)? castFn,
  }) {
    final value = data[key];
    if (value == null) return [];
    if (value is! List) return [];
    if (castFn == null) return value.cast<T>();
    return value.map((e) => castFn(e)).toList();
  }

  static Map<String, dynamic>? extractMap(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) return null;
    return value;
  }

  static bool isSuccessResponse(Map<String, dynamic> data) {
    return extractBool(data, 'success');
  }

  static String? extractMessage(Map<String, dynamic> data) {
    return data['message'] as String? ?? data['error'] as String? ?? data['detail'] as String?;
  }
}
