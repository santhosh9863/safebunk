"""Regression tests for the Phase 2.1 grouped train/validation/test benchmark."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

import pytest

from pulse_ml.duplicate_dataset import (
    COMPLAINT_COLUMNS,
    DuplicateDatasetError,
    build_duplicate_pairs,
    load_duplicate_complaints,
    load_duplicate_pairs,
    verify_test_freeze,
    write_duplicate_pairs,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames is not None
        return list(reader.fieldnames), list(reader)


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> Path:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return path


def test_v2_benchmark_has_three_pure_grouped_splits(
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
) -> None:
    dataset = load_duplicate_complaints(
        duplicate_v2_dataset_path,
        required_splits={"train", "validation", "test"},
        min_groups_per_category=3,
    )
    pairs = load_duplicate_pairs(duplicate_v2_pairs_path, dataset)

    assert len(dataset.complaints) == 216
    assert len(dataset.groups) == 72
    assert {len(group) for group in dataset.groups.values()} == {3}
    assert set(dataset.split_complaints) == {"train", "test", "validation"}

    group_splits: dict[str, set[str]] = {}
    for complaint in dataset.complaints:
        group_splits.setdefault(complaint.group_id, set()).add(complaint.split)
    assert all(len(splits) == 1 for splits in group_splits.values())

    for split in ("train", "validation", "test"):
        rows = dataset.split_complaints[split]
        assert len(rows) == 72
        assert len({row.group_id for row in rows}) == 24
        for category in {row.category for row in rows}:
            category_groups = {row.group_id for row in rows if row.category == category}
            assert len(category_groups) == 3

    assert len(pairs) == 3 * 2556
    for split in ("train", "validation", "test"):
        split_pairs = [pair for pair in pairs if pair.split == split]
        assert len(split_pairs) == 2556
        assert sum(pair.label == 1 for pair in split_pairs) == 72
        assert sum(pair.label == 0 for pair in split_pairs) == 2484
        difficulties = Counter(pair.difficulty for pair in split_pairs)
        assert difficulties["hard_negative"] > 0


def test_v2_metadata_and_freeze_sidecars_are_consistent(
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    duplicate_v2_freeze_path: Path,
) -> None:
    dataset = load_duplicate_complaints(
        duplicate_v2_dataset_path,
        required_splits={"train", "validation", "test"},
        min_groups_per_category=3,
    )
    pairs = load_duplicate_pairs(duplicate_v2_pairs_path, dataset)
    freeze = json.loads(duplicate_v2_freeze_path.read_text(encoding="utf-8"))
    metadata = json.loads(
        (duplicate_v2_dataset_path.parent / "duplicate_detection_v2.metadata.json").read_text(
            encoding="utf-8"
        )
    )

    verify_test_freeze(dataset, pairs, freeze)
    assert freeze["frozen_before_tuning"] is True
    assert freeze["split"] == "test"
    assert freeze["complaint_count"] == 72
    assert freeze["pair_count"] == 2556
    assert metadata["synthetic"] is True
    assert metadata["human_verified"] is False
    assert metadata["source"]["phase2_complaints"]["sha256"] == (
        "10450a547d3e1d491eacd02e5a01a2774f666e46b830b05809a5e2f9791114bc"
    )
    assert metadata["complaints"]["sha256"] == dataset.sha256
    assert metadata["frozen_test"]["complaints_sha256"] == freeze["complaints_sha256"]
    assert metadata["frozen_test"]["pairs_sha256"] == freeze["pairs_sha256"]


def test_tampered_frozen_test_is_rejected(
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    duplicate_v2_freeze_path: Path,
    tmp_path: Path,
) -> None:
    fieldnames, rows = _read_csv(duplicate_v2_dataset_path)
    assert fieldnames == list(COMPLAINT_COLUMNS)
    test_row = next(row for row in rows if row["split"] == "test")
    test_row["description"] = f"{test_row['description']} Tampered after freeze."
    tampered_path = _write_csv(tmp_path / "tampered.csv", fieldnames, rows)
    dataset = load_duplicate_complaints(
        tampered_path,
        required_splits={"train", "validation", "test"},
        min_groups_per_category=3,
    )
    pair_path = tmp_path / "tampered_pairs.csv"
    write_duplicate_pairs(build_duplicate_pairs(dataset), pair_path)
    pairs = load_duplicate_pairs(pair_path, dataset)
    freeze = json.loads(duplicate_v2_freeze_path.read_text(encoding="utf-8"))

    with pytest.raises(DuplicateDatasetError, match="frozen test"):
        verify_test_freeze(dataset, pairs, freeze)


def test_v2_build_is_reproducible(
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    tmp_path: Path,
) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(PROJECT_ROOT / "scripts" / "build_duplicate_v2_dataset.py"),
            "--output-dir",
            str(tmp_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "duplicate_detection_v2_complaints.csv").read_bytes() == (
        duplicate_v2_dataset_path.read_bytes()
    )
    assert (tmp_path / "duplicate_detection_v2_pairs.csv").read_bytes() == (
        duplicate_v2_pairs_path.read_bytes()
    )
