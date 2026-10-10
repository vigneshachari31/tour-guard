# Test isolation and proposed account cleanup

The earlier test_live_registration.py used HTTP requests to the running API on
port 8000 and committed generated accounts to the main database. A one-off route
verification command also registered a permanent account. These were verification
accounts created during earlier assistant work, not normal signup activity.

## Prevention implemented
- test_live_registration.py now uses the existing in-memory SQLite TestClient
  fixture and no longer contacts the running API, even if RUN_LIVE_AUTH_TESTS=1.
- Test subprocess DATABASE_URL is explicitly pointed at an unused localhost port
  and test database name so unoverridden dependencies cannot load the main URL.
  This does not change backend/.env or the running app's configuration.
- PostGIS tests require TEST_DATABASE_URL with database name exactly
  tour_guard_test, reject tour_guard before connecting, and roll back test rows.
- Guard tests cover rejecting main database URLs and isolated fixture storage.

Tests: 17 passed; 1 optional PostGIS test skipped because no separate test DB URL
was configured. Main users, sos_events and hazard_zones row counts and content
fingerprints matched before and after the suite. No records were deleted.

## Proposed deletion allowlist — awaiting explicit confirmation
All four accounts match exact addresses recorded in earlier verification reports.
Each currently has zero SOS records. No declared foreign keys referencing users
were found in the database; the logical sos_events.tourist_id links were checked
explicitly. Recheck dependencies immediately before any approved deletion.

| User ID | Email | Origin |
|---|---|---|
| 2 | tourguard-check-7b29693cb7be4e2dbb4f41075466d455@example.com | registration test |
| 4 | tourguard-check-ce078b6586f647f8b516af078448556e@example.com | registration test |
| 5 | tourguard-route-check-7f3705610c9540f09addb245d837f3ad@example.com | one-off route check |
| 7 | tourguard-check-905fbcdd31eb43f39e84fcad1ecd578b@example.com | registration test |

## Protected real accounts
- ID 3: Kishore, kishore@gmail.com (full_name currently NULL; do not alter).
- ID 6: Rax, rax@gmail.com, with one SOS record; preserve it and its links.

Deletion must use the exact IDs AND email addresses above, not a wildcard
example.com/prefix match. No cascading deletion is authorized. If any new linked
record or identity mismatch appears, stop and ask again. No sequence reset.
