"""Revocable mobile refresh sessions; existing account data is preserved."""
from alembic import op
import sqlalchemy as sa

revision = '0011'
down_revision = '0010'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('refresh_sessions',
        sa.Column('token_hash', sa.String(64), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('password_stamp', sa.String(64), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_refresh_sessions_user_id', 'refresh_sessions', ['user_id'])
    op.execute('ALTER TABLE refresh_sessions ENABLE ROW LEVEL SECURITY')
    op.execute('REVOKE ALL ON refresh_sessions FROM PUBLIC')
    op.execute("DO $$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON refresh_sessions FROM %I', r); END IF; END LOOP; END $$")


def downgrade():
    op.drop_table('refresh_sessions')
