"""R2 object DELETE via hand-rolled SigV4 (no boto/aioboto deps).

HOW-IT-WORKS §3.1 / §5.1 / §6.2:
    `/analyze` 가 성공하면 호출자(main.py) 가 fire-and-forget 으로 본 모듈의
    `delete_temp_object(key)` 를 await 한다. 실패해도 응답엔 영향 X — 1일
    R2 lifecycle 룰이 최종 안전망.

권한:
    Worker 와 동일한 R2 토큰 (Object Read & Write on bucket=facely). dashboard
    UI 가 DELETE-only tier 를 지원하지 않아 한 토큰 공유 (HOW-IT-WORKS §6.2).
"""
from __future__ import annotations

import datetime as _dt
import hashlib
import hmac
import logging

import httpx

from app.utils.config import get_settings

logger = logging.getLogger(__name__)

_SERVICE = "s3"
_REGION = "auto"
_ALGO = "AWS4-HMAC-SHA256"
_EMPTY_SHA256 = (
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
)


async def delete_temp_object(key: str) -> None:
    """Best-effort DELETE on `{bucket}/{key}`. Never raises.

    Caller passes the R2 key already verified from `X-Face-Key` (e.g.
    "temp/abc.jpg"). Empty/non-temp keys are skipped.
    """
    if not key or not key.startswith("temp/"):
        # 의도적 안전망: temp/ prefix 만 정리. 다른 prefix 면 drop.
        logger.warning("r2 delete skipped (not temp/)", extra={"key": key})
        return

    s = get_settings()
    if not (s.r2_account_id and s.r2_bucket_name
            and s.r2_access_key_id and s.r2_secret_access_key):
        logger.warning("r2 delete skipped (R2 env not configured)", extra={"key": key})
        return

    host = f"{s.r2_account_id}.r2.cloudflarestorage.com"
    uri = f"/{s.r2_bucket_name}/{key}"
    url = f"https://{host}{uri}"

    now = _dt.datetime.now(_dt.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")

    headers = {
        "host": host,
        "x-amz-content-sha256": _EMPTY_SHA256,
        "x-amz-date": amz_date,
    }

    auth = _build_authorization(
        method="DELETE",
        uri=uri,
        query="",
        headers=headers,
        payload_hash=_EMPTY_SHA256,
        access_key=s.r2_access_key_id,
        secret_key=s.r2_secret_access_key,
        date_stamp=date_stamp,
        amz_date=amz_date,
    )
    headers["authorization"] = auth

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            res = await client.delete(url, headers=headers)
        # R2 returns 204 on success, 404 if object missing (counts as success
        # for our cleanup intent).
        if 200 <= res.status_code < 300 or res.status_code == 404:
            logger.info("r2 delete ok", extra={"key": key, "status": res.status_code})
            return
        logger.warning(
            "r2 delete failed",
            extra={"key": key, "status": res.status_code, "body": res.text[:200]},
        )
    except httpx.HTTPError as exc:
        logger.warning("r2 delete threw", extra={"key": key, "error": str(exc)})


# ─── SigV4 signing helpers ──────────────────────────────────────────────────


def _build_authorization(
    *,
    method: str,
    uri: str,
    query: str,
    headers: dict[str, str],
    payload_hash: str,
    access_key: str,
    secret_key: str,
    date_stamp: str,
    amz_date: str,
) -> str:
    canonical_headers = "".join(
        f"{k.lower()}:{v.strip()}\n" for k, v in sorted(headers.items())
    )
    signed_headers = ";".join(sorted(k.lower() for k in headers.keys()))

    canonical_request = "\n".join([
        method,
        uri,
        query,
        canonical_headers,
        signed_headers,
        payload_hash,
    ])

    credential_scope = f"{date_stamp}/{_REGION}/{_SERVICE}/aws4_request"
    string_to_sign = "\n".join([
        _ALGO,
        amz_date,
        credential_scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])

    signing_key = _derive_signing_key(secret_key, date_stamp)
    signature = hmac.new(
        signing_key,
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    return (
        f"{_ALGO} "
        f"Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, "
        f"Signature={signature}"
    )


def _derive_signing_key(secret_key: str, date_stamp: str) -> bytes:
    def _hmac(key: bytes, msg: str) -> bytes:
        return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

    k_date = _hmac(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    k_region = _hmac(k_date, _REGION)
    k_service = _hmac(k_region, _SERVICE)
    return _hmac(k_service, "aws4_request")
