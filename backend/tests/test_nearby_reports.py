from datetime import datetime, timezone
from unittest.mock import MagicMock
from sqlalchemy.dialects import postgresql
from backend.routers.hazards import nearby_tourist_reports


def test_nearby_reports_only_public_fields_and_active_statuses():
    db = MagicMock()
    report = MagicMock(id=3, description="Fallen tree", hazard_type="road", severity=3,
                       status="pending", created_at=datetime.now(timezone.utc))
    db.scalars.return_value.all.return_value = [report]
    result = nearby_tourist_reports(MagicMock(), db, 19, 72)
    assert result["reports"][0]["name"] == "Fallen tree"
    assert result["reports"][0]["status"] == "pending"
    assert "tourist_id" not in result["reports"][0]
    query = str(db.scalars.call_args.args[0].compile(dialect=postgresql.dialect(), compile_kwargs={"literal_binds": True}))
    assert "ST_DWithin" in query and "2000" in query
    assert "'pending', 'verified'" in query
    assert "LIMIT 100" in query
