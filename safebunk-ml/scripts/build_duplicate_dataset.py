"""Build the reproducible synthetic duplicate-detection pair benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

from pulse_ml.duplicate_dataset import (
    DuplicateComplaint,
    DuplicateDatasetError,
    build_duplicate_pairs,
    load_duplicate_complaints,
    write_duplicate_pairs,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMPLAINTS = PROJECT_ROOT / "data" / "duplicate_detection_complaints.csv"
DEFAULT_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_pairs.csv"
DEFAULT_METADATA = PROJECT_ROOT / "data" / "duplicate_detection.metadata.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def _split_stats(
    groups: dict[str, tuple[DuplicateComplaint, ...]], split: str
) -> dict[str, object]:
    split_groups = {group_id: rows for group_id, rows in groups.items() if rows[0].split == split}
    return {
        "complaints": sum(len(rows) for rows in split_groups.values()),
        "groups": len(split_groups),
        "categories": sorted({rows[0].category for rows in split_groups.values()}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complaints", type=Path, default=DEFAULT_COMPLAINTS)
    parser.add_argument("--pairs-output", type=Path, default=DEFAULT_PAIRS)
    parser.add_argument("--metadata-output", type=Path, default=DEFAULT_METADATA)
    args = parser.parse_args()

    try:
        dataset = load_duplicate_complaints(args.complaints)
        pairs = build_duplicate_pairs(dataset)
        write_duplicate_pairs(pairs, args.pairs_output)
    except (DuplicateDatasetError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    groups = dataset.groups
    split_summary = {split: _split_stats(groups, split) for split in ("train", "test")}
    pair_summary = {}
    for split in ("train", "test"):
        split_pairs = [pair for pair in pairs if pair.split == split]
        pair_summary[split] = {
            "pairs": len(split_pairs),
            "positive": sum(pair.label == 1 for pair in split_pairs),
            "negative": sum(pair.label == 0 for pair in split_pairs),
            "difficulty": dict(Counter(pair.difficulty for pair in split_pairs)),
        }

    metadata = {
        "dataset_version": "duplicate-detection-v0.1.0",
        "synthetic": True,
        "human_verified": False,
        "label_source": (
            "Synthetic issue-group labels authored for this benchmark; not human-verified."
        ),
        "pii_review": (
            "No real complaints, personal names, student IDs, contact details, or addresses."
        ),
        "purpose": (
            "Read-only evaluation of TF-IDF cosine duplicate suggestions. "
            "Not a production-readiness claim."
        ),
        "source": {
            "path": _display_path(args.complaints),
            "sha256": dataset.sha256,
            "rows": len(dataset.complaints),
            "groups": len(groups),
            "variants_per_group": sorted({len(rows) for rows in groups.values()}),
            "categories": sorted({row.category for row in dataset.complaints}),
        },
        "pairs": {
            "path": _display_path(args.pairs_output),
            "sha256": _sha256(args.pairs_output),
            "rows": len(pairs),
            "label_definition": (
                "label=1 when both complaints belong to the same underlying issue group; "
                "label=0 otherwise."
            ),
            "construction": (
                "Every unordered pair of complaints within the same split is included. "
                "No negative sampling or model-score-based selection is used."
            ),
            "difficulty_definition": (
                "Positives are 'duplicate'. Negatives are 'hard_negative' when they share "
                "category or location, or have token Jaccard >= 0.30; 'medium_negative' "
                "when they share neither but Jaccard >= 0.15; otherwise 'easy_negative'."
            ),
        },
        "split": {
            "strategy": "By issue group; a group's variants appear in exactly one split.",
            "group_purity": True,
            "group_overlap": [],
            "summary": split_summary,
            "pair_summary": pair_summary,
        },
        "reproduction": {
            "command": "python scripts/build_duplicate_dataset.py",
            "deterministic": True,
        },
    }

    args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
    args.metadata_output.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(f"Complaints: {len(dataset.complaints)} in {len(groups)} groups")
    print(
        "Train: "
        f"{split_summary['train']['complaints']} complaints / "
        f"{split_summary['train']['groups']} groups"
    )
    print(
        "Test:  "
        f"{split_summary['test']['complaints']} complaints / "
        f"{split_summary['test']['groups']} groups"
    )
    for split in ("train", "test"):
        summary = pair_summary[split]
        print(
            f"{split.title()} pairs: {summary['pairs']} "
            f"({summary['positive']} positive / {summary['negative']} negative)"
        )
        print(f"  difficulty: {summary['difficulty']}")
    print(f"Complaint SHA-256: {dataset.sha256}")
    print(f"Pair SHA-256: {_sha256(args.pairs_output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
