"""
risk_predictor.py
-----------------
Loads model_weights.json (produced by train_model.py) and exposes
predict_risk() — pure Python + NumPy, no scikit-learn required.
"""

import os
import json
import numpy as np
from functools import lru_cache

MODEL_PATH = os.path.join(os.path.dirname(__file__), "model_weights.json")

RISK_LABELS = {0: "Low", 1: "Medium", 2: "High", 3: "Critical"}
RISK_COLORS = {0: "#22C55E", 1: "#F59E0B", 2: "#EF4444", 3: "#7C3AED"}

ADVICE = {
    0: "Conditions are safe. Enjoy your trip!",
    1: "Moderate risk. Stay alert and follow local guidelines.",
    2: "High risk detected. Avoid exposed ridges and check weather updates.",
    3: "CRITICAL: Immediate danger. Seek shelter and contact emergency services.",
}


@lru_cache(maxsize=1)
def _load_model() -> dict:
    """Load model weights once, cache in memory."""
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(
            f"model_weights.json not found at {MODEL_PATH}. "
            "Run `python ml_model/train_model.py` first."
        )
    with open(MODEL_PATH) as f:
        return json.load(f)


def predict_risk(
    rainfall_mm_h:   float,
    slope_degrees:   float,
    elevation_m:     float,
    wind_kmh:        float,
    visibility_km:   float = 8.0,
    tourist_density: float = 0.3,
) -> dict:
    """
    Predict travel risk for the given environmental conditions.

    Returns
    -------
    dict with keys:
      risk_level   : int  0-3
      risk_label   : str  Low / Medium / High / Critical
      risk_score   : int  0-100  (UI progress bar)
      color        : str  hex colour
      probabilities: list[float] soft class probs (4 values)
      advice       : str  short safety tip
    """
    m = _load_model()

    feat_min = np.array(m["feat_min"])
    feat_max = np.array(m["feat_max"])
    weights  = np.array(m["weights"])
    bias     = m["bias"]
    thr      = m["thresholds"]  # [t1, t2, t3]

    # Normalise input
    x = np.array([rainfall_mm_h, slope_degrees, elevation_m,
                  wind_kmh, visibility_km, tourist_density], dtype=float)
    x_norm = np.clip((x - feat_min) / (feat_max - feat_min), 0, 1)

    # Linear score
    score = float(x_norm @ weights + bias)

    # Classify
    if   score < thr[0]: level = 0
    elif score < thr[1]: level = 1
    elif score < thr[2]: level = 2
    else:                level = 3

    # Soft probabilities via distance-to-threshold sigmoid
    def _sigmoid(v): return 1 / (1 + np.exp(-v * 4))

    raw_probs = np.array([
        1 - _sigmoid(score - thr[0]),
        _sigmoid(score - thr[0]) * (1 - _sigmoid(score - thr[1])),
        _sigmoid(score - thr[1]) * (1 - _sigmoid(score - thr[2])),
        _sigmoid(score - thr[2]),
    ])
    probs = (raw_probs / raw_probs.sum()).tolist()

    # 0-100 risk score
    risk_score = int(round(min(max(score / thr[2], 0), 1.33) * 75))
    risk_score = min(risk_score, 100)

    return {
        "risk_level":    level,
        "risk_label":    RISK_LABELS[level],
        "risk_score":    risk_score,
        "color":         RISK_COLORS[level],
        "probabilities": probs,
        "advice":        ADVICE[level],
    }
