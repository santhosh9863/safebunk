# PULSE Reports — Database & Schema Design

Status: approved for Phase 1 (backend foundation).
Scope: design only. No ML claims. Timeline/event APIs deferred to Phase 5; status mutation APIs deferred to Phase 6.

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
| imageUrl | String? | yes | Phase 3 photo storage |
| priority | String | no | `LOW \| MEDIUM \| HIGH \| CRITICAL`, default `MEDIUM` (human-confirmed) |
| status | String | no | see state machine; initial `SUBMITTED` |
| assignedDepartment | String? | yes | rules-based routing may fill later |
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

Indexes: `@@index([studentId, createdAt])`, `@@unique([code])`.

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

### Lookup tables (Phase 1 creates empty tables; populated later)

- `Category(id, name, active)` — report categories.
- `Location(id, block, floor, room, label)` — selectable places.
- `Department(id, name, active)` — maintenance, IT, technical support, hostel admin, etc.

Reports in Phase 1 accept `category`/`location` as strings (per approved API), so these
tables are forward-compatible placeholders and are not written to yet.

## 5. Status state machine (explicit)

```
SUBMITTED  → ASSIGNED     (staff only, Phase 6)
SUBMITTED  → REJECTED     (staff only, Phase 6)
ASSIGNED   → IN_PROGRESS  (staff only, Phase 6)
IN_PROGRESS→ RESOLVED     (staff only, Phase 6)
```

- Initial status on create: `SUBMITTED`.
- Terminal: `RESOLVED`, `REJECTED`.
- `resolvedAt` set only when reaching `RESOLVED`.
- Any other transition is invalid (`INVALID_TRANSITION`).
- **No status mutation endpoints exist in Phase 1.** The state machine is implemented as a
  pure, unit-tested module so Phase 6 only has to wire guarded endpoints to it.

## 6. AI field rules

- AI columns (`ai*`) are nullable and written only by the AI/rules layer (Phase 7+).
- Phase 1 leaves every `ai*` column `null`. **No AI functionality is claimed or simulated.**
- Human-confirmed `priority`/`category`/`assignedDepartment` are never derived from AI
  columns implicitly; staff overrides record `aiOverrideBy`/`aiOverrideAt`.
- Routing in Phase 1 is a documented **rules-based stub** returning `assignedDepartment = null`.

## 7. API contract (Phase 1)

```
POST /api/reports          create (AuthGuard)
GET  /api/reports/my       list own reports (AuthGuard)
GET  /api/reports/:id      get one owned report (AuthGuard)
```

Authorization rule: `studentId` always comes from the authenticated session
(`request.user.studentId` set by `AuthGuard`). Any `studentId` in a request body/query is
ignored. `GET /api/reports/:id` returns 404 when the report belongs to another student
(no existence leak differences beyond 404, no cross-student reads).

Response envelope: existing `ApiResponse<T>` (`{ success, data, message, statusCode }`).

## 8. Future phases (not in schema yet)

- Phase 5: `GET /api/reports/:id/events` timeline.
- Phase 6: staff role model + status/assign endpoints writing `ReportEvent`.
- Phase 7+: ML service fills `ai*` columns via NestJS (Flutter never talks to ML directly).
