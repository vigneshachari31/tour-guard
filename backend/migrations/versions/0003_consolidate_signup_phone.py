"""Consolidate signup phone. Apply only after column-removal approval."""
from alembic import op
from backend.migrations.consolidate_signup_phone import consolidate
revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    consolidate(op.get_bind(), drop_approved=True)


def downgrade():
    raise RuntimeError('Automatic data migration reversal is disabled')
