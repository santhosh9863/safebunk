"""Build the Phase 2.1 grouped train/validation/test duplicate benchmark.

The frozen Phase 2 benchmark in ``duplicate_detection_complaints.csv`` is never
modified. This command reuses its 32 issue groups, assigns a new train /
validation / test role to each group, and appends five new groups per category
from ``duplicate_detection_v2_additions.csv``.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from pulse_ml.categories import CATEGORY_SET, SUPPORTED_CATEGORIES
from pulse_ml.duplicate_dataset import (
    COMPLAINT_COLUMNS,
    SPLIT_ORDER,
    TEST_SPLIT,
    TRAIN_SPLIT,
    VALID_SPLITS,
    VALIDATION_SPLIT,
    DuplicateComplaint,
    DuplicateDataset,
    DuplicateDatasetError,
    build_duplicate_pairs,
    load_duplicate_complaints,
    load_duplicate_pairs,
    test_fingerprint,
    verify_test_freeze,
    write_duplicate_pairs,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = PROJECT_ROOT / "data" / "duplicate_detection_complaints.csv"
DEFAULT_ADDITIONS = PROJECT_ROOT / "data" / "duplicate_detection_v2_additions.csv"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data"
DATASET_VERSION = "duplicate-detection-v0.2.0"
ADDITION_COLUMNS = ("group_id", "description", "category", "location", "split")
NEW_GROUPS_PER_CATEGORY = 5
MIN_GROUPS_PER_CATEGORY = 3

# The original Phase 2 groups are reassigned without changing their text.
EXISTING_GROUP_SPLITS: dict[str, str] = {
    "G01": TRAIN_SPLIT,
    "G02": TRAIN_SPLIT,
    "G03": VALIDATION_SPLIT,
    "G04": TEST_SPLIT,
    "G05": TRAIN_SPLIT,
    "G06": TRAIN_SPLIT,
    "G07": VALIDATION_SPLIT,
    "G08": TEST_SPLIT,
    "G09": TRAIN_SPLIT,
    "G10": TRAIN_SPLIT,
    "G11": VALIDATION_SPLIT,
    "G12": TEST_SPLIT,
    "G13": TRAIN_SPLIT,
    "G14": TRAIN_SPLIT,
    "G15": VALIDATION_SPLIT,
    "G16": TEST_SPLIT,
    "G17": TRAIN_SPLIT,
    "G18": TRAIN_SPLIT,
    "G19": VALIDATION_SPLIT,
    "G20": TEST_SPLIT,
    "G21": TRAIN_SPLIT,
    "G22": TRAIN_SPLIT,
    "G23": VALIDATION_SPLIT,
    "G24": TEST_SPLIT,
    "G25": TRAIN_SPLIT,
    "G26": TRAIN_SPLIT,
    "G27": VALIDATION_SPLIT,
    "G28": TEST_SPLIT,
    "G29": TRAIN_SPLIT,
    "G30": TRAIN_SPLIT,
    "G31": VALIDATION_SPLIT,
    "G32": TEST_SPLIT,
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _display_path(path: Path) -> str:
    try:
        return str(path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def _write_complaints(complaints: list[DuplicateComplaint], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(COMPLAINT_COLUMNS)
        for complaint in complaints:
            writer.writerow(
                (
                    complaint.complaint_id,
                    complaint.group_id,
                    complaint.description,
                    complaint.category,
                    complaint.location,
                    complaint.split,
                )
            )


def _load_additions(
    path: Path,
    *,
    starting_complaint_number: int,
    existing_descriptions: set[str],
) -> list[DuplicateComplaint]:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise DuplicateDatasetError([f"could not read {path}: {exc}"]) from exc

    issues: list[str] = []
    rows: list[dict[str, str]] = []
    try:
        reader = csv.DictReader(io.StringIO(raw))
        if reader.fieldnames is None or tuple(reader.fieldnames) != ADDITION_COLUMNS:
            raise DuplicateDatasetError(
                [f"addition header must be exactly {ADDITION_COLUMNS}; found {reader.fieldnames}"]
            )
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                issues.append(f"row {row_number}: unexpected extra field")
                continue
            values = {name: (row.get(name) or "").strip() for name in ADDITION_COLUMNS}
            if not values["group_id"]:
                issues.append(f"row {row_number}: missing group_id")
            if len(values["description"]) < 10:
                issues.append(f"row {row_number}: description is too short")
            if values["category"] not in CATEGORY_SET:
                issues.append(f"row {row_number}: unknown category {values['category']!r}")
            if not values["location"]:
                issues.append(f"row {row_number}: missing location")
            if values["split"] not in VALID_SPLITS:
                issues.append(f"row {row_number}: unknown split {values['split']!r}")
            rows.append(values)
    except csv.Error as exc:
        raise DuplicateDatasetError([f"malformed addition CSV: {exc}"]) from exc

    grouped: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        grouped.setdefault(row["group_id"], []).append(row)

    if len(grouped) != NEW_GROUPS_PER_CATEGORY * len(SUPPORTED_CATEGORIES):
        issues.append(
            f"expected {NEW_GROUPS_PER_CATEGORY * len(SUPPORTED_CATEGORIES)} new groups; "
            f"found {len(grouped)}"
        )

    category_group_counts: Counter[str] = Counter()
    category_split_counts: dict[str, Counter[str]] = {
        category: Counter() for category in SUPPORTED_CATEGORIES
    }
    for group_id, group_rows in grouped.items():
        if len(group_rows) != 3:
            issues.append(f"group {group_id}: expected 3 variants; found {len(group_rows)}")
        for field in ("category", "location", "split"):
            field_values = {row[field] for row in group_rows}
            if len(field_values) != 1:
                issues.append(f"group {group_id}: variants disagree on {field}")
        category = group_rows[0]["category"]
        split = group_rows[0]["split"]
        if category in CATEGORY_SET and split in VALID_SPLITS:
            category_group_counts[category] += 1
            category_split_counts[category][split] += 1
        for row in group_rows:
            normalized = " ".join(row["description"].casefold().split())
            if normalized in existing_descriptions:
                issues.append(
                    f"group {group_id}: duplicate description already used: {row['description']!r}"
                )
            existing_descriptions.add(normalized)

    for category in SUPPORTED_CATEGORIES:
        if category_group_counts[category] != NEW_GROUPS_PER_CATEGORY:
            issues.append(
                f"category {category}: expected {NEW_GROUPS_PER_CATEGORY} new groups; "
                f"found {category_group_counts[category]}"
            )
        expected_splits = Counter({TRAIN_SPLIT: 1, VALIDATION_SPLIT: 2, TEST_SPLIT: 2})
        if category_split_counts[category] != expected_splits:
            issues.append(
                f"category {category}: new group splits must be "
                f"{dict(expected_splits)}; found {dict(category_split_counts[category])}"
            )

    if issues:
        raise DuplicateDatasetError(issues)

    complaints: list[DuplicateComplaint] = []
    complaint_number = starting_complaint_number
    for group_id, group_rows in grouped.items():
        for row in group_rows:
            complaints.append(
                DuplicateComplaint(
                    complaint_id=f"C{complaint_number:03d}",
                    group_id=group_id,
                    description=row["description"],
                    category=row["category"],
                    location=row["location"],
                    split=row["split"],
                )
            )
            complaint_number += 1
    return complaints


def _validate_combined(
    complaints: list[DuplicateComplaint],
    *,
    additions: list[DuplicateComplaint],
) -> None:
    issues: list[str] = []
    grouped: dict[str, list[DuplicateComplaint]] = {}
    for complaint in complaints:
        grouped.setdefault(complaint.group_id, []).append(complaint)

    if len(grouped) != 72:
        issues.append(f"expected 72 issue groups; found {len(grouped)}")
    for group_id, rows in grouped.items():
        if len(rows) != 3:
            issues.append(f"group {group_id}: expected 3 complaints; found {len(rows)}")
        for field in ("category", "location", "split"):
            values = {getattr(row, field) for row in rows}
            if len(values) != 1:
                issues.append(f"group {group_id}: variants disagree on {field}")

    for split in SPLIT_ORDER:
        split_rows = [row for row in complaints if row.split == split]
        if len(split_rows) != 72:
            issues.append(f"split {split}: expected 72 complaints; found {len(split_rows)}")
        for category in SUPPORTED_CATEGORIES:
            category_groups = {row.group_id for row in split_rows if row.category == category}
            if len(category_groups) != MIN_GROUPS_PER_CATEGORY:
                issues.append(
                    f"split {split}: category {category} needs "
                    f"{MIN_GROUPS_PER_CATEGORY} groups; found {len(category_groups)}"
                )

    if len(additions) != 120:
        issues.append(f"expected 120 addition rows; found {len(additions)}")
    if issues:
        raise DuplicateDatasetError(issues)


def _split_summary(dataset: DuplicateDataset) -> dict[str, dict[str, Any]]:
    summary: dict[str, dict[str, Any]] = {}
    for split in SPLIT_ORDER:
        rows = dataset.split_complaints[split]
        summary[split] = {
            "complaints": len(rows),
            "groups": len({row.group_id for row in rows}),
            "categories": sorted({row.category for row in rows}),
            "group_ids": sorted({row.group_id for row in rows}),
            "category_group_counts": {
                category: len({row.group_id for row in rows if row.category == category})
                for category in SUPPORTED_CATEGORIES
            },
        }
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--additions", type=Path, default=DEFAULT_ADDITIONS)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()

    complaints_path = args.output_dir / "duplicate_detection_v2_complaints.csv"
    pairs_path = args.output_dir / "duplicate_detection_v2_pairs.csv"
    metadata_path = args.output_dir / "duplicate_detection_v2.metadata.json"
    freeze_path = args.output_dir / "duplicate_detection_v2_test_freeze.json"

    try:
        source = load_duplicate_complaints(args.source)
        if set(source.groups) != set(EXISTING_GROUP_SPLITS):
            raise DuplicateDatasetError(
                ["source dataset groups do not match the frozen Phase 2 group list"]
            )

        existing_descriptions = {
            " ".join(complaint.description.casefold().split()) for complaint in source.complaints
        }
        additions = _load_additions(
            args.additions,
            starting_complaint_number=len(source.complaints) + 1,
            existing_descriptions=existing_descriptions,
        )

        combined = [
            DuplicateComplaint(
                complaint_id=complaint.complaint_id,
                group_id=complaint.group_id,
                description=complaint.description,
                category=complaint.category,
                location=complaint.location,
                split=EXISTING_GROUP_SPLITS[complaint.group_id],
            )
            for complaint in source.complaints
        ]
        combined.extend(additions)
        _validate_combined(combined, additions=additions)

        ordered = sorted(
            combined,
            key=lambda row: (
                SPLIT_ORDER.index(row.split),
                row.group_id,
                row.complaint_id,
            ),
        )
        _write_complaints(ordered, complaints_path)

        dataset = load_duplicate_complaints(
            complaints_path,
            required_splits=VALID_SPLITS,
            min_groups_per_category=MIN_GROUPS_PER_CATEGORY,
        )
        pairs = build_duplicate_pairs(dataset)
        write_duplicate_pairs(pairs, pairs_path)
        loaded_pairs = load_duplicate_pairs(pairs_path, dataset)

        fingerprint = test_fingerprint(dataset, loaded_pairs)
        freeze: dict[str, Any] = {
            "schema_version": 1,
            "dataset_version": DATASET_VERSION,
            "frozen_before_tuning": True,
            "notes": [
                "Generated with the dataset before candidate selection.",
                "Training may fit only the train split; thresholds and feature "
                "configuration must be selected on train/validation.",
                "Evaluation must verify this fingerprint before scoring the test split.",
            ],
            **fingerprint,
        }
        verify_test_freeze(dataset, loaded_pairs, freeze)

        split_summary = _split_summary(dataset)
        pair_summary: dict[str, dict[str, Any]] = {}
        for split in SPLIT_ORDER:
            split_pairs = [pair for pair in loaded_pairs if pair.split == split]
            pair_summary[split] = {
                "pairs": len(split_pairs),
                "positive": sum(pair.label == 1 for pair in split_pairs),
                "negative": sum(pair.label == 0 for pair in split_pairs),
                "difficulty": dict(Counter(pair.difficulty for pair in split_pairs)),
            }

        metadata: dict[str, Any] = {
            "dataset_version": DATASET_VERSION,
            "synthetic": True,
            "human_verified": False,
            "label_source": (
                "Synthetic issue-group labels authored for this benchmark; not human-verified."
            ),
            "pii_review": (
                "No real complaints, personal names, student IDs, contact details, or addresses."
            ),
            "purpose": (
                "Grouped train/validation/test evaluation of a persisted TF-IDF duplicate "
                "detector. Not a production-readiness claim."
            ),
            "source": {
                "phase2_complaints": {
                    "path": _display_path(args.source),
                    "sha256": source.sha256,
                    "rows": len(source.complaints),
                    "groups": len(source.groups),
                },
                "phase2_1_additions": {
                    "path": _display_path(args.additions),
                    "sha256": _sha256(args.additions),
                    "rows": len(additions),
                    "groups": len({row.group_id for row in additions}),
                },
            },
            "complaints": {
                "path": _display_path(complaints_path),
                "sha256": dataset.sha256,
                "rows": len(dataset.complaints),
                "groups": len(dataset.groups),
                "variants_per_group": sorted({len(rows) for rows in dataset.groups.values()}),
                "categories": sorted({row.category for row in dataset.complaints}),
            },
            "pairs": {
                "path": _display_path(pairs_path),
                "sha256": _sha256(pairs_path),
                "rows": len(loaded_pairs),
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
                "strategy": (
                    "By issue group. A group's variants appear in exactly one of train, "
                    "validation, or test."
                ),
                "roles": {
                    TRAIN_SPLIT: "Fit the persisted TF-IDF vectorizer only.",
                    VALIDATION_SPLIT: (
                        "Select preprocessing and thresholds only; never fit the final model."
                    ),
                    TEST_SPLIT: "Frozen; scored once after selection.",
                },
                "summary": split_summary,
                "pair_summary": pair_summary,
            },
            "frozen_test": {
                "path": _display_path(freeze_path),
                "frozen_before_tuning": True,
                **fingerprint,
            },
            "reproduction": {
                "command": ("python scripts/build_duplicate_v2_dataset.py"),
                "deterministic": True,
            },
        }

        metadata_path.write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        freeze_path.write_text(
            json.dumps(freeze, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (DuplicateDatasetError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(f"Complaints: {len(dataset.complaints)} in {len(dataset.groups)} groups")
    for split in SPLIT_ORDER:
        summary = split_summary[split]
        split_pair_summary = pair_summary[split]
        print(
            f"{split.title():<10} {summary['complaints']} complaints / "
            f"{summary['groups']} groups / {split_pair_summary['pairs']} pairs "
            f"({split_pair_summary['positive']} positive, "
            f"{split_pair_summary['negative']} negative)"
        )
        print(f"  difficulty: {split_pair_summary['difficulty']}")
    print(f"Complaint SHA-256: {dataset.sha256}")
    print(f"Pair SHA-256: {_sha256(pairs_path)}")
    print(f"Frozen test complaints SHA-256: {fingerprint['complaints_sha256']}")
    print(f"Wrote {complaints_path}")
    print(f"Wrote {pairs_path}")
    print(f"Wrote {metadata_path}")
    print(f"Wrote {freeze_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
