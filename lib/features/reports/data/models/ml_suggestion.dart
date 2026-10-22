/// Typed views over the NestJS ML suggestion envelopes.
///
/// The Flutter app never talks to the Python ML service. These models are
/// parsed from the authenticated backend responses only. Unknown or malformed
/// shapes throw [FormatException] so the service layer can surface a safe
/// "invalid response" error instead of guessing at a prediction.
library;

enum CategorySuggestionDecision {
  predict('predict'),
  abstain('abstain'),
  unavailable('unavailable');

  const CategorySuggestionDecision(this.apiValue);

  final String apiValue;

  static CategorySuggestionDecision fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'predict' => CategorySuggestionDecision.predict,
      'abstain' => CategorySuggestionDecision.abstain,
      'unavailable' => CategorySuggestionDecision.unavailable,
      _ => throw const FormatException('Invalid category suggestion decision'),
    };
  }

  String get label => switch (this) {
    CategorySuggestionDecision.predict => 'Suggested',
    CategorySuggestionDecision.abstain => 'Low confidence',
    CategorySuggestionDecision.unavailable => 'Unavailable',
  };
}

class CategorySuggestion {
  final bool available;
  final String? reason;
  final String message;
  final String? category;
  final double? confidence;
  final String? modelVersion;
  final bool manualReviewRecommended;
  final CategorySuggestionDecision decision;
  final double? threshold;

  const CategorySuggestion({
    required this.available,
    required this.reason,
    required this.message,
    required this.category,
    required this.confidence,
    required this.modelVersion,
    required this.manualReviewRecommended,
    required this.decision,
    required this.threshold,
  });

  factory CategorySuggestion.fromJson(Map<String, dynamic> json) {
    final available = _requiredBool(json['available'], 'available');
    final reason = _optionalString(json['reason']);
    final message = _optionalString(json['message']) ?? '';

    if (!available) {
      final rawDecision = json['decision'];
      final decision = rawDecision == null
          ? CategorySuggestionDecision.unavailable
          : CategorySuggestionDecision.fromApi(rawDecision);
      if (decision != CategorySuggestionDecision.unavailable) {
        throw const FormatException('Unavailable suggestion had a prediction');
      }
      return CategorySuggestion(
        available: false,
        reason: reason,
        message: message,
        category: null,
        confidence: null,
        modelVersion: null,
        manualReviewRecommended:
            _optionalBool(json['manualReviewRecommended']) ?? true,
        decision: decision,
        threshold: null,
      );
    }

    final category = _requiredString(json['category'], 'category');
    final confidence = _requiredScore(json['confidence'], 'confidence');
    final modelVersion = _requiredString(json['modelVersion'], 'modelVersion');
    final decision = CategorySuggestionDecision.fromApi(json['decision']);
    if (decision == CategorySuggestionDecision.unavailable) {
      throw const FormatException(
        'Available suggestion was marked unavailable',
      );
    }

    return CategorySuggestion(
      available: true,
      reason: reason,
      message: message,
      category: category,
      confidence: confidence,
      modelVersion: modelVersion,
      manualReviewRecommended: _requiredBool(
        json['manualReviewRecommended'],
        'manualReviewRecommended',
      ),
      decision: decision,
      threshold: _requiredScore(json['threshold'], 'threshold'),
    );
  }

  bool get canApply =>
      available &&
      category != null &&
      category!.trim().isNotEmpty &&
      decision != CategorySuggestionDecision.unavailable;

  bool get needsManualReview =>
      !available ||
      manualReviewRecommended ||
      decision == CategorySuggestionDecision.abstain;
}

enum DuplicateSuggestionDecision {
  match('match'),
  uncertain('uncertain'),
  noMatch('no_match');

  const DuplicateSuggestionDecision(this.apiValue);

  final String apiValue;

  static DuplicateSuggestionDecision fromApi(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'match' => DuplicateSuggestionDecision.match,
      'uncertain' => DuplicateSuggestionDecision.uncertain,
      'no_match' => DuplicateSuggestionDecision.noMatch,
      _ => throw const FormatException('Invalid duplicate decision'),
    };
  }

  String get label => switch (this) {
    DuplicateSuggestionDecision.match => 'Possible match',
    DuplicateSuggestionDecision.uncertain => 'Uncertain — review manually',
    DuplicateSuggestionDecision.noMatch => 'No match found',
  };
}

class DuplicateCandidate {
  final String reportId;
  final String reportCode;
  final String title;
  final String status;
  final String? category;
  final String? location;
  final double similarityScore;
  final double rankingScore;
  final bool categoryMatch;
  final bool locationMatch;
  final List<String> reasons;

  const DuplicateCandidate({
    required this.reportId,
    required this.reportCode,
    required this.title,
    required this.status,
    required this.category,
    required this.location,
    required this.similarityScore,
    required this.rankingScore,
    required this.categoryMatch,
    required this.locationMatch,
    required this.reasons,
  });

  factory DuplicateCandidate.fromJson(Map<String, dynamic> json) {
    final rawReasons = json['reasons'];
    if (rawReasons is! List) {
      throw const FormatException('Duplicate candidate reasons were invalid');
    }
    final reasons = rawReasons
        .map((value) => _requiredString(value, 'reason'))
        .toList(growable: false);

    return DuplicateCandidate(
      reportId: _requiredString(json['reportId'], 'reportId'),
      reportCode: _requiredString(json['reportCode'], 'reportCode'),
      title: _requiredString(json['title'], 'title'),
      status: _requiredString(json['status'], 'status'),
      category: _optionalString(json['category']),
      location: _optionalString(json['location']),
      similarityScore: _requiredScore(
        json['similarityScore'],
        'similarityScore',
      ),
      rankingScore: _requiredScore(json['rankingScore'], 'rankingScore'),
      categoryMatch: _requiredBool(json['categoryMatch'], 'categoryMatch'),
      locationMatch: _requiredBool(json['locationMatch'], 'locationMatch'),
      reasons: reasons,
    );
  }
}

class DuplicateSuggestion {
  final bool available;
  final String? reason;
  final String message;
  final String? reportId;
  final DuplicateSuggestionDecision? decision;
  final List<DuplicateCandidate> candidates;
  final double? duplicateThreshold;
  final double? uncertainThreshold;
  final String? similarityMetric;
  final String? rankingMetric;
  final String? modelVersion;
  final String scoreNote;
  final bool manualReviewRecommended;
  final int? existingComplaintsEvaluated;

  const DuplicateSuggestion({
    required this.available,
    required this.reason,
    required this.message,
    required this.reportId,
    required this.decision,
    required this.candidates,
    required this.duplicateThreshold,
    required this.uncertainThreshold,
    required this.similarityMetric,
    required this.rankingMetric,
    required this.modelVersion,
    required this.scoreNote,
    required this.manualReviewRecommended,
    required this.existingComplaintsEvaluated,
  });

  factory DuplicateSuggestion.fromJson(Map<String, dynamic> json) {
    final available = _requiredBool(json['available'], 'available');
    final reason = _optionalString(json['reason']);
    final message = _optionalString(json['message']) ?? '';
    final reportId = _optionalString(json['reportId']);
    final scoreNote = _optionalString(json['scoreNote']) ?? '';

    if (!available) {
      final rawCandidates = json['candidates'];
      if (rawCandidates is List && rawCandidates.isNotEmpty) {
        throw const FormatException('Unavailable suggestion had candidates');
      }
      return DuplicateSuggestion(
        available: false,
        reason: reason,
        message: message,
        reportId: reportId,
        decision: null,
        candidates: const [],
        duplicateThreshold: null,
        uncertainThreshold: null,
        similarityMetric: null,
        rankingMetric: null,
        modelVersion: null,
        scoreNote: scoreNote,
        manualReviewRecommended:
            _optionalBool(json['manualReviewRecommended']) ?? true,
        existingComplaintsEvaluated: null,
      );
    }

    final rawCandidates = json['candidates'];
    if (rawCandidates is! List) {
      throw const FormatException('Duplicate candidates were invalid');
    }
    final candidates = rawCandidates
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Duplicate candidate was invalid');
          }
          return DuplicateCandidate.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);

    final evaluated = json['existingComplaintsEvaluated'];
    if (evaluated is! num ||
        evaluated < 0 ||
        evaluated != evaluated.roundToDouble()) {
      throw const FormatException('Evaluated complaint count was invalid');
    }

    return DuplicateSuggestion(
      available: true,
      reason: reason,
      message: message,
      reportId: reportId,
      decision: DuplicateSuggestionDecision.fromApi(json['decision']),
      candidates: candidates,
      duplicateThreshold: _requiredScore(
        json['duplicateThreshold'],
        'duplicateThreshold',
      ),
      uncertainThreshold: _requiredScore(
        json['uncertainThreshold'],
        'uncertainThreshold',
      ),
      similarityMetric: _optionalString(json['similarityMetric']),
      rankingMetric: _optionalString(json['rankingMetric']),
      modelVersion: _requiredString(json['modelVersion'], 'modelVersion'),
      scoreNote: scoreNote,
      manualReviewRecommended: _requiredBool(
        json['manualReviewRecommended'],
        'manualReviewRecommended',
      ),
      existingComplaintsEvaluated: evaluated.toInt(),
    );
  }

  bool get hasCandidates => candidates.isNotEmpty;
}

String categorySuggestionFailureMessage(String? reason) {
  return switch (reason) {
    'ml_not_configured' =>
      'Category suggestions are not configured for this build.',
    'ml_timeout' => 'The category suggestion timed out. Please try again.',
    'ml_unavailable' => 'Category suggestions are temporarily unavailable.',
    'ml_request_rejected' => 'The category suggestion request was rejected.',
    'ml_invalid_response' =>
      'The category service returned an unexpected response.',
    _ => 'Category suggestions are temporarily unavailable.',
  };
}

String duplicateSuggestionFailureMessage(String? reason) {
  return switch (reason) {
    'ml_not_configured' =>
      'Duplicate checks are not configured for this build.',
    'ml_timeout' => 'The duplicate check timed out. Please try again.',
    'ml_unavailable' => 'Duplicate checks are temporarily unavailable.',
    'ml_request_rejected' => 'The duplicate check request was rejected.',
    'ml_invalid_response' =>
      'The duplicate service returned an unexpected response.',
    _ => 'Duplicate checks are temporarily unavailable.',
  };
}

String formatMlScore(double value) {
  final bounded = value.clamp(0.0, 1.0);
  return bounded.toStringAsFixed(2);
}

bool _requiredBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('$field was invalid');
}

bool? _optionalBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Expected a boolean');
}

double _requiredScore(Object? value, String field) {
  if (value is! num) throw FormatException('$field was invalid');
  final score = value.toDouble();
  if (!score.isFinite || score < 0 || score > 1) {
    throw FormatException('$field was out of range');
  }
  return score;
}

String _requiredString(Object? value, String field) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException('$field was invalid');
  }
  return text;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
