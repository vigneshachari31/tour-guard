"""Add tracking timestamps without rewriting historical trip records."""

from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "ALTER TABLE trips ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now()"
    )
    op.execute("ALTER TABLE trips ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ")


def downgrade():
    raise RuntimeError("Timestamp removal requires an approved data-preservation plan")
