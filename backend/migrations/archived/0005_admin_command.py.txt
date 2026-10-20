"""Rescue-command roles, statuses and deactivatable hazards."""

import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    inspector = sa.inspect(op.get_bind())
    user_columns = {column["name"] for column in inspector.get_columns("users")}
    hazard_columns = {column["name"] for column in inspector.get_columns("hazard_zones")}
    if "role" not in user_columns:
        op.add_column("users", sa.Column("role", sa.String(20), nullable=False, server_default="tourist"))
    if "is_active" not in hazard_columns:
        op.add_column("hazard_zones", sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()))
    op.execute("ALTER TABLE sos_events DROP CONSTRAINT IF EXISTS sos_status_values")
    op.execute("ALTER TABLE sos_events ALTER COLUMN status TYPE varchar(20)")
    op.create_check_constraint("sos_status_values", "sos_events", "status IN ('active', 'acknowledged', 'dispatched', 'resolved')")


def downgrade():
    raise RuntimeError("Do not downgrade rescue-command data without a preservation plan")
