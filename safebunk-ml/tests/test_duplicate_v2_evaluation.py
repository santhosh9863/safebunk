"""Frozen-test evaluation and diagnostic-labelling tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pulse_ml.duplicate_dataset import DuplicateDatasetError
from pulse_ml.duplicate_model_evaluation import evaluate_frozen_duplicate_detector

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def test_frozen_test_evaluation_labels_diagnostics(
    duplicate_artifact_dir: Path,
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    duplicate_v2_freeze_path: Path,
    tmp_path: Path,
) -> None:
    report = evaluate_frozen_duplicate_detector(
        model_dir=duplicate_artifact_dir,
        dataset_path=duplicate_v2_dataset_path,
        pairs_path=duplicate_v2_pairs_path,
        freeze_path=duplicate_v2_freeze_path,
        output_dir=tmp_path,
    )

    candidate = report["candidate_frozen_test"]
    baseline = report["baseline_test_corpus_fitted_diagnostic"]
    assert candidate["evaluation_mode"] == "persisted_train_fitted_vectorizer"
    assert candidate["hard_negatives"]["pairs"] > 0
    assert baseline["evaluation_mode"] == "phase2_test_corpus_fitted_not_deployed"
    assert "not the deployed inference path" in baseline["note"]
    assert report["production_ready"] is False
    assert report["test_scored_once"] is True
    assert report["training_report"]["test_scored"] is False
    assert (
        report["artifacts"]["freeze"]["pairs_sha256"]
        == json.loads(duplicate_v2_freeze_path.read_text(encoding="utf-8"))["pairs_sha256"]
    )

    comparison = json.loads((tmp_path / "comparison.json").read_text(encoding="utf-8"))
    assert comparison["candidate"]["protocol"].startswith("Phase 2.1")
    assert comparison["baseline"]["protocol"].startswith("Phase 2")
    assert comparison["test_frozen"] is True


def test_changed_test_fingerprint_is_rejected_before_scoring(
    duplicate_artifact_dir: Path,
    duplicate_v2_dataset_path: Path,
    duplicate_v2_pairs_path: Path,
    tmp_path: Path,
) -> None:
    freeze = json.loads(
        (PROJECT_ROOT / "data" / "duplicate_detection_v2_test_freeze.json").read_text(
            encoding="utf-8"
        )
    )
    freeze["pairs_sha256"] = "0" * 64
    tampered_freeze = tmp_path / "tampered_freeze.json"
    tampered_freeze.write_text(json.dumps(freeze), encoding="utf-8")

    with pytest.raises(DuplicateDatasetError, match="frozen test"):
        evaluate_frozen_duplicate_detector(
            model_dir=duplicate_artifact_dir,
            dataset_path=duplicate_v2_dataset_path,
            pairs_path=duplicate_v2_pairs_path,
            freeze_path=tampered_freeze,
            output_dir=tmp_path,
        )
