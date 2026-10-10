"""Reject application databases before any integration-test connection is opened."""
from sqlalchemy.engine import make_url


def validated_test_url(value):
    url = make_url(value)
    if url.get_backend_name() != 'postgresql' or url.database != 'tour_guard_test':
        raise ValueError('TEST_DATABASE_URL must point to the separate tour_guard_test database; application databases are forbidden')
    if url.drivername == 'postgresql':
        url = url.set(drivername='postgresql+psycopg')
    return url
