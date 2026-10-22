"""Loading and using the versioned category-classifier artifact."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import joblib
import numpy as np

from pulse_ml.categories import CATEGORY_SET, SUPPORTED_CATEGORIES


class ModelError(RuntimeError):
    """Base class for operator-facing model availability errors."""

    code = "model_error"


class ModelUnavailableError(ModelError):
    """The artifact files are missing or cannot be read."""

    code = "model_unavailable"


class ModelArtifactError(ModelError):
    """The artifact exists but does not satisfy the service contract."""

    code = "model_invalid"


@dataclass(frozen=True)
class Prediction:
    category: str
    confidence: float
    model_version: str
    manual_review_recommended: bool
    decision: Literal["predict", "abstain"]
    threshold: float


@dataclass(frozen=True)
class CategoryPredictor:
    pipeline: Any
    metadata: dict[str, Any]

    @property
    def model_version(self) -> str:
        return str(self.metadata["model_version"])

    @property
    def threshold(self) -> float:
        return float(self.metadata["confidence_threshold"])

    @property
    def categories(self) -> tuple[str, ...]:
        values = self.metadata["categories"]
        return tuple(str(value) for value in values)

    @classmethod
    def from_directory(cls, model_dir: str | Path) -> CategoryPredictor:
        directory = Path(model_dir)
        model_path = directory / "model.joblib"
        metadata_path = directory / "metadata.json"

        if not model_path.is_file():
            raise ModelUnavailableError(f"model artifact not found: {model_path}")
        if not metadata_path.is_file():
            raise ModelUnavailableError(f"model metadata not found: {metadata_path}")

        try:
            metadata_raw = json.loads(metadata_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ModelArtifactError(f"could not read model metadata: {exc}") from exc

        if not isinstance(metadata_raw, dict):
            raise ModelArtifactError("model metadata must be a JSON object")

        metadata: dict[str, Any] = metadata_raw
        model_version = metadata.get("model_version")
        if not isinstance(model_version, str) or not model_version.strip():
            raise ModelArtifactError("model metadata is missing a valid model_version")

        categories = metadata.get("categories")
        if not isinstance(categories, list) or not all(
            isinstance(value, str) for value in categories
        ):
            raise ModelArtifactError("model metadata is missing a valid categories list")
        category_set = set(categories)
        unknown = sorted(category_set - CATEGORY_SET)
        missing = sorted(CATEGORY_SET - category_set)
        if unknown:
            raise ModelArtifactError(f"model metadata contains unknown categories: {unknown}")
        if missing:
            raise ModelArtifactError(f"model metadata is missing categories: {missing}")
        if len(categories) != len(SUPPORTED_CATEGORIES):
            raise ModelArtifactError("model metadata categories contain duplicates")

        threshold = metadata.get("confidence_threshold")
        if not isinstance(threshold, (int, float)) or not 0.0 <= float(threshold) <= 1.0:
            raise ModelArtifactError(
                "model metadata confidence_threshold must be a number between 0 and 1"
            )

        try:
            pipeline = joblib.load(model_path)
        except Exception as exc:  # joblib uses several exception types during unpickling
            raise ModelArtifactError(f"could not load model.joblib: {exc}") from exc

        if not hasattr(pipeline, "predict_proba") or not hasattr(pipeline, "classes_"):
            raise ModelArtifactError(
                "model.joblib must contain a fitted classifier with predict_proba and classes_"
            )

        classes = {str(value) for value in pipeline.classes_}
        if classes != CATEGORY_SET:
            raise ModelArtifactError(
                "fitted model classes do not match the supported category labels"
            )

        return cls(pipeline=pipeline, metadata=metadata)

    def predict(self, description: str) -> Prediction:
        text = description.strip()
        if not text:
            raise ValueError("description must not be empty")

        probabilities = np.asarray(self.pipeline.predict_proba([text])[0], dtype=float)
        classes = [str(value) for value in self.pipeline.classes_]
        if len(probabilities) != len(classes):
            raise ModelArtifactError("model returned probabilities with an unexpected shape")

        best_index = int(np.argmax(probabilities))
        category = classes[best_index]
        if category not in CATEGORY_SET:
            raise ModelArtifactError(f"model predicted an unknown category: {category!r}")

        confidence = float(probabilities[best_index])
        confidence = min(1.0, max(0.0, confidence))
        manual_review = confidence < self.threshold

        return Prediction(
            category=category,
            confidence=confidence,
            model_version=self.model_version,
            manual_review_recommended=manual_review,
            decision="abstain" if manual_review else "predict",
            threshold=self.threshold,
        )
