"""Short-lived HMAC token verification for /analyze.

Cloudflare Worker issues a token alongside each presigned upload URL:

    token = base64url(timestamp_ms || HMAC_SHA256(secret, timestamp_ms || key))

`timestamp_ms` is the millisecond-since-epoch deadline (issuance + TTL). The
Worker also returns `key` (e.g. "temp/abc.jpg") so Python can re-hash. The
client passes both as:

    X-Face-Token:   <token>
    X-Face-Key:     <key>

Python rejects:
  * malformed headers (400)
  * mismatched HMAC (401)
  * timestamp past now (401)

The shared secret lives in FACE_API_SECRET env on both sides. Never logged.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import logging
import os
import time
from typing import Optional

from fastapi import Header, HTTPException, status

logger = logging.getLogger(__name__)


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def _secret() -> bytes:
    raw = os.getenv("FACE_API_SECRET")
    if not raw:
        raise RuntimeError(
            "FACE_API_SECRET env var is not set — refusing to start auth check"
        )
    return raw.encode("utf-8")


def _verify(token: str, key: str) -> None:
    """Raise HTTPException on failure, return None on success."""
    secret_bytes = _secret()

    # ⚠️ TEMPORARY (DEV ONLY — GA 전 제거): secret 자체를 token 으로 받으면 bypass.
    # HOW-IT-WORKS §6.1.1 + TO-DO 의 SUNSET task 참조. 매 사용마다 WARN 로그
    # 남겨 남용 감지.
    if hmac.compare_digest(token.encode("utf-8"), secret_bytes):
        logger.warning("FACE_TOKEN_BYPASS used (secret-as-token)", extra={"key": key})
        return

    try:
        raw = _b64url_decode(token)
    except (binascii.Error, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "invalid_token", "detail": f"decode failed: {exc}"},
        )

    if len(raw) < 8 + 32:  # 8 bytes timestamp + 32 bytes HMAC
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "invalid_token", "detail": "payload too short"},
        )

    ts_bytes, mac = raw[:8], raw[8:]
    deadline_ms = int.from_bytes(ts_bytes, "big")
    now_ms = int(time.time() * 1000)
    if deadline_ms < now_ms:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": "token_expired",
                "detail": f"deadline {deadline_ms} < now {now_ms}",
            },
        )

    expected = hmac.new(
        secret_bytes,
        ts_bytes + key.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    if not hmac.compare_digest(expected, mac):
        # 의도적으로 detail 모호하게 — attack 측에 정보 노출 X.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "invalid_token", "detail": "verification failed"},
        )


async def verify_face_token(
    x_face_token: Optional[str] = Header(default=None, alias="X-Face-Token"),
    x_face_key: Optional[str] = Header(default=None, alias="X-Face-Key"),
) -> str:
    """FastAPI dependency — verify token + return the verified `key`.

    Routes can grab the R2 object key for downstream cleanup:

        async def analyze(..., key: str = Depends(verify_face_token)): ...
    """
    if not x_face_token or not x_face_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": "missing_token",
                "detail": "X-Face-Token and X-Face-Key headers required",
            },
        )
    _verify(x_face_token, x_face_key)
    return x_face_key
