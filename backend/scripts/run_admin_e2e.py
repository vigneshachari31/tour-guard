"""Browser workflow tests against a migrated tour_guard_test DB, always rolled back.
Usage: set TEST_DATABASE_URL, then python -m backend.scripts.run_admin_e2e.
"""

import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.tests.database_safety import validated_test_url


def main():
    url = validated_test_url(os.environ["TEST_DATABASE_URL"])
    os.environ["DATABASE_URL"] = url.render_as_string(hide_password=False)
    os.environ["JWT_SECRET"] = secrets.token_urlsafe(48)
    import uvicorn

    from backend.auth import hash_password
    from backend.database import get_db
    from backend.main import create_app
    from backend.models import SOSEvent, Trip, User, UserProfile

    engine = create_engine(url, hide_parameters=True)
    with engine.connect() as connection:
        transaction = connection.begin()
        gate = threading.Lock()
        app = create_app()

        def database():
            with (
                gate,
                Session(
                    bind=connection, join_transaction_mode="create_savepoint"
                ) as db,
            ):
                yield db

        app.dependency_overrides[get_db] = database
        with Session(bind=connection, join_transaction_mode="create_savepoint") as db:
            admin = User(
                email="admin-e2e@example.com",
                hashed_password=hash_password("isolated-browser-password"),
                role="admin",
                tourist_id="TG-" + secrets.token_hex(16).upper(),
                full_name="Test Administrator",
            )
            tourist = User(
                email="tourist-e2e@example.com",
                hashed_password=hash_password("isolated-browser-password"),
                role="tourist",
                tourist_id="TG-" + secrets.token_hex(16).upper(),
                full_name="Test Tourist",
            )
            db.add_all([admin, tourist])
            db.flush()
            db.add(
                UserProfile(
                    user_id=tourist.id,
                    full_name="Test Tourist",
                    phone_number="+12025550123",
                )
            )
            db.add(
                SOSEvent(tourist_id=tourist.tourist_id, latitude=11.4, longitude=76.7)
            )
            db.add(Trip(tourist_id=tourist.tourist_id, source_name="Tracking Source", destination_name="Tracking Destination",
                        origin_lat=19.04, origin_lng=72.85, dest_lat=19.05, dest_lng=72.86,
                        route_geometry='{"type":"LineString","coordinates":[[72.85,19.04],[72.855,19.045],[72.86,19.05]]}'))
            db.commit()
        server = uvicorn.Server(
            uvicorn.Config(app, host="127.0.0.1", port=8011, log_level="warning")
        )
        thread = threading.Thread(target=server.run, daemon=True)
        thread.start()
        try:
            for _ in range(50):
                try:
                    urllib.request.urlopen(
                        "http://127.0.0.1:8011/health/live", timeout=1
                    )
                    break
                except OSError:
                    time.sleep(0.1)
            result = subprocess.run(
                ["npm.cmd", "run", "test:e2e", "--", *sys.argv[1:]],
                check=False,
                cwd=Path(__file__).resolve().parents[2] / "admin_dashboard",
            )
        finally:
            server.should_exit = True
            thread.join(timeout=15)
            transaction.rollback()
            engine.dispose()
        print("Browser test transaction rolled back; no fixture accounts persisted.")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
