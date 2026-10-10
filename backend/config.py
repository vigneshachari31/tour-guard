from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).with_name(".env"), extra="ignore"
    )
    database_url: str = "postgresql://postgres:YOUR_PASSWORD@localhost:5432/tour_guard"
    jwt_secret: SecretStr = Field(min_length=32)
    jwt_issuer: str = "tour-guard"
    jwt_audience: str = "tour-guard-app"
    access_token_minutes: int = Field(default=30, ge=1, le=1440)
    osrm_base_url: str = "https://router.project-osrm.org"
    http_timeout_seconds: float = Field(default=15, gt=0, le=60)
    route_buffer_meters: float = Field(default=250, ge=0, le=5000)
    cors_origins: list[str] = []
    # Opt in only for local Flutter development (random browser ports).
    cors_allow_localhost: bool = False
    # Set only after loading and verifying coverage for the deployment region.
    hazard_coverage_verified: bool = False

    @field_validator("jwt_secret")
    @classmethod
    def reject_placeholder(cls, value: SecretStr) -> SecretStr:
        if "CHANGE_ME" in value.get_secret_value():
            raise ValueError("Generate a random JWT_SECRET before starting the API")
        return value

    @field_validator("osrm_base_url")
    @classmethod
    def validate_osrm_url(cls, value: str) -> str:
        if not value.startswith(("https://", "http://")):
            raise ValueError("OSRM_BASE_URL must be an HTTP(S) URL")
        return value.rstrip("/")


@lru_cache
def get_settings() -> Settings:
    return Settings()
