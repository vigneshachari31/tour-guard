# travel_risk_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Run the Tour Guard backend

Start the FastAPI service from the `backend` directory:

```powershell
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

The API documentation is available at `http://localhost:8000/docs`.

The Flutter app defaults to `http://10.0.2.2:8000`, the Android emulator
address for a backend running on the development computer. For a physical
device or another target, use the computer's LAN IP address:

```powershell
flutter run --dart-define=API_BASE_URL=http://<computer-ip>:8000
```

The map requests risk estimates and nearby hazards after a route is selected.
Risk estimates currently use sample environmental inputs; hazard reports and
SOS acknowledgements are demo backend data. SOS requests are logged by the
backend and do not contact emergency services.
