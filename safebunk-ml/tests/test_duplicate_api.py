"""FastAPI contract tests for read-only duplicate suggestions."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from pulse_ml.api import create_app


def _existing() -> list[dict[str, str]]:
    return [
        {
            "complaint_id": "R1",
            "description": "Lighting above the main library study area is flashing on and off.",
            "category": "Electrical",
            "location": "Main Library",
        },
        {
            "complaint_id": "R2",
            "description": "The main library reading room has lights that flicker constantly.",
            "category": "Electrical",
            "location": "Main Library",
        },
        {
            "complaint_id": "R3",
            "description": "The printer in the main library is offline.",
            "category": "Network / IT",
            "location": "Main Library",
        },
        {
            "complaint_id": "R4",
            "description": "The Wi-Fi network in the main library is not working.",
            "category": "Network / IT",
            "location": "Main Library",
        },
        {
            "complaint_id": "R5",
            "description": "The ceiling fan in Computer Lab 1 makes a loud rattling noise.",
            "category": "Electrical",
            "location": "Computer Lab 1",
        },
    ]


def _payload(
    *,
    existing: list[dict[str, str]] | None = None,
    **overrides: Any,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "new_complaint": {
            "description": "The lights in the main library reading room keep flickering.",
            "category": "Electrical",
            "location": "Main Library",
        },
        "existing_complaints": _existing() if existing is None else existing,
        "thresholds": {"duplicate": 0.20, "uncertain": 0.10},
        "max_candidates": 5,
    }
    payload.update(overrides)
    return payload


def _client(artifact_dir: Path) -> TestClient:
    return TestClient(create_app(duplicate_model_dir=artifact_dir))


def test_valid_request_returns_ranked_read_only_suggestions(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)

    response = client.post("/detect/duplicates", json=_payload())

    assert response.status_code == 200
    body = response.json()
    assert body["decision"] == "match"
    assert body["action"] == "suggestion_only"
    assert body["manual_review_recommended"] is True
    assert body["similarity_metric"] == "tfidf_cosine_similarity"
    assert body["ranking_metric"] == "cosine_similarity_with_metadata_support"
    assert body["model_version"] == "0.2.0"
    assert "not a probability" in body["score_note"]
    assert body["existing_complaints_evaluated"] == 5
    assert body["candidates"][0]["complaint_id"] == "R2"
    assert body["candidates"][0]["similarity_score"] > 0.20
    assert body["candidates"][0]["ranking_score"] >= body["candidates"][0]["similarity_score"]
    assert body["candidates"][0]["category_match"] is True
    assert body["candidates"][0]["location_match"] is True
    assert "same category: Electrical" in body["candidates"][0]["reasons"]
    assert "confidence" not in body
    assert "probability" not in body["candidates"][0]

    scores = [candidate["ranking_score"] for candidate in body["candidates"]]
    assert scores == sorted(scores, reverse=True)


def test_empty_existing_collection_is_a_valid_no_match(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)

    response = client.post("/detect/duplicates", json=_payload(existing=[]))

    assert response.status_code == 200
    body = response.json()
    assert body["decision"] == "no_match"
    assert body["candidates"] == []
    assert body["manual_review_recommended"] is False
    assert body["existing_complaints_evaluated"] == 0
    assert "No existing complaints" in body["message"]


def test_default_thresholds_come_from_the_loaded_artifact(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)
    payload = _payload()
    del payload["thresholds"]
    metadata = json.loads((duplicate_artifact_dir / "metadata.json").read_text(encoding="utf-8"))

    response = client.post("/detect/duplicates", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["duplicate_threshold"] == metadata["duplicate_threshold"]
    assert body["uncertain_threshold"] == metadata["uncertain_threshold"]


def test_partial_threshold_override_uses_artifact_for_the_other_band(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)
    metadata = json.loads((duplicate_artifact_dir / "metadata.json").read_text(encoding="utf-8"))
    payload = _payload(thresholds={"duplicate": 0.95})

    response = client.post("/detect/duplicates", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["duplicate_threshold"] == 0.95
    assert body["uncertain_threshold"] == metadata["uncertain_threshold"]


def test_partial_override_must_still_order_against_the_artifact_default(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)

    response = client.post("/detect/duplicates", json=_payload(thresholds={"duplicate": 0.20}))

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "invalid_input"


def test_max_candidates_caps_the_ranked_list(duplicate_artifact_dir: Path) -> None:
    client = _client(duplicate_artifact_dir)

    response = client.post("/detect/duplicates", json=_payload(max_candidates=2))

    assert response.status_code == 200
    body = response.json()
    assert len(body["candidates"]) == 2
    assert body["candidates"][0]["complaint_id"] == "R2"


def test_thresholds_control_match_uncertain_and_no_match(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)

    match = client.post("/detect/duplicates", json=_payload())
    assert match.status_code == 200
    top_score = match.json()["candidates"][0]["ranking_score"]
    assert top_score < 0.98

    uncertain_threshold = max(0.0, round(top_score - 0.01, 3))
    duplicate_threshold = round(top_score + 0.01, 3)
    uncertain = client.post(
        "/detect/duplicates",
        json=_payload(
            thresholds={
                "duplicate": duplicate_threshold,
                "uncertain": uncertain_threshold,
            }
        ),
    )
    no_match = client.post(
        "/detect/duplicates",
        json=_payload(thresholds={"duplicate": 0.99, "uncertain": 0.98}),
    )

    assert match.json()["decision"] == "match"
    assert uncertain.status_code == 200
    assert uncertain.json()["decision"] == "uncertain"
    assert uncertain.json()["manual_review_recommended"] is True
    assert no_match.status_code == 200
    assert no_match.json()["decision"] == "no_match"
    assert no_match.json()["candidates"] == []


def test_optional_metadata_and_missing_category_model_do_not_block_duplicates(
    tmp_path: Path,
    duplicate_artifact_dir: Path,
) -> None:
    client = TestClient(
        create_app(
            model_dir=tmp_path / "missing-category-model",
            duplicate_model_dir=duplicate_artifact_dir,
        )
    )
    description = "The printer in the main library is offline."
    payload = {
        "new_complaint": {"description": description},
        "existing_complaints": [{"complaint_id": "R7", "description": description}],
        "thresholds": {"duplicate": 0.20, "uncertain": 0.10},
    }

    response = client.post("/detect/duplicates", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["decision"] == "match"
    assert body["candidates"][0]["category"] is None
    assert body["candidates"][0]["location"] is None
    assert body["candidates"][0]["reasons"] == ["similar description text"]


def test_hard_negative_sharing_category_and_location_is_not_a_match(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)
    payload = {
        "new_complaint": {
            "description": "The main library air conditioner is making a loud noise.",
            "category": "Infrastructure",
            "location": "Main Library",
        },
        "existing_complaints": [
            {
                "complaint_id": "R9",
                "description": "The main library printer is offline.",
                "category": "Infrastructure",
                "location": "Main Library",
            }
        ],
    }

    response = client.post("/detect/duplicates", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["decision"] != "match"
    assert body["action"] == "suggestion_only"


def test_malformed_records_and_invalid_thresholds_are_rejected(
    duplicate_artifact_dir: Path,
) -> None:
    client = _client(duplicate_artifact_dir)
    cases: list[dict[str, Any]] = [{}]

    missing_description = _payload()
    del missing_description["new_complaint"]["description"]
    cases.append(missing_description)

    blank_description = _payload()
    blank_description["new_complaint"]["description"] = "   "
    cases.append(blank_description)

    empty_description = _payload()
    empty_description["new_complaint"]["description"] = ""
    cases.append(empty_description)

    unknown_category = _payload()
    unknown_category["new_complaint"]["category"] = "Rocket Science"
    cases.append(unknown_category)

    missing_id = _payload()
    del missing_id["existing_complaints"][0]["complaint_id"]
    cases.append(missing_id)

    blank_existing_description = _payload()
    blank_existing_description["existing_complaints"][0]["description"] = ""
    cases.append(blank_existing_description)

    duplicate_ids = _payload()
    duplicate_ids["existing_complaints"][1]["complaint_id"] = "R1"
    cases.append(duplicate_ids)

    identity_field = _payload()
    identity_field["new_complaint"]["studentId"] = "S123"
    cases.append(identity_field)

    nested_identity_field = _payload()
    nested_identity_field["existing_complaints"][0]["role"] = "STUDENT"
    cases.append(nested_identity_field)

    malformed_candidate = _payload()
    malformed_candidate["existing_complaints"][0] = "not an object"
    cases.append(malformed_candidate)

    inverted_thresholds = _payload(thresholds={"duplicate": 0.10, "uncertain": 0.20})
    cases.append(inverted_thresholds)

    equal_thresholds = _payload(thresholds={"duplicate": 0.20, "uncertain": 0.20})
    cases.append(equal_thresholds)

    out_of_range_threshold = _payload(thresholds={"duplicate": 1.5, "uncertain": 0.10})
    cases.append(out_of_range_threshold)

    zero_candidates = _payload(max_candidates=0)
    cases.append(zero_candidates)

    excessive_candidate_limit = _payload(max_candidates=21)
    cases.append(excessive_candidate_limit)

    too_many_existing = _payload(
        existing=[
            {"complaint_id": f"R{index}", "description": "A repeated complaint description."}
            for index in range(501)
        ]
    )
    cases.append(too_many_existing)

    for payload in cases:
        response = client.post("/detect/duplicates", json=payload)
        assert response.status_code == 422, payload


def test_missing_artifact_returns_safe_service_unavailable(tmp_path: Path) -> None:
    client = _client(tmp_path / "missing-duplicate-model")

    response = client.post("/detect/duplicates", json=_payload())

    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "duplicate_model_unavailable"
    assert "not found" in detail["message"]


def test_invalid_artifact_returns_safe_service_unavailable(tmp_path: Path) -> None:
    artifact_dir = tmp_path / "invalid-duplicate-model"
    artifact_dir.mkdir()
    (artifact_dir / "model.joblib").write_bytes(b"not a joblib artifact")
    (artifact_dir / "metadata.json").write_text("{}", encoding="utf-8")
    client = _client(artifact_dir)

    response = client.post("/detect/duplicates", json=_payload())

    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "duplicate_model_invalid"


def test_duplicate_endpoint_requires_the_configured_internal_token(
    duplicate_artifact_dir: Path,
) -> None:
    client = TestClient(
        create_app(
            duplicate_model_dir=duplicate_artifact_dir,
            api_token="shared-secret",
        )
    )

    missing = client.post("/detect/duplicates", json=_payload())
    accepted = client.post(
        "/detect/duplicates",
        json=_payload(),
        headers={"X-PULSE-ML-Token": "shared-secret"},
    )

    assert missing.status_code == 401
    assert missing.json()["detail"]["code"] == "unauthorized"
    assert accepted.status_code == 200
