"""routers/hazards.py
------------------
GET /api/hazards/nearby?lat=&lon=&radius=
  → Returns real/simulated hazard markers around the user's coordinates.

POST /api/v1/hazards/report
  → Dedicated endpoint to submit tourist hazard reports into `tourist_hazard_reports`.
"""

import math
import random
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

if __package__ and "." in __package__:
    from ..auth import get_current_user
    from ..database import get_db
    from ..models import TouristHazardReport, User
    from ..schemas import TouristHazardReportCreate, TouristHazardReportResponse
else:
    from auth import get_current_user
    from database import get_db
    from models import TouristHazardReport, User
    from schemas import TouristHazardReportCreate, TouristHazardReportResponse

router = APIRouter(tags=["Hazards"])
DB = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]

# ── Static hazards for popular tourist & demo hubs ───────────────────────────
DEMO_HAZARDS = [
    # Mumbai region (Live phone GPS test)
    {
        "id": 101,
        "type": "flood",
        "severity": "high",
        "lat": 19.0430,
        "lon": 72.8480,
        "title": "Mahim Waterlogging Alert",
        "description": "High tide & rainfall advisory. Waterlogged near railway subway.",
    },
    {
        "id": 102,
        "type": "road",
        "severity": "medium",
        "lat": 19.0280,
        "lon": 72.8420,
        "title": "Dadar Traffic & Road Work",
        "description": "Lane restriction due to flyover maintenance; 15 min delay.",
    },
    {
        "id": 103,
        "type": "weather",
        "severity": "medium",
        "lat": 19.0550,
        "lon": 72.8300,
        "title": "Bandra Coastal Wind Gust",
        "description": "Strong sea gusts up to 45 km/h along seaface corridor.",
    },
    {
        "id": 104,
        "type": "landslide",
        "severity": "low",
        "lat": 19.0600,
        "lon": 72.8650,
        "title": "Sion Hill Road Caution",
        "description": "Minor gravel slippage detected on elevated bypass ramp.",
    },
    # Nilgiris / Ooty region (Hill Station Demo Hub)
    {
        "id": 1,
        "type": "landslide",
        "severity": "high",
        "lat": 11.4102,
        "lon": 76.6950,
        "title": "Landslide Risk Zone",
        "description": "Heavy rains reported; road crumbling near km 42.",
    },
    {
        "id": 2,
        "type": "flood",
        "severity": "medium",
        "lat": 11.3700,
        "lon": 76.7200,
        "title": "Flash Flood Warning",
        "description": "Pykara river overflow possible in next 6 hours.",
    },
    {
        "id": 3,
        "type": "fog",
        "severity": "low",
        "lat": 11.4312,
        "lon": 76.7135,
        "title": "Dense Fog Advisory",
        "description": "Visibility < 50 m on Doddabetta road.",
    },
    {
        "id": 4,
        "type": "animal",
        "severity": "medium",
        "lat": 11.5850,
        "lon": 76.6300,
        "title": "Wild Elephant Crossing",
        "description": "Herd spotted near Mudumalai buffer zone.",
    },
    {
        "id": 5,
        "type": "road",
        "severity": "high",
        "lat": 11.3550,
        "lon": 76.7500,
        "title": "Road Closure",
        "description": "NH-67 blocked due to boulder fall; use alternate route.",
    },
    {
        "id": 6,
        "type": "weather",
        "severity": "critical",
        "lat": 11.4500,
        "lon": 76.7000,
        "title": "Thunderstorm Alert",
        "description": "IMD red alert: severe thunderstorm expected by 17:00 IST.",
    },
]

SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3}


class Hazard(BaseModel):
    id: int
    type: str
    severity: str
    lat: float
    lon: float
    title: str
    description: str
    distance_km: float


def _haversine(lat1, lon1, lat2, lon2) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


@router.get("/api/hazards/nearby", response_model=list[Hazard])
@router.get("/hazards/nearby", response_model=list[Hazard])
def get_nearby_hazards(
    lat: float = Query(..., description="User latitude"),
    lon: float = Query(..., description="User longitude"),
    radius: float = Query(50.0, description="Search radius in km"),
):
    """
    Returns hazards within `radius` km of the given coordinate.
    If no static hazards exist nearby, synthesizes 4 realistic local hazards.
    """
    results: list[Hazard] = []
    for h in DEMO_HAZARDS:
        dist = _haversine(lat, lon, h["lat"], h["lon"])
        if dist <= radius:
            results.append(Hazard(**h, distance_km=round(dist, 2)))

    # If no hazards in range (e.g. testing from an unmapped coordinate),
    # generate 4 nearby hazards around user's current GPS:
    if len(results) < 2:
        templates = [
            (
                "landslide",
                "high",
                "Active Terrain Hazard",
                "Slope erosion and loose debris reported along hillside bend.",
            ),
            (
                "flood",
                "medium",
                "Flash Water Accumulation",
                "Waterlogging alert on low-lying segment; slow down.",
            ),
            (
                "fog",
                "low",
                "Reduced Visibility Fog",
                "Dense mist corridor; headlights recommended.",
            ),
            (
                "road",
                "high",
                "Emergency Roadwork Zone",
                "Single-lane restriction in effect due to structural repair.",
            ),
        ]
        rng = random.Random(int(abs(lat * 1000) + abs(lon * 1000)))
        for i, (htype, hsev, htitle, hdesc) in enumerate(templates):
            d_lat = rng.uniform(-0.02, 0.02)
            d_lon = rng.uniform(-0.02, 0.02)
            h_lat = lat + d_lat
            h_lon = lon + d_lon
            dist = _haversine(lat, lon, h_lat, h_lon)
            results.append(
                Hazard(
                    id=900 + i,
                    type=htype,
                    severity=hsev,
                    lat=round(h_lat, 5),
                    lon=round(h_lon, 5),
                    title=htitle,
                    description=hdesc,
                    distance_km=round(dist, 2),
                )
            )

    results.sort(key=lambda x: (SEVERITY_ORDER.get(x.severity, 99), x.distance_km))
    return results


@router.post(
    "/api/v1/hazards/report",
    response_model=TouristHazardReportResponse,
    status_code=201,
    tags=["Hazards"],
)
def report_tourist_hazard(
    body: TouristHazardReportCreate,
    user: CurrentUser,
    db: DB,
) -> TouristHazardReportResponse:
    """
    Dedicated endpoint for tourist-submitted hazard reports.
    Writes strictly to `tourist_hazard_reports` with status 'pending'.
    Does NOT write to official `hazard_zones`.
    """
    geom = func.ST_SetSRID(func.ST_MakePoint(body.longitude, body.latitude), 4326)
    description = body.description or getattr(body, "name", None)
    report = TouristHazardReport(
        tourist_id=user.tourist_id,
        hazard_type=body.hazard_type,
        severity=body.severity,
        description=description,
        location=geom,
        status="pending",
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return TouristHazardReportResponse(
        id=report.id,
        tourist_id=report.tourist_id,
        hazard_type=report.hazard_type,
        severity=report.severity,
        description=report.description,
        name=report.description or report.hazard_type,
        latitude=body.latitude,
        longitude=body.longitude,
        status=report.status,
        created_at=report.created_at,
        message="Tourist hazard report submitted successfully and is pending review.",
    )
