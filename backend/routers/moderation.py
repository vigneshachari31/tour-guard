"""Admin moderation and verified community map features."""
import json
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select, func
from sqlalchemy.orm import Session

if __package__ == "backend.routers":
    from ..auth import verify_admin
    from ..database import get_db
    from ..models import TouristHazardReport, User
    from ..schemas import InputModel
else:
    from auth import verify_admin
    from database import get_db
    from models import TouristHazardReport, User
    from schemas import InputModel

router = APIRouter(tags=["Hazard moderation"])
DB = Annotated[Session, Depends(get_db)]
Admin = Annotated[User, Depends(verify_admin)]

class ReportStatus(InputModel):
    status: Literal["verified", "rejected"]

def report_rows(db, status=None):
    stmt = select(TouristHazardReport, func.ST_Y(TouristHazardReport.location), func.ST_X(TouristHazardReport.location))
    if status:
        stmt = stmt.where(TouristHazardReport.status == status)
    return [
        dict(id=r.id, hazard_type=r.hazard_type, severity=r.severity,
             description=r.description, latitude=lat, longitude=lng,
             status=r.status, created_at=r.created_at)
        for r, lat, lng in db.execute(stmt.order_by(TouristHazardReport.created_at.desc(), TouristHazardReport.id.desc()))
    ]

@router.get("/api/v1/admin/hazards/reports")
def reports(admin: Admin, db: DB, response: Response,
            status: Literal["pending", "verified", "rejected"] | None = None):
    response.headers["Cache-Control"] = "no-store"
    return report_rows(db, status)

@router.patch("/api/v1/admin/hazards/reports/{report_id}/status")
def moderate(report_id: int, body: ReportStatus, admin: Admin, db: DB):
    report = db.scalar(select(TouristHazardReport).where(TouristHazardReport.id == report_id).with_for_update())
    if report is None:
        raise HTTPException(404, "Report not found")
    report.status = body.status
    db.commit()
    return {"id": report_id, "status": body.status}

def verified_features(db):
    return [
        {"type": "Feature", "id": -r["id"],
         "geometry": {"type": "Point", "coordinates": [r["longitude"], r["latitude"]]},
         "properties": {"id": -r["id"], "report_id": r["id"],
                        "name": r["description"] or r["hazard_type"],
                        "hazard_type": r["hazard_type"], "severity": r["severity"],
                        "source": "Verified tourist report", "is_active": True, "status": "verified"}}
        for r in report_rows(db, "verified")
    ]

@router.get("/api/v1/hazards/public")
def public_reports(db: DB, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return {"type": "FeatureCollection", "features": verified_features(db)}
