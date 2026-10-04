"""
routers/risk.py
---------------
POST /api/predict-risk
  → Takes environmental sensor data, returns AI risk prediction.
"""

from fastapi import APIRouter
from pydantic import BaseModel, Field
from ml_model.risk_predictor import predict_risk

router = APIRouter(prefix="/api", tags=["Risk Prediction"])


class RiskRequest(BaseModel):
    rainfall_mm_h:   float = Field(..., ge=0, le=200,  description="Rainfall in mm/hour")
    slope_degrees:   float = Field(..., ge=0, le=90,   description="Terrain slope in degrees")
    elevation_m:     float = Field(..., ge=0, le=8848, description="Elevation in metres")
    wind_kmh:        float = Field(..., ge=0, le=200,  description="Wind speed in km/h")
    visibility_km:   float = Field(8.0, ge=0, le=10,  description="Visibility in km")
    tourist_density: float = Field(0.3, ge=0, le=1,   description="Relative tourist density 0-1")
    # Optional location context (not used by model, stored for logging)
    latitude:  float | None = None
    longitude: float | None = None
    location:  str   | None = None


class RiskResponse(BaseModel):
    risk_level:    int
    risk_label:    str
    risk_score:    int
    color:         str
    probabilities: list[float]
    advice:        str


@router.post("/predict-risk", response_model=RiskResponse)
def predict_risk_endpoint(req: RiskRequest):
    """
    Run AI risk prediction for the given environmental conditions.
    Returns risk level (0=Low … 3=Critical), a 0-100 score, and safety advice.
    """
    result = predict_risk(
        rainfall_mm_h   = req.rainfall_mm_h,
        slope_degrees   = req.slope_degrees,
        elevation_m     = req.elevation_m,
        wind_kmh        = req.wind_kmh,
        visibility_km   = req.visibility_km,
        tourist_density = req.tourist_density,
    )
    return RiskResponse(**result)

