"""Artifact-loading, determinism, and no-refit tests for duplicate detection."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

from pulse_ml.duplicate_model import (
    DuplicateDetector,
    DuplicateModelArtifactError,
    DuplicateModelUnavailableError,
)
from pulse_ml.duplicates import ExistingComplaint, NewComplaint, normalize_complaint_text


def _new_complaint() -> NewComplaint:
    return NewComplaint(
        description="The lights in the main library reading room keep flickering.",
        category="Electrical",
        location="Main Library",
    )


def _existing() -> list[ExistingComplaint]:
    return [
        ExistingComplaint(
            "R1",
            "Lighting above the main library study area is flashing on and off.",
            "Electrical",
            "Main Library",
        ),
        ExistingComplaint(
            "R2",
            "The main library reading room has lights that flicker constantly.",
            "Electrical",
            "Main Library",
        ),
        ExistingComplaint(
            "R3",
            "The printer in the main library is offline.",
            "Network / IT",
            "Main Library",
        ),
    ]


def test_artifact_metadata_and_preprocessing_contract(
    duplicate_detector: DuplicateDetector,
) -> None:
    metadata = duplicate_detector.metadata
    assert duplicate_detector.model_version == "0.2.0"
    assert duplicate_detector.artifact_version == "duplicate-detector-v0.2.0"
    assert metadata["training"]["vectorizer_fit"] == "train split only"
    assert metadata["duplicate_threshold"] == duplicate_detector.duplicate_threshold
    assert metadata["uncertain_threshold"] == duplicate_detector.uncertain_threshold
    assert duplicate_detector.uncertain_threshold < duplicate_detector.duplicate_threshold

    for name, transformer in duplicate_detector.vectorizer.transformer_list:
        assert transformer.preprocessor is normalize_complaint_text
        assert hasattr(transformer, "vocabulary_")
        assert name in {"word", "char"}


def test_reloading_artifact_is_deterministic(duplicate_artifact_dir: Path) -> None:
    first = DuplicateDetector.from_directory(duplicate_artifact_dir)
    second = DuplicateDetector.from_directory(duplicate_artifact_dir)

    first_result = first.detect(
        _new_complaint(),
        _existing(),
        duplicate_threshold=0.20,
        uncertain_threshold=0.10,
    )
    second_result = second.detect(
        _new_complaint(),
        _existing(),
        duplicate_threshold=0.20,
        uncertain_threshold=0.10,
    )

    assert first_result == second_result
    assert [candidate.complaint_id for candidate in first_result.candidates] == [
        "R2",
        "R1",
        "R3",
    ]


def test_detection_never_refits_the_vectorizer(
    duplicate_detector: DuplicateDetector,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def _fail_fit(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("detect() must not fit the duplicate vectorizer")

    monkeypatch.setattr(duplicate_detector.vectorizer, "fit", _fail_fit)

    result = duplicate_detector.detect(
        _new_complaint(),
        _existing(),
        duplicate_threshold=0.20,
        uncertain_threshold=0.10,
    )

    assert result.decision == "match"
    assert result.candidates[0].complaint_id == "R2"


def test_fresh_process_loads_artifact_without_retraining(
    duplicate_artifact_dir: Path,
) -> None:
    script = textwrap.dedent(
        """
        import json
        import sys

        from pulse_ml.duplicate_model import DuplicateDetector
        from pulse_ml.duplicates import ExistingComplaint, NewComplaint

        detector = DuplicateDetector.from_directory(sys.argv[1])
        result = detector.detect(
            NewComplaint(
                "The lights in the main library reading room keep flickering.",
                "Electrical",
                "Main Library",
            ),
            [
                ExistingComplaint(
                    "R1",
                    "Lighting above the main library study area is flashing on and off.",
                    "Electrical",
                    "Main Library",
                ),
                ExistingComplaint(
                    "R2",
                    "The main library reading room has lights that flicker constantly.",
                    "Electrical",
                    "Main Library",
                ),
            ],
            duplicate_threshold=0.20,
            uncertain_threshold=0.10,
        )
        print(
            json.dumps(
                {
                    "model_version": detector.model_version,
                    "decision": result.decision,
                    "candidates": [
                        [
                            candidate.complaint_id,
                            round(candidate.similarity_score, 12),
                            round(candidate.ranking_score, 12),
                        ]
                        for candidate in result.candidates
                    ],
                },
                sort_keys=True,
            )
        )
        """
    )
    command = [sys.executable, "-c", script, str(duplicate_artifact_dir)]
    first = subprocess.run(command, capture_output=True, text=True, check=True)
    second = subprocess.run(command, capture_output=True, text=True, check=True)

    assert first.stdout == second.stdout
    payload = json.loads(first.stdout)
    assert payload["model_version"] == "0.2.0"
    assert payload["decision"] == "match"
    assert payload["candidates"][0][0] == "R2"

    in_process = DuplicateDetector.from_directory(duplicate_artifact_dir).detect(
        _new_complaint(),
        _existing()[:2],
        duplicate_threshold=0.20,
        uncertain_threshold=0.10,
    )
    assert payload["candidates"] == [
        [
            candidate.complaint_id,
            round(candidate.similarity_score, 12),
            round(candidate.ranking_score, 12),
        ]
        for candidate in in_process.candidates
    ]


def test_missing_artifact_is_unavailable(tmp_path: Path) -> None:
    with pytest.raises(DuplicateModelUnavailableError, match="not found"):
        DuplicateDetector.from_directory(tmp_path / "missing")


def test_invalid_metadata_is_rejected(tmp_path: Path) -> None:
    artifact_dir = tmp_path / "invalid-metadata"
    artifact_dir.mkdir()
    (artifact_dir / "model.joblib").write_bytes(b"unused")
    (artifact_dir / "metadata.json").write_text("{not json", encoding="utf-8")

    with pytest.raises(DuplicateModelArtifactError, match="could not read"):
        DuplicateDetector.from_directory(artifact_dir)


def test_tampered_feature_config_is_rejected(
    duplicate_artifact_dir: Path,
    tmp_path: Path,
) -> None:
    copied = tmp_path / "tampered"
    shutil.copytree(duplicate_artifact_dir, copied)
    metadata_path = copied / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["feature_config"]["name"] = "tampered-config"
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

    with pytest.raises(DuplicateModelArtifactError, match="disagree on feature"):
        DuplicateDetector.from_directory(copied)


def test_matching_metadata_alone_cannot_create_a_candidate(
    duplicate_detector: DuplicateDetector,
) -> None:
    result = duplicate_detector.detect(
        NewComplaint("qqqq zzzz", category="Electrical", location="Main Library"),
        [ExistingComplaint("R9", "xxxx yyyy", "Electrical", "Main Library")],
        duplicate_threshold=0.02,
        uncertain_threshold=0.0,
    )

    assert result.decision == "no_match"
    assert result.candidates == ()
