from sqlalchemy import select
from backend.database import get_db
from backend.models import User


def test_signup_phone_and_full_name_are_saved(client):
    body = {"email":"contact@example.com", "password":"long-contact-password",
            "full_name":"  Test Tourist  ", "emergency_contact_phone":"+12025550124"}
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        user = db.scalar(select(User).where(User.email == body["email"]))
        assert user.full_name == "Test Tourist"
        assert user.emergency_contact_phone == body["emergency_contact_phone"]
    finally:
        provider.close()
    body["full_name"] = "  "
    assert client.post("/api/v1/auth/register", json=body).status_code == 422
    body["full_name"] = "Test Tourist"
    body["emergency_contact_phone"] = "not a phone"
    assert client.post("/api/v1/auth/register", json=body).status_code == 422
