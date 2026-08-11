class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'http://localhost:3000';
  static const String apiPrefix = '/api';

  static String get apiBaseUrl => '$baseUrl$apiPrefix';

  static const Duration timeout = Duration(seconds: 30);
}
