"""Add workflow status and hazard validity; keep legacy SOS status compatible."""

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "ALTER TABLE sos_events ADD COLUMN IF NOT EXISTS workflow_status VARCHAR(20)"
    )
    op.execute(
        "UPDATE sos_events SET workflow_status = CASE WHEN status='resolved' THEN 'RESOLVED' WHEN status IN ('acknowledged','dispatched') THEN 'IN_PROGRESS' ELSE 'OPEN' END WHERE workflow_status IS NULL"
    )
    op.execute("ALTER TABLE sos_events ALTER COLUMN workflow_status SET DEFAULT 'OPEN'")
    op.execute("ALTER TABLE sos_events ALTER COLUMN workflow_status SET NOT NULL")
    op.execute(
        "ALTER TABLE hazard_zones ADD COLUMN IF NOT EXISTS valid_from TIMESTAMPTZ"
    )
    op.execute(
        "ALTER TABLE hazard_zones ADD COLUMN IF NOT EXISTS valid_until TIMESTAMPTZ"
    )
    op.execute(
        "ALTER TABLE risk_assessment_logs ADD COLUMN IF NOT EXISTS trip_id INTEGER REFERENCES trips(id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_sos_workflow ON sos_events(workflow_status)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_risk_trip ON risk_assessment_logs(trip_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_location_trip_time ON trip_location_updates(trip_id, recorded_at)"
    )
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_assignment_active_incident ON rescue_assignments(sos_event_id) WHERE status='assigned'"
    )
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_assignment_active_responder ON rescue_assignments(responder_id) WHERE status='assigned'"
    )


def downgrade():
    raise RuntimeError("A reviewed data-preservation plan is required")
