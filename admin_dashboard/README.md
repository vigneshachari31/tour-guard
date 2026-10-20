# Tour Guard administration

A React/Vite/TypeScript console connected to the existing FastAPI and PostGIS database. No sample records or hardcoded metrics are used by the application. The test fixtures live only in isolated tests.

## Run locally

From the repository root in PowerShell:

```powershell
backend/.venv/Scripts/python -m pip install -r backend/requirements-v1.txt
backend/.venv/Scripts/python -m alembic -c backend/alembic.ini upgrade head
npm.cmd ci --prefix admin_dashboard
npm.cmd run build --prefix admin_dashboard
backend/.venv/Scripts/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Open **http://127.0.0.1:8000/admin/**. Restart an already-running backend after building, because the static bundle is mounted at startup. The existing Flutter `/api/v1` paths remain available on the same origin.

For UI development, run `npm.cmd run dev --prefix admin_dashboard` and open the URL it prints with `/admin/`. Vite proxies `/api` and `/health` to port 8000. For deployment, the built bundle can be served by FastAPI or by an HTTPS reverse proxy forwarding `/api` and `/health` to FastAPI. Never expose the Vite development server publicly.

## Admin access

Existing active `users.role = 'admin'` accounts can sign in. A JWT role claim is included, but each privileged request checks the current database role and activation flag; editing a browser claim never grants access. Tourist registration cannot supply a role.

If a bootstrap account is needed, add `ADMIN_EMAIL` and `ADMIN_PASSWORD` locally to `backend/.env`, then run:

```powershell
backend/.venv/Scripts/python -m backend.scripts.bootstrap_admin
```

The password must be 12–128 characters. New passwords use Argon2. An existing account is promoted only if that password verifies against its stored hash; the script never overwrites its password or reactivates a disabled account. It records the operation in the audit log. No bootstrap credentials were inserted by this implementation.

Admin access tokens remain in JavaScript memory, never localStorage/sessionStorage or URLs. Refresh and expiry require login again. Requests use Bearer authorization, so no cookie/CSRF flow is introduced. Logout clears memory. Account deactivation or role removal denies subsequent API access. Local sign-out does not revoke a previously copied JWT; use short token lifetimes and database deactivation for immediate access removal.

Admin login has a bounded per-process limit of 10 requests per IP per minute. Use a shared reverse-proxy rate limiter for multi-worker/public deployments, HTTPS, secure proxy configuration, database backups, private DB networking, and access logging that omits tokens/passwords. Admin/API responses are no-store; the UI is denied framing.

## Workflows

- Dashboard: SQL counts, last-30-day incident chart, status distribution, active hazard categories, recorded risk-level buckets, and latest incidents. Stats/feed refresh every 15 seconds; charts every 30 seconds.
- Incidents: filter/paginate, view reported SOS coordinates and active hazards, contact/emergency profile, recent trips, assignment and status history.
- Rescue: register a responder, assign/reassign them, enter a note, start response, then resolve or cancel. A responder can hold one active assignment. Stale transitions are rejected and terminal incidents cannot be reopened through these APIs. Assignments do **not** send SMS, calls, or external dispatch messages.
- Hazards: draw a polygon with map clicks, drag its numbered vertices, undo vertices, or edit GeoJSON. PostGIS rejects invalid/self-intersecting geometry. Category, provenance, severity and validity dates are saved. Deactivated/expired/future hazards are excluded from route checks and the active map. The management table shows all hazards, including existing point reports.
- Trips: each successful route analysis atomically records a trip and risk history; the previous active trip is completed. End Trip in Flutter updates that trip in PostgreSQL. Trips with no GPS update, or one older than 15 minutes, are marked stale.
- GPS: only actual device observations are written through `POST /api/v1/trips/{id}/locations`. Flutter sends an observation when it plans a route from current GPS. It does not silently enable continuous background tracking. Manual planned origins are never treated as observed tourist locations. The admin table polls stored updates; it cannot manufacture live GPS telemetry.
- Risk history: the existing engine produces SAFE / CAUTION / HIGH RISK, not a calibrated numeric ML score. Charts use these recorded categories and show factor explanations/limitations. Historical gaps are not populated with invented assessments.
- Users: searchable tourist accounts; reversible soft-deactivation preserves data and blocks current tokens/login. Admin accounts cannot be disabled from this table.
- Audit: admin login and write actions are recorded in the same transaction as each mutation. CSV exports escape quotes and neutralize spreadsheet formula prefixes.

The tourist `/sos/events` endpoint now returns only that tourist's records. The cross-user rescue view is exclusively under the admin API.

## Database reconciliation

Inspection found the live database at Alembic revision `0006` although repository migration files stopped at `0004`. Existing role/trip/rescue/history tables were preserved. Reconstructed baseline migrations `0005` and `0006` support fresh databases; `0007` adds workflow status, validity dates, risk-to-trip links, and active-assignment uniqueness indexes. No migration stamping, table reset, or account deletion is used.

Existing tables `trip_location_updates` and `risk_assessment_logs` provide the requested location-history and risk-assessment functions. They are reused instead of duplicating them as `location_history` and `risk_assessments`. Legacy SOS `status` stays `active`/`resolved` for Flutter; separate `workflow_status` carries OPEN / IN_PROGRESS / RESOLVED / CANCELLED. Existing acknowledged/dispatched statuses map to IN_PROGRESS during migration. Existing risk history remains readable even if not linked to a trip.

## Validation

```powershell
backend/.venv/Scripts/python -m pytest backend/tests -q
npm.cmd run lint --prefix admin_dashboard
npm.cmd run test --prefix admin_dashboard
npm.cmd run build --prefix admin_dashboard
npm.cmd audit --prefix admin_dashboard
C:/src/flutter/bin/flutter.bat test
C:/src/flutter/bin/flutter.bat analyze
```

Backend unit tests use SQLite. Set `TEST_DATABASE_URL` to a migrated, PostGIS-enabled database named **tour_guard_test** for spatial tests; the safety guard rejects the application database. Integration test writes roll back.

For real browser workflows with Chrome installed, build the frontend and run:

```powershell
backend/.venv/Scripts/python -m backend.scripts.run_admin_e2e
```

This requires `TEST_DATABASE_URL`; it starts a test server on 8011, uses synthetic accounts only inside an outer transaction, runs Playwright, and rolls the transaction back even after failures. It never starts against the main database. Screenshots go to ignored `admin_dashboard/test-results/`.

Implementation references: [Vite deployment](https://vite.dev/guide/build.html), [Tailwind Vite integration](https://tailwindcss.com/docs/installation/using-vite), [React Leaflet map API](https://react-leaflet.js.org/docs/api-map/).
