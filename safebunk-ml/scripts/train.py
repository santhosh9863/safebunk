"""Train and evaluate the versioned category classifier."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from pulse_ml.dataset import DatasetValidationError, InsufficientDataError
from pulse_ml.training import (
    DEFAULT_CONFIDENCE_THRESHOLD,
    TrainingConfig,
    format_confusion_matrix,
    train_category_classifier,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints.csv"
DEFAULT_ARTIFACT_ROOT = PROJECT_ROOT / "artifacts" / "category-classifier"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_ARTIFACT_ROOT)
    parser.add_argument("--model-version", default="0.1.0")
    parser.add_argument("--test-fraction", type=float, default=0.25)
    parser.add_argument("--random-state", type=int, default=42)
    parser.add_argument(
        "--confidence-threshold",
        type=float,
        default=DEFAULT_CONFIDENCE_THRESHOLD,
    )
    parser.add_argument(
        "--dataset-metadata",
        type=Path,
        default=None,
        help="Optional JSON sidecar; defaults to <dataset>.metadata.json.",
    )
    args = parser.parse_args()

    output_dir = args.output_root / f"v{args.model_version}"
    config = TrainingConfig(
        dataset_path=args.dataset,
        output_dir=output_dir,
        model_version=args.model_version,
        test_fraction=args.test_fraction,
        random_state=args.random_state,
        confidence_threshold=args.confidence_threshold,
        dataset_metadata_path=args.dataset_metadata,
    )

    try:
        result = train_category_classifier(config)
    except (DatasetValidationError, InsufficientDataError, ValueError) as exc:
        print(f"Training failed: {exc}", file=sys.stderr)
        return 2

    print("Training complete")
    print(f"Dataset: {result.dataset.path} ({result.dataset.size} rows)")
    print(
        "Split: "
        f"{len(result.split.train_indices)} train / {len(result.split.test_indices)} test, "
        f"{result.split.n_groups} near-duplicate groups"
    )
    print(f"Accuracy: {result.metrics['accuracy']:.4f}")
    print(f"Macro-F1: {result.metrics['macro_f1']:.4f}")
    print("Per-class metrics:")
    print(json.dumps(result.metrics["per_class"], indent=2))
    print(format_confusion_matrix(result.metrics))
    print(f"Artifact: {result.model_path}")
    print(f"Metadata: {result.metadata_path}")
    print(f"Metrics: {result.metrics_path}")
    print(
        "Reminder: this synthetic, tiny holdout is not evidence of production readiness, "
        "and confidence scores are not calibrated probabilities."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
