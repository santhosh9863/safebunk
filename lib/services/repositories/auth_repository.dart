import '../../core/auth/token_parser.dart';
import '../../core/session/session_manager.dart';
import '../../models/auth/session_data.dart';
import '../../models/api/login_request.dart';
import '../../models/api/login_response.dart';
import '../api/auth_api_service.dart';

class AuthRepository {
  final AuthApiService _authApiService;
  final SessionManager _sessionManager;

  AuthRepository({
    required AuthApiService authApiService,
    required SessionManager sessionManager,
  })  : _authApiService = authApiService,
        _sessionManager = sessionManager;

  Future<LoginResponse> login(String username, String password) async {
    final request = LoginRequest(username: username, password: password);
    final response = await _authApiService.login(request);

    if (!response.success) {
      throw Exception(response.message ?? 'Login failed.');
    }

    final studentData = response.data;
    final studentDataJson = studentData?.toJson();
    final studentId = TokenParser.extractStudentId(
      explicitId: studentData?.id,
      rawToken: studentData?.token,
      cookies: response.cookies,
    );

    final session = SessionData(
      studentId: studentId,
      username: username,
      cookies: response.cookies,
      studentData: studentDataJson,
    );

    await _sessionManager.saveSession(session);

    return response;
  }

  Future<void> logout() async {
    await _sessionManager.clearSession();
  }
}
