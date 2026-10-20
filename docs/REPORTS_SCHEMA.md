# PULSE Reports — Database & Schema Design

Status: approved for Phase 1 (backend foundation).
Scope: schema design + implemented report/staff workflow. Timeline is embedded in
report detail; assignment/status mutations are implemented (see
`docs/ISSUE_HANDLING.md`). No ML claims.

## 1. Goals

- Store campus issue reports with ownership, status history and room for AI outputs.
- Local development on **SQLite via Prisma**; straightforward migration to **PostgreSQL** later.
- AI predictions stored separately from human-confirmed values; staff can override.
- Append-only status history (`ReportEvent`) instead of overwriting status.

## 2. Technology

| Concern | Choice | Notes |
|---|---|---|
| ORM | Prisma | migrations via `prisma migrate` |
| Dev DB | SQLite (`dev.db`) | file-based, no server needed |
| Target DB | PostgreSQL | same schema, provider swap + `migrate` |
| Store isolation | separate DB | existing `JsonStoreService` (auth/notifications) is untouched |

Prisma runs as a single instantiation per process (`PrismaService`), extends `PrismaClient`,
and is shut down on `onModuleDestroy`. The existing JSON store continues to own
`authSessions`, `devices`, `preferences`, `processedEvents`, `attendanceSnapshots`,
`timetableSnapshots`, `plannedReminders`.

## 3. PostgreSQL migration notes

Keep the schema Postgres-friendly from day one:

- Use `@default(cuid())` string IDs (portable, no auto-increment assumptions).
- Use `DateTime` (Prisma maps to `DATETIME`/`TIMESTAMP(3)`).
- Use enums as Prisma `enum` blocks (SQLite ignores enum constraints, Postgres enforces them).
- Avoid SQLite-only functions/expressions in queries.
- Text fields: no `@db.Text` overrides (SQLite ignores them, Postgres accepts them).

Migration path: change `provider = "postgresql"` in `schema.prisma`, set `DATABASE_URL`,
run `prisma migrate deploy`. Column types map 1:1 for the types used here.

## 4. Entities

### Report

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | String (cuid) | no | PK |
| code | String | no | unique, human-readable `PULSE-1042` |
| studentId | String | no | owner identity, from **AuthGuard session only** |
| title | String | no | max 160 |
| description | String | no | max 4000 |
| category | String? | yes | free-form/normalized label (Phase 2 adds a dictionary) |
| location | String? | yes | free text: `Block B · 2nd Floor` |
| imageUrl | String? | yes | server-derived reference `/api/reports/attachments/<id>` (Phase 3); never client-supplied |
| priority | String | no | `LOW \| MEDIUM \| HIGH \| CRITICAL`, default `MEDIUM` (human-confirmed) |
| status | String | no | see state machine; initial `SUBMITTED` |
| assignedDepartment | String? | yes | rules-based routing may fill later |
| assignedStaffId | String? | yes | FK → StaffUser, `SET NULL` if the account is deleted |
| assignedAt | DateTime? | yes | last assignment/reassignment time |
| resolutionNotes | String? | yes | required when STAFF resolves; student-visible |
| rejectionReason | String? | yes | required when ADMIN rejects; student-visible |
| aiCategory | String? | yes | AI prediction — never trusted for authz |
| aiPriority | String? | yes | AI prediction |
| aiConfidence | Float? | yes | 0..1 |
| aiDepartment | String? | yes | AI/rules routing recommendation |
| aiReasons | String? | yes | JSON array of explainability strings |
| aiOverrideBy | String? | yes | staff id that overrode AI |
| aiOverrideAt | DateTime? | yes | |
| createdAt | DateTime | no | `@default(now())` |
| updatedAt | DateTime | no | `@updatedAt` |
| resolvedAt | DateTime? | yes | set on `RESOLVED` |

Indexes: `@@index([studentId, createdAt])`, `@@index([assignedStaffId, status])`,
`@@index([status])`, `@@unique([code])`.

### ReportEvent (append-only, created in Phase 1, API in Phase 5)

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | String (cuid) | no | PK |
| reportId | String | no | FK → Report, cascade delete |
| type | String | no | see event types |
| actorId | String? | no-default | studentId or staff id; system events use `system` |
| actorRole | String | no | `STUDENT \| STAFF \| ADMIN \| SYSTEM` |
| remark | String? | yes | staff comment |
| aiPayload | String? | yes | JSON snapshot of predictions at event time |
| createdAt | DateTime | no | `@default(now())` |

Index: `@@index([reportId, createdAt])`.

### Attachment (added in Phase 3)

Image **bytes live in object storage** (Firebase Storage); this table stores only
ownership + object metadata. There is deliberately no local-disk storage path.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | String (cuid) | no | PK; also used to derive the object path |
| studentId | String | no | uploader identity, from **AuthGuard session only** |
| reportId | String? | yes | FK → Report, `onDelete: SetNull`; null until linked |
| storagePath | String | no | unique object key `reports/<studentId>/<id>.<ext>` |
| contentType | String | no | sniffed `image/jpeg \| image/png \| image/webp` |
| size | Int | no | bytes |
| createdAt | DateTime | no | `@default(now())` |

Indexes: `@@index([studentId, createdAt])`, `@@index([reportId])`, unique `storagePath`.

Lifecycle / orphan control:

- Upload creates an unlinked row (`reportId = null`) after the object is written;
  if the DB write fails the object is deleted.
- Creating a report with `attachmentId` atomically claims the row
  (`updateMany` where `reportId = null`); the report stores the derived
  `imageUrl`. A lost race rolls the report back.
- A student may delete their own unlinked attachment; once linked it is immutable here.
- Foreign or unknown attachment ids are indistinguishable from missing (404 / bad request).

### Lookup tables (Phase 1 creates empty tables; populated later)

- `Category(id, name, active)` — report categories.
- `Location(id, block, floor, room, label)` — selectable places.
- `Department(id, name, active)` — maintenance, IT, technical support, hostel admin, etc.

Reports in Phase 1 accept `category`/`location` as strings (per approved API), so these
tables are forward-compatible placeholders and are not written to yet.

## 5. Status state machine (explicit)

```
SUBMITTED  → ASSIGNED     (ADMIN assign; implemented)
SUBMITTED  → REJECTED     (ADMIN reject with reason; implemented)
ASSIGNED   → IN_PROGRESS  (assigned STAFF accepts; implemented)
ASSIGNED   → REJECTED     (ADMIN reject with reason; implemented)
IN_PROGRESS→ RESOLVED     (assigned STAFF, resolution notes required; implemented)
IN_PROGRESS→ REJECTED     (ADMIN reject with reason; implemented)
```

- Initial status on create: `SUBMITTED`.
- Terminal: `RESOLVED`, `REJECTED`.
- `resolvedAt` set only when reaching `RESOLVED`.
- Any other transition is invalid (`INVALID_TRANSITION`).
- ADMIN reassignment keeps `ASSIGNED`/`IN_PROGRESS` and appends `REASSIGNED`.
- Workflow endpoints and authorization are documented in
  `docs/ISSUE_HANDLING.md`.

## 6. AI field rules

- AI columns (`ai*`) are nullable and written only by the AI/rules layer (Phase 7+).
- Phase 1 leaves every `ai*` column `null`. **No AI functionality is claimed or simulated.**
- Human-confirmed `priority`/`category`/`assignedDepartment` are never derived from AI
  columns implicitly; staff overrides record `aiOverrideBy`/`aiOverrideAt`.
- Routing in Phase 1 is a documented **rules-based stub** returning `assignedDepartment = null`.

## 7. API contract

```
POST   /api/reports                     create (AuthGuard)
GET    /api/reports/my                  list own reports (AuthGuard)
GET    /api/reports/:id                 get one owned report + safe history (AuthGuard)
POST   /api/reports/attachments         upload a photo, multipart "file" (AuthGuard)
GET    /api/reports/attachments/:id     download own photo, bytes (AuthGuard)
DELETE /api/reports/attachments/:id     remove own not-yet-linked photo (AuthGuard)

GET    /api/staff/reports               assigned-only (STAFF) / all (ADMIN)
GET    /api/staff/reports/:id           detail + full history (assigned STAFF/ADMIN)
GET    /api/staff/reports/:id/photo     authorized photo bytes (assigned STAFF/ADMIN)
POST   /api/staff/reports/:id/assign    assign/reassign (ADMIN)
POST   /api/staff/reports/:id/accept    ASSIGNED -> IN_PROGRESS (STAFF)
POST   /api/staff/reports/:id/progress  internal progress note (STAFF)
POST   /api/staff/reports/:id/resolve   IN_PROGRESS -> RESOLVED (STAFF)
POST   /api/staff/reports/:id/reject    reject with reason (ADMIN)
```

Authorization rule: `studentId` always comes from the authenticated session
(`request.user.studentId` set by `AuthGuard`). Any `studentId` in a request body/query is
ignored. `GET /api/reports/:id` returns 404 when the report belongs to another student
(no existence leak differences beyond 404, no cross-student reads). Staff report access
comes from `StaffAuthGuard`; a STAFF account can only read/update its own assignments,
and another staff member's report returns 404. See `docs/ISSUE_HANDLING.md`.

Upload validation: multipart field `file` only; max 5 MB; the true type is sniffed
from magic bytes (JPEG/PNG/WebP) — a spoofed `Content-Type` is rejected. Reports
reference a photo via `attachmentId` (in `POST /api/reports`), never a client URL;
the stored `imageUrl` is derived server-side.

Response envelope: existing `ApiResponse<T>` (`{ success, data, message, statusCode }`).

### Storage prerequisite (Phase 3)

Object storage uses **Supabase Storage** (private bucket) via the server-side
service-role key. Configuration comes from the backend environment:

- `SUPABASE_URL` — project URL.
- `SUPABASE_SERVICE_ROLE_KEY` — backend only; never exposed to Flutter or committed.
- `SUPABASE_STORAGE_BUCKET` — defaults to `report-attachments`.

The bucket is **private** and accessed only by the NestJS backend (which mediates
upload/download/delete behind `AuthGuard` + ownership). Flutter never talks to Supabase
directly. When any of these vars is missing the upload/download endpoints return **503** —
there is no insecure or local-disk fallback.

## 8. Future phases (not in schema yet)

- Phase 5: standalone `GET /api/reports/:id/events` timeline. History is currently
  embedded in report detail responses.
- Phase 6: implemented — staff assignment/workflow endpoints write `ReportEvent` rows.
- Phase 7+: ML service fills `ai*` columns via NestJS (Flutter never talks to ML directly).
