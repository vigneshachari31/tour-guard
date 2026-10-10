import pytest
from backend.tests.database_safety import validated_test_url


@pytest.mark.parametrize('url', [
    'postgresql://localhost/tour_guard',
    'postgresql://localhost/postgres',
    'postgresql://localhost/tour_guard_prod',
    'sqlite:///tour_guard_test',
])
def test_application_databases_rejected(url):
    with pytest.raises(ValueError, match='separate tour_guard_test'):
        validated_test_url(url)


def test_separate_database_accepted():
    url = validated_test_url('postgresql://localhost/tour_guard_test')
    assert url.database == 'tour_guard_test'
    assert url.drivername == 'postgresql+psycopg'


def test_registration_does_not_survive_isolated_fixture(client):
    # Fixture teardown disposes its in-memory SQLite engine. No network API calls.
    from backend.database import get_db
    provider = client.app.dependency_overrides[get_db]()
    db = next(provider)
    try:
        assert db.get_bind().dialect.name == 'sqlite'
        assert db.get_bind().url.database is None
    finally:
        provider.close()
