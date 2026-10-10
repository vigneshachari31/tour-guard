"""Transparent demonstration thresholds, not a trained or validated ML model."""

import math
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import HTTPException
from geoalchemy2 import Geography
from pydantic import ValidationError
from sqlalchemy import cast, func, select
from sqlalchemy.orm import Session

try:
    from .config import get_settings
    from .models import HazardZone
    from .schemas import (
        HazardSummary,
        RiskAssessment,
        RouteGeometry,
        RouteRequest,
        WeatherObservation,
    )
except ImportError:
    from config import get_settings
    from models import HazardZone
    from schemas import (
        HazardSummary,
        RiskAssessment,
        RouteGeometry,
        RouteRequest,
        WeatherObservation,
    )


def fetch_route(
    request: RouteRequest, client: httpx.Client
) -> tuple[RouteGeometry, float, float]:
    coordinates = f"{request.origin_lng},{request.origin_lat};{request.dest_lng},{request.dest_lat}"
    try:
        response = client.get(
            f"{get_settings().osrm_base_url}/route/v1/driving/{coordinates}",
            params={
                "overview": "full",
                "geometries": "geojson",
                "alternatives": "false",
            },
        )
        response.raise_for_status()
        data = response.json()
        if data.get("code") == "NoRoute":
            raise HTTPException(422, "No drivable route found between these points")
        if data.get("code") != "Ok":
            raise ValueError("OSRM did not return a route")
        route = data["routes"][0]
        geometry = RouteGeometry.model_validate(route["geometry"])
        distance, duration = float(route["distance"]), float(route["duration"])
        if not all(math.isfinite(x) and x >= 0 for x in (distance, duration)):
            raise ValueError("Invalid route metrics")
        return geometry, distance, duration
    except httpx.TimeoutException as exc:
        raise HTTPException(504, "Routing service timed out; retry later") from exc
    except (
        httpx.HTTPError,
        ValueError,
        KeyError,
        IndexError,
        TypeError,
        AttributeError,
        ValidationError,
    ) as exc:
        raise HTTPException(
            502, "Routing service returned an invalid response"
        ) from exc


def nearby_hazards(
    db: Session, geometry: RouteGeometry, buffer_meters: float
) -> list[HazardSummary]:
    route = cast(
        func.ST_SetSRID(func.ST_GeomFromGeoJSON(geometry.model_dump_json()), 4326),
        Geography(srid=4326),
    )
    query = (
        select(HazardZone)
        .where(
            func.ST_DWithin(
                cast(HazardZone.geometry, Geography(srid=4326)), route, buffer_meters
            )
        )
        .order_by(HazardZone.severity.desc(), HazardZone.id)
        .limit(1001)
    )
    hazards = db.scalars(query).all()
    if len(hazards) > 1000:
        raise HTTPException(
            422, "Route intersects too many hazard records; analyze a shorter route"
        )
    return [
        HazardSummary(
            id=h.id,
            name=h.name,
            hazard_type=h.hazard_type,
            severity=h.severity,
            source=h.source or "Source not recorded",
        )
        for h in hazards
    ]


def assess_risk(
    hazards: list[HazardSummary],
    weather: WeatherObservation | None,
    coverage_verified: bool,
    *,
    now: datetime | None = None,
) -> RiskAssessment:
    now = now or datetime.now(timezone.utc)
    reasons: list[str] = []
    limitations = [
        "Heuristic thresholds are not validated predictions or a guarantee of safety."
    ]
    severity = max((h.severity for h in hazards), default=0)
    rank = 2 if severity >= 4 else 1 if hazards else 0
    if hazards:
        reasons.append(
            f"{len(hazards)} hazard zone(s) within the route buffer; maximum severity {severity}/5."
        )
    else:
        reasons.append("No matching hazards found in the loaded dataset.")
    weather_used = weather is not None and timedelta(
        minutes=-5
    ) <= now - weather.observed_at <= timedelta(hours=1)
    if weather_used and weather is not None:
        limitations.append(
            f"Weather is caller-supplied ({weather.source}), not independently verified; it may not cover the whole route."
        )
        if weather.rainfall_mm_h >= 30 or weather.wind_kmh >= 70:
            rank = 2
            reasons.append(
                "Weather exceeds high-risk rainfall (30 mm/h) or wind (70 km/h) threshold."
            )
        elif weather.rainfall_mm_h >= 10 or weather.wind_kmh >= 40:
            rank = max(rank, 1)
            reasons.append(
                "Weather exceeds caution rainfall (10 mm/h) or wind (40 km/h) threshold."
            )
    else:
        rank = max(rank, 1)
        limitations.append(
            "Weather missing, stale, or future-dated; weather risk was not assessed."
        )
    if not coverage_verified:
        rank = max(rank, 1)
        limitations.append(
            "Hazard coverage has not been verified for this deployment region."
        )
    return RiskAssessment(
        level=("SAFE", "CAUTION", "HIGH RISK")[rank],
        reasons=reasons,
        limitations=limitations,
        weather_used=weather_used,
    )
