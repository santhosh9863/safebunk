"""Frozen-test evaluation for the persisted Phase 2.1 duplicate detector.

The deployed-path candidate loads its train-fitted vectorizer. The Phase 2
request-corpus-fitted score is reported only as a diagnostic; it is not the
service inference path. This module verifies the frozen test fingerprint before
scoring anything.
"""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any

from pulse_ml.duplicate_dataset import (
    VALID_SPLITS,
    DuplicateDataset,
    DuplicatePair,
    load_duplicate_complaints,
    load_duplicate_pairs,
    verify_test_freeze,
)
from pulse_ml.duplicate_evaluation import (
    PairMetrics,
    calculate_pair_metrics,
    evidence_adjusted_scores,
    score_pairs,
    score_pairs_with_support,
    score_summary,
    uncertain_band_rates,
)
from pulse_ml.duplicate_model import DuplicateDetector
from pulse_ml.duplicates import (
    DEFAULT_DUPLICATE_THRESHOLD,
    build_tfidf_vectorizer,
)

MIN_GROUPS_PER_CATEGORY = 3


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _display_path(path: Path) -> str:
    project_root = Path(__file__).resolve().parents[2]
    try:
        return str(path.relative_to(project_root)).replace("\\", "/")
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
    metrics = calculate_pair_metrics(
        [pairs[index].label for index in indices],
        [scores[index] for index in indices],
        threshold,
    )
    return {
        "pairs": metrics.actual_negative,
        "false_positives": metrics.false_positive,
        "false_positive_rate": round(metrics.false_positive_rate, 4),
    }


def _load_json_object(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"could not read {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return raw


def _dataset_summary(dataset: DuplicateDataset, pairs: tuple[DuplicatePair, ...]) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for split in ("train", "validation", "test"):
        rows = dataset.split_complaints[split]
        split_pairs = [pair for pair in pairs if pair.split == split]
        summary[split] = {
            "complaints": len(rows),
            "groups": len({row.group_id for row in rows}),
            "categories": sorted({row.category for row in rows}),
            "pairs": len(split_pairs),
            "positive_pairs": sum(pair.label == 1 for pair in split_pairs),
            "negative_pairs": sum(pair.label == 0 for pair in split_pairs),
            "difficulty": dict(Counter(pair.difficulty for pair in split_pairs)),
        }
    return summary


def evaluate_frozen_duplicate_detector(
    *,
    model_dir: Path,
    dataset_path: Path,
    pairs_path: Path,
    freeze_path: Path,
    output_dir: Path,
) -> dict[str, Any]:
    """Score the frozen test split once and write machine-readable reports."""

    dataset = load_duplicate_complaints(
        dataset_path,
        required_splits=VALID_SPLITS,
        min_groups_per_category=MIN_GROUPS_PER_CATEGORY,
    )
    pairs = load_duplicate_pairs(pairs_path, dataset)
    freeze = _load_json_object(freeze_path)
    verify_test_freeze(dataset, pairs, freeze)

    detector = DuplicateDetector.from_directory(model_dir)
    metadata_dataset = detector.metadata.get("dataset")
    if not isinstance(metadata_dataset, dict):
        raise ValueError("artifact metadata is missing dataset information")
    if metadata_dataset.get("sha256") != dataset.sha256:
        raise ValueError("artifact dataset SHA-256 does not match the evaluation dataset")
    artifact_split = detector.metadata.get("split")
    if not isinstance(artifact_split, dict):
        raise ValueError("artifact metadata is missing split information")
    if artifact_split.get("test_groups") != freeze["group_ids"]:
        raise ValueError("artifact test groups do not match the frozen test groups")
    artifact_freeze = artifact_split.get("frozen_test")
    if not isinstance(artifact_freeze, dict):
        raise ValueError("artifact metadata is missing the frozen test record")
    for key in ("complaints_sha256", "pairs_sha256"):
        if artifact_freeze.get(key) != freeze[key]:
            raise ValueError(f"artifact frozen test {key} does not match the freeze file")
    training_metadata = detector.metadata.get("training")
    if (
        not isinstance(training_metadata, dict)
        or training_metadata.get("vectorizer_fit") != "train split only"
    ):
        raise ValueError("artifact does not record a train-only vectorizer fit")

    complaints_by_id = {complaint.complaint_id: complaint for complaint in dataset.complaints}
    test_pairs = tuple(pair for pair in pairs if pair.split == "test")
    if not test_pairs:
        raise ValueError("frozen test split has no pairs")

    test_details = score_pairs_with_support(
        detector.vectorizer,
        test_pairs,
        complaints_by_id,
        support=detector.support_config,
    )
    candidate_scores = evidence_adjusted_scores(
        test_details,
        support=detector.support_config,
    )
    test_labels = [pair.label for pair in test_pairs]
    candidate_metrics = calculate_pair_metrics(
        test_labels,
        candidate_scores,
        detector.duplicate_threshold,
    )

    text_only_metrics = calculate_pair_metrics(
        test_labels,
        [detail.text_similarity for detail in test_details],
        detector.duplicate_threshold,
    )

    # Diagnostic only: the Phase 2 endpoint fitted a vectorizer on the request's
    # supplied complaint collection. It is not the deployed Phase 2.1 path.
    baseline_vectorizer = build_tfidf_vectorizer()
    test_complaints = dataset.split_complaints["test"]
    baseline_vectorizer.fit([complaint.description for complaint in test_complaints])
    baseline_scores = score_pairs(baseline_vectorizer, test_pairs, complaints_by_id)
    baseline_metrics = calculate_pair_metrics(
        test_labels,
        baseline_scores,
        DEFAULT_DUPLICATE_THRESHOLD,
    )

    positive_text = [
        detail.text_similarity
        for detail, pair in zip(test_details, test_pairs, strict=True)
        if pair.label == 1
    ]
    negative_text = [
        detail.text_similarity
        for detail, pair in zip(test_details, test_pairs, strict=True)
        if pair.label == 0
    ]
    positive_ranking = [
        score for score, pair in zip(candidate_scores, test_pairs, strict=True) if pair.label == 1
    ]
    negative_ranking = [
        score for score, pair in zip(candidate_scores, test_pairs, strict=True) if pair.label == 0
    ]

    training_report_path = model_dir / "training_report.json"
    training_report: dict[str, Any] | None = None
    if training_report_path.is_file():
        training_report = _load_json_object(training_report_path)

    report: dict[str, Any] = {
        "artifact_version": detector.artifact_version,
        "model_version": detector.model_version,
        "dataset_version": "duplicate-detection-v0.2.0",
        "synthetic": True,
        "production_ready": False,
        "test_scored_once": True,
        "artifacts": {
            "model_dir": _display_path(model_dir),
            "dataset": {
                "path": _display_path(dataset_path),
                "sha256": dataset.sha256,
            },
            "pairs": {
                "path": _display_path(pairs_path),
                "sha256": _sha256(pairs_path),
            },
            "freeze": {
                "path": _display_path(freeze_path),
                "complaints_sha256": freeze["complaints_sha256"],
                "pairs_sha256": freeze["pairs_sha256"],
            },
        },
        "protocol": {
            "split": (
                "Issue groups are assigned wholly to train, validation, or test. "
                "The test fingerprint was created before feature/threshold selection."
            ),
            "feature_selection": (
                "Selected on the validation split only. The final vectorizer is fitted "
                "on the train split only."
            ),
            "threshold_selection": (
                "Selected on the validation split only by maximum F1 subject to "
                "false-positive rate <= 0.10."
            ),
            "candidate_inference": (
                "Load the persisted train-fitted vectorizer and transform the new and "
                "existing complaints. No request-time fitting."
            ),
            "score_semantics": (
                "Text cosine similarity plus a small category/location support boost. "
                "Not a calibrated probability."
            ),
            "baseline_diagnostic": (
                "The Phase 2 test-corpus-fitted protocol is reported only for comparison. "
                "It is not used by the service."
            ),
        },
        "selected_configuration": {
            "feature_config": detector.feature_config.to_dict(),
            "support_signals": detector.support_config.to_dict(),
            "duplicate_threshold": detector.duplicate_threshold,
            "uncertain_threshold": detector.uncertain_threshold,
        },
        "dataset": _dataset_summary(dataset, pairs),
        "candidate_frozen_test": {
            "evaluation_mode": "persisted_train_fitted_vectorizer",
            **_metrics_payload(candidate_metrics),
            "uncertain_band": uncertain_band_rates(
                test_labels,
                candidate_scores,
                uncertain_threshold=detector.uncertain_threshold,
                duplicate_threshold=detector.duplicate_threshold,
            ),
            "hard_negatives": _hard_negative_payload(
                test_pairs,
                candidate_scores,
                detector.duplicate_threshold,
            ),
            "score_distributions": {
                "positive_text_similarity": score_summary(positive_text),
                "negative_text_similarity": score_summary(negative_text),
                "positive_ranking": score_summary(positive_ranking),
                "negative_ranking": score_summary(negative_ranking),
            },
        },
        "candidate_text_only_ablation": {
            "evaluation_mode": "persisted_train_fitted_vectorizer_without_metadata_support",
            **_metrics_payload(text_only_metrics),
            "hard_negatives": _hard_negative_payload(
                test_pairs,
                [detail.text_similarity for detail in test_details],
                detector.duplicate_threshold,
            ),
        },
        "baseline_test_corpus_fitted_diagnostic": {
            "evaluation_mode": "phase2_test_corpus_fitted_not_deployed",
            **_metrics_payload(baseline_metrics),
            "hard_negatives": _hard_negative_payload(
                test_pairs,
                baseline_scores,
                DEFAULT_DUPLICATE_THRESHOLD,
            ),
            "note": (
                "This diagnostic fits TF-IDF on test complaint text without labels to "
                "mirror the old request-local Phase 2 API. It is not a strict "
                "unseen-vocabulary estimate and is not the deployed inference path."
            ),
        },
        "baseline_vs_candidate": {
            "baseline": {
                "protocol": "Phase 2 test-corpus-fitted diagnostic",
                "threshold": DEFAULT_DUPLICATE_THRESHOLD,
                "precision": baseline_metrics.precision,
                "recall": baseline_metrics.recall,
                "f1": baseline_metrics.f1,
                "false_positive_rate": baseline_metrics.false_positive_rate,
            },
            "candidate": {
                "protocol": "Phase 2.1 frozen-test persisted train-fitted artifact",
                "threshold": detector.duplicate_threshold,
                "precision": candidate_metrics.precision,
                "recall": candidate_metrics.recall,
                "f1": candidate_metrics.f1,
                "false_positive_rate": candidate_metrics.false_positive_rate,
            },
            "delta": {
                "precision": round(candidate_metrics.precision - baseline_metrics.precision, 4),
                "recall": round(candidate_metrics.recall - baseline_metrics.recall, 4),
                "f1": round(candidate_metrics.f1 - baseline_metrics.f1, 4),
                "false_positive_rate": round(
                    candidate_metrics.false_positive_rate - baseline_metrics.false_positive_rate,
                    4,
                ),
            },
            "note": (
                "The baseline diagnostic uses test text to fit its vocabulary, so it is "
                "not an apples-to-apples unseen-corpus comparison. The candidate is the "
                "only deployable path."
            ),
        },
        "training_report": training_report,
        "limitations": [
            "All 216 complaints and pair labels are synthetic and not human-verified.",
            "The detector is lexical TF-IDF and can miss semantic paraphrases.",
            "Scores are similarities/ranking scores, not calibrated probabilities.",
            "Feature and threshold selection used a small validation split.",
            "The test split is frozen, but repeated future evaluations could still overfit "
            "the benchmark through unrelated changes.",
            "The Phase 2 test-corpus-fitted diagnostic is not the deployed path.",
            "No production-readiness claim is supported by these results.",
            "No complaint is merged, rejected, or modified.",
            "The service is not integrated with NestJS or Flutter.",
        ],
    }

    comparison = {
        "baseline": report["baseline_vs_candidate"]["baseline"],
        "candidate": report["baseline_vs_candidate"]["candidate"],
        "delta": report["baseline_vs_candidate"]["delta"],
        "note": report["baseline_vs_candidate"]["note"],
        "test_frozen": True,
        "frozen_test_pairs_sha256": freeze["pairs_sha256"],
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    evaluation_path = output_dir / "evaluation.json"
    comparison_path = output_dir / "comparison.json"
    evaluation_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    comparison_path.write_text(
        json.dumps(comparison, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report
