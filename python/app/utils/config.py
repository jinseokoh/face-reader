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

    # 업로드 본문 상한 (multipart image). 384px 얼굴 크롭은 20~35KB 다.
    max_upload_mb: int = 1

    # DeepFace — 인종 + (전체 사진일 때) 얼굴 검출
    detector_backend: str = "opencv"

    # MiVOLO v2 — 나이·성별. HF 리비전 고정 (원격 코드가 함께 온다).
    mivolo_model_id: str = "iitolstykh/mivolo_v2"
    mivolo_revision: str = "53393526c220e34cdd7b722b36d22b6f9e5f4241"
    # 전체 사진에서 검출 박스를 사방 이 비율만큼 넓혀 정사각 크롭 → MiVOLO.
    # 앱·웹이 보내는 크롭 규격과 같아야 한다 (tools/face_shape_ml/eval_mivolo_crop_margin.py 로 정함).
    crop_margin: float = 0.2

    # 백프레셔 — 추론 1건이 이미 8코어 중 6개를 점유해서(실측 ~630% CPU) 동시
    # 실행은 총 처리량을 못 올리고 대기시간만 선형으로 늘린다: 동시 16 이면
    # 처리량은 그대로 0.7 req/s 인데 p95 가 34초. 상한 초과분은 큐에 쌓지 않고
    # 503 으로 즉시 거절한다 — 34초 침묵보다 빠른 실패가 낫다.
    max_concurrent_analyses: int = 4
    busy_retry_after_sec: int = 5

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
