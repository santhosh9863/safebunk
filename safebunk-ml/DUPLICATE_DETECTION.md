# Duplicate Campus Issue Detection — Phases 2 and 2.1

## Status

This is a local, read-only duplicate-suggestion detector. It is **not** a
production duplicate detector. The NestJS backend can call the FastAPI service
through its private server-to-server boundary; Flutter does not call it directly.

- It never merges, rejects, closes, or edits a complaint.
- It returns ranked suggestions for later human review.
- It does not modify the Phase 1 classifier datasets, metrics, or artifacts.
- All complaints and pair labels used for evaluation are synthetic.
- The frozen Phase 2 baseline report remains at
  `artifacts/duplicate-detector/v0.1.0/`. Phase 2.1 writes separately to
  `artifacts/duplicate-detector/v0.2.0/`.

## Phase 2 baseline (preserved)

The Phase 2 baseline represented each complaint with two TF-IDF blocks:

1. word 1–2 grams with English stop-word removal;
2. character 3–5 grams, less sensitive to inflection, punctuation, and small
   spelling differences.

The blocks were combined with `FeatureUnion` and compared with cosine similarity.
The baseline API fitted the vectorizer on the supplied new complaint plus existing
complaints for every request. That made the score depend on the request corpus and
exposed vocabulary leakage risk in offline evaluation.

Phase 2 benchmark:

- 96 synthetic complaints in 32 issue groups, three variants per group;
- grouped 48-row train / 48-row test split;
- 2,256 labeled pairs, 1,128 per split, 48 positive and 1,080 negative per split;
- 432 hard negatives in the test split.

Phase 2 selected thresholds on train only: maximize F1 subject to false-positive
rate ≤ 0.10. The selected operating point was duplicate **0.20**, uncertain
**0.10**.

Phase 2 results:

| Evaluation | Precision | Recall | F1 | FPR |
| --- | ---: | ---: | ---: | ---: |
| Train, selected threshold | 0.7551 | 0.7708 | 0.7629 | 0.0111 |
| Test, test-corpus-fitted | 0.5147 | 0.7292 | 0.6034 | 0.0306 |
| Test, train-vocabulary stress | 0.1538 | 0.9167 | 0.2635 | 0.2241 |

The primary Phase 2 test protocol fitted on test complaint text without labels.
It was a diagnostic for the request-local API, not a strict unseen-vocabulary
estimate. The stress test showed substantial degradation under vocabulary shift.
The full report is `artifacts/duplicate-detector/v0.1.0/evaluation.json`.

## Phase 2.1 artifact and inference

Phase 2.1 replaces request-time fitting with a persisted, versioned detector
artifact.

```text
artifacts/duplicate-detector/v0.2.0/
  model.joblib            fitted FeatureUnion + feature/threshold metadata
  metadata.json           human-reviewable artifact contract and provenance
  training_report.json    train/validation selection report
  evaluation.json         frozen-test report
  comparison.json         baseline diagnostic versus candidate
```

`model.joblib` is a local binary artifact and is ignored by Git. The JSON records
are reviewable and can be regenerated. The default artifact directory is
`artifacts/duplicate-detector/v0.2.0`; use `PULSE_ML_DUPLICATE_MODEL_DIR` to point
at a different version.

Inference:

1. load `model.joblib` and `metadata.json`;
2. validate the artifact version, feature configuration, preprocessing callable,
   vectorizer type/parameters, support weights, and thresholds;
3. transform the new complaint and existing complaints with the already-fitted
   vectorizer;
4. compute TF-IDF cosine similarity;
5. add at most 0.04 for category/location agreement;
6. require text similarity ≥ 0.05 before a record can be returned or classified;
7. rank by ranking score, then text similarity, then complaint ID.

No `.fit()` or `.fit_transform()` call occurs in the request path. A fresh process
can load the artifact and produce the same ranking without retraining. The service
never fits on incoming complaint text.

Category and location are supporting signals only. They add at most 0.02 each to
the ranking score. A metadata-only pair cannot create a candidate because the
text-evidence floor is applied first. They also appear in `reasons`.

Scores are **ranking scores**, not calibrated probabilities. `similarity_score` is
the text cosine similarity; `ranking_score` is text similarity plus the bounded
metadata support.

## Input contract

`POST /detect/duplicates`

```json
{
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
}
```

- `new_complaint.description` is required, non-blank, and 5–4,000 characters.
- New-complaint `category` and `location` are optional.
- Every existing complaint requires a unique `complaint_id` and a non-blank
  `description`; `category` and `location` are optional.
- At most 500 existing complaints and 20 returned candidates are accepted.
- Extra identity or role fields such as `studentId` or `role` are rejected.
- `thresholds` is optional. When omitted, both bands come from the artifact. A
  single supplied band overrides only that band.
- After artifact defaults are applied, the combined values must satisfy
  `0 <= uncertain < duplicate <= 1`; otherwise the request returns HTTP 422.
- An empty `existing_complaints` list is valid and produces `no_match`.

## Response contract

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

- `decision` is `match`, `uncertain`, or `no_match`.
- The top candidate's ranking score determines the decision. Candidates below the
  uncertain threshold are omitted, and candidates without the text-evidence floor
  are omitted first.
- `max_candidates` caps the ranked list.
- `category_match` and `location_match` require both values to be present and
  equal. Location comparison ignores case and repeated whitespace.
- `manual_review_recommended` is true for `match` and `uncertain`.
- `action` is always `suggestion_only`.
- Malformed records return HTTP 422. Missing/invalid duplicate artifacts return
  HTTP 503 with `duplicate_model_unavailable` or `duplicate_model_invalid`.
  Defensive scoring failures return HTTP 500 with `duplicate_detection_failed`.
  The duplicate endpoint does not require the category classifier artifact.

## Phase 2.1 benchmark

`data/duplicate_detection_v2_complaints.csv` contains 216 complaints in 72
underlying-issue groups. The original 32 Phase 2 groups are reused without text
changes but assigned new split roles; 40 new groups were added from
`data/duplicate_detection_v2_additions.csv`.

Each split has 24 issue groups, three groups per category, and 72 complaints:

| Split | Complaints | Groups | Pairs | Positive | Negative | Hard negatives |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Train | 72 | 24 | 2,556 | 72 | 2,484 | 396 |
| Validation | 72 | 24 | 2,556 | 72 | 2,484 | 594 |
| Test | 72 | 24 | 2,556 | 72 | 2,484 | 631 |

A positive pair is two variants from the same group. A negative pair is two
complaints from different groups. All unordered within-split pairs are included;
there is no model-score-based negative sampling. No group or variant crosses a
split.

`data/duplicate_detection_v2_pairs.csv` contains the generated 7,668 labeled
pairs. `data/duplicate_detection_v2.metadata.json` records provenance, hashes,
split roles, counts, and frozen-test details.
`data/duplicate_detection_v2_test_freeze.json` records the test group IDs and
canonical complaint/pair hashes before tuning.

Hard-negative labels use shared category/location or token Jaccard ≥ 0.30. The
benchmark is synthetic and not human-verified. Hard-negative status is a
data-generation rule, not a human duplicate adjudication.

Reproduce:

```powershell
.\.venv\Scripts\python.exe scripts\build_duplicate_v2_dataset.py
```

The builder refuses group leakage, missing category coverage, duplicate
descriptions, malformed additions, or a missing group split assignment. It also
verifies the frozen-test fingerprint it writes.

## Training and selection protocol

```powershell
.\.venv\Scripts\python.exe scripts\train_duplicate_detector.py
.\.venv\Scripts\python.exe scripts\evaluate_duplicates_v2.py
```

- The vectorizer is fitted on the **train split only**.
- Feature configuration and thresholds are selected on the **validation split
  only**. The rule is maximize F1 subject to FPR ≤ 0.10 over a fixed threshold
  grid, with deterministic tie-breaks.
- The test split is verified against its freeze fingerprint before evaluation and
  is never scored by the training command.
- The evaluation command verifies the dataset SHA-256, artifact dataset SHA-256,
  test groups, and frozen complaint/pair hashes before scoring.
- The final artifact is not refitted on validation or test data.

Phase 2.1 selected:

- preprocessing: NFKC normalization plus whitespace collapse;
- word unigrams with English stop-word removal;
- character 2–4 grams with `char_wb`;
- sublinear TF-IDF, lowercase, Unicode accent stripping;
- duplicate threshold **0.50**, uncertain threshold **0.40**;
- category and location rank support **0.02** each;
- minimum text similarity **0.05**.

The uncertain threshold is a 0.10 operating band below the selected duplicate
threshold. Both are ranking-score bands, not calibrated probabilities.

## Results

Phase 2.1 train and validation at the selected threshold:

| Split | Precision | Recall | F1 | FPR | TP | FP | TN | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Train | 1.0000 | 0.2361 | 0.3820 | 0.0000 | 17 | 0 | 2,484 | 55 |
| Validation | 0.5325 | 0.5694 | 0.5503 | 0.0145 | 41 | 36 | 2,448 | 31 |

Frozen test results:

| Evaluation | Precision | Recall | F1 | FPR | TP | FP | TN | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Persisted train-fitted candidate | 0.7077 | 0.6389 | 0.6715 | 0.0076 | 46 | 19 | 2,465 | 26 |
| Text-only ablation | 0.8125 | 0.5417 | 0.6500 | 0.0036 | 39 | 9 | 2,475 | 33 |
| Phase 2 test-corpus diagnostic | 0.7500 | 0.7917 | 0.7703 | 0.0076 | 57 | 19 | 2,465 | 15 |

- Candidate hard-negative FPR is **0.0301** (19 / 631). The text-only ablation is
  **0.0143** (9 / 631). The diagnostic is **0.0254** (16 / 631).
- In the frozen candidate run, 22.22% of positives and 1.41% of negatives fall in
  the uncertain band.
- The Phase 2 test-corpus diagnostic fits on test complaint text and is not the
  deployed inference path. Its higher recall/F1 is expected with vocabulary
  leakage and is not an apples-to-apples unseen-corpus comparison.
- The candidate is the only deployable path. Its test result is one frozen-benchmark
  result, not evidence of production readiness.

## Limitations

- All 216 complaints and 7,668 pair labels are synthetic and not human-verified.
  Synthetic duplicate rates do not estimate real campus duplicate rates.
- The test set has 24 issue groups, 72 positive pairs, and 631 hard negatives.
  Metrics are sensitive to individual paraphrases and small sample sizes.
- TF-IDF with word and character n-grams is lexical. It can miss semantic
  paraphrases and can over-weight shared category/location vocabulary.
- Category/location support is intentionally small, but it can still raise a
  borderline text score. It cannot create a candidate from metadata alone.
- Similarity and ranking scores are not probabilities and should not be shown as
  confidence percentages.
- Feature configuration and thresholds were selected on a small validation split.
  A different validation split could select a different operating point.
- The Phase 2 test-corpus-fitted result remains a diagnostic only. It must not be
  used as the deployed inference path.
- Thresholds selected on this synthetic corpus are not portable to real complaint
  volume or wording.
- No automatic merge, rejection, or complaint modification is implemented.
- The NestJS backend exposes read-only suggestion routes, but Flutter does not
  consume them yet. These results do not establish production readiness.

## Verification

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m ruff format --check .
.\.venv\Scripts\python.exe -m mypy
.\.venv\Scripts\python.exe scripts\build_duplicate_dataset.py
.\.venv\Scripts\python.exe scripts\evaluate_duplicates.py
.\.venv\Scripts\python.exe scripts\build_duplicate_v2_dataset.py
.\.venv\Scripts\python.exe scripts\train_duplicate_detector.py
.\.venv\Scripts\python.exe scripts\evaluate_duplicates_v2.py
```

The machine-readable reports are
`artifacts/duplicate-detector/v0.1.0/evaluation.json` and
`artifacts/duplicate-detector/v0.2.0/evaluation.json`.
