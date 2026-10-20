# PULSE — Current Work Status & Pending Items

Last updated: 2026-10-20

Project direction: **AI/ML Powered Smart Campus Issue Reporting System** on top of the
existing attendance app. Approved plan lives in the session record; schema design is in
`docs/REPORTS_SCHEMA.md`. Attendance/Subjects functionality is untouched and stays until
Reports is fully functional.

## What is DONE

### Phase 0 — safety prep (complete)
- **`.env` untracked**: `safebunk-backend/.env` removed from git with `git rm --cached`
  (local file intact). **Secrets are still exposed in git history** — rotation of
  `BACKEND_JWT_SECRET`, `SESSION_ENCRYPTION_KEY`, `GOOGLE_CLIENT_ID` is a **separate,
  not-yet-performed security task**. History was NOT rewritten (per approval).
- **Baseline test fix**: date-dependent `timetable-watcher.service.spec.ts` now uses
  Jest fake timers (the service falls back to `new Date()`, so mocking only `Date.now`
  broke it on any day other than the fixture date).
- **`docs/REPORTS_SCHEMA.md`** — full schema design: entities, status state machine,
  AI-column rules, Postgres migration notes, API/ownership contract.

### Phase 1 — Reports backend foundation (code complete, pushed at `e6b4ef2`)
- **Prisma 6.19.3 + SQLite** added (`prisma/schema.prisma`), migration
  `20261006134749_init_reports` applied. Models: `Report`, `ReportEvent` (append-only,
  API deferred to Phase 5), `Category`, `Location`, `Department` (lookup tables created
  empty). `dev.db` is gitignored.
- **`src/prisma/`** — global `PrismaModule` + `PrismaService` (connect/disconnect lifecycle).
- **`src/reports/`** — new module, registered in `app.module.ts` (the only existing file
  with logic-adjacent change: 2 import lines + 2 array entries):
  - `POST /api/reports` — create; `GET /api/reports/my`; `GET /api/reports/:id`.
  - Ownership **exclusively** from `AuthGuard` session (`user.studentId`); `CreateReportDto`
    has no `studentId` field, so the global whitelist/`forbidNonWhitelisted` pipe rejects it.
    Cross-student `GET /:id` → 404 (same as missing — no existence oracle).
  - Initial status `SUBMITTED`, `createdAt/updatedAt/resolvedAt`, all `ai*` fields `null`,
    `assignedDepartment` null.
  - `report-status.ts` — explicit, unit-tested state machine:
    `SUBMITTED→ASSIGNED|REJECTED`, `ASSIGNED→IN_PROGRESS`, `IN_PROGRESS→RESOLVED`.
    Phase 1 shipped read-only; Phase 6 now adds guarded assignment/workflow endpoints
    (see `docs/ISSUE_HANDLING.md`).
  - Routing = documented **rules-based stub returning null**. No ML, no model, no AI claimed.
- **Verification**: `npm test` **68/68 pass** (8 suites), `npx tsc --noEmit` clean,
  `nest build` OK, `prisma migrate dev` OK. Swagger at `/docs`.
- **Not yet done for Phase 1**: live HTTP smoke test of the 3 routes (server boot hung
  under the tool shell — needs a manual `npm run start:prod` + curl, incl. IDOR check).

### Backend (earlier — notifications) — NestJS + Firebase Admin
- **JSON persistence**: `src/common/store/` — `JsonStoreService` + `StoreModule`
  (sessions, devices, preferences, dedup events, watcher snapshots, planned reminders).
  Still owns all non-report data; Reports uses its own DB, untouched.
- **Notifications module**: register/unregister device, preferences GET+PUT, status, test
  (all behind `AuthGuard`); `FcmService` (firebase-admin v14, per-type TTL, channels,
  invalid-token deactivation); `NotificationRuleService` (pure, tested);
  `NotificationContentService` (roast/neutral copy); `NotificationSchedulerService`
  (1-min cron, TTL drop + retry); `AttendanceWatcherService`; `TimetableWatcherService`.
- Auth sessions persist to the store and survive restarts; `POST /api/auth/logout` works.
- Delivery: events marked processed only after FCM accepts them.

### Flutter (`lib/`) — unchanged in Phases 0/1
- **`pulse_backend_service.dart`** — backend client (login/logout, device registration,
  preference sync), no-op without `PULSE_BACKEND_URL` dart-define.
- **`fcm_setup.dart`** — `FcmController`: permission, token capture, rotation
  re-registration, foreground rendering from server payload, tap-through navigation.
- **41 `flutter test` pass**; `flutter analyze` clean.
- Navigation is still Dashboard / **Subjects** / Analytics / Settings — Reports tab not
  started (Phase 2+), Subjects intentionally kept.

## PENDING / TO-DO

### Reports auth/session (fixed 2026-10-20)
- The installed Android app was running an **older build**: its error text
  (`Reports need the PULSE backend. Build with ...`) no longer exists in the current
  source. The old build's invalid backend URL made `/api/auth/login` fail.
- Backend login is now **awaited during Linways login**, so a fresh login cannot leave
  Reports racing a half-finished background request. A backend `401` clears the stale
  token; logout clears the token, student id and cached gender.
- **After installing the new build, log out and sign in once.** The previous install has
  Linways cookies but no PULSE backend token; the token can only be created from a fresh
  login because the password is never persisted.
- Clean Android run (backend on port 3000, same Wi-Fi, Node allowed through the firewall):
  ```powershell
  # terminal 1 - backend
  cd safebunk-backend
  npm run start:prod

  # terminal 2 - app
  adb shell am force-stop com.example.safebunk_v2
  flutter clean
  flutter pub get
  flutter devices
  flutter run -d <device-id> --dart-define=PULSE_BACKEND_URL=http://10.133.160.180:3000
  ```
  `10.133.160.180` was the PC Wi-Fi address at the time; re-check with `ipconfig` and
  replace it if the router assigned a new one. For USB, `adb reverse tcp:3000 tcp:3000`
  and use `http://localhost:3000`; for the emulator use `http://10.0.2.2:3000`.
  The define is compile-time: hot reload/restart does **not** change it.

### Immediate — finish Phase 1 verification
- [ ] Boot backend (`npm run start:prod`) and smoke test:
      `POST /api/reports`, `GET /api/reports/my`, `GET /api/reports/:id`,
      cross-student IDOR → 404, Swagger shows the 3 routes, existing routes still respond.
- [ ] **Fix lint**: `npm run lint` fails because `eslint` is not installed and no eslint
      config exists anywhere in the repo (pre-existing, unrelated to Reports).

### Security (separate task, approved as phase 0 remainder)
- [ ] Rotate `BACKEND_JWT_SECRET`, `SESSION_ENCRYPTION_KEY`, `GOOGLE_CLIENT_ID`.
- [ ] Decide on history purge (`git filter-repo`) — destructive, explicitly deferred.
- [x] Add focused login rate limiting for student and staff/admin login (per-IP and
      per-account, in-memory).
- [ ] Back the login limiter with a shared store before a multi-instance deployment,
      and add permanent account lockout if the deployment policy requires it.
- [ ] `npm run lint`/CI: no CI pipeline exists at all.

### Phase 2+ (awaiting explicit approval — do NOT start automatically)
- [ ] Phase 2: report creation flow (Flutter UI) — after Phase 1 smoke test.
- [ ] Phase 3: photo storage + validation.
- [ ] Phase 4: Flutter Reports tab replacing Subjects in `main_shell_screen.dart`
      (Subjects stays until Reports list+detail verified).
- [ ] Phase 5: report timeline endpoints (`GET /api/reports/:id/events`) — schema ready.
- [ ] Phase 6: staff roles + admin auth path + status/assign endpoints (state machine ready).
  - [x] Staff/admin identities, role guards, read-only staff report views, admin-only
        account provisioning, and first-admin CLI (feature branch, pending review).
  - [x] Focused login throttling for student and staff/admin login (per-IP and
        per-account, in-memory, fixed 15-minute window).
  - [x] Staff/admin Flutter login, secure session restore/logout, and role-based
        navigation (STAFF: reports/account; ADMIN: plus admin-only staff list).
  - [x] Staff issue handling (feature branch, implemented 2026-10-20): admin
        assignment/reassignment/rejection, staff accept/progress/resolve, lifecycle
        events, assigned-only staff views, and assignment-authorized staff photo access.
  - [ ] Staff deactivation/role-change API (DB changes already revoke the next request).
- [ ] Phase 7–10: rules-based routing → real ML (needs labeled data), priority prediction,
      duplicate detection, campus analytics. FastAPI ML service deferred; NestJS only.
- [ ] Phase 11: report events → existing FCM `dispatchEvent()`.
- [ ] Phase 12: conversational AI assistant.

### Older pending items (notifications, still open)
- [ ] Download service-account JSON for `pulse-5b489` → `FCM_SERVICE_ACCOUNT_PATH`
      (backend runs in dev mode without it).
- [ ] Backend deploy + pinned CORS/HTTPS + persistent `PULSE_STORE_PATH`.
- [ ] Run Flutter with the correct local backend origin:
      `--dart-define=PULSE_BACKEND_URL=http://localhost:3000` (web/Windows),
      `http://10.0.2.2:3000` (Android emulator), or
      `http://YOUR_PC_LAN_IP:3000` (physical Android device). Do not include `/api`.
- [ ] 10-case E2E notification test matrix (see git history of this file).

## Notes
- Without `PULSE_BACKEND_URL` the app behaves exactly as before (local-only notifications).
- `npm run lint` was already broken before this work (eslint never in devDependencies) —
  pre-existing, not introduced by the Reports work.
- Nothing in attendance, dashboard, analytics, timetable, auth or notifications was
  modified for Phases 0/1 except: `.gitignore` (+db entries), `package.json` (+prisma
  deps/scripts), `app.module.ts` (+2 module imports), and the isolated test fix.
