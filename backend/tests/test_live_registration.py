"""Registration regression using the isolated in-memory client fixture only."""
import re
from uuid import uuid4

from sqlalchemy import select

from backend.auth import verify_password
from backend.database import get_db
from backend.models import User


def test_registration_persistence_and_login(client):
    email = f"tourguard-check-{uuid4().hex}@example.com"
    password = uuid4().hex + uuid4().hex
    response = client.post("/api/v1/auth/register", json={"email": email, "password": password, "full_name": "Tour Guard Test Tourist", "emergency_contact_phone": "+12025550123"})
    assert response.status_code == 201, response.status_code
    account = response.json()
    assert account["access_token"]
    assert account["token_type"] == "bearer"
    assert re.fullmatch(r"TG-[A-F0-9]{32}", account["tourist_id"])
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        user = db.scalar(select(User).where(User.email == email))
        assert user is not None
        assert user.full_name == "Tour Guard Test Tourist"
        assert user.emergency_contact_phone == "+12025550123"
        assert user.tourist_id == account["tourist_id"]
        assert user.hashed_password != password
        assert user.hashed_password.startswith("$argon2")
        assert verify_password(password, user.hashed_password)
        assert not verify_password("wrong-password", user.hashed_password)
    finally:
        provider.close()
    duplicate = client.post("/api/v1/auth/register", json={"email": email.upper(), "password": password})
    assert duplicate.status_code == 409
    login = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert login.status_code == 200
    assert login.json()["tourist_id"] == account["tourist_id"]
    assert client.post("/api/v1/auth/login", json={"email": email, "password": "wrong-password"}).status_code == 401
