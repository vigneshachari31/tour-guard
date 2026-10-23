from unittest.mock import MagicMock
import pytest
from backend.routers.hazards import report_tourist_hazard
from backend.schemas import TouristHazardReportCreate, TouristHazardReportResponse
from backend.models import TouristHazardReport, HazardZone, User


@pytest.mark.parametrize("incident_type", ["landslide", "accident", "fire", "fallen_tree", "damaged_road", "other"])
def test_tourist_hazard_report_saves_to_dedicated_table_not_hazard_zones(incident_type):
    user = User(
        id=1,
        email="tourist@example.com",
        tourist_id="TG-12345678",
        role="tourist",
    )
    db = MagicMock()
    # Mock refresh to populate id, status, created_at
    def mock_refresh(instance):
        instance.id = 42
        instance.status = "pending"
        from datetime import datetime, timezone
        instance.created_at = datetime.now(timezone.utc)
    db.refresh.side_effect = mock_refresh

    body = TouristHazardReportCreate(
        latitude=11.4102,
        longitude=76.6950,
        hazard_type=incident_type,
        severity=4,
        description="Fallen boulder near hairpin bend 3",
    )

    response = report_tourist_hazard(body=body, user=user, db=db)

    # 1. Verify db.add was called with a TouristHazardReport instance
    assert db.add.called
    added_obj = db.add.call_args[0][0]
    assert isinstance(added_obj, TouristHazardReport)
    assert not isinstance(added_obj, HazardZone)

    # 2. Verify TouristHazardReport fields
    assert added_obj.tourist_id == "TG-12345678"
    assert added_obj.hazard_type == incident_type
    assert added_obj.severity == 4
    assert added_obj.description == "Fallen boulder near hairpin bend 3"
    assert added_obj.status == "pending"

    # 3. Verify response
    assert isinstance(response, TouristHazardReportResponse)
    assert response.id == 42
    assert response.tourist_id == "TG-12345678"
    assert response.hazard_type == incident_type
    assert response.severity == 4
    assert response.description == "Fallen boulder near hairpin bend 3"
    assert response.status == "pending"

