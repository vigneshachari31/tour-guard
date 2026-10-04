"""
routers/sos.py
--------------
POST /api/sos/dispatch
  → Receives an SOS alert, logs it, and returns dispatch confirmation.
  (In production: sends push notifications, alerts rangers, etc.)
"""

import uuid
from datetime import datetime, timezone
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api", tags=["SOS"])

# In-memory log (replace with DB in production)
_sos_log: list[dict] = []


class SosRequest(BaseModel):
    latitude:      float
    longitude:     float
    altitude_m:    float | None = None
    user_name:     str
    blood_group:   str   | None = None
    medical_notes: str   | None = None
    allergies:     str   | None = None
    emergency_contact: str | None = None
    location_name: str   | None = None
    device_id:     str   | None = None


class SosResponse(BaseModel):
    incident_id:        str
    status:             str
    eta_minutes:        int
    nearest_unit:       str
    emergency_contacts: list[str]
    message:            str
    timestamp:          str


@router.post("/sos/dispatch", response_model=SosResponse)
def dispatch_sos(req: SosRequest):
    """
    Dispatch an SOS emergency alert.
    Logs the incident and returns simulated rescue coordination info.
    """
    incident_id = f"SOS-{uuid.uuid4().hex[:8].upper()}"
    timestamp   = datetime.now(timezone.utc).isoformat()

    entry = {
        "incident_id": incident_id,
        "timestamp":   timestamp,
        **req.model_dump(),
    }
    _sos_log.append(entry)

    print(f"[SOS DISPATCH] {incident_id} | {req.user_name} @ "
          f"({req.latitude:.5f}, {req.longitude:.5f}) | {timestamp}")

    return SosResponse(
        incident_id  = incident_id,
        status       = "dispatched",
        eta_minutes  = 12,
        nearest_unit = "Ooty Mountain Rescue Unit #3",
        emergency_contacts = ["Police: 112", "Disaster Mgmt: 1077", "Ambulance: 108"],
        message      = (
            f"Emergency received! Incident {incident_id} logged. "
            "Rescue team has been alerted. Stay calm and remain at your location."
        ),
        timestamp = timestamp,
    )


@router.get("/sos/log")
def get_sos_log():
    """Dev endpoint: view all SOS incidents logged this session."""
    return {"count": len(_sos_log), "incidents": _sos_log}

