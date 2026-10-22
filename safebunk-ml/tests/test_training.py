"""Training, artifact, and reproducibility tests."""

from __future__ import annotations

import json
from pathlib import Path

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.model import CategoryPredictor
from pulse_ml.training import TrainingConfig, calculate_metrics, train_category_classifier


def test_training_writes_versioned_artifact_with_evaluation(
    tmp_path: Path,
    starter_dataset_path: Path,
) -> None:
    output_dir = tmp_path / "artifacts" / "category-classifier" / "v0.1.0"
    result = train_category_classifier(
        TrainingConfig(
            dataset_path=starter_dataset_path,
            output_dir=output_dir,
            model_version="0.1.0",
            random_state=42,
        )
    )

    assert result.model_path.is_file()
    assert result.metadata_path.is_file()
    assert result.metrics_path.is_file()
    assert result.metrics["support"] == len(result.split.test_indices)
    assert result.metrics["macro_f1"] == result.metadata["evaluation"]["macro_f1"]
    assert result.metrics["macro_f1"] >= 0.0
    assert result.metrics["macro_f1"] <= 1.0
    assert len(result.metrics["confusion_matrix"]) == len(SUPPORTED_CATEGORIES)
    assert all(len(row) == len(SUPPORTED_CATEGORIES) for row in result.metrics["confusion_matrix"])
    assert set(result.metrics["per_class"]) == set(SUPPORTED_CATEGORIES)

    metadata = json.loads(result.metadata_path.read_text(encoding="utf-8"))
    assert metadata["model_version"] == "0.1.0"
    assert metadata["categories"] == list(SUPPORTED_CATEGORIES)
    assert metadata["environment"]["python"]
    assert metadata["environment"]["scikit_learn"] != "unknown"
    assert metadata["dataset"]["metadata"]["synthetic"] is True
    assert metadata["dataset"]["rows"] == 192
    assert metadata["dataset"]["sha256"] == result.dataset.sha256
    assert metadata["split"]["train_rows"] == 144
    assert metadata["split"]["test_rows"] == 48
    assert "not a calibrated" in metadata["confidence_note"]

    predictor = CategoryPredictor.from_directory(output_dir)
    prediction = predictor.predict("A water pipe is leaking under the sink in the staff room.")
    assert prediction.category in SUPPORTED_CATEGORIES
    assert 0.0 <= prediction.confidence <= 1.0
    assert prediction.model_version == "0.1.0"
    assert prediction.decision in {"predict", "abstain"}


def test_training_is_reproducible(
    tmp_path: Path,
    starter_dataset_path: Path,
) -> None:
    first = train_category_classifier(
        TrainingConfig(
            dataset_path=starter_dataset_path,
            output_dir=tmp_path / "first" / "v0.1.0",
            random_state=7,
        )
    )
    second = train_category_classifier(
        TrainingConfig(
            dataset_path=starter_dataset_path,
            output_dir=tmp_path / "second" / "v0.1.0",
            random_state=7,
        )
    )

    assert first.metrics == second.metrics
    assert first.split.train_indices == second.split.train_indices
    assert first.split.test_indices == second.split.test_indices
    assert first.metadata["dataset"]["sha256"] == second.metadata["dataset"]["sha256"]


def test_fixed_holdout_training_records_the_frozen_protocol(
    tmp_path: Path,
    phase1_1_dataset_path: Path,
    phase1_1_holdout_row_numbers: tuple[int, ...],
) -> None:
    output_dir = tmp_path / "artifacts" / "category-classifier" / "v0.2.0"
    result = train_category_classifier(
        TrainingConfig(
            dataset_path=phase1_1_dataset_path,
            output_dir=output_dir,
            model_version="0.2.0",
            holdout_row_numbers=phase1_1_holdout_row_numbers,
            holdout_description="Frozen Phase 1 test rows",
        )
    )

    metadata = json.loads(result.metadata_path.read_text(encoding="utf-8"))
    assert result.dataset.size == 224
    assert result.metrics["support"] == 48
    assert len(result.split.train_indices) == 176
    assert len(result.split.test_indices) == 48
    assert result.split.method == "fixed holdout"
    assert metadata["evaluation_protocol"] == "fixed_holdout"
    assert metadata["split"]["method"] == "fixed holdout"
    assert metadata["split"]["holdout_row_numbers"] == list(phase1_1_holdout_row_numbers)
    assert metadata["split"]["holdout_description"] == "Frozen Phase 1 test rows"
    assert metadata["dataset"]["rows"] == 224


def test_metrics_reject_empty_test_set() -> None:
    try:
        calculate_metrics([], [])
    except ValueError as exc:
        assert "empty test set" in str(exc)
    else:
        raise AssertionError("calculate_metrics should reject an empty test set")
