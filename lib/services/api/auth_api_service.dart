import 'package:dio/dio.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_response_validator.dart';
import '../../models/api/login_request.dart';
import '../../models/api/login_response.dart';

class AuthApiService {
  final Dio _dio;

  AuthApiService(this._dio);

  Future<LoginResponse> login(LoginRequest request) async {
    try {
      final response = await _dio.post(
        ApiConstants.login,
        data: request.toJson(),
      );

      ApiResponseValidator.validateContentType(response);
      final data = ApiResponseValidator.validateAndParse(response.data);
      final cookies = _extractCookies(response);

      final loginResponse = LoginResponse.fromJson(data);
      return loginResponse.copyWith(cookies: cookies);
    } on DioException catch (e) {
      throw mapDioException(e);
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
}
