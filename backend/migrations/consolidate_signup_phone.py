"""Backfill is non-destructive. Column removal requires explicit approval."""
from sqlalchemy import inspect, text
from backend.database import get_engine


def consolidate(connection, *, drop_approved=False):
    connection.execute(text("SET LOCAL lock_timeout = '5s'"))
    connection.execute(text("LOCK TABLE users IN ACCESS EXCLUSIVE MODE"))
    if 'phone_number' not in {c['name'] for c in inspect(connection).get_columns('users')}:
        return {"copied": 0, "remaining": 0, "dropped": False}
    result = connection.execute(text("UPDATE users SET emergency_contact_phone = phone_number WHERE emergency_contact_phone IS NULL AND phone_number IS NOT NULL"))
    remaining = connection.execute(text("SELECT count(*) FROM users WHERE phone_number IS NOT NULL AND emergency_contact_phone IS DISTINCT FROM phone_number")).scalar_one()
    if drop_approved:
        if remaining:
            raise RuntimeError('Phone conflicts remain; column removal refused')
        # No CASCADE: dependencies must not be silently removed.
        connection.execute(text('ALTER TABLE users DROP COLUMN phone_number'))
    return {"copied": result.rowcount, "remaining": remaining, "dropped": drop_approved}


if __name__ == '__main__':
    with get_engine().begin() as connection:
        print(consolidate(connection))
