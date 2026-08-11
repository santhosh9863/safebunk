# PULSE — Push Notification Architecture: Work Status & Pending Items

Last updated: 2026-08-11

## What is DONE

### Backend (`safebunk-backend/`) — NestJS + Firebase Admin
- **JSON persistence layer**: `src/common/store/` — `JsonStoreService` (file-based store for dedup markers, notification log, devices, sessions) + `StoreModule`.
- **Notifications module** (`src/notifications/`):
  - `register-device` / `unregister-device` / `preferences` (PUT) / `watched-events` (GET) / `recent-notifications` (GET) / `notification-count` (GET) endpoints in `notifications.controller.ts`.
  - `FcmService` — sends pushes via `firebase-admin` (v14 modular API), uses **data-only messages** (`eventId`, `type`, `messageId`, `dedupeId`) with `data-message-priority: high`.
  - `NotificationRuleService` — TypeScript port of the Flutter rule engine (attendance/bunk/milestone events).
  - `NotificationContentService` — roast/neutral content templates (same copy as Flutter).
  - `NotificationSchedulerService` — 1-minute cron that fires due reminders (10-min / 5-min / class-start / missed-class).
  - `AttendanceWatcherService` — 5-minute cron polling Linways attendance via the session manager.
  - `TimetableWatcherService` — fingerprint diff on timetable + replans reminders when classes change.
  - Dedup + TTL logic, per-user preference filtering (master/attendance/class reminders/milestones/roasting).
- **Auth**: `AuthService.getActiveSessions()` for watchers; `POST /api/auth/logout` invalidates backend session.
- Compiles clean: `npx tsc --noEmit` passes.

### Flutter (`lib/`)
- **`services/api/pulse_backend_service.dart`** — backend client: login/logout, register/unregister device, preference sync. Disabled (all no-ops) when `PULSE_BACKEND_URL` dart-define is absent.
- **`features/notifications/application/fcm_setup.dart`** — `FcmController`: permission request, token capture, foreground messages → existing local `NotificationService` (same channels), tap handling via normal auth flow, token-rotation re-registration.
- **Providers**: `deviceTokenProvider`, `pulseBackendServiceProvider` (in `features/notifications/application/notification_providers.dart`).
- **Wiring**:
  - `main.dart` — `FcmController.initialize(...)` after Firebase + NotificationService.
  - `providers/auth_provider.dart` — session restore → re-registers device (backend token survives in its own secure storage); explicit login → backend login + register; logout / session-expired → unregister + backend logout.
  - `features/notifications/presentation/providers/notification_settings_provider.dart` — every setter mirrors preferences to the backend (best-effort).
- **Android manifest** — FCM permissions (`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `VIBRATE`), FCM default channel meta-data, `FirebaseMessagingReceiver` boot receivers, `firebase_messaging` 16.x dependency in `pubspec.yaml`.
- **Tests**: 39/39 pass (`flutter test`) — rule engine, content service, scheduler spec tests.

## PENDING / TO-DO

### 1. Firebase project setup (blocking for real push)
- [ ] Create/enable Firebase project with Cloud Messaging.
- [ ] Add Android app (package id must match `android/app/build.gradle` applicationId).
- [ ] Download **`google-services.json`** and place it in **`android/app/google-services.json`** (file is NOT in the repo — required to build/run with FCM).
- [ ] Upload the server service-account key for `firebase-admin` (see backend env below).

### 2. Backend environment / deploy
- [ ] Set env vars for `safebunk-backend`: `GOOGLE_APPLICATION_CREDENTIALS` (path to Firebase Admin service-account JSON) and `FIREBASE_PROJECT_ID`.
- [ ] Run `npm run start:dev` and hit `/api` + Swagger (`/api/docs`) to sanity-check the notifications endpoints.
- [ ] (Optional) Pin/CORS + HTTPS for real device registration; decide deployment target (local LAN, VPS, etc.).

### 3. Flutter run flags
- [ ] Build/run the app with:
      `flutter run --dart-define=PULSE_BACKEND_URL=https://<host>:<port>`
      (also requires Firebase's `google-services.json` and the app's `firebase_options.dart` already checked in).
- [ ] Verify FCM token appears in the debug log (`[FCM] token obtained (…)`).

### 4. End-to-end verification (once 1–3 done)
- [ ] Login → backend registers device (`/api/notifications/register-device`).
- [ ] Server-side watcher triggers: simulate attendance drop / bunk event / class reminder; confirm push arrives while app is **foreground** (local notification) and **background/killed** (FCM system tray).
- [ ] Toggle preferences in Settings → verify `PUT /api/notifications/preferences` fires and server respects them (roasting off = neutral copy).
- [ ] Logout → device unregistered; token rotation re-registers.
- [ ] Check `recent-notifications` + `notification-count` endpoints show pushed events.

### 5. Known pre-existing issues (NOT from this feature — leave for a separate pass)
- [ ] `lib/screens/auth_capture_webview_screen.dart` — errors: missing `webview_flutter` dependency + missing `providers/safebunk_auth_provider.dart` (dead file).
- [ ] `lib/services/api/timetable_api_service.dart` — `ApiConstants` getters (`timetable`, `batchId`, `getDaywise`, …) missing.
- [ ] `lib/services/repositories/timetable_repository.dart` — `PersistentCache.getTimetable/setTimetable` missing.
- [ ] `lib/services/update_service.dart` — `package_info_plus` missing from pubspec.
- [ ] `safebunk-backend/node_modules` is tracked in git — should be gitignored.

## Notes
- Without `PULSE_BACKEND_URL` the app behaves exactly as before (local-only notifications, all backend calls are no-ops).
- FCM messages are data-only; the app renders them locally so channels/priority/silence settings stay consistent. Android shows system-tray notifications automatically when the app is in background.
