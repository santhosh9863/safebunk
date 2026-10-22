"""Validate a dataset without training a model."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.dataset import DatasetValidationError, load_and_validate_dataset

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints.csv"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Allow a focused file that does not contain all eight categories.",
    )
    args = parser.parse_args()

    try:
        dataset = load_and_validate_dataset(
            args.dataset,
            require_all_categories=not args.allow_partial,
        )
    except DatasetValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    counts = {category: dataset.category_counts[category] for category in SUPPORTED_CATEGORIES}
    payload = {
        "dataset": str(args.dataset),
        "sha256": dataset.sha256,
        "rows": dataset.size,
        "category_counts": counts,
        "source_counts": dataset.source_counts,
        "balanced": len(set(counts.values())) == 1,
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
