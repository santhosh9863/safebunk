"""Retrain on Phase 1.1 data without touching the frozen Phase 1 holdout.

The 48 test rows are reconstructed from the original Phase 1 dataset with the
same seed. They are held out from the new model, and every new Phase 1.1 row is
kept in training. The baseline artifact and its metrics are left untouched.
"""

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
    stratified_group_split,
)
from pulse_ml.training import (
    TrainingConfig,
    format_confusion_matrix,
    train_category_classifier,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints.csv"
DEFAULT_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints_v2.csv"
DEFAULT_OUTPUT_ROOT = PROJECT_ROOT / "artifacts" / "category-classifier"
DEFAULT_BASELINE_METRICS = DEFAULT_OUTPUT_ROOT / "v0.1.0" / "metrics.json"


def _per_class_delta(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
) -> dict[str, dict[str, float]]:
    deltas: dict[str, dict[str, float]] = {}
    baseline_classes = baseline.get("per_class", {})
    candidate_classes = candidate.get("per_class", {})
    if not isinstance(baseline_classes, dict) or not isinstance(candidate_classes, dict):
        return deltas
    for category in candidate_classes:
        baseline_values = baseline_classes.get(category)
        candidate_values = candidate_classes.get(category)
        if not isinstance(baseline_values, dict) or not isinstance(candidate_values, dict):
            continue
        deltas[category] = {
            metric: round(
                float(candidate_values[metric]) - float(baseline_values[metric]),
                6,
            )
            for metric in ("precision", "recall", "f1")
        }
    return deltas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dataset", type=Path, default=DEFAULT_BASELINE_DATASET)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--model-version", default="0.2.0")
    parser.add_argument("--baseline-metrics", type=Path, default=DEFAULT_BASELINE_METRICS)
    parser.add_argument("--test-fraction", type=float, default=0.25)
    parser.add_argument("--random-state", type=int, default=42)
    args = parser.parse_args()

    try:
        baseline = load_and_validate_dataset(args.baseline_dataset)
        dataset = load_and_validate_dataset(args.dataset)
        baseline_split = stratified_group_split(
            baseline,
            test_fraction=args.test_fraction,
            random_state=args.random_state,
        )
        holdout_descriptions = {
            baseline.rows[index].description for index in baseline_split.test_indices
        }
        index_by_description = {row.description: row.row_number for row in dataset.rows}
        missing_descriptions = sorted(holdout_descriptions - index_by_description.keys())
        if missing_descriptions:
            raise ValueError(
                "Phase 1 holdout descriptions are missing from the Phase 1.1 dataset: "
                + "; ".join(missing_descriptions)
            )
        holdout_row_numbers = tuple(
            sorted(index_by_description[description] for description in holdout_descriptions)
        )
        holdout_rows = [row for row in dataset.rows if row.row_number in set(holdout_row_numbers)]
        non_baseline_sources = sorted(
            {row.source or "<missing>" for row in holdout_rows if row.source != "phase1_synthetic"}
        )
        if non_baseline_sources:
            raise ValueError(
                "The frozen holdout contains rows that are not Phase 1 baseline rows: "
                f"{non_baseline_sources}"
            )
        baseline_metrics = json.loads(args.baseline_metrics.read_text(encoding="utf-8"))
    except (
        DatasetValidationError,
        InsufficientDataError,
        OSError,
        UnicodeDecodeError,
        json.JSONDecodeError,
        ValueError,
    ) as exc:
        print(f"Phase 1.1 setup failed: {exc}", file=sys.stderr)
        return 1

    output_dir = args.output_root / f"v{args.model_version}"
    config = TrainingConfig(
        dataset_path=args.dataset,
        output_dir=output_dir,
        model_version=args.model_version,
        test_fraction=args.test_fraction,
        random_state=args.random_state,
        holdout_row_numbers=holdout_row_numbers,
        holdout_description=(
            "Untouched 48-row Phase 1 baseline test set reconstructed with "
            f"fraction={args.test_fraction}, random_state={args.random_state}. "
            "All Phase 1.1 additions are in training."
        ),
    )

    try:
        result = train_category_classifier(config)
    except (DatasetValidationError, InsufficientDataError, ValueError) as exc:
        print(f"Training failed: {exc}", file=sys.stderr)
        return 2

    per_class_delta = _per_class_delta(baseline_metrics, result.metrics)
    comparison = {
        "evaluation_protocol": "fixed 48-row Phase 1 baseline holdout",
        "baseline_model_version": "0.1.0",
        "candidate_model_version": result.model_version,
        "baseline_metrics": baseline_metrics,
        "candidate_metrics": result.metrics,
        "delta": {
            "accuracy": round(
                float(result.metrics["accuracy"]) - float(baseline_metrics["accuracy"]),
                6,
            ),
            "macro_f1": round(
                float(result.metrics["macro_f1"]) - float(baseline_metrics["macro_f1"]),
                6,
            ),
            "per_class": per_class_delta,
        },
        "note": (
            "Both models were evaluated on the same untouched Phase 1 test rows. "
            "The candidate used Phase 1.1 synthetic additions in training. This is "
            "a synthetic benchmark, not production evidence."
        ),
    }
    comparison_path = output_dir / "comparison.json"
    comparison_path.write_text(
        json.dumps(comparison, indent=2) + "\n",
        encoding="utf-8",
    )

    print("Phase 1.1 training complete")
    print(f"Dataset: {result.dataset.path} ({result.dataset.size} rows)")
    print(
        "Frozen holdout: "
        f"{len(result.split.test_indices)} rows; training rows: "
        f"{len(result.split.train_indices)}; groups: {result.split.n_groups}"
    )
    print(f"Accuracy: {result.metrics['accuracy']:.4f}")
    print(f"Macro-F1: {result.metrics['macro_f1']:.4f}")
    print("Per-class metrics:")
    print(json.dumps(result.metrics["per_class"], indent=2))
    print(format_confusion_matrix(result.metrics))
    print("Comparison on the same holdout:")
    print(
        f"  accuracy {baseline_metrics['accuracy']:.4f} -> "
        f"{result.metrics['accuracy']:.4f} "
        f"(delta {comparison['delta']['accuracy']:+.4f})"
    )
    print(
        f"  macro-F1 {baseline_metrics['macro_f1']:.4f} -> "
        f"{result.metrics['macro_f1']:.4f} "
        f"(delta {comparison['delta']['macro_f1']:+.4f})"
    )
    for category in ("Electrical", "Network / IT"):
        delta = per_class_delta.get(category, {})
        baseline_class = baseline_metrics["per_class"][category]
        candidate_class = result.metrics["per_class"][category]
        print(
            f"  {category}: F1 {baseline_class['f1']:.4f} -> "
            f"{candidate_class['f1']:.4f} "
            f"(delta {delta.get('f1', 0.0):+.4f}; "
            f"P {baseline_class['precision']:.4f} -> {candidate_class['precision']:.4f}; "
            f"R {baseline_class['recall']:.4f} -> {candidate_class['recall']:.4f})"
        )
    print(f"Artifact: {result.model_path}")
    print(f"Comparison: {comparison_path}")
    print("No production-readiness claim is made; the dataset remains small and synthetic.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
