"""No production writes: isolated SQLite fixtures and mocked spatial lookup."""

import pytest
from starlette.websockets import WebSocketDisconnect

from backend.database import get_db
from backend.models import Trip
from backend.tests.test_admin import account
from backend.tests.test_geofencing import setup_trip


def token(headers):
    return headers["Authorization"].split(" ")[1]


def read_event(ws, event):
    for _ in range(20):
        message = ws.receive_json()
        if message.get("event") == event:
            return message
    raise AssertionError(f"Missing {event}")


def test_stream_arrival_and_admin_sync(client, monkeypatch):
    monkeypatch.setattr("backend.geofencing.hazards_at_location", lambda *args: [])
    identity, tourist = setup_trip(client)
    _, _, admin, _ = account(client, "admin")
    assert (
        client.patch(f"/api/v1/trips/{identity}/complete", headers=tourist).status_code
        == 409
    )
    assert client.get("/api/v1/admin/active-trips", headers=tourist).status_code == 403
    with client.websocket_connect("/ws/admin/active-trips") as desk:
        desk.send_json({"token": token(admin)})
        initial = read_event(desk, "SNAPSHOT")
        assert initial["items"][0]["id"] == identity
        with client.websocket_connect(f"/ws/trips/{identity}/track") as tracker:
            tracker.send_json({"token": token(tourist)})
            assert tracker.receive_json()["event"] == "READY"
            tracker.send_json({"lat": 95, "lng": 72})
            assert tracker.receive_json()["event"] == "ERROR"
            # A claimed zero distance must not complete a distant trip.
            tracker.send_json({"lat": 19.04, "lng": 72.85, "distance_remaining": 0})
            update = tracker.receive_json()
            assert update["status"] == "IN_PROGRESS"
            assert update["distance_remaining"] > 30
            moving = read_event(desk, "LOCATION_UPDATE")
            assert moving["current_lat"] == 19.04
            tracker.send_json({"lat": 19.05, "lng": 72.86})
            completed = tracker.receive_json()
            assert completed["event"] == "TRIP_COMPLETED"
            assert completed["completed_at"]
        done = read_event(desk, "TRIP_COMPLETED")
        assert done["trip_id"] == identity
        assert done["trip"]["dest_lat"] == 19.05
    assert (
        client.patch(f"/api/v1/trips/{identity}/complete", headers=tourist).status_code
        == 200
    )
    assert client.get("/api/v1/admin/active-trips", headers=admin).json()["items"] == []
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        trip = db.get(Trip, identity)
        assert trip.status == "completed" and trip.completed_at is not None
    finally:
        provider.close()


@pytest.mark.parametrize("admin_channel", [False, True])
def test_stream_rejects_unauthorized_or_other_tourist(client, admin_channel):
    identity, _ = setup_trip(client)
    _, _, other, _ = account(client)
    path = "/ws/admin/active-trips" if admin_channel else f"/ws/trips/{identity}/track"
    with client.websocket_connect(path) as ws:
        ws.send_json({"token": token(other)})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
        assert exc.value.code == 1008


def test_cancel_does_not_claim_arrival(client, monkeypatch):
    monkeypatch.setattr("backend.geofencing.hazards_at_location", lambda *args: [])
    identity, headers = setup_trip(client)
    result = client.post(f"/api/v1/trips/{identity}/end", headers=headers)
    assert result.json()["status"] == "cancelled"
    assert (
        client.patch(f"/api/v1/trips/{identity}/complete", headers=headers).status_code
        == 409
    )


def test_start_preserves_route_and_real_initial_position(client, monkeypatch):
    from backend.main import get_http
    from backend.schemas import RouteGeometry

    _, _, headers, _ = account(client)
    monkeypatch.setattr(
        "backend.main.fetch_routes",
        lambda *args: [(
            RouteGeometry(
                type="LineString", coordinates=[(72.85, 19.04), (72.86, 19.05)]
            ),
            1500,
            300,
        )],
    )
    monkeypatch.setattr("backend.main.nearby_hazards", lambda *args: [])
    client.app.dependency_overrides[get_http] = lambda: None
    body = {
        "origin_lat": 19.04,
        "origin_lng": 72.85,
        "dest_lat": 19.05,
        "dest_lng": 72.86,
        "origin_name": "Source",
        "destination_name": "Destination",
        "initial_position": {"latitude": 19.041, "longitude": 72.851},
    }
    preview = client.post("/api/v1/route/analyze", headers=headers, json=body)
    assert preview.json()["trip_id"] is None
    response = client.post("/api/v1/trips/start", headers=headers, json=body)
    assert response.status_code == 201
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        trip = db.get(Trip, response.json()["trip_id"])
        assert trip.status == "active"
        assert trip.source_name == "Source" and trip.destination_name == "Destination"
        assert trip.last_latitude == 19.041 and trip.origin_lat == 19.04
        assert trip.route_geometry and trip.updated_at and trip.started_at
    finally:
        provider.close()
