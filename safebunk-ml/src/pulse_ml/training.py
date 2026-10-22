"""Reproducible training and evaluation for the category baseline."""

from __future__ import annotations

import json
import platform
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Any

import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.pipeline import Pipeline

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.dataset import (
    Dataset,
    DatasetSplit,
    dataset_display_path,
    fixed_holdout_split,
    load_and_validate_dataset,
    stratified_group_split,
)

DEFAULT_CONFIDENCE_THRESHOLD = 0.20
MODEL_VERSION_PATTERN = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$")


@dataclass(frozen=True)
class TrainingConfig:
    dataset_path: Path
    output_dir: Path
    model_version: str = "0.1.0"
    test_fraction: float = 0.25
    random_state: int = 42
    confidence_threshold: float = DEFAULT_CONFIDENCE_THRESHOLD
    dataset_metadata_path: Path | None = None
    holdout_row_numbers: tuple[int, ...] | None = None
    holdout_description: str | None = None


@dataclass(frozen=True)
class TrainingResult:
    model_dir: Path
    model_path: Path
    metadata_path: Path
    metrics_path: Path
    model_version: str
    dataset: Dataset
    split: DatasetSplit
    metrics: dict[str, Any]
    metadata: dict[str, Any]


def build_pipeline(*, random_state: int) -> Pipeline:
    """Build the documented TF-IDF plus logistic-regression baseline."""

    return Pipeline(
        steps=[
            (
                "tfidf",
                TfidfVectorizer(
                    analyzer="word",
                    ngram_range=(1, 2),
                    lowercase=True,
                    min_df=1,
                    max_df=0.95,
                    strip_accents="unicode",
                    sublinear_tf=True,
                ),
            ),
            (
                "classifier",
                LogisticRegression(
                    class_weight="balanced",
                    max_iter=2000,
                    random_state=random_state,
                    solver="lbfgs",
                ),
            ),
        ]
    )


def calculate_metrics(
    y_true: list[str],
    y_pred: list[str],
    *,
    labels: tuple[str, ...] = SUPPORTED_CATEGORIES,
) -> dict[str, Any]:
    """Calculate honest holdout metrics for every supported category."""

    if len(y_true) != len(y_pred):
        raise ValueError("y_true and y_pred must have the same length")
    if not y_true:
        raise ValueError("cannot evaluate an empty test set")

    report = classification_report(
        y_true,
        y_pred,
        labels=list(labels),
        output_dict=True,
        zero_division=0,
    )
    per_class: dict[str, dict[str, float | int]] = {}
    for label in labels:
        label_report = report[label]
        per_class[label] = {
            "precision": round(float(label_report["precision"]), 6),
            "recall": round(float(label_report["recall"]), 6),
            "f1": round(float(label_report["f1-score"]), 6),
            "support": int(label_report["support"]),
        }

    matrix = confusion_matrix(y_true, y_pred, labels=list(labels))
    return {
        "accuracy": round(float(accuracy_score(y_true, y_pred)), 6),
        "macro_f1": round(
            float(f1_score(y_true, y_pred, labels=list(labels), average="macro", zero_division=0)),
            6,
        ),
        "macro_precision": round(
            float(
                precision_score(
                    y_true,
                    y_pred,
                    labels=list(labels),
                    average="macro",
                    zero_division=0,
                )
            ),
            6,
        ),
        "macro_recall": round(
            float(
                recall_score(
                    y_true,
                    y_pred,
                    labels=list(labels),
                    average="macro",
                    zero_division=0,
                )
            ),
            6,
        ),
        "per_class": per_class,
        "confusion_matrix": matrix.tolist(),
        "confusion_matrix_labels": list(labels),
        "support": len(y_true),
    }


def format_confusion_matrix(metrics: dict[str, Any]) -> str:
    """Render a compact readable matrix for command-line output."""

    labels = [str(label) for label in metrics["confusion_matrix_labels"]]
    matrix = metrics["confusion_matrix"]
    width = max(len(label) for label in labels) + 2
    lines = ["Confusion matrix (rows = actual, columns = predicted):"]
    lines.append(" " * width + " ".join(f"{label[:12]:>12}" for label in labels))
    for label, row in zip(labels, matrix, strict=True):
        values = " ".join(f"{int(value):>12}" for value in row)
        lines.append(f"{label:<{width}}{values}")
    return "\n".join(lines)


def _validate_config(config: TrainingConfig) -> None:
    if not MODEL_VERSION_PATTERN.fullmatch(config.model_version):
        raise ValueError(
            "model_version must contain only letters, digits, dots, underscores, or hyphens"
        )
    if not 0.0 <= config.confidence_threshold <= 1.0:
        raise ValueError("confidence_threshold must be between 0 and 1")
    if not 0.0 < config.test_fraction < 1.0:
        raise ValueError("test_fraction must be between 0 and 1")


def _package_version(name: str) -> str:
    try:
        return version(name)
    except PackageNotFoundError:
        return "unknown"


def _load_dataset_metadata(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {
            "dataset_id": "unspecified",
            "synthetic": None,
            "provenance": "unspecified",
            "human_verified": False,
        }
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"could not read dataset metadata {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise ValueError("dataset metadata must be a JSON object")
    return raw


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def train_category_classifier(
    config: TrainingConfig,
    *,
    dataset: Dataset | None = None,
) -> TrainingResult:
    """Train, evaluate, and persist one versioned artifact directory."""

    _validate_config(config)
    validated_dataset = dataset or load_and_validate_dataset(config.dataset_path)
    if config.holdout_row_numbers is None:
        split = stratified_group_split(
            validated_dataset,
            test_fraction=config.test_fraction,
            random_state=config.random_state,
        )
        evaluation_protocol = "stratified_grouped_holdout"
    else:
        split = fixed_holdout_split(
            validated_dataset,
            config.holdout_row_numbers,
            random_state=config.random_state,
        )
        evaluation_protocol = "fixed_holdout"

    rows = validated_dataset.rows
    x_train = [rows[index].description for index in split.train_indices]
    y_train = [rows[index].category for index in split.train_indices]
    x_test = [rows[index].description for index in split.test_indices]
    y_test = [rows[index].category for index in split.test_indices]

    pipeline = build_pipeline(random_state=config.random_state)
    pipeline.fit(x_train, y_train)
    y_pred = [str(value) for value in pipeline.predict(x_test)]
    metrics = calculate_metrics(y_test, y_pred)

    output_dir = config.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / "model.joblib"
    metadata_path = output_dir / "metadata.json"
    metrics_path = output_dir / "metrics.json"

    temporary_model_path = output_dir / "model.joblib.tmp"
    joblib.dump(pipeline, temporary_model_path)
    temporary_model_path.replace(model_path)

    dataset_metadata_path = config.dataset_metadata_path
    if dataset_metadata_path is None:
        dataset_metadata_path = config.dataset_path.with_suffix(".metadata.json")
    dataset_metadata = _load_dataset_metadata(dataset_metadata_path)

    created_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    metadata: dict[str, Any] = {
        "schema_version": 1,
        "model_version": config.model_version,
        "created_at": created_at,
        "environment": {
            "python": platform.python_version(),
            "scikit_learn": _package_version("scikit-learn"),
            "numpy": _package_version("numpy"),
            "joblib": _package_version("joblib"),
        },
        "task": "complaint_category_classification",
        "categories": list(SUPPORTED_CATEGORIES),
        "confidence_threshold": config.confidence_threshold,
        "confidence_note": (
            "Confidence is the maximum predict_proba score. It is not a calibrated "
            "probability; consumers must treat scores below the threshold as abstain. "
            "The default 0.20 threshold is an operational routing choice for eight "
            "classes, not a measure of certainty."
        ),
        "dataset": {
            "path": dataset_display_path(validated_dataset.path),
            "sha256": validated_dataset.sha256,
            "rows": validated_dataset.size,
            "category_counts": validated_dataset.category_counts,
            "metadata": dataset_metadata,
        },
        "training": {
            "pipeline": "tfidf_word_1_2 + logistic_regression",
            "vectorizer": {
                "analyzer": "word",
                "ngram_range": [1, 2],
                "max_df": 0.95,
                "sublinear_tf": True,
            },
            "classifier": {
                "class_weight": "balanced",
                "max_iter": 2000,
                "solver": "lbfgs",
            },
            "random_state": config.random_state,
        },
        "split": {
            "method": split.method,
            "test_fraction": round(split.test_fraction, 6),
            "requested_test_fraction": config.test_fraction,
            "random_state": config.random_state,
            "n_groups": split.n_groups,
            "train_rows": len(split.train_indices),
            "test_rows": len(split.test_indices),
            "leakage_guard": (
                "Exact duplicates are rejected; near-identical rows are grouped by "
                "TF-IDF cosine similarity before the split."
            ),
            **(
                {
                    "holdout_row_numbers": list(config.holdout_row_numbers),
                    "holdout_description": config.holdout_description,
                }
                if config.holdout_row_numbers is not None
                else {}
            ),
        },
        "evaluation_protocol": evaluation_protocol,
        "evaluation": metrics,
        "limitations": [
            "This artifact is trained on a small, hand-written synthetic dataset.",
            "The examples are not real campus complaints and the labels are not human-verified.",
            "Phase 1.1 additions, where present, were guided by error review; the fixed "
            "holdout is a targeted synthetic regression benchmark, not a clean "
            "generalization test.",
            "Metrics describe this synthetic holdout split only and are not production evidence.",
            "The model accepts only the description text and does not use identity or role data.",
            "Confidence scores are uncalibrated and must not be shown as certainty.",
            "Low-confidence results require manual review or retention of the existing category.",
            "No priority prediction, duplicate detection, chatbot, or automatic report "
            "mutation is included.",
        ],
    }

    _write_json_atomic(metadata_path, metadata)
    _write_json_atomic(metrics_path, metrics)

    return TrainingResult(
        model_dir=output_dir,
        model_path=model_path,
        metadata_path=metadata_path,
        metrics_path=metrics_path,
        model_version=config.model_version,
        dataset=validated_dataset,
        split=split,
        metrics=metrics,
        metadata=metadata,
    )
