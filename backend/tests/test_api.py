from datetime import datetime, timedelta, timezone

import httpx
import jwt
import pytest
from fastapi import HTTPException

from backend.config import get_settings
from backend.risk_engine import assess_risk, fetch_route
from backend.schemas import HazardSummary, RouteRequest, WeatherObservation


def register(client, email="tourist@example.com"):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "a-long-test-password",
            "emergency_contact_phone": "+919876543210",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_register_login_duplicate_and_persisted_sos(client):
    account = register(client)
    assert account["tourist_id"].startswith("TG-")
    assert "hashed_password" not in account
    assert (
        client.post(
            "/api/v1/auth/register",
            json={"email": "TOURIST@example.com", "password": "a-long-test-password"},
        ).status_code
        == 409
    )
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "tourist@example.com", "password": "wrong"},
        ).status_code
        == 401
    )
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "tourist@example.com", "password": "a-long-test-password"},
    )
    assert login.status_code == 200
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    body = {"tourist_id": account["tourist_id"], "latitude": 11.4, "longitude": 76.7}
    assert client.post("/api/v1/sos/trigger", json=body).status_code == 401
    result = client.post("/api/v1/sos/trigger", json=body, headers=headers)
    assert result.status_code == 201, result.text
    assert result.json()["status"] == "active"
    assert result.json()["created_at"]
    body["tourist_id"] = register(client, "other@example.com")["tourist_id"]
    assert (
        client.post("/api/v1/sos/trigger", json=body, headers=headers).status_code
        == 403
    )


def test_expired_token_and_coordinate_validation(client):
    account = register(client)
    settings = get_settings()
    token = jwt.encode(
        {
            "sub": "1",
            "iat": datetime.now(timezone.utc) - timedelta(hours=2),
            "exp": datetime.now(timezone.utc) - timedelta(hours=1),
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
        },
        settings.jwt_secret.get_secret_value(),
        algorithm="HS256",
    )
    body = {"tourist_id": account["tourist_id"], "latitude": 0, "longitude": 0}
    assert (
        client.post(
            "/api/v1/sos/trigger",
            json=body,
            headers={"Authorization": f"Bearer {token}"},
        ).status_code
        == 401
    )
    body["latitude"] = 91
    assert (
        client.post(
            "/api/v1/sos/trigger",
            json=body,
            headers={"Authorization": f"Bearer {account['access_token']}"},
        ).status_code
        == 422
    )


def test_risk_thresholds_and_missing_data():
    weather = WeatherObservation(
        rainfall_mm_h=0,
        wind_kmh=5,
        observed_at=datetime.now(timezone.utc),
        source="test observation",
    )
    assert assess_risk([], weather, True).level == "SAFE"
    assert assess_risk([], None, True).level == "CAUTION"
    assert assess_risk([], weather, False).level == "CAUTION"
    hazard = HazardSummary(
        id=1, name="test zone", hazard_type="flood", severity=4, source="test"
    )
    assert assess_risk([hazard], weather, True).level == "HIGH RISK"
    assert (
        assess_risk([], weather.model_copy(update={"rainfall_mm_h": 30}), True).level
        == "HIGH RISK"
    )
    assert not assess_risk(
        [],
        weather.model_copy(
            update={"observed_at": datetime.now(timezone.utc) - timedelta(hours=2)}
        ),
        True,
    ).weather_used


def test_osrm_coordinate_order_and_geometry():
    def handler(request):
        assert request.url.path.endswith("/76.7,11.4;76.8,11.5")
        assert request.url.params["geometries"] == "geojson"
        return httpx.Response(
            200,
            json={
                "code": "Ok",
                "routes": [
                    {
                        "geometry": {
                            "type": "LineString",
                            "coordinates": [[76.7, 11.4], [76.8, 11.5]],
                        },
                        "distance": 14000,
                        "duration": 1800,
                    }
                ],
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        geometry, distance, duration = fetch_route(
            RouteRequest(
                origin_lat=11.4, origin_lng=76.7, dest_lat=11.5, dest_lng=76.8
            ),
            client,
        )
    assert geometry.coordinates[0] == (76.7, 11.4)
    assert (distance, duration) == (14000, 1800)


@pytest.mark.parametrize(
    "body, status", [({"code": "NoRoute"}, 422), ({"code": "Ok", "routes": []}, 502)]
)
def test_osrm_failures(body, status):
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=body))
    ) as client:
        with pytest.raises(HTTPException) as error:
            fetch_route(
                RouteRequest(origin_lat=0, origin_lng=0, dest_lat=1, dest_lng=1), client
            )
        assert error.value.status_code == status


def test_osrm_timeout():
    def timeout(request):
        raise httpx.ReadTimeout("test timeout", request=request)

    with httpx.Client(transport=httpx.MockTransport(timeout)) as client:
        with pytest.raises(HTTPException) as error:
            fetch_route(
                RouteRequest(origin_lat=0, origin_lng=0, dest_lat=1, dest_lng=1), client
            )
        assert error.value.status_code == 504


def test_analyze_endpoint_authentication_and_response(client, monkeypatch):
    from backend.main import get_http
    from backend.schemas import RouteGeometry

    account = register(client)
    body = {"origin_lat": 11.4, "origin_lng": 76.7, "dest_lat": 11.5, "dest_lng": 76.8}
    assert client.post("/api/v1/route/analyze", json=body).status_code == 401
    geometry = RouteGeometry(
        type="LineString", coordinates=[(76.7, 11.4), (76.8, 11.5)]
    )
    monkeypatch.setattr(
        "backend.main.fetch_route", lambda *args: (geometry, 14000, 1800)
    )
    monkeypatch.setattr("backend.main.nearby_hazards", lambda *args: [])
    client.app.dependency_overrides[get_http] = lambda: None
    response = client.post(
        "/api/v1/route/analyze",
        json=body,
        headers={"Authorization": f"Bearer {account['access_token']}"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["assessment"]["level"] == "CAUTION"
    assert response.json()["geometry"]["coordinates"][0] == [76.7, 11.4]


def test_database_failure_does_not_leak_sql_or_credentials(client):
    from sqlalchemy.exc import OperationalError

    from backend.database import get_db

    def broken_db():
        raise OperationalError(
            "sensitive SQL", {"password": "private"}, Exception("secret")
        )
        yield  # ensures this is a dependency generator

    client.app.dependency_overrides[get_db] = broken_db
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "tourist@example.com", "password": "a-long-test-password"},
    )
    assert response.status_code == 503
    assert "secret" not in response.text and "password" not in response.text
