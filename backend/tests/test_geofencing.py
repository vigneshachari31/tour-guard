"""Request/transaction tests use SQLite with an isolated spatial-query mock.

Actual PostGIS predicates are checked by check_geofence_postgis.py.
"""

import json

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import OperationalError

from backend.database import get_db
from backend.models import LocationHistory, Trip
from backend.tests.test_admin import account


def setup_trip(client):
    _, _, headers, tourist_id = account(client)
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        trip = Trip(
            tourist_id=tourist_id,
            destination_name="Test destination",
            origin_lat=19.04,
            origin_lng=72.85,
            dest_lat=19.05,
            dest_lng=72.86,
        )
        db.add(trip)
        db.commit()
        identity = trip.id
    finally:
        provider.close()
    return identity, headers


def post(client, identity, headers, latitude=19.0440, longitude=72.8565):
    return client.post(
        f"/api/v1/trips/{identity}/locations",
        headers=headers,
        json={"latitude": latitude, "longitude": longitude},
    )


def test_entry_repeat_exit_reentry_and_admin_history(client, monkeypatch):
    identity, headers = setup_trip(client)
    hazard = {
        "hazard_id": 9,
        "name": "dangerous zone",
        "hazard_type": "landslide",
        "severity": 4,
    }
    calls = []

    def spatial_mock(db, lat, lng):
        calls.append((lat, lng))
        return [hazard] if (lat, lng) == (19.0440, 72.8565) else []

    monkeypatch.setattr("backend.geofencing.hazards_at_location", spatial_mock)
    first = post(client, identity, headers)
    assert first.status_code == 201, first.text
    alert = first.json()["alerts"][0]
    assert alert["hazard_id"] == 9 and alert["trip_id"] == identity
    assert alert["latitude"] == 19.0440 and alert["longitude"] == 72.8565
    assert first.json()["current_hazards"] == [hazard]
    assert post(client, identity, headers).json()["alerts"] == []
    outside = post(client, identity, headers, 20, 73).json()
    assert outside["alerts"] == [] and outside["current_hazards"] == []
    assert len(post(client, identity, headers).json()["alerts"]) == 1
    assert len(calls) == 4
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        rows = db.scalars(select(LocationHistory).order_by(LocationHistory.id)).all()
        assert len(rows) == 4
        assert [len(json.loads(r.hazard_alerts)) for r in rows] == [1, 0, 0, 1]
        assert db.get(Trip, identity).last_latitude == 19.0440
    finally:
        provider.close()
    _, _, admin, _ = account(client, "admin")
    result = client.get("/api/v1/admin/trips", headers=admin).json()["items"][0]
    assert result["current_hazards"] == [hazard]
    assert len(result["recent_hazard_alerts"]) == 2


@pytest.mark.parametrize("latitude,longitude", [(91, 0), (-91, 0), (0, 181), (0, -181)])
def test_invalid_coordinates(client, latitude, longitude):
    identity, headers = setup_trip(client)
    assert post(client, identity, headers, latitude, longitude).status_code == 422


def test_auth_ownership_missing_invalid_and_completed_trip(client, monkeypatch):
    monkeypatch.setattr("backend.geofencing.hazards_at_location", lambda *args: [])
    identity, headers = setup_trip(client)
    _, _, other, _ = account(client)
    assert post(client, identity, {}).status_code == 401
    assert (
        post(client, identity, {"Authorization": "Bearer invalid"}).status_code == 401
    )
    assert post(client, identity, other).status_code == 404
    assert post(client, 999999, headers).status_code == 404
    assert post(client, "not-an-id", headers).status_code == 422
    assert post(client, identity, headers).json()["alerts"] == []
    assert (
        client.post(f"/api/v1/trips/{identity}/end", headers=headers).status_code == 200
    )
    assert post(client, identity, headers).status_code == 409


def test_spatial_failure_is_not_success_and_saves_nothing(client, monkeypatch):
    identity, headers = setup_trip(client)

    def fail(*args):
        raise OperationalError("spatial query", {}, Exception("test failure"))

    monkeypatch.setattr("backend.geofencing.hazards_at_location", fail)
    assert post(client, identity, headers).status_code == 503
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        assert db.scalar(select(func.count(LocationHistory.id))) == 0
        assert db.get(Trip, identity).last_latitude is None
    finally:
        provider.close()
