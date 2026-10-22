"""Pydantic request and response contracts for the ML service."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from pulse_ml.categories import (
    CATEGORY_SET,
    MAX_DESCRIPTION_LENGTH,
    MIN_DESCRIPTION_LENGTH,
    SUPPORTED_CATEGORIES,
)
from pulse_ml.duplicates import SCORE_NOTE


class PredictCategoryRequest(BaseModel):
    """Text-only input. Identity and role fields are explicitly rejected."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    description: str = Field(
        min_length=MIN_DESCRIPTION_LENGTH,
        max_length=MAX_DESCRIPTION_LENGTH,
        description="Complaint description text only; do not send identity or role data.",
    )

    @field_validator("description")
    @classmethod
    def description_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("description must not be blank")
        return value


class PredictCategoryResponse(BaseModel):
    category: str
    confidence: float = Field(ge=0.0, le=1.0)
    model_version: str
    manual_review_recommended: bool
    decision: Literal["predict", "abstain"]
    threshold: float = Field(ge=0.0, le=1.0)


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    model_loaded: bool
    model_version: str | None = None
    detail: str | None = None


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    detail: ErrorDetail


class _ComplaintFields(BaseModel):
    """Shared text and optional metadata for duplicate comparison."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    description: str = Field(
        min_length=MIN_DESCRIPTION_LENGTH,
        max_length=MAX_DESCRIPTION_LENGTH,
        description="Complaint description text only; do not send identity or role data.",
    )
    category: str | None = Field(
        default=None,
        description="Optional canonical category from the existing PULSE category set.",
    )
    location: str | None = Field(
        default=None,
        max_length=200,
        description=(
            "Optional free-text location used only as supporting ranking evidence "
            "and explanation, never as sufficient evidence on its own."
        ),
    )

    @field_validator("description")
    @classmethod
    def description_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("description must not be blank")
        return value

    @field_validator("category")
    @classmethod
    def category_must_be_supported(cls, value: str | None) -> str | None:
        if value is not None and value not in CATEGORY_SET:
            raise ValueError("category must be one of " + ", ".join(SUPPORTED_CATEGORIES))
        return value

    @field_validator("location")
    @classmethod
    def normalize_location(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        return normalized or None


class NewComplaintInput(_ComplaintFields):
    """A new complaint to compare against an existing collection."""


class ExistingComplaintInput(_ComplaintFields):
    """An existing complaint that may be suggested as a duplicate."""

    complaint_id: str = Field(
        min_length=1,
        max_length=100,
        description="Stable identifier supplied by the caller; not an identity field.",
    )


class DuplicateThresholds(BaseModel):
    """Optional per-request overrides of the artifact operating thresholds."""

    model_config = ConfigDict(extra="forbid")

    duplicate: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        allow_inf_nan=False,
        description="Optional duplicate threshold; artifact default when omitted.",
    )
    uncertain: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        allow_inf_nan=False,
        description="Optional uncertain threshold; artifact default when omitted.",
    )

    @model_validator(mode="after")
    def thresholds_must_be_ordered_when_both_set(self) -> DuplicateThresholds:
        if (
            self.duplicate is not None
            and self.uncertain is not None
            and self.uncertain >= self.duplicate
        ):
            raise ValueError("uncertain threshold must be lower than duplicate threshold")
        return self


class DuplicateDetectionRequest(BaseModel):
    """A read-only duplicate suggestion request."""

    model_config = ConfigDict(extra="forbid")

    new_complaint: NewComplaintInput
    existing_complaints: list[ExistingComplaintInput] = Field(
        default_factory=list,
        max_length=500,
        description="Existing complaints to compare; an empty list is a valid no-match request.",
    )
    thresholds: DuplicateThresholds = Field(default_factory=DuplicateThresholds)
    max_candidates: int = Field(
        default=5,
        ge=1,
        le=20,
        description="Maximum number of ranked candidates returned.",
    )

    @model_validator(mode="after")
    def complaint_ids_must_be_unique(self) -> DuplicateDetectionRequest:
        identifiers = [complaint.complaint_id for complaint in self.existing_complaints]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("existing complaint_id values must be unique")
        return self


class DuplicateCandidateResponse(BaseModel):
    complaint_id: str
    similarity_score: float = Field(
        ge=0.0,
        le=1.0,
        description="TF-IDF cosine similarity of the descriptions, not a probability.",
    )
    ranking_score: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "Text similarity plus a small supporting category/location boost. "
            "Still a ranking score, not a probability."
        ),
    )
    category: str | None
    location: str | None
    category_match: bool
    location_match: bool
    reasons: list[str]


class DuplicateDetectionResponse(BaseModel):
    decision: Literal["match", "uncertain", "no_match"]
    candidates: list[DuplicateCandidateResponse]
    duplicate_threshold: float = Field(ge=0.0, le=1.0)
    uncertain_threshold: float = Field(ge=0.0, le=1.0)
    similarity_metric: Literal["tfidf_cosine_similarity"] = "tfidf_cosine_similarity"
    ranking_metric: Literal["cosine_similarity_with_metadata_support"] = (
        "cosine_similarity_with_metadata_support"
    )
    model_version: str
    score_note: str = SCORE_NOTE
    manual_review_recommended: bool
    action: Literal["suggestion_only"] = "suggestion_only"
    existing_complaints_evaluated: int = Field(ge=0)
    message: str
