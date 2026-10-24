"""Rotating opaque refresh credentials; only hashes are stored server-side."""
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy import delete
from sqlalchemy.orm import Session

from ..auth import create_access_token
from ..config import get_settings
from ..database import get_db
from ..models import RefreshSession, User
from ..schemas import TokenResponse

router = APIRouter(prefix='/api/v1/auth', tags=['Authentication'])


def digest(value):
    return sha256(value.encode()).hexdigest()


def issue_session(user: User, db: Session) -> TokenResponse:
    token = secrets.token_urlsafe(48)
    now = datetime.now(timezone.utc)
    db.execute(delete(RefreshSession).where(RefreshSession.user_id == user.id, RefreshSession.expires_at <= now))
    db.add(RefreshSession(token_hash=digest(token), user_id=user.id,
        password_stamp=digest(user.hashed_password), expires_at=now + timedelta(days=90)))
    db.commit()
    return TokenResponse(access_token=create_access_token(user.id, user.role),
        refresh_token=token, tourist_id=user.tourist_id, role=user.role,
        expires_in=get_settings().access_token_minutes * 60)


class SessionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    refresh_token: str = Field(min_length=32, max_length=256)


@router.post('/refresh', response_model=TokenResponse)
def refresh(body: SessionRequest, db: Session = Depends(get_db)):
    row = db.get(RefreshSession, digest(body.refresh_token))
    now = datetime.now(timezone.utc)
    if row is None:
        raise HTTPException(401, 'Session expired or revoked')
    expiry = row.expires_at.replace(tzinfo=timezone.utc) if row.expires_at.tzinfo is None else row.expires_at
    user = db.get(User, row.user_id)
    if expiry <= now or user is None or not user.is_active or row.password_stamp != digest(user.hashed_password):
        db.delete(row)
        db.commit()
        raise HTTPException(401, 'Session expired or revoked')
    # Only one request can consume the old credential, including concurrent refreshes.
    removed = db.execute(delete(RefreshSession).where(RefreshSession.token_hash == row.token_hash))
    if removed.rowcount != 1:
        db.rollback()
        raise HTTPException(401, 'Session already renewed')
    return issue_session(user, db)


@router.post('/logout', status_code=204)
def logout(body: SessionRequest, db: Session = Depends(get_db)):
    db.execute(delete(RefreshSession).where(RefreshSession.token_hash == digest(body.refresh_token)))
    db.commit()
