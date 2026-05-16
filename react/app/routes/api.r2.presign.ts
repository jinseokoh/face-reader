import { AwsClient } from "aws4fetch";
import type { Route } from "./+types/api.r2.presign";

/**
 * POST /api/r2/presign
 *
 * 모바일 앱이 R2 에 직접 PUT 하기 위한 SigV4 presigned URL 을 발급한다.
 * 이미지는 모바일 → R2 직통 (Worker 를 경유하지 않음).
 *
 * 요청:
 *   { prefix: "temp" | "thumbnails", uuid: string, ext?: "jpg",
 *     contentType?: "image/jpeg" }
 *
 * 응답:
 *   { uploadUrl, publicUrl, key, token? }
 *
 *   * uploadUrl : 5분 TTL presigned PUT URL
 *   * publicUrl : 업로드 후 GET 가능한 CDN URL (R2_CDN_BASE/key)
 *   * key       : 실제 R2 object key. prefix=thumbnails 면 YYYYMM 자동 삽입.
 *   * token     : prefix=temp 에 한해, Python /analyze 호출 인증용 HMAC 토큰
 *                 (X-Face-Token 헤더로 전달; X-Face-Key 도 함께 보내야 함).
 */
export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== "POST")
    return new Response("Method Not Allowed", { status: 405 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const parsed = parseBody(body);
  if (!parsed) return new Response("Bad Request", { status: 400 });

  const env = context.cloudflare.env;
  const cfg = readConfig(env);
  if (!cfg)
    return new Response("Server misconfigured", { status: 500 });

  const key = buildKey(parsed.prefix, parsed.uuid, parsed.ext);
  const uploadUrl = await signPut(cfg, key);
  const publicUrl = `${cfg.cdnBase}/${key}`;

  // /analyze 인증 토큰은 temp/ 객체에만 의미 있음.
  let token: string | undefined;
  if (parsed.prefix === "temp") {
    token = await issueFaceToken(cfg, key);
  }

  return Response.json({ uploadUrl, publicUrl, key, token });
}

// ─── parsing / config ────────────────────────────────────────────────────

type Prefix = "temp" | "thumbnails";

interface ParsedBody {
  prefix: Prefix;
  uuid: string;
  ext: string;
  contentType: string;
}

function parseBody(b: unknown): ParsedBody | null {
  if (!b || typeof b !== "object") return null;
  const o = b as Record<string, unknown>;
  const prefix = o.prefix === "temp" || o.prefix === "thumbnails"
    ? (o.prefix as Prefix)
    : null;
  const uuid = typeof o.uuid === "string" ? o.uuid : null;
  if (!prefix || !uuid || !/^[a-f0-9-]{8,}$/i.test(uuid)) return null;
  const ext = (typeof o.ext === "string" && o.ext) ? o.ext : "jpg";
  if (!/^[a-z0-9]{2,5}$/i.test(ext)) return null;
  const contentType = typeof o.contentType === "string" && o.contentType
    ? o.contentType
    : "image/jpeg";
  if (!contentType.startsWith("image/")) return null;
  return { prefix, uuid, ext, contentType };
}

interface Cfg {
  accountId: string;
  bucket: string;
  cdnBase: string;
  accessKeyId: string;
  secretAccessKey: string;
  faceSecret: string;
  ttlSec: number;
}

function readConfig(env: Env): Cfg | null {
  const accountId = env.R2_ACCOUNT_ID;
  const bucket = env.R2_BUCKET_NAME;
  const cdnBase = (env.R2_CDN_BASE || "").replace(/\/$/, "");
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  const faceSecret = env.FACE_API_SECRET;
  const ttlSec = Number(env.FACE_TOKEN_TTL_SEC || "300");
  if (
    !accountId || !bucket || !cdnBase ||
    !accessKeyId || !secretAccessKey || !faceSecret
  ) return null;
  return { accountId, bucket, cdnBase, accessKeyId, secretAccessKey, faceSecret, ttlSec };
}

// ─── key composition ─────────────────────────────────────────────────────

function buildKey(prefix: Prefix, uuid: string, ext: string): string {
  if (prefix === "temp") return `temp/${uuid}.${ext}`;
  const now = new Date();
  const yyyymm = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  return `thumbnails/${yyyymm}/${uuid}.${ext}`;
}

// ─── R2 SigV4 presign ────────────────────────────────────────────────────

async function signPut(cfg: Cfg, key: string): Promise<string> {
  // SigV4 query signing — host 만 서명되고 content-type 은 client 가 자유로이
  // 보낼 수 있다. R2 는 PUT 시점의 content-type 을 객체 메타로 저장하므로
  // 다운로드 측에서 content-type 검증 가능 (Python downloader 가 이미 함).
  const r2 = new AwsClient({
    accessKeyId: cfg.accessKeyId,
    secretAccessKey: cfg.secretAccessKey,
    service: "s3",
    region: "auto",
  });
  const base = `https://${cfg.accountId}.r2.cloudflarestorage.com/${cfg.bucket}/${key}`;
  const url = new URL(base);
  url.searchParams.set("X-Amz-Expires", String(cfg.ttlSec));
  const signed = await r2.sign(
    new Request(url, { method: "PUT" }),
    { aws: { signQuery: true } },
  );
  return signed.url;
}

// ─── HMAC token for /analyze ─────────────────────────────────────────────

async function issueFaceToken(cfg: Cfg, key: string): Promise<string> {
  const deadlineMs = Date.now() + cfg.ttlSec * 1000;
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
    new TextEncoder().encode(cfg.faceSecret),
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
