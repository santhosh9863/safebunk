import '../models/api_response.dart';

abstract class ApiClient {
  Future<ApiResponse<dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  });

  Future<ApiResponse<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return request('GET', path, queryParams: queryParams, headers: headers);
  }

  Future<ApiResponse<dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    return request('POST', path, body: body, headers: headers);
  }
}
