"""Shared fixtures for the isolated ML service tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from pulse_ml.dataset import load_and_validate_dataset, stratified_group_split
from pulse_ml.duplicate_model import DuplicateDetector
from pulse_ml.duplicate_training import DuplicateTrainingConfig, train_duplicate_detector
from pulse_ml.model import CategoryPredictor
from pulse_ml.training import TrainingConfig, train_category_classifier

PROJECT_ROOT = Path(__file__).resolve().parents[1]
STARTER_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints.csv"
PHASE1_1_DATASET = PROJECT_ROOT / "data" / "synthetic_complaints_v2.csv"
PHASE1_1_ADDITIONS = PROJECT_ROOT / "data" / "phase1_1_additions.csv"
DUPLICATE_DATASET = PROJECT_ROOT / "data" / "duplicate_detection_complaints.csv"
DUPLICATE_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_pairs.csv"
DUPLICATE_V2_DATASET = PROJECT_ROOT / "data" / "duplicate_detection_v2_complaints.csv"
DUPLICATE_V2_PAIRS = PROJECT_ROOT / "data" / "duplicate_detection_v2_pairs.csv"
DUPLICATE_V2_FREEZE = PROJECT_ROOT / "data" / "duplicate_detection_v2_test_freeze.json"


@pytest.fixture(scope="session")
def starter_dataset_path() -> Path:
    return STARTER_DATASET


@pytest.fixture(scope="session")
def phase1_1_dataset_path() -> Path:
    return PHASE1_1_DATASET


@pytest.fixture(scope="session")
def phase1_1_additions_path() -> Path:
    return PHASE1_1_ADDITIONS


@pytest.fixture(scope="session")
def duplicate_dataset_path() -> Path:
    return DUPLICATE_DATASET


@pytest.fixture(scope="session")
def duplicate_pairs_path() -> Path:
    return DUPLICATE_PAIRS


@pytest.fixture(scope="session")
def duplicate_v2_dataset_path() -> Path:
    return DUPLICATE_V2_DATASET


@pytest.fixture(scope="session")
def duplicate_v2_pairs_path() -> Path:
    return DUPLICATE_V2_PAIRS


@pytest.fixture(scope="session")
def duplicate_v2_freeze_path() -> Path:
    return DUPLICATE_V2_FREEZE


@pytest.fixture(scope="session")
def phase1_1_holdout_row_numbers() -> tuple[int, ...]:
    baseline = load_and_validate_dataset(STARTER_DATASET)
    dataset = load_and_validate_dataset(PHASE1_1_DATASET)
    baseline_split = stratified_group_split(baseline, test_fraction=0.25, random_state=42)
    index_by_description = {row.description: row.row_number for row in dataset.rows}
    return tuple(
        sorted(
            index_by_description[baseline.rows[index].description]
            for index in baseline_split.test_indices
        )
    )


@pytest.fixture(scope="session")
def trained_model_dir(
    tmp_path_factory: pytest.TempPathFactory,
    starter_dataset_path: Path,
) -> Path:
    output_dir = tmp_path_factory.mktemp("model") / "v0.1.0"
    result = train_category_classifier(
        TrainingConfig(
            dataset_path=starter_dataset_path,
            output_dir=output_dir,
            model_version="0.1.0",
        )
    )
    return result.model_dir


@pytest.fixture(scope="session")
def trained_predictor(trained_model_dir: Path) -> CategoryPredictor:
    return CategoryPredictor.from_directory(trained_model_dir)


@pytest.fixture(scope="session")
def duplicate_artifact_dir(
    tmp_path_factory: pytest.TempPathFactory,
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    duplicate_v2_freeze_path: Path,
) -> Path:
    output_dir = tmp_path_factory.mktemp("duplicate-model") / "v0.2.0"
    result = train_duplicate_detector(
        DuplicateTrainingConfig(
            dataset_path=duplicate_v2_dataset_path,
            pairs_path=duplicate_v2_pairs_path,
            freeze_path=duplicate_v2_freeze_path,
            output_dir=output_dir,
            model_version="0.2.0",
        )
    )
    return result.model_dir


@pytest.fixture(scope="session")
def duplicate_detector(duplicate_artifact_dir: Path) -> DuplicateDetector:
    return DuplicateDetector.from_directory(duplicate_artifact_dir)
