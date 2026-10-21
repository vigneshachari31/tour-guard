"""Preserve geofence state and entry alerts alongside each GPS observation."""

import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "trip_location_updates", sa.Column("current_hazards", sa.Text(), nullable=True)
    )
    op.add_column(
        "trip_location_updates", sa.Column("hazard_alerts", sa.Text(), nullable=True)
    )
    # Widen accepted geometry types; no hazard rows are modified or deleted.
    op.drop_constraint("hazard_geometry_type", "hazard_zones", type_="check")
    op.create_check_constraint(
        "hazard_geometry_type",
        "hazard_zones",
        "GeometryType(geometry) IN ('POINT', 'POLYGON', 'MULTIPOLYGON')",
    )


def downgrade():
    raise RuntimeError("A reviewed data-preservation plan is required")
