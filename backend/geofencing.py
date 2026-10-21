"""PostGIS geofencing. Caller holds the trip row lock until commit."""

import json

from geoalchemy2 import Geography
from sqlalchemy import and_, cast, func, or_, select

if __package__:
    from .config import get_settings
    from .models import HazardZone, LocationHistory
else:
    from config import get_settings
    from models import HazardZone, LocationHistory


def hazards_at_location(db, latitude, longitude):
    point = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
    shape_type = func.GeometryType(HazardZone.geometry)
    query = (
        select(HazardZone)
        .where(
            HazardZone.is_active.is_(True),
            or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= func.now()),
            or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > func.now()),
            or_(
                and_(
                    shape_type.in_(["POLYGON", "MULTIPOLYGON"]),
                    func.ST_Covers(HazardZone.geometry, point),
                ),
                and_(
                    shape_type == "POINT",
                    func.ST_DWithin(
                        cast(HazardZone.geometry, Geography(srid=4326)),
                        cast(point, Geography(srid=4326)),
                        get_settings().geofence_point_radius_meters,
                    ),
                ),
            ),
        )
        .order_by(HazardZone.severity.desc(), HazardZone.id)
    )
    return [
        {
            "hazard_id": h.id,
            "name": h.name,
            "hazard_type": h.hazard_type,
            "severity": h.severity,
        }
        for h in db.scalars(query)
    ]


def evaluate_location(db, trip, latitude, longitude, now):
    previous = db.scalar(
        select(LocationHistory)
        .where(LocationHistory.trip_id == trip.id)
        .order_by(LocationHistory.id.desc())
        .limit(1)
    )
    previous_ids = (
        {h["hazard_id"] for h in json.loads(previous.current_hazards or "[]")}
        if previous
        else set()
    )
    current = hazards_at_location(db, latitude, longitude)
    alerts = [
        dict(
            h,
            trip_id=trip.id,
            tourist_id=trip.tourist_id,
            latitude=latitude,
            longitude=longitude,
            detected_at=now.isoformat(),
            kind="hazard_entry",
        )
        for h in current
        if h["hazard_id"] not in previous_ids
    ]
    return current, alerts
