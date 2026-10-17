import base64
import io

from PIL import Image


def account(client, email="profile@example.com"):
    result = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "Profile-test-password-42",
            "full_name": "Original Name",
            "emergency_contact_phone": "+12025550123",
        },
    )
    assert result.status_code == 201, result.text
    return {"Authorization": f"Bearer {result.json()['access_token']}"}


def test_profile_roundtrip_and_login_email(client):
    headers = account(client)
    original = client.get("/api/v1/profile/me", headers=headers)
    assert original.status_code == 200
    assert original.json()["full_name"] == "Original Name"
    assert original.json()["phone_number"] == "+12025550123"
    assert original.json()["emergency_contact"] is None
    values = {
        "full_name": "Updated Name",
        "email": "updated@example.com",
        "phone_number": "+919876543210",
        "blood_group": "O+",
        "emergency_contact": "Contact +919876543211",
        "medical_notes": "Carry medication",
        "allergies": "Pollen",
    }
    saved = client.put("/api/v1/profile/me", headers=headers, json=values)
    assert saved.status_code == 200, saved.text
    restored = client.get("/api/v1/profile/me", headers=headers).json()
    for key, value in values.items():
        assert restored[key] == value
    login = client.post(
        "/api/v1/auth/login",
        json={"email": values["email"], "password": "Profile-test-password-42"},
    )
    assert login.status_code == 200


def test_duplicate_email_rolls_back_profile_changes(client):
    first = account(client)
    account(client, "other@example.com")
    result = client.put(
        "/api/v1/profile/me",
        headers=first,
        json={"email": "other@example.com", "full_name": "Must Roll Back"},
    )
    assert result.status_code == 409
    restored = client.get("/api/v1/profile/me", headers=first).json()
    assert restored["email"] == "profile@example.com"
    assert restored["full_name"] == "Original Name"


def test_avatars_persist_and_are_private(client):
    headers = account(client)
    other = account(client, "other@example.com")
    image = io.BytesIO()
    Image.new("RGB", (30, 30), "blue").save(image, "PNG")
    upload = client.post(
        "/api/v1/profile/upload-avatar",
        headers=headers,
        json={"image_base64": base64.b64encode(image.getvalue()).decode()},
    )
    assert upload.status_code == 200, upload.text
    url = upload.json()["profile_picture_url"]
    assert (
        client.get("/api/v1/profile/me", headers=headers).json()["profile_picture_url"]
        == url
    )
    photo = client.get(url, headers=headers)
    assert photo.status_code == 200
    assert photo.headers["content-type"] == "image/jpeg"
    assert Image.open(io.BytesIO(photo.content)).size == (30, 30)
    assert client.get(url, headers=other).status_code == 404
    assert client.get(url).status_code == 401
    assert (
        client.get("/api/v1/profile/me", headers=other).json()["profile_picture_url"]
        is None
    )
    assert (
        client.put(
            "/api/v1/profile/me", headers=other, json={"profile_picture_url": url}
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/api/v1/profile/me",
            headers=headers,
            json={"medical_notes": "Saved after avatar"},
        ).json()["profile_picture_url"]
        == url
    )
    assert (
        client.put(
            "/api/v1/profile/me", headers=headers, json={"profile_picture_url": None}
        ).status_code
        == 200
    )
    assert client.get(url, headers=headers).status_code == 404


def test_profile_authentication_and_validation(client):
    assert client.get("/api/v1/profile/me").status_code == 401
    assert client.put("/api/v1/profile/me", json={}).status_code == 401
    assert (
        client.post(
            "/api/v1/profile/upload-avatar", json={"image_base64": "x"}
        ).status_code
        == 401
    )
    headers = account(client)
    for invalid in (
        {"blood_group": "invalid"},
        {"email": "bad"},
        {"phone_number": "abc"},
        {"medical_notes": "x" * 5001},
        {"user_id": 999},
    ):
        assert (
            client.put("/api/v1/profile/me", headers=headers, json=invalid).status_code
            == 422
        )
    for invalid_image in ("not-base64!", base64.b64encode(b"not an image").decode()):
        assert (
            client.post(
                "/api/v1/profile/upload-avatar",
                headers=headers,
                json={"image_base64": invalid_image},
            ).status_code
            == 422
        )
