"""Exercise real HTTP/auth/PostGIS flow in connection-local temporary tables.

Never writes application tables or advances application sequences. All fixtures
and location updates are rolled back; temp tables exist only on this connection.
Run explicitly: python -m backend.tests.check_geofence_request_postgis
"""
from fastapi.testclient import TestClient
from geoalchemy2 import WKTElement
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from backend.auth import create_access_token
from backend.database import get_db, get_engine
from backend.main import create_app
from backend.models import HazardZone, LocationHistory, Trip, User
from backend.tests.check_geofence_postgis import POLYGON


def main():
    engine = get_engine()
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            # LIKE copies structure, not records. Local names shadow public tables.
            for table in ("users", "trips", "hazard_zones", "trip_location_updates"):
                connection.execute(text(f"CREATE TEMP TABLE {table} (LIKE public.{table} INCLUDING DEFAULTS INCLUDING CONSTRAINTS) ON COMMIT DROP"))
            connection.execute(text("CREATE TEMP SEQUENCE geofence_test_location_id"))
            connection.execute(text("ALTER TABLE pg_temp.trip_location_updates ALTER COLUMN id SET DEFAULT nextval('pg_temp.geofence_test_location_id')"))
            # Abort before any writes unless all unqualified ORM names resolve locally.
            for table in ("users", "trips", "hazard_zones", "trip_location_updates"):
                assert connection.scalar(text(f"SELECT '{table}'::regclass = 'pg_temp.{table}'::regclass"))
            with Session(connection, join_transaction_mode="create_savepoint") as db:
                db.add(User(id=1, email="geofence-test@example.com", hashed_password="unused",
                            tourist_id="TG-AAAAAAAA", role="tourist", is_active=True))
                db.add(Trip(id=1, tourist_id="TG-AAAAAAAA", destination_name="Temporary test",
                            origin_lat=19, origin_lng=72, dest_lat=20, dest_lng=73))
                db.add(HazardZone(id=9, name="dangerous zone", hazard_type="landslide",
                                  severity=4, source="Temporary integration fixture",
                                  geometry=WKTElement(POLYGON, srid=4326), is_active=True))
                db.commit()
                app = create_app()
                def database():
                    try:
                        yield db
                    except Exception:
                        db.rollback()
                        raise
                app.dependency_overrides[get_db] = database
                headers = {"Authorization": "Bearer " + create_access_token(1)}
                with TestClient(app) as client:
                    def send(lat=19.0440, lng=72.8565):
                        response = client.post("/api/v1/trips/1/locations", headers=headers,
                                               json={"latitude": lat, "longitude": lng})
                        assert response.status_code == 201, response.status_code
                        return response.json()
                    assert send()["alerts"][0]["hazard_id"] == 9
                    assert send()["alerts"] == []
                    assert send(20, 73)["current_hazards"] == []
                    assert send()["alerts"][0]["hazard_id"] == 9
                    hazard = db.get(HazardZone, 9)
                    hazard.is_active = False
                    db.commit()
                    assert send()["current_hazards"] == []
                    hazard.is_active = True
                    hazard.geometry = WKTElement("POINT(72.8565 19.0440)", srid=4326)
                    db.commit()
                    assert send()["alerts"][0]["hazard_id"] == 9
                    assert db.scalar(select(func.count(LocationHistory.id))) == 6
                    assert db.get(Trip, 1).last_latitude == 19.0440
                    print("PASS: authenticated GPS persistence, polygon entry, repeat, exit/re-entry, inactive hazard and point proximity")
        finally:
            transaction.rollback()
    engine.dispose()


if __name__ == "__main__":
    main()
