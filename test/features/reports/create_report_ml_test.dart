import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/core/errors/app_exceptions.dart';
import 'package:safebunk_v2/features/notifications/application/notification_providers.dart';
import 'package:safebunk_v2/features/reports/data/models/ml_suggestion.dart';
import 'package:safebunk_v2/features/reports/data/models/report_model.dart';
import 'package:safebunk_v2/features/reports/presentation/screens/create_report_screen.dart';
import 'package:safebunk_v2/services/api/pulse_backend_service.dart';

CategorySuggestion _category({
  bool available = true,
  String decision = 'predict',
  bool manualReview = false,
}) {
  return CategorySuggestion(
    available: available,
    reason: available ? null : 'ml_unavailable',
    message: available ? 'Suggestion only.' : 'ML unavailable.',
    category: available ? 'Plumbing' : null,
    confidence: available ? 0.38 : null,
    modelVersion: available ? '0.1.0' : null,
    manualReviewRecommended: available ? manualReview : true,
    decision: available
        ? (decision == 'abstain'
              ? CategorySuggestionDecision.abstain
              : CategorySuggestionDecision.predict)
        : CategorySuggestionDecision.unavailable,
    threshold: available ? 0.2 : null,
  );
}

DuplicateSuggestion _duplicates({
  bool available = true,
  List<DuplicateCandidate> candidates = const [],
  String decision = 'uncertain',
}) {
  return DuplicateSuggestion(
    available: available,
    reason: available ? null : 'ml_timeout',
    message: available ? 'Suggestions found.' : 'ML unavailable.',
    reportId: null,
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
    existingComplaintsEvaluated: available ? 4 : null,
  );
}

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

class _FakeMlBackend extends PulseBackendService {
  _FakeMlBackend({
    this.category = const CategorySuggestion(
      available: true,
      reason: null,
      message: 'Suggestion only.',
      category: 'Plumbing',
      confidence: 0.38,
      modelVersion: '0.1.0',
      manualReviewRecommended: false,
      decision: CategorySuggestionDecision.predict,
      threshold: 0.2,
    ),
    this.duplicate,
    this.categoryError,
    this.duplicateError,
  }) : super(baseUrl: 'http://localhost:3000');

  CategorySuggestion category;
  DuplicateSuggestion? duplicate;
  Object? categoryError;
  Object? duplicateError;

  int categoryCalls = 0;
  int draftDuplicateCalls = 0;
  int createCalls = 0;
  String? lastDescription;

  @override
  Future<CategorySuggestion> suggestCategory(String description) async {
    categoryCalls++;
    lastDescription = description;
    if (categoryError != null) throw categoryError!;
    return category;
  }

  @override
  Future<DuplicateSuggestion> suggestDraftDuplicates({
    required String description,
    String? category,
    String? location,
    int maxCandidates = 5,
  }) async {
    draftDuplicateCalls++;
    lastDescription = description;
    if (duplicateError != null) throw duplicateError!;
    return duplicate ?? _duplicates();
  }

  @override
  Future<ReportModel> createReport({
    required String title,
    required String description,
    String? category,
    String? location,
    String? priority,
    String? attachmentId,
  }) async {
    createCalls++;
    return ReportModel(
      id: 'rep_new',
      code: 'PULSE-2000',
      title: title,
      description: description,
      category: category,
      location: location,
      imageUrl: null,
      priority: priority ?? 'MEDIUM',
      status: 'SUBMITTED',
      assignedDepartment: null,
      aiCategory: null,
      aiPriority: null,
      aiConfidence: null,
      createdAt: DateTime.utc(2026, 10, 21, 9),
      updatedAt: DateTime.utc(2026, 10, 21, 9),
      resolvedAt: null,
    );
  }
}

Future<void> _pumpCreate(WidgetTester tester, _FakeMlBackend backend) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [pulseBackendServiceProvider.overrideWithValue(backend)],
      child: const MaterialApp(home: CreateReportScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterRequiredFields(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Title'),
    'Library lighting problem',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Description'),
    'The lights in the main library reading room keep flickering constantly.',
  );
  await tester.pump();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('suggested category is displayed and only applied on request', (
    tester,
  ) async {
    final backend = _FakeMlBackend();
    await _pumpCreate(tester, backend);
    await _enterRequiredFields(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suggest category'));
    await tester.pumpAndSettle();

    expect(backend.categoryCalls, 1);
    expect(
      backend.lastDescription,
      'The lights in the main library reading room keep flickering constantly.',
    );
    expect(find.text('Suggested category'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.textContaining('0.38'), findsOneWidget);
    expect(find.textContaining('Model 0.1.0'), findsOneWidget);
    expect(find.text('Use suggested category'), findsOneWidget);

    // Still no category applied to the form before the explicit tap.
    expect(find.text('Suggested category selected'), findsNothing);

    await _scrollTo(tester, find.text('Use suggested category'));
    await tester.tap(find.text('Use suggested category'));
    await tester.pumpAndSettle();

    expect(find.text('Suggested category selected'), findsOneWidget);
    expect(backend.createCalls, 0);
  });

  testWidgets('abstention shows a manual-review warning', (tester) async {
    final backend = _FakeMlBackend(
      category: _category(decision: 'abstain', manualReview: true),
    );
    await _pumpCreate(tester, backend);
    await _enterRequiredFields(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suggest category'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Low confidence'), findsWidgets);
    expect(find.textContaining('review the category manually'), findsOneWidget);
    expect(find.text('Use suggested category'), findsOneWidget);
  });

  testWidgets('unavailable category service does not block submission', (
    tester,
  ) async {
    final backend = _FakeMlBackend(category: _category(available: false));
    await _pumpCreate(tester, backend);
    await _enterRequiredFields(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suggest category'));
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);

    await _scrollTo(tester, find.text('Submit Report'));
    expect(find.text('Submit Report'), findsOneWidget);
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(backend.createCalls, 1);
  });

  testWidgets('expired session message is shown without blocking submission', (
    tester,
  ) async {
    final backend = _FakeMlBackend(
      categoryError: const SessionExpiredException(
        'Your PULSE backend session expired. Log out and sign in again.',
      ),
    );
    await _pumpCreate(tester, backend);
    await _enterRequiredFields(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suggest category'));
    await tester.pumpAndSettle();

    expect(find.textContaining('session expired'), findsOneWidget);
    await _scrollTo(tester, find.text('Submit Report'));
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(backend.createCalls, 1);
  });

  testWidgets(
    'pre-submission duplicate check shows matches but does not block',
    (tester) async {
      final backend = _FakeMlBackend(
        duplicate: _duplicates(
          candidates: const [_candidate],
          decision: 'match',
        ),
      );
      await _pumpCreate(tester, backend);
      await _enterRequiredFields(tester);

      await _scrollTo(tester, find.text('Check possible duplicates'));
      await tester.tap(find.text('Check possible duplicates'));
      await tester.pumpAndSettle();

      expect(backend.draftDuplicateCalls, 1);
      expect(find.text('PULSE-1043'), findsOneWidget);
      expect(find.textContaining('Similarity 0.47'), findsOneWidget);
      expect(find.textContaining('Ranking 0.51'), findsOneWidget);
      expect(
        find.textContaining('Possible matches — not confirmed duplicates'),
        findsOneWidget,
      );
      expect(find.text('similar description text'), findsOneWidget);

      await _scrollTo(tester, find.text('Submit Report'));
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(backend.createCalls, 1);
    },
  );

  testWidgets('duplicate check errors stay inline and never block submission', (
    tester,
  ) async {
    final backend = _FakeMlBackend(
      duplicateError: const TimeoutException(
        'The duplicate check timed out. Please try again.',
      ),
    );
    await _pumpCreate(tester, backend);
    await _enterRequiredFields(tester);

    await _scrollTo(tester, find.text('Check possible duplicates'));
    await tester.tap(find.text('Check possible duplicates'));
    await tester.pumpAndSettle();

    expect(find.text('Could not check for duplicates'), findsOneWidget);
    expect(find.textContaining('timed out'), findsOneWidget);

    await _scrollTo(tester, find.text('Submit Report'));
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(backend.createCalls, 1);
  });

  testWidgets(
    'unavailable duplicate check is safe and empty results are clear',
    (tester) async {
      final backend = _FakeMlBackend(duplicate: _duplicates(available: false));
      await _pumpCreate(tester, backend);
      await _enterRequiredFields(tester);

      await _scrollTo(tester, find.text('Check possible duplicates'));
      await tester.tap(find.text('Check possible duplicates'));
      await tester.pumpAndSettle();

      expect(find.text('ML suggestions unavailable'), findsOneWidget);
      expect(find.textContaining('unaffected'), findsOneWidget);

      backend.duplicate = _duplicates(decision: 'no_match');
      await _scrollTo(tester, find.text('Check possible duplicates'));
      await tester.tap(find.text('Check possible duplicates'));
      await tester.pumpAndSettle();

      expect(find.text('No possible duplicates found.'), findsOneWidget);
      await _scrollTo(tester, find.text('Submit Report'));
      expect(find.text('Submit Report'), findsOneWidget);
    },
  );
}
