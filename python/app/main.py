"""FastAPI entry point — /health and /analyze.

Wires up:
  * JSON structured logging
  * Startup model warm-up
  * Global exception middleware → consistent ErrorResponse shape
  * httpx-streamed download → DeepFace inference
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse

from app.schemas import AnalyzeRequest, AnalyzeResponse, ErrorResponse
from app.services.deleter import delete_temp_object
from app.services.downloader import DownloadError, cleanup, download_image
from app.services.inference import NoFaceError, analyze_image, warm_up
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
        "CPU-only DeepFace service. POST an image URL, get back age / gender "
        "/ ethnicity. Images are streamed from the supplied URL — never uploaded."
    ),
    version="0.1.0",
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


@app.post(
    "/analyze",
    response_model=AnalyzeResponse,
    responses={
        400: {"model": ErrorResponse},
        401: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
        502: {"model": ErrorResponse},
    },
    tags=["inference"],
)
async def analyze(
    req: AnalyzeRequest,
    key: str = Depends(verify_face_token),
) -> AnalyzeResponse:
    """Analyze + immediately DELETE temp/{uuid}.jpg from R2.

    `key` is the verified R2 object key from `X-Face-Key` (e.g.
    "temp/abc.jpg"). After successful analysis (or no-face) we fire-and-forget
    the DELETE — failure is logged only, with the 1-day R2 lifecycle as safety net.
    """
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
        result = await analyze_image(image.path)
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
    return JSONResponse(status_code=exc.status_code, content=body)
