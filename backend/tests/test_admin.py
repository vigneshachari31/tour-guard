"""Admin regressions use isolated storage. No writes to the application database."""

import os
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from backend.auth import create_access_token
from backend.config import get_settings
from backend.database import get_db
from backend.main import create_app
from backend.models import User
from backend.tests.database_safety import validated_test_url


def account(client, role="tourist"):
    email = f"{uuid4().hex}@example.com"
    password = "Admin-test-only-password-42"
    registered = client.post(
        "/api/v1/auth/register", json={"email": email, "password": password}
    )
    assert registered.status_code == 201, registered.text
    if role == "admin":
        provider = client.app.dependency_overrides[get_db]()
        db = next(provider)
        try:
            user = db.scalar(select(User).where(User.email == email))
            user.role = "admin"
            db.commit()
        finally:
            provider.close()
    headers = {"Authorization": "Bearer " + registered.json()["access_token"]}
    return email, password, headers, registered.json()["tourist_id"]


def test_admin_login_and_database_authoritative_rbac(client):
    email, password, tourist, _ = account(client)
    assert (
        client.post(
            "/api/v1/admin/auth/login", json={"email": email, "password": password}
        ).status_code
        == 403
    )
    for path in [
        "auth/me",
        "dashboard/stats",
        "dashboard/charts",
        "incidents",
        "responders",
        "hazards",
        "trips",
        "risk-assessments",
        "users",
        "audit-logs",
    ]:
        assert client.get("/api/v1/admin/" + path).status_code == 401
        assert client.get("/api/v1/admin/" + path, headers=tourist).status_code == 403
    # Even an admin role claim cannot override a tourist's database role.
    settings = get_settings()
    claims = jwt.decode(
        tourist["Authorization"][7:],
        settings.jwt_secret.get_secret_value(),
        algorithms=["HS256"],
        audience=settings.jwt_audience,
        issuer=settings.jwt_issuer,
    )
    forged = create_access_token(int(claims["sub"]), "admin")
    assert (
        client.get(
            "/api/v1/admin/users", headers={"Authorization": "Bearer " + forged}
        ).status_code
        == 403
    )
    email, password, _, _ = account(client, "admin")
    login = client.post(
        "/api/v1/admin/auth/login", json={"email": email, "password": password}
    )
    assert login.status_code == 200
    token = login.json()["access_token"]
    assert (
        jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=["HS256"],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
        )["role"]
        == "admin"
    )
    assert login.headers["cache-control"] == "no-store"
    assert (
        client.post(
            "/api/v1/auth/register",
            json={
                "email": "escalate@example.com",
                "password": password,
                "role": "admin",
            },
        ).status_code
        == 422
    )


def test_incident_workflow_assignment_audit_and_tourist_isolation(client):
    _, _, admin, _ = account(client, "admin")
    _, _, tourist, tourist_id = account(client)
    _, _, other, _ = account(client)
    event = client.post(
        "/api/v1/sos/trigger",
        headers=tourist,
        json={"tourist_id": tourist_id, "latitude": 11.4, "longitude": 76.7},
    )
    assert event.status_code == 201 and event.json()["status"] == "active"
    identity = event.json()["id"]
    path = f"/api/v1/admin/incidents/{identity}"
    assert client.get("/api/v1/sos/events", headers=other).json()["total"] == 0
    assert client.get(path, headers=tourist).status_code == 403
    assert (
        client.patch(
            path + "/status",
            headers=admin,
            json={
                "status": "RESOLVED",
                "expected_status": "OPEN",
                "note": "invalid jump",
            },
        ).status_code
        == 409
    )
    assert (
        client.patch(
            path + "/status",
            headers=admin,
            json={
                "status": "IN_PROGRESS",
                "expected_status": "OPEN",
                "note": "no responder",
            },
        ).status_code
        == 409
    )
    responder = client.post(
        "/api/v1/admin/responders",
        headers=admin,
        json={"name": "Test Rescue", "phone": "+12025550123"},
    ).json()
    second = client.post(
        "/api/v1/admin/responders",
        headers=admin,
        json={"name": "Second Rescue", "phone": "+12025550124"},
    ).json()
    assert (
        client.post(
            path + "/assign",
            headers=admin,
            json={"responder_id": responder["id"], "note": "Assigned duty"},
        ).status_code
        == 200
    )
    assert (
        client.post(
            path + "/assign",
            headers=admin,
            json={"responder_id": second["id"], "note": "Shift change"},
        ).status_code
        == 200
    )
    assert (
        client.patch(
            path + "/status",
            headers=admin,
            json={
                "status": "IN_PROGRESS",
                "expected_status": "OPEN",
                "note": "Response started",
            },
        ).status_code
        == 200
    )
    assert (
        client.patch(
            path + "/status",
            headers=admin,
            json={
                "status": "RESOLVED",
                "expected_status": "OPEN",
                "note": "Stale screen",
            },
        ).status_code
        == 409
    )
    assert (
        client.patch(
            path + "/status",
            headers=admin,
            json={
                "status": "RESOLVED",
                "expected_status": "IN_PROGRESS",
                "note": "Tourist reached safe shelter",
            },
        ).status_code
        == 200
    )
    details = client.get(path, headers=admin).json()
    assert details["status"] == "RESOLVED"
    assert [h["new_status"] for h in details["history"]] == ["IN_PROGRESS", "RESOLVED"]
    assert [a["status"] for a in details["assignments"]] == ["reassigned", "completed"]
    assert (
        client.get("/api/v1/sos/events?status=resolved", headers=tourist).json()[
            "total"
        ]
        == 1
    )
    assert all(
        r["status"] == "available"
        for r in client.get("/api/v1/admin/responders", headers=admin).json()["items"]
    )
    assert (
        client.post(
            path + "/assign",
            headers=admin,
            json={"responder_id": responder["id"], "note": "closed"},
        ).status_code
        == 409
    )
    actions = [
        a["action"]
        for a in client.get("/api/v1/admin/audit-logs", headers=admin).json()["items"]
    ]
    assert "INCIDENT_STATUS" in actions and "INCIDENT_ASSIGN" in actions


def test_soft_deactivation_revokes_existing_token_and_blocks_login(client):
    _, _, admin, _ = account(client, "admin")
    email, password, tourist, _ = account(client)
    users = client.get("/api/v1/admin/users?search=" + email, headers=admin).json()
    assert users["total"] == 1
    identity = users["items"][0]["id"]
    assert (
        client.patch(
            f"/api/v1/admin/users/{identity}", headers=admin, json={"is_active": False}
        ).status_code
        == 200
    )
    assert client.get("/api/v1/profile/me", headers=tourist).status_code == 401
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}
        ).status_code
        == 401
    )
    assert (
        client.patch(
            f"/api/v1/admin/users/{identity}", headers=admin, json={"is_active": True}
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}
        ).status_code
        == 200
    )


def test_trip_risk_history_and_location_ownership(client, monkeypatch):
    monkeypatch.setattr("backend.geofencing.hazards_at_location", lambda *args: [])
    from backend.main import get_http
    from backend.schemas import RouteGeometry

    _, _, tourist, _ = account(client)
    _, _, other, _ = account(client)
    _, _, admin, _ = account(client, "admin")
    monkeypatch.setattr(
        "backend.main.fetch_routes",
        lambda *args: [(
            RouteGeometry(type="LineString", coordinates=[(76.7, 11.4), (76.8, 11.5)]),
            3300,
            300,
        )],
    )
    monkeypatch.setattr("backend.main.nearby_hazards", lambda *args: [])
    client.app.dependency_overrides[get_http] = lambda: None
    result = client.post(
        "/api/v1/trips/start",
        headers=tourist,
        json={
            "origin_lat": 11.4,
            "origin_lng": 76.7,
            "dest_lat": 11.5,
            "dest_lng": 76.8,
            "origin_name": "Test origin",
            "destination_name": "Test destination",
            "start_trip": True,
        },
    )
    assert result.status_code == 201
    identity = result.json()["trip_id"]
    trips = client.get("/api/v1/admin/trips", headers=admin).json()["items"]
    assert (
        trips[0]["stale_location"] is True and trips[0]["source_name"] == "Test origin"
    )
    body = {"latitude": 11.41, "longitude": 76.71}
    assert (
        client.post(
            f"/api/v1/trips/{identity}/locations", headers=other, json=body
        ).status_code
        == 404
    )
    assert (
        client.post(
            f"/api/v1/trips/{identity}/locations", headers=tourist, json=body
        ).status_code
        == 201
    )
    assert (
        client.get("/api/v1/admin/trips", headers=admin).json()["items"][0][
            "stale_location"
        ]
        is False
    )
    risk = client.get("/api/v1/admin/risk-assessments", headers=admin).json()["items"][
        0
    ]
    assert (
        risk["trip_id"] == identity
        and risk["risk_level"] == "CAUTION"
        and risk["reasons"]
    )
    assert (
        client.post(f"/api/v1/trips/{identity}/end", headers=other).status_code == 404
    )
    assert (
        client.post(f"/api/v1/trips/{identity}/end", headers=tourist).json()["status"]
        == "cancelled"
    )
    assert (
        client.post(
            f"/api/v1/trips/{identity}/locations", headers=tourist, json=body
        ).status_code
        == 409
    )


@pytest.mark.skipif(
    not os.getenv("TEST_DATABASE_URL"),
    reason="Separate TEST_DATABASE_URL not configured",
)
def test_postgis_admin_polygon_and_spatial_query():
    from backend.risk_engine import nearby_hazards
    from backend.schemas import RouteGeometry

    engine = create_engine(validated_test_url(os.environ["TEST_DATABASE_URL"]))
    # Endpoints can commit savepoints, but the outer test transaction always rolls back.
    with engine.connect() as connection:
        transaction = connection.begin()
        app = create_app()

        def database():
            with Session(
                bind=connection, join_transaction_mode="create_savepoint"
            ) as db:
                yield db

        app.dependency_overrides[get_db] = database
        try:
            with TestClient(app) as client:
                _, _, admin, _ = account(client, "admin")
                body = {
                    "name": "Isolated test polygon",
                    "hazard_type": "flood",
                    "severity": 4,
                    "source": "Automated isolated test",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [
                            [
                                [0, -0.001],
                                [0.01, -0.001],
                                [0.01, 0.001],
                                [0, 0.001],
                                [0, -0.001],
                            ]
                        ],
                    },
                }
                created = client.post("/api/v1/admin/hazards", headers=admin, json=body)
                assert created.status_code == 201, created.text
                identity = created.json()["id"]
                with Session(
                    bind=connection, join_transaction_mode="create_savepoint"
                ) as db:
                    hazards = nearby_hazards(
                        db,
                        RouteGeometry(
                            type="LineString", coordinates=[(0, 0), (0.01, 0)]
                        ),
                        250,
                    )
                    assert identity in [h.id for h in hazards]
                assert (
                    client.get("/api/v1/admin/dashboard/stats", headers=admin).json()[
                        "active_hazards"
                    ]
                    >= 1
                )
                assert (
                    client.get(
                        "/api/v1/admin/dashboard/charts", headers=admin
                    ).status_code
                    == 200
                )
                assert (
                    client.patch(
                        f"/api/v1/admin/hazards/{identity}",
                        headers=admin,
                        json={"is_active": False},
                    ).status_code
                    == 200
                )
                features = client.get("/api/v1/admin/hazards", headers=admin).json()[
                    "features"
                ]
                assert identity not in [f["id"] for f in features]
                with Session(
                    bind=connection, join_transaction_mode="create_savepoint"
                ) as db:
                    assert identity not in [
                        h.id
                        for h in nearby_hazards(
                            db,
                            RouteGeometry(
                                type="LineString", coordinates=[(0, 0), (0.01, 0)]
                            ),
                            250,
                        )
                    ]
                body["geometry"]["coordinates"] = [
                    [[0, 0], [1, 1], [0, 1], [1, 0], [0, 0]]
                ]
                assert (
                    client.post(
                        "/api/v1/admin/hazards", headers=admin, json=body
                    ).status_code
                    == 422
                )
        finally:
            transaction.rollback()
    engine.dispose()


def test_admin_login_rate_limit(client):
    for _ in range(10):
        result = client.post(
            "/api/v1/admin/auth/login",
            json={"email": "missing@example.com", "password": "wrong"},
        )
        assert result.status_code == 401
    result = client.post(
        "/api/v1/admin/auth/login",
        json={"email": "missing@example.com", "password": "wrong"},
    )
    assert result.status_code == 429 and result.headers["retry-after"] == "60"
