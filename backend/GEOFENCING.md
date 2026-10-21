# Tour Guard hazard geofencing

## Existing flow and changes

FastAPI `main.py` mounts the trips router. Authenticated route analysis creates
a numeric `Trip.id`, returned as `trip_id`. Only that tourist can submit GPS
updates or end the trip. `owned_trip` locks the trip row until commit.
Previously, locations were saved in `trip_location_updates` with no hazard check;
Flutter sent one GPS observation after route planning. Route corridor risk
assessment already existed, but it is different from current-location geofencing.

The location endpoint now checks active, currently valid hazards using PostGIS.
Polygon/MultiPolygon checks use ST_Covers (boundaries included, holes excluded).
Point hazards use ST_DWithin on geography in metres. Configure their radius with
`GEOFENCE_POINT_RADIUS_METERS` (default 100). GeoJSON uses longitude, latitude;
location requests retain named latitude/longitude fields.

Each GPS record saves current hazard snapshots and newly entered hazard alerts.
The previous record's hazard IDs determine entry/exit, under the existing trip
row lock. Staying inside gives `alerts: []`; a recorded exit allows a new entry.
Current hazards are always returned, so a lost response can recover its warning
on the next successful update. Location, warning history and trip position commit
together. Database errors roll back and return the existing 503 response.

Flutter polls fresh device GPS every 10 seconds while an active trip is open in
the foreground. It does not upload manually selected route origins as GPS.
A persistent banner shows hazard name/type/severity; it does not repeatedly open
dialogs. API/GPS failures retain the last warning with an error message, then
retry. Logout/end trip stops tracking; backgrounding pauses it. Existing
API_BASE_URL configuration and bearer authentication are reused.

Admin Trip Monitoring displays hazards from the last GPS check and entry history
(last 20 observations containing alerts). SOS incidents remain explicit rescue
requests; entering a hazard does not silently dispatch rescue or create SOS.

## Files changed

- `backend/geofencing.py`: PostGIS lookup and persistent entry comparison.
- `backend/routers/trips.py`, `backend/schemas.py`: GPS request integration and documented response.
- `backend/models.py`, `backend/migrations/versions/0008_geofencing.py`: two nullable snapshot columns; widen geometry constraint to allow MultiPolygon. No records deleted or rewritten.
- `backend/config.py`, `backend/.env.example`: point proximity radius.
- `backend/routers/admin.py`: attach warning/history data to existing trip responses.
- `admin_dashboard/src/pages/Trips.tsx`, `admin_dashboard/src/types.ts`: display those warnings in the existing page.
- `lib/models/geofence_update.dart`, `lib/services/api_service.dart`: typed response parsing.
- `lib/services/trip_monitor.dart`, `lib/widgets/trip_hazard_monitor.dart`, `lib/main.dart`: foreground GPS monitoring, lifecycle management and warning banner.
- `lib/screens/map_screen.dart`: replace the old one-shot upload with the shared monitor.
- `backend/tests/test_geofencing.py`, `backend/tests/test_admin.py`: isolated request, state, authorization and rollback tests.
- `backend/tests/check_geofence_postgis.py`: read-only spatial checks using inline fixtures.
- `backend/tests/check_geofence_request_postgis.py`: real authenticated API/PostGIS tests in temporary tables, with independent temporary sequence and rollback.
- `test/geofencing_test.dart`: response-to-banner, offline recovery and cancellation tests.

## Start and test

From `C:\Users\vigne\Desktop\travel_risk_app`:

```powershell
.\.venv\Scripts\python.exe -m alembic -c backend/alembic.ini upgrade head
.\.venv\Scripts\python.exe -m pytest backend/tests -q -p no:cacheprovider
.\.venv\Scripts\python.exe -m backend.tests.check_geofence_postgis
.\.venv\Scripts\python.exe -m backend.tests.check_geofence_request_postgis
flutter test
```

Migration 0008 was applied during implementation. Running `upgrade head` again
does not recreate the columns. The two explicit PostGIS scripts use the configured
connection; the first performs read-only checks, and the second uses only
connection-local temporary tables and rolls everything back. Neither inserts
fixtures into application tables or advances application ID sequences.

Start the API with your existing command from `backend`:

```powershell
..\.venv\Scripts\python.exe -m uvicorn main:app --reload
```

For a physical Android phone on the same network, bind the development API:

```powershell
..\.venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Then from the project root, substitute your computer's LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8000/api/v1
```

Allow the connection through the local firewall. A physical phone cannot use
your computer's localhost. Sign in as a tourist, allow GPS, plan a trip, and keep
the app foregrounded. Use an Android emulator GPS override for the supplied test
positions, connected to an isolated test backend. Do not physically enter a
dangerous zone to test this feature.

Admin frontend, from `admin_dashboard`:

```powershell
npm.cmd run build
npm.cmd run dev
```

## Swagger verification with isolated data

Manual location submissions are stored. Use a separate PostGIS-enabled
`tour_guard_test` database for synthetic test locations. In a separate PowerShell
terminal at the project root, set DATABASE_URL to that test database's connection
string (keep it private), then run:

```powershell
.\.venv\Scripts\python.exe -m alembic -c backend/alembic.ini upgrade head
.\.venv\Scripts\python.exe -m backend.create_admin rescue-test@example.com
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --port 8001
```

The admin creation command prompts for a password. Open
`http://127.0.0.1:8001/docs`. All following operations must use that test server.

1. Call `POST /api/v1/admin/auth/login` with the test admin credentials. Copy
   `access_token`, click **Authorize**, and paste the token into HTTPBearer.
2. Call `POST /api/v1/admin/hazards` with the payload below. Save its returned ID;
   test database IDs may differ from the original hazard 9.

```json
{
  "name": "dangerous zone",
  "hazard_type": "landslide",
  "severity": 4,
  "source": "Isolated geofencing test fixture",
  "is_active": true,
  "geometry": {
    "type": "Polygon",
    "coordinates": [[
      [72.85563203, 19.044743219],
      [72.857853272, 19.044783785],
      [72.857574276, 19.043505941],
      [72.855835912, 19.042877157],
      [72.85563203, 19.044743219]
    ]]
  }
}
```

3. Register a test tourist using `POST /api/v1/auth/register` with `email` and
   your chosen password (at least 12 characters). Replace the Swagger token with
   that tourist's access_token.
4. Call `POST /api/v1/route/analyze` to create that tourist's active trip:

```json
{
  "origin_lat": 19.0440,
  "origin_lng": 72.8565,
  "dest_lat": 19.05,
  "dest_lng": 72.86,
  "origin_name": "Test origin",
  "destination_name": "Test destination"
}
```

   Save the returned numeric `trip_id`. Route creation needs OSRM connectivity.
5. Call `POST /api/v1/trips/{identity}/locations`, using that trip_id as identity:

```json
{"latitude": 19.0440, "longitude": 72.8565}
```

   Expect 201, the hazard in `current_hazards`, and one new `hazard_entry` in
   `alerts`, including trip/tourist identity and coordinates. No ID is hardcoded
   in production; the automated fixture explicitly verifies hazard ID 9.
6. Repeat: `current_hazards` still contains it, but `alerts` is empty.
7. Send `{"latitude":20,"longitude":73}`: that polygon is absent. Send the
   inside location again: one new entry alert appears.
8. Send latitude 91 or longitude 181: expect 422. Remove authorization: 401.
   Use a different tourist or missing trip: 404. Non-numeric identity: 422.
   End the trip and submit a location: 409.
9. Reauthorize as the test admin. `GET /api/v1/admin/trips` shows current warnings
   and recent entries. For inactivity testing, use the existing admin hazard
   edit endpoint to set the copied test hazard's `is_active` to false, then
   authorize as its tourist and submit to a new active trip. It must not alert.
   The automated PostGIS scripts also cover point hazards without adding any
   persistent test records.

## Verification and limits

Implementation checks: backend suite 33 passed / 2 optional tests skipped;
10 actual PostGIS geometry checks passed; temporary-table API/PostGIS scenario
passed; Flutter suite 24 passed; React TypeScript/Vite build passed. Checks use
synthetic fixtures, not a claim that the named real-world area is dangerous.

Physical Android testing has not been performed. Background/killed-app tracking
and push notifications are not implemented. Active trip state is session-scoped
and is not restored after restarting the app. Polling can miss a zone crossed
entirely between GPS samples, and GPS drift near a boundary can cause exit/re-entry.
There is no boundary hysteresis yet. Warnings depend on the accuracy and freshness
of the loaded hazard dataset. Offline updates are not backfilled with invented
locations; the next successful request uses fresh GPS. A network failure does not
clear the last warning. The existing admin polygon editor still creates Polygon
zones; detection/storage also accept MultiPolygon data supplied through a
controlled import.
