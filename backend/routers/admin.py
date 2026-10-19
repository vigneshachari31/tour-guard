"""Authenticated Rescue Command endpoints.

Only accounts pre-approved with ``users.role = 'admin'`` may access these APIs.
Never promote an account from a public endpoint.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from geoalchemy2.shape import to_shape
from shapely.geometry import mapping, shape
from sqlalchemy import select
from sqlalchemy.orm import Session

if __package__ and "." in __package__:
    from ..auth import get_current_admin
    from ..database import get_db
    from ..models import HazardZone, SOSEvent, User, UserProfile
    from ..schemas import (
        AdminHazardCreate,
        AdminHazardResponse,
        AdminSOSResponse,
        SOSStatusUpdate,
    )
else:
    from auth import get_current_admin
    from database import get_db
    from models import HazardZone, SOSEvent, User, UserProfile
    from schemas import (
        AdminHazardCreate,
        AdminHazardResponse,
        AdminSOSResponse,
        SOSStatusUpdate,
    )

router = APIRouter(prefix="/api/v1/admin", tags=["Rescue Command"])
DB = Annotated[Session, Depends(get_db)]
Admin = Annotated[User, Depends(get_current_admin)]


def as_hazard(hazard: HazardZone) -> AdminHazardResponse:
    geometry = mapping(to_shape(hazard.geometry))
    return AdminHazardResponse(
        id=hazard.id, name=hazard.name, hazard_type=hazard.hazard_type,
        severity=hazard.severity, source=hazard.source, is_active=hazard.is_active,
        geometry=geometry, updated_at=hazard.updated_at,
    )


@router.get("/sos-events", response_model=list[AdminSOSResponse])
def list_sos_events(_: Admin, db: DB) -> list[AdminSOSResponse]:
    rows = db.execute(
        select(SOSEvent, User, UserProfile)
        .join(User, User.tourist_id == SOSEvent.tourist_id)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .order_by(SOSEvent.created_at.desc())
        .limit(500)
    ).all()
    return [
        AdminSOSResponse(
            id=event.id, tourist_id=event.tourist_id, latitude=event.latitude,
            longitude=event.longitude, status=event.status, created_at=event.created_at,
            full_name=(profile.full_name if profile and profile.full_name else user.full_name),
            phone_number=(profile.phone_number if profile and profile.phone_number else user.emergency_contact_phone),
            blood_group=profile.blood_group if profile else None,
            emergency_contact=profile.emergency_contact if profile else None,
            medical_notes=profile.medical_notes if profile else None,
        ) for event, user, profile in rows
    ]


@router.patch("/sos-events/{event_id}/status", response_model=AdminSOSResponse)
def update_sos_status(event_id: int, body: SOSStatusUpdate, _: Admin, db: DB) -> AdminSOSResponse:
    event = db.get(SOSEvent, event_id)
    if event is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "SOS event not found")
    event.status = body.status
    db.commit()
    row = db.execute(
        select(SOSEvent, User, UserProfile)
        .join(User, User.tourist_id == SOSEvent.tourist_id)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(SOSEvent.id == event_id)
    ).one()
    event, user, profile = row
    return AdminSOSResponse(
        id=event.id, tourist_id=event.tourist_id, latitude=event.latitude,
        longitude=event.longitude, status=event.status, created_at=event.created_at,
        full_name=(profile.full_name if profile and profile.full_name else user.full_name),
        phone_number=(profile.phone_number if profile and profile.phone_number else user.emergency_contact_phone),
        blood_group=profile.blood_group if profile else None,
        emergency_contact=profile.emergency_contact if profile else None,
        medical_notes=profile.medical_notes if profile else None,
    )


@router.get("/hazards", response_model=list[AdminHazardResponse])
def list_hazards(_: Admin, db: DB, include_inactive: bool = False) -> list[AdminHazardResponse]:
    stmt = select(HazardZone).order_by(HazardZone.updated_at.desc(), HazardZone.id.desc())
    if not include_inactive:
        stmt = stmt.where(HazardZone.is_active.is_(True))
    return [as_hazard(hazard) for hazard in db.scalars(stmt).all()]


@router.post("/hazards", response_model=AdminHazardResponse, status_code=status.HTTP_201_CREATED)
def create_hazard(body: AdminHazardCreate, _: Admin, db: DB) -> AdminHazardResponse:
    from geoalchemy2.elements import WKTElement

    polygon = shape(body.geometry.model_dump())
    if not polygon.is_valid or polygon.is_empty:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid polygon geometry")
    hazard = HazardZone(
        name=body.name, hazard_type=body.hazard_type, severity=body.severity,
        source=body.source, geometry=WKTElement(polygon.wkt, srid=4326), is_active=True,
    )
    db.add(hazard)
    db.commit()
    db.refresh(hazard)
    return as_hazard(hazard)


@router.delete("/hazards/{hazard_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_hazard(hazard_id: int, _: Admin, db: DB) -> None:
    hazard = db.get(HazardZone, hazard_id)
    if hazard is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Hazard zone not found")
    hazard.is_active = False
    db.commit()
