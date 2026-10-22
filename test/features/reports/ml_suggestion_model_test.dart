import 'package:flutter_test/flutter_test.dart';
import 'package:safebunk_v2/features/reports/data/models/ml_suggestion.dart';

Map<String, dynamic> _categoryJson({
  bool available = true,
  String decision = 'predict',
  bool manualReview = false,
}) {
  return {
    'available': available,
    'suggestionOnly': true,
    'reason': available ? null : 'ml_unavailable',
    'message': available
        ? 'Category suggestion only; no report fields were changed.'
        : 'ML suggestions are temporarily unavailable. No report data was changed.',
    'category': available ? 'Plumbing' : null,
    'confidence': available ? 0.38 : null,
    'modelVersion': available ? '0.1.0' : null,
    'manualReviewRecommended': available ? manualReview : true,
    'decision': available ? decision : 'unavailable',
    'threshold': available ? 0.2 : null,
  };
}

Map<String, dynamic> _duplicateJson({
  bool available = true,
  String decision = 'uncertain',
  List<Map<String, dynamic>>? candidates,
  String? reportId = 'rep_src',
}) {
  return {
    'available': available,
    'suggestionOnly': true,
    'action': 'suggestion_only',
    'reason': available ? null : 'ml_timeout',
    'reportId': reportId,
    'decision': available ? decision : null,
    'candidates': available
        ? (candidates ??
              [
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
                  'reasons': [
                    'similar description text',
                    'same category: Electrical',
                  ],
                },
              ])
        : [],
    'duplicateThreshold': available ? 0.5 : null,
    'uncertainThreshold': available ? 0.4 : null,
    'similarityMetric': available ? 'tfidf_cosine_similarity' : null,
    'rankingMetric': available
        ? 'cosine_similarity_with_metadata_support'
        : null,
    'modelVersion': available ? '0.2.0' : null,
    'scoreNote': 'Ranking score, not a probability.',
    'manualReviewRecommended': true,
    'existingComplaintsEvaluated': available ? 4 : null,
    'message': available
        ? 'Potential duplicates found; these are suggestions only.'
        : 'ML suggestions are temporarily unavailable. No report data was changed.',
  };
}

void main() {
  group('CategorySuggestion', () {
    test('parses a prediction including score, version, and decision', () {
      final suggestion = CategorySuggestion.fromJson(_categoryJson());

      expect(suggestion.available, isTrue);
      expect(suggestion.category, 'Plumbing');
      expect(suggestion.confidence, 0.38);
      expect(suggestion.modelVersion, '0.1.0');
      expect(suggestion.decision, CategorySuggestionDecision.predict);
      expect(suggestion.manualReviewRecommended, isFalse);
      expect(suggestion.canApply, isTrue);
      expect(suggestion.needsManualReview, isFalse);
    });

    test('parses abstention as a manual-review suggestion', () {
      final suggestion = CategorySuggestion.fromJson(
        _categoryJson(decision: 'abstain', manualReview: true),
      );

      expect(suggestion.decision, CategorySuggestionDecision.abstain);
      expect(suggestion.needsManualReview, isTrue);
      expect(suggestion.canApply, isTrue);
    });

    test('parses a safe unavailable response', () {
      final suggestion = CategorySuggestion.fromJson(
        _categoryJson(available: false),
      );

      expect(suggestion.available, isFalse);
      expect(suggestion.category, isNull);
      expect(suggestion.confidence, isNull);
      expect(suggestion.decision, CategorySuggestionDecision.unavailable);
      expect(suggestion.needsManualReview, isTrue);
      expect(
        categorySuggestionFailureMessage(suggestion.reason),
        contains('temporarily unavailable'),
      );
    });

    test('rejects malformed prediction data', () {
      final json = _categoryJson()..remove('modelVersion');

      expect(
        () => CategorySuggestion.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an out-of-range score', () {
      final json = _categoryJson()..['confidence'] = 1.4;

      expect(
        () => CategorySuggestion.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DuplicateSuggestion', () {
    test('parses candidates, scores, decisions, and reasons', () {
      final result = DuplicateSuggestion.fromJson(_duplicateJson());

      expect(result.available, isTrue);
      expect(result.reportId, 'rep_src');
      expect(result.decision, DuplicateSuggestionDecision.uncertain);
      expect(result.modelVersion, '0.2.0');
      expect(result.existingComplaintsEvaluated, 4);
      expect(result.hasCandidates, isTrue);
      expect(result.candidates.single.reportCode, 'PULSE-1043');
      expect(result.candidates.single.reportId, 'rep_2');
      expect(result.candidates.single.similarityScore, 0.47);
      expect(result.candidates.single.rankingScore, 0.51);
      expect(result.candidates.single.reasons, hasLength(2));
    });

    test('accepts a draft preview with no source report id', () {
      final result = DuplicateSuggestion.fromJson(
        _duplicateJson(decision: 'no_match', candidates: [], reportId: null),
      );

      expect(result.reportId, isNull);
      expect(result.decision, DuplicateSuggestionDecision.noMatch);
      expect(result.candidates, isEmpty);
    });

    test('parses unavailable without inventing candidates', () {
      final result = DuplicateSuggestion.fromJson(
        _duplicateJson(available: false),
      );

      expect(result.available, isFalse);
      expect(result.decision, isNull);
      expect(result.candidates, isEmpty);
      expect(result.modelVersion, isNull);
      expect(
        duplicateSuggestionFailureMessage(result.reason),
        contains('timed out'),
      );
    });

    test('rejects a candidate with an invalid score', () {
      final invalid = _duplicateJson();
      (invalid['candidates'] as List).first['rankingScore'] = -0.1;

      expect(
        () => DuplicateSuggestion.fromJson(invalid),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects available responses without a candidates list', () {
      final invalid = _duplicateJson()..remove('candidates');

      expect(
        () => DuplicateSuggestion.fromJson(invalid),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('formats scores as bounded two-decimal values', () {
    expect(formatMlScore(0.456), '0.46');
    expect(formatMlScore(2), '1.00');
  });
}
