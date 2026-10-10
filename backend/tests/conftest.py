import os

# Test subprocess only: never fall through to DATABASE_URL from backend/.env.
os.environ["DATABASE_URL"] = "postgresql+psycopg://localhost:1/tour_guard_tests"

os.environ["JWT_SECRET"] = "unit-test-only-secret-not-for-deployment-123456789"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from backend.database import get_db
from backend.main import create_app
from backend.models import SOSEvent, User


@pytest.fixture
def client():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    # SQLite is only used for auth/SOS unit tests, never for spatial verification.
    User.__table__.create(engine)
    SOSEvent.__table__.create(engine)
    app = create_app()

    def database():
        with Session(engine) as db:
            yield db

    app.dependency_overrides[get_db] = database
    with TestClient(app) as test_client:
        yield test_client
    engine.dispose()
