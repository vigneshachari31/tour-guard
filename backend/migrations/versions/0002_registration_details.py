"""Registration details and nullable legacy hazard metadata; no data backfill."""
from alembic import op
from backend.migrations.add_registration_fields import apply_columns
revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade():
    apply_columns(op.get_bind())


def downgrade():
    raise RuntimeError("Automatic column deletion is disabled to preserve account data")
