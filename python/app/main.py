"""FastAPI entry point — /health and /analyze.

Wires up:
  * JSON structured logging
  * Startup model warm-up
  * Global exception middleware → consistent ErrorResponse shape
  * multipart 업로드(얼굴 크롭) 또는 image_url 다운로드 → MiVOLO + DeepFace 추론
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.schemas import AnalyzeRequest, AnalyzeResponse, ErrorResponse
from app.services.deleter import delete_temp_object
from app.services.downloader import DownloadError, cleanup, download_image
from app.services.inference import NoFaceError, analyze_image, decode_image, warm_up
from app.utils.auth import verify_face_token
from app.utils.config import get_settings
from app.utils.logging_config import configure_logging

configure_logging()
logger = logging.getLogger("face.api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logger.info(
        "starting face metadata service",
        extra={
            "host": settings.host,
            "port": settings.port,
            "detector": settings.detector_backend,
        },
    )
    await warm_up()
    yield
    logger.info("face metadata service shutting down")


app = FastAPI(
    title="Face Metadata Inference",
    description=(
        "CPU-only face metadata service. POST a face crop (multipart) or an "
        "image URL, get back age / gender / ethnicity. Age·gender = MiVOLO v2, "
        "ethnicity = DeepFace race head."
    ),
    version="0.2.0",
    lifespan=lifespan,
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Last-resort handler so callers never see a raw stack-trace body."""
    logger.exception("unhandled exception", extra={"path": request.url.path})
    return JSONResponse(
        status_code=500,
        content=ErrorResponse(
            error="internal_error",
            detail="unexpected server error",
        ).model_dump(),
    )


@app.get("/health", tags=["meta"])
async def health() -> dict[str, str]:
    """Liveness check — does not exercise the model."""
    return {"status": "ok"}


# 진행 중인 /analyze 개수. asyncio 단일 스레드라 아래 검사~증가 사이에 await 가
# 없으면 원자적 — 별도 락 불필요.
_inflight = 0


@app.post(
    "/analyze",
    response_model=AnalyzeResponse,
    responses={
        400: {"model": ErrorResponse},
        401: {"model": ErrorResponse},
        413: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
        502: {"model": ErrorResponse},
        503: {"model": ErrorResponse},
    },
    tags=["inference"],
)
async def analyze(
    request: Request,
    key: str = Depends(verify_face_token),
) -> AnalyzeResponse:
    """두 입력 형태를 받는다. 인증은 둘 다 X-Face-Token/X-Face-Key (워커가 발급).

    * multipart/form-data — `image`(JPEG/PNG/WebP bytes), `face_crop`("1"|"0",
      기본 "1"). 워커가 앱·웹의 업로드를 그대로 중계한다. key 는 워커가 정한
      요청 id (`upload/{uuid}`) 라 R2 정리가 없다.
    * application/json — `{image_url}` (옛 앱 계약). key 는 R2 temp 키이고
      분석 뒤 즉시 DELETE 한다 (1일 lifecycle 이 백업). 스토어의 옛 앱이 전부
      갱신되면 이 경로를 지운다.

    동시 처리 상한(`MAX_CONCURRENT_ANALYSES`)을 넘으면 대기시키지 않고 503 을
    돌려준다 — 호출자가 재시도 시점을 정할 수 있게 `Retry-After` 동봉.
    """
    global _inflight
    settings = get_settings()
    if _inflight >= settings.max_concurrent_analyses:
        logger.warning("analyze rejected (busy)", extra={"inflight": _inflight})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "busy",
                "detail": (
                    f"server at capacity ({settings.max_concurrent_analyses} "
                    "concurrent analyses); retry shortly"
                ),
            },
            headers={"Retry-After": str(settings.busy_retry_after_sec)},
        )
    _inflight += 1
    try:
        ctype = request.headers.get("content-type", "")
        if ctype.startswith("multipart/form-data"):
            return await _analyze_upload(request, key)
        return await _analyze_url(request, key)
    finally:
        _inflight -= 1


async def _analyze_upload(request: Request, key: str) -> AnalyzeResponse:
    settings = get_settings()
    max_bytes = settings.max_upload_mb * 1024 * 1024
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"error": "upload_too_large", "detail": f"max {settings.max_upload_mb}MB"},
        )
    form = await request.form()
    upload = form.get("image")
    if upload is None or not hasattr(upload, "read"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "bad_request", "detail": "multipart field 'image' required"},
        )
    data = await upload.read()
    if len(data) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"error": "upload_too_large", "detail": f"max {settings.max_upload_mb}MB"},
        )
    face_crop = str(form.get("face_crop", "1")).strip().lower() not in ("0", "false", "no")
    logger.info("analyze upload", extra={"key": key, "bytes": len(data), "face_crop": face_crop})
    try:
        img = decode_image(data)
        result = await analyze_image(img, face_crop=face_crop)
    except NoFaceError as exc:
        logger.info("no face detected", extra={"key": key, "reason": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "error": "no_face_detected",
                "detail": "No face could be detected in the supplied image.",
            },
        )
    logger.info("analyze ok", extra={"key": key, **result})
    return AnalyzeResponse(**result)


async def _analyze_url(request: Request, key: str) -> AnalyzeResponse:
    try:
        req = AnalyzeRequest.model_validate(await request.json())
    except (ValueError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "bad_request", "detail": f"invalid JSON body: {exc}"},
        )
    url = str(req.image_url)
    logger.info("analyze request", extra={"image_url": url, "key": key})

    try:
        image = await download_image(url)
    except DownloadError as exc:
        logger.warning(
            "download rejected",
            extra={"image_url": url, "status": exc.status, "reason": exc.message},
        )
        raise HTTPException(
            status_code=exc.status,
            detail={"error": "download_failed", "detail": exc.message},
        )

    try:
        with open(image.path, "rb") as fh:
            img = decode_image(fh.read())
        # 옛 앱은 720px 전체 사진을 보낸다 — 검출부터.
        result = await analyze_image(img, face_crop=False)
    except NoFaceError as exc:
        logger.info("no face detected", extra={"image_url": url, "reason": str(exc)})
        # 분석 실패해도 R2 객체는 정리. lifecycle 룰이 백업이긴 하나 즉시 삭제 선호.
        await delete_temp_object(key)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "error": "no_face_detected",
                "detail": "No face could be detected in the supplied image.",
            },
        )
    finally:
        cleanup(image.path)

    # 성공 케이스도 동일하게 즉시 정리. delete_temp_object 는 never-raises.
    await delete_temp_object(key)

    logger.info("analyze ok", extra={"image_url": url, "key": key, **result})
    return AnalyzeResponse(**result)


@app.exception_handler(HTTPException)
async def http_exception_to_error_response(
    request: Request, exc: HTTPException
) -> JSONResponse:
    """Normalise HTTPException payloads to the ErrorResponse schema."""
    detail = exc.detail
    if isinstance(detail, dict) and "error" in detail:
        body = ErrorResponse(**detail).model_dump()
    else:
        body = ErrorResponse(error="http_error", detail=str(detail)).model_dump()
    # headers 를 그대로 넘긴다 — 503 의 Retry-After 가 여기서 유실되면 안 된다.
    return JSONResponse(status_code=exc.status_code, content=body, headers=exc.headers)
