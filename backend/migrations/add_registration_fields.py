"""Additive bridge for existing, unversioned databases; never stamps a baseline."""
from sqlalchemy import Column, DateTime, String, inspect
from alembic.migration import MigrationContext
from alembic.operations import Operations
from backend.database import get_engine


def apply_columns(connection):
    inspector = inspect(connection)
    additions = {
        "users": [Column("full_name", String(255), nullable=True),
                  Column("emergency_contact_phone", String(25), nullable=True)],
        "hazard_zones": [Column("source", String(500), nullable=True),
                         Column("updated_at", DateTime(timezone=True), nullable=True)],
    }
    for table in additions:
        if not inspector.has_table(table):
            raise RuntimeError(f"Missing {table}; use the initial migration for a new database")
    operations = Operations(MigrationContext.configure(connection))
    for table, columns in additions.items():
        existing = {column["name"] for column in inspector.get_columns(table)}
        for column in columns:
            if column.name not in existing:
                operations.add_column(table, column)


if __name__ == "__main__":
    with get_engine().begin() as connection:
        apply_columns(connection)
    print("Additive columns verified. No existing row values changed; no baseline stamped.")
