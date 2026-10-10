# Registration details and original planner restoration

## Causes and changes
Signup collected name/mobile but sent only email/password. User lacked mapped
full_name and personal phone fields. The existing Mobile Number input represents
the tourist's own number, so it now maps to phone_number, never to
emergency_contact_phone. Full name maps to full_name end to end. Optional fields
preserve compatibility with older API clients. New supplied values are validated.
The existing signup design, JWTs, Argon2 hashing and Tourist IDs are preserved.

The original MapScreen remains in Git (b3540be and earlier). Recent uncommitted
navigation changes pointed dashboard and /map to BackendRouteScreen. These paths
now use the original MapScreen again, preserving its floating dual-input card,
autocomplete, OSM canvas, markers, swap control, presets, and route summary.
Driving was the supported routing mode; no unsupported mode is presented.
GPS is opt-in. Demo coordinates are used only as the initial map viewport or when
a user explicitly chooses a preset, never as a failed GPS substitute.

Route geometry, distance, duration, risk and hazards now come from the same
/api/v1/route/analyze response. Old sample risk inputs and fabricated fallback
routes were removed from this flow. Editing either location invalidates the prior
assessment. Failed calls leave the map visible without a fabricated SAFE result.
Hazards are listed by name/type/severity; the API does not supply their geometry,
so no fabricated hazard pins are placed. The original Start Navigation button
only showed a snackbar, so it now truthfully offers View Full Route / camera fit.

## Database changes
Applied only nullable additive columns using the Alembic Operations bridge:
- users.phone_number (full_name and emergency_contact_phone already existed).
- hazard_zones.source and updated_at, required by the route query's mapped model.

No existing row values were updated, deleted, backfilled or fabricated. Existing
accounts therefore keep NULL where values were never recorded. Missing hazard
sources display Source not recorded. No credentials changed.

0002_registration_details follows 0001 for normally migrated databases. This
existing database has no Alembic history and differs from the original baseline;
the additive bridge was applied without falsely stamping 0001 or recreating tables.
To apply the same idempotent bridge to another existing database:

    backend\.venv\Scripts\python.exe -m backend.migrations.add_registration_fields

Do not run the initial migration over existing tables. Full baseline reconciliation
is separate from these targeted fixes.

## Files changed in this task
- backend/models.py, schemas.py, main.py: registration fields and mapping.
- backend/risk_engine.py: truthful label for missing legacy hazard source.
- backend/migrations/add_registration_fields.py: additive existing-schema bridge.
- backend/migrations/versions/0002_registration_details.py: Alembic revision.
- backend/tests/test_registration_details.py, test_live_registration.py.
- lib/services/api_service.dart, lib/screens/register_screen.dart: signup JSON.
- lib/screens/map_screen.dart: original planner wired to v1 with optional GPS.
- lib/screens/dashboard_screen.dart, lib/main.dart: restore original navigation.
- test/map_screen_test.dart, test/api_service_test.dart: interaction/request tests.
- FLUTTER_API_SETUP.md and this report.

## Verification
- Flutter analyze: no issues.
- Flutter tests: 19 passed, including manual source and destination selection,
  map present on entry/failure, exact returned polyline, markers, risk/hazards,
  clearing stale analysis, signup JSON, profile and application smoke tests.
- Backend tests with live registration enabled: 11 passed; spatial test initially
  skipped, then run separately against PostGIS and passed (test rows rolled back).
- Actual registration: 201; full_name and personal phone verified in PostgreSQL;
  emergency contact remained NULL as intended. Hashing, ID, duplicate-email and
  subsequent login verified.
- Actual authenticated route request: 200, LineString with 565 points, 21930.6 m,
  CAUTION, zero matching hazards. This does not imply verified hazard coverage.
- OSM tile: HTTP 200 image/png; Photon Ooty place search: HTTP 200 with a result.
- UI behavior tested with deterministic tiles/place results; interactive browser
  visual inspection was not performed. Device GPS acquisition was not exercised.
- Existing FastAPI TestClient dependency emits a deprecation warning; no failures.

Two new verification accounts were deliberately retained, no existing accounts changed:
- tourguard-check-ce078b6586f647f8b516af078448556e@example.com
- tourguard-route-check-7f3705610c9540f09addb245d837f3ad@example.com
Passwords were generated in memory. No real SOS messages were sent.

Restart/hot-restart Flutter to load the restored screen. The live backend reloaded
and passed the tests. Older missing account details were not altered; correcting
those requires the actual values and explicit approval.
