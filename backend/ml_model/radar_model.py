"""Small neural classifier. Synthetic training is a demonstration, not validation."""
import json
from pathlib import Path
import numpy as np

PATH = Path(__file__).with_name("radar_model.json")
FEATURES = ["rainfall_mm_h", "wind_kmh", "hazard_count", "max_severity"]
SCALE = np.array([60., 120., 20., 5.])
LABELS = ["LOW", "MODERATE", "HIGH"]

def infer(values):
    x = np.asarray(values, dtype=float)
    if x.shape != (4,) or not np.isfinite(x).all() or (x < 0).any() or (x > SCALE).any():
        return {"available": False, "reason": "Inputs outside the model training range"}
    if not PATH.exists():
        return {"available": False, "reason": "Model artifact unavailable"}
    model = json.loads(PATH.read_text())
    hidden = np.maximum(0, x / SCALE @ np.array(model["w1"]) + np.array(model["b1"]))
    logits = hidden @ np.array(model["w2"]) + np.array(model["b2"])
    return {"available": True, "level": LABELS[int(logits.argmax())],
            "version": model["version"], "training_data": "synthetic",
            "validation": "Demonstration only; not validated on real incidents"}

def train():
    rng = np.random.default_rng(42)
    x = rng.uniform(size=(9000, 4))
    x[:, 2] = rng.integers(0, 21, len(x)) / 20
    x[:, 3] = rng.integers(1, 6, len(x)) / 5
    # Include hazard-free scenarios, including bad weather.
    empty = rng.random(len(x)) < .35
    x[empty, 2:] = 0
    y = np.where((x[:,0]*60 >= 30) | (x[:,1]*120 >= 70) | (x[:,3]*5 >= 4), 2,
                 np.where((x[:,0]*60 >= 10) | (x[:,1]*120 >= 40) | (x[:,2] > 0), 1, 0))
    order = rng.permutation(len(x))
    train_ids, test_ids = order[:7200], order[7200:]
    xt, yt = x[train_ids], np.eye(3)[y[train_ids]]
    w1 = rng.normal(0, .4, (4, 24)); b1 = np.zeros(24)
    w2 = rng.normal(0, .2, (24, 3)); b2 = np.zeros(3)
    for step in range(3000):
        ids = rng.choice(len(xt), 256, replace=False)
        batch = xt[ids]
        h = np.maximum(0, batch @ w1 + b1)
        z = h @ w2 + b2
        probs = np.exp(z-z.max(axis=1, keepdims=True))
        probs /= probs.sum(axis=1, keepdims=True)
        dz = (probs - yt[ids]) / len(ids)
        dh = (dz @ w2.T) * (h > 0)
        w2 -= .15 * (h.T @ dz); b2 -= .15 * dz.sum(axis=0)
        w1 -= .15 * (batch.T @ dh); b1 -= .15 * dh.sum(axis=0)
    predicted = (np.maximum(0, x[test_ids] @ w1 + b1) @ w2 + b2).argmax(axis=1)
    matrix = np.zeros((3,3), dtype=int)
    for actual, guess in zip(y[test_ids], predicted):
        matrix[actual,guess] += 1
    metrics = {"held_out_samples": len(test_ids), "accuracy": float((predicted==y[test_ids]).mean()),
               "confusion_matrix": matrix.tolist(),
               "class_recall": (matrix.diagonal()/np.maximum(matrix.sum(axis=1),1)).tolist(),
               "majority_baseline_accuracy": float(np.bincount(y[test_ids]).max()/len(test_ids)),
               "warning": "Synthetic rule imitation only; no real-world predictive accuracy established."}
    model = {"version": "synthetic_mlp_v1", "features": FEATURES, "seed": 42,
             "w1": w1.tolist(), "b1": b1.tolist(), "w2": w2.tolist(), "b2": b2.tolist(),
             "metrics": metrics}
    PATH.write_text(json.dumps(model, indent=2))
    print(json.dumps(metrics, indent=2))

if __name__ == "__main__":
    train()
