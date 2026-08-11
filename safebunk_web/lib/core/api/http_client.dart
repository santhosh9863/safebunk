import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:safebunk_shared/safebunk_shared.dart';
import 'api_config.dart';

class HttpClient extends ApiClient {
  HttpClient() : _client = http.Client();

  final http.Client _client;
  String? _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  @override
  Future<ApiResponse<dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${ApiConfig.apiBaseUrl}$path').replace(
      queryParameters: queryParams?.map((k, v) => MapEntry(k, v.toString())),
    );

    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      ...?headers,
    };

    late http.Response response;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(uri, headers: requestHeaders);
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await _client.put(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: requestHeaders);
          break;
        default:
          return ApiResponse(success: false, message: 'Unsupported method: $method', statusCode: 400);
      }
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Network error: ${e.toString()}',
        statusCode: 0,
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse(
        success: json['success'] as bool? ?? response.statusCode == 200,
        data: json['data'],
        message: json['message'] as String?,
        statusCode: json['statusCode'] as int? ?? response.statusCode,
      );
    } catch (_) {
      return ApiResponse(
        success: response.statusCode == 200,
        data: response.body,
        message: response.statusCode != 200 ? 'Request failed: ${response.statusCode}' : null,
        statusCode: response.statusCode,
      );
    }
  }
}
