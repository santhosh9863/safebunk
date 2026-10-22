"""Re-evaluate a saved artifact on the deterministic held-out split."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from pulse_ml.dataset import (
    DatasetValidationError,
    InsufficientDataError,
    load_and_validate_dataset,
    split_from_metadata,
)
from pulse_ml.model import CategoryPredictor, ModelError
from pulse_ml.training import calculate_metrics, format_confusion_matrix

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL_DIR = PROJECT_ROOT / "artifacts" / "category-classifier" / "v0.1.0"


def _resolve_dataset_path(metadata: dict[str, Any]) -> Path:
    dataset_metadata = metadata.get("dataset")
    if not isinstance(dataset_metadata, dict):
        raise ValueError("model metadata has no dataset block")
    relative = dataset_metadata.get("path")
    if not isinstance(relative, str) or not relative:
        raise ValueError("model metadata has no dataset path")

    candidates = [
        Path(relative),
        PROJECT_ROOT / relative,
        PROJECT_ROOT.parent / relative,
        PROJECT_ROOT / "data" / Path(relative).name,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"dataset from metadata was not found: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--dataset", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    try:
        predictor = CategoryPredictor.from_directory(args.model_dir)
        metadata = predictor.metadata
        dataset_path = args.dataset or _resolve_dataset_path(metadata)
        dataset = load_and_validate_dataset(dataset_path)

        expected_hash = metadata["dataset"]["sha256"]
        if dataset.sha256 != expected_hash:
            raise ValueError(
                "dataset SHA-256 does not match the artifact metadata; "
                "retrain or use the original dataset"
            )

        split = split_from_metadata(dataset, metadata)
    except (
        ModelError,
        DatasetValidationError,
        InsufficientDataError,
        KeyError,
        OSError,
        ValueError,
    ) as exc:
        print(f"Evaluation failed: {exc}", file=sys.stderr)
        return 1

    y_true = [dataset.rows[index].category for index in split.test_indices]
    y_pred = [
        predictor.predict(dataset.rows[index].description).category for index in split.test_indices
    ]
    metrics = calculate_metrics(y_true, y_pred)

    print(f"Model version: {predictor.model_version}")
    print(f"Dataset: {dataset_path} ({dataset.size} rows, SHA-256 verified)")
    print(f"Evaluated {len(split.test_indices)} held-out rows across {len(set(y_true))} categories")
    print(f"Accuracy: {metrics['accuracy']:.4f}")
    print(f"Macro-F1: {metrics['macro_f1']:.4f}")
    print(json.dumps(metrics["per_class"], indent=2))
    print(format_confusion_matrix(metrics))

    stored = metadata.get("evaluation")
    if isinstance(stored, dict) and stored.get("macro_f1") != metrics["macro_f1"]:
        print(
            "Warning: recomputed macro-F1 differs from the stored metadata. "
            "The artifact may have been produced by a different library version.",
            file=sys.stderr,
        )

    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
        print(f"Metrics written to {args.output}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
