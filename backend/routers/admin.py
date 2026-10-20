<<<<<<< HEAD
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
=======
"""Database-backed administration. Every operation checks the current database role."""

import json
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

if __package__ == "backend.routers":
    from ..admin_schemas import (
        ActivationInput,
        AssignmentInput,
        HazardInput,
        HazardPatch,
        IncidentStatus,
        ResponderInput,
        StatusUpdate,
    )
    from ..auth import create_access_token, verify_admin, verify_password
    from ..config import get_settings
    from ..database import get_db
    from ..models import (
        AuditLog,
        HazardZone,
        RescueAssignment,
        Responder,
        RiskAssessmentLog,
        SOSEvent,
        SOSHistory,
        Trip,
        User,
        UserProfile,
    )
    from ..schemas import LoginRequest
else:
    from admin_schemas import (
        ActivationInput,
        AssignmentInput,
        HazardInput,
        HazardPatch,
        IncidentStatus,
        ResponderInput,
        StatusUpdate,
    )
    from auth import create_access_token, verify_admin, verify_password
    from config import get_settings
    from database import get_db
    from models import (
        AuditLog,
        HazardZone,
        RescueAssignment,
        Responder,
        RiskAssessmentLog,
        SOSEvent,
        SOSHistory,
        Trip,
        User,
        UserProfile,
    )
    from schemas import LoginRequest

router = APIRouter(prefix="/api/v1/admin", tags=["Administration"])
DB = Annotated[Session, Depends(get_db)]
Admin = Annotated[User, Depends(verify_admin)]
Limit = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0, le=1000000)]


def audit(db, user, action, kind, target=None, details=None):
    db.add(
        AuditLog(
            admin_id=user.id,
            admin_email=user.email,
            action=action,
            resource_type=kind,
            resource_id=str(target) if target is not None else None,
            details=json.dumps(details) if details else None,
        )
    )


def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            409,
            "Record changed or conflicts with another assignment. Refresh and retry.",
        ) from None


def row(obj, fields):
    return {key: getattr(obj, key) for key in fields.split()}


def required(db, model, identity, lock=False):
    stmt = select(model).where(model.id == identity)
    obj = db.scalar(stmt.with_for_update() if lock else stmt)
    if obj is None:
        raise HTTPException(404, "Record not found")
    return obj


def page(db, stmt, limit, offset, serialize):
    total = db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery()))
    return {
        "items": [
            serialize(obj) for obj in db.scalars(stmt.limit(limit).offset(offset))
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


def active_hazards():
    now = datetime.now(timezone.utc)
    return (
        HazardZone.is_active.is_(True),
        or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= now),
        or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > now),
    )


@router.post("/auth/login")
def admin_login(body: LoginRequest, db: DB, response: Response):
    user = db.scalar(select(User).where(User.email == body.email))
    if (
        not verify_password(body.password, user.hashed_password if user else None)
        or not user
        or not user.is_active
    ):
        raise HTTPException(401, "Invalid email or password")
    if user.role != "admin":
        raise HTTPException(403, "Administrator access required")
    audit(db, user, "LOGIN", "session")
    commit(db)
    response.headers["Cache-Control"] = "no-store"
    return {
        "access_token": create_access_token(user.id, user.role),
        "token_type": "bearer",
        "expires_in": get_settings().access_token_minutes * 60,
        "user": row(user, "id email full_name role"),
    }


@router.get("/auth/me")
def me(admin: Admin):
    return row(admin, "id email full_name role")


@router.get("/dashboard/stats")
def stats(admin: Admin, db: DB):
    def count(model, *where):
        return db.scalar(select(func.count()).select_from(model).where(*where))

    return {
        "total_users": count(User),
        "active_trips": count(Trip, Trip.status == "active"),
        "open_incidents": count(SOSEvent, SOSEvent.workflow_status == "OPEN"),
        "in_progress_incidents": count(
            SOSEvent, SOSEvent.workflow_status == "IN_PROGRESS"
        ),
        "resolved_incidents": count(SOSEvent, SOSEvent.workflow_status == "RESOLVED"),
        "active_hazards": count(HazardZone, *active_hazards()),
    }


@router.get("/dashboard/charts")
def charts(admin: Admin, db: DB):
    def grouped(column, *where):
        return [
            {"name": str(name), "count": n}
            for name, n in db.execute(
                select(column, func.count())
                .where(*where)
                .group_by(column)
                .order_by(column)
            )
        ]

    day = func.date(SOSEvent.created_at)
    return {
        "incidents_over_time": grouped(
            day, SOSEvent.created_at >= datetime.now(timezone.utc) - timedelta(days=30)
        ),
        "incident_status": grouped(SOSEvent.workflow_status),
        "hazard_categories": grouped(HazardZone.hazard_type, *active_hazards()),
        "risk_buckets": grouped(RiskAssessmentLog.risk_level),
        "risk_bucket_note": "Recorded heuristic risk levels; no numeric ML score is produced by the current engine.",
    }


def trip_dict(db, trip):
    result = row(
        trip,
        "id tourist_id source_name destination_name origin_lat origin_lng dest_lat dest_lng status started_at ended_at last_latitude last_longitude last_location_updated_at",
    )
    stamp = trip.last_location_updated_at
    if stamp and stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    result["stale_location"] = stamp is None or stamp < datetime.now(
        timezone.utc
    ) - timedelta(minutes=15)
    result["route_geometry"] = (
        json.loads(trip.route_geometry) if trip.route_geometry else None
    )
    risk = db.scalar(
        select(RiskAssessmentLog)
        .where(RiskAssessmentLog.trip_id == trip.id)
        .order_by(RiskAssessmentLog.id.desc())
        .limit(1)
    )
    result["risk_level"] = risk.risk_level if risk else None
    return result


def incident_dict(db, incident):
    result = row(incident, "id tourist_id latitude longitude created_at")
    result["status"] = incident.workflow_status
    user = db.scalar(select(User).where(User.tourist_id == incident.tourist_id))
    profile = (
        db.scalar(select(UserProfile).where(UserProfile.user_id == user.id))
        if user
        else None
    )
    result["tourist"] = {
        "full_name": (profile.full_name if profile else None)
        or (user.full_name if user else None),
        "email": user.email if user else None,
        "phone": (profile.phone_number if profile else None)
        or (user.emergency_contact_phone if user else None),
    }
    trip = db.scalar(
        select(Trip)
        .where(Trip.tourist_id == incident.tourist_id)
        .order_by(Trip.id.desc())
        .limit(1)
    )
    result["last_location"] = (
        {
            "latitude": trip.last_latitude,
            "longitude": trip.last_longitude,
            "at": trip.last_location_updated_at,
        }
        if trip and trip.last_location_updated_at
        else {
            "latitude": incident.latitude,
            "longitude": incident.longitude,
            "at": incident.created_at,
        }
    )
    assignment = db.scalar(
        select(RescueAssignment).where(
            RescueAssignment.sos_event_id == incident.id,
            RescueAssignment.status == "assigned",
        )
    )
    result["responder_id"] = assignment.responder_id if assignment else None
    return result


@router.get("/incidents")
def incidents(
    admin: Admin,
    db: DB,
    status: IncidentStatus | None = None,
    limit: Limit = 25,
    offset: Offset = 0,
):
    stmt = select(SOSEvent).order_by(SOSEvent.id.desc())
    if status:
        stmt = stmt.where(SOSEvent.workflow_status == status)
    return page(db, stmt, limit, offset, lambda obj: incident_dict(db, obj))


@router.get("/incidents/{identity}")
def incident_detail(identity: int, admin: Admin, db: DB):
    incident = required(db, SOSEvent, identity)
    result = incident_dict(db, incident)
    user = db.scalar(select(User).where(User.tourist_id == incident.tourist_id))
    profile = (
        db.scalar(select(UserProfile).where(UserProfile.user_id == user.id))
        if user
        else None
    )
    result["emergency_profile"] = (
        row(profile, "blood_group emergency_contact medical_notes allergies")
        if profile
        else None
    )
    result["history"] = [
        row(h, "id old_status new_status changed_by_id notes created_at")
        for h in db.scalars(
            select(SOSHistory)
            .where(SOSHistory.sos_event_id == identity)
            .order_by(SOSHistory.id)
        )
    ]
    result["assignments"] = [
        row(a, "id responder_id assigned_by_id status notes created_at updated_at")
        for a in db.scalars(
            select(RescueAssignment)
            .where(RescueAssignment.sos_event_id == identity)
            .order_by(RescueAssignment.id)
        )
    ]
    result["trips"] = [
        trip_dict(db, t)
        for t in db.scalars(
            select(Trip)
            .where(Trip.tourist_id == incident.tourist_id)
            .order_by(Trip.id.desc())
            .limit(20)
        )
    ]
    return result


def release_assignment(db, incident_id, status):
    assignments = list(
        db.scalars(
            select(RescueAssignment)
            .where(
                RescueAssignment.sos_event_id == incident_id,
                RescueAssignment.status == "assigned",
            )
            .with_for_update()
        )
    )
    for assignment in assignments:
        responder = required(db, Responder, assignment.responder_id, True)
        assignment.status = status
        responder.status = "available"
    db.flush()


@router.patch("/incidents/{identity}/status")
def update_status(identity: int, body: StatusUpdate, admin: Admin, db: DB):
    incident = required(db, SOSEvent, identity, True)
    old = incident.workflow_status
    transitions = {
        "OPEN": {"IN_PROGRESS", "CANCELLED"},
        "IN_PROGRESS": {"RESOLVED", "CANCELLED"},
        "RESOLVED": set(),
        "CANCELLED": set(),
    }
    if old != body.expected_status or body.status not in transitions.get(old, set()):
        raise HTTPException(
            409, "Stale or invalid incident transition. Refresh the incident."
        )
    if body.status == "IN_PROGRESS" and not db.scalar(
        select(RescueAssignment.id).where(
            RescueAssignment.sos_event_id == identity,
            RescueAssignment.status == "assigned",
        )
    ):
        raise HTTPException(409, "Assign a responder before starting response")
    incident.workflow_status = body.status
    incident.status = (
        "resolved" if body.status in ("RESOLVED", "CANCELLED") else "active"
    )
    if body.status in ("RESOLVED", "CANCELLED"):
        release_assignment(
            db, identity, "completed" if body.status == "RESOLVED" else "cancelled"
        )
    db.add(
        SOSHistory(
            sos_event_id=identity,
            old_status=old,
            new_status=body.status,
            changed_by_id=admin.id,
            notes=body.note,
        )
    )
    audit(
        db,
        admin,
        "INCIDENT_STATUS",
        "incident",
        identity,
        {"from": old, "to": body.status, "note": body.note},
    )
    commit(db)
    return incident_dict(db, incident)


@router.post("/incidents/{identity}/assign")
def assign(identity: int, body: AssignmentInput, admin: Admin, db: DB):
    incident = required(db, SOSEvent, identity, True)
    if incident.workflow_status not in ("OPEN", "IN_PROGRESS"):
        raise HTTPException(409, "Closed incidents cannot be assigned")
    # Lock all involved responder rows in ID order to avoid cross-reassignment deadlocks.
    current = db.scalar(
        select(RescueAssignment).where(
            RescueAssignment.sos_event_id == identity,
            RescueAssignment.status == "assigned",
        )
    )
    ids = {body.responder_id}
    if current:
        ids.add(current.responder_id)
    responders = {
        r.id: r
        for r in db.scalars(
            select(Responder)
            .where(Responder.id.in_(ids))
            .order_by(Responder.id)
            .with_for_update()
        )
    }
    responder = responders.get(body.responder_id)
    if responder is None:
        raise HTTPException(404, "Responder not found")
    if current and current.responder_id == body.responder_id:
        raise HTTPException(409, "Responder is already assigned to this incident")
    if responder.status != "available":
        raise HTTPException(409, "Responder is unavailable or already assigned")
    release_assignment(db, identity, "reassigned")
    responder.status = "assigned"
    db.add(
        RescueAssignment(
            sos_event_id=identity,
            responder_id=responder.id,
            assigned_by_id=admin.id,
            notes=body.note,
        )
    )
    audit(
        db,
        admin,
        "INCIDENT_ASSIGN",
        "incident",
        identity,
        {"responder_id": responder.id, "note": body.note},
    )
    commit(db)
    return incident_dict(db, incident)


@router.get("/responders")
def responders(admin: Admin, db: DB, limit: Limit = 25, offset: Offset = 0):
    def serialize(responder):
        result = row(responder, "id name phone email role status")
        result["assignments"] = [
            row(a, "id sos_event_id status created_at updated_at")
            for a in db.scalars(
                select(RescueAssignment)
                .where(RescueAssignment.responder_id == responder.id)
                .order_by(RescueAssignment.id.desc())
                .limit(100)
            )
        ]
        return result

    return page(db, select(Responder).order_by(Responder.id), limit, offset, serialize)


@router.post("/responders")
def save_responder(body: ResponderInput, admin: Admin, db: DB):
    responder = required(db, Responder, body.id, True) if body.id else Responder()
    if body.id and responder.status == "assigned":
        raise HTTPException(
            409,
            "Complete or reassign the active incident before editing this responder",
        )
    for key, value in body.model_dump(exclude={"id"}).items():
        setattr(responder, key, value)
    db.add(responder)
    db.flush()
    audit(db, admin, "RESPONDER_SAVE", "responder", responder.id)
    commit(db)
    return row(responder, "id name phone email role status")


def polygon_expression(db, polygon):
    geometry = func.ST_SetSRID(func.ST_GeomFromGeoJSON(polygon.model_dump_json()), 4326)
    if not db.scalar(select(func.ST_IsValid(geometry))) or db.scalar(
        select(func.ST_IsEmpty(geometry))
    ):
        raise HTTPException(
            422, "Polygon is empty or self-intersects; correct its boundaries"
        )
    return geometry


@router.get("/hazards")
def hazards(admin: Admin, db: DB, include_inactive: bool = False):
    stmt = select(HazardZone, func.ST_AsGeoJSON(HazardZone.geometry)).order_by(
        HazardZone.id
    )
    if not include_inactive:
        stmt = stmt.where(*active_hazards())
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": h.id,
                "geometry": json.loads(geometry),
                "properties": row(
                    h,
                    "id name hazard_type severity source is_active valid_from valid_until updated_at",
                ),
            }
            for h, geometry in db.execute(stmt)
        ],
    }


@router.post("/hazards", status_code=201)
def create_hazard(body: HazardInput, admin: Admin, db: DB):
    hazard = HazardZone(
        **body.model_dump(exclude={"geometry"}),
        geometry=polygon_expression(db, body.geometry),
    )
    db.add(hazard)
    db.flush()
    audit(db, admin, "HAZARD_CREATE", "hazard", hazard.id)
    commit(db)
    return {"id": hazard.id}


@router.patch("/hazards/{identity}")
def patch_hazard(identity: int, body: HazardPatch, admin: Admin, db: DB):
    hazard = required(db, HazardZone, identity, True)
    changes = body.model_dump(exclude_unset=True, exclude={"geometry"})
    for key, value in changes.items():
        if value is None and key not in ("valid_from", "valid_until"):
            raise HTTPException(422, f"{key} cannot be null")
        setattr(hazard, key, value)
    if (
        hazard.valid_from
        and hazard.valid_until
        and hazard.valid_until <= hazard.valid_from
    ):
        raise HTTPException(422, "Valid until must be after valid from")
    if body.geometry:
        hazard.geometry = polygon_expression(db, body.geometry)
    hazard.updated_at = datetime.now(timezone.utc)
    audit(
        db,
        admin,
        "HAZARD_UPDATE",
        "hazard",
        identity,
        {"fields": list(body.model_fields_set)},
    )
    commit(db)
    return {"id": identity}


@router.get("/trips")
def trips(
    admin: Admin,
    db: DB,
    status: Annotated[str | None, Query(pattern="^(active|completed)$")] = None,
    limit: Limit = 25,
    offset: Offset = 0,
):
    stmt = select(Trip).order_by(Trip.id.desc())
    if status:
        stmt = stmt.where(Trip.status == status)
    return page(db, stmt, limit, offset, lambda t: trip_dict(db, t))


@router.get("/risk-assessments")
def risks(admin: Admin, db: DB, limit: Limit = 25, offset: Offset = 0):
    def serialize(risk):
        result = row(
            risk,
            "id user_id trip_id origin_lat origin_lng dest_lat dest_lng risk_level distance_meters duration_seconds hazards_count weather_used created_at",
        )
        for field in ("reasons", "limitations"):
            value = getattr(risk, field)
            try:
                parsed = json.loads(value) if value else []
                result[field] = parsed if isinstance(parsed, list) else [str(parsed)]
            except ValueError:
                result[field] = [value]
        return result

    return page(
        db,
        select(RiskAssessmentLog).order_by(RiskAssessmentLog.id.desc()),
        limit,
        offset,
        serialize,
    )


@router.get("/users")
def users(
    admin: Admin,
    db: DB,
    search: Annotated[str, Query(max_length=200)] = "",
    limit: Limit = 25,
    offset: Offset = 0,
):
    stmt = select(User).where(User.role == "tourist").order_by(User.id.desc())
    if search:
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        stmt = stmt.where(
            or_(
                User.email.ilike(f"%{escaped}%", escape="\\"),
                User.full_name.ilike(f"%{escaped}%", escape="\\"),
                User.tourist_id.ilike(f"%{escaped}%", escape="\\"),
            )
        )

    def serialize(user):
        result = row(user, "id email full_name tourist_id is_active")
        profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user.id))
        result["phone_number"] = (
            profile.phone_number if profile else user.emergency_contact_phone
        )
        return result

    return page(db, stmt, limit, offset, serialize)


@router.patch("/users/{identity}")
def activate_user(identity: int, body: ActivationInput, admin: Admin, db: DB):
    user = required(db, User, identity, True)
    if user.role != "tourist":
        raise HTTPException(
            403, "Admin accounts cannot be changed through tourist management"
        )
    user.is_active = body.is_active
    audit(db, admin, "USER_ACTIVATION", "user", identity, {"is_active": body.is_active})
    commit(db)
    return row(user, "id is_active")


@router.get("/audit-logs")
def logs(admin: Admin, db: DB, limit: Limit = 25, offset: Offset = 0):
    return page(
        db,
        select(AuditLog).order_by(AuditLog.id.desc()),
        limit,
        offset,
        lambda log: row(
            log,
            "id admin_id admin_email action resource_type resource_id details created_at",
        ),
    )
>>>>>>> e2f60aa148e362ce2472a0aa4680086ef97e4f15
