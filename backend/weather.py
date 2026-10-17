"""Small, explicit adapter for the Open-Meteo forecast API.

The response is used as environmental context only. It is not an IMD warning and
does not make the route assessment a validated safety prediction.
"""

from datetime import datetime, timezone
from typing import Any

import httpx

try:
    from .config import get_settings
    from .schemas import WeatherObservation
except ImportError:  # Supports: uvicorn main:app from backend/
    from config import get_settings
    from schemas import WeatherObservation


def fetch_current_weather(latitude: float, longitude: float, client: httpx.Client) -> WeatherObservation | None:
    """Return the latest provider observation, or None if it cannot be verified."""
    try:
        response = client.get(
            f"{get_settings().weather_base_url}/v1/forecast",
            params={
                "latitude": latitude,
                "longitude": longitude,
                "current": "temperature_2m,precipitation,wind_speed_10m",
                "wind_speed_unit": "kmh",
                "timezone": "UTC",
            },
        )
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        current = payload["current"]
        observed_at = datetime.fromisoformat(current["time"].replace("Z", "+00:00"))
        if observed_at.tzinfo is None:
            observed_at = observed_at.replace(tzinfo=timezone.utc)
        return WeatherObservation(
            rainfall_mm_h=float(current["precipitation"]),
            wind_kmh=float(current["wind_speed_10m"]),
            observed_at=observed_at,
            source="Open-Meteo current forecast",
        )
    except (httpx.HTTPError, KeyError, TypeError, ValueError):
        # A safety UI must never invent weather after a provider failure.
        return None
