"""Regression tests for the grouped synthetic duplicate-detection benchmark."""

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
    PAIR_COLUMNS,
    DuplicateDatasetError,
    build_duplicate_pairs,
    load_duplicate_complaints,
    load_duplicate_pairs,
    write_duplicate_pairs,
)


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


def test_benchmark_is_grouped_balanced_and_synthetic(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
) -> None:
    dataset = load_duplicate_complaints(duplicate_dataset_path)
    pairs = load_duplicate_pairs(duplicate_pairs_path, dataset)

    assert len(dataset.complaints) == 96
    assert len(dataset.groups) == 32
    assert {len(group) for group in dataset.groups.values()} == {3}

    train_groups = {
        complaint.group_id for complaint in dataset.complaints if complaint.split == "train"
    }
    test_groups = {
        complaint.group_id for complaint in dataset.complaints if complaint.split == "test"
    }
    assert len(train_groups) == 16
    assert len(test_groups) == 16
    assert train_groups.isdisjoint(test_groups)

    for group in dataset.groups.values():
        assert {row.split for row in group} == {group[0].split}
        assert {row.category for row in group} == {group[0].category}
        assert {row.location for row in group} == {group[0].location}

    assert len(pairs) == 2256
    for split in ("train", "test"):
        split_pairs = [pair for pair in pairs if pair.split == split]
        assert len(split_pairs) == 1128
        assert sum(pair.label == 1 for pair in split_pairs) == 48
        assert sum(pair.label == 0 for pair in split_pairs) == 1080
        assert all(
            (pair.label == 1)
            == (
                next(
                    row.group_id
                    for row in dataset.complaints
                    if row.complaint_id == pair.left_complaint_id
                )
                == next(
                    row.group_id
                    for row in dataset.complaints
                    if row.complaint_id == pair.right_complaint_id
                )
            )
            for pair in split_pairs
        )
        difficulties = Counter(pair.difficulty for pair in split_pairs)
        assert difficulties["hard_negative"] > 0

    sidecar = json.loads(
        (duplicate_dataset_path.parent / "duplicate_detection.metadata.json").read_text(
            encoding="utf-8"
        )
    )
    assert sidecar["synthetic"] is True
    assert sidecar["human_verified"] is False
    assert sidecar["source"]["rows"] == 96
    assert sidecar["pairs"]["rows"] == 2256
    assert sidecar["source"]["sha256"] == dataset.sha256


def test_pair_file_is_complete_and_reproducible(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
    tmp_path: Path,
) -> None:
    dataset = load_duplicate_complaints(duplicate_dataset_path)
    loaded = load_duplicate_pairs(duplicate_pairs_path, dataset)
    rebuilt = build_duplicate_pairs(dataset)

    assert rebuilt == loaded

    output = tmp_path / "pairs.csv"
    write_duplicate_pairs(rebuilt, output)
    assert output.read_bytes() == duplicate_pairs_path.read_bytes()


def test_group_crossing_split_is_rejected(
    duplicate_dataset_path: Path,
    tmp_path: Path,
) -> None:
    fieldnames, rows = _read_csv(duplicate_dataset_path)
    assert fieldnames == list(COMPLAINT_COLUMNS)
    next(row for row in rows if row["complaint_id"] == "C007")["split"] = "train"
    path = _write_csv(tmp_path / "crossing.csv", fieldnames, rows)

    with pytest.raises(DuplicateDatasetError, match="must not cross"):
        load_duplicate_complaints(path)


def test_duplicate_description_is_rejected(
    duplicate_dataset_path: Path,
    tmp_path: Path,
) -> None:
    fieldnames, rows = _read_csv(duplicate_dataset_path)
    source = next(row for row in rows if row["complaint_id"] == "C007")
    target = next(row for row in rows if row["complaint_id"] == "C008")
    target["description"] = source["description"]
    path = _write_csv(tmp_path / "duplicate.csv", fieldnames, rows)

    with pytest.raises(DuplicateDatasetError, match="duplicate description"):
        load_duplicate_complaints(path)


def test_extra_complaint_field_is_rejected(
    duplicate_dataset_path: Path,
    tmp_path: Path,
) -> None:
    content = duplicate_dataset_path.read_text(encoding="utf-8")
    path = tmp_path / "extra_field.csv"
    path.write_text(content.replace("\nC002,", "\nC002,extra,", 1), encoding="utf-8")

    with pytest.raises(DuplicateDatasetError, match="unexpected extra field"):
        load_duplicate_complaints(path)


def test_unknown_category_is_rejected(
    duplicate_dataset_path: Path,
    tmp_path: Path,
) -> None:
    fieldnames, rows = _read_csv(duplicate_dataset_path)
    next(row for row in rows if row["complaint_id"] == "C007")["category"] = "Rocket Science"
    path = _write_csv(tmp_path / "unknown.csv", fieldnames, rows)

    with pytest.raises(DuplicateDatasetError, match="unknown category"):
        load_duplicate_complaints(path)


def test_tampered_pair_label_is_rejected(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
    tmp_path: Path,
) -> None:
    dataset = load_duplicate_complaints(duplicate_dataset_path)
    fieldnames, rows = _read_csv(duplicate_pairs_path)
    assert fieldnames == list(PAIR_COLUMNS)
    positive = next(row for row in rows if row["label"] == "1")
    positive["label"] = "0"
    path = _write_csv(tmp_path / "tampered.csv", fieldnames, rows)

    with pytest.raises(DuplicateDatasetError, match="label disagrees"):
        load_duplicate_pairs(path, dataset)


def test_missing_pair_is_rejected(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
    tmp_path: Path,
) -> None:
    dataset = load_duplicate_complaints(duplicate_dataset_path)
    fieldnames, rows = _read_csv(duplicate_pairs_path)
    path = _write_csv(tmp_path / "incomplete.csv", fieldnames, rows[:-1])

    with pytest.raises(DuplicateDatasetError, match="incomplete"):
        load_duplicate_pairs(path, dataset)


def test_phase2_builder_supports_outputs_outside_the_project(
    duplicate_dataset_path: Path,
    duplicate_pairs_path: Path,
    tmp_path: Path,
) -> None:
    project_root = duplicate_dataset_path.parents[1]
    pairs_path = tmp_path / "pairs.csv"
    metadata_path = tmp_path / "metadata.json"

    result = subprocess.run(
        [
            sys.executable,
            str(project_root / "scripts" / "build_duplicate_dataset.py"),
            "--pairs-output",
            str(pairs_path),
            "--metadata-output",
            str(metadata_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert pairs_path.read_bytes() == duplicate_pairs_path.read_bytes()
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    assert metadata["pairs"]["path"] == str(pairs_path)
    assert metadata["pairs"]["sha256"] == (
        "eddeb6a1562f557e8e5deab8ab6a97607e4931adc87f007dfb92e6b6a95fe15a"
    )
