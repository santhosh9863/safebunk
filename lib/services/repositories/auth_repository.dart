import '../../models/api/login_request.dart';
import '../../storage/session_storage.dart';
import '../api/auth_api_service.dart';

class AuthRepository {
  final AuthApiService _authApiService;
  final SessionStorage _sessionStorage;

  AuthRepository({
    required AuthApiService authApiService,
    required SessionStorage sessionStorage,
  })  : _authApiService = authApiService,
        _sessionStorage = sessionStorage;

  Future<void> login(String username, String password) async {
    final request = LoginRequest(username: username, password: password);
    final response = await _authApiService.login(request);

    if (!response.success) {
      throw Exception(response.message ?? 'Login failed.');
    }

    if (response.cookies != null && response.cookies!.isNotEmpty) {
      await _sessionStorage.saveCookies(response.cookies!);
    }

    await _sessionStorage.saveUsername(username);
  }

  Future<bool> hasSession() async {
    return _sessionStorage.hasSession();
  }

  Future<void> logout() async {
    await _sessionStorage.clearSession();
  }
}
