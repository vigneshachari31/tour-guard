from alembic import context

from backend import models  # noqa: F401
from backend.database import Base, get_engine


def run_migrations() -> None:
    if context.is_offline_mode():
        raise RuntimeError("Use online migrations against PostgreSQL/PostGIS")
    with get_engine().connect() as connection:
        context.configure(connection=connection, target_metadata=Base.metadata)
        with context.begin_transaction():
            context.run_migrations()


run_migrations()
