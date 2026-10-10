# Tour Guard v1 backend

Python 3.11+. Run commands below from the repository root. This is a production-oriented
foundation, not a deployed emergency service or a validated ML predictor.

## Files

```
backend/
  config.py                environment configuration
  database.py              SQLAlchemy 2 engine and request sessions
  models.py                users, hazard_zones, sos_events
  schemas.py               validated API inputs and outputs
  auth.py                  Argon2 hashing and expiring JWTs
  risk_engine.py           OSRM, PostGIS buffer queries, heuristic assessment
  main.py                  versioned API endpoints and lifecycle
  migrations/              Alembic initial schema
  tests/                   API, risk, routing and optional PostGIS tests
  .env.example
  compose.yaml             optional local PostGIS database
  requirements-v1.txt      new API dependencies
  requirements-dev.txt
  legacy_main.py           preserved prototype entry point
```

The old `routers/`, `ml_model/`, and `requirements.txt` are preserved for reference.
The new app does not expose their unversioned endpoints or claim their prototype
SOS response means an actual rescue dispatch. Flutter now uses the versioned endpoints with secure token storage. See
`../FLUTTER_API_SETUP.md` for frontend startup and integration details.

## Local setup (PowerShell)

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python -m pip install -r backend/requirements-dev.txt
Copy-Item backend/.env.example backend/.env
backend/.venv/Scripts/python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Paste the generated value into `JWT_SECRET` in `backend/.env`. Set `DATABASE_URL`
to your real database credentials; percent-encode special characters in the password.
The requested `postgresql://postgres:YOUR_PASSWORD@localhost:5432/tour_guard` format
is supported and internally selects the psycopg 3 driver.

`requirements-lock.txt` records the exact versions used in the Windows/Python 3.11
test environment. Use `pip install -r backend/requirements-lock.txt` to reproduce
that environment; review updates before deployment.

Use an existing PostGIS database or, with Docker installed:

```powershell
$env:POSTGRES_PASSWORD = 'your-local-database-password'
docker compose -f backend/compose.yaml up -d
```

For an existing PostgreSQL installation, create `tour_guard`, then run
`CREATE EXTENSION IF NOT EXISTS postgis;` in that database as an administrator.
Do not use the PostgreSQL superuser as the production application account.

```powershell
backend/.venv/Scripts/alembic -c backend/alembic.ini upgrade head
backend/.venv/Scripts/python -m uvicorn backend.main:app --reload --port 8000
```

Swagger: http://127.0.0.1:8000/docs. Use **Authorize** with the access token.
For emulator access, use `http://10.0.2.2:8000`; expose the server to the emulator
with `--host 0.0.0.0` only on a trusted development network if needed.
`/health/live` checks the process; `/health/ready` checks PostGIS and the user table.

## API examples

Register (201; password minimum 12 characters):

```json
{"email":"tourist@example.com","password":"choose-a-long-password","emergency_contact_phone":"+919876543210"}
```

POST `/api/v1/auth/register` returns `access_token`, `token_type`, `expires_in`
and a generated `TG-...` ID. POST `/api/v1/auth/login` takes email and password
as JSON and returns the same shape. Emails are normalized to lowercase.
IDs use 128 random bits, a unique DB index and collision retry.

POST `/api/v1/route/analyze` with `Authorization: Bearer <token>`:

```json
{"origin_lat":11.41,"origin_lng":76.70,"dest_lat":11.40,"dest_lng":76.73}
```

The result includes a GeoJSON LineString (longitude, latitude order), distance in
meters, duration in seconds, matched hazards, and assessment/reasons/limitations.
OSRM uses HTTPS by default; `OSRM_BASE_URL=http://router.project-osrm.org` supports
the requested HTTP endpoint, but HTTPS is preferable. No straight-line fallback is
fabricated. No route returns 422, upstream failure 502, and timeout 504.

Optional `weather` object: `rainfall_mm_h`, `wind_kmh`, `observed_at` (ISO timestamp
with timezone), and `source`. Observations older than one hour or over five minutes
in the future are excluded. These are caller-supplied observations, not a live
weather integration. Connect a trusted weather provider before operational use.

Risk rules are illustrative, configurable in `risk_engine.py`, and **not ML**:
- Severity 4–5 hazard exposure, rainfall >=30 mm/h, or wind >=70 km/h: HIGH RISK.
- Any lower-severity hazard, rainfall >=10 mm/h, or wind >=40 km/h: CAUTION.
- Missing/stale weather or unverified hazard coverage: at least CAUTION.
- Otherwise SAFE means only that these rules found no elevated risk.

Hazards are queried with `ST_DWithin` over geography casts, using a default 250 m
corridor and a matching GiST expression index. Source provenance is mandatory.
Import real POINT/POLYGON geometries in EPSG:4326 using a controlled GIS pipeline;
do not classify forests or tourist attractions as hazards by themselves.
No demo hazards or fabricated training data are seeded. Set
`HAZARD_COVERAGE_VERIFIED=true` only for a genuinely verified deployment region;
region-level coverage/freshness enforcement remains necessary before public use.

POST `/api/v1/sos/trigger` with the same authorization header:

```json
{"tourist_id":"TG-REPLACE_WITH_YOUR_RETURNED_ID","latitude":11.41,"longitude":76.70}
```

Only the authenticated user's ID is accepted (403 otherwise). The response confirms
a committed active event with a UTC timestamp, **not rescue dispatch**. Repeating
the request creates another event; add idempotency keys before automated retries.
No public SOS log or unauthenticated user data endpoints are exposed.

## Validation

```powershell
backend/.venv/Scripts/python -m pytest backend/tests -q
backend/.venv/Scripts/ruff check backend/config.py backend/database.py backend/models.py backend/schemas.py backend/auth.py backend/risk_engine.py backend/main.py backend/tests
```

Auth/SOS unit tests use isolated SQLite tables; they do not validate PostGIS.
For real spatial integration testing, migrate a dedicated test database and set
`TEST_DATABASE_URL=postgresql+psycopg://.../tour_guard_test` before running tests.
The spatial test inserts synthetic fixtures in a rolled-back transaction only.

## Before production deployment

Use TLS, a secrets manager, exact CORS origins, a private database with backups,
separate migration/runtime roles, and reviewed/pinned dependency versions. Apply
gateway rate limits to registration/login, routing and SOS, plus request-body limits.
Use a private or contracted OSRM service; the public demo has no production SLA.
Add audited hazard ingestion, geographic coverage checks, a trusted weather provider,
responder delivery/acknowledgements, access control for administrators, monitoring,
session revocation/refresh, and validated risk thresholds. Coordinate/token/password
data must not be included in access logs. No trained model or accuracy claim is made.

References: [FastAPI authentication](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/),
[OSRM route API](https://project-osrm.org/docs/v5.22.0/api/),
[PostGIS ST_DWithin](https://postgis.net/docs/ST_DWithin.html).

## Test isolation

Registration tests run in isolated in-memory SQLite, never through the running
API. RUN_LIVE_AUTH_TESTS no longer enables live writes. PostGIS tests only accept
a separate database named tour_guard_test and roll back test records. See
TEST_ACCOUNT_CLEANUP.md for the audit and pending cleanup approval.
