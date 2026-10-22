import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/application/reports_providers.dart';
import 'package:safebunk_v2/features/reports/application/reports_realtime_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/data/models/report_realtime_event.dart';
import 'package:safebunk_v2/features/reports/data/realtime/reports_realtime_client.dart';
import 'package:safebunk_v2/features/staff/application/staff_providers.dart';

class _FakeRealtimeClient implements ReportsRealtimeClient {
  final StreamController<ReportsRealtimeSignal> _signals =
      StreamController<ReportsRealtimeSignal>.broadcast();

  final List<({String baseUrl, String token})> connects = [];
  int disconnectCalls = 0;
  bool disposed = false;

  @override
  Stream<ReportsRealtimeSignal> get signals => _signals.stream;

  bool get hasListener => _signals.hasListener;

  @override
  Future<void> connect({required String baseUrl, required String token}) async {
    connects.add((baseUrl: baseUrl, token: token));
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_signals.close());
  }

  void emit(ReportsRealtimeSignal signal) => _signals.add(signal);
}

const _studentIdentity = ReportsRealtimeIdentity(
  baseUrl: 'http://localhost:3000',
  token: 'student-token',
  accountKey: 'STUDENT:student.one',
  isStaff: false,
);

const _staffIdentity = ReportsRealtimeIdentity(
  baseUrl: 'http://localhost:3000',
  token: 'staff-token',
  accountKey: 'STAFF:staff_1',
  isStaff: true,
);

ReportModel _report(String id) {
  return ReportModel(
    id: id,
    code: 'PULSE-1042',
    title: 'Water leakage',
    description: 'Water near the electrical panel.',
    category: 'Plumbing',
    location: 'Block B',
    imageUrl: null,
    priority: 'MEDIUM',
    status: 'SUBMITTED',
    assignedDepartment: null,
    aiCategory: null,
    aiPriority: null,
    aiConfidence: null,
    createdAt: DateTime.utc(2026, 10, 20, 9),
    updatedAt: DateTime.utc(2026, 10, 20, 9),
    resolvedAt: null,
  );
}

ReportRealtimeEvent _event(
  String reportId, {
  String change = 'resolved',
  String eventId = 'evt_1',
}) {
  return ReportRealtimeEvent(
    eventId: eventId,
    reportId: reportId,
    code: 'PULSE-1042',
    status: 'RESOLVED',
    change: change,
    occurredAt: DateTime.utc(2026, 10, 22, 10),
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeRealtimeClient client;
  late StateProvider<ReportsRealtimeIdentity?> identity;
  late ProviderContainer container;
  late List<String> studentDetailFetches;
  late List<String> staffDetailFetches;
  late int studentListFetches;
  late int staffListFetches;
  bool containerDisposed = false;

  ProviderContainer createContainer({
    ReportsRealtimeIdentity? initialIdentity = _studentIdentity,
  }) {
    identity = StateProvider<ReportsRealtimeIdentity?>(
      (ref) => initialIdentity,
    );
    studentDetailFetches = [];
    staffDetailFetches = [];
    studentListFetches = 0;
    staffListFetches = 0;

    return ProviderContainer(
      overrides: [
        reportsRealtimeClientProvider.overrideWith((ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        reportsRealtimeIdentityProvider.overrideWith(
          (ref) => ref.watch(identity),
        ),
        reportsListProvider.overrideWith((ref) async {
          studentListFetches++;
          return <ReportModel>[_report('report_1')];
        }),
        reportDetailProvider.overrideWith((ref, id) async {
          studentDetailFetches.add(id);
          return _report(id);
        }),
        staffReportsProvider.overrideWith((ref) async {
          staffListFetches++;
          return <ReportModel>[_report('report_1')];
        }),
        staffReportDetailProvider.overrideWith((ref, id) async {
          staffDetailFetches.add(id);
          return _report(id);
        }),
      ],
    );
  }

  setUp(() {
    client = _FakeRealtimeClient();
    container = createContainer();
    containerDisposed = false;
  });

  tearDown(() {
    if (!containerDisposed) container.dispose();
  });

  void disposeContainer() {
    container.dispose();
    containerDisposed = true;
  }

  Future<void> startCoordinator() async {
    container.read(reportsRealtimeCoordinatorProvider);
    await _settle();
  }

  test(
    'connects with the authenticated identity and resyncs after connect',
    () async {
      final listSubscription = container.listen(
        reportsListProvider,
        (previous, next) {},
      );
      addTearDown(listSubscription.close);
      await container.read(reportsListProvider.future);
      expect(studentListFetches, 1);

      await startCoordinator();
      expect(client.connects, hasLength(1));
      expect(client.connects.single.token, 'student-token');

      client.emit(const ReportsRealtimeConnected(isReconnect: false));
      await _settle();
      await container.read(reportsListProvider.future);

      expect(studentListFetches, 2);
    },
  );

  test(
    'clears cached report data when the authenticated account changes',
    () async {
      final listSubscription = container.listen(
        reportsListProvider,
        (previous, next) {},
      );
      addTearDown(listSubscription.close);
      await container.read(reportsListProvider.future);
      expect(studentListFetches, 1);

      await startCoordinator();
      container.read(identity.notifier).state = _staffIdentity;
      await _settle();
      await container.read(reportsListProvider.future);

      expect(client.connects, hasLength(2));
      expect(studentListFetches, 2);
    },
  );

  test(
    'refreshes the matching detail provider and coalesces a burst',
    () async {
      final detailSubscription = container.listen(
        reportDetailProvider('report_1'),
        (previous, next) {},
      );
      addTearDown(detailSubscription.close);
      await container.read(reportDetailProvider('report_1').future);
      await startCoordinator();
      expect(studentDetailFetches, ['report_1']);

      client.emit(ReportsRealtimeChanged(_event('report_1', eventId: 'evt_1')));
      client.emit(ReportsRealtimeChanged(_event('report_1', eventId: 'evt_2')));
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await container.read(reportDetailProvider('report_1').future);

      expect(studentDetailFetches, ['report_1', 'report_1']);
    },
  );

  test('ignores a duplicate delivery of the same event', () async {
    final detailSubscription = container.listen(
      reportDetailProvider('report_1'),
      (previous, next) {},
    );
    addTearDown(detailSubscription.close);
    await container.read(reportDetailProvider('report_1').future);
    await startCoordinator();
    expect(studentDetailFetches, ['report_1']);

    final duplicate = _event('report_1', eventId: 'evt_duplicate');
    client.emit(ReportsRealtimeChanged(duplicate));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await container.read(reportDetailProvider('report_1').future);
    expect(studentDetailFetches, ['report_1', 'report_1']);

    client.emit(ReportsRealtimeChanged(duplicate));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await container.read(reportDetailProvider('report_1').future);
    expect(studentDetailFetches, ['report_1', 'report_1']);
  });

  test(
    'progress notes refresh staff detail without refetching the list',
    () async {
      disposeContainer();
      containerDisposed = false;
      client = _FakeRealtimeClient();
      container = createContainer(initialIdentity: _staffIdentity);

      final detailSubscription = container.listen(
        staffReportDetailProvider('report_1'),
        (previous, next) {},
      );
      addTearDown(detailSubscription.close);
      await container.read(staffReportDetailProvider('report_1').future);
      final initialDetailFetches = staffDetailFetches.length;

      await startCoordinator();
      final listSubscription = container.listen(
        staffReportsProvider,
        (previous, next) {},
      );
      addTearDown(listSubscription.close);
      await container.read(staffReportsProvider.future);
      final initialListFetches = staffListFetches;

      client.emit(
        ReportsRealtimeChanged(_event('report_1', change: 'progress')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await container.read(staffReportDetailProvider('report_1').future);

      expect(staffDetailFetches.length, initialDetailFetches + 1);
      expect(staffListFetches, initialListFetches);
    },
  );

  test('refreshes staff providers for a staff identity', () async {
    disposeContainer();
    containerDisposed = false;
    client = _FakeRealtimeClient();
    container = createContainer(initialIdentity: _staffIdentity);

    final listSubscription = container.listen(
      staffReportsProvider,
      (previous, next) {},
    );
    addTearDown(listSubscription.close);
    await container.read(staffReportsProvider.future);
    await startCoordinator();
    expect(client.connects.single.token, 'staff-token');

    client.emit(
      ReportsRealtimeChanged(_event('report_1', eventId: 'evt_staff')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await container.read(staffReportsProvider.future);

    expect(staffListFetches, 2);
  });

  test('disconnects on logout and disposes its listener', () async {
    await startCoordinator();
    expect(client.hasListener, isTrue);

    container.read(identity.notifier).state = null;
    await _settle();

    expect(client.disconnectCalls, greaterThanOrEqualTo(1));

    disposeContainer();
    await _settle();
    expect(client.disposed, isTrue);
    expect(client.hasListener, isFalse);
  });
}
