from datetime import datetime
from typing import Annotated, Any, Literal

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
    role: Literal["tourist", "admin"] = "tourist"


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
    start_trip: bool = False
    origin_lat: Latitude
    origin_lng: Longitude
    dest_lat: Latitude
    dest_lng: Longitude
    origin_name: str | None = Field(default=None, max_length=255)
    destination_name: str | None = Field(default=None, max_length=255)
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
    geometry: dict[str, Any] | None = None


class RiskAssessment(BaseModel):
    level: Literal["SAFE", "CAUTION", "HIGH RISK"]
    method: Literal["heuristic_v1"] = "heuristic_v1"
    reasons: list[str]
    limitations: list[str]
    weather_used: bool


class RouteResponse(BaseModel):
    trip_id: int | None = None
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
    status: Literal["active", "acknowledged", "dispatched", "resolved"]
    created_at: datetime
    message: str = "SOS recorded. Responder dispatchh is not confirmed."


class SOSEventsListResponse(BaseModel):
    events: list[SOSResponse]
    total: int


class HazardReportRequest(InputModel):
    name: str = Field(min_length=3, max_length=200)
    hazard_type: str = Field(min_length=3, max_length=50)
    severity: int = Field(ge=1, le=5)
    latitude: Latitude
    longitude: Longitude


class HazardReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    hazard_type: str
    severity: int
    latitude: float
    longitude: float
    source: str | None
    updated_at: datetime | None
    message: str = "Hazard report recorded into spatial database."


class ProfileUpdate(InputModel):
    full_name: str | None = Field(default=None, max_length=255)
    phone_number: str | None = Field(default=None, max_length=50, pattern=r"^$|^\+?[0-9][0-9 ()-]{6,49}$")
    profile_picture_url: str | None = Field(default=None, pattern=r"^/api/v1/profile/avatar/[a-f0-9]{32}$")
    blood_group: Literal["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] | None = None
    emergency_contact: str | None = Field(default=None, max_length=100)
    medical_notes: str | None = Field(default=None, max_length=5000)
    allergies: str | None = Field(default=None, max_length=5000)
    email: EmailStr | None = None

    @field_validator("*", mode="before")
    @classmethod
    def trim_fields(cls, value):
        return value.strip() if isinstance(value, str) else value


class ProfileResponse(ProfileUpdate):
    user_id: int
    email: EmailStr


class AvatarUpload(InputModel):
    image_base64: str = Field(min_length=1, max_length=2796204)


class AdminSOSResponse(InputModel):
    id: int
    tourist_id: str
    latitude: Latitude
    longitude: Longitude
    status: Literal["active", "acknowledged", "dispatched", "resolved"]
    created_at: datetime
    full_name: str | None = None
    phone_number: str | None = None
    blood_group: str | None = None
    emergency_contact: str | None = None
    medical_notes: str | None = None


class SOSStatusUpdate(InputModel):
    status: Literal["active", "acknowledged", "dispatched", "resolved"]


class HazardGeometry(InputModel):
    type: Literal["Polygon"]
    coordinates: list[list[tuple[Longitude, Latitude]]] = Field(min_length=1)

    @field_validator("coordinates")
    @classmethod
    def validate_rings(cls, rings):
        if any(len(ring) < 4 or ring[0] != ring[-1] for ring in rings):
            raise ValueError("Each polygon ring must have at least 4 closed coordinates")
        return rings


class AdminHazardCreate(InputModel):
    name: str = Field(min_length=3, max_length=200)
    hazard_type: str = Field(min_length=3, max_length=50)
    severity: int = Field(ge=1, le=5)
    geometry: HazardGeometry
    source: str = Field(min_length=3, max_length=500)


class AdminHazardResponse(InputModel):
    id: int
    name: str
    hazard_type: str
    severity: int
    source: str | None
    is_active: bool
    # Historic community reports are stored as Point geometries, while rescue
    # command zones are Polygons.  Keep both visible; only creation accepts a
    # validated Polygon (AdminHazardCreate above).
    geometry: dict[str, Any]
    updated_at: datetime | None


class GeofenceHazard(BaseModel):
    hazard_id: int
    name: str
    hazard_type: str
    severity: int


class HazardEntry(GeofenceHazard):
    trip_id: int
    tourist_id: str
    latitude: Latitude
    longitude: Longitude
    detected_at: datetime
    kind: Literal["hazard_entry"]


class TripLocationResponse(BaseModel):
    trip_id: int
    recorded_at: datetime
    current_hazards: list[GeofenceHazard]
    alerts: list[HazardEntry]
