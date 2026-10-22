"""FastAPI contract tests, including dependency-injected low confidence."""

from __future__ import annotations

import json
from pathlib import Path

from fastapi.testclient import TestClient

from pulse_ml.api import create_app
from pulse_ml.categories import SUPPORTED_CATEGORIES
from pulse_ml.model import Prediction


class _FakePredictor:
    model_version = "test-0.0.0"

    def __init__(self, *, manual_review: bool = False) -> None:
        self._manual_review = manual_review

    def predict(self, _description: str) -> Prediction:
        return Prediction(
            category="Plumbing",
            confidence=0.35 if self._manual_review else 0.85,
            model_version=self.model_version,
            manual_review_recommended=self._manual_review,
            decision="abstain" if self._manual_review else "predict",
            threshold=0.55,
        )


def test_valid_prediction_contract() -> None:
    client = TestClient(create_app(predictor=_FakePredictor()))

    response = client.post(
        "/predict/category",
        json={"description": "A water pipe is leaking under the sink."},
    )

    assert response.status_code == 200
    body = response.json()
    assert body == {
        "category": "Plumbing",
        "confidence": 0.85,
        "model_version": "test-0.0.0",
        "manual_review_recommended": False,
        "decision": "predict",
        "threshold": 0.55,
    }


def test_low_confidence_returns_abstain() -> None:
    client = TestClient(create_app(predictor=_FakePredictor(manual_review=True)))

    response = client.post(
        "/predict/category",
        json={"description": "Something is wrong near the sink."},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["manual_review_recommended"] is True
    assert body["decision"] == "abstain"


def test_empty_blank_and_oversized_descriptions_are_rejected() -> None:
    client = TestClient(create_app(predictor=_FakePredictor()))

    for payload in (
        {"description": ""},
        {"description": "     "},
        {"description": "x" * 4001},
    ):
        response = client.post("/predict/category", json=payload)
        assert response.status_code == 422, payload


def test_identity_and_role_fields_are_not_accepted() -> None:
    client = TestClient(create_app(predictor=_FakePredictor()))

    response = client.post(
        "/predict/category",
        json={
            "description": "A water pipe is leaking under the sink.",
            "studentId": "S123",
            "role": "STUDENT",
        },
    )

    assert response.status_code == 422


def test_missing_model_is_a_clear_503(tmp_path: Path) -> None:
    client = TestClient(create_app(model_dir=tmp_path / "missing"))

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["status"] == "degraded"
    assert health.json()["model_loaded"] is False

    response = client.post(
        "/predict/category",
        json={"description": "A water pipe is leaking under the sink."},
    )
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "model_unavailable"


def test_invalid_model_metadata_is_a_clear_503(tmp_path: Path) -> None:
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
    (tmp_path / "model.joblib").write_bytes(b"unused")
    client = TestClient(create_app(model_dir=tmp_path))

    response = client.post(
        "/predict/category",
        json={"description": "A water pipe is leaking under the sink."},
    )
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "model_invalid"


def test_real_trained_artifact_is_served(trained_model_dir: Path) -> None:
    client = TestClient(create_app(model_dir=trained_model_dir))

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json() == {
        "status": "ok",
        "model_loaded": True,
        "model_version": "0.1.0",
        "detail": None,
    }

    response = client.post(
        "/predict/category",
        json={"description": "Water is leaking from a pipe under the sink."},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["category"] in SUPPORTED_CATEGORIES
    assert body["model_version"] == "0.1.0"
    assert body["decision"] in {"predict", "abstain"}


def test_internal_token_is_enforced_when_configured() -> None:
    client = TestClient(create_app(predictor=_FakePredictor(), api_token="shared-secret"))
    payload = {"description": "A water pipe is leaking under the sink."}

    missing = client.post("/predict/category", json=payload)
    wrong = client.post(
        "/predict/category",
        json=payload,
        headers={"X-PULSE-ML-Token": "wrong-secret"},
    )
    accepted = client.post(
        "/predict/category",
        json=payload,
        headers={"X-PULSE-ML-Token": "shared-secret"},
    )

    assert missing.status_code == 401
    assert missing.json()["detail"]["code"] == "unauthorized"
    assert wrong.status_code == 401
    assert accepted.status_code == 200
    # Liveness/readiness stays reachable so an operator can inspect the service.
    assert client.get("/health").status_code == 200
