"""Account-scoped profiles and private, database-backed avatar images."""

import base64
import binascii
import io
import warnings
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Response
from PIL import Image, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

if __package__ and "." in __package__:
    from ..auth import get_current_user
    from ..database import get_db
    from ..models import User, UserProfile
    from ..schemas import AvatarUpload, ProfileResponse, ProfileUpdate
else:
    from auth import get_current_user
    from database import get_db
    from models import User, UserProfile
    from schemas import AvatarUpload, ProfileResponse, ProfileUpdate

router = APIRouter(prefix="/api/v1/profile", tags=["Profile"])
DB = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]
FIELDS = (
    "full_name",
    "phone_number",
    "profile_picture_url",
    "blood_group",
    "emergency_contact",
    "medical_notes",
    "allergies",
)


def find_profile(db: Session, user: User) -> UserProfile | None:
    return db.scalar(select(UserProfile).where(UserProfile.user_id == user.id))


def profile_response(profile: UserProfile | None, user: User) -> ProfileResponse:
    values = (
        {field: getattr(profile, field) for field in FIELDS}
        if profile
        else {
            "full_name": user.full_name,
            # Existing signup stores its mobile number in this account column.
            "phone_number": user.emergency_contact_phone,
        }
    )
    return ProfileResponse(user_id=user.id, email=user.email, **values)


def writable_profile(db: Session, user: User) -> UserProfile:
    # Serialize updates per user, including first-profile creation and uploads.
    db.execute(select(User.id).where(User.id == user.id).with_for_update())
    profile = find_profile(db, user)
    if profile is None:
        profile = UserProfile(
            user_id=user.id,
            full_name=user.full_name,
            phone_number=user.emergency_contact_phone,
        )
        db.add(profile)
    return profile


@router.get("/me", response_model=ProfileResponse)
def get_profile(user: CurrentUser, db: DB, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return profile_response(find_profile(db, user), user)


@router.put("/me", response_model=ProfileResponse)
def update_profile(body: ProfileUpdate, user: CurrentUser, db: DB):
    profile = writable_profile(db, user)
    changes = body.model_dump(exclude_unset=True)
    if "profile_picture_url" in changes:
        value = changes["profile_picture_url"]
        if value is not None and value != profile.profile_picture_url:
            raise HTTPException(422, "Upload your photo before setting its URL")
        if value is None:
            profile.avatar_data = None
    if "email" in changes:
        if changes["email"] is None:
            raise HTTPException(422, "Email cannot be empty")
        user.email = changes.pop("email").lower()
    for field, value in changes.items():
        setattr(profile, field, value)
    if "full_name" in changes:
        user.full_name = changes["full_name"]
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            409, "Email is already in use or the profile changed; retry"
        ) from None
    db.refresh(profile)
    return profile_response(profile, user)


def sanitize_image(encoded: str) -> bytes:
    try:
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) > 2 * 1024 * 1024:
            raise HTTPException(413, "Choose an image smaller than 2 MB")
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as source:
                if source.format not in ("PNG", "JPEG", "WEBP"):
                    raise HTTPException(415, "Choose a JPEG, PNG or WebP image")
                if source.width * source.height > 16_000_000:
                    raise HTTPException(413, "Image dimensions are too large")
                from PIL import ImageOps

                source = ImageOps.exif_transpose(source)
                source.thumbnail((1024, 1024))
                output = io.BytesIO()
                source.convert("RGB").save(output, format="JPEG", quality=85)
                return output.getvalue()
    except (
        binascii.Error,
        ValueError,
        OSError,
        UnidentifiedImageError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise HTTPException(422, "The file is not a valid supported image") from None


@router.post("/upload-avatar", response_model=ProfileResponse)
def upload_avatar(body: AvatarUpload, user: CurrentUser, db: DB):
    data = sanitize_image(body.image_base64)
    profile = writable_profile(db, user)
    profile.avatar_data = data
    profile.profile_picture_url = f"/api/v1/profile/avatar/{uuid4().hex}"
    db.commit()
    db.refresh(profile)
    return profile_response(profile, user)


@router.get("/avatar/{avatar_id}")
def get_avatar(avatar_id: str, user: CurrentUser, db: DB):
    profile = find_profile(db, user)
    if (
        not profile
        or not profile.avatar_data
        or profile.profile_picture_url != f"/api/v1/profile/avatar/{avatar_id}"
    ):
        raise HTTPException(404, "Profile photo not found")
    return Response(
        profile.avatar_data,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )
