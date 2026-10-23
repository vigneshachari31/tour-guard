# Experimental risk radar

Run: python -m backend.ml_model.radar_model

Model: one hidden layer (24 ReLU units), softmax loss trained with minibatch
gradient descent. Features: hourly precipitation, wind speed, hazard count
within 1 km, maximum hazard severity. Seed 42, 7,200 training examples and
1,800 untouched test examples. Metrics, confusion matrix and majority baseline
are saved alongside weights in radar_model.json.

All examples and targets are synthetic. Targets reproduce fixed weather/hazard
thresholds. Test scores measure imitation of these rules, NOT prediction of
real incidents. No calibrated probabilities or disaster forecasts are exposed.
This model must not replace verified hazard warnings or official advice.

Runtime weather comes from https://open-meteo.com/en/docs (hourly forecast).
Official active zones and verified tourist reports are queried through PostGIS.
Pending/rejected reports are excluded. Missing weather and inputs beyond the
training range cause abstention. No slope, crowd or visibility is fabricated.
Radar is location-based; the existing route assessment remains rule-based.

To establish real predictive value, collect licensed event-labelled observations
with event times, geography, weather and hazard features available before the
outcome. Define prediction horizon and outcomes, split by time/geography,
evaluate class recall and calibration, then independently validate deployment
coverage. The synthetic benchmark is not a substitute for this work.
