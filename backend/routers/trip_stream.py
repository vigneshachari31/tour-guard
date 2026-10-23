"""Authenticated streams; committed DB snapshots synchronize multiple API workers.

Tokens are sent in the first frame, never URLs/access logs. Sessions are short-lived
per operation, so idle sockets do not hold database connections or transactions.
"""

import asyncio
from contextlib import contextmanager
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.encoders import jsonable_encoder
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy import or_, select
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

if __package__ == "backend.routers":
    from ..admin_schemas import LocationInput
    from ..auth import get_current_user, verify_admin
    from ..database import get_db
    from ..models import Trip
    from .admin import trip_dict
    from .trips import location, owned_trip
else:
    from admin_schemas import LocationInput
    from auth import get_current_user, verify_admin
    from database import get_db
    from models import Trip
    from routers.admin import trip_dict
    from routers.trips import location, owned_trip

router = APIRouter()


class PositionFrame(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    distance_remaining: float | None = Field(default=None, ge=0)


@contextmanager
def session(ws):
    provider = ws.app.dependency_overrides.get(get_db, get_db)
    generator = provider()
    db = next(generator)
    try:
        yield db
    finally:
        generator.close()


def authenticated(db, token, admin=False):
    user = get_current_user(
        HTTPAuthorizationCredentials(scheme="Bearer", credentials=token), db
    )
    return verify_admin(user) if admin else user


async def handshake(ws):
    await ws.accept()
    frame = await asyncio.wait_for(ws.receive_json(), timeout=10)
    token = frame.get("token") if isinstance(frame, dict) else None
    if not isinstance(token, str) or len(token) > 8192:
        raise HTTPException(401, "Authentication required")
    return token


def verify_owner(ws, token, identity):
    with session(ws) as db:
        owned_trip(db, authenticated(db, token), identity)


def write_location(ws, token, identity, frame):
    with session(ws) as db:
        user = authenticated(db, token)
        return jsonable_encoder(
            location(
                identity,
                LocationInput(latitude=frame.lat, longitude=frame.lng),
                user,
                db,
            )
        )


@router.websocket("/ws/trips/{identity}/track")
async def tourist_stream(ws: WebSocket, identity: int):
    try:
        token = await handshake(ws)
        await run_in_threadpool(verify_owner, ws, token, identity)
        await ws.send_json({"event": "READY"})
        while True:
            try:
                raw = await asyncio.wait_for(ws.receive_json(), timeout=30)
            except asyncio.TimeoutError:
                await run_in_threadpool(verify_owner, ws, token, identity)
                await ws.send_json({"event": "PING"})
                continue
            try:
                frame = PositionFrame.model_validate(raw)
            except ValidationError:
                await ws.send_json(
                    {"event": "ERROR", "detail": "Invalid GPS coordinates"}
                )
                continue
            update = await run_in_threadpool(write_location, ws, token, identity, frame)
            update["event"] = (
                "TRIP_COMPLETED"
                if update["status"] == "COMPLETED"
                else "LOCATION_UPDATE"
            )
            await ws.send_json(update)
            if update["status"] == "COMPLETED":
                await ws.close(code=1000)
                return
    except WebSocketDisconnect:
        pass
    except (HTTPException, asyncio.TimeoutError):
        await ws.close(code=1008)
    except (ValueError, SQLAlchemyError):
        await ws.close(code=1011)


def snapshot(ws, token, since):
    with session(ws) as db:
        authenticated(db, token, admin=True)
        trips = db.scalars(
            select(Trip)
            .where(or_(Trip.status == "active", Trip.ended_at >= since))
            .order_by(Trip.id)
        )
        return jsonable_encoder([trip_dict(db, t) for t in trips])


@router.websocket("/ws/admin/active-trips")
async def admin_stream(ws: WebSocket):
    try:
        token = await handshake(ws)
        since = datetime.now(UTC)
        previous = {}
        first = True
        while True:
            items = await run_in_threadpool(snapshot, ws, token, since)
            if first:
                await ws.send_json({"event": "SNAPSHOT", "items": items})
                first = False
            else:
                for item in items:
                    if previous.get(item["id"]) != item:
                        status = item["lifecycle_status"]
                        await ws.send_json(
                            {
                                "event": "TRIP_COMPLETED"
                                if status == "COMPLETED"
                                else "TRIP_CANCELLED"
                                if status == "CANCELLED"
                                else "LOCATION_UPDATE",
                                "trip_id": item["id"],
                                "tourist_id": item["tourist_id"],
                                "current_lat": item["current_lat"],
                                "current_lng": item["current_lng"],
                                "status": status,
                                "trip": item,
                            }
                        )
            previous = {item["id"]: item for item in items}
            # Heartbeats detect dead clients even when no tourist moves.
            await ws.send_json({"event": "PING"})
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        pass
    except (HTTPException, asyncio.TimeoutError):
        await ws.close(code=1008)
    except (ValueError, SQLAlchemyError):
        await ws.close(code=1011)
