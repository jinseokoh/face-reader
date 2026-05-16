"""Async, streaming, size-guarded image download.

Streams chunks to a NamedTemporaryFile so large/malicious bodies never live in
memory all at once. Caller is responsible for unlinking the file when done.
"""
from __future__ import annotations

import logging
import os
import tempfile
from dataclasses import dataclass

import httpx

from app.utils.config import get_settings

logger = logging.getLogger(__name__)


class DownloadError(Exception):
    """Raised when the remote URL cannot be turned into a usable image file."""

    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


@dataclass
class DownloadedImage:
    path: str
    content_type: str
    size: int


async def download_image(url: str) -> DownloadedImage:
    """Stream the remote image to a temp file. Returns its path.

    Raises DownloadError with an HTTP status code suitable for re-raising at
    the API layer (400 for client-blame, 502 for upstream-blame).
    """
    settings = get_settings()
    max_bytes = settings.max_download_mb * 1024 * 1024
    timeout = httpx.Timeout(settings.download_timeout_sec, connect=5.0)

    suffix = _suffix_from_url(url)
    tmp = tempfile.NamedTemporaryFile(
        prefix="face-", suffix=suffix, delete=False
    )
    tmp_path = tmp.name
    tmp.close()  # Reopen below for binary write.

    try:
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            async with client.stream("GET", url) as resp:
                if resp.status_code != 200:
                    raise DownloadError(
                        502,
                        f"upstream returned {resp.status_code}",
                    )

                content_type = (resp.headers.get("content-type") or "").lower().split(";")[0].strip()
                if content_type not in settings.allowed_content_types:
                    raise DownloadError(
                        400,
                        f"unsupported content-type: {content_type!r}",
                    )

                # Pre-check Content-Length if the server gave us one.
                declared = resp.headers.get("content-length")
                if declared and declared.isdigit() and int(declared) > max_bytes:
                    raise DownloadError(
                        400,
                        f"image too large: {declared} bytes > {max_bytes}",
                    )

                size = 0
                with open(tmp_path, "wb") as fh:
                    async for chunk in resp.aiter_bytes(chunk_size=64 * 1024):
                        size += len(chunk)
                        if size > max_bytes:
                            raise DownloadError(
                                400,
                                f"image exceeded {max_bytes} bytes mid-stream",
                            )
                        fh.write(chunk)

        logger.info(
            "downloaded image",
            extra={"url": url, "bytes": size, "content_type": content_type},
        )
        return DownloadedImage(path=tmp_path, content_type=content_type, size=size)

    except httpx.HTTPError as exc:
        _safe_unlink(tmp_path)
        raise DownloadError(502, f"download failed: {exc}") from exc
    except DownloadError:
        _safe_unlink(tmp_path)
        raise
    except Exception:
        _safe_unlink(tmp_path)
        raise


def _suffix_from_url(url: str) -> str:
    lower = url.lower().split("?", 1)[0]
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if lower.endswith(ext):
            return ext
    return ".img"


def _safe_unlink(path: str) -> None:
    try:
        os.unlink(path)
    except OSError:
        pass


def cleanup(path: str) -> None:
    """Idempotent unlink — call in a finally block after inference."""
    _safe_unlink(path)
