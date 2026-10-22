# Model artifacts

Artifacts are versioned by directory:

```text
artifacts/category-classifier/<model-version>/
  model.joblib
  metadata.json
  metrics.json
  error_analysis.json      # generated for reviewed versions
  comparison.json          # present for v0.2.0

artifacts/duplicate-detector/<version>/
  model.joblib             # Phase 2.1 fitted FeatureUnion; ignored by Git
  metadata.json            # Phase 2.1 artifact contract and provenance
  training_report.json     # Phase 2.1 train/validation selection
  evaluation.json          # grouped-pair evaluation report
  comparison.json          # Phase 2.1 candidate vs diagnostic baseline
```

`scripts/train.py` writes the classifier baseline, `scripts/train_phase1_1.py`
writes the Phase 1.1 candidate, `scripts/build_duplicate_v2_dataset.py` builds
the Phase 2.1 benchmark, `scripts/train_duplicate_detector.py` writes the
duplicate artifact, and `scripts/analyze_errors.py` writes the error report.
`model.joblib` is generated and ignored by Git because it is a binary build
product; metadata, metrics, comparison, and report files are small, reviewable
records of how the version was produced and how it scored.

The classifier service defaults to `artifacts/category-classifier/v0.1.0`. The
reviewed Phase 1.1 candidate is `artifacts/category-classifier/v0.2.0`; override
the default with the `PULSE_ML_MODEL_DIR` environment variable or the
`create_app(model_dir=...)` factory argument used by tests. The duplicate service
defaults to `artifacts/duplicate-detector/v0.2.0`; override it with
`PULSE_ML_DUPLICATE_MODEL_DIR` or `create_app(duplicate_model_dir=...)`.

## Artifact contract

- `metadata.json` must contain a non-empty `model_version`, the exact supported
  `categories`, and a `confidence_threshold` between 0 and 1.
- `model.joblib` must contain a fitted pipeline with `predict_proba` and
  `classes_`.
- The pipeline classes must exactly match the eight supported categories.
- A missing artifact produces HTTP 503 with `model_unavailable`; corrupt or
  incompatible metadata/model files produce HTTP 503 with `model_invalid`.
- If `split.holdout_row_numbers` is present, evaluation must recreate that exact
  fixed holdout and reject near-duplicate groups crossing it.

Do not hand-edit metadata to claim better metrics. Retrain the artifact, keep the
dataset SHA-256, and record the real holdout results.

Duplicate artifact contract:

- `metadata.json` must contain matching `artifact_version`, `model_version`,
  `feature_config`, support weights, and `duplicate_threshold`/`uncertain_threshold`
  values.
- `model.joblib` must contain a fitted `FeatureUnion` with word and character
  TF-IDF blocks, the persisted preprocessing callable, and the same feature
  configuration and thresholds as `metadata.json`.
- The vectorizer must already be fitted; inference calls `transform` only.
- A missing artifact produces HTTP 503 with `duplicate_model_unavailable`; corrupt,
  incomplete, or inconsistent artifacts produce HTTP 503 with
  `duplicate_model_invalid`.
- The loader must reject mismatched versions, feature configurations, support
  weights, or thresholds. Never bypass validation to load an untrusted file.

## Duplicate detector evaluation

Phase 2 baseline: `scripts/evaluate_duplicates.py` writes
`artifacts/duplicate-detector/v0.1.0/evaluation.json`. The Phase 2 API fitted
TF-IDF on the complaint collection in each request. That report records the
dataset and pair SHA-256 values, the train-only threshold selection, the primary
test-corpus-fitted results, the train-vocabulary stress test, the threshold
sensitivity audit, score distributions, and limitations. It is preserved
unchanged.

Phase 2.1: `scripts/train_duplicate_detector.py` writes
`artifacts/duplicate-detector/v0.2.0/` with `model.joblib`, `metadata.json`, and
`training_report.json`. It fits the vectorizer on the train split only and selects
the feature configuration and thresholds on validation only. It verifies, but does
not score, the frozen test.

`scripts/evaluate_duplicates_v2.py` verifies the dataset/artifact hashes, test
groups, and frozen complaint/pair fingerprints, then scores the frozen test once.
It writes `evaluation.json` and `comparison.json`. The comparison includes the
Phase 2 test-corpus-fitted result only as a labelled diagnostic; that path is not
deployed inference. Reports record confusion counts, uncertain-band rates,
hard-negative performance, hashes, and limitations.

Do not treat either report as a production model card. Both benchmarks are
synthetic. Do not edit a report to change a threshold or metric, and do not
reselect features or thresholds from the frozen test; rerun the builder,
trainer, and evaluator instead. The Phase 2.1 test has already been scored once,
so further changes require a new frozen benchmark version rather than retuning.

## Trust boundary

`model.joblib` is a Joblib/pickle artifact. This applies to both the classifier
and duplicate-detector bundles. Load only files produced by the training commands
from trusted source or deployment storage. Never load an untrusted artifact or
expose an artifact-upload endpoint in this service.
