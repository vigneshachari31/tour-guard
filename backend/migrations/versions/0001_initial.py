"""Initial PostGIS schema. Provision the extension with an administrator first."""

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # No automatic extension creation requiring an elevated application account.
    op.execute("SELECT PostGIS_Version()")
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("tourist_id", sa.String(35), nullable=False),
        sa.Column("emergency_contact_phone", sa.String(25)),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_index("ix_users_tourist_id", "users", ["tourist_id"], unique=True)
    op.create_table(
        "hazard_zones",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("hazard_type", sa.String(50), nullable=False),
        sa.Column("severity", sa.Integer(), nullable=False),
        sa.Column(
            "geometry",
            Geometry("GEOMETRY", srid=4326, spatial_index=False),
            nullable=False,
        ),
        sa.Column("source", sa.String(500), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("severity BETWEEN 1 AND 5", name="hazard_severity_range"),
        sa.CheckConstraint(
            "GeometryType(geometry) IN ('POINT', 'POLYGON')",
            name="hazard_geometry_type",
        ),
        sa.CheckConstraint(
            "ST_IsValid(geometry) AND NOT ST_IsEmpty(geometry)",
            name="hazard_geometry_valid",
        ),
    )
    op.create_index(
        "idx_hazard_zones_geometry",
        "hazard_zones",
        ["geometry"],
        postgresql_using="gist",
    )
    op.execute(
        "CREATE INDEX ix_hazard_zones_geography ON hazard_zones USING gist ((geometry::geography))"
    )
    op.create_table(
        "sos_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "tourist_id",
            sa.String(35),
            sa.ForeignKey("users.tourist_id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("status", sa.String(10), server_default="active", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("latitude BETWEEN -90 AND 90", name="sos_latitude_range"),
        sa.CheckConstraint(
            "longitude BETWEEN -180 AND 180", name="sos_longitude_range"
        ),
        sa.CheckConstraint(
            "status IN ('active', 'resolved')", name="sos_status_values"
        ),
    )
    op.create_index("ix_sos_events_tourist_id", "sos_events", ["tourist_id"])


def downgrade() -> None:
    op.drop_table("sos_events")
    op.drop_table("hazard_zones")
    op.drop_table("users")
