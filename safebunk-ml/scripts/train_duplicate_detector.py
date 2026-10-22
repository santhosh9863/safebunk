"""Train and select the Phase 2.1 persisted duplicate detector."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from pulse_ml.duplicate_dataset import DuplicateDatasetError
from pulse_ml.duplicate_training import DuplicateTrainingConfig, train_duplicate_detector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = PROJECT_ROOT / "data" / "duplicate_detection_v2_complaints.csv"
DEFAULT_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_v2_pairs.csv"
DEFAULT_FREEZE = PROJECT_ROOT / "data" / "duplicate_detection_v2_test_freeze.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "artifacts" / "duplicate-detector" / "v0.2.0"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--pairs", type=Path, default=DEFAULT_PAIRS)
    parser.add_argument("--freeze", type=Path, default=DEFAULT_FREEZE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--model-version", default="0.2.0")
    args = parser.parse_args()

    try:
        result = train_duplicate_detector(
            DuplicateTrainingConfig(
                dataset_path=args.dataset,
                pairs_path=args.pairs,
                freeze_path=args.freeze,
                output_dir=args.output,
                model_version=args.model_version,
            )
        )
    except (DuplicateDatasetError, ValueError, OSError) as exc:
        print(f"Training failed: {exc}", file=sys.stderr)
        return 1

    selected = result.report["selected_feature_config"]
    train = result.report["train"]
    validation = result.report["validation"]
    print(f"Selected feature config: {selected['name']}")
    print(
        "Selected thresholds: "
        f"duplicate={result.report['selected_duplicate_threshold']:.2f} "
        f"uncertain={result.report['selected_uncertain_threshold']:.2f}"
    )
    print(
        "Train metrics: "
        f"precision={train['precision']:.4f} recall={train['recall']:.4f} "
        f"f1={train['f1']:.4f} fpr={train['false_positive_rate']:.4f}"
    )
    print(
        "Validation metrics: "
        f"precision={validation['precision']:.4f} recall={validation['recall']:.4f} "
        f"f1={validation['f1']:.4f} fpr={validation['false_positive_rate']:.4f}"
    )
    print(
        "Validation hard negatives: "
        f"{validation['hard_negatives']['false_positives']} / "
        f"{validation['hard_negatives']['pairs']} "
        f"(FPR {validation['hard_negatives']['false_positive_rate']:.4f})"
    )
    print(f"Wrote {result.model_path}")
    print(f"Wrote {result.metadata_path}")
    print(f"Wrote {result.training_report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
