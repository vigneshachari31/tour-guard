from unittest.mock import MagicMock
import httpx
import pytest
from fastapi import Response, HTTPException
from backend.services.risk_engine import calculate_risk_score
from backend.routers.radar import assess_radar


@pytest.mark.parametrize("rain,verified,pending,score,level", [
    (0,0,0,0,"LOW"), (9.99,0,0,0,"LOW"), (10,0,0,20,"LOW"),
    (25,1,1,50,"MODERATE"), (25.01,3,2,100,"HIGH"),
    (0,2,1,30,"LOW"), (0,3,0,40,"MODERATE"),
    (26,1,1,70,"MODERATE"), (26,1,2,80,"HIGH"), (99,99,99,100,"HIGH"),
])
def test_thresholds(rain,verified,pending,score,level):
    result = calculate_risk_score(rain,verified,pending)
    assert result["score"] == score
    assert result["risk_level"] == level


@pytest.mark.parametrize("rain", [-1, float("nan"), float("inf")])
def test_invalid_rain(rain):
    with pytest.raises(ValueError):
        calculate_risk_score(rain,0,0)


def test_endpoint_and_spatial_filters(monkeypatch):
    from sqlalchemy.dialects import postgresql
    db = MagicMock()
    db.scalar.side_effect = [3, 2]
    monkeypatch.setattr("backend.routers.radar.weather_at", lambda *args: {"rainfall_mm_h":26})
    result = assess_radar(Response(), MagicMock(), db, 19, 72)
    assert result["score"] == 100
    queries = [call.args[0].compile(dialect=postgresql.dialect(), compile_kwargs={"literal_binds": True}) for call in db.scalar.call_args_list]
    assert all("ST_DWithin" in str(q) and "2000" in str(q) and "geography" in str(q).lower() for q in queries)
    assert "verified" in str(queries[0])
    assert "pending" in str(queries[1]) and "INTERVAL '3 hours'" in str(queries[1])


def test_weather_unavailable_does_not_return_low(monkeypatch):
    monkeypatch.setattr("backend.routers.radar.weather_at", lambda *args: (_ for _ in ()).throw(httpx.ConnectError("offline")))
    db = MagicMock(); db.scalar.return_value = 0
    with pytest.raises(HTTPException) as error:
        assess_radar(Response(), MagicMock(), db, 19, 72)
    assert error.value.status_code == 503


def test_auth_and_coordinate_validation(client):
    assert client.get("/api/v1/radar/assess?latitude=19&longitude=72").status_code == 401
    from backend.auth import get_current_user
    client.app.dependency_overrides[get_current_user] = lambda: MagicMock()
    assert client.get("/api/v1/radar/assess?latitude=91&longitude=72").status_code == 422


def test_real_postgis_radius_and_recency(monkeypatch):
    import os
    from datetime import datetime, timedelta, timezone
    from geoalchemy2 import WKTElement
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from backend.models import TouristHazardReport
    from backend.tests.database_safety import validated_test_url
    if not os.getenv("TEST_DATABASE_URL"):
        pytest.skip("Separate TEST_DATABASE_URL not configured")
    engine = create_engine(validated_test_url(os.environ["TEST_DATABASE_URL"]))
    monkeypatch.setattr("backend.routers.radar.weather_at", lambda *args: {"rainfall_mm_h":10})
    with Session(engine) as db:
        try:
            now = datetime.now(timezone.utc)
            for status, age, lng in [("verified", 10, 0.01), ("pending", 1, 0.01),
                                     ("pending", 4, 0.01), ("verified", 1, 0.03),
                                     ("rejected", 1, 0.01)]:
                db.add(TouristHazardReport(hazard_type="flood", severity=2, status=status,
                    created_at=now-timedelta(hours=age), location=WKTElement(f"POINT({lng} 0)", srid=4326)))
            db.flush()
            result = assess_radar(Response(), MagicMock(), db, 0, 0)
            assert result["verified_hazards_count"] == 1
            assert result["pending_reports_count"] == 1
            assert result["score"] == 50
        finally:
            db.rollback()
    engine.dispose()
