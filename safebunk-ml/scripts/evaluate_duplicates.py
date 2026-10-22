"""Evaluate duplicate suggestions on grouped train/test complaint pairs.

Thresholds are selected on train pairs only. Primary test scoring fits TF-IDF on
the test complaint corpus to mirror the request-local API; a train-only vocabulary
stress test is also reported. The test split is never used to select the threshold.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from pulse_ml.duplicate_dataset import (
    DuplicateDatasetError,
    DuplicatePair,
    load_duplicate_complaints,
    load_duplicate_pairs,
)
from pulse_ml.duplicate_evaluation import (
    AUDIT_THRESHOLD_GRID,
    DEFAULT_THRESHOLD_GRID,
    PairMetrics,
    calculate_pair_metrics,
    score_pairs,
    score_summary,
    select_threshold,
    uncertain_band_rates,
)
from pulse_ml.duplicates import build_tfidf_vectorizer

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMPLAINTS = PROJECT_ROOT / "data" / "duplicate_detection_complaints.csv"
DEFAULT_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_pairs.csv"
DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "duplicate-detector" / "v0.1.0" / "evaluation.json"
MAX_FPR = 0.10
UNCERTAIN_BAND_WIDTH = 0.10


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def _metrics_payload(metrics: PairMetrics) -> dict[str, Any]:
    payload: dict[str, Any] = metrics.to_dict()
    payload["confusion_matrix"] = {
        "true_negative": metrics.true_negative,
        "false_positive": metrics.false_positive,
        "false_negative": metrics.false_negative,
        "true_positive": metrics.true_positive,
    }
    return payload


def _hard_negative_payload(
    pairs: tuple[DuplicatePair, ...],
    scores: list[float],
    threshold: float,
) -> dict[str, float | int]:
    indices = [index for index, pair in enumerate(pairs) if pair.difficulty == "hard_negative"]
    labels = [pairs[index].label for index in indices]
    hard_scores = [scores[index] for index in indices]
    metrics = calculate_pair_metrics(labels, hard_scores, threshold)
    return {
        "pairs": metrics.actual_negative,
        "false_positives": metrics.false_positive,
        "false_positive_rate": round(metrics.false_positive_rate, 4),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complaints", type=Path, default=DEFAULT_COMPLAINTS)
    parser.add_argument("--pairs", type=Path, default=DEFAULT_PAIRS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    try:
        dataset = load_duplicate_complaints(args.complaints)
        pairs = load_duplicate_pairs(args.pairs, dataset)
    except (DuplicateDatasetError, OSError) as exc:
        print(f"Evaluation failed: {exc}", file=sys.stderr)
        return 1

    complaints_by_id = {complaint.complaint_id: complaint for complaint in dataset.complaints}
    train_complaints = [complaint for complaint in dataset.complaints if complaint.split == "train"]
    test_complaints = [complaint for complaint in dataset.complaints if complaint.split == "test"]
    train_pairs = tuple(pair for pair in pairs if pair.split == "train")
    test_pairs = tuple(pair for pair in pairs if pair.split == "test")

    if not train_pairs or not test_pairs:
        print("Evaluation failed: train and test pairs are both required.", file=sys.stderr)
        return 1

    # Threshold selection uses only the train split.
    train_vectorizer = build_tfidf_vectorizer()
    train_vectorizer.fit([complaint.description for complaint in train_complaints])
    train_scores = score_pairs(train_vectorizer, train_pairs, complaints_by_id)
    train_labels = [pair.label for pair in train_pairs]
    selected = select_threshold(train_labels, train_scores, max_fpr=MAX_FPR)
    uncertain_threshold = round(max(0.0, selected.threshold - UNCERTAIN_BAND_WIDTH), 2)
    if uncertain_threshold >= selected.threshold:
        uncertain_threshold = 0.0

    # Primary test scoring mirrors the request-local API: fit TF-IDF on the
    # complaint corpus being compared. No labels are used in this fit.
    test_vectorizer = build_tfidf_vectorizer()
    test_vectorizer.fit([complaint.description for complaint in test_complaints])
    test_scores = score_pairs(test_vectorizer, test_pairs, complaints_by_id)
    test_labels = [pair.label for pair in test_pairs]
    test_metrics = calculate_pair_metrics(test_labels, test_scores, selected.threshold)

    # Stress test: reuse the train-only vocabulary and transform unseen test text.
    stress_scores = score_pairs(train_vectorizer, test_pairs, complaints_by_id)
    stress_metrics = calculate_pair_metrics(test_labels, stress_scores, selected.threshold)

    audit_thresholds = sorted({*AUDIT_THRESHOLD_GRID, selected.threshold})
    audit_metrics = [
        _metrics_payload(calculate_pair_metrics(test_labels, test_scores, threshold))
        for threshold in audit_thresholds
    ]

    train_positive_scores = [
        score for pair, score in zip(train_pairs, train_scores, strict=True) if pair.label == 1
    ]
    train_negative_scores = [
        score for pair, score in zip(train_pairs, train_scores, strict=True) if pair.label == 0
    ]
    test_positive_scores = [
        score for pair, score in zip(test_pairs, test_scores, strict=True) if pair.label == 1
    ]
    test_negative_scores = [
        score for pair, score in zip(test_pairs, test_scores, strict=True) if pair.label == 0
    ]

    report: dict[str, Any] = {
        "dataset_version": "duplicate-detection-v0.1.0",
        "synthetic": True,
        "production_ready": False,
        "artifacts": {
            "complaints": {
                "path": _display_path(args.complaints),
                "sha256": dataset.sha256,
            },
            "pairs": {
                "path": _display_path(args.pairs),
                "sha256": _sha256(args.pairs),
            },
        },
        "protocol": {
            "similarity": (
                "TF-IDF word 1-2 grams + character 3-5 grams, combined with "
                "FeatureUnion, then cosine similarity."
            ),
            "score_semantics": "Similarity score, not a probability.",
            "split": (
                "Issue groups are assigned wholly to train or test. Every variant of a "
                "group appears in exactly one split."
            ),
            "vectorizer_fit": (
                "Threshold selection fits TF-IDF on train complaints only. Primary test "
                "scoring fits a separate vectorizer on the test complaint corpus to mirror "
                "the request-local API; no labels are used. The train-only vocabulary is "
                "also applied to test text as an unseen-vocabulary stress test."
            ),
            "threshold_selection": (
                "Train split only: maximize F1 subject to false-positive rate <= "
                f"{MAX_FPR:.2f} over the fixed grid {list(DEFAULT_THRESHOLD_GRID)}."
            ),
            "uncertain_band": (
                f"Uncertain threshold = duplicate threshold - {UNCERTAIN_BAND_WIDTH:.2f}; "
                "it is an operating band, not a calibrated probability."
            ),
            "test_usage": (
                "The test split is not used to select the threshold. Test complaint text is "
                "used unsupervised in the primary corpus-fitted vectorizer; the group split "
                "prevents issue variants from crossing train and test. The audit grid is "
                "reported for sensitivity only."
            ),
            "pair_unit": "One unordered pair of complaint descriptions.",
        },
        "dataset": {
            "complaints": len(dataset.complaints),
            "groups": len(dataset.groups),
            "categories": sorted({row.category for row in dataset.complaints}),
            "splits": {
                split: {
                    "complaints": len(dataset.split_complaints[split]),
                    "groups": len({row.group_id for row in dataset.split_complaints[split]}),
                    "pairs": len(train_pairs) if split == "train" else len(test_pairs),
                    "positive_pairs": sum(
                        pair.label == 1
                        for pair in (train_pairs if split == "train" else test_pairs)
                    ),
                    "negative_pairs": sum(
                        pair.label == 0
                        for pair in (train_pairs if split == "train" else test_pairs)
                    ),
                }
                for split in ("train", "test")
            },
        },
        "threshold_selection": {
            "split": "train",
            "max_false_positive_rate": MAX_FPR,
            "grid": list(DEFAULT_THRESHOLD_GRID),
            "selected": _metrics_payload(selected),
            "uncertain_threshold": uncertain_threshold,
        },
        "test_results_at_selected_threshold": {
            "evaluation_mode": "test_corpus_fitted",
            **_metrics_payload(test_metrics),
            "uncertain_threshold": uncertain_threshold,
            "uncertain_band": uncertain_band_rates(
                test_labels,
                test_scores,
                uncertain_threshold=uncertain_threshold,
                duplicate_threshold=selected.threshold,
            ),
            "hard_negatives": _hard_negative_payload(test_pairs, test_scores, selected.threshold),
        },
        "test_stress_unseen_vocabulary": {
            "evaluation_mode": "train_vocabulary_only",
            **_metrics_payload(stress_metrics),
            "hard_negatives": _hard_negative_payload(test_pairs, stress_scores, selected.threshold),
            "note": (
                "This deliberately reuses the train vocabulary on unseen test text. It is "
                "a vocabulary-shift stress test, not the request-local operating mode."
            ),
        },
        "test_sensitivity_audit": audit_metrics,
        "score_distributions": {
            "train_positive": score_summary(train_positive_scores),
            "train_negative": score_summary(train_negative_scores),
            "test_positive": score_summary(test_positive_scores),
            "test_negative": score_summary(test_negative_scores),
        },
        "difficulty_counts": {
            split: dict(
                Counter(
                    pair.difficulty for pair in (train_pairs if split == "train" else test_pairs)
                )
            )
            for split in ("train", "test")
        },
        "limitations": [
            "All 96 complaints and their pair labels are synthetic.",
            "The test set has 48 positive and 1,080 negative pairs from 16 issue groups.",
            "The primary test vectorizer sees test complaint text without labels. It is not "
            "a strict unseen-corpus estimate; the train-vocabulary stress test is reported "
            "separately.",
            "The detector is a lexical TF-IDF baseline and does not understand synonyms "
            "or context beyond character and word overlap.",
            "The API fits TF-IDF on each request's supplied complaint corpus, so live scores "
            "may differ from both offline protocols.",
            "Similarity scores are not probabilities and are not calibrated.",
            "No production-readiness claim is supported by these synthetic results.",
        ],
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(
        "Train-selected duplicate threshold: "
        f"{selected.threshold:.2f} (uncertain {uncertain_threshold:.2f})"
    )
    print(
        "Train metrics at selected threshold: "
        f"precision={selected.precision:.4f} recall={selected.recall:.4f} "
        f"f1={selected.f1:.4f} fpr={selected.false_positive_rate:.4f}"
    )
    print(
        "Test metrics at selected threshold (test-corpus-fitted): "
        f"precision={test_metrics.precision:.4f} recall={test_metrics.recall:.4f} "
        f"f1={test_metrics.f1:.4f} fpr={test_metrics.false_positive_rate:.4f}"
    )
    print(
        "Test stress metrics (train vocabulary only): "
        f"precision={stress_metrics.precision:.4f} recall={stress_metrics.recall:.4f} "
        f"f1={stress_metrics.f1:.4f} fpr={stress_metrics.false_positive_rate:.4f}"
    )
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
