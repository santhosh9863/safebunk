"""Train and version the persisted Phase 2.1 duplicate detector.

Only the train split is used to fit the vectorizer. Feature configuration and
thresholds are selected on the validation split. The test split is verified
against its frozen fingerprint but is never scored in this module.
"""

from __future__ import annotations

import hashlib
import json
import platform
from dataclasses import dataclass
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Any

import joblib

from pulse_ml.dataset import dataset_display_path
from pulse_ml.duplicate_dataset import (
    VALID_SPLITS,
    DuplicateDataset,
    DuplicateDatasetError,
    DuplicatePair,
    load_duplicate_complaints,
    load_duplicate_pairs,
    verify_test_freeze,
)
from pulse_ml.duplicate_evaluation import (
    PairMetrics,
    PairScore,
    calculate_pair_metrics,
    evidence_adjusted_scores,
    score_pairs_with_support,
    select_threshold,
)
from pulse_ml.duplicates import (
    DEFAULT_SUPPORT_CONFIG,
    FEATURE_CONFIGS,
    DuplicateFeatureConfig,
    DuplicateSupportConfig,
    build_duplicate_vectorizer,
)

DEFAULT_MODEL_VERSION = "0.2.0"
DEFAULT_MAX_FPR = 0.10
DEFAULT_UNCERTAIN_BAND = 0.10
THRESHOLD_GRID: tuple[float, ...] = tuple(round(0.05 + index * 0.05, 2) for index in range(16))
MIN_GROUPS_PER_CATEGORY = 3


@dataclass(frozen=True)
class DuplicateTrainingConfig:
    dataset_path: Path
    pairs_path: Path
    freeze_path: Path
    output_dir: Path
    model_version: str = DEFAULT_MODEL_VERSION
    max_fpr: float = DEFAULT_MAX_FPR
    uncertain_band: float = DEFAULT_UNCERTAIN_BAND
    support: DuplicateSupportConfig = DEFAULT_SUPPORT_CONFIG
    dataset_version: str = "duplicate-detection-v0.2.0"


@dataclass(frozen=True)
class DuplicateTrainingResult:
    model_dir: Path
    model_path: Path
    metadata_path: Path
    training_report_path: Path
    model_version: str
    dataset: DuplicateDataset
    pairs: tuple[DuplicatePair, ...]
    metadata: dict[str, Any]
    report: dict[str, Any]


@dataclass(frozen=True)
class _Candidate:
    feature_config: DuplicateFeatureConfig
    metrics: PairMetrics
    uncertain_threshold: float


def _package_version(name: str) -> str:
    try:
        return version(name)
    except PackageNotFoundError:
        return "unknown"


def _load_json_object(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"could not read {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return raw


def _uncertain_threshold(duplicate_threshold: float, band: float) -> float:
    uncertain = round(max(0.0, duplicate_threshold - band), 2)
    if uncertain >= duplicate_threshold:
        return 0.0
    return uncertain


def _hard_negative_metrics(
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


def _metrics_payload(metrics: PairMetrics) -> dict[str, Any]:
    payload: dict[str, Any] = metrics.to_dict()
    payload["confusion_matrix"] = {
        "true_negative": metrics.true_negative,
        "false_positive": metrics.false_positive,
        "false_negative": metrics.false_negative,
        "true_positive": metrics.true_positive,
    }
    return payload


def _select_candidate(
    vectorizer: Any,
    validation_pairs: tuple[DuplicatePair, ...],
    complaints_by_id: dict[str, Any],
    config: DuplicateFeatureConfig,
    *,
    max_fpr: float,
    uncertain_band: float,
    support: DuplicateSupportConfig,
) -> tuple[_Candidate, list[PairScore], list[float]]:
    details = score_pairs_with_support(
        vectorizer,
        validation_pairs,
        complaints_by_id,
        support=support,
    )
    scores = evidence_adjusted_scores(details, support=support)
    metrics = select_threshold(
        [pair.label for pair in validation_pairs],
        scores,
        max_fpr=max_fpr,
        grid=THRESHOLD_GRID,
    )
    return (
        _Candidate(
            feature_config=config,
            metrics=metrics,
            uncertain_threshold=_uncertain_threshold(metrics.threshold, uncertain_band),
        ),
        details,
        scores,
    )


def train_duplicate_detector(config: DuplicateTrainingConfig) -> DuplicateTrainingResult:
    """Fit, select, and persist one versioned duplicate-detector artifact."""

    if not config.model_version.strip():
        raise ValueError("model_version must not be blank")
    if not 0.0 <= config.max_fpr <= 1.0:
        raise ValueError("max_fpr must be between 0 and 1")
    if not 0.0 < config.uncertain_band < 1.0:
        raise ValueError("uncertain_band must be between 0 and 1")

    dataset = load_duplicate_complaints(
        config.dataset_path,
        required_splits=VALID_SPLITS,
        min_groups_per_category=MIN_GROUPS_PER_CATEGORY,
    )
    pairs = load_duplicate_pairs(config.pairs_path, dataset)
    freeze = _load_json_object(config.freeze_path)
    verify_test_freeze(dataset, pairs, freeze)

    complaints_by_id = {complaint.complaint_id: complaint for complaint in dataset.complaints}
    train_complaints = dataset.split_complaints["train"]
    validation_complaints = dataset.split_complaints["validation"]
    train_pairs = tuple(pair for pair in pairs if pair.split == "train")
    validation_pairs = tuple(pair for pair in pairs if pair.split == "validation")
    if not train_pairs or not validation_pairs:
        raise DuplicateDatasetError(["train and validation pairs are required"])

    train_texts = [complaint.description for complaint in train_complaints]

    candidate_results: list[
        tuple[_Candidate, DuplicateFeatureConfig, list[PairScore], list[float]]
    ] = []
    for feature_config in FEATURE_CONFIGS:
        vectorizer = build_duplicate_vectorizer(feature_config)
        vectorizer.fit(train_texts)
        candidate, details, scores = _select_candidate(
            vectorizer,
            validation_pairs,
            complaints_by_id,
            feature_config,
            max_fpr=config.max_fpr,
            uncertain_band=config.uncertain_band,
            support=config.support,
        )
        candidate_results.append((candidate, feature_config, details, scores))

    selected, selected_config, _selected_validation_details, selected_validation_scores = max(
        candidate_results,
        key=lambda item: (
            item[0].metrics.f1,
            -item[0].metrics.false_positive_rate,
            item[0].metrics.threshold,
            item[1].name,
        ),
    )

    # The final artifact is fitted on the train split only. Validation is used
    # for model selection, not for fitting the deployed vectorizer.
    final_vectorizer = build_duplicate_vectorizer(selected_config)
    final_vectorizer.fit(train_texts)

    train_details = score_pairs_with_support(
        final_vectorizer,
        train_pairs,
        complaints_by_id,
        support=config.support,
    )
    train_scores = evidence_adjusted_scores(train_details, support=config.support)
    train_metrics = calculate_pair_metrics(
        [pair.label for pair in train_pairs],
        train_scores,
        selected.metrics.threshold,
    )
    validation_metrics = calculate_pair_metrics(
        [pair.label for pair in validation_pairs],
        selected_validation_scores,
        selected.metrics.threshold,
    )

    artifact_version = f"duplicate-detector-v{config.model_version}"
    output_dir = config.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / "model.joblib"
    metadata_path = output_dir / "metadata.json"
    training_report_path = output_dir / "training_report.json"

    bundle = {
        "schema_version": 1,
        "artifact_version": artifact_version,
        "model_version": config.model_version,
        "vectorizer": final_vectorizer,
        "feature_config": selected_config.to_dict(),
        "support_signals": config.support.to_dict(),
        "duplicate_threshold": selected.metrics.threshold,
        "uncertain_threshold": selected.uncertain_threshold,
    }
    temporary_model_path = output_dir / "model.joblib.tmp"
    joblib.dump(bundle, temporary_model_path)
    temporary_model_path.replace(model_path)

    created_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    freeze_record = {
        "path": dataset_display_path(config.freeze_path),
        "group_ids": freeze["group_ids"],
        "complaints_sha256": freeze["complaints_sha256"],
        "pairs_sha256": freeze["pairs_sha256"],
        "frozen_before_tuning": True,
    }
    metadata: dict[str, Any] = {
        "schema_version": 1,
        "artifact_version": artifact_version,
        "model_version": config.model_version,
        "created_at": created_at,
        "task": "duplicate_complaint_suggestion",
        "algorithm": "tfidf_word_char_feature_union_cosine",
        "feature_config": selected_config.to_dict(),
        "support_signals": config.support.to_dict(),
        "duplicate_threshold": selected.metrics.threshold,
        "uncertain_threshold": selected.uncertain_threshold,
        "score_note": (
            "Cosine similarity plus a small category/location support boost. "
            "This is a ranking score, not a calibrated probability."
        ),
        "environment": {
            "python": platform.python_version(),
            "scikit_learn": _package_version("scikit-learn"),
            "numpy": _package_version("numpy"),
            "joblib": _package_version("joblib"),
        },
        "dataset": {
            "version": config.dataset_version,
            "path": dataset_display_path(dataset.path),
            "sha256": dataset.sha256,
            "rows": len(dataset.complaints),
            "groups": len(dataset.groups),
            "synthetic": True,
            "human_verified": False,
        },
        "split": {
            "strategy": "Grouped issue variants; train, validation, and test are disjoint.",
            "train_groups": sorted({complaint.group_id for complaint in train_complaints}),
            "validation_groups": sorted(
                {complaint.group_id for complaint in validation_complaints}
            ),
            "test_groups": freeze_record["group_ids"],
            "train_complaints": len(train_complaints),
            "validation_complaints": len(validation_complaints),
            "test_complaints": freeze["complaint_count"],
            "frozen_test": freeze_record,
        },
        "training": {
            "vectorizer_fit": "train split only",
            "final_vectorizer_rows": len(train_complaints),
            "feature_config_selection": (
                "Validation split: maximum F1 subject to false-positive rate <= "
                f"{config.max_fpr:.2f}; tie-break lower FPR, higher threshold, config name."
            ),
            "threshold_selection": (
                "Validation split: maximum F1 subject to false-positive rate <= "
                f"{config.max_fpr:.2f} over {list(THRESHOLD_GRID)}; thresholds are "
                "applied to ranking scores with a text-evidence floor."
            ),
            "uncertain_band": (
                f"Artifact duplicate threshold minus {config.uncertain_band:.2f}; "
                "an operating band, not a calibrated probability."
            ),
            "test_usage": (
                "The test split is fingerprinted before selection and never scored by "
                "the training command."
            ),
        },
        "validation": {
            **_metrics_payload(validation_metrics),
            "hard_negatives": _hard_negative_metrics(
                validation_pairs,
                selected_validation_scores,
                selected.metrics.threshold,
            ),
        },
        "train": {
            **_metrics_payload(train_metrics),
            "hard_negatives": _hard_negative_metrics(
                train_pairs,
                train_scores,
                selected.metrics.threshold,
            ),
        },
        "limitations": [
            "All complaints and pair labels are synthetic and not human-verified.",
            "The detector is lexical TF-IDF and can miss semantic paraphrases.",
            "Similarity and ranking scores are not calibrated probabilities.",
            "Thresholds and feature configuration were selected on a small validation split.",
            "The frozen test results do not establish production readiness.",
            "The service is not integrated with NestJS or Flutter.",
            "No complaint is merged, rejected, or modified.",
        ],
    }

    selection_payload = [
        {
            "feature_config": feature_config.to_dict(),
            "validation": {
                **_metrics_payload(candidate.metrics),
                "uncertain_threshold": candidate.uncertain_threshold,
            },
        }
        for candidate, feature_config, _details, _scores in candidate_results
    ]
    report: dict[str, Any] = {
        "artifact_version": artifact_version,
        "model_version": config.model_version,
        "dataset_version": config.dataset_version,
        "dataset_sha256": dataset.sha256,
        "pairs_sha256": hashlib.sha256(config.pairs_path.read_bytes()).hexdigest(),
        "frozen_test": freeze_record,
        "selection_rule": (
            "Select feature configuration and duplicate threshold on validation only: "
            f"maximum F1 subject to FPR <= {config.max_fpr:.2f}."
        ),
        "threshold_grid": list(THRESHOLD_GRID),
        "support_signals": config.support.to_dict(),
        "selected_feature_config": selected_config.to_dict(),
        "selected_duplicate_threshold": selected.metrics.threshold,
        "selected_uncertain_threshold": selected.uncertain_threshold,
        "candidates": selection_payload,
        "train": {
            **_metrics_payload(train_metrics),
            "hard_negatives": _hard_negative_metrics(
                train_pairs,
                train_scores,
                selected.metrics.threshold,
            ),
        },
        "validation": {
            **_metrics_payload(validation_metrics),
            "hard_negatives": _hard_negative_metrics(
                validation_pairs,
                selected_validation_scores,
                selected.metrics.threshold,
            ),
        },
        "test_scored": False,
    }

    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    training_report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return DuplicateTrainingResult(
        model_dir=output_dir,
        model_path=model_path,
        metadata_path=metadata_path,
        training_report_path=training_report_path,
        model_version=config.model_version,
        dataset=dataset,
        pairs=pairs,
        metadata=metadata,
        report=report,
    )
