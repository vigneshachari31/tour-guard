from datetime import datetime

from geoalchemy2 import Geography, Geometry, WKBElement
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    cast,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

try:
    from .database import Base
except ImportError:
    from database import Base


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    role: Mapped[str] = mapped_column(
        String(20), default="tourist", server_default="tourist"
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default="true"
    )
    hashed_password: Mapped[str] = mapped_column(String(255))
    tourist_id: Mapped[str] = mapped_column(String(35), unique=True, index=True)
    full_name: Mapped[str | None] = mapped_column(String(255))
    emergency_contact_phone: Mapped[str | None] = mapped_column(String(25))
    # Admin is assigned manually by a database administrator; users cannot self-register it.
    role: Mapped[str] = mapped_column(String(20), default="tourist", server_default="tourist")


class HazardZone(Base):
    __tablename__ = "hazard_zones"
    __table_args__ = (
        CheckConstraint("severity BETWEEN 1 AND 5", name="hazard_severity_range"),
        CheckConstraint(
            "GeometryType(geometry) IN ('POINT', 'POLYGON', 'MULTIPOLYGON')",
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
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default="true"
    )
    valid_from: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Mixed point/polygon storage, restricted by the check constraint above.
    geometry: Mapped[WKBElement] = mapped_column(Geometry("GEOMETRY", srid=4326))
    source: Mapped[str | None] = mapped_column(String(500))
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    is_active: Mapped[bool] = mapped_column(default=True, server_default="true")


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
        CheckConstraint("status IN ('active', 'acknowledged', 'dispatched', 'resolved')", name="sos_status_values"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    tourist_id: Mapped[str] = mapped_column(
        ForeignKey("users.tourist_id", ondelete="RESTRICT"), index=True
    )
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(
        String(20), default="active", server_default="active"
    )
    workflow_status: Mapped[str] = mapped_column(
        String(20), default="OPEN", server_default="OPEN"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class UserProfile(Base):
    __tablename__ = "user_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    full_name: Mapped[str | None] = mapped_column(String(255))
    phone_number: Mapped[str | None] = mapped_column(String(50))
    profile_picture_url: Mapped[str | None] = mapped_column(Text)
    blood_group: Mapped[str | None] = mapped_column(String(10))
    emergency_contact: Mapped[str | None] = mapped_column(String(100))
    medical_notes: Mapped[str | None] = mapped_column(Text)
    allergies: Mapped[str | None] = mapped_column(Text)
    avatar_data: Mapped[bytes | None] = mapped_column(LargeBinary)
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(), server_default=func.now(), onupdate=func.now()
    )


class Trip(Base):
    __tablename__ = "trips"
    id: Mapped[int] = mapped_column(primary_key=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("users.tourist_id"), index=True)
    source_name: Mapped[str | None] = mapped_column(String(255))
    destination_name: Mapped[str] = mapped_column(String(255))
    origin_lat: Mapped[float] = mapped_column(Float)
    origin_lng: Mapped[float] = mapped_column(Float)
    dest_lat: Mapped[float] = mapped_column(Float)
    dest_lng: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(
        String(20), default="active", server_default="active"
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_latitude: Mapped[float | None] = mapped_column(Float)
    last_longitude: Mapped[float | None] = mapped_column(Float)
    last_location_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    route_geometry: Mapped[str | None] = mapped_column(Text)


class LocationHistory(Base):
    __tablename__ = "trip_location_updates"
    id: Mapped[int] = mapped_column(primary_key=True)
    trip_id: Mapped[int] = mapped_column(ForeignKey("trips.id"), index=True)
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    # Snapshots preserve entry history without creating rescue/SOS incidents.
    current_hazards: Mapped[str | None] = mapped_column(Text)
    hazard_alerts: Mapped[str | None] = mapped_column(Text)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class RiskAssessmentLog(Base):
    __tablename__ = "risk_assessment_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    trip_id: Mapped[int | None] = mapped_column(ForeignKey("trips.id"), index=True)
    origin_lat: Mapped[float] = mapped_column(Float)
    origin_lng: Mapped[float] = mapped_column(Float)
    dest_lat: Mapped[float] = mapped_column(Float)
    dest_lng: Mapped[float] = mapped_column(Float)
    risk_level: Mapped[str] = mapped_column(String(20))
    distance_meters: Mapped[float] = mapped_column(Float)
    duration_seconds: Mapped[float] = mapped_column(Float)
    hazards_count: Mapped[int] = mapped_column(Integer, default=0)
    weather_used: Mapped[bool] = mapped_column(Boolean, default=False)
    reasons: Mapped[str | None] = mapped_column(Text)
    limitations: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Responder(Base):
    __tablename__ = "responders"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(50))
    email: Mapped[str | None] = mapped_column(String(254))
    role: Mapped[str] = mapped_column(String(50), default="Mountain Rescue")
    status: Mapped[str] = mapped_column(String(20), default="available")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class SOSHistory(Base):
    __tablename__ = "sos_event_history"
    id: Mapped[int] = mapped_column(primary_key=True)
    sos_event_id: Mapped[int] = mapped_column(ForeignKey("sos_events.id"), index=True)
    old_status: Mapped[str] = mapped_column(String(20))
    new_status: Mapped[str] = mapped_column(String(20))
    changed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class RescueAssignment(Base):
    __tablename__ = "rescue_assignments"
    id: Mapped[int] = mapped_column(primary_key=True)
    sos_event_id: Mapped[int] = mapped_column(ForeignKey("sos_events.id"), index=True)
    responder_id: Mapped[int] = mapped_column(ForeignKey("responders.id"))
    assigned_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(20), default="assigned")
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    admin_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    admin_email: Mapped[str] = mapped_column(String(254))
    action: Mapped[str] = mapped_column(String(100))
    resource_type: Mapped[str] = mapped_column(String(50))
    resource_id: Mapped[str | None] = mapped_column(String(100))
    details: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
