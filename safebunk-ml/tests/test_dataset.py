"""Dataset validation, provenance, and leakage-guard tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.dataset import (
    Dataset,
    DatasetRow,
    DatasetValidationError,
    InsufficientDataError,
    fixed_holdout_split,
    load_and_validate_dataset,
    near_duplicate_groups,
    split_from_metadata,
    stratified_group_split,
)


def _write_csv(path: Path, content: str) -> Path:
    path.write_text(content, encoding="utf-8")
    return path


def test_starter_dataset_is_valid_balanced_and_marked_synthetic(
    starter_dataset_path: Path,
) -> None:
    dataset = load_and_validate_dataset(starter_dataset_path)

    assert dataset.size == 192
    assert set(dataset.category_counts) == set(SUPPORTED_CATEGORIES)
    assert set(dataset.category_counts.values()) == {24}
    assert len(dataset.sha256) == 64

    sidecar = json.loads(
        starter_dataset_path.with_suffix(".metadata.json").read_text(encoding="utf-8")
    )
    assert sidecar["synthetic"] is True
    assert sidecar["human_verified"] is False
    assert "not real campus complaints" in sidecar["provenance"].lower()
    assert sidecar["categories"] == list(SUPPORTED_CATEGORIES)


def test_validation_reports_missing_unknown_and_duplicate_rows(tmp_path: Path) -> None:
    path = _write_csv(
        tmp_path / "invalid.csv",
        "description,category\n"
        ",Plumbing\n"
        "Water leak under the sink,Unknown\n"
        "Water leak under the sink,Plumbing\n"
        "Water leak under the sink,Plumbing\n",
    )

    with pytest.raises(DatasetValidationError) as raised:
        load_and_validate_dataset(path)

    message = str(raised.value)
    assert "missing description" in message
    assert "unknown category" in message
    assert "duplicate description" in message


def test_validation_rejects_malformed_headers_and_records(tmp_path: Path) -> None:
    bad_header = _write_csv(
        tmp_path / "bad_header.csv",
        "description,label\nThe tap is running,Plumbing\n",
    )
    with pytest.raises(DatasetValidationError, match="header must be exactly"):
        load_and_validate_dataset(bad_header)

    bad_row = _write_csv(
        tmp_path / "bad_row.csv",
        "description,category\nThe tap is running,Plumbing,extra\n",
    )
    with pytest.raises(DatasetValidationError, match="expected 2 fields"):
        load_and_validate_dataset(bad_row)


def test_validation_rejects_missing_categories_and_short_descriptions(tmp_path: Path) -> None:
    path = _write_csv(
        tmp_path / "partial.csv",
        "description,category\nLeaking tap in the washroom,Plumbing\n"
        "Flickering tube light in the lab,Electrical\n",
    )
    with pytest.raises(DatasetValidationError) as raised:
        load_and_validate_dataset(path)
    assert "missing categories" in str(raised.value)

    short = _write_csv(
        tmp_path / "short.csv",
        "description,category\nLeak,Plumbing\n",
    )
    with pytest.raises(DatasetValidationError, match="shorter than"):
        load_and_validate_dataset(short)


def test_near_duplicate_descriptions_share_a_group() -> None:
    rows = (
        DatasetRow(
            row_number=2,
            description="Water is leaking from the pipe under the sink in the staff room.",
            category="Plumbing",
        ),
        DatasetRow(
            row_number=3,
            description="Water is leaking from the pipe under the sink in the staff room today.",
            category="Plumbing",
        ),
    )

    groups = near_duplicate_groups(rows)

    assert groups[0] == groups[1]


def test_split_is_stratified_and_keeps_groups_whole(starter_dataset_path: Path) -> None:
    dataset = load_and_validate_dataset(starter_dataset_path)
    split = stratified_group_split(dataset, test_fraction=0.25, random_state=42)

    assert len(split.train_indices) == 144
    assert len(split.test_indices) == 48
    assert len(set(split.train_indices) & set(split.test_indices)) == 0
    assert {dataset.rows[index].category for index in split.test_indices} == set(
        SUPPORTED_CATEGORIES
    )

    test_groups = {split.groups[index] for index in split.test_indices}
    for group in set(split.groups):
        group_indices = {index for index, value in enumerate(split.groups) if value == group}
        assert group_indices <= set(split.train_indices) or group_indices <= set(split.test_indices)
    assert test_groups


def test_split_rejects_dataset_without_independent_classes() -> None:
    rows = (
        DatasetRow(2, "Water is leaking under the sink in the staff room.", "Plumbing"),
        DatasetRow(3, "A pipe is blocked near the washroom entrance.", "Plumbing"),
    )
    dataset = Dataset(
        path=Path("tiny.csv"),
        sha256="0" * 64,
        rows=rows,
        category_counts={category: 0 for category in SUPPORTED_CATEGORIES} | {"Plumbing": 2},
    )

    with pytest.raises(InsufficientDataError):
        stratified_group_split(dataset)


def test_optional_source_column_marks_rows_and_requires_a_value(tmp_path: Path) -> None:
    path = _write_csv(
        tmp_path / "sourced.csv",
        "description,category,source\n"
        "Leaking tap in the washroom,Plumbing,phase1_synthetic\n"
        "Blocked drain beside the washroom,Plumbing,phase1_1_synthetic\n"
        "Flickering tube light in the lab,Electrical,phase1_synthetic\n"
        "Wall socket near the projector,Electrical,phase1_1_synthetic\n",
    )

    dataset = load_and_validate_dataset(path, require_all_categories=False)

    assert dataset.source_counts == {
        "phase1_synthetic": 2,
        "phase1_1_synthetic": 2,
    }
    assert dataset.rows[0].source == "phase1_synthetic"
    assert dataset.rows[1].source == "phase1_1_synthetic"

    missing_source = _write_csv(
        tmp_path / "missing_source.csv",
        "description,category,source\n"
        "Leaking tap in the washroom,Plumbing,\n"
        "Blocked drain beside the washroom,Plumbing,phase1_synthetic\n"
        "Slow drain in the staff kitchen,Plumbing,phase1_synthetic\n"
        "Flickering tube light in the lab,Electrical,phase1_synthetic\n"
        "Wall socket near the projector,Electrical,phase1_synthetic\n",
    )
    with pytest.raises(DatasetValidationError, match="missing source"):
        load_and_validate_dataset(missing_source, require_all_categories=False)


def test_fixed_holdout_rejects_a_near_duplicate_group_that_crosses_it() -> None:
    rows = (
        DatasetRow(2, "Broken floor tile near the library entrance.", "Infrastructure"),
        DatasetRow(3, "Loose handrail on the main stairwell.", "Infrastructure"),
        DatasetRow(4, "Ceiling fan in the computer lab sparks.", "Electrical"),
        DatasetRow(5, "Wall socket near the projector is loose.", "Electrical"),
        DatasetRow(
            6,
            "Water is leaking from the pipe under the sink in the staff room.",
            "Plumbing",
        ),
        DatasetRow(
            7,
            "Water is leaking from the pipe under the sink in the staff room today.",
            "Plumbing",
        ),
        DatasetRow(8, "Overflowing bin near the cafeteria counter.", "Cleanliness"),
        DatasetRow(9, "Washroom floor is covered with muddy footprints.", "Cleanliness"),
        DatasetRow(10, "Emergency exit path is blocked by boxes.", "Safety"),
        DatasetRow(11, "Broken glass is lying near the playground.", "Safety"),
        DatasetRow(12, "Library printer appears online but jobs time out.", "Network / IT"),
        DatasetRow(13, "Wi-Fi access point in the hostel is not responding.", "Network / IT"),
        DatasetRow(14, "Course registration portal shows the wrong timetable.", "Academic"),
        DatasetRow(15, "Library catalogue does not list reserved books.", "Academic"),
        DatasetRow(16, "Notice board in the lobby needs new posters.", "Other"),
        DatasetRow(17, "Lost and found box is overflowing with items.", "Other"),
    )
    dataset = Dataset(
        path=Path("leaky.csv"),
        sha256="0" * 64,
        rows=rows,
        category_counts={category: 2 for category in SUPPORTED_CATEGORIES},
    )
    holdout = (2, 4, 6, 8, 10, 12, 14, 16)

    with pytest.raises(InsufficientDataError, match="crosses the fixed holdout"):
        fixed_holdout_split(dataset, holdout)


def test_split_from_metadata_recreates_a_fixed_holdout(
    phase1_1_dataset_path: Path,
    phase1_1_holdout_row_numbers: tuple[int, ...],
) -> None:
    dataset = load_and_validate_dataset(phase1_1_dataset_path)
    split = split_from_metadata(
        dataset,
        {
            "split": {
                "holdout_row_numbers": list(phase1_1_holdout_row_numbers),
                "random_state": 42,
            }
        },
    )

    assert split.method == "fixed holdout"
    assert len(split.test_indices) == 48
    assert len(split.train_indices) == 176
