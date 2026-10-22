"""Create tourist_hazard_reports table with GiST spatial index.

Revision ID: 0009
Revises: 0008
"""

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "tourist_hazard_reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "tourist_id",
            sa.String(length=35),
            sa.ForeignKey("users.tourist_id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        sa.Column("hazard_type", sa.String(length=50), nullable=False),
        sa.Column("severity", sa.Integer(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "location",
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.String(length=20),
            server_default="pending",
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "severity BETWEEN 1 AND 5", name="tourist_hazard_severity_range"
        ),
    )
    op.create_index(
        "idx_tourist_hazard_reports_location",
        "tourist_hazard_reports",
        ["location"],
        postgresql_using="gist",
    )


def downgrade():
    op.drop_index(
        "idx_tourist_hazard_reports_location",
        table_name="tourist_hazard_reports",
        postgresql_using="gist",
    )
    op.drop_table("tourist_hazard_reports")

