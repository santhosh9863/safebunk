"""Pair-level evaluation helpers for the duplicate-similarity baseline."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from statistics import mean, median
from typing import Final

from sklearn.pipeline import FeatureUnion

from pulse_ml.duplicate_dataset import DuplicateComplaint, DuplicatePair
from pulse_ml.duplicates import (
    DEFAULT_SUPPORT_CONFIG,
    DuplicateSupportConfig,
    ExistingComplaint,
    NewComplaint,
    category_location_matches,
    combine_ranking_score,
    has_text_evidence,
    score_text_similarity,
)

DEFAULT_THRESHOLD_GRID: Final[tuple[float, ...]] = tuple(
    round(0.20 + index * 0.05, 2) for index in range(13)
)
AUDIT_THRESHOLD_GRID: Final[tuple[float, ...]] = (0.25, 0.35, 0.45, 0.55, 0.65, 0.75)


@dataclass(frozen=True)
class PairMetrics:
    threshold: float
    true_positive: int
    false_positive: int
    true_negative: int
    false_negative: int

    @property
    def actual_positive(self) -> int:
        return self.true_positive + self.false_negative

    @property
    def actual_negative(self) -> int:
        return self.false_positive + self.true_negative

    @property
    def predicted_positive(self) -> int:
        return self.true_positive + self.false_positive

    @property
    def precision(self) -> float:
        if self.predicted_positive == 0:
            return 0.0
        return self.true_positive / self.predicted_positive

    @property
    def recall(self) -> float:
        if self.actual_positive == 0:
            return 0.0
        return self.true_positive / self.actual_positive

    @property
    def f1(self) -> float:
        if self.precision + self.recall == 0:
            return 0.0
        return 2 * self.precision * self.recall / (self.precision + self.recall)

    @property
    def false_positive_rate(self) -> float:
        if self.actual_negative == 0:
            return 0.0
        return self.false_positive / self.actual_negative

    def to_dict(self) -> dict[str, float | int]:
        return {
            "threshold": self.threshold,
            "precision": round(self.precision, 4),
            "recall": round(self.recall, 4),
            "f1": round(self.f1, 4),
            "false_positive_rate": round(self.false_positive_rate, 4),
            "true_positive": self.true_positive,
            "false_positive": self.false_positive,
            "true_negative": self.true_negative,
            "false_negative": self.false_negative,
            "actual_positive": self.actual_positive,
            "actual_negative": self.actual_negative,
            "predicted_positive": self.predicted_positive,
        }


def calculate_pair_metrics(
    labels: Sequence[int], scores: Sequence[float], threshold: float
) -> PairMetrics:
    """Build a confusion matrix at one cosine-similarity threshold."""

    if len(labels) != len(scores):
        raise ValueError("labels and scores must have the same length")
    if not 0.0 <= threshold <= 1.0:
        raise ValueError("threshold must be between 0 and 1")
    if any(label not in {0, 1} for label in labels):
        raise ValueError("labels must contain only 0 and 1")

    true_positive = false_positive = true_negative = false_negative = 0
    for label, score in zip(labels, scores, strict=True):
        predicted = score >= threshold
        if label == 1 and predicted:
            true_positive += 1
        elif label == 1:
            false_negative += 1
        elif predicted:
            false_positive += 1
        else:
            true_negative += 1

    return PairMetrics(
        threshold=threshold,
        true_positive=true_positive,
        false_positive=false_positive,
        true_negative=true_negative,
        false_negative=false_negative,
    )


def score_pairs(
    vectorizer: FeatureUnion,
    pairs: Sequence[DuplicatePair],
    complaints_by_id: Mapping[str, DuplicateComplaint],
) -> list[float]:
    """Score each unordered pair with the fitted vectorizer."""

    scores: list[float] = []
    for pair in pairs:
        left = complaints_by_id[pair.left_complaint_id]
        right = complaints_by_id[pair.right_complaint_id]
        scores.append(score_text_similarity(vectorizer, left.description, right.description))
    return scores


@dataclass(frozen=True)
class PairScore:
    text_similarity: float
    ranking_score: float
    category_match: bool
    location_match: bool


def score_pairs_with_support(
    vectorizer: FeatureUnion,
    pairs: Sequence[DuplicatePair],
    complaints_by_id: Mapping[str, DuplicateComplaint],
    *,
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG,
) -> list[PairScore]:
    """Score pairs with text similarity plus supporting metadata agreement."""

    details: list[PairScore] = []
    for pair in pairs:
        left = complaints_by_id[pair.left_complaint_id]
        right = complaints_by_id[pair.right_complaint_id]
        text_similarity = score_text_similarity(
            vectorizer,
            left.description,
            right.description,
        )
        category_match, location_match = category_location_matches(
            NewComplaint(left.description, left.category, left.location),
            ExistingComplaint(
                right.complaint_id,
                right.description,
                right.category,
                right.location,
            ),
        )
        ranking_score = combine_ranking_score(
            text_similarity,
            category_match=category_match,
            location_match=location_match,
            support=support,
        )
        details.append(
            PairScore(
                text_similarity=text_similarity,
                ranking_score=ranking_score,
                category_match=category_match,
                location_match=location_match,
            )
        )
    return details


def evidence_adjusted_scores(
    details: Sequence[PairScore],
    *,
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG,
) -> list[float]:
    """Return ranking scores, with textless metadata-only pairs forced below zero."""

    return [
        detail.ranking_score if has_text_evidence(detail.text_similarity, support) else -1.0
        for detail in details
    ]


def select_threshold(
    labels: Sequence[int],
    scores: Sequence[float],
    *,
    max_fpr: float = 0.10,
    grid: Sequence[float] = DEFAULT_THRESHOLD_GRID,
) -> PairMetrics:
    """Select a train-split threshold by F1 subject to a false-positive-rate cap.

    The test split is never used here. If no grid point satisfies the cap, the
    lowest-FPR point is selected so the outcome remains deterministic.
    """

    if not grid:
        raise ValueError("threshold grid must not be empty")
    candidates = [calculate_pair_metrics(labels, scores, threshold) for threshold in grid]
    within_cap = [metrics for metrics in candidates if metrics.false_positive_rate <= max_fpr]
    if within_cap:
        return max(within_cap, key=lambda metrics: (metrics.f1, metrics.threshold))
    return min(candidates, key=lambda metrics: (metrics.false_positive_rate, -metrics.f1))


def score_summary(scores: Sequence[float]) -> dict[str, float | int]:
    if not scores:
        return {"count": 0}
    return {
        "count": len(scores),
        "mean": round(mean(scores), 4),
        "median": round(median(scores), 4),
        "min": round(min(scores), 4),
        "max": round(max(scores), 4),
    }


def uncertain_band_rates(
    labels: Sequence[int],
    scores: Sequence[float],
    *,
    uncertain_threshold: float,
    duplicate_threshold: float,
) -> dict[str, float]:
    """Fraction of each class that falls in the uncertain band."""

    if uncertain_threshold >= duplicate_threshold:
        raise ValueError("uncertain threshold must be lower than duplicate threshold")

    positives = [score for label, score in zip(labels, scores, strict=True) if label == 1]
    negatives = [score for label, score in zip(labels, scores, strict=True) if label == 0]

    def _rate(values: Sequence[float]) -> float:
        if not values:
            return 0.0
        in_band = sum(uncertain_threshold <= score < duplicate_threshold for score in values)
        return in_band / len(values)

    return {
        "positive_uncertain_rate": round(_rate(positives), 4),
        "negative_uncertain_rate": round(_rate(negatives), 4),
    }
