"""Add authenticated profiles and private avatar storage without resetting data."""

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    if not inspector.has_table("user_profiles"):
        op.create_table(
            "user_profiles",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id",
                sa.Integer(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
                unique=True,
            ),
            sa.Column("full_name", sa.String(255)),
            sa.Column("phone_number", sa.String(50)),
            sa.Column("profile_picture_url", sa.Text()),
            sa.Column("blood_group", sa.String(10)),
            sa.Column("emergency_contact", sa.String(100)),
            sa.Column("medical_notes", sa.Text()),
            sa.Column("allergies", sa.Text()),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("avatar_data", sa.LargeBinary()),
        )
    elif "avatar_data" not in {
        column["name"] for column in inspector.get_columns("user_profiles")
    }:
        op.add_column(
            "user_profiles", sa.Column("avatar_data", sa.LargeBinary(), nullable=True)
        )


def downgrade():
    raise RuntimeError("Profile deletion requires an explicit data-preservation plan")
