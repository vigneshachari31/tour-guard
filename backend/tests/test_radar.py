import numpy as np
from backend.ml_model.radar_model import infer, PATH

def test_radar_abstains_outside_training_range():
    assert not infer([float("nan"), 20, 0, 0])["available"]
    assert not infer([100, 20, 0, 0])["available"]

def test_trained_artifact_is_explicitly_experimental():
    assert PATH.exists()
    result = infer([0, 5, 0, 0])
    assert result["available"]
    assert result["training_data"] == "synthetic"
    assert infer([40, 90, 10, 5])["level"] == "HIGH"

def test_weather_failure_is_not_zero_weather(monkeypatch):
    from backend.routers.radar import weather_at
    import httpx
    import pytest
    monkeypatch.setattr(httpx.Client, "get", lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("offline")))
    with pytest.raises(httpx.ConnectError):
        weather_at(19, 72)
