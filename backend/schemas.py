from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

Latitude = Annotated[float, Field(ge=-90, le=90, allow_inf_nan=False)]
Longitude = Annotated[float, Field(ge=-180, le=180, allow_inf_nan=False)]


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class LoginRequest(InputModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.lower()


class RegisterRequest(LoginRequest):
    full_name: str | None = Field(default=None, min_length=1, max_length=255)

    @field_validator("full_name", "emergency_contact_phone", mode="before")
    @classmethod
    def trim_contact_fields(cls, value):
        return value.strip() if isinstance(value, str) else value

    password: str = Field(min_length=12, max_length=128)
    emergency_contact_phone: str | None = Field(
        default=None, pattern=r"^\+?[0-9][0-9 ()-]{6,24}$"
    )


class TokenResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    tourist_id: str


class WeatherObservation(InputModel):
    rainfall_mm_h: float = Field(ge=0, le=500)
    wind_kmh: float = Field(ge=0, le=500)
    observed_at: datetime
    source: str = Field(min_length=1, max_length=200)

    @field_validator("observed_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("observed_at must include a timezone")
        return value


class RouteRequest(InputModel):
    origin_lat: Latitude
    origin_lng: Longitude
    dest_lat: Latitude
    dest_lng: Longitude
    weather: WeatherObservation | None = None


class RouteGeometry(InputModel):
    type: Literal["LineString"]
    coordinates: list[tuple[Longitude, Latitude]] = Field(
        min_length=2, max_length=100000
    )


class HazardSummary(BaseModel):
    id: int
    name: str
    hazard_type: str
    severity: int
    source: str


class RiskAssessment(BaseModel):
    level: Literal["SAFE", "CAUTION", "HIGH RISK"]
    method: Literal["heuristic_v1"] = "heuristic_v1"
    reasons: list[str]
    limitations: list[str]
    weather_used: bool


class RouteResponse(BaseModel):
    geometry: RouteGeometry
    distance_meters: float
    duration_seconds: float
    buffer_meters: float
    hazards: list[HazardSummary]
    assessment: RiskAssessment


class SOSRequest(InputModel):
    tourist_id: str = Field(pattern=r"^TG-[A-F0-9]{8,32}$")
    latitude: Latitude
    longitude: Longitude


class SOSResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    tourist_id: str
    latitude: float
    longitude: float
    status: Literal["active", "resolved"]
    created_at: datetime
    message: str = "SOS recorded. Responder dispatch is not confirmed."
