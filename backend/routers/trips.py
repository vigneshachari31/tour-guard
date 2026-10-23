import json
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

if __package__ == "backend.routers":
    from ..admin_schemas import LocationInput
    from ..auth import get_current_user
    from ..database import get_db
    from ..geofencing import evaluate_location
    from ..models import LocationHistory, Trip, User
    from ..schemas import TripLocationResponse
    from ..tracking import complete_trip, distance_remaining, tracking_fields
else:
    from admin_schemas import LocationInput
    from auth import get_current_user
    from database import get_db
    from geofencing import evaluate_location
    from models import LocationHistory, Trip, User
    from schemas import TripLocationResponse
    from tracking import complete_trip, distance_remaining, tracking_fields

router = APIRouter(prefix="/api/v1/trips", tags=["Trips"])
DB = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]


def owned_trip(db, user, identity):
    trip = db.scalar(
        select(Trip)
        .where(Trip.id == identity, Trip.tourist_id == user.tourist_id)
        .with_for_update()
    )
    if trip is None:
        raise HTTPException(404, "Trip not found")
    return trip


@router.post("/{identity}/end")
def end_trip(identity: int, user: CurrentUser, db: DB):
    trip = owned_trip(db, user, identity)
    if trip.status == "active":
        trip.status = "cancelled"
        trip.ended_at = datetime.now(UTC)
    db.commit()
    return {"id": trip.id, "status": trip.status}


@router.patch("/{identity}/complete")
def complete(identity: int, user: CurrentUser, db: DB):
    trip = owned_trip(db, user, identity)
    complete_trip(trip)
    db.commit()
    return tracking_fields(trip)


@router.post(
    "/{identity}/locations", status_code=201, response_model=TripLocationResponse
)
def location(identity: int, body: LocationInput, user: CurrentUser, db: DB):
    trip = owned_trip(db, user, identity)
    if trip.status == "completed" and trip.completed_at is not None:
        return {
            **tracking_fields(trip),
            "recorded_at": trip.last_location_updated_at or trip.completed_at,
            "current_hazards": [],
            "alerts": [],
        }
    if trip.status != "active":
        raise HTTPException(409, "Trip is no longer active")
    now = datetime.now(UTC)
    current, alerts = evaluate_location(db, trip, body.latitude, body.longitude, now)
    trip.last_latitude, trip.last_longitude = body.latitude, body.longitude
    trip.last_location_updated_at = now
    db.add(
        LocationHistory(
            trip_id=trip.id,
            latitude=body.latitude,
            longitude=body.longitude,
            recorded_at=now,
            current_hazards=json.dumps(current),
            hazard_alerts=json.dumps(alerts),
        )
    )
    trip.updated_at = now
    if distance_remaining(trip) <= 30:
        complete_trip(trip)
    db.commit()
    return {
        **tracking_fields(trip),
        "trip_id": trip.id,
        "recorded_at": now,
        "current_hazards": current,
        "alerts": alerts,
    }
