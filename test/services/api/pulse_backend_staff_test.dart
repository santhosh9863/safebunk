import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/features/reports/domain/report_enums.dart';
import 'package:safebunk_v2/models/auth/staff_session.dart';
import 'package:safebunk_v2/services/api/pulse_backend_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

PulseBackendService _service(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
  dio.httpClientAdapter = adapter;
  return PulseBackendService(baseUrl: 'http://localhost:3000', dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'staff login posts credentials and parses the backend-issued role',
    () async {
      final adapter = _FakeAdapter((options) async {
        expect(options.method, 'POST');
        expect(options.path, '/api/auth/staff/login');
        expect(options.headers['Authorization'], isNull);
        expect(options.data, {
          'username': 'campus.admin',
          'password': 'secret',
        });
        return _json({
          'success': true,
          'data': {
            'accessToken': 'staff-token',
            'staff': {
              'id': 'staff-1',
              'username': 'campus.admin',
              'displayName': 'Campus Admin',
              'role': 'ADMIN',
            },
          },
        });
      });
      final service = _service(adapter);

      final session = await service.staffLogin('campus.admin', 'secret');

      expect(session.accessToken, 'staff-token');
      expect(session.staffId, 'staff-1');
      expect(session.role, StaffRole.admin);
    },
  );

  test(
    'staff login 401 is a credential failure, not an expired session',
    () async {
      final adapter = _FakeAdapter(
        (_) async => _json({'message': 'Invalid staff credentials'}, 401),
      );
      final service = _service(adapter);

      await expectLater(
        service.staffLogin('campus.staff', 'wrong'),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.message,
            'message',
            'Invalid username or password.',
          ),
        ),
      );
    },
  );

  test('staff login 429 preserves the safe retry message', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'message': 'Too many login attempts. Please try again later.',
      }, 429),
    );
    final service = _service(adapter);

    await expectLater(
      service.staffLogin('campus.staff', 'secret'),
      throwsA(
        isA<ServerException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having(
              (e) => e.message,
              'message',
              'Too many login attempts. Please try again later.',
            ),
      ),
    );
  });

  test('staff report calls use the staff Bearer token', () async {
    final adapter = _FakeAdapter((options) async {
      expect(options.path, '/api/staff/reports');
      expect(options.headers['Authorization'], 'Bearer staff-token');
      return _json({
        'success': true,
        'data': [
          {
            'id': 'rep_1',
            'code': 'PULSE-1042',
            'title': 'Leak',
            'description': 'Water near the lab.',
            'priority': 'MEDIUM',
            'status': 'SUBMITTED',
            'createdAt': '2026-10-20T00:00:00.000Z',
            'updatedAt': '2026-10-20T00:00:00.000Z',
          },
        ],
      });
    });
    final service = _service(adapter);

    final reports = await service.fetchStaffReports('staff-token');

    expect(reports, hasLength(1));
    expect(reports.single.id, 'rep_1');
  });

  test(
    'staff endpoints map 401 to an expired session and 403 to forbidden',
    () async {
      final adapter = _FakeAdapter((options) async {
        if (options.path == '/api/staff/reports') {
          return _json({'message': 'Session expired'}, 401);
        }
        return _json({'message': 'Insufficient permissions'}, 403);
      });
      final service = _service(adapter);

      await expectLater(
        service.fetchStaffReports('expired-token'),
        throwsA(isA<SessionExpiredException>()),
      );
      await expectLater(
        service.fetchStaffAccounts('staff-token'),
        throwsA(isA<UnauthorizedException>()),
      );
    },
  );

  test('staff detail parses assignment and status history', () async {
    final adapter = _FakeAdapter((options) async {
      expect(options.path, '/api/staff/reports/rep_1');
      expect(options.headers['Authorization'], 'Bearer staff-token');
      return _json(_reportEnvelope());
    });
    final service = _service(adapter);

    final report = await service.fetchStaffReport('staff-token', 'rep_1');

    expect(report.statusEnum, ReportStatus.assigned);
    expect(report.assignedStaff?.displayLabel, 'Staff A');
    expect(report.assignedDepartment, 'Maintenance');
    expect(report.events, hasLength(2));
    expect(report.events.last.type, 'ASSIGNED');
  });

  test('staff workflow mutations post the expected bodies', () async {
    final calls = <String, RequestOptions>{};
    final adapter = _FakeAdapter((options) async {
      calls[options.path] = options;
      final status = switch (options.path) {
        '/api/staff/reports/rep_1/accept' => 'IN_PROGRESS',
        '/api/staff/reports/rep_1/resolve' => 'RESOLVED',
        _ => 'ASSIGNED',
      };
      return _json(_reportEnvelope(status: status));
    });
    final service = _service(adapter);

    await service.acceptStaffReport('staff-token', 'rep_1');
    await service.addStaffProgressNote(
      'staff-token',
      'rep_1',
      'Parts ordered.',
    );
    await service.resolveStaffReport('staff-token', 'rep_1', 'Valve replaced.');

    expect(calls['/api/staff/reports/rep_1/accept']?.method, 'POST');
    expect(calls['/api/staff/reports/rep_1/progress']?.data, {
      'note': 'Parts ordered.',
    });
    expect(calls['/api/staff/reports/rep_1/resolve']?.data, {
      'resolutionNotes': 'Valve replaced.',
    });
    for (final options in calls.values) {
      expect(options.headers['Authorization'], 'Bearer staff-token');
    }
  });

  test('admin assignment and rejection send the required payloads', () async {
    final calls = <String, RequestOptions>{};
    final adapter = _FakeAdapter((options) async {
      calls[options.path] = options;
      return _json(_reportEnvelope());
    });
    final service = _service(adapter);

    await service.assignStaffReport(
      'admin-token',
      'rep_1',
      staffId: 'staff_a',
      department: 'Maintenance',
    );
    await service.rejectStaffReport(
      'admin-token',
      'rep_1',
      'Duplicate report.',
    );

    expect(calls['/api/staff/reports/rep_1/assign']?.data, {
      'staffId': 'staff_a',
      'department': 'Maintenance',
    });
    expect(calls['/api/staff/reports/rep_1/reject']?.data, {
      'reason': 'Duplicate report.',
    });
  });

  test('workflow conflicts surface the backend message', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'message': 'Only an in-progress report can be resolved.',
      }, 409),
    );
    final service = _service(adapter);

    await expectLater(
      service.resolveStaffReport('staff-token', 'rep_1', 'Done'),
      throwsA(
        isA<ServerException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having(
              (e) => e.message,
              'message',
              'Only an in-progress report can be resolved.',
            ),
      ),
    );
  });
}

Map<String, dynamic> _reportEnvelope({String status = 'ASSIGNED'}) {
  return {
    'success': true,
    'data': {
      'id': 'rep_1',
      'code': 'PULSE-1042',
      'title': 'Leak',
      'description': 'Water near the lab.',
      'category': 'Plumbing',
      'location': 'Block B',
      'priority': 'HIGH',
      'status': status,
      'assignedDepartment': 'Maintenance',
      'assignedAt': '2026-10-20T10:00:00.000Z',
      'assignedStaff': {
        'id': 'staff_a',
        'username': 'staff.a',
        'displayName': 'Staff A',
        'role': 'STAFF',
        'active': true,
      },
      'resolutionNotes': status == 'RESOLVED' ? 'Valve replaced.' : null,
      'rejectionReason': null,
      'events': [
        {
          'id': 'evt_1',
          'type': 'SUBMITTED',
          'actorRole': 'STUDENT',
          'remark': null,
          'createdAt': '2026-10-20T09:00:00.000Z',
        },
        {
          'id': 'evt_2',
          'type': 'ASSIGNED',
          'actorRole': 'ADMIN',
          'remark': 'Maintenance',
          'createdAt': '2026-10-20T10:00:00.000Z',
        },
      ],
      'createdAt': '2026-10-20T09:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      'resolvedAt': status == 'RESOLVED' ? '2026-10-20T11:00:00.000Z' : null,
    },
  };
}
