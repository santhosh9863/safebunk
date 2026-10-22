"""TF-IDF cosine scoring and read-only duplicate candidate ranking.

The Phase 2 baseline built a vectorizer for every request. Phase 2.1 uses a
fitted vectorizer loaded from a versioned artifact; this module only transforms
text and never fits on incoming complaints. Nothing here merges, rejects, or
edits a complaint.
"""

from __future__ import annotations

import math
import unicodedata
from dataclasses import dataclass
from typing import Final, Literal

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.pipeline import FeatureUnion

# Phase 2 baseline operating point. Phase 2.1 candidate defaults come from the
# trained artifact and are not hard-coded in the request contract.
DEFAULT_DUPLICATE_THRESHOLD: Final[float] = 0.20
DEFAULT_UNCERTAIN_THRESHOLD: Final[float] = 0.10
SIMILARITY_METRIC: Final[str] = "tfidf_cosine_similarity"
RANKING_METRIC: Final[str] = "cosine_similarity_with_metadata_support"
SCORE_NOTE: Final[str] = (
    "Cosine similarity is a ranking score, not a probability. Category and "
    "location matches add a small supporting boost and cannot create a match "
    "without text similarity."
)
SUGGESTION_ACTION: Final[str] = "suggestion_only"
MIN_TEXT_EVIDENCE: Final[float] = 0.05
CATEGORY_SUPPORT: Final[float] = 0.02
LOCATION_SUPPORT: Final[float] = 0.02

Decision = Literal["match", "uncertain", "no_match"]


@dataclass(frozen=True)
class NewComplaint:
    description: str
    category: str | None = None
    location: str | None = None


@dataclass(frozen=True)
class ExistingComplaint:
    complaint_id: str
    description: str
    category: str | None = None
    location: str | None = None


@dataclass(frozen=True)
class DuplicateCandidate:
    complaint_id: str
    similarity_score: float
    ranking_score: float
    category: str | None
    location: str | None
    category_match: bool
    location_match: bool
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class DuplicateDetectionResult:
    decision: Decision
    candidates: tuple[DuplicateCandidate, ...]
    duplicate_threshold: float
    uncertain_threshold: float
    manual_review_recommended: bool
    existing_complaints_evaluated: int
    message: str


@dataclass(frozen=True)
class DuplicateFeatureConfig:
    """Persisted preprocessing and TF-IDF feature configuration."""

    name: str
    word_ngram_range: tuple[int, int] = (1, 2)
    char_ngram_range: tuple[int, int] = (3, 5)
    use_stop_words: bool = True
    sublinear_tf: bool = True
    lowercase: bool = True
    strip_accents: str | None = "unicode"

    def to_dict(self) -> dict[str, object]:
        return {
            "name": self.name,
            "text_normalization": "nfkc_whitespace",
            "word_analyzer": "word",
            "word_ngram_range": list(self.word_ngram_range),
            "word_stop_words": "english" if self.use_stop_words else None,
            "char_analyzer": "char_wb",
            "char_ngram_range": list(self.char_ngram_range),
            "sublinear_tf": self.sublinear_tf,
            "lowercase": self.lowercase,
            "strip_accents": self.strip_accents,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, object]) -> DuplicateFeatureConfig:
        word_range = payload.get("word_ngram_range")
        char_range = payload.get("char_ngram_range")
        if not isinstance(word_range, list) or len(word_range) != 2:
            raise ValueError("word_ngram_range must be a two-item list")
        if not isinstance(char_range, list) or len(char_range) != 2:
            raise ValueError("char_ngram_range must be a two-item list")
        try:
            normalized_word_range = (int(word_range[0]), int(word_range[1]))
            normalized_char_range = (int(char_range[0]), int(char_range[1]))
        except (TypeError, ValueError) as exc:
            raise ValueError("ngram ranges must contain integers") from exc

        name = payload.get("name")
        if not isinstance(name, str) or not name.strip():
            raise ValueError("feature config name must be a non-empty string")
        return cls(
            name=name,
            word_ngram_range=normalized_word_range,
            char_ngram_range=normalized_char_range,
            use_stop_words=payload.get("word_stop_words") == "english",
            sublinear_tf=bool(payload.get("sublinear_tf", True)),
            lowercase=bool(payload.get("lowercase", True)),
            strip_accents=(
                str(payload["strip_accents"]) if payload.get("strip_accents") is not None else None
            ),
        )


@dataclass(frozen=True)
class DuplicateSupportConfig:
    """Small metadata ranking signals; never sufficient on their own."""

    category_support: float = CATEGORY_SUPPORT
    location_support: float = LOCATION_SUPPORT
    min_text_evidence: float = MIN_TEXT_EVIDENCE

    def to_dict(self) -> dict[str, float]:
        return {
            "category_support": self.category_support,
            "location_support": self.location_support,
            "min_text_evidence": self.min_text_evidence,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, object]) -> DuplicateSupportConfig:
        category_value = payload.get("category_support")
        location_value = payload.get("location_support")
        evidence_value = payload.get("min_text_evidence")
        if not isinstance(category_value, (int, float)):
            raise ValueError("category_support must be numeric")
        if not isinstance(location_value, (int, float)):
            raise ValueError("location_support must be numeric")
        if not isinstance(evidence_value, (int, float)):
            raise ValueError("min_text_evidence must be numeric")
        category_support = float(category_value)
        location_support = float(location_value)
        min_text_evidence = float(evidence_value)
        values = (category_support, location_support, min_text_evidence)
        if any(not math.isfinite(value) for value in values):
            raise ValueError("support weights must be finite")
        if category_support < 0.0 or location_support < 0.0:
            raise ValueError("support weights must be non-negative")
        if not 0.0 <= min_text_evidence <= 1.0:
            raise ValueError("min_text_evidence must be between 0 and 1")
        return cls(
            category_support=category_support,
            location_support=location_support,
            min_text_evidence=min_text_evidence,
        )


FEATURE_CONFIGS: Final[tuple[DuplicateFeatureConfig, ...]] = (
    DuplicateFeatureConfig(name="word12_char35_stopwords"),
    DuplicateFeatureConfig(name="word12_char35_all_words", use_stop_words=False),
    DuplicateFeatureConfig(
        name="word11_char24_stopwords",
        word_ngram_range=(1, 1),
        char_ngram_range=(2, 4),
    ),
    DuplicateFeatureConfig(
        name="word11_char25_stopwords",
        word_ngram_range=(1, 1),
        char_ngram_range=(2, 5),
    ),
    DuplicateFeatureConfig(
        name="word12_char24_stopwords",
        char_ngram_range=(2, 4),
    ),
    DuplicateFeatureConfig(
        name="word12_char25_stopwords",
        char_ngram_range=(2, 5),
    ),
)
DEFAULT_SUPPORT_CONFIG: Final[DuplicateSupportConfig] = DuplicateSupportConfig()


def validate_thresholds(duplicate_threshold: float, uncertain_threshold: float) -> None:
    """Reject inverted, non-finite, or out-of-range thresholds."""

    values = (duplicate_threshold, uncertain_threshold)
    if any(not math.isfinite(value) for value in values):
        raise ValueError("thresholds must be finite numbers")
    if not 0.0 <= uncertain_threshold < duplicate_threshold <= 1.0:
        raise ValueError("thresholds must satisfy 0 <= uncertain < duplicate <= 1")


def normalize_complaint_text(text: str) -> str:
    """Persisted normalization used by both fitting and inference."""

    normalized = unicodedata.normalize("NFKC", text)
    return " ".join(normalized.split())


def build_tfidf_vectorizer() -> FeatureUnion:
    """Return the frozen Phase 2 word + character baseline.

    This builder is retained for reproducing the Phase 2 v0.1.0 evaluation. It
    is not used by the Phase 2.1 service.
    """

    return FeatureUnion(
        [
            (
                "word",
                TfidfVectorizer(
                    analyzer="word",
                    ngram_range=(1, 2),
                    stop_words="english",
                    sublinear_tf=True,
                    strip_accents="unicode",
                    lowercase=True,
                ),
            ),
            (
                "char",
                TfidfVectorizer(
                    analyzer="char_wb",
                    ngram_range=(3, 5),
                    stop_words=None,
                    sublinear_tf=True,
                    strip_accents="unicode",
                    lowercase=True,
                ),
            ),
        ]
    )


def build_duplicate_vectorizer(config: DuplicateFeatureConfig) -> FeatureUnion:
    """Build the persisted candidate vectorizer for one feature configuration."""

    return FeatureUnion(
        [
            (
                "word",
                TfidfVectorizer(
                    analyzer="word",
                    ngram_range=config.word_ngram_range,
                    stop_words="english" if config.use_stop_words else None,
                    sublinear_tf=config.sublinear_tf,
                    strip_accents=config.strip_accents,
                    lowercase=config.lowercase,
                    preprocessor=normalize_complaint_text,
                ),
            ),
            (
                "char",
                TfidfVectorizer(
                    analyzer="char_wb",
                    ngram_range=config.char_ngram_range,
                    stop_words=None,
                    sublinear_tf=config.sublinear_tf,
                    strip_accents=config.strip_accents,
                    lowercase=config.lowercase,
                    preprocessor=normalize_complaint_text,
                ),
            ),
        ]
    )


def score_text_similarity(
    vectorizer: FeatureUnion,
    left: str,
    right: str,
) -> float:
    """Compute cosine similarity for one pair using an already-fitted vectorizer."""

    matrix = vectorizer.transform([left, right])
    score = cosine_similarity(matrix[0:1], matrix[1:2])[0][0]
    return float(np.clip(score, 0.0, 1.0))


def normalize_location(location: str | None) -> str:
    if location is None:
        return ""
    return " ".join(location.casefold().split())


def category_location_matches(
    new_complaint: NewComplaint,
    existing_complaint: ExistingComplaint,
) -> tuple[bool, bool]:
    """Return category and location agreement, safely handling missing values."""

    category_match = (
        new_complaint.category is not None
        and existing_complaint.category is not None
        and new_complaint.category.strip().casefold()
        == existing_complaint.category.strip().casefold()
    )
    new_location = normalize_location(new_complaint.location)
    existing_location = normalize_location(existing_complaint.location)
    location_match = bool(new_location and existing_location and new_location == existing_location)
    return category_match, location_match


def combine_ranking_score(
    text_similarity: float,
    *,
    category_match: bool,
    location_match: bool,
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG,
) -> float:
    """Add bounded metadata support without letting metadata stand alone."""

    score = text_similarity
    if category_match:
        score += support.category_support
    if location_match:
        score += support.location_support
    return float(np.clip(score, 0.0, 1.0))


def has_text_evidence(
    text_similarity: float,
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG,
) -> bool:
    return text_similarity >= support.min_text_evidence


def _reason_list(
    *,
    category_match: bool,
    location_match: bool,
    category: str | None,
    location: str | None,
) -> tuple[str, ...]:
    reasons = ["similar description text"]
    if category_match and category is not None:
        reasons.append(f"same category: {category}")
    if location_match and location is not None:
        reasons.append(f"same location: {location.strip()}")
    return tuple(reasons)


def rank_with_fitted_vectorizer(
    vectorizer: FeatureUnion,
    new_complaint: NewComplaint,
    existing_complaints: list[ExistingComplaint] | tuple[ExistingComplaint, ...],
    *,
    duplicate_threshold: float,
    uncertain_threshold: float,
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG,
    max_candidates: int = 5,
) -> DuplicateDetectionResult:
    """Rank existing complaints with a fitted vectorizer; never fit here."""

    validate_thresholds(duplicate_threshold, uncertain_threshold)
    if max_candidates < 1:
        raise ValueError("max_candidates must be at least 1")
    if not new_complaint.description.strip():
        raise ValueError("new complaint description must not be blank")

    if not existing_complaints:
        return DuplicateDetectionResult(
            decision="no_match",
            candidates=(),
            duplicate_threshold=duplicate_threshold,
            uncertain_threshold=uncertain_threshold,
            manual_review_recommended=False,
            existing_complaints_evaluated=0,
            message="No existing complaints were provided.",
        )

    seen_ids: set[str] = set()
    for complaint in existing_complaints:
        if not complaint.complaint_id.strip():
            raise ValueError("existing complaint_id must not be blank")
        if complaint.complaint_id in seen_ids:
            raise ValueError(f"duplicate complaint_id: {complaint.complaint_id}")
        seen_ids.add(complaint.complaint_id)
        if not complaint.description.strip():
            raise ValueError(
                f"description for complaint {complaint.complaint_id} must not be blank"
            )

    try:
        matrix = vectorizer.transform(
            [new_complaint.description, *(c.description for c in existing_complaints)]
        )
    except ValueError as exc:
        raise ValueError("the duplicate vectorizer is not usable for this text") from exc

    similarity_scores = cosine_similarity(matrix[0:1], matrix[1:]).ravel()

    candidates: list[DuplicateCandidate] = []
    for complaint, raw_score in zip(existing_complaints, similarity_scores, strict=True):
        text_score = float(np.clip(raw_score, 0.0, 1.0))
        if not has_text_evidence(text_score, support):
            continue

        category_match, location_match = category_location_matches(new_complaint, complaint)
        ranking_score = combine_ranking_score(
            text_score,
            category_match=category_match,
            location_match=location_match,
            support=support,
        )
        if ranking_score < uncertain_threshold:
            continue

        candidates.append(
            DuplicateCandidate(
                complaint_id=complaint.complaint_id,
                similarity_score=text_score,
                ranking_score=ranking_score,
                category=complaint.category,
                location=complaint.location,
                category_match=category_match,
                location_match=location_match,
                reasons=_reason_list(
                    category_match=category_match,
                    location_match=location_match,
                    category=complaint.category,
                    location=complaint.location,
                ),
            )
        )

    candidates.sort(
        key=lambda candidate: (
            -candidate.ranking_score,
            -candidate.similarity_score,
            candidate.complaint_id,
        )
    )
    top_candidates = tuple(candidates[:max_candidates])

    if not top_candidates:
        return DuplicateDetectionResult(
            decision="no_match",
            candidates=(),
            duplicate_threshold=duplicate_threshold,
            uncertain_threshold=uncertain_threshold,
            manual_review_recommended=False,
            existing_complaints_evaluated=len(existing_complaints),
            message=(
                "No candidate reached the uncertain ranking threshold with "
                "sufficient text similarity."
            ),
        )

    top_score = top_candidates[0].ranking_score
    if top_score >= duplicate_threshold:
        decision: Decision = "match"
        message = "Potential duplicates found; these are suggestions only and require human review."
    elif top_score >= uncertain_threshold:
        decision = "uncertain"
        message = "Candidate similarity is uncertain; manual review is recommended."
    else:  # pragma: no cover - defensive: candidates are filtered at uncertain
        decision = "no_match"
        message = "No candidate reached the uncertain ranking threshold."

    return DuplicateDetectionResult(
        decision=decision,
        candidates=top_candidates,
        duplicate_threshold=duplicate_threshold,
        uncertain_threshold=uncertain_threshold,
        manual_review_recommended=decision != "no_match",
        existing_complaints_evaluated=len(existing_complaints),
        message=message,
    )
