/**
 * Python /analyze 호출 인증용 HMAC 토큰 (HOW-IT-WORKS §6.1).
 *
 *   token = base64url(deadline_ms_8B_BE || HMAC_SHA256(secret, deadline_ms || key))
 *
 * python/app/utils/auth.py 가 같은 secret(FACE_API_SECRET) 으로 검증한다. `key` 는
 * 요청을 식별하는 문자열 — presign 경로에선 R2 temp 키, 업로드 중계 경로에선
 * `upload/{uuid}`. python 은 key 가 `temp/` 로 시작할 때만 R2 정리를 한다.
 *
 * 워커 두 라우트(api.r2.presign, api.analyze)가 공용. 서버 전용 (crypto.subtle).
 */
export async function issueFaceToken(
  secret: string,
  ttlSec: number,
  key: string,
): Promise<string> {
  const deadlineMs = Date.now() + ttlSec * 1000;
  const ts = new Uint8Array(8);
  // big-endian 64-bit unsigned write.
  const v = BigInt(deadlineMs);
  for (let i = 7; i >= 0; i--) ts[i] = Number((v >> BigInt((7 - i) * 8)) & 0xffn);

  const keyBytes = new TextEncoder().encode(key);
  const message = new Uint8Array(ts.length + keyBytes.length);
  message.set(ts, 0);
  message.set(keyBytes, ts.length);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const macBuf = await crypto.subtle.sign("HMAC", cryptoKey, message);
  const mac = new Uint8Array(macBuf);

  const out = new Uint8Array(ts.length + mac.length);
  out.set(ts, 0);
  out.set(mac, ts.length);
  return base64UrlEncode(out);
}

function base64UrlEncode(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
