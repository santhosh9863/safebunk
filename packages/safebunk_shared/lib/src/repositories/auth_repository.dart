import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';

abstract class AuthRepository {
  Future<LoginResponse> login(LoginRequest request);
  Future<void> logout();
  String? getAccessToken();
  bool get isAuthenticated;
}
