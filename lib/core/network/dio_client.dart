import 'package:dio/dio.dart';

import '../../storage/session_storage.dart';
import '../errors/api_exception.dart';

class DioClient {
  DioClient._();

  static final DioClient _instance = DioClient._();
  static DioClient get instance => _instance;

  late final Dio dio;

  static DioClient init({SessionStorage? sessionStorage}) {
    _instance.dio = Dio(
      BaseOptions(
        baseUrl: 'https://sfcv4.linways.com/academics/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    _instance.dio.interceptors.add(_AuthInterceptor(sessionStorage));
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
        final code = e.response?.statusCode;
        final body = e.response?.data;
        final msg = body is Map ? (body['message'] ?? body['error'] ?? '').toString() : null;
        return switch (code) {
          401 => UnauthorizedException(msg ?? 'Session expired'),
          500 => ServerException('Server error', statusCode: code),
          _ => ServerException(msg ?? 'Request failed', statusCode: code),
        };
      default:
        return const UnknownException('An unexpected error occurred');
    }
  }
}

class _AuthInterceptor extends Interceptor {
  final SessionStorage? _storage;
  _AuthInterceptor(this._storage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_storage != null) {
      final cookies = await _storage.getCookies();
      if (cookies != null && cookies.isNotEmpty) {
        options.headers['Cookie'] = cookies;
        final token = _extractAuthSession(cookies);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
    }
    handler.next(options);
  }

  String? _extractAuthSession(String s) {
    const p = 'AUTH_SESSION=';
    final start = s.indexOf(p);
    if (start == -1) return null;
    final vStart = start + p.length;
    final end = s.indexOf('; ', vStart);
    return end == -1 ? s.substring(vStart) : s.substring(vStart, end);
  }
}
