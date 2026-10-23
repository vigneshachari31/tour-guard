import httpx
import pytest
from types import SimpleNamespace
from backend.risk_engine import choose_route, fetch_routes, nearby_hazards
from backend.schemas import RouteGeometry, RouteRequest, HazardSummary


def hazard(severity):
    return HazardSummary(id=1, name="Flood", hazard_type="flood", severity=severity, source="test")


@pytest.mark.parametrize("risks, expected", [
    ([[5], []], 1), ([[5], [2]], 1), ([[2, 2], [2]], 1),
    ([[], []], 0), ([[4], [5]], 0),
])
def test_prefers_lower_hazard_before_speed(risks, expected):
    candidates = [(0, 1000, 60), (1, 2000, 120)]
    route, hazards, message = choose_route(candidates, lambda i: [hazard(s) for s in risks[i]])
    assert route == candidates[expected]
    assert "Compared 2 routes" in message
    if all(risks):
        assert "All available routes have reported hazards" in message
    if expected == 1:
        assert "1 min longer" in message


def test_single_route_discloses_no_comparison():
    _, _, message = choose_route([(0, 1000, 60)], lambda _: [])
    assert "Only one route available" in message


def test_requests_and_parses_alternatives():
    def handler(request):
        assert request.url.params["alternatives"] == "true"
        return httpx.Response(200, json={"code": "Ok", "routes": [
            {"geometry": {"type": "LineString", "coordinates": [[0, 0], [1, 1]]},
             "distance": distance, "duration": 60} for distance in (1000, 2000)]})
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        routes = fetch_routes(RouteRequest(origin_lat=0, origin_lng=0, dest_lat=1, dest_lng=1), client)
    assert len(routes) == 2


def test_verified_report_query(monkeypatch):
    monkeypatch.setattr("backend.risk_engine.nearby_official_hazards", lambda *args: [])
    class DB:
        def execute(self, query):
            compiled = query.compile()
            assert "verified" in compiled.params.values()
            assert "ST_DWithin" in str(compiled)
            return SimpleNamespace(all=lambda: [(SimpleNamespace(id=7, description="Flood",
                hazard_type="flood", severity=4), '{"type":"Point","coordinates":[0,0]}')])
    result = nearby_hazards(DB(), RouteGeometry(type="LineString", coordinates=[(0, 0), (1, 1)]), 250)
    assert result[0].id == -7
    assert result[0].source == "Verified tourist report"


def test_endpoint_returns_selected_geometry(client, monkeypatch):
    from backend.tests.test_api import register
    from backend.main import get_http
    account = register(client)
    direct = RouteGeometry(type="LineString", coordinates=[(0, 0), (1, 1)])
    detour = RouteGeometry(type="LineString", coordinates=[(0, 0), (0, 1), (1, 1)])
    monkeypatch.setattr("backend.main.fetch_routes", lambda *args: [(direct, 1000, 60), (detour, 2000, 120)])
    monkeypatch.setattr("backend.main.nearby_hazards", lambda db, geometry, buffer: [hazard(5)] if geometry == direct else [])
    client.app.dependency_overrides[get_http] = lambda: None
    response = client.post('/api/v1/route/analyze', json={"origin_lat":0,"origin_lng":0,"dest_lat":1,"dest_lng":1},
        headers={"Authorization": f"Bearer {account['access_token']}"})
    assert response.status_code == 200
    data = response.json()
    assert data['geometry']['coordinates'] == [[0, 0], [0, 1], [1, 1]]
    assert data['hazards'] == []
    assert "Compared 2 routes" in data['assessment']['reasons'][0]
    assert data['original_geometry']['coordinates'] == [[0, 0], [1, 1]]
    assert data['original_hazard_count'] == 1
    response = client.post('/api/v1/route/analyze', json={"origin_lat":0,"origin_lng":0,"dest_lat":1,"dest_lng":1,"route_preference":"fastest"},
        headers={"Authorization": f"Bearer {account['access_token']}"})
    assert response.status_code == 200
    assert response.json()['geometry']['coordinates'] == [[0, 0], [1, 1]]
    assert len(response.json()['hazards']) == 1
