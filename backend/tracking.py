"""Shared trip lifecycle. Database state is authoritative across workers."""

import math
from datetime import UTC, datetime

from fastapi import HTTPException

STATUS = {
    "planned": "PLANNED",
    "active": "IN_PROGRESS",
    "completed": "COMPLETED",
    "cancelled": "CANCELLED",
}
ARRIVAL_METERS = 30


def distance_remaining(trip):
    if trip.last_latitude is None or trip.last_longitude is None:
        return None
    a, b = math.radians(trip.last_latitude), math.radians(trip.dest_lat)
    dlat = b - a
    dlng = math.radians(trip.dest_lng - trip.last_longitude)
    h = math.sin(dlat / 2) ** 2 + math.cos(a) * math.cos(b) * math.sin(dlng / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(min(1, max(0, h))))


def complete_trip(trip):
    if trip.status == "completed":
        return
    if trip.status != "active":
        raise HTTPException(409, "Trip is no longer active")
    distance = distance_remaining(trip)
    stamp = trip.last_location_updated_at
    if stamp and stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=UTC)
    if (
        distance is None
        or distance > ARRIVAL_METERS
        or not stamp
        or (datetime.now(UTC) - stamp).total_seconds() > 60
    ):
        raise HTTPException(
            409,
            "A fresh GPS observation within 30 metres of the destination is required",
        )
    trip.status = "completed"
    trip.completed_at = trip.ended_at = trip.updated_at = datetime.now(UTC)


def tracking_fields(trip):
    return {
        "trip_id": trip.id,
        "tourist_id": trip.tourist_id,
        "status": STATUS.get(trip.status, trip.status),
        "source_lat": trip.origin_lat,
        "source_lng": trip.origin_lng,
        "source_address": trip.source_name,
        "dest_address": trip.destination_name,
        "current_lat": trip.last_latitude,
        "current_lng": trip.last_longitude,
        "distance_remaining": distance_remaining(trip),
        "created_at": trip.started_at,
        "updated_at": trip.updated_at,
        "completed_at": trip.completed_at,
    }
