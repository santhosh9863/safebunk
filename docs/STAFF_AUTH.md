# Staff/Admin Authorization Foundation

Status: implemented on `feature/staff-admin-auth-foundation` (including the Flutter
staff/admin login/navigation and the staff issue-handling workflow).

## Roles and identity source

Staff and admin identities are stored locally in the `StaffUser` Prisma model.
They are **not** Linways student identities and are never created by the
student login flow.

- `STAFF` — read-only staff report access.
- `ADMIN` — all staff access plus staff-account provisioning.

`role` is a required database column with no default. A malformed or unknown
role is rejected at login (no fallback role). Student sessions are always
`STUDENT`, assigned by the backend after Linways verification.

Passwords are stored as salted scrypt hashes (`scrypt$N$r$p$salt$hash`) in
`src/auth/password.ts`. Plaintext passwords are never persisted, logged or
returned.

## Session separation

`AuthService` stores both session types in the existing `authSessions` JSON
store, discriminated by `role`:

- Student routes use `AuthGuard`; a staff/admin token receives **403**.
- Staff routes use `StaffAuthGuard`; a student token receives **403**.
- Missing/expired/invalid tokens receive **401**.
- Admin-only routes add `RolesGuard` + `@Roles('ADMIN')`.
- Background notification watchers only receive student sessions.

Every staff request revalidates the session against the `StaffUser` row. A
deleted/inactive account, a malformed stored role, or a role change invalidates
an existing token immediately with **401**; the 24-hour session TTL does not
keep a revoked account usable. Staff identity/role are never trusted from the
request body or token alone.

Legacy stored student sessions without a `role` are restored as `STUDENT` only
when they have the complete student session shape. Unknown roles are dropped.

## Login throttling

`POST /api/auth/login` and `POST /api/auth/staff/login` share the in-memory
`LoginRateLimiterService`:

| Login endpoint | Per IP / 15 min | Per account / 15 min |
|---|---:|---:|
| student | 120 | 10 |
| staff/admin | 30 | 5 |

Student IP limits are deliberately higher to tolerate shared campus/mobile
NAT. Both policies are constants in `login-rate-limiter.service.ts`.

Attempts are counted before credentials are verified, so concurrent requests
cannot race past the limit. A successful login clears only that account's
bucket; the per-IP bucket is not cleared, so a valid account cannot be used to
reset IP-level protection. Throttled responses are **429** with a generic
message and a `Retry-After` header, and never echo the username, password or
account existence.

The limiter is per-process and its counters reset when the backend restarts. A
multi-instance deployment must back the same policy with a shared store. This
is a temporary throttle, not a permanent account lockout.

When the backend is behind a reverse proxy, set `TRUST_PROXY` to the number of
proxy hops (normally `1`) so the login routes key on the client address. Leave
it unset when clients can reach the app directly; otherwise clients could spoof
`X-Forwarded-For`.

## Flutter staff/admin UI

The student login screen keeps its existing Linways flow and adds a clearly
visible **Staff / Admin Login** option. That option opens a separate
username/password screen that calls `POST /api/auth/staff/login`; there is no
staff registration screen.

The backend-issued role is parsed strictly as `STAFF` or `ADMIN`. An unknown or
missing role invalidates the response rather than falling back to a privileged
identity. The complete staff session is stored through the existing
`SecureStorageService`/`SessionManager` architecture under
`saved_staff_session`, and student and staff sessions are mutually exclusive:
saving either one removes the other.

Role-based navigation is enforced at the shell level:

- `STAFF` — assigned issue queue with accept/progress/resolve actions and account/sign-out.
- `ADMIN` — all campus reports with assignment/reassignment/rejection oversight, plus
  the admin-only staff account list.
- Student sessions cannot enter the staff shell; staff/admin sessions cannot
  enter the student shell. The backend still enforces every endpoint
  independently, so the UI gates are not the security boundary.

Invalid/inactive credentials use a generic failure message. Network failures
are shown in the staff form. A `401` from a staff endpoint clears the local staff
session and returns to the login screen. Signing out revokes the staff token,
clears secure storage, caches and notification state.

## API

| Method | Route | Access |
|---|---|---|
| `POST` | `/api/auth/staff/login` | public credentials endpoint |
| `GET` | `/api/staff/reports` | STAFF, ADMIN |
| `GET` | `/api/staff/reports/:id` | STAFF, ADMIN |
| `GET` | `/api/staff/users` | ADMIN only |
| `POST` | `/api/staff/users` | ADMIN only |

`POST /api/auth/staff/login` accepts only `username` and `password`. The role
comes from the database row, never the request body.

`POST /api/staff/users` accepts `username`, `password`, optional `displayName`
and an explicit `role` (`STAFF` or `ADMIN`). The acting admin is authorized by
their session. Responses never include `passwordHash`.

No report status or assignment mutation route exists in this slice. Report
status therefore remains immutable until a separately reviewed lifecycle
milestone wires the existing state machine to guarded staff endpoints.

## Migration and first admin

Apply the new migration:

```powershell
cd safebunk-backend
npm run prisma:deploy
# dev-only alternative: npm run prisma:dev
```

Provision the first admin locally. The password is read from a hidden prompt,
not a CLI argument. Passing `--password` or `--password=...` is rejected
explicitly so a secret cannot be left in shell history:

```powershell
npm run staff:create -- --username campus.admin --role ADMIN --name "Campus Admin"
```

First-admin protection by environment:

- **Local dev:** run the command against the local `DATABASE_URL`; protection is
  the developer's OS account and access to the local `prisma/dev.db` file.
- **Staging/production:** there is no unauthenticated bootstrap route, default
  account, or HTTP way to create the first admin. Run the compiled
  `node dist/staff/staff-cli.js` from a deployment shell that has the production
  `DATABASE_URL` and database credentials (normally from the platform secret
  manager). Protection therefore rests on deployment-shell access plus database
  credentials. Do not expose the CLI or database credentials over the network.
  `npm run staff:create` requires the dev-only `ts-node` dependency; use the
  compiled file in production.

After that, an authenticated admin can create additional staff/admin accounts
through `POST /api/staff/users`.

Never commit `.env`, `prisma/dev.db`, a password, or a password hash.

## Related

- Issue workflow, assignment rules and report lifecycle endpoints:
  `docs/ISSUE_HANDLING.md`.

## Still pending

- Permanent account lockout and shared/distributed throttling state. The current
  login limiter is in-memory and per-process; see “Login throttling” above.
- Account deactivation/role-change APIs. Changing `active` or `role` directly in
  the database now takes effect on the next staff request, but no API performs
  that change yet.
