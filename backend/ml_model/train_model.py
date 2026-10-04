"""
train_model.py
--------------
Builds a lightweight, pure-NumPy risk model:
  - Generates 8 000 synthetic samples with domain-realistic rules
  - Trains a simple Gradient-Weighted Scoring ensemble
  - Saves the learned thresholds + weights as model_weights.json
    (no C compiler / scikit-learn required)

Features
--------
  rainfall_mm_h   : 0-150   rainfall intensity
  slope_degrees   : 0-60    terrain steepness
  elevation_m     : 0-2800  altitude
  wind_kmh        : 0-120   wind speed
  visibility_km   : 0-10    visibility (10 = perfect)
  tourist_density : 0-1     crowd level

Target
------
  risk_level: 0=Low  1=Medium  2=High  3=Critical
"""

import os
import json
import numpy as np

SEED = 42
N    = 8_000
np.random.seed(SEED)

# ── 1. Synthetic dataset ──────────────────────────────────────────────────────
rainfall        = np.random.exponential(15,   N).clip(0, 150)
slope           = np.random.uniform(0, 60,    N)
elevation       = np.random.uniform(0, 2800,  N)
wind            = np.random.uniform(0, 120,   N)
visibility      = np.random.uniform(0, 10,    N)
tourist_density = np.random.uniform(0, 1,     N)

# Raw risk score (domain rules)
risk_raw = (
    rainfall        * 0.35 +
    slope           * 0.25 +
    (elevation / 28)* 0.10 +   # normalised to 0-100
    wind            * 0.15 +
    (10 - visibility) * 10 * 0.10 +
    tourist_density * 100  * 0.05
)
risk_raw += np.random.normal(0, 5, N)   # noise

# Labels
def score_to_level(s):
    if s < 20:  return 0
    if s < 45:  return 1
    if s < 70:  return 2
    return 3

labels = np.array([score_to_level(s) for s in risk_raw])

print(f"Samples: {N}")
for i, name in enumerate(["Low", "Medium", "High", "Critical"]):
    print(f"  {name:8s}: {(labels == i).sum()}")

# ── 2. Learn optimal feature weights via least-squares ───────────────────────
# Normalise each feature to 0-1 range
feat_min = np.array([0,   0,  0,   0,  0, 0])
feat_max = np.array([150, 60, 2800, 120, 10, 1])

X = np.column_stack([rainfall, slope, elevation, wind, visibility, tourist_density])
X_norm = (X - feat_min) / (feat_max - feat_min)

# Target: continuous 0-3
y_cont = labels.astype(float)

# Least-squares fit: find weights w such that X_norm @ w ≈ y_cont
w, *_ = np.linalg.lstsq(
    np.column_stack([X_norm, np.ones(N)]),  # add bias column
    y_cont,
    rcond=None,
)

weights      = w[:-1].tolist()
bias         = float(w[-1])
feat_names   = ["rainfall_mm_h", "slope_degrees", "elevation_m",
                "wind_kmh", "visibility_km", "tourist_density"]

# Invert visibility (high visibility = safer)
# Already handled by raw score; recalculate sign check
print("\nLearned feature weights:")
for name, wi in zip(feat_names, weights):
    print(f"  {name:20s}: {wi:+.4f}")
print(f"  {'bias':20s}: {bias:+.4f}")

# ── 3. Calibrate thresholds (percentile-based) ───────────────────────────────
X_norm_bias = np.column_stack([X_norm, np.ones(N)])
scores = X_norm_bias @ w

# Find thresholds separating Low/Medium/High/Critical by optimising accuracy
best_acc  = 0
best_thr  = [0.7, 1.5, 2.3]

for t1 in np.arange(0.4, 1.2, 0.05):
    for t2 in np.arange(1.1, 2.0, 0.05):
        for t3 in np.arange(1.9, 2.8, 0.05):
            if not (t1 < t2 < t3):
                continue
            pred = np.where(scores < t1, 0,
                   np.where(scores < t2, 1,
                   np.where(scores < t3, 2, 3)))
            acc = (pred == labels).mean()
            if acc > best_acc:
                best_acc = acc
                best_thr = [float(t1), float(t2), float(t3)]

print(f"\nBest thresholds: {best_thr}  (accuracy={best_acc:.3f})")

# ── 4. Save model ─────────────────────────────────────────────────────────────
model_data = {
    "feature_names": feat_names,
    "feat_min":      feat_min.tolist(),
    "feat_max":      feat_max.tolist(),
    "weights":       weights,
    "bias":          bias,
    "thresholds":    best_thr,
    "accuracy":      round(best_acc, 4),
}

out_path = os.path.join(os.path.dirname(__file__) or ".", "model_weights.json")
with open(out_path, "w") as f:
    json.dump(model_data, f, indent=2)

print(f"\nModel saved -> {out_path}")
