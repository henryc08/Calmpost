"""Settings loaded from the environment (.env in development)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = ""
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    app_api_key: str = "dev-change-me"
    cors_origins: str = "*"

    # How long a cached Gemini answer stays usable when the bin has not moved.
    advice_ttl_seconds: int = 900

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
