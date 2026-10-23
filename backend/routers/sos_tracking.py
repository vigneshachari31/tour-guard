"""SOS telemetry and dispatcher-recorded responder confirmations."""
import json
from datetime import datetime, timezone
from typing import Annotated, Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import AwareDatetime, Field
from sqlalchemy import select
from sqlalchemy.orm import Session
if __package__ == "backend.routers":
    from ..auth import get_current_user, verify_admin
    from ..database import get_db
    from ..models import SOSEvent, SOSHistory, RescueAssignment, Responder, User
    from ..schemas import InputModel, Latitude, Longitude
else:
    from auth import get_current_user, verify_admin
    from database import get_db
    from models import SOSEvent, SOSHistory, RescueAssignment, Responder, User
    from schemas import InputModel, Latitude, Longitude

router = APIRouter(tags=["SOS tracking"])
DB = Annotated[Session, Depends(get_db)]
Tourist = Annotated[User, Depends(get_current_user)]
Admin = Annotated[User, Depends(verify_admin)]

class LocationInput(InputModel):
    latitude: Latitude
    longitude: Longitude
    accuracy: float = Field(ge=0, le=100000)
    captured_at: AwareDatetime

class ProgressInput(InputModel):
    stage: Literal["ACCEPTED", "DEPARTED", "ARRIVED"]
    assignment_id: int
    note: str = Field(min_length=3, max_length=1000)

def latest(db, identity, kind):
    return db.scalar(select(SOSHistory).where(
        SOSHistory.sos_event_id == identity, SOSHistory.new_status == kind
    ).order_by(SOSHistory.id.desc()).limit(1))

def tracking_details(db, event):
    assignment = db.scalar(select(RescueAssignment).where(
        RescueAssignment.sos_event_id == event.id, RescueAssignment.status == "assigned"))
    responder = db.get(Responder, assignment.responder_id) if assignment else None
    progress = latest(db, event.id, "RESPONDER_PROGRESS")
    progress_data = json.loads(progress.notes) if progress else {}
    stage = progress_data.get("stage") if assignment and progress_data.get("assignment_id") == assignment.id else None
    location = latest(db, event.id, "GPS_UPDATE")
    coordinates = json.loads(location.notes) if location else {
        "latitude": event.latitude, "longitude": event.longitude,
        "captured_at": event.created_at.isoformat(), "accuracy": None}
    at = datetime.fromisoformat(coordinates["captured_at"].replace("Z", "+00:00"))
    if at.tzinfo is None:
        at = at.replace(tzinfo=timezone.utc)
    coordinates["stale"] = (datetime.now(timezone.utc) - at).total_seconds() > 60
    return {"responder": {"id": responder.id, "name": responder.name, "phone": responder.phone,
             "assignment_id": assignment.id} if responder else None,
            "responder_stage": stage or ("ASSIGNED" if assignment else "UNASSIGNED"),
            "sos_location": coordinates}

@router.post("/api/v1/sos/events/{identity}/location")
def update_location(identity: int, body: LocationInput, user: Tourist, db: DB):
    event = db.scalar(select(SOSEvent).where(SOSEvent.id == identity,
        SOSEvent.tourist_id == user.tourist_id).with_for_update())
    if not event:
        raise HTTPException(404, "SOS not found")
    if event.workflow_status not in ("OPEN", "IN_PROGRESS"):
        raise HTTPException(409, "SOS is closed")
    age = (datetime.now(timezone.utc) - body.captured_at).total_seconds()
    if age < -10 or age > 120:
        raise HTTPException(422, "Send a fresh GPS reading")
    previous = latest(db, identity, "GPS_UPDATE")
    if previous and datetime.fromisoformat(json.loads(previous.notes)["captured_at"].replace("Z", "+00:00")) >= body.captured_at:
        return {"recorded": False}
    db.add(SOSHistory(sos_event_id=identity, old_status=event.workflow_status,
        new_status="GPS_UPDATE", changed_by_id=user.id, notes=body.model_dump_json()))
    db.commit()
    return {"recorded": True}

@router.patch("/api/v1/admin/incidents/{identity}/progress")
def update_progress(identity: int, body: ProgressInput, admin: Admin, db: DB):
    event = db.scalar(select(SOSEvent).where(SOSEvent.id == identity).with_for_update())
    if not event:
        raise HTTPException(404, "SOS not found")
    if event.workflow_status not in ("OPEN", "IN_PROGRESS"):
        raise HTTPException(409, "SOS is closed")
    details = tracking_details(db, event)
    if not details["responder"] or details["responder"]["assignment_id"] != body.assignment_id:
        raise HTTPException(409, "Assignment changed. Refresh before continuing.")
    expected = {"ASSIGNED": "ACCEPTED", "ACCEPTED": "DEPARTED", "DEPARTED": "ARRIVED"}
    if expected.get(details["responder_stage"]) != body.stage:
        raise HTTPException(409, "Invalid or outdated responder progress")
    db.add(SOSHistory(sos_event_id=identity, old_status=event.workflow_status,
        new_status="RESPONDER_PROGRESS", changed_by_id=admin.id, notes=body.model_dump_json()))
    if body.stage == "ACCEPTED":
        db.add(SOSHistory(sos_event_id=identity, old_status=event.workflow_status,
            new_status="IN_PROGRESS", changed_by_id=admin.id, notes=body.note))
        event.workflow_status = "IN_PROGRESS"
    db.commit()
    return tracking_details(db, event)
