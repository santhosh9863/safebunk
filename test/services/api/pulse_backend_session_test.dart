import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
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

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login stores the backend token returned by /api/auth/login', () async {
    final adapter = _FakeAdapter((options) async {
      expect(options.method, 'POST');
      expect(options.path, '/api/auth/login');
      return _json({
        'success': true,
        'data': {
          'accessToken': 'backend-token-1',
          'student': {'studentId': '4301', 'gender': 'M'},
        },
      });
    });
    final service = _service(adapter);

    expect(await service.login('4301', 'secret'), isTrue);
    expect(await service.isLoggedIn, isTrue);
    expect(await service.getDetectedGender(), 'M');
  });

  test(
    'a fresh login clears a previous account token even on failure',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'backend_access_token': 'old-token',
        'backend_student_id': '9999',
        'backend_student_gender': 'F',
      });
      final adapter = _FakeAdapter(
        (_) async => _json({'message': 'bad login'}, 401),
      );
      final service = _service(adapter);

      expect(await service.login('4301', 'wrong'), isFalse);
      expect(await service.isLoggedIn, isFalse);
      expect(await service.getDetectedGender(), '');
    },
  );

  test('an expired backend session is cleared on 401', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_access_token': 'expired-token',
      'backend_student_id': '4301',
    });
    final adapter = _FakeAdapter(
      (_) async => _json({'message': 'Session expired or invalid'}, 401),
    );
    final service = _service(adapter);

    await expectLater(
      service.fetchMyReports(),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(await service.isLoggedIn, isFalse);
  });

  test('logout always removes persisted backend credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_access_token': 'live-token',
      'backend_student_id': '4301',
      'backend_student_gender': 'M',
    });
    final adapter = _FakeAdapter((options) async {
      expect(options.path, '/api/auth/logout');
      return _json({'success': true, 'data': null});
    });
    final service = _service(adapter);

    await service.logout();
    expect(await service.isLoggedIn, isFalse);
    expect(await service.getDetectedGender(), '');
  });

  test('authenticated reports calls send the stored Bearer token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'backend_access_token': 'live-token',
      'backend_student_id': '4301',
    });
    final adapter = _FakeAdapter((options) async {
      expect(options.headers['Authorization'], 'Bearer live-token');
      if (options.path == '/api/reports/my') {
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
      }
      if (options.path == '/api/reports') {
        return _json({
          'success': true,
          'data': {
            'id': 'rep_2',
            'code': 'PULSE-1043',
            'title': 'Leak',
            'description': 'Water near the lab.',
            'imageUrl': '/api/reports/attachments/att_1',
            'priority': 'MEDIUM',
            'status': 'SUBMITTED',
            'createdAt': '2026-10-20T00:00:00.000Z',
            'updatedAt': '2026-10-20T00:00:00.000Z',
          },
        });
      }
      return _json({'message': 'unexpected path ${options.path}'}, 404);
    });
    final service = _service(adapter);

    final reports = await service.fetchMyReports();
    expect(reports, hasLength(1));
    expect(reports.single.id, 'rep_1');

    final created = await service.createReport(
      title: 'Leak',
      description: 'Water near the lab.',
      attachmentId: 'att_1',
    );
    expect(created.id, 'rep_2');
    expect(created.imageUrl, '/api/reports/attachments/att_1');
  });
}
