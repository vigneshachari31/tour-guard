import json
import logging
import time
from collections import deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated, Literal
from uuid import uuid4

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import func, or_, select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

if __package__:
    from .auth import (
        create_access_token,
        get_current_user,
        get_optional_user,
        hash_password,
        verify_password,
    )
    from .config import get_settings
    from .database import get_db, get_engine
    from .models import HazardZone, RiskAssessmentLog, SOSEvent, Trip, User
    from .risk_engine import assess_risk, fetch_route, nearby_hazards
    from .routers.admin import router as admin_router
    from .routers.profile import router as profile_router
    from .routers.trips import router as trips_router
    from .routers.trip_stream import router as trip_stream_router
    from .routers.hazards import router as hazards_router
    from .routers.radar import router as radar_router
    from .routers.sos_tracking import router as sos_tracking_router, tracking_details
    from .routers.moderation import router as moderation_router, verified_features
    from .schemas import (
        HazardReportRequest,
        HazardReportResponse,
        LoginRequest,
        RegisterRequest,
        RouteRequest,
        RouteResponse,
        SOSEventsListResponse,
        SOSRequest,
        SOSResponse,
        TokenResponse,
    )
else:
    from auth import (
        create_access_token,
        get_current_user,
        get_optional_user,
        hash_password,
        verify_password,
    )
    from config import get_settings
    from database import get_db, get_engine
    from models import HazardZone, RiskAssessmentLog, SOSEvent, Trip, User
    from risk_engine import assess_risk, fetch_route, nearby_hazards
    from routers.admin import router as admin_router
    from routers.profile import router as profile_router
    from routers.trips import router as trips_router
    from routers.trip_stream import router as trip_stream_router
    from routers.hazards import router as hazards_router
    from routers.radar import router as radar_router
    from routers.sos_tracking import router as sos_tracking_router, tracking_details
    from routers.moderation import router as moderation_router, verified_features
    from schemas import (
        HazardReportRequest,
        HazardReportResponse,
        LoginRequest,
        RegisterRequest,
        RouteRequest,
        RouteResponse,
        SOSEventsListResponse,
        SOSRequest,
        SOSResponse,
        TokenResponse,
    )

logger = logging.getLogger(__name__)
DB = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    app.state.http = httpx.Client(
        timeout=httpx.Timeout(settings.http_timeout_seconds),
        limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
        headers={"User-Agent": "TourGuard/1.0"},
        follow_redirects=False,
    )
    try:
        yield
    finally:
        app.state.http.close()
        get_engine().dispose()


def get_http(request: Request) -> httpx.Client:
    return request.app.state.http


def token_for(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.id, user.role),
        tourist_id=user.tourist_id,
        expires_in=get_settings().access_token_minutes * 60,
        role=user.role,
    )


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Tour Guard API", version="2.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=(
            r"http://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})?"
            if settings.cors_allow_localhost
            else None
        ),
        allow_methods=["GET", "POST", "PUT", "PATCH"],
        allow_headers=["Authorization", "Content-Type"],
    )

    app.include_router(profile_router)
    app.include_router(admin_router)
    app.include_router(trips_router)
    app.include_router(trip_stream_router)
    app.include_router(hazards_router)
    app.include_router(radar_router)
    app.include_router(sos_tracking_router)
    app.include_router(moderation_router)

    login_attempts: dict[str, deque[float]] = {}

    @app.middleware("http")
    async def admin_security_headers(request, call_next):
        if request.url.path == "/api/v1/admin/auth/login" and request.method == "POST":
            # Per-process protection; a shared gateway limiter is needed with multiple workers.
            now = time.monotonic()
            for key in list(login_attempts):
                if not login_attempts[key] or login_attempts[key][-1] < now - 60:
                    del login_attempts[key]
            key = request.client.host if request.client else "unknown"
            if key not in login_attempts and len(login_attempts) >= 4096:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Login is busy; retry shortly"},
                    headers={"Retry-After": "60"},
                )
            attempts = login_attempts.setdefault(key, deque())
            while attempts and attempts[0] < now - 60:
                attempts.popleft()
            if len(attempts) >= 10:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Too many login attempts. Wait one minute."},
                    headers={"Retry-After": "60"},
                )
            attempts.append(now)
        response = await call_next(request)
        if request.url.path.startswith(("/api/v1/admin", "/admin")):
            response.headers["Cache-Control"] = "no-store"
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
            response.headers["X-Frame-Options"] = "DENY"
        return response

    @app.exception_handler(SQLAlchemyError)
    async def database_error(request: Request, exc: SQLAlchemyError) -> JSONResponse:
        # Never log the exception text: it can contain user data or SQL parameters.
        original = getattr(exc, "orig", None)
        logger.error(
            "Database operation failed: %s; driver=%s; sqlstate=%s",
            type(exc).__name__,
            type(original).__name__ if original is not None else "unknown",
            getattr(original, "sqlstate", None) or "unknown",
        )
        return JSONResponse(
            status_code=503,
            content={"detail": "Database operation unavailable; retry later"},
        )

    @app.get("/health/live", tags=["Health"])
    def live() -> dict[str, str]:
        return {"status": "alive"}

    @app.get("/health/ready", tags=["Health"])
    def ready(db: DB) -> dict[str, str]:
        db.execute(text("SELECT PostGIS_Version()"))
        db.execute(select(User.id).limit(1))
        return {"status": "ready"}

    @app.post(
        "/api/v1/auth/register",
        response_model=TokenResponse,
        status_code=201,
        tags=["Authentication"],
    )
    def register(body: RegisterRequest, db: DB) -> TokenResponse:
        if db.scalar(select(User.id).where(User.email == body.email)) is not None:
            raise HTTPException(409, "Email is already registered")
        password = hash_password(body.password)
        for _ in range(3):
            user = User(
                email=body.email,
                full_name=body.full_name,
                hashed_password=password,
                tourist_id=f"TG-{uuid4().hex.upper()}",
                emergency_contact_phone=body.emergency_contact_phone,
            )
            db.add(user)
            try:
                db.commit()
                db.refresh(user)
                return token_for(user)
            except IntegrityError:
                db.rollback()
                if (
                    db.scalar(select(User.id).where(User.email == body.email))
                    is not None
                ):
                    raise HTTPException(409, "Email is already registered") from None
                # Retry the extremely unlikely generated-ID collision.
        raise HTTPException(503, "Unable to create account; retry later")

    @app.post(
        "/api/v1/auth/login", response_model=TokenResponse, tags=["Authentication"]
    )
    def login(body: LoginRequest, db: DB) -> TokenResponse:
        user = db.scalar(select(User).where(User.email == body.email))
        if not verify_password(body.password, user.hashed_password if user else None):
            raise HTTPException(
                401, "Invalid email or password", headers={"WWW-Authenticate": "Bearer"}
            )
        assert user is not None
        if not user.is_active:
            raise HTTPException(401, "Account is inactive")
        return token_for(user)

    @app.post("/api/v1/trips/start", response_model=RouteResponse, status_code=201, tags=["Trips"])
    @app.post("/api/v1/route/analyze", response_model=RouteResponse, tags=["Routes"])
    def analyze(
        request: Request,
        body: RouteRequest,
        user: CurrentUser,
        db: DB,
        client: Annotated[httpx.Client, Depends(get_http)],
    ) -> RouteResponse:
        geometry, distance, duration = fetch_route(body, client)
        hazards = nearby_hazards(db, geometry, settings.route_buffer_meters)
        result = RouteResponse(
            geometry=geometry,
            distance_meters=distance,
            duration_seconds=duration,
            buffer_meters=settings.route_buffer_meters,
            hazards=hazards,
            assessment=assess_risk(
                hazards, body.weather, settings.hazard_coverage_verified
            ),
        )

        if not body.start_trip and request.url.path != "/api/v1/trips/start":
            return result

        # Serialize trip replacement for this tourist; keep assessment and trip atomic.
        db.execute(select(User.id).where(User.id == user.id).with_for_update())
        for previous in db.scalars(
            select(Trip).where(
                Trip.tourist_id == user.tourist_id, Trip.status == "active"
            )
        ):
            previous.status = "cancelled"
            previous.ended_at = datetime.now(timezone.utc)
        trip = Trip(
            tourist_id=user.tourist_id,
            source_name=body.origin_name
            or f"{body.origin_lat:.5f}, {body.origin_lng:.5f}",
            destination_name=body.destination_name
            or f"{body.dest_lat:.5f}, {body.dest_lng:.5f}",
            origin_lat=body.origin_lat,
            origin_lng=body.origin_lng,
            dest_lat=body.dest_lat,
            dest_lng=body.dest_lng,
            route_geometry=geometry.model_dump_json(),
            last_latitude=body.initial_position.latitude if body.initial_position else None,
            last_longitude=body.initial_position.longitude if body.initial_position else None,
            last_location_updated_at=datetime.now(timezone.utc) if body.initial_position else None,
        )
        db.add(trip)
        db.flush()
        db.add(
            RiskAssessmentLog(
                user_id=user.id,
                trip_id=trip.id,
                origin_lat=body.origin_lat,
                origin_lng=body.origin_lng,
                dest_lat=body.dest_lat,
                dest_lng=body.dest_lng,
                risk_level=result.assessment.level,
                distance_meters=distance,
                duration_seconds=duration,
                hazards_count=len(hazards),
                weather_used=result.assessment.weather_used,
                reasons=json.dumps(result.assessment.reasons),
                limitations=json.dumps(result.assessment.limitations),
            )
        )
        db.commit()
        return result.model_copy(update={"trip_id": trip.id})

    @app.post(
        "/api/v1/sos/trigger", response_model=SOSResponse, status_code=201, tags=["SOS"]
    )
    def trigger_sos(body: SOSRequest, user: CurrentUser, db: DB) -> SOSEvent:
        if body.tourist_id != user.tourist_id:
            raise HTTPException(403, "You can only submit SOS for your own tourist ID")
        db.execute(select(User.id).where(User.id == user.id).with_for_update())
        existing = db.scalar(select(SOSEvent).where(
            SOSEvent.tourist_id == user.tourist_id,
            SOSEvent.workflow_status.in_(["OPEN", "IN_PROGRESS"]),
        ).order_by(SOSEvent.created_at.desc()).limit(1))
        if existing is not None:
            db.commit()
            return existing
        event = SOSEvent(
            tourist_id=user.tourist_id,
            latitude=body.latitude,
            longitude=body.longitude,
            status="active",
        )
        db.add(event)
        db.commit()
        db.refresh(event)
        return event

    @app.post("/api/v1/sos/events/{identity}/cancel", tags=["SOS"])
    def cancel_own_sos(identity: int, user: CurrentUser, db: DB):
        if __package__:
            from .routers.admin import release_assignment
            from .models import SOSHistory
        else:
            from routers.admin import release_assignment
            from models import SOSHistory
        event = db.scalar(select(SOSEvent).where(
            SOSEvent.id == identity, SOSEvent.tourist_id == user.tourist_id
        ).with_for_update())
        if event is None:
            raise HTTPException(404, "SOS not found")
        if event.workflow_status in ("RESOLVED", "CANCELLED"):
            return {"id": identity, "status": event.workflow_status}
        old = event.workflow_status
        event.workflow_status = "CANCELLED"
        event.status = "resolved"
        release_assignment(db, identity, "cancelled")
        db.add(SOSHistory(sos_event_id=identity, old_status=old,
            new_status="CANCELLED", changed_by_id=user.id,
            notes="Tourist cancelled the SOS after confirmation."))
        db.commit()
        return {"id": identity, "status": "CANCELLED"}

    @app.get(
        "/api/v1/sos/events",
        response_model=SOSEventsListResponse,
        tags=["SOS"],
    )
    def list_sos_events(
        user: CurrentUser,
        db: DB,
        status: Literal["active", "resolved"] | None = None,
    ) -> SOSEventsListResponse:
        stmt = select(SOSEvent).where(SOSEvent.tourist_id == user.tourist_id)
        if status:
            stmt = stmt.where(SOSEvent.status == status)
        stmt = stmt.order_by(SOSEvent.created_at.desc(), SOSEvent.id.desc()).limit(100)
        events = list(db.scalars(stmt).all())
        return SOSEventsListResponse(
            events=[SOSResponse.model_validate(e).model_copy(update=tracking_details(db, e)) for e in events],
            total=len(events),
        )

    @app.get(
        "/api/v1/hazards/active",
        tags=["Hazards"],
    )
    def list_active_hazards(
        response: Response,
        db: DB,
        user: Annotated[User | None, Depends(get_optional_user)] = None,
    ):
        response.headers["Cache-Control"] = "no-store"
        try:
            stmt = (
                select(HazardZone, func.ST_AsGeoJSON(HazardZone.geometry))
                .where(
                    HazardZone.is_active.is_(True),
                    or_(HazardZone.valid_from.is_(None), HazardZone.valid_from <= func.now()),
                    or_(HazardZone.valid_until.is_(None), HazardZone.valid_until > func.now()),
                )
                .order_by(HazardZone.id)
            )
            features = []
            for h, geom_str in db.execute(stmt):
                geom = json.loads(geom_str) if geom_str else None
                if geom:
                    features.append({
                        "type": "Feature",
                        "id": h.id,
                        "geometry": geom,
                        "properties": {
                            "id": h.id,
                            "name": h.name,
                            "hazard_type": h.hazard_type,
                            "severity": h.severity,
                            "source": h.source or "Official",
                            "is_active": h.is_active,
                        },
                    })
            return {
                "type": "FeatureCollection",
                "features": features + verified_features(db),
            }
        except SQLAlchemyError:
            raise
        except Exception as exc:
            raise HTTPException(503, "Hazard data unavailable; retry later") from exc


    from pathlib import Path

    from fastapi.staticfiles import StaticFiles
    from starlette.exceptions import HTTPException as StarletteHTTPException

    class AdminFiles(StaticFiles):
        async def get_response(self, path, scope):
            try:
                return await super().get_response(path, scope)
            except StarletteHTTPException as exc:
                if exc.status_code == 404 and not Path(path).suffix:
                    return await super().get_response("index.html", scope)
                raise

    bundle = Path(__file__).resolve().parent.parent / "admin_dashboard" / "dist"
    if bundle.is_dir():
        app.mount(
            "/admin", AdminFiles(directory=bundle, html=True), name="admin-dashboard"
        )
    return app


app = create_app()
