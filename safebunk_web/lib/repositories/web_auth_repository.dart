import 'package:safebunk_shared/safebunk_shared.dart';
import '../core/api/http_client.dart';
import '../core/storage/web_storage.dart';

class WebAuthRepository extends AuthRepository {
  WebAuthRepository(this._client);

  final HttpClient _client;
  String? _accessToken;

  @override
  String? getAccessToken() => _accessToken;

  @override
  bool get isAuthenticated => _accessToken != null;

  Future<void> restoreSession() async {
    final token = await WebStorage.getAccessToken();
    if (token != null) {
      _accessToken = token;
      _client.setAccessToken(token);
    }
  }

  @override
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await _client.post('/auth/login', body: request.toJson());

    if (!response.success || response.data == null) {
      throw Exception(response.message ?? 'Login failed');
    }

    final data = response.data as Map<String, dynamic>;
    final loginResponse = LoginResponse.fromJson(data);

    _accessToken = loginResponse.accessToken;
    _client.setAccessToken(_accessToken);

    await WebStorage.setAccessToken(_accessToken);
    await WebStorage.setStudentId(loginResponse.student.studentId);
    await WebStorage.setUsername(loginResponse.student.username);
    await WebStorage.setStudentName(loginResponse.student.name);

    return loginResponse;
  }

  @override
  Future<void> logout() async {
    await _client.post('/auth/logout');
    _accessToken = null;
    _client.setAccessToken(null);
    await WebStorage.clearAll();
  }
}
