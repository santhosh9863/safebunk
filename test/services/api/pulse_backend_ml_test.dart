import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/features/reports/data/models/ml_suggestion.dart';
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
  return PulseBackendService(
    baseUrl: 'http://localhost:3000',
    dio: dio,
    storage: const FlutterSecureStorage(),
  );
}

Map<String, dynamic> _categoryEnvelope({bool available = true}) {
  return {
    'success': true,
    'message': 'Suggestion only; no report was changed.',
    'statusCode': 200,
    'data': {
      'available': available,
      'suggestionOnly': true,
      'reason': available ? null : 'ml_unavailable',
      'message': available
          ? 'Category suggestion only; no report fields were changed.'
          : 'ML suggestions are temporarily unavailable. No report data was changed.',
      'category': available ? 'Plumbing' : null,
      'confidence': available ? 0.38 : null,
      'modelVersion': available ? '0.1.0' : null,
      'manualReviewRecommended': !available,
      'decision': available ? 'predict' : 'unavailable',
      'threshold': available ? 0.2 : null,
    },
  };
}

Map<String, dynamic> _duplicateEnvelope({
  String? reportId = 'rep_src',
  String decision = 'uncertain',
}) {
  return {
    'success': true,
    'message': 'Suggestion only; no report was changed.',
    'statusCode': 200,
    'data': {
      'available': true,
      'suggestionOnly': true,
      'action': 'suggestion_only',
      'reason': null,
      'reportId': reportId,
      'decision': decision,
      'candidates': [
        {
          'reportId': 'rep_2',
          'reportCode': 'PULSE-1043',
          'title': 'Library lighting problem',
          'status': 'SUBMITTED',
          'category': 'Electrical',
          'location': 'Main Library',
          'similarityScore': 0.47,
          'rankingScore': 0.51,
          'categoryMatch': true,
          'locationMatch': true,
          'reasons': ['similar description text', 'same category: Electrical'],
        },
      ],
      'duplicateThreshold': 0.5,
      'uncertainThreshold': 0.4,
      'similarityMetric': 'tfidf_cosine_similarity',
      'rankingMetric': 'cosine_similarity_with_metadata_support',
      'modelVersion': '0.2.0',
      'scoreNote': 'Ranking score, not a probability.',
      'manualReviewRecommended': true,
      'existingComplaintsEvaluated': 4,
      'message': 'Potential duplicates found; these are suggestions only.',
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'backend_access_token': 'student-token',
    });
  });

  test('category suggestion uses the authenticated backend route', () async {
    final adapter = _FakeAdapter((_) async => _json(_categoryEnvelope()));
    final service = _service(adapter);

    final suggestion = await service.suggestCategory('Leaking pipe');

    expect(suggestion.category, 'Plumbing');
    expect(suggestion.confidence, 0.38);
    expect(suggestion.modelVersion, '0.1.0');
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/api/ml/category-suggestion');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer student-token',
    );
    expect(adapter.requests.single.data, {'description': 'Leaking pipe'});
  });

  test('draft duplicate preview sends only draft fields', () async {
    final adapter = _FakeAdapter(
      (_) async => _json(_duplicateEnvelope(reportId: null)),
    );
    final service = _service(adapter);

    final result = await service.suggestDraftDuplicates(
      description: '  The library lights keep flickering.  ',
      category: 'Electrical',
      location: ' Main Library ',
    );

    expect(result.reportId, isNull);
    expect(result.candidates.single.reportCode, 'PULSE-1043');
    expect(
      adapter.requests.single.path,
      '/api/ml/duplicate-suggestions/preview',
    );
    expect(adapter.requests.single.data, {
      'description': 'The library lights keep flickering.',
      'category': 'Electrical',
      'location': 'Main Library',
      'maxCandidates': 5,
    });
  });

  test('student report duplicate route uses the report id', () async {
    final adapter = _FakeAdapter((_) async => _json(_duplicateEnvelope()));
    final service = _service(adapter);

    final result = await service.suggestDuplicates('rep_src');

    expect(result.decision, DuplicateSuggestionDecision.uncertain);
    expect(
      adapter.requests.single.path,
      '/api/ml/duplicate-suggestions/rep_src',
    );
    expect(adapter.requests.single.data, {'maxCandidates': 5});
  });

  test('staff duplicate route sends the staff Bearer token', () async {
    final adapter = _FakeAdapter((_) async => _json(_duplicateEnvelope()));
    final service = _service(adapter);

    final result = await service.suggestStaffDuplicates(
      'staff-token',
      'rep_src',
      maxCandidates: 3,
    );

    expect(result.available, isTrue);
    expect(
      adapter.requests.single.path,
      '/api/staff/ml/duplicate-suggestions/rep_src',
    );
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer staff-token',
    );
    expect(adapter.requests.single.data, {'maxCandidates': 3});
  });

  test('available:false is a safe typed response, not an exception', () async {
    final adapter = _FakeAdapter(
      (_) async => _json(_categoryEnvelope(available: false)),
    );
    final service = _service(adapter);

    final suggestion = await service.suggestCategory('Leaking pipe');

    expect(suggestion.available, isFalse);
    expect(suggestion.reason, 'ml_unavailable');
    expect(suggestion.category, isNull);
    expect(suggestion.needsManualReview, isTrue);
  });

  test('malformed ML data becomes a BadResponseException', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'success': true,
        'data': {'available': true, 'category': 'Plumbing'},
      }),
    );
    final service = _service(adapter);

    await expectLater(
      service.suggestCategory('Leaking pipe'),
      throwsA(isA<BadResponseException>()),
    );
  });

  test(
    'student 401 clears the stale token and reports session expiry',
    () async {
      final adapter = _FakeAdapter(
        (_) async => _json({'message': 'Session expired'}, 401),
      );
      final service = _service(adapter);

      await expectLater(
        service.suggestCategory('Leaking pipe'),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(
        await const FlutterSecureStorage().read(key: 'backend_access_token'),
        isNull,
      );
    },
  );

  test('staff 401 reports session expiry', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({'message': 'Expired'}, 401),
    );
    final service = _service(adapter);

    await expectLater(
      service.suggestStaffDuplicates('staff-token', 'rep_src'),
      throwsA(isA<SessionExpiredException>()),
    );
  });

  test('upstream 403 is surfaced as a permission error', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({'message': 'Forbidden'}, 403),
    );
    final service = _service(adapter);

    await expectLater(
      service.suggestStaffDuplicates('staff-token', 'rep_src'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('transport timeout is surfaced as a timeout', () async {
    final adapter = _FakeAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    });
    final service = _service(adapter);

    await expectLater(
      service.suggestCategory('Leaking pipe'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
