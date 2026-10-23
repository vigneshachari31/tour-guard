from datetime import datetime, timedelta, timezone
import httpx
import pytest
from backend.risk_engine import fetch_route_weather
from backend.schemas import RouteGeometry, WeatherObservation


@pytest.mark.parametrize('age, rain, units, valid', [
    (0, 35, 'mm', True), (7200, 2, 'mm', False),
    (-7200, 2, 'mm', False), (0, None, 'mm', False),
    (0, 2, 'inch', False), (0, float('inf'), 'mm', False),
])
def test_forecast_validation(age, rain, units, valid):
    import json
    def handler(request):
        assert request.url.host == 'api.open-meteo.com'
        assert request.url.params['latitude'] == '19'
        assert 'authorization' not in request.headers
        return httpx.Response(200, text=json.dumps({
            'hourly_units': {'precipitation': units, 'wind_speed_10m': 'km/h'},
            'hourly': {'time': [(datetime.now(timezone.utc)-timedelta(seconds=age)).isoformat()],
                       'precipitation': [rain], 'wind_speed_10m': [12]},
        }))
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = fetch_route_weather(19, 72, client)
    assert (result is not None) == valid


def test_weather_timeout_is_not_route_failure():
    def handler(request):
        raise httpx.ReadTimeout('offline')
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        assert fetch_route_weather(19, 72, client) is None


@pytest.mark.parametrize('available', [True, False])
def test_route_endpoint_uses_server_weather(client, monkeypatch, available):
    from backend.main import get_http
    from backend.tests.test_api import register
    account = register(client)
    geometry = RouteGeometry(type='LineString', coordinates=[(72, 19), (73, 20)])
    monkeypatch.setattr('backend.main.fetch_routes', lambda *args: [(geometry, 1000, 60)])
    monkeypatch.setattr('backend.main.nearby_hazards', lambda *args: [])
    weather = WeatherObservation(rainfall_mm_h=35, wind_kmh=12,
        observed_at=datetime.now(timezone.utc), source='Open-Meteo hourly forecast at route origin')
    monkeypatch.setattr('backend.main.fetch_route_weather', lambda *args: weather if available else None)
    client.app.dependency_overrides[get_http] = lambda: None
    response = client.post('/api/v1/route/analyze',
        headers={'Authorization': f"Bearer {account['access_token']}"},
        json={'origin_lat':19, 'origin_lng':72, 'dest_lat':20, 'dest_lng':73})
    assert response.status_code == 200
    assessment = response.json()['assessment']
    assert assessment['weather_used'] == available
    if available:
        assert assessment['level'] == 'HIGH RISK'
        assert any('rain 35 mm/h' in r for r in assessment['reasons'])
        assert not any('caller-supplied' in r or 'Weather missing' in r for r in assessment['limitations'])
    else:
        assert any('Weather missing' in r for r in assessment['limitations'])
