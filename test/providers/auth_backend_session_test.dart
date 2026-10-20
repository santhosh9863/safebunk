import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/cache/cache_manager.dart';
import 'package:safebunk_v2/core/session/session_manager.dart';
import 'package:safebunk_v2/core/storage/secure_storage_service.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/models/api/login_response.dart';
import 'package:safebunk_v2/providers/auth_provider.dart';
import 'package:safebunk_v2/services/api/auth_api_service.dart';
import 'package:safebunk_v2/services/api/pulse_backend_service.dart';
import 'package:safebunk_v2/services/repositories/auth_repository.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(SessionManager sessionManager)
    : super(
        authApiService: AuthApiService(Dio()),
        sessionManager: sessionManager,
      );

  @override
  Future<LoginResponse> login(String username, String password) async {
    return const LoginResponse(success: true);
  }
}

class _FakeBackend extends PulseBackendService {
  _FakeBackend() : super(baseUrl: 'http://localhost:3000');

  final loginGate = Completer<void>();
  int loginCalls = 0;

  @override
  Future<bool> login(String username, String password) async {
    loginCalls++;
    await loginGate.future;
    return true;
  }

  // Keep the fire-and-forget post-login sync inert in this test.
  @override
  Future<bool> get isLoggedIn async => false;

  @override
  Future<String> getDetectedGender() async => '';
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met in time');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login completes only after the PULSE backend session is established',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sessionManager = SessionManager(SecureStorageService());
      final backend = _FakeBackend();
      final container = ProviderContainer(
        overrides: [
          sessionManagerProvider.overrideWithValue(sessionManager),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(sessionManager),
          ),
          cacheManagerProvider.overrideWithValue(CacheManager()),
          pulseBackendServiceProvider.overrideWithValue(backend),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authProvider.notifier);
      await _waitFor(
        () => container.read(authProvider).status == AuthStatus.unauthenticated,
      );

      final loginFuture = notifier.login('4301', 'secret');
      await _waitFor(() => backend.loginCalls == 1);

      // Linways has succeeded, but the app must remain in its loading state
      // until the backend token has been stored; otherwise Reports can open
      // with a missing session.
      expect(
        container.read(authProvider).status,
        isNot(AuthStatus.authenticated),
      );
      expect(container.read(authProvider).isLoading, isTrue);

      backend.loginGate.complete();
      await loginFuture;

      expect(backend.loginCalls, 1);
      expect(container.read(authProvider).status, AuthStatus.authenticated);
      expect(container.read(authProvider).isLoading, isFalse);
    },
  );
}
