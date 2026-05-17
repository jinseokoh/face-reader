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

    # R2 — Worker 와 동일 토큰 공유 (HOW-IT-WORKS §6.2). `/analyze` 후 temp/
    # 즉시 DELETE 용. 미설정 시 deleter 가 fail-soft (로그만 + skip).
    r2_account_id: str = ""
    r2_bucket_name: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""

    # Logging
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
