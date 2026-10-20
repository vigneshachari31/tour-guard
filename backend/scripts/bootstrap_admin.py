"""Run from repository root: python -m backend.scripts.bootstrap_admin.
Existing passwords are never reset; an existing account is upgraded only when
ADMIN_PASSWORD verifies against its current hash.
"""

import os
from pathlib import Path
from uuid import uuid4

from dotenv import dotenv_values
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.auth import hash_password, verify_password
from backend.database import get_engine
from backend.models import AuditLog, User
from backend.schemas import RegisterRequest


def main():
    values = {
        **dotenv_values(Path(__file__).resolve().parents[1] / ".env"),
        **os.environ,
    }
    email, password = values.get("ADMIN_EMAIL"), values.get("ADMIN_PASSWORD")
    if not email or not password:
        raise SystemExit(
            "Set ADMIN_EMAIL and ADMIN_PASSWORD in backend/.env, then rerun. No accounts changed."
        )
    try:
        request = RegisterRequest(email=email, password=password)
    except ValueError:
        raise SystemExit(
            "ADMIN_EMAIL must be valid and ADMIN_PASSWORD must be 12–128 characters."
        ) from None
    with Session(get_engine()) as db:
        user = db.scalar(
            select(User).where(User.email == request.email).with_for_update()
        )
        if user and not verify_password(password, user.hashed_password):
            raise SystemExit(
                "Existing account password did not match. No accounts changed."
            )
        if user and not user.is_active:
            raise SystemExit("Account is inactive. Bootstrap will not reactivate it.")
        if user is None:
            user = User(
                email=request.email,
                hashed_password=hash_password(password),
                role="admin",
                tourist_id=f"TG-{uuid4().hex.upper()}",
                is_active=True,
            )
            db.add(user)
            db.flush()
        user.role = "admin"
        db.add(
            AuditLog(
                admin_id=user.id,
                admin_email=user.email,
                action="ADMIN_BOOTSTRAP",
                resource_type="user",
                resource_id=str(user.id),
            )
        )
        db.commit()
    print("Administrator account is ready. Credentials were not printed or reset.")


if __name__ == "__main__":
    main()
