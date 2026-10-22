# PULSE ML Foundation — Phases 1, 1.1, 2, 2.1, and NestJS integration

A Python service for **complaint-category suggestions and read-only duplicate
suggestions**. The NestJS backend calls it through a private server-to-server
boundary; Flutter never calls it directly. It never changes a report's category,
priority, status, assignee, or permissions, and the duplicate endpoint never
merges, rejects, or edits complaints.

## What is included

- Synthetic starter dataset across the eight existing PULSE categories.
- Phase 1.1 focused synthetic additions for ambiguous Electrical and
  Network / IT complaints, marked by source column.
- Strict dataset validation, provenance metadata, and frozen-holdout leakage
  guards.
- Reproducible TF-IDF + logistic-regression baseline and candidate.
- Grouped, stratified holdout evaluation with macro-F1, accuracy, per-class
  precision/recall, and a confusion matrix.
- Versioned model artifacts (`model.joblib`, `metadata.json`, `metrics.json`).
- Error analysis and baseline-versus-candidate reports.
- Phase 2 synthetic duplicate benchmark with hard negatives and a group split
  that keeps every variant of an issue in one partition.
- Frozen Phase 2 duplicate baseline report and metrics in
  `artifacts/duplicate-detector/v0.1.0/`.
- Phase 2.1 grouped train/validation/test duplicate benchmark with a frozen test
  fingerprint and 216 complaints across 72 issue groups.
- Persisted, train-only TF-IDF artifact (`model.joblib`, `metadata.json`,
  `training_report.json`, `evaluation.json`, `comparison.json`). Inference loads
  the fitted vectorizer and never fits on incoming complaints.
- Reproducible TF-IDF word + character cosine detector, bounded category/location
  ranking support, ranked candidates, and concise reasons.
- FastAPI endpoints `GET /health`, `POST /predict/category`, and
  `POST /detect/duplicates`.
- Optional shared-token authentication (`PULSE_ML_API_TOKEN`) for private
  server-to-server prediction calls.
- Low-confidence abstain signal, read-only duplicate suggestions, and safe
  HTTP 503 responses when a model artifact is missing or invalid.
- Unit tests, lint/type configuration, and local run instructions.

Out of scope: priority prediction, automatic complaint merges or rejections,
chatbots, automatic report changes, Flutter screens that consume suggestions,
and real campus data.

## Layout

```text
safebunk-ml/
  data/                         synthetic CSVs, additions, dataset card, sidecars
  src/pulse_ml/                 service, datasets, training, model, and duplicate code
  scripts/                      validate, build, train, evaluate, analyze commands
  tests/                        pytest suite
  artifacts/category-classifier versioned classifier artifacts
  artifacts/duplicate-detector  frozen Phase 2 baseline and Phase 2.1 detector artifacts
  ERROR_ANALYSIS.md             Phase 1.1 findings and evaluation protocol
  DUPLICATE_DETECTION.md        Phase 2 baseline and Phase 2.1 detector protocol
```

## Requirements

- Python 3.11–3.13. The commands below use a local virtual environment.
- Dependencies are bounded in `pyproject.toml`; `requirements.txt` installs the
  local package and its runtime dependencies.

## Setup

From `safebunk-ml/`:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

If PowerShell activation is allowed, `.\.venv\Scripts\Activate.ps1` works too.
On macOS/Linux use `python3 -m venv .venv` and `.venv/bin/python`.

## Dataset validation

```powershell
.\.venv\Scripts\python.exe scripts\validate_dataset.py
.\.venv\Scripts\python.exe scripts\validate_dataset.py --dataset data\synthetic_complaints_v2.csv
```

This prints the row count, SHA-256, per-category counts, source counts, and
balance status. Both datasets are **synthetic and not real campus complaints**.
See `data/README.md` for the schema, versions, limitations, and the authorized
process for adding anonymized, human-labeled real complaints.

## Train

Phase 1 baseline:

```powershell
.\.venv\Scripts\python.exe scripts\train.py --model-version 0.1.0
```

The training command:

1. validates the dataset;
2. groups near-identical descriptions;
3. creates a category-stratified grouped holdout (default 25% test, seed 42);
4. fits TF-IDF (word 1–2 grams) + logistic regression;
5. records accuracy, macro-F1, macro precision/recall, per-class metrics, and the
   confusion matrix;
6. writes `artifacts/category-classifier/v0.1.0/model.joblib`,
   `metadata.json`, and `metrics.json`.

Phase 1.1 candidate:

```powershell
.\.venv\Scripts\python.exe scripts\build_phase1_1_dataset.py
.\.venv\Scripts\python.exe scripts\train_phase1_1.py
```

The v2 build is deterministic and refuses to proceed if a new row creates a
near-duplicate group crossing the frozen Phase 1 holdout. The candidate trains
on all non-holdout v2 rows, including all 32 additions, and evaluates on the
untouched 48-row Phase 1 test set. The baseline artifact and metrics are not
overwritten.

`model.joblib` is a local binary artifact and is ignored by Git. The metadata,
metrics, comparison, and error analysis files are small and reviewable. Retrain
rather than editing them.

## Evaluate

```powershell
.\.venv\Scripts\python.exe scripts\evaluate.py
.\.venv\Scripts\python.exe scripts\evaluate.py --model-dir artifacts\category-classifier\v0.2.0
```

This loads the saved artifact, verifies the dataset SHA-256, recreates the
recorded holdout split, and recomputes the metrics. For v0.2.0 that split is the
explicit frozen Phase 1 holdout recorded in the metadata. It does not evaluate on
training data. Use `--output path/to/report.json` to save the recomputed metrics.

### Phase 1 synthetic baseline (v0.1.0)

- 192 synthetic rows, 24 per category; 144 train / 48 test.
- Accuracy: **0.6667**.
- Macro-F1: **0.6608**.
- Strongest per-class F1: Academic (0.9091); weakest: Electrical (0.2500).
- Electrical examples were most often confused with Network / IT.

### Phase 1.1 candidate (v0.2.0)

- 224 synthetic rows: 40 Electrical, 40 Network / IT, 24 in each other category.
- Same frozen 48-row Phase 1 holdout; 176 training rows.
- Accuracy: **0.7500**.
- Macro-F1: **0.7536**.
- Electrical F1: **0.6667** (baseline 0.2500); Network / IT F1: **0.7692**
  (baseline 0.5333).
- Focus errors (Electrical <-> Network / IT): **1** (baseline 4).
- Threshold remains **0.20**; it was not lowered to increase predictions.

The candidate was trained on synthetic additions chosen after reviewing baseline
errors, so the improvement is evidence on a targeted synthetic regression
benchmark, not an unbiased generalization estimate. The holdout has only six
rows per category. See `ERROR_ANALYSIS.md` and
`artifacts/category-classifier/v0.2.0/comparison.json` for full metrics and the
confusion matrix. None of these numbers establish production readiness.

## Duplicate detection (Phases 2 and 2.1)

The duplicate detector is independent of the category classifier. It compares a
new complaint with supplied existing complaints using TF-IDF word and character
n-grams combined with `FeatureUnion`, then cosine similarity. Scores are
**similarity and ranking scores, not probabilities**. The endpoint only suggests
possible duplicates; it never merges, rejects, or modifies anything.

### Phase 2 baseline (preserved)

The frozen Phase 2 baseline used word 1–2 grams plus character 3–5 grams, with
TF-IDF fitted on each request's complaint collection. Its report remains at
`artifacts/duplicate-detector/v0.1.0/evaluation.json`; Phase 2.1 does not overwrite
it.

```powershell
.\.venv\Scripts\python.exe scripts\build_duplicate_dataset.py
.\.venv\Scripts\python.exe scripts\evaluate_duplicates.py
```

The Phase 2 benchmark has 96 complaints in 32 issue groups, split 16/16 by group.
Thresholds were selected on train only at duplicate **0.20** and uncertain
**0.10**.

| Evaluation | Precision | Recall | F1 | FPR |
| --- | ---: | ---: | ---: | ---: |
| Train, selected threshold | 0.7551 | 0.7708 | 0.7629 | 0.0111 |
| Test, test-corpus-fitted | 0.5147 | 0.7292 | 0.6034 | 0.0306 |
| Test, train-vocabulary stress | 0.1538 | 0.9167 | 0.2635 | 0.2241 |

The primary Phase 2 test protocol fitted on test complaint text, so it is a
diagnostic rather than the Phase 2.1 inference path. Its hard-negative FPR was
0.0764. The train-vocabulary stress result shows the baseline's vocabulary
sensitivity.

### Phase 2.1 persisted detector

```powershell
.\.venv\Scripts\python.exe scripts\build_duplicate_v2_dataset.py
.\.venv\Scripts\python.exe scripts\train_duplicate_detector.py
.\.venv\Scripts\python.exe scripts\evaluate_duplicates_v2.py
```

1. The v2 benchmark has 216 complaints in 72 issue groups, split 72 complaints
   and 24 groups each into train, validation, and test. Every category has three
   groups per split, and every split has 2,556 pairs (72 positive, 2,484
   negative).
2. `duplicate_detection_v2_test_freeze.json` records the test group IDs and
   canonical complaint/pair hashes. Training verifies the fingerprint but never
   scores test; evaluation verifies it before scoring.
3. The vectorizer is fitted on the **train split only**. Preprocessing and
   thresholds are selected on validation only: maximize F1 subject to
   false-positive rate ≤ 0.10.
4. The selected configuration is word unigrams + character 2–4 grams with NFKC
   whitespace normalization and English stop-word removal. The selected
   operating point is duplicate **0.50** and uncertain **0.40**.
5. Category and location agreement add at most 0.04 to the ranking score.
   Candidate decisions require text similarity of at least 0.05, so matching
   metadata alone cannot create a match or candidate.

| Evaluation | Precision | Recall | F1 | FPR | Hard-negative FPR |
| --- | ---: | ---: | ---: | ---: | ---: |
| Train, selected threshold 0.50 | 1.0000 | 0.2361 | 0.3820 | 0.0000 | 0.0000 |
| Validation, selected threshold 0.50 | 0.5325 | 0.5694 | 0.5503 | 0.0145 | 0.0606 |
| Frozen test, persisted train-fitted artifact | 0.7077 | 0.6389 | 0.6715 | 0.0076 | 0.0301 |
| Frozen test, text-only ablation | 0.8125 | 0.5417 | 0.6500 | 0.0036 | 0.0143 |
| Frozen test, Phase 2 test-corpus diagnostic | 0.7500 | 0.7917 | 0.7703 | 0.0076 | 0.0254 |

The Phase 2 test-corpus diagnostic is not the deployed path and uses test text to
build its vocabulary. The candidate's lower F1 against that diagnostic is
expected when vocabulary leakage is removed; this is not an apples-to-apples
unseen-corpus comparison. The candidate is the only deployable inference path.
See `DUPLICATE_DETECTION.md` and
`artifacts/duplicate-detector/v0.2.0/evaluation.json` for the full protocol,
confusion counts, uncertain-band rates, and limitations. These synthetic results
do not establish production readiness.

## Run the API

Set the same shared secret in the ML service and the NestJS backend before
starting an integrated local run. The ML service accepts prediction calls
without a token only when `PULSE_ML_API_TOKEN` is unset; the NestJS client
requires both its URL and token and otherwise returns a safe "unavailable"
suggestion without calling this service.

```powershell
$env:PULSE_ML_API_TOKEN = "replace-with-a-long-random-secret"
.\.venv\Scripts\python.exe -m uvicorn pulse_ml.api:app --host 127.0.0.1 --port 8001
```

The classifier service default remains the Phase 1 baseline (`v0.1.0`). The
duplicate detector default is `artifacts/duplicate-detector/v0.2.0`. To serve the
reviewed classifier candidate locally:

```powershell
$env:PULSE_ML_MODEL_DIR = "artifacts\category-classifier\v0.2.0"
.\.venv\Scripts\python.exe -m uvicorn pulse_ml.api:app --host 127.0.0.1 --port 8001
```

Use `PULSE_ML_DUPLICATE_MODEL_DIR` to point at another duplicate-detector
artifact directory. The duplicate endpoint does not require the category model.
`model.joblib` is intentionally ignored by Git; run
`scripts/train_duplicate_detector.py` after checkout if the local duplicate
artifact is absent.

Health:

```powershell
curl http://127.0.0.1:8001/health
```

Prediction:

```powershell
curl -X POST http://127.0.0.1:8001/predict/category `
  -H "Content-Type: application/json" `
  -H "X-PULSE-ML-Token: $env:PULSE_ML_API_TOKEN" `
  -d '{"description":"Water is leaking from a pipe under the sink."}'
```

Example response:

```json
{
  "category": "Plumbing",
  "confidence": 0.38,
  "model_version": "0.1.0",
  "manual_review_recommended": false,
  "decision": "predict",
  "threshold": 0.20
}
```

When `confidence` is below `threshold`:

- `manual_review_recommended` is `true`;
- `decision` is `abstain`;
- a consumer must retain the existing category or request human review instead
  of applying the suggestion.

`confidence` is the maximum `predict_proba` score. It is **not calibrated** and
must not be presented as certainty. The default `0.20` threshold is an
operational routing choice for an eight-class model, not a probability of being
correct. It was not tuned on the Phase 1.1 holdout and remains unchanged.

The category request body accepts only `description`. Extra fields such as
`studentId` or `role` are rejected. Descriptions are required, non-blank, and
limited to 4,000 characters. The service performs no external network calls.

### Duplicate suggestions

```powershell
curl -X POST http://127.0.0.1:8001/detect/duplicates `
  -H "Content-Type: application/json" `
  -H "X-PULSE-ML-Token: $env:PULSE_ML_API_TOKEN" `
  -d '{
    "new_complaint": {
      "description": "The lights in the main library keep flickering.",
      "category": "Electrical",
      "location": "Main Library"
    },
    "existing_complaints": [
      {
        "complaint_id": "R-1001",
        "description": "Lighting in the main library reading room is flashing.",
        "category": "Electrical",
        "location": "Main Library"
      }
    ],
    "max_candidates": 5
  }'
```

`thresholds` may be omitted, in which case the artifact defaults are used. If only
one band is supplied, the other comes from the artifact.

Example response:

```json
{
  "decision": "match",
  "candidates": [
    {
      "complaint_id": "R-1001",
      "similarity_score": 0.5179,
      "ranking_score": 0.5579,
      "category": "Electrical",
      "location": "Main Library",
      "category_match": true,
      "location_match": true,
      "reasons": [
        "similar description text",
        "same category: Electrical",
        "same location: Main Library"
      ]
    }
  ],
  "duplicate_threshold": 0.5,
  "uncertain_threshold": 0.4,
  "similarity_metric": "tfidf_cosine_similarity",
  "ranking_metric": "cosine_similarity_with_metadata_support",
  "model_version": "0.2.0",
  "score_note": "Cosine similarity is a ranking score, not a probability. Category and location matches add a small supporting boost and cannot create a match without text similarity.",
  "manual_review_recommended": true,
  "action": "suggestion_only",
  "existing_complaints_evaluated": 1,
  "message": "Potential duplicates found; these are suggestions only and require human review."
}
```

- `new_complaint.description` is required; category and location are optional.
- Each existing record requires `complaint_id` and `description`; category and
  location are optional. IDs must be unique, and at most 500 records are accepted.
- `thresholds.duplicate` and `thresholds.uncertain` are optional per-request
  overrides; omitted values come from the loaded artifact. After defaults are
  applied, the combined values must satisfy `0 <= uncertain < duplicate <= 1`.
- `decision` is `match`, `uncertain`, or `no_match`. Candidates below the
  uncertain threshold are not returned. An empty existing collection is a valid
  `no_match`, not an error.
- `similarity_score` is the TF-IDF cosine similarity of the descriptions.
  `ranking_score` adds at most 0.04 for matching category/location. Neither is a
  probability or calibrated confidence. Candidates require text similarity of at
  least 0.05, so metadata agreement alone cannot create a match.
- `reasons` explains text similarity and category/location agreement.
- The endpoint loads the persisted vectorizer; it never fits on the request
  corpus. It does not require the category model and never changes a complaint.
  Malformed records return HTTP 422; missing/invalid duplicate artifacts return
  HTTP 503; defensive failures return HTTP 500.

## Tests and checks

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m ruff format --check .
.\.venv\Scripts\python.exe -m mypy
```

Test coverage includes dataset validation, optional source-column provenance,
duplicate/near-duplicate leakage guards, the frozen Phase 1 holdout, split
reproducibility, fixed-holdout training metadata, ambiguous-example data
regression, artifact metadata errors, real artifact serving, valid input,
empty/oversized input, identity-field rejection, missing/invalid models, and
low-confidence abstention. Duplicate tests cover Phase 2 group purity, Phase 2.1
three-way group purity, frozen-test fingerprint verification and tampering,
complete pair generation, pair-label tampering, train/validation-only threshold
selection, persisted artifact loading in a fresh process, deterministic ranking,
no-refit detection, metadata-only hard negatives, empty existing collections,
threshold bands, malformed/excessive input, missing/invalid artifacts, and the
endpoint's independence from the category model, and shared-token enforcement
when `PULSE_ML_API_TOKEN` is configured.

## Model and service errors

- Missing or wrong internal token when `PULSE_ML_API_TOKEN` is configured:
  HTTP 401, `{"detail":{"code":"unauthorized", ...}}`. `/health` remains
  reachable for local liveness checks.
- Missing category artifact: HTTP 503,
  `{"detail":{"code":"model_unavailable", ...}}`.
- Invalid/corrupt category artifact or unsupported labels: HTTP 503,
  `{"detail":{"code":"model_invalid", ...}}`.
- Invalid category or duplicate request: HTTP 422.
- Missing duplicate artifact: HTTP 503,
  `{"detail":{"code":"duplicate_model_unavailable", ...}}`.
- Invalid/corrupt duplicate artifact: HTTP 503,
  `{"detail":{"code":"duplicate_model_invalid", ...}}`.
- `/health` returns HTTP 200 with `status: "degraded"` when the category model is
  missing or invalid, so an operator can see the problem without a successful
  prediction. Duplicate detection remains available without that model when its
  own artifact is present.
- An empty duplicate request collection returns HTTP 200 with `no_match`.
- A defensive duplicate-detector failure returns HTTP 500 with
  `duplicate_detection_failed`; no complaint is changed in any error path.

Set `PULSE_ML_MODEL_DIR` to point at another versioned classifier artifact
directory, and `PULSE_ML_DUPLICATE_MODEL_DIR` to point at another duplicate
artifact directory.

## NestJS integration boundary

The NestJS backend now calls this service through its internal `MlClientService`.
The Python service is still intended to bind to a private interface and must not
be exposed to Flutter or other public clients.

- The backend sends `X-PULSE-ML-Token` from `PULSE_ML_SERVICE_TOKEN`; configure
  the same value here as `PULSE_ML_API_TOKEN`. Both values are deployment
  secrets and are never sent to Flutter.
- Only complaint text and the minimum comparison metadata (report IDs,
  categories, locations) cross the boundary. Student IDs, roles, and session
  credentials are never sent.
- The backend uses a short timeout (2 seconds by default), at most one retry for
  read-only predictions, and maps every upstream failure to a safe suggestion
  response. `POST /api/ml/category-suggestion` and the duplicate-suggestion
  routes never mutate a report.
- On timeout, a 5xx, a missing artifact, or low confidence, the backend keeps
  the report unchanged and marks the result for manual review. Report creation,
  viewing, and attachments do not depend on ML availability.
- Duplicate responses remain suggestions only. Nothing automatically merges,
  rejects, or modifies a complaint.
- A future human action may apply a suggestion; it must record the model
  version, score, threshold, and decision for audit. No auto-apply path exists.
- A prediction or duplicate suggestion must never directly update category,
  priority, status, assignee, or permissions.

## Limitations

- The datasets are tiny, synthetic, intentionally non-uniform in v2, and not
  human-verified.
- The Phase 1.1 additions were informed by baseline holdout errors. The
  candidate's improvement is therefore measured on a targeted synthetic
  regression benchmark, not a clean generalization test.
- Each holdout category has only six rows, so per-class scores are highly
  sensitive to single predictions.
- High holdout scores on synthetic text do not establish real-world accuracy.
- The model is English-only and uses description text only.
- Confidence is uncalibrated; the threshold is a conservative routing signal.
- The Phase 2 baseline benchmark (96 complaints, 32 groups) and the Phase 2.1
  benchmark (216 complaints, 72 groups) are both synthetic and not human-verified.
  Their duplicate rates do not estimate real campus duplicate rates.
- The Phase 2.1 frozen test has 24 issue groups, 72 positive pairs, and 631 hard
  negatives. Metrics are sensitive to individual paraphrases and small sample
  sizes.
- The persisted detector is lexical TF-IDF. It misses semantic paraphrases, can be
  confused by shared category/location vocabulary, and its similarity/ranking
  scores are not calibrated probabilities. The Phase 2 train-vocabulary stress
  test shows substantial degradation under vocabulary shift.
- Feature configuration and thresholds were selected on a small validation split.
  The frozen test result is one honest benchmark result, not a production
  readiness claim.
- The backend integration returns suggestions only; Flutter does not consume
  them yet. There is no production monitoring, drift detection, or calibrated
  confidence for either model.
