"""Read-only spatial checks using CTE fixtures, never inserts/updates/deletes.

Run explicitly: python -m backend.tests.check_geofence_postgis
Uses the configured PostGIS connection, but reads only inline fixture values.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import patch

from sqlalchemy import Boolean, DateTime, Integer, String, func, literal, select, text
from sqlalchemy.orm import Session, aliased

from backend.database import get_engine
from backend.geofencing import hazards_at_location
from backend.models import HazardZone

POLYGON = "POLYGON((72.85563203 19.044743219,72.857853272 19.044783785,72.857574276 19.043505941,72.855835912 19.042877157,72.85563203 19.044743219))"


def fixture(wkt, active=True, valid_until=None, valid_from=None):
    values = {
        "id": literal(9, Integer),
        "name": literal("dangerous zone", String),
        "hazard_type": literal("landslide", String),
        "severity": literal(4, Integer),
        "geometry": func.ST_GeomFromText(wkt, 4326),
        "source": literal("isolated CTE test", String),
        "is_active": literal(active, Boolean),
        "valid_from": literal(valid_from, DateTime(timezone=True)),
        "valid_until": literal(valid_until, DateTime(timezone=True)),
        "updated_at": func.now(),
    }
    cte = select(*(value.label(key) for key, value in values.items())).cte(
        "test_hazards"
    )
    return aliased(HazardZone, cte, adapt_on_names=True)


def main():
    engine = get_engine()
    now = datetime.now(UTC)
    cases = [
        ("inside polygon", POLYGON, 19.0440, 72.8565, {}, True),
        ("outside polygon", POLYGON, 20, 73, {}, False),
        ("polygon boundary", POLYGON, 19.044743219, 72.85563203, {}, True),
        ("inactive polygon", POLYGON, 19.0440, 72.8565, {"active": False}, False),
        (
            "expired polygon",
            POLYGON,
            19.0440,
            72.8565,
            {"valid_until": now - timedelta(days=1)},
            False,
        ),
        (
            "future polygon",
            POLYGON,
            19.0440,
            72.8565,
            {"valid_from": now + timedelta(days=1)},
            False,
        ),
        ("near point", "POINT(72.8565 19.0440)", 19.0441, 72.8565, {}, True),
        ("distant point", "POINT(72.8565 19.0440)", 20, 73, {}, False),
        (
            "multipolygon",
            "MULTIPOLYGON(" + POLYGON[7:] + ")",
            19.0440,
            72.8565,
            {},
            True,
        ),
        (
            "polygon hole",
            "POLYGON((0 0,4 0,4 4,0 4,0 0),(1 1,1 3,3 3,3 1,1 1))",
            2,
            2,
            {},
            False,
        ),
    ]
    with Session(engine) as db:
        db.execute(text("SET TRANSACTION READ ONLY"))
        for label, wkt, lat, lng, options, expected in cases:
            with patch("backend.geofencing.HazardZone", fixture(wkt, **options)):
                result = hazards_at_location(db, lat, lng)
                assert bool(result) == expected, label
                if expected:
                    assert result[0]["hazard_id"] == 9, label
            print(f"PASS: {label}")
        db.rollback()
    engine.dispose()


if __name__ == "__main__":
    main()
