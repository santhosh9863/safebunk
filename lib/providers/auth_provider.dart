import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/cache_manager.dart';
import '../core/cache/persistent_cache.dart';
import '../core/errors/app_exceptions.dart';
import '../core/network/dio_client.dart';
import '../core/notifications/notification_providers.dart';
import '../core/session/session_manager.dart';
import '../core/storage/secure_storage_service.dart';
import '../services/api/auth_api_service.dart';
import '../services/repositories/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? error;
  final bool isLoading;
  final String? username;

  const AuthState({
    required this.status,
    this.error,
    this.isLoading = false,
    this.username,
  });

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const authenticated = AuthState(status: AuthStatus.authenticated);
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);

  AuthState copyWith({
    AuthStatus? status,
    String? error,
    bool? isLoading,
    String? username,
  }) {
    return AuthState(
      status: status ?? this.status,
      error: error,
      isLoading: isLoading ?? this.isLoading,
      username: username ?? this.username,
    );
  }
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return SessionManager(secureStorage);
});

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService(DioClient.instance.dio);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final authApiService = ref.watch(authApiServiceProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  return AuthRepository(
    authApiService: authApiService,
    sessionManager: sessionManager,
  );
});

final cacheManagerProvider = Provider<CacheManager>((ref) {
  final manager = CacheManager();
  manager.registerAsync(PersistentCache.clearAll);
  return manager;
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final cacheManager = ref.watch(cacheManagerProvider);
  final notifier = AuthNotifier(authRepository, sessionManager, cacheManager, ref);
  DioClient.sessionExpiredHandler = () => notifier.handleSessionExpired();
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final SessionManager _sessionManager;
  final CacheManager _cacheManager;
  final Ref _ref;

  AuthNotifier(
    this._authRepository,
    this._sessionManager,
    this._cacheManager,
    this._ref,
  ) : super(const AuthState(status: AuthStatus.unknown)) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final session = await _sessionManager.restoreSession();
      final hasSession = session != null;
      final username = session?.username;

      state = AuthState(
        status: hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated,
        username: username,
      );
    } catch (_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String username, String password) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authRepository.login(username, password);
      state = AuthState(
        status: AuthStatus.authenticated,
        username: username,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e is ApiException ? e.message : e.toString(),
      );
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    await _cacheManager.clearAll();
    final store = _ref.read(notificationStateStoreProvider);
    await store.clearOperationalState();
    final service = _ref.read(notificationServiceProvider);
    await service?.cancelAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> handleSessionExpired() async {
    await _authRepository.logout();
    await _cacheManager.clearAll();
    final store = _ref.read(notificationStateStoreProvider);
    await store.clearOperationalState();
    final service = _ref.read(notificationServiceProvider);
    await service?.cancelAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
