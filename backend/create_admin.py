"""Create or promote one administrator from the configured PostgreSQL database.

Run only from a trusted local terminal. Password input is hidden and is never
printed, stored in source control, or passed as a command-line argument.
"""

import getpass
import os
import sys
from uuid import uuid4

from sqlalchemy import select

from backend.auth import hash_password
from backend.database import get_session_factory
from backend.models import User


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python -m backend.create_admin EMAIL")
    email = sys.argv[1].strip().lower()
    if not email or "@" not in email:
        raise SystemExit("Provide a valid administrator email address")

    # A CI/deployment secret can be supplied by the environment.  Local users
    # are prompted with hidden input, avoiding shell history exposure.
    password = os.environ.get("TOUR_GUARD_ADMIN_PASSWORD")
    if password is None:
        password = getpass.getpass("New administrator password: ")
        confirmation = getpass.getpass("Confirm administrator password: ")
        if password != confirmation:
            raise SystemExit("Passwords do not match")
    if len(password) < 12:
        raise SystemExit("Password must contain at least 12 characters")
    with get_session_factory()() as db:
        user = db.scalar(select(User).where(User.email == email))
        if user is None:
            user = User(
                email=email,
                full_name="Tour Guard Rescue Admin",
                hashed_password=hash_password(password),
                tourist_id=f"TG-{uuid4().hex.upper()}",
                role="admin",
            )
            db.add(user)
        else:
            user.role = "admin"
            user.hashed_password = hash_password(password)
        db.commit()
    print("Administrator account is ready. Sign in to receive an admin JWT.")


if __name__ == "__main__":
    main()
