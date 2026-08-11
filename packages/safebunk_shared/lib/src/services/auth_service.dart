import '../models/api_response.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';

abstract class AuthService {
  Future<ApiResponse<LoginResponse>> login(LoginRequest request);
  Future<ApiResponse<void>> logout();
}
