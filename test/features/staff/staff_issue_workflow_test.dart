import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/cache/cache_manager.dart';
import 'package:safebunk_v2/core/session/session_manager.dart';
import 'package:safebunk_v2/core/storage/secure_storage_service.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/ml_suggestion.dart';
import 'package:safebunk_v2/features/reports/data/models/report_event.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/staff/presentation/staff_report_detail_screen.dart';
import 'package:safebunk_v2/models/api/login_response.dart';
import 'package:safebunk_v2/models/auth/staff_account.dart';
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

const _duplicateCandidate = DuplicateCandidate(
  reportId: 'rep_2',
  reportCode: 'PULSE-1043',
  title: 'Library lighting problem',
  status: 'ASSIGNED',
  category: 'Electrical',
  location: 'Main Library',
  similarityScore: 0.47,
  rankingScore: 0.51,
  categoryMatch: true,
  locationMatch: true,
  reasons: ['similar description text', 'same category: Electrical'],
);

DuplicateSuggestion _duplicateResult({bool available = true}) {
  return DuplicateSuggestion(
    available: available,
    reason: available ? null : 'ml_unavailable',
    message: available ? 'Possible duplicates found.' : 'ML unavailable.',
    reportId: 'rep_1',
    decision: available ? DuplicateSuggestionDecision.match : null,
    candidates: available ? const [_duplicateCandidate] : const [],
    duplicateThreshold: available ? 0.5 : null,
    uncertainThreshold: available ? 0.4 : null,
    similarityMetric: available ? 'tfidf_cosine_similarity' : null,
    rankingMetric: available ? 'cosine_similarity_with_metadata_support' : null,
    modelVersion: available ? '0.2.0' : null,
    scoreNote: 'Ranking score, not a probability.',
    manualReviewRecommended: true,
    existingComplaintsEvaluated: available ? 3 : null,
  );
}

class _WorkflowBackend extends PulseBackendService {
  _WorkflowBackend({
    required this.loginSession,
    required this.detail,
    this.acceptResult,
    this.progressResult,
    this.resolveResult,
    this.assignResult,
    this.duplicateResult,
    this.accounts = const [],
  }) : super(baseUrl: 'http://localhost:3000');

  final StaffSession loginSession;
  ReportModel detail;
  ReportModel? acceptResult;
  ReportModel? progressResult;
  ReportModel? resolveResult;
  ReportModel? assignResult;
  DuplicateSuggestion? duplicateResult;
  final List<StaffAccount> accounts;

  int acceptCalls = 0;
  int progressCalls = 0;
  int resolveCalls = 0;
  int assignCalls = 0;
  int duplicateCalls = 0;
  String? lastDuplicateToken;
  String? lastDuplicateReportId;
  String? lastNote;
  String? lastResolution;
  String? lastAssignedStaffId;
  String? lastDepartment;

  @override
  Future<StaffSession> staffLogin(String username, String password) async {
    return loginSession;
  }

  @override
  Future<void> staffLogout(String token) async {}

  @override
  Future<bool> get isLoggedIn async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<List<ReportModel>> fetchStaffReports(
    String token, {
    String? status,
  }) async {
    return [detail];
  }

  @override
  Future<ReportModel> fetchStaffReport(String token, String reportId) async {
    return detail;
  }

  @override
  Future<List<StaffAccount>> fetchStaffAccounts(String token) async {
    return accounts;
  }

  @override
  Future<ReportModel> acceptStaffReport(String token, String reportId) async {
    acceptCalls++;
    detail = acceptResult ?? detail;
    return detail;
  }

  @override
  Future<ReportModel> addStaffProgressNote(
    String token,
    String reportId,
    String note,
  ) async {
    progressCalls++;
    lastNote = note;
    detail = progressResult ?? detail;
    return detail;
  }

  @override
  Future<ReportModel> resolveStaffReport(
    String token,
    String reportId,
    String resolutionNotes,
  ) async {
    resolveCalls++;
    lastResolution = resolutionNotes;
    detail = resolveResult ?? detail;
    return detail;
  }

  @override
  Future<ReportModel> assignStaffReport(
    String token,
    String reportId, {
    required String staffId,
    String? department,
  }) async {
    assignCalls++;
    lastAssignedStaffId = staffId;
    lastDepartment = department;
    detail = assignResult ?? detail;
    return detail;
  }

  @override
  Future<ReportModel> rejectStaffReport(
    String token,
    String reportId,
    String reason,
  ) async {
    return detail;
  }

  @override
  Future<DuplicateSuggestion> suggestStaffDuplicates(
    String token,
    String reportId, {
    int maxCandidates = 5,
  }) async {
    duplicateCalls++;
    lastDuplicateToken = token;
    lastDuplicateReportId = reportId;
    return duplicateResult ?? _duplicateResult();
  }
}

class _Harness {
  final ProviderContainer container;
  final _WorkflowBackend backend;

  const _Harness({required this.container, required this.backend});
}

Future<_Harness> _pumpDetail(
  WidgetTester tester, {
  required StaffSession session,
  required ReportModel report,
  ReportModel? acceptResult,
  ReportModel? progressResult,
  ReportModel? resolveResult,
  ReportModel? assignResult,
  DuplicateSuggestion? duplicateResult,
  List<StaffAccount> accounts = const [],
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final manager = SessionManager(SecureStorageService());
  final backend = _WorkflowBackend(
    loginSession: session,
    detail: report,
    acceptResult: acceptResult,
    progressResult: progressResult,
    resolveResult: resolveResult,
    assignResult: assignResult,
    duplicateResult: duplicateResult,
    accounts: accounts,
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

  await container
      .read(authProvider.notifier)
      .staffLogin(session.username, 'secret');
  expect(container.read(authProvider).status, AuthStatus.authenticated);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: StaffReportDetailScreen(reportId: report.id, initial: report),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container: container, backend: backend);
}

const _staffAccount = StaffAccount(
  id: 'staff_a',
  username: 'campus.staff',
  displayName: 'Campus Staff',
  role: StaffRole.staff,
  active: true,
);

const _adminAccount = StaffAccount(
  id: 'admin_1',
  username: 'campus.admin',
  displayName: 'Campus Admin',
  role: StaffRole.admin,
  active: true,
);

const _staffSession = StaffSession(
  accessToken: 'staff-token',
  staffId: 'staff_a',
  username: 'campus.staff',
  displayName: 'Campus Staff',
  role: StaffRole.staff,
);

const _adminSession = StaffSession(
  accessToken: 'admin-token',
  staffId: 'admin_1',
  username: 'campus.admin',
  displayName: 'Campus Admin',
  role: StaffRole.admin,
);

ReportEventModel _event(String id, String type, String role, String? remark) {
  return ReportEventModel(
    id: id,
    type: type,
    actorRole: role,
    remark: remark,
    createdAt: DateTime.utc(2026, 10, 20, 9),
  );
}

ReportModel _report({
  required String status,
  StaffAccount? assignedStaff,
  String? resolutionNotes,
  required List<ReportEventModel> events,
}) {
  return ReportModel(
    id: 'rep_1',
    code: 'PULSE-1042',
    title: 'Water leakage',
    description: 'Water is leaking near the electrical panel.',
    category: 'Plumbing',
    location: 'Block B · 2nd Floor',
    imageUrl: null,
    priority: 'HIGH',
    status: status,
    assignedDepartment: assignedStaff == null ? null : 'Maintenance',
    assignedStaff: assignedStaff,
    assignedAt: assignedStaff == null ? null : DateTime.utc(2026, 10, 20, 10),
    resolutionNotes: resolutionNotes,
    events: events,
    aiCategory: null,
    aiPriority: null,
    aiConfidence: null,
    createdAt: DateTime.utc(2026, 10, 20, 9),
    updatedAt: DateTime.utc(2026, 10, 20, 11),
    resolvedAt: status == 'RESOLVED' ? DateTime.utc(2026, 10, 20, 11) : null,
  );
}

Future<void> _scrollToDuplicateButton(WidgetTester tester) async {
  final button = find.text('Check possible duplicates');
  for (var i = 0; i < 12 && button.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assigned staff can accept, note progress, and resolve', (
    tester,
  ) async {
    final assigned = _report(
      status: 'ASSIGNED',
      assignedStaff: _staffAccount,
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
      ],
    );
    final inProgress = _report(
      status: 'IN_PROGRESS',
      assignedStaff: _staffAccount,
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
        _event('e3', 'IN_PROGRESS', 'STAFF', null),
      ],
    );
    final withNote = _report(
      status: 'IN_PROGRESS',
      assignedStaff: _staffAccount,
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
        _event('e3', 'IN_PROGRESS', 'STAFF', null),
        _event(
          'e4',
          'PROGRESS_NOTE',
          'STAFF',
          'Valve ordered and access arranged.',
        ),
      ],
    );
    final resolved = _report(
      status: 'RESOLVED',
      assignedStaff: _staffAccount,
      resolutionNotes: 'Replaced the faulty valve.',
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
        _event('e3', 'IN_PROGRESS', 'STAFF', null),
        _event('e4', 'PROGRESS_NOTE', 'STAFF', 'Valve ordered.'),
        _event('e5', 'RESOLVED', 'STAFF', 'Replaced the faulty valve.'),
      ],
    );

    final harness = await _pumpDetail(
      tester,
      session: _staffSession,
      report: assigned,
      acceptResult: inProgress,
      progressResult: withNote,
      resolveResult: resolved,
    );

    expect(find.text('Accept issue'), findsOneWidget);
    await tester.tap(find.text('Accept issue'));
    await tester.pumpAndSettle();
    expect(harness.backend.acceptCalls, 1);
    expect(find.text('Add progress note'), findsOneWidget);
    expect(find.text('Mark resolved'), findsOneWidget);

    await tester.tap(find.text('Add progress note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Valve ordered and access arranged.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add note'));
    await tester.pumpAndSettle();
    expect(harness.backend.progressCalls, 1);
    expect(harness.backend.lastNote, 'Valve ordered and access arranged.');

    await tester.tap(find.text('Mark resolved'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Replaced the faulty valve.',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Mark resolved'),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.backend.resolveCalls, 1);
    expect(harness.backend.lastResolution, 'Replaced the faulty valve.');
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('RESOLUTION'), findsOneWidget);
    expect(find.text('Replaced the faulty valve.'), findsAtLeastNWidgets(1));
    expect(harness.container.read(authProvider).isStaff, isTrue);
  });

  testWidgets('admin can assign an issue to an active STAFF account', (
    tester,
  ) async {
    final submitted = _report(
      status: 'SUBMITTED',
      events: [_event('e1', 'SUBMITTED', 'STUDENT', null)],
    );
    final assigned = _report(
      status: 'ASSIGNED',
      assignedStaff: _staffAccount,
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
      ],
    );

    final harness = await _pumpDetail(
      tester,
      session: _adminSession,
      report: submitted,
      assignResult: assigned,
      accounts: const [_staffAccount, _adminAccount],
    );

    expect(find.text('Assign to staff'), findsOneWidget);
    expect(find.text('Reject report'), findsOneWidget);
    await tester.tap(find.text('Assign to staff'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Campus Staff').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Maintenance');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
    await tester.pumpAndSettle();

    expect(harness.backend.assignCalls, 1);
    expect(harness.backend.lastAssignedStaffId, 'staff_a');
    expect(harness.backend.lastDepartment, 'Maintenance');
    expect(find.text('Campus Staff'), findsOneWidget);
    expect(find.text('Reassign issue'), findsOneWidget);
    expect(harness.container.read(authProvider).isAdmin, isTrue);
  });

  testWidgets(
    'assigned staff can request duplicate suggestions without mutation',
    (tester) async {
      final assigned = _report(
        status: 'ASSIGNED',
        assignedStaff: _staffAccount,
        events: [
          _event('e1', 'SUBMITTED', 'STUDENT', null),
          _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
        ],
      );
      final harness = await _pumpDetail(
        tester,
        session: _staffSession,
        report: assigned,
        duplicateResult: _duplicateResult(),
      );
      expect(find.text('ASSIGNMENT'), findsOneWidget);

      await _scrollToDuplicateButton(tester);

      expect(harness.backend.duplicateCalls, 1);
      expect(harness.backend.lastDuplicateToken, 'staff-token');
      expect(harness.backend.lastDuplicateReportId, 'rep_1');
      expect(find.text('PULSE-1043'), findsOneWidget);
      expect(find.textContaining('Similarity 0.47'), findsOneWidget);
      expect(harness.backend.acceptCalls, 0);
      expect(harness.backend.progressCalls, 0);
      expect(harness.backend.resolveCalls, 0);
    },
  );

  testWidgets('admin duplicate check uses the authenticated admin session', (
    tester,
  ) async {
    final assigned = _report(
      status: 'ASSIGNED',
      assignedStaff: _staffAccount,
      events: [
        _event('e1', 'SUBMITTED', 'STUDENT', null),
        _event('e2', 'ASSIGNED', 'ADMIN', 'Maintenance'),
      ],
    );
    final harness = await _pumpDetail(
      tester,
      session: _adminSession,
      report: assigned,
      duplicateResult: _duplicateResult(available: false),
    );

    await _scrollToDuplicateButton(tester);

    expect(harness.backend.duplicateCalls, 1);
    expect(harness.backend.lastDuplicateToken, 'admin-token');
    expect(find.text('ML suggestions unavailable'), findsOneWidget);
    expect(find.text('PULSE-1042'), findsWidgets);
  });
}
