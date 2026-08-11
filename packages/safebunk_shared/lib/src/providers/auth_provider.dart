import 'package:riverpod/riverpod.dart';
import '../repositories/auth_repository.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw UnimplementedError('authRepositoryProvider must be overridden');
});

final authLoginProvider = FutureProvider.family<LoginResponse, LoginRequest>((ref, request) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.login(request);
});

final authStatusProvider = Provider<bool>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.isAuthenticated;
});
