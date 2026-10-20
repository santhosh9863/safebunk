import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/cache/cache_manager.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/core/session/session_manager.dart';
import 'package:safebunk_v2/core/storage/secure_storage_service.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/models/api/login_response.dart';
import 'package:safebunk_v2/models/auth/session_data.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';
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
  _FakeBackend({this.loginResult, this.loginError})
    : super(baseUrl: 'http://localhost:3000');

  StaffSession? loginResult;
  Object? loginError;
  int loginCalls = 0;
  String? lastUsername;
  String? lastPassword;
  String? revokedToken;

  @override
  Future<StaffSession> staffLogin(String username, String password) async {
    loginCalls++;
    lastUsername = username;
    lastPassword = password;
    final error = loginError;
    if (error != null) throw error;
    return loginResult!;
  }

  @override
  Future<void> staffLogout(String token) async {
    revokedToken = token;
  }

  @override
  Future<bool> get isLoggedIn async => false;

  @override
  Future<void> logout() async {
    // The test's student backend session is intentionally inert.
  }
}

class _Harness {
  final SessionManager manager;
  final _FakeBackend backend;
  final ProviderContainer container;

  const _Harness({
    required this.manager,
    required this.backend,
    required this.container,
  });

  AuthNotifier get notifier => container.read(authProvider.notifier);
  AuthState get state => container.read(authProvider);
}

Future<_Harness> _createHarness({
  StaffSession? loginResult,
  Object? loginError,
  StaffSession? storedSession,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final manager = SessionManager(SecureStorageService());
  if (storedSession != null) {
    await manager.saveStaffSession(storedSession);
  }

  final backend = _FakeBackend(
    loginResult: loginResult,
    loginError: loginError,
  );
  final container = ProviderContainer(
    overrides: [
      sessionManagerProvider.overrideWithValue(manager),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(manager)),
      cacheManagerProvider.overrideWithValue(CacheManager()),
      pulseBackendServiceProvider.overrideWithValue(backend),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(manager: manager, backend: backend, container: container);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met in time');
}

const _adminSession = StaffSession(
  accessToken: 'staff-token',
  staffId: 'staff-1',
  username: 'campus.admin',
  displayName: 'Campus Admin',
  role: StaffRole.admin,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('staff login stores the backend role and token securely', () async {
    final harness = await _createHarness(loginResult: _adminSession);
    await _waitFor(() => harness.state.status == AuthStatus.unauthenticated);

    // Simulate a stale student session already on the device.
    await harness.manager.saveSession(
      const SessionData(
        cookies: 'AUTH_SESSION=student',
        username: 'student',
        studentId: 'student-1',
      ),
    );

    await harness.notifier.staffLogin('  campus.admin  ', 'secret');

    expect(harness.backend.loginCalls, 1);
    expect(harness.backend.lastUsername, 'campus.admin');
    expect(harness.state.status, AuthStatus.authenticated);
    expect(harness.state.role, AuthRole.admin);
    expect(harness.state.isAdmin, isTrue);
    expect(harness.state.staffSession?.accessToken, 'staff-token');

    final stored = await harness.manager.restoreStaffSession();
    expect(stored?.role, StaffRole.admin);
    expect(stored?.accessToken, 'staff-token');
    expect(await harness.manager.restoreSession(), isNull);
  });

  test(
    'staff login maps an invalid/inactive account to a safe message',
    () async {
      final harness = await _createHarness(
        loginError: const UnauthorizedException(
          'Invalid username or password.',
        ),
      );
      await _waitFor(() => harness.state.status == AuthStatus.unauthenticated);

      await harness.notifier.staffLogin('campus.staff', 'wrong');

      expect(harness.state.status, AuthStatus.unauthenticated);
      expect(harness.state.error, 'Invalid username or password.');
      expect(harness.state.staffSession, isNull);
      expect(await harness.manager.restoreStaffSession(), isNull);
    },
  );

  test(
    'staff login surfaces a network failure without authenticating',
    () async {
      final harness = await _createHarness(
        loginError: const NetworkException('No internet connection.'),
      );
      await _waitFor(() => harness.state.status == AuthStatus.unauthenticated);

      await harness.notifier.staffLogin('campus.staff', 'secret');

      expect(harness.state.status, AuthStatus.unauthenticated);
      expect(harness.state.error, 'No internet connection.');
      expect(await harness.manager.restoreStaffSession(), isNull);
    },
  );

  test('startup restores a stored staff session and role', () async {
    final harness = await _createHarness(storedSession: _adminSession);
    await _waitFor(() => harness.state.status == AuthStatus.authenticated);

    expect(harness.state.role, AuthRole.admin);
    expect(harness.state.username, 'campus.admin');
    expect(harness.state.staffSession?.staffId, 'staff-1');
    expect(harness.backend.loginCalls, 0);
  });

  test('logout revokes and clears the staff session', () async {
    final harness = await _createHarness(loginResult: _adminSession);
    await _waitFor(() => harness.state.status == AuthStatus.unauthenticated);
    await harness.notifier.staffLogin('campus.admin', 'secret');

    await harness.notifier.logout();

    expect(harness.state.status, AuthStatus.unauthenticated);
    expect(harness.state.staffSession, isNull);
    expect(harness.state.role, isNull);
    expect(harness.backend.revokedToken, 'staff-token');
    expect(await harness.manager.restoreStaffSession(), isNull);
  });

  test('expired staff session is cleared and reported safely', () async {
    final harness = await _createHarness(loginResult: _adminSession);
    await _waitFor(() => harness.state.status == AuthStatus.unauthenticated);
    await harness.notifier.staffLogin('campus.admin', 'secret');

    await harness.notifier.handleSessionExpired();

    expect(harness.state.status, AuthStatus.unauthenticated);
    expect(harness.state.staffSession, isNull);
    expect(harness.state.error, contains('session expired'));
    expect(harness.backend.revokedToken, 'staff-token');
    expect(await harness.manager.restoreStaffSession(), isNull);
  });
}
