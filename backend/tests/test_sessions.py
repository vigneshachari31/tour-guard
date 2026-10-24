from datetime import datetime, timedelta, timezone
from backend.database import get_db
from backend.models import RefreshSession, User
from backend.routers.sessions import digest


def signup(client):
    response = client.post('/api/v1/auth/register', json={'email': 'session@example.com', 'password': 'long-test-password-123'})
    assert response.status_code == 201
    return response.json()


def test_refresh_rotates_and_logout_revokes(client):
    original = signup(client)
    token = original['refresh_token']
    refreshed = client.post('/api/v1/auth/refresh', json={'refresh_token': token})
    assert refreshed.status_code == 200
    renewed = refreshed.json()
    assert renewed['tourist_id'] == original['tourist_id']
    assert renewed['refresh_token'] != token
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': token}).status_code == 401
    assert client.post('/api/v1/auth/logout', json={'refresh_token': renewed['refresh_token']}).status_code == 204
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': renewed['refresh_token']}).status_code == 401


def test_refresh_stores_hash_and_rejects_expiry(client):
    token = signup(client)['refresh_token']
    with next(client.app.dependency_overrides[get_db]()) as db:
        row = db.get(RefreshSession, digest(token))
        assert row is not None and row.token_hash != token
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': token}).status_code == 401


def test_disabled_user_cannot_refresh(client):
    token = signup(client)['refresh_token']
    with next(client.app.dependency_overrides[get_db]()) as db:
        row = db.get(RefreshSession, digest(token))
        db.get(User, row.user_id).is_active = False
        db.commit()
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': token}).status_code == 401


def test_password_change_revokes_refresh(client):
    token = signup(client)['refresh_token']
    with next(client.app.dependency_overrides[get_db]()) as db:
        row = db.get(RefreshSession, digest(token))
        db.get(User, row.user_id).hashed_password = 'changed-password-hash'
        db.commit()
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': token}).status_code == 401
