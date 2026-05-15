import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../services/api/auth_api_service.dart';
import '../services/repositories/auth_repository.dart';
import '../storage/session_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;
  final bool isLoading;

  const AuthState({
    required this.status,
    this.error,
    this.isLoading = false,
  });

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const authenticated = AuthState(status: AuthStatus.authenticated);
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);

  AuthState copyWith({AuthStatus? status, String? error, bool? isLoading}) {
    return AuthState(
      status: status ?? this.status,
      error: error ?? this.error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage();
});

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService(DioClient.instance.dio);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final authApiService = ref.watch(authApiServiceProvider);
  final sessionStorage = ref.watch(sessionStorageProvider);
  return AuthRepository(
    authApiService: authApiService,
    sessionStorage: sessionStorage,
  );
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final sessionStorage = ref.watch(sessionStorageProvider);
  return AuthNotifier(authRepository, sessionStorage);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final SessionStorage _sessionStorage;

  AuthNotifier(this._authRepository, this._sessionStorage)
      : super(const AuthState(status: AuthStatus.unknown)) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final hasSession = await _sessionStorage.hasSession();
      state = AuthState(
        status: hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    } catch (_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authRepository.login(username, password);
      state = const AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
