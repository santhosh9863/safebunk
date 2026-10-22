import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/features/reports/application/reports_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/ml_suggestion.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/presentation/screens/report_detail_screen.dart';
import 'package:safebunk_v2/services/api/pulse_backend_service.dart';

final _report = ReportModel(
  id: 'rep_1',
  code: 'PULSE-1042',
  title: 'Water leakage',
  description: 'Water near the electrical panel.',
  category: 'Plumbing',
  location: 'Block B',
  imageUrl: null,
  priority: 'HIGH',
  status: 'SUBMITTED',
  assignedDepartment: null,
  aiCategory: null,
  aiPriority: null,
  aiConfidence: null,
  createdAt: DateTime.utc(2026, 10, 20, 9),
  updatedAt: DateTime.utc(2026, 10, 20, 9),
  resolvedAt: null,
);

const _candidate = DuplicateCandidate(
  reportId: 'rep_2',
  reportCode: 'PULSE-1043',
  title: 'Library lighting problem',
  status: 'SUBMITTED',
  category: 'Electrical',
  location: 'Main Library',
  similarityScore: 0.47,
  rankingScore: 0.51,
  categoryMatch: true,
  locationMatch: true,
  reasons: ['similar description text', 'same category: Electrical'],
);

DuplicateSuggestion _result({
  bool available = true,
  List<DuplicateCandidate> candidates = const [],
  String decision = 'uncertain',
}) {
  return DuplicateSuggestion(
    available: available,
    reason: available ? null : 'ml_unavailable',
    message: available ? 'Suggestions found.' : 'ML unavailable.',
    reportId: 'rep_1',
    decision: available
        ? (decision == 'match'
              ? DuplicateSuggestionDecision.match
              : decision == 'no_match'
              ? DuplicateSuggestionDecision.noMatch
              : DuplicateSuggestionDecision.uncertain)
        : null,
    candidates: available ? candidates : const [],
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

class _FakeDetailBackend extends PulseBackendService {
  _FakeDetailBackend({this.result, this.error})
    : super(baseUrl: 'http://localhost:3000');

  DuplicateSuggestion? result;
  Object? error;
  int calls = 0;
  String? lastReportId;

  @override
  Future<DuplicateSuggestion> suggestDuplicates(
    String reportId, {
    int maxCandidates = 5,
  }) async {
    calls++;
    lastReportId = reportId;
    if (error != null) throw error!;
    return result ?? _result();
  }
}

Future<void> _pump(WidgetTester tester, _FakeDetailBackend backend) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reportDetailProvider(_report.id).overrideWith((ref) async => _report),
        pulseBackendServiceProvider.overrideWithValue(backend),
      ],
      child: MaterialApp(
        home: ReportDetailScreen(reportId: _report.id, initial: _report),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester) async {
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
  testWidgets('student report detail shows possible duplicates with evidence', (
    tester,
  ) async {
    final backend = _FakeDetailBackend(
      result: _result(candidates: const [_candidate], decision: 'match'),
    );
    await _pump(tester, backend);
    expect(find.text('Water leakage'), findsOneWidget);

    await _check(tester);

    expect(backend.calls, 1);
    expect(backend.lastReportId, 'rep_1');
    expect(find.text('PULSE-1043'), findsOneWidget);
    expect(find.textContaining('Similarity 0.47'), findsOneWidget);
    expect(find.textContaining('Ranking 0.51'), findsOneWidget);
    expect(
      find.textContaining('Possible matches — not confirmed duplicates'),
      findsOneWidget,
    );
    expect(find.text('similar description text'), findsOneWidget);
    expect(find.textContaining('Model 0.2.0'), findsOneWidget);
    expect(find.textContaining('Report ID: rep_2'), findsOneWidget);
  });

  testWidgets('student detail keeps working when duplicate ML is unavailable', (
    tester,
  ) async {
    final backend = _FakeDetailBackend(result: _result(available: false));
    await _pump(tester, backend);
    expect(find.text('Water leakage'), findsOneWidget);

    await _check(tester);

    expect(find.text('ML suggestions unavailable'), findsOneWidget);
    expect(find.textContaining('unaffected'), findsOneWidget);
  });

  testWidgets('empty duplicate results are labelled clearly', (tester) async {
    final backend = _FakeDetailBackend(result: _result(decision: 'no_match'));
    await _pump(tester, backend);

    await _check(tester);

    expect(find.text('No possible duplicates found.'), findsOneWidget);
    expect(find.textContaining('Compared with 3'), findsOneWidget);
  });

  testWidgets('expired backend session is shown without hiding the report', (
    tester,
  ) async {
    final backend = _FakeDetailBackend(
      error: const SessionExpiredException(
        'Your PULSE backend session expired. Log out and sign in again.',
      ),
    );
    await _pump(tester, backend);
    expect(find.text('Water leakage'), findsOneWidget);

    await _check(tester);

    expect(find.textContaining('session expired'), findsOneWidget);
  });
}
