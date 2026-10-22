"""FastAPI application for local, internal category suggestions."""

from __future__ import annotations

import hmac
import os
import threading
from pathlib import Path
from typing import Protocol

from fastapi import Depends, FastAPI, HTTPException, Request

from pulse_ml.duplicate_model import (
    DuplicateDetector,
    DuplicateModelError,
)
from pulse_ml.duplicates import ExistingComplaint, NewComplaint
from pulse_ml.model import CategoryPredictor, ModelError, Prediction
from pulse_ml.schemas import (
    DuplicateCandidateResponse,
    DuplicateDetectionRequest,
    DuplicateDetectionResponse,
    ErrorResponse,
    HealthResponse,
    PredictCategoryRequest,
    PredictCategoryResponse,
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL_DIR = PROJECT_ROOT / "artifacts" / "category-classifier" / "v0.1.0"
MODEL_DIR_ENV = "PULSE_ML_MODEL_DIR"
DEFAULT_DUPLICATE_MODEL_DIR = PROJECT_ROOT / "artifacts" / "duplicate-detector" / "v0.2.0"
DUPLICATE_MODEL_DIR_ENV = "PULSE_ML_DUPLICATE_MODEL_DIR"
API_TOKEN_ENV = "PULSE_ML_API_TOKEN"
API_TOKEN_HEADER = "X-PULSE-ML-Token"


class Predictor(Protocol):
    @property
    def model_version(self) -> str: ...

    def predict(self, description: str) -> Prediction: ...


class _ModelManager:
    """Lazy loader that keeps a missing model recoverable without a restart."""

    def __init__(self, model_dir: Path) -> None:
        self._model_dir = model_dir
        self._predictor: CategoryPredictor | None = None
        self._lock = threading.Lock()

    def get(self) -> CategoryPredictor:
        with self._lock:
            if self._predictor is None:
                self._predictor = CategoryPredictor.from_directory(self._model_dir)
            return self._predictor


class _DuplicateModelManager:
    """Lazy loader for the fitted duplicate vectorizer artifact."""

    def __init__(self, model_dir: Path) -> None:
        self._model_dir = model_dir
        self._detector: DuplicateDetector | None = None
        self._lock = threading.Lock()

    def get(self) -> DuplicateDetector:
        with self._lock:
            if self._detector is None:
                self._detector = DuplicateDetector.from_directory(self._model_dir)
            return self._detector


def create_app(
    *,
    model_dir: str | Path | None = None,
    predictor: Predictor | None = None,
    duplicate_model_dir: str | Path | None = None,
    duplicate_detector: DuplicateDetector | None = None,
    api_token: str | None = None,
) -> FastAPI:
    """Create an isolated app; tests can inject models, temp dirs, or a token."""

    configured_dir = Path(model_dir or os.environ.get(MODEL_DIR_ENV, str(DEFAULT_MODEL_DIR)))
    manager = _ModelManager(configured_dir)
    configured_duplicate_dir = Path(
        duplicate_model_dir
        or os.environ.get(DUPLICATE_MODEL_DIR_ENV, str(DEFAULT_DUPLICATE_MODEL_DIR))
    )
    duplicate_manager = _DuplicateModelManager(configured_duplicate_dir)
    configured_token = (api_token or os.environ.get(API_TOKEN_ENV) or "").strip() or None

    app = FastAPI(
        title="PULSE ML Local Service",
        version="0.3.0",
        description=(
            "Local category suggestions and read-only duplicate suggestions. "
            "This service never mutates reports, priority, status, assignment, "
            "or permissions."
        ),
    )
    app.state.model_manager = manager
    app.state.predictor = predictor
    app.state.duplicate_model_manager = duplicate_manager
    app.state.duplicate_detector = duplicate_detector

    def get_predictor() -> Predictor:
        if predictor is not None:
            return predictor
        return manager.get()

    def get_duplicate_detector() -> DuplicateDetector:
        if duplicate_detector is not None:
            return duplicate_detector
        return duplicate_manager.get()

    def require_internal_token(request: Request) -> None:
        """Require the shared server-to-server token when one is configured."""

        if configured_token is None:
            return
        supplied = request.headers.get(API_TOKEN_HEADER, "")
        if not hmac.compare_digest(
            supplied.encode("utf-8"),
            configured_token.encode("utf-8"),
        ):
            raise HTTPException(
                status_code=401,
                detail={
                    "code": "unauthorized",
                    "message": "A valid internal service token is required.",
                },
            )

    @app.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        try:
            active_predictor = get_predictor()
        except ModelError as exc:
            return HealthResponse(
                status="degraded",
                model_loaded=False,
                detail=f"{exc.code}: {exc}",
            )
        return HealthResponse(
            status="ok",
            model_loaded=True,
            model_version=active_predictor.model_version,
        )

    @app.post(
        "/predict/category",
        response_model=PredictCategoryResponse,
        responses={
            401: {"model": ErrorResponse},
            503: {"model": ErrorResponse},
        },
        dependencies=[Depends(require_internal_token)],
    )
    def predict_category(payload: PredictCategoryRequest) -> PredictCategoryResponse:
        try:
            active_predictor = get_predictor()
        except ModelError as exc:
            raise HTTPException(
                status_code=503,
                detail={"code": exc.code, "message": str(exc)},
            ) from exc

        try:
            prediction = active_predictor.predict(payload.description)
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail={"code": "invalid_input", "message": str(exc)},
            ) from exc
        except ModelError as exc:
            raise HTTPException(
                status_code=503,
                detail={"code": exc.code, "message": str(exc)},
            ) from exc
        except Exception as exc:  # defensive boundary around third-party model code
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "prediction_failed",
                    "message": "The model could not produce a prediction.",
                },
            ) from exc

        return PredictCategoryResponse(
            category=prediction.category,
            confidence=prediction.confidence,
            model_version=prediction.model_version,
            manual_review_recommended=prediction.manual_review_recommended,
            decision=prediction.decision,
            threshold=prediction.threshold,
        )

    @app.post(
        "/detect/duplicates",
        response_model=DuplicateDetectionResponse,
        responses={
            401: {"model": ErrorResponse},
            500: {"model": ErrorResponse},
            503: {"model": ErrorResponse},
        },
        dependencies=[Depends(require_internal_token)],
    )
    def detect_duplicates(payload: DuplicateDetectionRequest) -> DuplicateDetectionResponse:
        """Return read-only duplicate suggestions, never an automatic merge."""

        try:
            active_detector = get_duplicate_detector()
        except DuplicateModelError as exc:
            raise HTTPException(
                status_code=503,
                detail={"code": exc.code, "message": str(exc)},
            ) from exc

        duplicate_threshold = (
            payload.thresholds.duplicate
            if payload.thresholds.duplicate is not None
            else active_detector.duplicate_threshold
        )
        uncertain_threshold = (
            payload.thresholds.uncertain
            if payload.thresholds.uncertain is not None
            else active_detector.uncertain_threshold
        )

        try:
            result = active_detector.detect(
                NewComplaint(
                    description=payload.new_complaint.description,
                    category=payload.new_complaint.category,
                    location=payload.new_complaint.location,
                ),
                [
                    ExistingComplaint(
                        complaint_id=complaint.complaint_id,
                        description=complaint.description,
                        category=complaint.category,
                        location=complaint.location,
                    )
                    for complaint in payload.existing_complaints
                ],
                duplicate_threshold=duplicate_threshold,
                uncertain_threshold=uncertain_threshold,
                max_candidates=payload.max_candidates,
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail={"code": "invalid_input", "message": str(exc)},
            ) from exc
        except DuplicateModelError as exc:
            raise HTTPException(
                status_code=503,
                detail={"code": exc.code, "message": str(exc)},
            ) from exc
        except Exception as exc:  # defensive boundary around third-party code
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "duplicate_detection_failed",
                    "message": "The duplicate detector could not score the complaints.",
                },
            ) from exc

        return DuplicateDetectionResponse(
            decision=result.decision,
            candidates=[
                DuplicateCandidateResponse(
                    complaint_id=candidate.complaint_id,
                    similarity_score=candidate.similarity_score,
                    ranking_score=candidate.ranking_score,
                    category=candidate.category,
                    location=candidate.location,
                    category_match=candidate.category_match,
                    location_match=candidate.location_match,
                    reasons=list(candidate.reasons),
                )
                for candidate in result.candidates
            ],
            duplicate_threshold=result.duplicate_threshold,
            uncertain_threshold=result.uncertain_threshold,
            model_version=active_detector.model_version,
            manual_review_recommended=result.manual_review_recommended,
            existing_complaints_evaluated=result.existing_complaints_evaluated,
            message=result.message,
        )

    return app


app = create_app()
