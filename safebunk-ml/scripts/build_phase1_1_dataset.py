"""Build the Phase 1.1 dataset from the untouched Phase 1 CSV plus additions.

The build is deterministic and verifies that no new row creates a near-duplicate
group crossing the frozen Phase 1 holdout. It does not modify the Phase 1 CSV.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.dataset import (
    DatasetValidationError,
    InsufficientDataError,
    load_and_validate_dataset,
    near_duplicate_groups,
    stratified_group_split,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = PROJECT_ROOT / "data" / "synthetic_complaints.csv"
DEFAULT_ADDITIONS = PROJECT_ROOT / "data" / "phase1_1_additions.csv"
DEFAULT_OUTPUT = PROJECT_ROOT / "data" / "synthetic_complaints_v2.csv"
NEW_SOURCE = "phase1_1_synthetic"
BASELINE_SOURCE = "phase1_synthetic"


def _build() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--additions", type=Path, default=DEFAULT_ADDITIONS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    try:
        baseline = load_and_validate_dataset(args.baseline)
        additions = load_and_validate_dataset(
            args.additions,
            require_all_categories=False,
        )
    except DatasetValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if any(row.source != NEW_SOURCE for row in additions.rows):
        print(f"All additions must use source={NEW_SOURCE!r}", file=sys.stderr)
        return 1

    baseline_descriptions = {row.description for row in baseline.rows}
    duplicate_descriptions = [
        row.description for row in additions.rows if row.description in baseline_descriptions
    ]
    if duplicate_descriptions:
        print(
            "Additions duplicate baseline descriptions: " + "; ".join(duplicate_descriptions),
            file=sys.stderr,
        )
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(("description", "category", "source"))
        for row in baseline.rows:
            writer.writerow((row.description, row.category, BASELINE_SOURCE))
        for row in additions.rows:
            writer.writerow((row.description, row.category, row.source))

    try:
        combined = load_and_validate_dataset(args.output)
        baseline_split = stratified_group_split(
            baseline,
            test_fraction=0.25,
            random_state=42,
        )
    except (DatasetValidationError, InsufficientDataError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    index_by_description = {row.description: index for index, row in enumerate(combined.rows)}
    holdout_indices = {
        index_by_description[baseline.rows[index].description]
        for index in baseline_split.test_indices
    }
    groups = near_duplicate_groups(combined.rows)
    holdout_groups = {groups[index] for index in holdout_indices}
    train_groups = {groups[index] for index in range(combined.size) if index not in holdout_indices}
    leaked = sorted(holdout_groups & train_groups)
    if leaked:
        leaked_rows = [
            combined.rows[index].row_number for index, group in enumerate(groups) if group in leaked
        ]
        print(
            "Near-duplicate group crosses the frozen Phase 1 holdout. "
            f"Affected CSV rows: {leaked_rows}",
            file=sys.stderr,
        )
        return 1

    source_counts = combined.source_counts
    category_counts = {
        category: combined.category_counts[category] for category in SUPPORTED_CATEGORIES
    }
    print(f"Wrote {args.output}")
    print(f"Rows: {combined.size}; sources: {source_counts}; categories: {category_counts}")
    print(f"Frozen Phase 1 holdout: {len(holdout_indices)} rows, near-duplicate leakage check PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(_build())
