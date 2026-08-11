# PULSE — Push Notification Architecture: Work Status & Pending Items

Last updated: 2026-08-11

## What is DONE

### Backend (`safebunk-backend/`) — NestJS + Firebase Admin
- **JSON persistence layer**: `src/common/store/` — `JsonStoreService` (file-based store for dedup markers, notification log, devices, sessions, watcher snapshots, planned reminders) + `StoreModule`.
- **Notifications module** (`src/notifications/`):
  - `register-device` / `unregister-device` / `preferences` (GET+PUT) / `status` / `test` endpoints in `notifications.controller.ts`, all behind `AuthGuard`.
  - `FcmService` — sends pushes via `firebase-admin` (v14 modular API), data + notification payloads (`type`, `eventId`, `studentId`, `subjectName`), `priority: high`, **per-type TTL** and correct Android channel. Invalid tokens are deactivated.
  - `NotificationRuleService` — TS port of the Flutter rule engine (marked/drop/zone/milestone events), pure + unit tested.
  - `NotificationContentService` — roast/neutral content templates (same copy as Flutter).
  - `NotificationSchedulerService` — 1-minute cron that fires due reminders, **drops reminders whose TTL window has passed** (a "starts in 5 minutes" never arrives late), keeps undelivered ones pending for retry.
  - `AttendanceWatcherService` — 5-minute cron polling Linways; **baselines only advance when the event is actually delivered**, so transient FCM failures / phone-off are retried instead of lost.
  - `TimetableWatcherService` — 5-minute cron fingerprint-diff + replan reminders; `timetableUpdated` fires once per day.
  - Dedup + TTL logic; per-user preference filtering (master/attendance/bunk/class reminders/milestones/**timetable changes**/roasting + reminder timing).
- **Auth**: sessions now **persist to the JSON store and survive restarts** (watchers keep running across redeploys); `POST /api/auth/logout` invalidates the session.
- **Delivery guarantees**: events are only marked processed once FCM accepted them (or all tokens invalid); zero-device and transient failures stay pending and are retried on the next watcher/scheduler tick. Phone-off delivery is handled by FCM's own queueing within the per-type TTL.
- Compiles clean: `npx tsc --noEmit` passes. **31 jest tests pass** (rule engine, TTL/channel mapping, dispatch/dedup/retry/preferences).

### Flutter (`lib/`)
- **`services/api/pulse_backend_service.dart`** — backend client: login/logout, register/unregister device, full preference sync (now sends real `bunkEnabled` + `timetableEnabled`). Disabled (all no-ops) when `PULSE_BACKEND_URL` dart-define is absent.
- **`features/notifications/application/fcm_setup.dart`** — `FcmController`: permission request, token capture, token-rotation re-registration, **foreground messages rendered through the local pipeline using the server data payload** (`type` → channel, `eventId` → stable id), background/terminated taps forwarded to `FcmController.onMessageOpened`.
- **Tap handling (new)**: local + FCM taps navigate back to the dashboard when a session is active (`main.dart` → `rootNavigatorKey`).
- **Preferences**: new **Timetable Changes** toggle; legacy Attendance/Low-warning toggles now mirror to the backend automatically; `bunkEnabled` synced from the real setting.
- **Tests**: **41 pass** (`flutter test`) — rule engine, content, scheduler, FCM channel mapping.
- **Build blockers fixed**: `package_info_plus` added, missing `ApiConstants` getters + `PersistentCache.getTimetable/setTimetable` restored, dead `auth_capture_webview_screen.dart` (broken webview SSO file) removed. `flutter analyze` is error-free.

## PENDING / TO-DO

### 1. Firebase credentials (blocking for REAL pushes — env/config, not code)
- [ ] Download the server service-account JSON for project `pulse-5b489` and set `FCM_SERVICE_ACCOUNT_PATH` (or `GOOGLE_APPLICATION_CREDENTIALS`) in `safebunk-backend/.env`. Without it the backend runs in dev mode (logs would-be notifications — pipeline fully exercised, nothing delivered).
- [ ] (Optional) Set `PULSE_STORE_PATH` to a persistent volume in production so the store survives filesystem resets.

### 2. Backend deploy
- [ ] Run `npm run start:dev` and hit `/api` + Swagger (`/api/docs`) to sanity-check the notifications endpoints.
- [ ] Pin CORS + HTTPS; decide deployment target (LAN, VPS, Railway, etc.).
- [ ] `safebunk-backend/node_modules` is tracked in git — should be gitignored (pre-existing).

### 3. Flutter run flags
- [ ] Build/run the app with:
      `flutter run --dart-define=PULSE_BACKEND_URL=https://<host>:<port>`
- [ ] Verify FCM token appears in the debug log (`[FCM] token obtained (…)`).

### 4. End-to-end verification (once 1–3 done) — test matrix from the spec
- [ ] TEST 1/2/3/4: attendance marked while app OPEN / BACKGROUND / REMOVED FROM RECENTS / SCREEN LOCKED → notification arrives.
- [ ] TEST 5: phone powered off → event detected by backend → phone on → FCM delivers within configured TTL (10 min reminders / 1 h state events).
- [ ] TEST 6: same attendance record polled repeatedly → exactly ONE notification.
- [ ] TEST 7: timetable changed → old reminders cancelled, new ones scheduled, one `timetableUpdated` push.
- [ ] TEST 8: no timetable → no class reminders. TEST 9: no faculty → no invented names. TEST 10: Roast Mode OFF → neutral copy.
- [ ] Toggle every settings switch → verify `PUT /api/notifications/preferences` and that the server respects it.
- [ ] Logout → device unregistered + backend session invalidated; login again → re-registered.
- [ ] `GET /api/notifications/status` shows devices, preferences and recent event ids.

## Notes
- Without `PULSE_BACKEND_URL` the app behaves exactly as before (local-only notifications, all backend calls are no-ops).
- FCM messages carry notification + data payloads; the app renders foreground messages locally so channels/priority/silence settings stay consistent. Android shows system-tray notifications automatically in background/terminated/killed states.
- A powered-off phone cannot show a notification. FCM retains the message per the per-type TTL and delivers when the phone reconnects; stale class reminders are dropped server-side and never fire late.
