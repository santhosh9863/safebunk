"""Evaluate the persisted duplicate detector on the frozen Phase 2.1 test set."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from pulse_ml.duplicate_dataset import DuplicateDatasetError
from pulse_ml.duplicate_model import DuplicateModelError
from pulse_ml.duplicate_model_evaluation import evaluate_frozen_duplicate_detector

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = PROJECT_ROOT / "data" / "duplicate_detection_v2_complaints.csv"
DEFAULT_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_v2_pairs.csv"
DEFAULT_FREEZE = PROJECT_ROOT / "data" / "duplicate_detection_v2_test_freeze.json"
DEFAULT_MODEL_DIR = PROJECT_ROOT / "artifacts" / "duplicate-detector" / "v0.2.0"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--pairs", type=Path, default=DEFAULT_PAIRS)
    parser.add_argument("--freeze", type=Path, default=DEFAULT_FREEZE)
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    args = parser.parse_args()

    try:
        report = evaluate_frozen_duplicate_detector(
            model_dir=args.model_dir,
            dataset_path=args.dataset,
            pairs_path=args.pairs,
            freeze_path=args.freeze,
            output_dir=args.model_dir,
        )
    except (DuplicateDatasetError, DuplicateModelError, ValueError, OSError) as exc:
        print(f"Evaluation failed: {exc}", file=sys.stderr)
        return 1

    candidate = report["candidate_frozen_test"]
    baseline = report["baseline_test_corpus_fitted_diagnostic"]
    text_only = report["candidate_text_only_ablation"]
    print(
        "Frozen-test candidate at selected threshold: "
        f"precision={candidate['precision']:.4f} recall={candidate['recall']:.4f} "
        f"f1={candidate['f1']:.4f} fpr={candidate['false_positive_rate']:.4f}"
    )
    print(
        "Frozen-test hard negatives: "
        f"{candidate['hard_negatives']['false_positives']} / "
        f"{candidate['hard_negatives']['pairs']} "
        f"(FPR {candidate['hard_negatives']['false_positive_rate']:.4f})"
    )
    print(
        "Text-only ablation: "
        f"precision={text_only['precision']:.4f} recall={text_only['recall']:.4f} "
        f"f1={text_only['f1']:.4f} fpr={text_only['false_positive_rate']:.4f}"
    )
    print(
        "Phase 2 test-corpus diagnostic (not deployed): "
        f"precision={baseline['precision']:.4f} recall={baseline['recall']:.4f} "
        f"f1={baseline['f1']:.4f} fpr={baseline['false_positive_rate']:.4f}"
    )
    print(f"Wrote {args.model_dir / 'evaluation.json'}")
    print(f"Wrote {args.model_dir / 'comparison.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
