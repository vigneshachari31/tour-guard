from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from fastapi import HTTPException
from backend.routers.moderation import moderate, ReportStatus, report_rows, verified_features

@pytest.mark.parametrize("status", ["verified", "rejected"])
def test_moderation_commits(status):
    db = Mock()
    report = SimpleNamespace(status="pending")
    db.scalar.return_value = report
    assert moderate(4, ReportStatus(status=status), Mock(), db) == {"id": 4, "status": status}
    assert report.status == status
    db.commit.assert_called_once()

def test_missing_report():
    db = Mock()
    db.scalar.return_value = None
    with pytest.raises(HTTPException) as error:
        moderate(8, ReportStatus(status="verified"), Mock(), db)
    assert error.value.status_code == 404
    db.commit.assert_not_called()

def test_pending_filter_and_coordinates():
    db = Mock()
    db.execute.return_value = [(SimpleNamespace(id=4, hazard_type="flood", severity=3, description="Water", status="pending", created_at=None), 19, 72)]
    rows = report_rows(db, "pending")
    assert rows[0]["latitude"] == 19
    assert rows[0]["status"] == "pending"
    assert db.execute.call_args.args[0].compile().params["status_1"] == "pending"

def test_public_query_requires_verified():
    db = Mock()
    db.execute.return_value = []
    assert verified_features(db) == []
    assert db.execute.call_args.args[0].compile().params["status_1"] == "verified"
