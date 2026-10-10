import logging
from contextlib import asynccontextmanager
from typing import Annotated
from uuid import uuid4

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

try:
    from .auth import create_access_token, get_current_user, hash_password, verify_password
    from .config import get_settings
    from .database import get_db, get_engine
    from .models import SOSEvent, User
    from .risk_engine import assess_risk, fetch_route, nearby_hazards
    from .schemas import (
        LoginRequest,
        RegisterRequest,
        RouteRequest,
        RouteResponse,
        SOSRequest,
        SOSResponse,
        TokenResponse,
    )
except ImportError:
    from auth import create_access_token, get_current_user, hash_password, verify_password
    from config import get_settings
    from database import get_db, get_engine
    from models import SOSEvent, User
    from risk_engine import assess_risk, fetch_route, nearby_hazards
    from schemas import (
        LoginRequest,
        RegisterRequest,
        RouteRequest,
        RouteResponse,
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
        access_token=create_access_token(user.id),
        tourist_id=user.tourist_id,
        expires_in=get_settings().access_token_minutes * 60,
    )


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Tour Guard API", version="2.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=(
            r"http://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})?"
            if settings.cors_allow_localhost else None
        ),
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

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
        return token_for(user)

    @app.post("/api/v1/route/analyze", response_model=RouteResponse, tags=["Routes"])
    def analyze(
        body: RouteRequest,
        user: CurrentUser,
        db: DB,
        client: Annotated[httpx.Client, Depends(get_http)],
    ) -> RouteResponse:
        geometry, distance, duration = fetch_route(body, client)
        hazards = nearby_hazards(db, geometry, settings.route_buffer_meters)
        return RouteResponse(
            geometry=geometry,
            distance_meters=distance,
            duration_seconds=duration,
            buffer_meters=settings.route_buffer_meters,
            hazards=hazards,
            assessment=assess_risk(
                hazards, body.weather, settings.hazard_coverage_verified
            ),
        )

    @app.post(
        "/api/v1/sos/trigger", response_model=SOSResponse, status_code=201, tags=["SOS"]
    )
    def trigger_sos(body: SOSRequest, user: CurrentUser, db: DB) -> SOSEvent:
        if body.tourist_id != user.tourist_id:
            raise HTTPException(403, "You can only submit SOS for your own tourist ID")
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

    return app


app = create_app()
