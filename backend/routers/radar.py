"""Authenticated location radar; live inputs and explicitly experimental ML."""
from datetime import datetime, timezone
from typing import Annotated
import httpx
from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import select, func, cast, or_
from geoalchemy2 import Geography
from sqlalchemy.orm import Session
if __package__ == "backend.routers":
    from ..auth import get_current_user
    from ..database import get_db
    from ..models import HazardZone, TouristHazardReport, User
    from ..ml_model.radar_model import infer
else:
    from auth import get_current_user
    from database import get_db
    from models import HazardZone, TouristHazardReport, User
    from ml_model.radar_model import infer
router = APIRouter(tags=["Risk radar"])

def weather_at(lat, lng):
    with httpx.Client(timeout=10) as client:
        response = client.get("https://api.open-meteo.com/v1/forecast", params={
            "latitude":lat, "longitude":lng, "hourly":"precipitation,wind_speed_10m,temperature_2m",
            "forecast_hours":1, "timezone":"UTC", "wind_speed_unit":"kmh"})
        response.raise_for_status()
        data = response.json()
        h = data["hourly"]
        stamp = datetime.fromisoformat(h["time"][0]).replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc)-stamp).total_seconds()
        if not -300 <= age <= 5400:
            raise ValueError("Weather is stale")
        if data["hourly_units"]["precipitation"] != "mm" or data["hourly_units"]["wind_speed_10m"] != "km/h":
            raise ValueError("Unexpected weather units")
        return {"rainfall_mm_h":float(h["precipitation"][0]), "wind_kmh":float(h["wind_speed_10m"][0]),
                "temperature_c":float(h["temperature_2m"][0]), "at":stamp.isoformat(),
                "source":"Open-Meteo hourly forecast"}

@router.get("/api/v1/risk/radar")
def radar(response: Response, user: Annotated[User, Depends(get_current_user)],
          db: Annotated[Session, Depends(get_db)],
          latitude: float = Query(ge=-90, le=90), longitude: float = Query(ge=-180, le=180)):
    response.headers["Cache-Control"] = "no-store"
    point = cast(func.ST_SetSRID(func.ST_MakePoint(longitude, latitude),4326), Geography(srid=4326))
    hazards = []
    for model, geom, condition in [
        (HazardZone, HazardZone.geometry, HazardZone.is_active.is_(True) &
         or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= func.now()) &
         or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > func.now())),
        (TouristHazardReport, TouristHazardReport.location, TouristHazardReport.status == "verified"),
    ]:
        for h in db.scalars(select(model).where(condition, func.ST_DWithin(cast(geom, Geography(srid=4326)), point, 1000))):
            hazards.append({"name": getattr(h,"name",None) or getattr(h,"description",None) or h.hazard_type,
                            "severity":h.severity, "type":h.hazard_type})
    severity = max((h["severity"] for h in hazards), default=0)
    try:
        weather = weather_at(latitude, longitude)
    except (httpx.HTTPError, KeyError, ValueError, TypeError, IndexError):
        weather = None
    prediction = infer([weather["rainfall_mm_h"],weather["wind_kmh"],len(hazards),severity]) if weather else {
        "available":False, "reason":"Live weather unavailable; model assessment withheld"}
    return {"radius_m":1000, "hazards":hazards, "weather":weather, "model":prediction,
            "warning": "Experimental AI trained on synthetic examples. Not a safety guarantee.",
            "coverage": "Absence of reports does not establish safety.",
            "hazard_alert": "HIGH" if severity >= 4 else "CAUTION" if hazards else "NO REPORTS",
            "checked_at": datetime.now(timezone.utc).isoformat()}
