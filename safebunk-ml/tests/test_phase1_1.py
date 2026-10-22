"""Phase 1.1 dataset provenance, ambiguity, and frozen-holdout regression tests."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from pulse_ml.dataset import (
    fixed_holdout_split,
    load_and_validate_dataset,
    stratified_group_split,
)

NEW_SOURCE = "phase1_1_synthetic"


def test_phase1_1_dataset_marks_additions_and_preserves_provenance(
    phase1_1_dataset_path: Path,
) -> None:
    dataset = load_and_validate_dataset(phase1_1_dataset_path)

    assert dataset.size == 224
    assert dataset.source_counts == {
        "phase1_synthetic": 192,
        NEW_SOURCE: 32,
    }
    assert dataset.category_counts == {
        "Infrastructure": 24,
        "Electrical": 40,
        "Plumbing": 24,
        "Cleanliness": 24,
        "Safety": 24,
        "Network / IT": 40,
        "Academic": 24,
        "Other": 24,
    }

    additions = [row for row in dataset.rows if row.source == NEW_SOURCE]
    assert len(additions) == 32
    assert Counter(row.category for row in additions) == {
        "Electrical": 16,
        "Network / IT": 16,
    }

    sidecar = json.loads(
        phase1_1_dataset_path.with_suffix(".metadata.json").read_text(encoding="utf-8")
    )
    assert sidecar["synthetic"] is True
    assert sidecar["human_verified"] is False
    assert (
        sidecar["parent_dataset"]["sha256"]
        == "ae78cd491da998b60cf66d27cf2b309bcd6706619ff1a6dedf6d4df869b580d4"
    )
    assert sidecar["row_sources"] == {
        "phase1_synthetic": 192,
        NEW_SOURCE: 32,
    }
    assert sidecar["phase1_1_additions"]["synthetic"] is True
    assert sidecar["phase1_1_additions"]["derived_from_test_rows"] is False


def test_phase1_1_additions_cover_distinct_ambiguous_examples(
    phase1_1_additions_path: Path,
    starter_dataset_path: Path,
) -> None:
    additions = load_and_validate_dataset(
        phase1_1_additions_path,
        require_all_categories=False,
    )
    baseline = load_and_validate_dataset(starter_dataset_path)

    assert additions.size == 32
    assert additions.source_counts == {NEW_SOURCE: 32}
    assert len({row.description for row in additions.rows}) == 32
    assert not (
        {row.description for row in additions.rows} & {row.description for row in baseline.rows}
    )

    electrical = [row for row in additions.rows if row.category == "Electrical"]
    network = [row for row in additions.rows if row.category == "Network / IT"]
    assert len(electrical) == 16
    assert len(network) == 16

    electrical_terms = ("power", "socket", "breaker", "fan", "light", "battery", "panel")
    network_terms = ("network", "internet", "wi-fi", "server", "portal", "firewall", "lan")
    assert (
        sum(any(term in row.description.lower() for term in electrical_terms) for row in electrical)
        >= 12
    )
    assert (
        sum(any(term in row.description.lower() for term in network_terms) for row in network) >= 12
    )


def test_phase1_1_frozen_holdout_is_unchanged_and_group_safe(
    phase1_1_dataset_path: Path,
    phase1_1_holdout_row_numbers: tuple[int, ...],
    starter_dataset_path: Path,
) -> None:
    baseline = load_and_validate_dataset(starter_dataset_path)
    dataset = load_and_validate_dataset(phase1_1_dataset_path)
    baseline_split = stratified_group_split(baseline, test_fraction=0.25, random_state=42)

    assert len(phase1_1_holdout_row_numbers) == 48
    assert len(set(phase1_1_holdout_row_numbers)) == 48
    holdout_numbers = set(phase1_1_holdout_row_numbers)
    holdout_rows = [row for row in dataset.rows if row.row_number in holdout_numbers]
    assert {row.description for row in holdout_rows} == {
        baseline.rows[index].description for index in baseline_split.test_indices
    }
    assert {row.source for row in holdout_rows} == {"phase1_synthetic"}

    split = fixed_holdout_split(dataset, phase1_1_holdout_row_numbers)
    assert split.method == "fixed holdout"
    assert len(split.train_indices) == 176
    assert len(split.test_indices) == 48

    test_groups = {split.groups[index] for index in split.test_indices}
    for group in set(split.groups):
        group_indices = {index for index, value in enumerate(split.groups) if value == group}
        assert group_indices <= set(split.train_indices) or group_indices <= set(split.test_indices)
    assert test_groups
