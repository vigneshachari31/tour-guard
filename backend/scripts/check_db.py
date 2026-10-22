import sys
from pathlib import Path
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from backend.database import get_engine
from sqlalchemy import text

try:
    engine = get_engine()
    with engine.connect() as conn:
        tables = [r[0] for r in conn.execute(text("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"))]
        print("Existing tables:", tables)
        try:
            ver = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
            print("Current Alembic version:", ver)
        except Exception as e:
            print("Alembic version table error:", e)
except Exception as e:
    print("Database connection error:", e)

