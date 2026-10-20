"""Baseline for the existing rescue/history tables, preserving all records."""

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS responders (\n\tid SERIAL NOT NULL, \n\tname VARCHAR(200) NOT NULL, \n\tphone VARCHAR(50) NOT NULL, \n\temail VARCHAR(254), \n\trole VARCHAR(50) NOT NULL, \n\tstatus VARCHAR(20) NOT NULL, \n\tcreated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id)\n)\n\n"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS sos_event_history (\n\tid SERIAL NOT NULL, \n\tsos_event_id INTEGER NOT NULL, \n\told_status VARCHAR(20) NOT NULL, \n\tnew_status VARCHAR(20) NOT NULL, \n\tchanged_by_id INTEGER, \n\tnotes TEXT, \n\tcreated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(sos_event_id) REFERENCES sos_events (id), \n\tFOREIGN KEY(changed_by_id) REFERENCES users (id)\n)\n\n"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS rescue_assignments (\n\tid SERIAL NOT NULL, \n\tsos_event_id INTEGER NOT NULL, \n\tresponder_id INTEGER NOT NULL, \n\tassigned_by_id INTEGER, \n\tstatus VARCHAR(20) NOT NULL, \n\tnotes TEXT, \n\tcreated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tupdated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(sos_event_id) REFERENCES sos_events (id), \n\tFOREIGN KEY(responder_id) REFERENCES responders (id), \n\tFOREIGN KEY(assigned_by_id) REFERENCES users (id)\n)\n\n"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS trip_location_updates (\n\tid SERIAL NOT NULL, \n\ttrip_id INTEGER NOT NULL, \n\tlatitude FLOAT NOT NULL, \n\tlongitude FLOAT NOT NULL, \n\trecorded_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(trip_id) REFERENCES trips (id)\n)\n\n"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS risk_assessment_logs (\n\tid SERIAL NOT NULL, \n\tuser_id INTEGER, \n\ttrip_id INTEGER, \n\torigin_lat FLOAT NOT NULL, \n\torigin_lng FLOAT NOT NULL, \n\tdest_lat FLOAT NOT NULL, \n\tdest_lng FLOAT NOT NULL, \n\trisk_level VARCHAR(20) NOT NULL, \n\tdistance_meters FLOAT NOT NULL, \n\tduration_seconds FLOAT NOT NULL, \n\thazards_count INTEGER NOT NULL, \n\tweather_used BOOLEAN NOT NULL, \n\treasons TEXT, \n\tlimitations TEXT, \n\tcreated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(user_id) REFERENCES users (id), \n\tFOREIGN KEY(trip_id) REFERENCES trips (id)\n)\n\n"
    )
    op.execute(
        "\nCREATE TABLE IF NOT EXISTS audit_logs (\n\tid SERIAL NOT NULL, \n\tadmin_id INTEGER, \n\tadmin_email VARCHAR(254) NOT NULL, \n\taction VARCHAR(100) NOT NULL, \n\tresource_type VARCHAR(50) NOT NULL, \n\tresource_id VARCHAR(100), \n\tdetails TEXT, \n\tcreated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, \n\tPRIMARY KEY (id), \n\tFOREIGN KEY(admin_id) REFERENCES users (id)\n)\n\n"
    )


def downgrade():
    raise RuntimeError("A reviewed data-preservation plan is required")
