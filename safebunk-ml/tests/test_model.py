"""Artifact-loading and prediction-decision tests."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import numpy as np
import pytest

from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.model import (
    CategoryPredictor,
    ModelArtifactError,
    ModelUnavailableError,
)


class _FakePipeline:
    def __init__(self, top_score: float) -> None:
        self.classes_ = np.asarray(SUPPORTED_CATEGORIES, dtype=object)
        remaining = (1.0 - top_score) / (len(SUPPORTED_CATEGORIES) - 1)
        self._probabilities = np.asarray(
            [remaining if index != 2 else top_score for index in range(len(SUPPORTED_CATEGORIES))],
            dtype=float,
        )

    def predict_proba(self, _texts: list[str]) -> np.ndarray:
        return self._probabilities.reshape(1, -1)


def _metadata(threshold: float) -> dict[str, Any]:
    return {
        "model_version": "test-0.0.0",
        "categories": list(SUPPORTED_CATEGORIES),
        "confidence_threshold": threshold,
    }


def test_missing_artifact_is_reported() -> None:
    with pytest.raises(ModelUnavailableError, match="model artifact not found"):
        CategoryPredictor.from_directory("does-not-exist")


def test_unknown_category_metadata_is_rejected(tmp_path: Path) -> None:
    (tmp_path / "metadata.json").write_text(
        json.dumps(
            {
                "model_version": "bad",
                "categories": [*SUPPORTED_CATEGORIES, "Rocket Science"],
                "confidence_threshold": 0.55,
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "model.joblib").write_bytes(b"not a model")

    with pytest.raises(ModelArtifactError, match="unknown categories"):
        CategoryPredictor.from_directory(tmp_path)


def test_corrupt_model_binary_is_rejected(trained_model_dir: Path, tmp_path: Path) -> None:
    corrupt_dir = tmp_path / "corrupt"
    shutil.copytree(trained_model_dir, corrupt_dir)
    (corrupt_dir / "model.joblib").write_bytes(b"not a valid joblib artifact")

    with pytest.raises(ModelArtifactError, match=r"could not load model\.joblib"):
        CategoryPredictor.from_directory(corrupt_dir)


def test_low_confidence_abstains() -> None:
    predictor = CategoryPredictor(
        pipeline=_FakePipeline(top_score=0.40),
        metadata=_metadata(threshold=0.55),
    )

    prediction = predictor.predict("A water pipe is leaking in the washroom.")

    assert prediction.category == "Plumbing"
    assert prediction.confidence == pytest.approx(0.40)
    assert prediction.manual_review_recommended is True
    assert prediction.decision == "abstain"
    assert prediction.threshold == 0.55


def test_high_confidence_predicts() -> None:
    predictor = CategoryPredictor(
        pipeline=_FakePipeline(top_score=0.90),
        metadata=_metadata(threshold=0.55),
    )

    prediction = predictor.predict("A water pipe is leaking in the washroom.")

    assert prediction.category == "Plumbing"
    assert prediction.confidence == pytest.approx(0.90)
    assert prediction.manual_review_recommended is False
    assert prediction.decision == "predict"


def test_empty_text_is_rejected_at_service_boundary() -> None:
    predictor = CategoryPredictor(
        pipeline=_FakePipeline(top_score=0.90),
        metadata=_metadata(threshold=0.55),
    )

    with pytest.raises(ValueError, match="must not be empty"):
        predictor.predict("   ")
