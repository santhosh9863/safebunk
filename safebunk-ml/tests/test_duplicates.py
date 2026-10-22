"""Unit tests for fitted TF-IDF duplicate ranking and threshold decisions."""

from __future__ import annotations

import pytest
from sklearn.pipeline import FeatureUnion

from pulse_ml.duplicates import (
    FEATURE_CONFIGS,
    DuplicateDetectionResult,
    ExistingComplaint,
    NewComplaint,
    build_duplicate_vectorizer,
    rank_with_fitted_vectorizer,
    validate_thresholds,
)


def _new_complaint() -> NewComplaint:
    return NewComplaint(
        description="The lights in the main library reading room keep flickering.",
        category="Electrical",
        location="Main Library",
    )


def _existing_complaints() -> list[ExistingComplaint]:
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
        ExistingComplaint(
            "R4",
            "The Wi-Fi network in the main library is not working.",
            "Network / IT",
            "Main Library",
        ),
        ExistingComplaint(
            "R5",
            "The ceiling fan in Computer Lab 1 makes a loud rattling noise.",
            "Electrical",
            "Computer Lab 1",
        ),
    ]


def _fitted_vectorizer(
    texts: list[str] | None = None,
) -> FeatureUnion:
    vectorizer = build_duplicate_vectorizer(FEATURE_CONFIGS[0])
    corpus = [complaint.description for complaint in _existing_complaints()]
    corpus.extend(texts or [])
    vectorizer.fit(list(dict.fromkeys(corpus)))
    return vectorizer


def _rank(
    new_complaint: NewComplaint,
    existing: list[ExistingComplaint],
    *,
    duplicate_threshold: float = 0.20,
    uncertain_threshold: float = 0.10,
    max_candidates: int = 5,
) -> DuplicateDetectionResult:
    vectorizer = _fitted_vectorizer([complaint.description for complaint in existing])
    return rank_with_fitted_vectorizer(
        vectorizer,
        new_complaint,
        existing,
        duplicate_threshold=duplicate_threshold,
        uncertain_threshold=uncertain_threshold,
        max_candidates=max_candidates,
    )


def test_ranked_candidates_include_scores_and_reasons() -> None:
    result = _rank(_new_complaint(), _existing_complaints())

    assert result.decision == "match"
    assert result.manual_review_recommended is True
    assert result.existing_complaints_evaluated == 5
    assert result.candidates[0].complaint_id == "R2"
    assert 0.0 <= result.candidates[0].similarity_score <= 1.0
    assert result.candidates[0].ranking_score >= result.candidates[0].similarity_score
    assert result.candidates[0].category_match is True
    assert result.candidates[0].location_match is True
    assert "same category: Electrical" in result.candidates[0].reasons
    assert "same location: Main Library" in result.candidates[0].reasons
    assert [candidate.ranking_score for candidate in result.candidates] == sorted(
        (candidate.ranking_score for candidate in result.candidates), reverse=True
    )


def test_empty_existing_collection_is_a_valid_no_match() -> None:
    result = _rank(_new_complaint(), [])

    assert result.decision == "no_match"
    assert result.candidates == ()
    assert result.manual_review_recommended is False
    assert result.existing_complaints_evaluated == 0
    assert "No existing complaints" in result.message


def test_thresholds_can_produce_uncertain_and_no_match() -> None:
    uncertain = _rank(
        _new_complaint(),
        _existing_complaints(),
        duplicate_threshold=0.80,
        uncertain_threshold=0.70,
    )
    no_match = _rank(
        _new_complaint(),
        _existing_complaints(),
        duplicate_threshold=0.99,
        uncertain_threshold=0.98,
    )

    assert uncertain.decision == "uncertain"
    assert uncertain.candidates
    assert uncertain.manual_review_recommended is True
    assert no_match.decision == "no_match"
    assert no_match.candidates == ()
    assert no_match.manual_review_recommended is False


def test_weak_evidence_with_high_thresholds_returns_no_match() -> None:
    result = _rank(
        NewComplaint("A water pipe is leaking under the sink."),
        [ExistingComplaint("R9", "The library printer is offline.")],
        duplicate_threshold=0.90,
        uncertain_threshold=0.80,
    )

    assert result.decision == "no_match"
    assert result.candidates == ()


def test_max_candidates_caps_ranked_output() -> None:
    result = _rank(_new_complaint(), _existing_complaints(), max_candidates=2)

    assert len(result.candidates) == 2
    assert result.candidates[0].complaint_id == "R2"
    assert result.candidates[0].ranking_score >= result.candidates[1].ranking_score


def test_exact_text_without_metadata_has_text_only_reason() -> None:
    description = "The printer in the main library is offline."
    result = _rank(
        NewComplaint(description),
        [ExistingComplaint("R7", description)],
    )

    assert result.decision == "match"
    assert result.candidates[0].similarity_score == pytest.approx(1.0)
    assert result.candidates[0].ranking_score == pytest.approx(1.0)
    assert result.candidates[0].category is None
    assert result.candidates[0].category_match is False
    assert result.candidates[0].location_match is False
    assert result.candidates[0].reasons == ("similar description text",)


def test_location_matching_normalizes_case_and_whitespace() -> None:
    description = "The main library entrance bin is full."
    result = _rank(
        NewComplaint(description, location="  Main   Library  "),
        [ExistingComplaint("R8", description, location="main library")],
    )

    assert result.candidates[0].location_match is True
    assert "same location: main library" in result.candidates[0].reasons


def test_matching_category_and_location_alone_cannot_classify() -> None:
    result = _rank(
        NewComplaint("qqqq zzzz", category="Electrical", location="Main Library"),
        [ExistingComplaint("R9", "xxxx yyyy", "Electrical", "Main Library")],
        duplicate_threshold=0.02,
        uncertain_threshold=0.00,
    )

    assert result.decision == "no_match"
    assert result.candidates == ()


def test_invalid_arguments_are_rejected() -> None:
    complaint = _new_complaint()
    existing = _existing_complaints()

    for duplicate, uncertain in ((0.2, 0.2), (0.1, 0.2), (-0.1, 0.0), (1.1, 0.2)):
        with pytest.raises(ValueError, match="thresholds must satisfy"):
            validate_thresholds(duplicate, uncertain)

    with pytest.raises(ValueError, match="max_candidates"):
        _rank(complaint, existing, max_candidates=0)

    with pytest.raises(ValueError, match="must not be blank"):
        _rank(NewComplaint("   "), existing)

    with pytest.raises(ValueError, match="duplicate complaint_id"):
        _rank(
            complaint,
            [ExistingComplaint("R1", "One description"), ExistingComplaint("R1", "Another")],
        )

    with pytest.raises(ValueError, match="must not be blank"):
        _rank(complaint, [ExistingComplaint("R1", "   ")])
