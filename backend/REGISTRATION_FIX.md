# Registration verification — 2026-10-09

The running API returned 503 while a fresh Python process using the same backend
virtual environment and current configuration connected successfully to
localhost:5432 / tour_guard as postgres. A User insert/refresh succeeded in a
transaction that was rolled back. After a code-triggered Uvicorn reload, the
running API returned 200 for /health/ready and 201 for registration, with no
credential or schema changes. This isolates the failure to stale process state /
configuration. Settings and the SQLAlchemy engine are cached for the process
lifetime; editing .env alone does not reliably trigger Uvicorn's Python watcher.
The original driver's exception details were not retained by the old generic
handler, so its precise SQLSTATE cannot be recovered from that response.

After future .env changes, stop and restart the backend from the repository root:

    backend\.venv\Scripts\python.exe -m uvicorn backend.main:app --reload --reload-dir backend

The error handler now logs exception class, driver class, and SQLSTATE without
logging credentials, SQL values, or personal data. Client errors remain generic.

Verified against the actual local API and PostgreSQL:
- /health/ready: 200, including PostGIS availability.
- Register: 201 with bearer token and TG-prefixed 32-hex-digit identifier.
- Persisted account, matching Tourist ID, Argon2 hash verification.
- Duplicate case-insensitive email: 409.
- Login: 200; wrong password: 401.

One intentionally retained test account:
 tourguard-check-7b29693cb7be4e2dbb4f41075466d455@example.com
No existing account was changed or deleted. The test password was generated in
memory and was not written to disk. A diagnostic rolled-back insert may consume
a sequence number; gaps are normal for PostgreSQL sequences.

The former live test has been replaced with an isolated in-memory registration
test. RUN_LIVE_AUTH_TESTS no longer enables requests to the running API.

    backend\.venv\Scripts\python.exe -m pytest backend/tests/test_live_registration.py -q

Schema inspection: users has the columns, auto-increment ID, and unique email /
tourist_id constraints needed for registration. Its wider VARCHAR lengths and
nullable extra full_name column are compatible. There is no alembic_version
table. hazard_zones lacks source and updated_at, and sos_events differs in
nullability and timestamp type from the model. These do not block registration;
no unrelated schema changes or initial migrations were applied over existing
tables. The spatial integration test requires a separately configured migrated
TEST_DATABASE_URL and was not run against this database.

Flutter registration posts email/password to /api/v1/auth/register, accepts
successful 2xx responses, stores the returned session, and navigates to the
dashboard. Error responses are shown to the user. No frontend layout change was
needed. Live browser interaction was not automated in this verification.
