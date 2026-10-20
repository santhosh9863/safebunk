# Staff Issue Handling

Status: implemented (2026-10-20). Backend and Flutter tests pass; no ML is involved.

## Workflow

```
SUBMITTED -> ASSIGNED -> IN_PROGRESS -> RESOLVED
     |           |            |
     +-----------+------------+--> REJECTED (ADMIN only, reason required)
```

- `RESOLVED` and `REJECTED` are terminal. They cannot be assigned, accepted,
  resolved, or rejected again.
- Initial assignment moves `SUBMITTED` to `ASSIGNED`.
- Reassignment preserves `ASSIGNED` or `IN_PROGRESS`; it does not regress work.
- STAFF can accept only their own `ASSIGNED` report.
- STAFF can add internal progress notes while their report is `ASSIGNED` or
  `IN_PROGRESS`.
- STAFF can resolve only their own `IN_PROGRESS` report, with required notes.
- ADMIN can reject any non-terminal report with a required reason.

All transitions are checked on the server. Client-supplied role or staff identity
is never trusted.

## Assignment rules

- Only active accounts with role `STAFF` can be assigned.
- ADMIN accounts and inactive STAFF accounts are rejected.
- Department is an optional free-text label on the report.
- The assigned staff id, assignment time, resolution notes, rejection reason, and
  append-only status history are stored in the database.

## API

All routes require a staff/admin Bearer session and the appropriate role.

| Method | Route | Access | Purpose |
|---|---|---|---|
| GET | `/api/staff/reports` | STAFF, ADMIN | STAFF: assigned reports only; ADMIN: all reports |
| GET | `/api/staff/reports/:id` | STAFF, ADMIN | Detail + full status/progress history |
| GET | `/api/staff/reports/:id/photo` | STAFF, ADMIN | Authorized report photo download |
| POST | `/api/staff/reports/:id/assign` | ADMIN | Assign/reassign to an active STAFF account |
| POST | `/api/staff/reports/:id/accept` | STAFF | `ASSIGNED -> IN_PROGRESS` |
| POST | `/api/staff/reports/:id/progress` | STAFF | Add an internal progress note |
| POST | `/api/staff/reports/:id/resolve` | STAFF | `IN_PROGRESS -> RESOLVED` with notes |
| POST | `/api/staff/reports/:id/reject` | ADMIN | Reject with a recorded reason |

## Authorization and privacy

- A STAFF request for another staff member's report (or an unassigned report)
  returns `404`, the same as a missing report, so report existence is not leaked.
- Student report reads remain scoped to `studentId` from the verified session.
- Student history exposes status events and resolution/rejection reasons but
  excludes internal `PROGRESS_NOTE` events and all staff ids/usernames.
- Staff report photo access is checked against the assignment before attachment
  bytes are read. ADMIN can read any report photo.
- The student attachment endpoint remains unchanged.

## Flutter UI

- STAFF: **Assigned**, **In Progress**, **Resolved** tabs; detail shows category,
  location, priority, description, photo, assignment, resolution/rejection notes,
  and history. Actions: accept, add progress note, mark resolved.
- ADMIN: all-report queue with filters; detail adds assign/reassign and reject
  actions, and shows the assigned staff member and progress history.
- Loading, empty, success, refresh, and error states are implemented.

## Verification

- Backend: `npx tsc --noEmit`, `npx nest build`, `npm test -- --runInBand`
  (24 suites / 171 tests).
- Flutter: `flutter test` (114 tests) and `flutter analyze` (clean).
- Prisma migration `20261020131052_staff_issue_handling` applied; migration status
  is up to date.

## Not included

- ML-based routing, priority prediction, duplicate detection, or analytics.
- Staff deactivation/role-change APIs.
- FCM notifications for report lifecycle changes.
