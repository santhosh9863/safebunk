"""Loading and using the versioned duplicate-detector artifact."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.pipeline import FeatureUnion

from pulse_ml.duplicates import (
    DuplicateDetectionResult,
    DuplicateFeatureConfig,
    DuplicateSupportConfig,
    ExistingComplaint,
    NewComplaint,
    normalize_complaint_text,
    rank_with_fitted_vectorizer,
    validate_thresholds,
)


class DuplicateModelError(RuntimeError):
    """Base class for duplicate artifact availability errors."""

    code = "duplicate_model_error"


class DuplicateModelUnavailableError(DuplicateModelError):
    """The artifact files are missing or cannot be read."""

    code = "duplicate_model_unavailable"


class DuplicateModelArtifactError(DuplicateModelError):
    """The artifact exists but does not satisfy the service contract."""

    code = "duplicate_model_invalid"


@dataclass(frozen=True)
class DuplicateDetector:
    vectorizer: FeatureUnion
    feature_config: DuplicateFeatureConfig
    support_config: DuplicateSupportConfig
    metadata: dict[str, Any]
    artifact_version: str
    model_version: str
    duplicate_threshold: float
    uncertain_threshold: float

    @classmethod
    def from_directory(cls, model_dir: str | Path) -> DuplicateDetector:
        directory = Path(model_dir)
        model_path = directory / "model.joblib"
        metadata_path = directory / "metadata.json"

        if not model_path.is_file():
            raise DuplicateModelUnavailableError(
                f"duplicate detector artifact not found: {model_path}"
            )
        if not metadata_path.is_file():
            raise DuplicateModelUnavailableError(
                f"duplicate detector metadata not found: {metadata_path}"
            )

        try:
            metadata_raw = json.loads(metadata_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise DuplicateModelArtifactError(
                f"could not read duplicate detector metadata: {exc}"
            ) from exc
        if not isinstance(metadata_raw, dict):
            raise DuplicateModelArtifactError("duplicate detector metadata must be a JSON object")
        metadata: dict[str, Any] = metadata_raw

        artifact_version = metadata.get("artifact_version")
        if not isinstance(artifact_version, str) or not artifact_version.strip():
            raise DuplicateModelArtifactError(
                "duplicate detector metadata is missing a valid artifact_version"
            )
        model_version = metadata.get("model_version")
        if not isinstance(model_version, str) or not model_version.strip():
            raise DuplicateModelArtifactError(
                "duplicate detector metadata is missing a valid model_version"
            )

        feature_config_raw = metadata.get("feature_config")
        if not isinstance(feature_config_raw, dict):
            raise DuplicateModelArtifactError(
                "duplicate detector metadata is missing feature_config"
            )
        try:
            feature_config = DuplicateFeatureConfig.from_dict(feature_config_raw)
        except ValueError as exc:
            raise DuplicateModelArtifactError(f"invalid feature_config: {exc}") from exc

        support_raw = metadata.get("support_signals")
        if not isinstance(support_raw, dict):
            raise DuplicateModelArtifactError(
                "duplicate detector metadata is missing support_signals"
            )
        try:
            support_config = DuplicateSupportConfig.from_dict(support_raw)
        except ValueError as exc:
            raise DuplicateModelArtifactError(f"invalid support_signals: {exc}") from exc

        duplicate_threshold = metadata.get("duplicate_threshold")
        uncertain_threshold = metadata.get("uncertain_threshold")
        if not isinstance(duplicate_threshold, (int, float)) or not isinstance(
            uncertain_threshold, (int, float)
        ):
            raise DuplicateModelArtifactError("duplicate detector thresholds must be numeric")
        normalized_duplicate = float(duplicate_threshold)
        normalized_uncertain = float(uncertain_threshold)
        if not math.isfinite(normalized_duplicate) or not math.isfinite(normalized_uncertain):
            raise DuplicateModelArtifactError("duplicate detector thresholds must be finite")
        try:
            validate_thresholds(normalized_duplicate, normalized_uncertain)
        except ValueError as exc:
            raise DuplicateModelArtifactError(str(exc)) from exc

        try:
            bundle = joblib.load(model_path)
        except Exception as exc:  # joblib uses several exception types during unpickling
            raise DuplicateModelArtifactError(
                f"could not load duplicate model.joblib: {exc}"
            ) from exc
        if not isinstance(bundle, dict):
            raise DuplicateModelArtifactError(
                "duplicate model.joblib must contain an artifact mapping"
            )

        if bundle.get("artifact_version") != artifact_version:
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on artifact_version"
            )
        if bundle.get("model_version") != model_version:
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on model_version"
            )

        bundle_config_raw = bundle.get("feature_config")
        if not isinstance(bundle_config_raw, dict):
            raise DuplicateModelArtifactError("model.joblib is missing a feature_config mapping")
        try:
            bundle_config = DuplicateFeatureConfig.from_dict(bundle_config_raw)
        except ValueError as exc:
            raise DuplicateModelArtifactError(f"invalid model feature_config: {exc}") from exc
        if bundle_config.to_dict() != feature_config.to_dict():
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on feature configuration"
            )

        bundle_support_raw = bundle.get("support_signals")
        if not isinstance(bundle_support_raw, dict):
            raise DuplicateModelArtifactError("model.joblib is missing a support_signals mapping")
        try:
            bundle_support = DuplicateSupportConfig.from_dict(bundle_support_raw)
        except ValueError as exc:
            raise DuplicateModelArtifactError(f"invalid model support_signals: {exc}") from exc
        if bundle_support != support_config:
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on support signals"
            )

        bundle_duplicate = bundle.get("duplicate_threshold")
        bundle_uncertain = bundle.get("uncertain_threshold")
        if not isinstance(bundle_duplicate, (int, float)) or not isinstance(
            bundle_uncertain, (int, float)
        ):
            raise DuplicateModelArtifactError("model.joblib duplicate thresholds must be numeric")
        if not math.isclose(float(bundle_duplicate), normalized_duplicate, abs_tol=1e-12):
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on duplicate_threshold"
            )
        if not math.isclose(float(bundle_uncertain), normalized_uncertain, abs_tol=1e-12):
            raise DuplicateModelArtifactError(
                "model.joblib and metadata.json disagree on uncertain_threshold"
            )

        vectorizer = bundle.get("vectorizer")
        _validate_vectorizer(vectorizer, feature_config)

        return cls(
            vectorizer=vectorizer,
            feature_config=feature_config,
            support_config=support_config,
            metadata=metadata,
            artifact_version=artifact_version,
            model_version=model_version,
            duplicate_threshold=normalized_duplicate,
            uncertain_threshold=normalized_uncertain,
        )

    def detect(
        self,
        new_complaint: NewComplaint,
        existing_complaints: list[ExistingComplaint] | tuple[ExistingComplaint, ...],
        *,
        duplicate_threshold: float | None = None,
        uncertain_threshold: float | None = None,
        max_candidates: int = 5,
    ) -> DuplicateDetectionResult:
        """Rank candidates using the persisted vectorizer; no fitting occurs."""

        return rank_with_fitted_vectorizer(
            self.vectorizer,
            new_complaint,
            existing_complaints,
            duplicate_threshold=(
                self.duplicate_threshold if duplicate_threshold is None else duplicate_threshold
            ),
            uncertain_threshold=(
                self.uncertain_threshold if uncertain_threshold is None else uncertain_threshold
            ),
            support=self.support_config,
            max_candidates=max_candidates,
        )


def _validate_vectorizer(
    vectorizer: object,
    feature_config: DuplicateFeatureConfig,
) -> None:
    if not isinstance(vectorizer, FeatureUnion):
        raise DuplicateModelArtifactError("model.joblib vectorizer must be a fitted FeatureUnion")

    expected_names = ("word", "char")
    actual_names = tuple(name for name, _ in vectorizer.transformer_list)
    if actual_names != expected_names:
        raise DuplicateModelArtifactError(
            "model.joblib vectorizer must contain word and char transformers"
        )

    for name, transformer in vectorizer.transformer_list:
        if not isinstance(transformer, TfidfVectorizer):
            raise DuplicateModelArtifactError(
                f"model.joblib {name} transformer must be a TfidfVectorizer"
            )
        if not hasattr(transformer, "vocabulary_") or not hasattr(transformer, "idf_"):
            raise DuplicateModelArtifactError(f"model.joblib {name} transformer is not fitted")
        if transformer.preprocessor is not normalize_complaint_text:
            raise DuplicateModelArtifactError(
                f"model.joblib {name} transformer does not use the persisted preprocessing"
            )
        if transformer.sublinear_tf is not feature_config.sublinear_tf:
            raise DuplicateModelArtifactError(
                f"model.joblib {name} transformer has an unexpected sublinear_tf"
            )
        if transformer.lowercase is not feature_config.lowercase:
            raise DuplicateModelArtifactError(
                f"model.joblib {name} transformer has an unexpected lowercase setting"
            )
        if transformer.strip_accents != feature_config.strip_accents:
            raise DuplicateModelArtifactError(
                f"model.joblib {name} transformer has an unexpected strip_accents setting"
            )

        if name == "word":
            if transformer.analyzer != "word":
                raise DuplicateModelArtifactError(
                    "model.joblib word transformer must use the word analyzer"
                )
            if transformer.ngram_range != feature_config.word_ngram_range:
                raise DuplicateModelArtifactError(
                    "model.joblib word transformer has an unexpected ngram_range"
                )
            expected_stop_words = "english" if feature_config.use_stop_words else None
            if transformer.stop_words != expected_stop_words:
                raise DuplicateModelArtifactError(
                    "model.joblib word transformer has an unexpected stop_words setting"
                )
        else:
            if transformer.analyzer != "char_wb":
                raise DuplicateModelArtifactError("model.joblib char transformer must use char_wb")
            if transformer.ngram_range != feature_config.char_ngram_range:
                raise DuplicateModelArtifactError(
                    "model.joblib char transformer has an unexpected ngram_range"
                )
            if transformer.stop_words is not None:
                raise DuplicateModelArtifactError(
                    "model.joblib char transformer must not use stop words"
                )

    try:
        probe = vectorizer.transform(["duplicate detector artifact validation probe"])
        feature_names = vectorizer.get_feature_names_out()
    except Exception as exc:  # fitted third-party objects can fail in several ways
        raise DuplicateModelArtifactError(
            f"model.joblib vectorizer could not transform validation text: {exc}"
        ) from exc
    if probe.shape[0] != 1 or len(feature_names) == 0:
        raise DuplicateModelArtifactError(
            "model.joblib vectorizer returned an unexpected feature shape"
        )
