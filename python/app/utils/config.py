from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Env-driven runtime config.

    Override any field via env var with the same name (case-insensitive).
    Example: MAX_DOWNLOAD_MB=20 docker compose up
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Image download
    download_timeout_sec: float = 15.0
    max_download_mb: int = 10
    allowed_content_types: tuple[str, ...] = (
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
    )

    # DeepFace
    detector_backend: str = "opencv"

    # Logging
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
