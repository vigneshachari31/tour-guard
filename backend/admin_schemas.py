"""Validated admin inputs. No role or arbitrary column assignment from clients."""

from typing import Literal

from pydantic import AwareDatetime, EmailStr, Field, model_validator

if __package__:
    from .schemas import InputModel, Latitude, Longitude
else:
    from schemas import InputModel, Latitude, Longitude

IncidentStatus = Literal["OPEN", "IN_PROGRESS", "RESOLVED", "CANCELLED"]


class StatusUpdate(InputModel):
    status: IncidentStatus
    expected_status: IncidentStatus
    note: str = Field(min_length=3, max_length=2000)


class AssignmentInput(InputModel):
    responder_id: int = Field(gt=0)
    note: str = Field(min_length=3, max_length=2000)


class ResponderInput(InputModel):
    id: int | None = Field(default=None, gt=0)
    name: str = Field(min_length=2, max_length=200)
    phone: str = Field(pattern=r"^\+?[0-9][0-9 ()-]{6,49}$")
    email: EmailStr | None = None
    role: str = Field(default="Mountain Rescue", min_length=2, max_length=50)
    status: Literal["available", "unavailable"] = "available"


class Polygon(InputModel):
    type: Literal["Polygon"]
    coordinates: list[list[tuple[Longitude, Latitude]]] = Field(
        min_length=1, max_length=100
    )

    @model_validator(mode="after")
    def closed_rings(self):
        if sum(len(r) for r in self.coordinates) > 10000:
            raise ValueError("Polygon exceeds 10000 vertices")
        for ring in self.coordinates:
            if len(ring) < 4 or ring[0] != ring[-1]:
                raise ValueError(
                    "Each polygon ring requires at least four coordinates and must be closed"
                )
        return self


class HazardInput(InputModel):
    name: str = Field(min_length=3, max_length=200)
    hazard_type: Literal["flood", "landslide", "high_tide", "severe_weather"]
    severity: int = Field(ge=1, le=5)
    source: str = Field(min_length=3, max_length=500)
    geometry: Polygon
    is_active: bool = True
    valid_from: AwareDatetime | None = None
    valid_until: AwareDatetime | None = None

    @model_validator(mode="after")
    def dates(self):
        if self.valid_from and self.valid_until and self.valid_until <= self.valid_from:
            raise ValueError("Valid until must be after valid from")
        return self


class HazardPatch(InputModel):
    name: str | None = Field(default=None, min_length=3, max_length=200)
    hazard_type: Literal["flood", "landslide", "high_tide", "severe_weather"] | None = (
        None
    )
    severity: int | None = Field(default=None, ge=1, le=5)
    source: str | None = Field(default=None, min_length=3, max_length=500)
    geometry: Polygon | None = None
    is_active: bool | None = None
    valid_from: AwareDatetime | None = None
    valid_until: AwareDatetime | None = None


class ActivationInput(InputModel):
    is_active: bool


class LocationInput(InputModel):
    latitude: Latitude
    longitude: Longitude
