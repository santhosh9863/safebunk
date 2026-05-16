import 'package:dio/dio.dart';

import '../errors/app_exceptions.dart';
import '../session/session_manager.dart';
import 'api_constants.dart';

class DioClient {
  DioClient._();

  static final DioClient _instance = DioClient._();
  static DioClient get instance => _instance;

  static Future<void> Function()? sessionExpiredHandler;

  late final Dio dio;

  static DioClient init({SessionManager? sessionManager}) {
    _instance.dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    _instance.dio.interceptors.add(_AuthInterceptor(sessionManager));
    return _instance;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
  }) async {
    return _execute(() => dio.get<T>(path, queryParameters: queryParameters, data: data));
  }

  Future<Response<T>> post<T>(
    String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    return _execute(() => dio.post<T>(path, data: data, queryParameters: queryParameters));
  }

  Future<Response<T>> _execute<T>(
    Future<Response<T>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

String? _extractCookieValue(String cookies, String cookieName) {
  final pattern = RegExp('$cookieName=([^;]+)');
  final match = pattern.firstMatch(cookies);
  return match?.group(1);
}

class _AuthInterceptor extends Interceptor {
  final SessionManager? _sessionManager;
  _AuthInterceptor(this._sessionManager);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_sessionManager != null) {
      final cookies = await _sessionManager.getCookies();
      if (cookies != null && cookies.isNotEmpty) {
        options.headers[ApiConstants.cookieHeader] = cookies;

        final authSession = _extractCookieValue(cookies, ApiConstants.authSessionCookie);
        if (authSession != null && authSession.isNotEmpty) {
          if (!options.headers.containsKey(ApiConstants.authorizationHeader)) {
            options.headers[ApiConstants.authorizationHeader] =
                '${ApiConstants.bearerPrefix}$authSession';
          }
        }
      }
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await DioClient.sessionExpiredHandler?.call();
    }
    handler.next(err);
  }
}
