"""Transparent demonstration thresholds, not a trained or validated ML model."""

import json
import math
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import HTTPException
from geoalchemy2 import Geography
from pydantic import ValidationError
from sqlalchemy import cast, func, or_, select
from sqlalchemy.orm import Session

try:
    from .config import get_settings
    from .models import HazardZone, TouristHazardReport
    from .schemas import (
        HazardSummary,
        RiskAssessment,
        RouteGeometry,
        RouteRequest,
        WeatherObservation,
    )
except ImportError:
    from config import get_settings
    from models import HazardZone, TouristHazardReport
    from schemas import (
        HazardSummary,
        RiskAssessment,
        RouteGeometry,
        RouteRequest,
        WeatherObservation,
    )


def fetch_routes(
    request: RouteRequest, client: httpx.Client
) -> list[tuple[RouteGeometry, float, float]]:
    coordinates = f"{request.origin_lng},{request.origin_lat};{request.dest_lng},{request.dest_lat}"
    try:
        response = client.get(
            f"{get_settings().osrm_base_url}/route/v1/driving/{coordinates}",
            params={
                "overview": "full",
                "geometries": "geojson",
                "alternatives": "true",
            },
        )
        response.raise_for_status()
        data = response.json()
        if data.get("code") == "NoRoute":
            raise HTTPException(422, "No drivable route found between these points")
        if data.get("code") != "Ok":
            raise ValueError("OSRM did not return a route")
        candidates = []
        for route in data["routes"]:
            geometry = RouteGeometry.model_validate(route["geometry"])
            distance, duration = float(route["distance"]), float(route["duration"])
            if not all(math.isfinite(x) and x >= 0 for x in (distance, duration)):
                raise ValueError("Invalid route metrics")
            candidates.append((geometry, distance, duration))
        if not candidates:
            raise ValueError("No route candidates")
        return candidates
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


def fetch_route(request: RouteRequest, client: httpx.Client):
    return fetch_routes(request, client)[0]


def nearby_hazards(db: Session, geometry: RouteGeometry, buffer_meters: float):
    hazards = nearby_official_hazards(db, geometry, buffer_meters)
    route = cast(func.ST_SetSRID(func.ST_GeomFromGeoJSON(geometry.model_dump_json()), 4326), Geography(srid=4326))
    rows = db.execute(select(TouristHazardReport, func.ST_AsGeoJSON(TouristHazardReport.location)).where(
        TouristHazardReport.status == "verified",
        func.ST_DWithin(cast(TouristHazardReport.location, Geography(srid=4326)), route, buffer_meters),
    ).limit(1001)).all()
    if len(rows) + len(hazards) > 1000:
        raise HTTPException(422, "Route intersects too many hazard records; analyze a shorter route")
    hazards.extend(HazardSummary(id=-h.id, name=h.description or h.hazard_type,
        hazard_type=h.hazard_type, severity=h.severity, source="Verified tourist report",
        geometry=json.loads(geometry_json) if geometry_json else None) for h, geometry_json in rows)
    return hazards


def choose_route(candidates, hazard_lookup):
    """Minimize worst severity, then cumulative severity, then travel time."""
    checked = [(candidate, hazard_lookup(candidate[0])) for candidate in candidates]
    def score(item):
        (_, distance, duration), hazards = item
        return (max((h.severity for h in hazards), default=0),
                sum(h.severity for h in hazards), len(hazards), duration, distance)
    candidate, hazards = min(checked, key=score)
    count = len(checked)
    if count == 1:
        message = "Only one route available; no alternative could be compared."
    elif not hazards:
        message = f"Compared {count} routes: selected a route with no reported hazards nearby."
    else:
        message = f"Compared {count} routes: selected the lowest-hazard option. All available routes have reported hazards."
    extra_minutes = max(0, round((candidate[2] - min(c[2] for c in candidates)) / 60))
    if extra_minutes:
        message += f" About {extra_minutes} min longer than the fastest option."
    return candidate, hazards, message


def nearby_official_hazards(
    db: Session, geometry: RouteGeometry, buffer_meters: float
) -> list[HazardSummary]:
    route = cast(
        func.ST_SetSRID(func.ST_GeomFromGeoJSON(geometry.model_dump_json()), 4326),
        Geography(srid=4326),
    )
    try:
        query = (
            select(HazardZone, func.ST_AsGeoJSON(HazardZone.geometry))
            .where(
                HazardZone.is_active.is_(True),
                or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= func.now()),
                or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > func.now()),
                func.ST_DWithin(
                    cast(HazardZone.geometry, Geography(srid=4326)), route, buffer_meters
                ),
            )
            .order_by(HazardZone.severity.desc(), HazardZone.id)
            .limit(1001)
        )
        rows = db.execute(query).all()
        if len(rows) > 1000:
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
                geometry=json.loads(geom_str) if geom_str else None,
            )
            for h, geom_str in rows
        ]
    except HTTPException:
        raise
    except Exception:
        query = (
            select(HazardZone)
            .where(
                HazardZone.is_active.is_(True),
                or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= func.now()),
                or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > func.now()),
                func.ST_DWithin(
                    cast(HazardZone.geometry, Geography(srid=4326)), route, buffer_meters
                ),
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


def fetch_route_weather(lat: float, lng: float, client: httpx.Client):
    """Origin-only hourly forecast. No account data is sent to the provider."""
    try:
        response = client.get("https://api.open-meteo.com/v1/forecast", params={
            "latitude": lat, "longitude": lng,
            "hourly": "precipitation,wind_speed_10m", "forecast_hours": 1,
            "timezone": "UTC", "wind_speed_unit": "kmh",
        }, timeout=8)
        response.raise_for_status()
        data = response.json()
        units = data["hourly_units"]
        if units["precipitation"] != "mm" or units["wind_speed_10m"] != "km/h":
            return None
        hourly = data["hourly"]
        stamp = datetime.fromisoformat(hourly["time"][0])
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        weather = WeatherObservation(
            rainfall_mm_h=hourly["precipitation"][0], wind_kmh=hourly["wind_speed_10m"][0],
            observed_at=stamp, source="Open-Meteo hourly forecast at route origin",
        )
        if not all(math.isfinite(v) for v in (weather.rainfall_mm_h, weather.wind_kmh)):
            return None
        if not timedelta(minutes=-5) <= datetime.now(timezone.utc) - stamp <= timedelta(hours=1):
            return None
        return weather
    except (httpx.HTTPError, ValueError, KeyError, TypeError, IndexError, AttributeError):
        return None


def assess_risk(
    hazards: list[HazardSummary],
    weather: WeatherObservation | None,
    coverage_verified: bool,
    *,
    now: datetime | None = None,
    server_weather: bool = False,
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
        if server_weather:
            reasons.append(f"Weather at route origin: rain {weather.rainfall_mm_h:g} mm/h, wind {weather.wind_kmh:g} km/h. Source: {weather.source}; forecast time {weather.observed_at.isoformat()}.")
            limitations.append("Weather is sampled at the route origin, not along the entire route. Alternatives are ranked by reported hazards, not route-wide weather.")
        else:
            limitations.append(f"Weather is caller-supplied ({weather.source}), not independently verified; it may not cover the whole route.")
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
