from datetime import datetime

from geoalchemy2 import Geography, Geometry, WKBElement
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    cast,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    tourist_id: Mapped[str] = mapped_column(String(35), unique=True, index=True)
    full_name: Mapped[str | None] = mapped_column(String(255))
    emergency_contact_phone: Mapped[str | None] = mapped_column(String(25))


class HazardZone(Base):
    __tablename__ = "hazard_zones"
    __table_args__ = (
        CheckConstraint("severity BETWEEN 1 AND 5", name="hazard_severity_range"),
        CheckConstraint(
            "GeometryType(geometry) IN ('POINT', 'POLYGON')",
            name="hazard_geometry_type",
        ),
        CheckConstraint(
            "ST_IsValid(geometry) AND NOT ST_IsEmpty(geometry)",
            name="hazard_geometry_valid",
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    hazard_type: Mapped[str] = mapped_column(String(50))
    severity: Mapped[int] = mapped_column(Integer)
    # Mixed point/polygon storage, restricted by the check constraint above.
    geometry: Mapped[WKBElement] = mapped_column(Geometry("GEOMETRY", srid=4326))
    source: Mapped[str | None] = mapped_column(String(500))
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


# The query casts geometry to geography for meter-based distances; index that expression.
Index(
    "ix_hazard_zones_geography",
    cast(HazardZone.geometry, Geography(srid=4326)),
    postgresql_using="gist",
)


class SOSEvent(Base):
    __tablename__ = "sos_events"
    __table_args__ = (
        CheckConstraint("latitude BETWEEN -90 AND 90", name="sos_latitude_range"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="sos_longitude_range"),
        CheckConstraint("status IN ('active', 'resolved')", name="sos_status_values"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    tourist_id: Mapped[str] = mapped_column(
        ForeignKey("users.tourist_id", ondelete="RESTRICT"), index=True
    )
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(
        String(10), default="active", server_default="active"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
