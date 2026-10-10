"""Optional real PostGIS test; TEST_DATABASE_URL must reference a migrated test DB."""

import os

import pytest
from geoalchemy2 import WKTElement
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.models import HazardZone
from backend.tests.database_safety import validated_test_url
from backend.risk_engine import nearby_hazards
from backend.schemas import RouteGeometry


@pytest.mark.skipif(
    not os.getenv("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL not configured"
)
def test_meter_buffer_point_polygon_and_remote_exclusion():
    engine = create_engine(validated_test_url(os.environ["TEST_DATABASE_URL"]))
    with Session(engine) as db:
        try:
            records = [
                HazardZone(
                    name="test-near",
                    hazard_type="flood",
                    severity=2,
                    source="integration test",
                    geometry=WKTElement("POINT(0.005 0.001)", srid=4326),
                ),
                HazardZone(
                    name="test-far",
                    hazard_type="flood",
                    severity=2,
                    source="integration test",
                    geometry=WKTElement("POINT(0.005 0.02)", srid=4326),
                ),
                HazardZone(
                    name="test-polygon",
                    hazard_type="landslide",
                    severity=4,
                    source="integration test",
                    geometry=WKTElement(
                        "POLYGON((0.004 -0.001,0.006 -0.001,0.006 0.001,0.004 0.001,0.004 -0.001))",
                        srid=4326,
                    ),
                ),
            ]
            db.add_all(records)
            db.flush()
            result = nearby_hazards(
                db,
                RouteGeometry(type="LineString", coordinates=[(0, 0), (0.01, 0)]),
                250,
            )
            ids = {h.id for h in result}
            assert records[0].id in ids
            assert records[1].id not in ids
            assert records[2].id in ids
        finally:
            db.rollback()
    engine.dispose()
