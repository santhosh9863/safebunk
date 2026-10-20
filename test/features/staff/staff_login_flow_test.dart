import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/cache/cache_manager.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/core/session/session_manager.dart';
import 'package:safebunk_v2/core/storage/secure_storage_service.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/staff/presentation/staff_shell_screen.dart';
import 'package:safebunk_v2/models/api/login_response.dart';
import 'package:safebunk_v2/models/auth/staff_account.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';
import 'package:safebunk_v2/providers/auth_provider.dart';
import 'package:safebunk_v2/screens/staff_login_screen.dart';
import 'package:safebunk_v2/screens/web_login_screen.dart';
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
  _FakeBackend({this.loginSession, this.loginError})
    : super(baseUrl: 'http://localhost:3000');

  StaffSession? loginSession;
  Object? loginError;
  int loginCalls = 0;
  int reportCalls = 0;
  String? revokedToken;

  @override
  Future<StaffSession> staffLogin(String username, String password) async {
    loginCalls++;
    final error = loginError;
    if (error != null) throw error;
    return loginSession!;
  }

  @override
  Future<void> staffLogout(String token) async {
    revokedToken = token;
  }

  @override
  Future<bool> get isLoggedIn async => false;

  @override
  Future<void> logout() async {
    // Keep the test's student backend session inert.
  }

  @override
  Future<List<ReportModel>> fetchStaffReports(
    String token, {
    String? status,
  }) async {
    reportCalls++;
    return const [];
  }

  @override
  Future<List<StaffAccount>> fetchStaffAccounts(String token) async {
    return const [];
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
}

Future<_Harness> _harness({
  StaffSession? loginSession,
  Object? loginError,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final manager = SessionManager(SecureStorageService());
  final backend = _FakeBackend(
    loginSession: loginSession,
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

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(reason ?? 'condition was not met in time');
}

Future<void> _pumpApp(
  WidgetTester tester,
  _Harness harness,
  Widget home,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(home: home),
    ),
  );
  await _pumpUntil(
    tester,
    () => harness.container.read(authProvider).status != AuthStatus.unknown,
    reason: 'auth session restore did not complete',
  );
}

Future<void> _submitLogin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'campus.admin');
  await tester.enterText(find.byType(TextFormField).at(1), 'secret');
  final button = find.text('Sign In');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

const _adminSession = StaffSession(
  accessToken: 'staff-token',
  staffId: 'staff-1',
  username: 'campus.admin',
  displayName: 'Campus Admin',
  role: StaffRole.admin,
);

const _staffSession = StaffSession(
  accessToken: 'staff-token-2',
  staffId: 'staff-2',
  username: 'campus.staff',
  displayName: 'Campus Staff',
  role: StaffRole.staff,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('student login screen exposes a separate staff/admin option', (
    tester,
  ) async {
    final harness = await _harness();
    await _pumpApp(tester, harness, const WebLoginScreen());
    await tester.pumpAndSettle();

    final staffOption = find.text('Staff / Admin Login');
    expect(staffOption, findsOneWidget);
    await tester.ensureVisible(staffOption);
    await tester.tap(staffOption);
    await tester.pumpAndSettle();

    expect(find.byType(StaffLoginScreen), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('ADMIN login persists the session and opens admin navigation', (
    tester,
  ) async {
    final harness = await _harness(loginSession: _adminSession);
    await _pumpApp(tester, harness, const StaffLoginScreen());
    await tester.pumpAndSettle();

    await _submitLogin(tester);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(authProvider).status ==
          AuthStatus.authenticated,
    );
    await tester.pumpAndSettle();

    expect(find.byType(StaffShellScreen), findsOneWidget);
    expect(find.byIcon(Icons.manage_accounts_outlined), findsOneWidget);
    expect(harness.backend.reportCalls, greaterThan(0));

    final stored = await harness.manager.restoreStaffSession();
    expect(stored?.role, StaffRole.admin);
    expect(stored?.accessToken, 'staff-token');
  });

  testWidgets('STAFF login never exposes staff-account management', (
    tester,
  ) async {
    final harness = await _harness(loginSession: _staffSession);
    await _pumpApp(tester, harness, const StaffLoginScreen());
    await tester.pumpAndSettle();

    await _submitLogin(tester);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(authProvider).status ==
          AuthStatus.authenticated,
    );
    await tester.pumpAndSettle();

    expect(find.byType(StaffShellScreen), findsOneWidget);
    expect(find.byIcon(Icons.manage_accounts_outlined), findsNothing);
    expect(find.text('Staff Access'), findsNothing);
  });

  testWidgets('invalid staff credentials stay on the staff login screen', (
    tester,
  ) async {
    final harness = await _harness(
      loginError: const UnauthorizedException('Invalid username or password.'),
    );
    await _pumpApp(tester, harness, const StaffLoginScreen());
    await tester.pumpAndSettle();

    await _submitLogin(tester);
    await tester.pumpAndSettle();

    expect(find.byType(StaffLoginScreen), findsOneWidget);
    expect(find.text('Invalid username or password.'), findsOneWidget);
    expect(
      harness.container.read(authProvider).status,
      AuthStatus.unauthenticated,
    );
  });

  testWidgets('signing out clears the session and returns to student login', (
    tester,
  ) async {
    final harness = await _harness(loginSession: _adminSession);
    await _pumpApp(tester, harness, const StaffLoginScreen());
    await tester.pumpAndSettle();

    await _submitLogin(tester);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(authProvider).status ==
          AuthStatus.authenticated,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Staff ID'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final signOut = find.text('Sign out');
    expect(signOut, findsOneWidget);
    await tester.tap(signOut);
    await _pumpUntil(
      tester,
      () =>
          harness.container.read(authProvider).status ==
          AuthStatus.unauthenticated,
    );
    await tester.pumpAndSettle();

    expect(find.byType(WebLoginScreen), findsOneWidget);
    expect(harness.backend.revokedToken, 'staff-token');
    expect(await harness.manager.restoreStaffSession(), isNull);
  });
}
