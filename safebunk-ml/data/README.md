# Dataset card: synthetic complaint categories

## Status

All datasets here are **synthetic**. They were hand-written for the PULSE ML
foundation and contain no real campus complaints, names, student IDs, contact
details, credentials, addresses, or other personal information. Do not present
these rows or their evaluation scores as production evidence.

| File | Rows | Purpose |
| --- | ---: | --- |
| `synthetic_complaints.csv` | 192 | Phase 1 baseline, 24 per category |
| `phase1_1_additions.csv` | 32 | Phase 1.1 focused additions, 16 Electrical + 16 Network / IT |
| `synthetic_complaints_v2.csv` | 224 | Generated Phase 1.1 dataset: baseline + additions |
| `duplicate_detection_complaints.csv` | 96 | Phase 2 grouped duplicate benchmark, 32 issue groups |
| `duplicate_detection_pairs.csv` | 2,256 | Generated Phase 2 labeled pairs, 1,128 per split |
| `duplicate_detection_v2_additions.csv` | 120 | Phase 2.1 additions, 40 issue groups |
| `duplicate_detection_v2_complaints.csv` | 216 | Phase 2.1 grouped benchmark, 72 issue groups, 3 splits |
| `duplicate_detection_v2_pairs.csv` | 7,668 | Generated Phase 2.1 labeled pairs, 2,556 per split |

The sidecars `synthetic_complaints.metadata.json`,
`synthetic_complaints_v2.metadata.json`, `duplicate_detection.metadata.json`,
`duplicate_detection_v2.metadata.json`, and
`duplicate_detection_v2_test_freeze.json` record provenance, label source,
synthetic flags, row sources, hashes, split roles, and PII review. Keep the
matching sidecar next to the CSV when copying, training, or evaluating so metadata
remains honest.

## Schema

`description,category` for the Phase 1 baseline, or
`description,category,source` for the Phase 1.1 dataset and additions.

- `description`: English text describing one complaint. The API accepts 5 to
  4,000 characters; training rows must be at least 10 characters.
- `category`: exactly one of the eight labels used by the existing Flutter report
  form. Stored values are not renamed by this service.
- `source`: optional provenance marker. The Phase 1.1 values are
  `phase1_synthetic` for the original rows and `phase1_1_synthetic` for every
  addition. Both values explicitly identify synthetic text.

| Category | Meaning |
| --- | --- |
| `Infrastructure` | Buildings, furniture, roads, roofs, structural access |
| `Electrical` | Lighting, power, wiring, fans, generators, electrical safety |
| `Plumbing` | Leaks, taps, drains, toilets, water supply and pressure |
| `Cleanliness` | Waste, cleaning, spills, hygiene of shared spaces |
| `Safety` | Fire, blocked exits, unsafe equipment, security hazards |
| `Network / IT` | Wi-Fi, computers, printers, portals, AV and campus systems |
| `Academic` | Timetables, exams, registration, marks, courses, library materials |
| `Other` | Issues that do not fit the categories above |

The Phase 1 baseline has 24 rows per category (192 total) so the deterministic
holdout keeps every category in both train and test partitions. Phase 1.1 adds
16 focused examples to Electrical and 16 to Network / IT, making v2 deliberately
non-uniform (40 / 40 / 24 x 6) while preserving all eight exact labels.

### Phase 2 duplicate benchmark

`duplicate_detection_complaints.csv` has one row per complaint:

```text
complaint_id,group_id,description,category,location,split
```

- `complaint_id`: stable synthetic benchmark ID.
- `group_id`: the underlying issue. All variants of an issue share a group, and a
  group appears in exactly one of `train` or `test`.
- `description`, `category`, `location`: the comparison text and optional
  metadata. Every group keeps one category and one location.
- `split`: `train` or `test`. The split is by group, never by individual row.

The benchmark has 32 groups, three paraphrased variants per group, and four
groups per category. Sixteen groups are train and sixteen are test, giving 48
complaints in each split. The test side deliberately includes hard negatives that
share a category or location but describe a different underlying issue.

`duplicate_detection_pairs.csv` is generated from the complaints:

```text
pair_id,left_complaint_id,right_complaint_id,split,label,difficulty,same_category,same_location,token_overlap
```

- `label=1` means both complaints belong to the same `group_id`; `label=0` means
  they are different issues.
- Every unordered pair within a split is included, so there is no model-score or
  convenience sampling. Each split has 1,128 pairs: 48 positive and 1,080
  negative.
- `difficulty` is `duplicate` for positives. Negatives are `hard_negative` when
  they share a category or location or have token Jaccard ≥ 0.30,
  `medium_negative` when Jaccard ≥ 0.15, and `easy_negative` otherwise. Difficulty
  is metadata/analysis, not a model input.
- No group crosses the split, so a paraphrase of an issue cannot appear on both
  sides of threshold selection and evaluation.

All 96 complaints and all pair labels are synthetic and not human-verified. The
metadata sidecar records hashes, counts, group purity, and the pair-construction
rules. API schema and thresholds are documented in `DUPLICATE_DETECTION.md`.

### Phase 2.1 duplicate benchmark

Phase 2.1 reuses the 32 original issue groups with new split roles and adds 40
groups from `duplicate_detection_v2_additions.csv`. The generated benchmark has:

- 216 complaints in 72 issue groups, three variants per group;
- 72 complaints / 24 groups / three groups per category in each of train,
  validation, and test;
- 2,556 unordered pairs per split: 72 positive and 2,484 negative;
- 7,668 pairs total;
- 396 train, 594 validation, and 631 test hard negatives.

`duplicate_detection_v2_complaints.csv` uses the same schema as the Phase 2
complaint file, but `split` is `train`, `validation`, or `test`.
`duplicate_detection_v2_pairs.csv` uses the same pair schema as Phase 2.

`duplicate_detection_v2_test_freeze.json` records the test group IDs and SHA-256
fingerprints of the canonical test complaints and pairs before tuning. Training
verifies the fingerprint but does not score test. Evaluation verifies the dataset
hash, artifact dataset hash, test groups, and fingerprints before scoring. If the
freeze sidecar is missing, malformed, or inconsistent, training/evaluation stops.

The Phase 2.1 additions file is intentionally limited to the 40 new groups; the
builder merges it with the preserved Phase 2 complaints and rejects duplicate
group IDs or descriptions, malformed rows, unknown categories, group leakage,
missing category coverage, and split-role conflicts.

The 216 complaints are synthetic and not human-verified. Phase 2.1 metrics must
not be presented as production estimates.

## Validation

Run:

```powershell
python scripts/validate_dataset.py
python scripts/validate_dataset.py --dataset data/synthetic_complaints_v2.csv
python scripts/validate_dataset.py --dataset data/phase1_1_additions.csv --allow-partial
```

Validation rejects:

- a missing or malformed header;
- blank or malformed rows;
- missing descriptions;
- descriptions shorter than 10 or longer than 4,000 characters;
- missing, unknown, or duplicate category values;
- duplicate descriptions after Unicode/case/whitespace/punctuation normalization;
- a source column with a blank value;
- categories with no rows or only one independent example.

Training also computes near-duplicate groups with word-level TF-IDF cosine
similarity. Near-identical descriptions are kept in the same split; if a
near-duplicate group has conflicting category labels, training stops instead of
silently leaking an ambiguous example across train and test.

`scripts/build_phase1_1_dataset.py` rebuilds v2 deterministically and stops if a
new row creates a near-duplicate group crossing the frozen Phase 1 holdout. The
Phase 1 CSV is never modified.

The duplicate benchmarks have separate builders/validators:

```powershell
python scripts/build_duplicate_dataset.py
python scripts/build_duplicate_v2_dataset.py
```

The Phase 2.1 builder rejects a malformed header or record, duplicate complaint
IDs or descriptions, unknown categories, missing locations, groups with fewer than
two variants, groups whose variants disagree on category/location, groups crossing
train/validation/test, missing categories in any split, or fewer than three groups
per category per split. It then regenerates every within-split pair
deterministically, writes the v2 metadata and freeze sidecars, and verifies the
new freeze against the generated test partition. The Phase 2 builder's checks are
the same in spirit for its
two-way split: it rejects missing categories in either split and fewer than two
groups per category per split (needed for same-category hard negatives), then
regenerates its pair file and metadata sidecar. Loading either pair file verifies
pair IDs, labels, difficulty, split membership, token overlap, and completeness
against the complaint groups, so a hand-edited pair file cannot silently change
the evaluation.

## Adding authorized, anonymized real complaints

Do this only with an approved data-handling process:

1. Obtain authorization and a documented purpose for using campus complaint text.
2. Remove or generalize names, student/staff IDs, phone numbers, emails, room
   numbers tied to an individual, credentials, and any other unnecessary personal
   data before the text reaches this repository.
3. Have a human reviewer assign one supported category to each row. Do not use
   model predictions as ground-truth labels.
4. Deduplicate rows and review paraphrases so the same complaint is not counted
   twice.
5. Store the real data outside source control unless the project's privacy review
   explicitly allows it. Keep only an approved, access-controlled dataset path.
6. Create or update a sidecar with `"synthetic": false`, the provenance, consent
   or authorization reference, anonymization steps, label-review process, and a
   `human_verified` flag.
7. Run validation and training. Review per-class support; do not train on a class
   with only one independent example.
8. Version the dataset and model together. The metadata records the dataset
   SHA-256, so an evaluation cannot silently use a different file.

Never add real complaint text, PII, or secrets to a commit or test fixture
without explicit approval.

## Reproduction

From `safebunk-ml/`:

```powershell
python scripts/validate_dataset.py
python scripts/validate_dataset.py --dataset data/synthetic_complaints_v2.csv
python scripts/train.py --model-version 0.1.0
python scripts/evaluate.py

python scripts/build_phase1_1_dataset.py
python scripts/train_phase1_1.py
python scripts/evaluate.py --model-dir artifacts/category-classifier/v0.2.0
python scripts/analyze_errors.py --model-dir artifacts/category-classifier/v0.2.0 --output artifacts/category-classifier/v0.2.0/error_analysis.json

python scripts/build_duplicate_dataset.py
python scripts/evaluate_duplicates.py

python scripts/build_duplicate_v2_dataset.py
python scripts/train_duplicate_detector.py
python scripts/evaluate_duplicates_v2.py
```

Phase 1 uses a category-stratified grouped holdout with a fixed random seed.
Phase 1.1 trains on the other v2 rows and evaluates on the untouched 48-row
Phase 1 holdout. The baseline and candidate artifacts are written under
`artifacts/category-classifier/v0.1.0/` and
`artifacts/category-classifier/v0.2.0/` respectively. See `ERROR_ANALYSIS.md`.

The Phase 2 duplicate benchmark rebuilds its 2,256 pairs and metadata
deterministically, then evaluates with a train-only threshold selection and
separate train-only vocabulary stress test. Phase 2.1 rebuilds 7,668 pairs and
the frozen-test sidecar, fits the vectorizer on train only, selects features and
thresholds on validation only, and scores test once. See
`DUPLICATE_DETECTION.md`, `artifacts/duplicate-detector/v0.1.0/evaluation.json`,
and `artifacts/duplicate-detector/v0.2.0/evaluation.json`.
