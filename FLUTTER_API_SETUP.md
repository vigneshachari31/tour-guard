# Flutter / FastAPI integration

The app uses `ApiService.instance` for registration, login, authenticated route
assessment, and SOS. JWT and tourist ID are persisted with flutter_secure_storage.
HTTP 401 on a protected endpoint clears the expired session and returns to login.
Registration requires a password of at least 12 characters. Name and mobile fields
on the existing registration form are not submitted to the email/password API.

## Run locally

Configure `backend/.env` with your real PostGIS database credentials and JWT secret,
then apply the migrations described in `backend/README.md`. Do not overwrite an
existing `.env`. From the repository root, start the backend:

```powershell
venv\Scripts\python.exe -m uvicorn backend.main:app --reload --reload-dir backend
```

In a second terminal:

```powershell
flutter pub get
flutter run -d emulator-5554
```

Android emulator defaults to `http://10.0.2.2:8000/api/v1`; desktop and web default
to `http://127.0.0.1:8000/api/v1`. Fully restart the app after adding secure storage.
Allow location permission and set a GPS position in the emulator's location controls.

For Chrome, use `flutter run -d chrome --web-port 3000` and ensure the exact browser
origin is allowed in the backend `CORS_ORIGINS` JSON array, for example
`["http://localhost:3000","http://127.0.0.1:3000"]`. Restart the backend after changes.

Override the address for a physical device or deployed backend:

```powershell
flutter run --dart-define=API_BASE_URL=https://your-api.example.com/api/v1
```

On a physical phone, localhost refers to the phone; use a reachable server address.
Local HTTP is for development; use HTTPS for deployed credentials and locations.

## Connected flows

- Login and registration save the returned session before opening the dashboard.
- Dashboard search opens the original dual-source/destination planner, calls the backend,
  draws its GeoJSON route, and displays the risk, hazards, reasons, and limitations.
  The dashboard also retains the last successful assessment during its lifetime.
- The SOS confirmation countdown sends fresh coordinates with the authenticated
  tourist ID. A recorded event does not confirm emergency responder dispatch.
- The service accepts `WeatherObservation` for actual observations. The UI omits
  weather until a real source is connected; it never labels fabricated readings IMD.

Legacy `map_screen.dart` and `backend_service.dart` remain as reference code;
dashboard and `/map` use `BackendRouteScreen` and the v1 API instead.
Place search and basemap tiles require access to their public map providers.

```powershell
flutter analyze
flutter test
```

API tests use a mock HTTP client; they do not send real SOS events or establish
that your local PostGIS server is configured.

Local Flutter web can also use random ports when `CORS_ALLOW_LOCALHOST=true`
in `backend/.env`. This allows only HTTP localhost/127.0.0.1 origins. Keep it
false in production and configure exact `CORS_ORIGINS`. Restart the API after
changing environment settings. `/health/live` checks the API process;
`/health/ready` must return 200 before accounts can be stored in PostGIS.
