"""Reconcile previously applied role/trip schema; safe for fresh installations."""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'tourist'"
    )
    op.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true"
    )
    op.execute(
        "ALTER TABLE hazard_zones ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS trips (\n\tid SERIAL NOT NULL, \n\ttourist_id VARCHAR(35) NOT NULL, \n\tsource_name VARCHAR(255), \n\tdestination_name VARCHAR(255) NOT NULL, \n\torigin_lat FLOAT NOT NULL, \n\torigin_lng FLOAT NOT NULL, \n\tdest_lat FLOAT NOT NULL, \n\tdest_lng FLOAT NOT NULL, \n\tstatus VARCHAR(20) DEFAULT 'active' NOT NULL, \n\tstarted_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tended_at TIMESTAMP WITH TIME ZONE, \n\tlast_latitude FLOAT, \n\tlast_longitude FLOAT, \n\tlast_location_updated_at TIMESTAMP WITH TIME ZONE, \n\troute_geometry TEXT, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(tourist_id) REFERENCES users (tourist_id)\n)\n\n"
    )


def downgrade():
    raise RuntimeError("A reviewed data-preservation plan is required")
