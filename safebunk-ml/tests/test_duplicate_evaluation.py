"""Unit tests for pair metrics and train-only threshold selection."""

from __future__ import annotations

from pathlib import Path

import pytest

from pulse_ml.duplicate_dataset import load_duplicate_complaints, load_duplicate_pairs
from pulse_ml.duplicate_evaluation import (
    calculate_pair_metrics,
    score_pairs,
    score_summary,
    select_threshold,
    uncertain_band_rates,
)
from pulse_ml.duplicates import (
    DEFAULT_DUPLICATE_THRESHOLD,
    DEFAULT_UNCERTAIN_THRESHOLD,
    build_tfidf_vectorizer,
)


def test_pair_metrics_confusion_matrix_and_rates() -> None:
    metrics = calculate_pair_metrics(
        [1, 1, 1, 0, 0, 0],
        [0.9, 0.4, 0.2, 0.8, 0.3, 0.1],
        0.5,
    )

    assert metrics.true_positive == 1
    assert metrics.false_positive == 1
    assert metrics.true_negative == 2
    assert metrics.false_negative == 2
    assert metrics.precision == pytest.approx(0.5)
    assert metrics.recall == pytest.approx(1 / 3)
    assert metrics.f1 == pytest.approx(0.4)
    assert metrics.false_positive_rate == pytest.approx(1 / 3)


def test_threshold_selection_prefers_f1_within_fpr_cap() -> None:
    selected = select_threshold(
        [1, 1, 0, 0],
        [0.9, 0.5, 0.45, 0.1],
        max_fpr=0.10,
        grid=(0.40, 0.50),
    )

    assert selected.threshold == 0.50
    assert selected.precision == 1.0
    assert selected.recall == 1.0
    assert selected.false_positive_rate == 0.0


def test_threshold_selection_falls_back_to_lowest_fpr() -> None:
    selected = select_threshold(
        [1, 0],
        [0.9, 0.8],
        max_fpr=0.0,
        grid=(0.5, 0.6),
    )

    assert selected.threshold == 0.5
    assert selected.false_positive_rate == pytest.approx(1.0)


def test_uncertain_band_rates_are_per_class() -> None:
    rates = uncertain_band_rates(
        [1, 1, 0, 0],
        [0.6, 0.2, 0.3, 0.05],
        uncertain_threshold=0.10,
        duplicate_threshold=0.50,
    )

    assert rates["positive_uncertain_rate"] == 0.5
    assert rates["negative_uncertain_rate"] == 0.5


def test_score_summary_handles_empty_and_non_empty_scores() -> None:
    assert score_summary([]) == {"count": 0}
    summary = score_summary([0.1, 0.2, 0.3])
    assert summary["count"] == 3
    assert summary["mean"] == 0.2
    assert summary["median"] == 0.2
    assert summary["min"] == 0.1
    assert summary["max"] == 0.3


def test_api_defaults_match_train_only_threshold_selection(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
) -> None:
    dataset = load_duplicate_complaints(duplicate_dataset_path)
    pairs = load_duplicate_pairs(duplicate_pairs_path, dataset)
    complaints_by_id = {complaint.complaint_id: complaint for complaint in dataset.complaints}
    train_complaints = [complaint for complaint in dataset.complaints if complaint.split == "train"]
    train_pairs = tuple(pair for pair in pairs if pair.split == "train")

    vectorizer = build_tfidf_vectorizer()
    vectorizer.fit([complaint.description for complaint in train_complaints])
    scores = score_pairs(vectorizer, train_pairs, complaints_by_id)
    selected = select_threshold(
        [pair.label for pair in train_pairs],
        scores,
        max_fpr=0.10,
    )

    assert selected.threshold == DEFAULT_DUPLICATE_THRESHOLD
    assert round(max(0.0, selected.threshold - 0.10), 2) == DEFAULT_UNCERTAIN_THRESHOLD
