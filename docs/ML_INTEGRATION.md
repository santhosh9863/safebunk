# PULSE ML Integration (Phases 3-4)

Status: backend integration and Flutter suggestion UI implemented (2026-10-21).

The NestJS backend calls the isolated FastAPI service in `safebunk-ml/`
through a private server-to-server client. Flutter calls only NestJS; the
Python service URL and internal token never reach the app. Predictions never
mutate a report.

## Environment

Configure both services with the same long random secret.

NestJS (`safebunk-backend/.env`):

```dotenv
PULSE_ML_SERVICE_URL=http://127.0.0.1:8001
PULSE_ML_SERVICE_TOKEN=replace-with-a-long-random-secret
# Optional, bounded settings:
PULSE_ML_TIMEOUT_MS=2000
PULSE_ML_MAX_RETRIES=1
```

FastAPI (`safebunk-ml/`):

```powershell
$env:PULSE_ML_API_TOKEN = "replace-with-a-long-random-secret"
$env:PULSE_ML_MODEL_DIR = "artifacts\category-classifier\v0.1.0"
$env:PULSE_ML_DUPLICATE_MODEL_DIR = "artifacts\duplicate-detector\v0.2.0"
.\.venv\Scripts\python.exe -m uvicorn pulse_ml.api:app --host 127.0.0.1 --port 8001
```

The backend requires both `PULSE_ML_SERVICE_URL` and
`PULSE_ML_SERVICE_TOKEN`. If either is missing, or the URL is not a valid
HTTP(S) URL, ML suggestions return a safe `available: false` result; no ML call
is attempted. The ML service enforces `PULSE_ML_API_TOKEN` on prediction routes
when it is set. `GET /health` stays open for local liveness checks.

`PULSE_ML_TIMEOUT_MS` is clamped to 100-10,000 ms (default 2,000).
`PULSE_ML_MAX_RETRIES` is clamped to 0-2 (default 1). Only idempotent read-only
prediction calls are retried; input 4xx responses are not retried.

## API contracts

All routes require the existing PULSE Bearer session. The backend derives the
student or staff identity from that session; it never accepts a client-supplied
user id or role.

### Category suggestion

`POST /api/ml/category-suggestion` (student session)

```json
{
  "description": "Water is leaking from a pipe under the sink."
}
```

```json
{
  "success": true,
  "data": {
    "available": true,
    "suggestionOnly": true,
    "reason": null,
    "message": "Category suggestion only; no report fields were changed.",
    "category": "Plumbing",
    "confidence": 0.38,
    "modelVersion": "0.1.0",
    "manualReviewRecommended": false,
    "decision": "predict",
    "threshold": 0.2
  },
  "message": "Suggestion only; no report was changed.",
  "statusCode": 200
}
```

`confidence` is the classifier's maximum `predict_proba` score, not a calibrated
probability. `decision: "abstain"` and `manualReviewRecommended: true` mean the
client must keep the existing category or ask a human to decide. The route never
writes `category`, `aiCategory`, `priority`, `status`, or any other report field.

### Pre-submission duplicate preview

`POST /api/ml/duplicate-suggestions/preview` (student session)

The app uses this optional route before submitting a new report, because no
report id exists yet. It compares the draft description/category/location with
only the authenticated student's earlier reports. It never creates a report and
does not block submission. `reportId` is `null` in the response.

```json
{
  "description": "The library reading-room lights keep flickering.",
  "category": "Electrical",
  "location": "Main Library",
  "maxCandidates": 5
}
```

`category` and `location` are optional. An unsupported/free-text category is
omitted before the ML call, exactly like the report-id routes. The response
shape is otherwise identical to the student report-id route.

### Student duplicate suggestions

`POST /api/ml/duplicate-suggestions/:reportId` (student session)

```json
{
  "maxCandidates": 5
}
```

The source report must belong to the authenticated student. Only that student's
other reports are compared; another student's report is indistinguishable from a
missing one (`404`). This keeps the existing ownership boundary and avoids
returning another student's report details.

```json
{
  "success": true,
  "data": {
    "available": true,
    "suggestionOnly": true,
    "action": "suggestion_only",
    "reason": null,
    "reportId": "cm...",
    "decision": "uncertain",
    "candidates": [
      {
        "reportId": "cm...",
        "reportCode": "PULSE-1042",
        "title": "Flickering library lights",
        "status": "SUBMITTED",
        "category": "Electrical",
        "location": "Main Library",
        "similarityScore": 0.47,
        "rankingScore": 0.51,
        "categoryMatch": true,
        "locationMatch": true,
        "reasons": ["similar description text", "same category: Electrical"]
      }
    ],
    "duplicateThreshold": 0.5,
    "uncertainThreshold": 0.4,
    "similarityMetric": "tfidf_cosine_similarity",
    "rankingMetric": "cosine_similarity_with_metadata_support",
    "modelVersion": "0.2.0",
    "scoreNote": "Cosine similarity plus a small category/location support boost. This is a ranking score, not a calibrated probability.",
    "manualReviewRecommended": true,
    "existingComplaintsEvaluated": 4,
    "message": "Potential duplicates found; these are suggestions only and require human review."
  },
  "message": "Suggestion only; no report was changed.",
  "statusCode": 200
}
```

`decision` is `match`, `uncertain`, or `no_match`. Scores are ranking scores, not
probabilities or confidence percentages. Duplicate suggestions never merge,
reject, or modify reports.

### Staff/admin duplicate suggestions

`POST /api/staff/ml/duplicate-suggestions/:reportId`
(`STAFF` or `ADMIN` session)

- `STAFF` may request suggestions only for a report assigned to them, and the
  comparison set is their own assigned reports.
- `ADMIN` may request suggestions for any report, and the comparison set is all
  reports.
- An unauthorized staff request returns `404`, matching the existing staff report
  visibility behavior.

The response shape is identical to the student duplicate route.

## Failure behavior

These are optional suggestion endpoints, so a configured-but-unavailable ML
service returns HTTP `200` with an explicit safe envelope:

```json
{
  "success": true,
  "data": {
    "available": false,
    "suggestionOnly": true,
    "reason": "ml_unavailable",
    "message": "ML suggestions are temporarily unavailable. No report data was changed.",
    "category": null,
    "confidence": null,
    "modelVersion": null,
    "manualReviewRecommended": true,
    "decision": "unavailable",
    "threshold": null
  },
  "statusCode": 200
}
```

Duplicate failures use the same `available: false` pattern with
`decision: null`, `candidates: []`, and `reason` set to one of:

- `ml_not_configured`: URL/token missing or invalid.
- `ml_timeout`: the configured timeout elapsed.
- `ml_unavailable`: connection failure or upstream 5xx after bounded retries.
- `ml_request_rejected`: upstream 4xx (for example a contract/input mismatch).
- `ml_invalid_response`: upstream returned an unexpected payload.

No raw upstream body, URL, or token is returned to the client. Invalid request
bodies (blank/oversized descriptions, bad candidate limits, extra fields) are
rejected by NestJS validation with HTTP `400` before any ML call.

## Privacy and mutation guarantees

- The ML payload contains complaint text, report IDs, category, and location
  only. It never contains student ids, names, roles, session cookies, or auth
  tokens.
- Category support is sent only when the stored category is one of the eight
  supported PULSE labels. Custom/free-text categories are omitted so the Python
  validator cannot reject the whole request.
- The module performs report reads only. No `create`, `update`, `delete`, or
  report-event write is performed by any suggestion route, including the
  pre-submission preview.
- Report creation, viewing, photos, auth, attendance, and notifications do not
  depend on ML and continue to work when it is down.
- Flutter sends only complaint text/category/location to NestJS. It never has
  the internal ML URL or shared token, and client-side role checks are never
  used as authorization.

## Verification

```powershell
cd safebunk-backend
npx tsc --noEmit
npm test -- --runInBand
npm run build

cd ..\safebunk-ml
.\.venv\Scripts\python.exe -m pytest
```

## Limitations

- The category classifier and duplicate detector are trained on small synthetic
  datasets, not real campus data. Their metrics are not production evidence.
- Category confidence is uncalibrated.
- Student duplicate suggestions compare only the student's own reports; staff
  compare only their assigned reports. This is an intentional privacy scope, not
  campus-wide duplicate detection.
- Duplicate checks are optional and manually triggered. A match is a ranking
  signal, never a confirmation, and never blocks submission or changes status.
- There is no deployment monitoring, drift detection, or rate limiting specific
  to ML suggestions yet.
