# Live trip tracking

## Runtime
- Start the API from the repository root: `backend\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000`.
- Rebuild the React admin after changes with `cd admin_dashboard` then `npm.cmd run build`. Open `/admin/` on the API server, or use `npm.cmd run dev` (Vite forwards `/ws`).
- Restart Flutter after adding web_socket_channel. Android emulators use `10.0.2.2`; physical devices need the computer's reachable LAN address via `--dart-define=API_BASE_URL=http://HOST:8000/api/v1`.
- API migration 0010 adds only updated_at/completed_at. No user/trip records are removed or reclassified. This workspace's application and separate test database have been upgraded.

## Lifecycle and compatibility
Route previews do not start tracking. START TRIP requests device permission, obtains a real initial observation, and calls POST /api/v1/trips/start with the existing route-analysis request plus optional initial_position {latitude, longitude}. The server retains the actual OSRM road geometry. It cancels any previous active trip for that tourist.

Existing database columns remain compatible: origin_lat/lng and source_name represent source; destination_name is the destination address; last_latitude/longitude represent current GPS. Existing stored statuses planned/active/completed/cancelled map to PLANNED/IN_PROGRESS/COMPLETED/CANCELLED in tracking events and lifecycle_status. started_at is created_at; new updated_at and completed_at are timestamps. Existing integer IDs are preserved.

Each received observation computes destination distance on the server, ignoring client distance claims. Within 30 metres, status and completion timestamps are committed atomically. PATCH /api/v1/trips/{id}/complete is idempotent and requires a received location within 30 metres and no older than 60 seconds. POST /end cancels early trips; it does not claim arrival. Lost completion replies can be recovered by retrying an observation for an already completed trip.

## Streams and permissions
- /ws/trips/{id}/track: first frame {"token":"JWT"}; wait for READY; then send {"lat":...,"lng":...}. Replies include geofence warnings and LOCATION_UPDATE/TRIP_COMPLETED. Coordinates and ownership are validated; the JWT/database account is rechecked on every observation and idle heartbeat.
- /ws/admin/active-trips: same first-frame authentication, admin role required. Sends SNAPSHOT, LOCATION_UPDATE, TRIP_COMPLETED, TRIP_CANCELLED and PING. Admin updates use committed database snapshots approximately every second, so separate API workers see the same state. This is bounded-latency database polling over WebSockets, not an external message broker; larger deployments should replace snapshot polling with a shared event transport.
- GET /api/v1/admin/active-trips returns active trips and tourist names only to authenticated admins.
- Tokens are never placed in socket URLs. Deploy HTTPS/WSS and enable WebSocket proxy upgrade forwarding. Reconnect snapshots and 15-second HTTP polling provide recovery for admins. Tourists fall back to authenticated HTTP location posts if the socket fails.

## App behavior and limits
The shared session monitor uses high-accuracy geolocator streaming with a 5-metre distance filter, plus periodic checks for stationary arrival and retry. It continues across screen navigation, pauses when the app leaves the foreground, and cancels subscriptions/sockets when a trip ends, on logout, or when the app-wide monitor is disposed. Native background tracking/terminated-app recovery is not implemented.

Map position and direct destination distance update with GPS; displayed remaining ETA is an estimate based on the original route's average speed, not live traffic or a newly calculated road route. The server confirms arrival before the app shows success. GPS accuracy still depends on the device. Offline positions do not count as confirmed completion until received by the server.

## Verification
Backend tests use isolated SQLite fixtures; optional PostGIS tests require TEST_DATABASE_URL with database name exactly tour_guard_test. Never point tests at tour_guard. `python -m backend.scripts.run_admin_e2e e2e/tracking.spec.ts` seeds an isolated test transaction, drives a real Chrome session, and rolls back fixture records. The browser test verifies the moving marker and green completion flag without reload. Physical movement on a device must still be checked with location permission enabled.
