import { AwsClient } from "aws4fetch";
import type { Route } from "./+types/api.r2.presign";

/**
 * POST /api/r2/presign
 *
 * 모바일 앱이 R2 에 직접 PUT 하기 위한 SigV4 presigned URL 을 발급한다.
 * 이미지는 모바일 → R2 직통 (Worker 를 경유하지 않음).
 *
 * 요청:
 *   { prefix: "temp", uuid: string, ext?, contentType? }
 *   { prefix: "thumbnails", hash: string, scope?, ext?, contentType? }
 *   { prefix: "thumbnails", uuid: string, ... }                  ← 레거시 경로
 *
 * 썸네일 키의 첫 칸은 **소유자**다 — `thumbnails/{owner}/{sha256}.jpg`.
 * 사진의 수명이 카드가 아니라 사람에게 묶이는 지점이고, 탈퇴는 이 prefix 를
 * 통째로 지우는 한 번의 연산이 된다. 참조 계수도 회수 잡도 필요 없어진다.
 *
 *   로그인  owner = JWT 의 user.id — **서버가 읽는다.** 호출자가 남의 uid 를
 *           지정할 수 없고, 그래서 남의 폴더에 쓸 수 없다.
 *   익명    owner = 요청의 `scope` (= `anon-{metrics_id}`). 그 id 는
 *           unguessable uuid 다.
 *   레거시  토큰도 scope 도 없으면 소유자 없는 옛 키 (배포된 앱).
 *
 * 응답 200:
 *   { uploadUrl, publicUrl, key, cacheControl, token? }
 *
 *   * uploadUrl    : 5분 TTL presigned PUT URL
 *   * publicUrl    : 업로드 후 GET 가능한 CDN URL (R2_CDN_BASE/key)
 *   * key          : 실제 R2 object key
 *   * cacheControl : PUT 시 그대로 실어 보낼 Cache-Control 값. 내용 주소 키는
 *                    불변이라 무기한 캐시가 안전하다 (다른 바이트 = 다른 URL).
 *   * token        : prefix=temp 에 한해, Python /analyze 호출 인증용 HMAC 토큰
 *                    (X-Face-Token 헤더로 전달; X-Face-Key 도 함께 보내야 함).
 *
 * 응답 409: { key, publicUrl, exists: true }
 *   thumbnails/ 객체가 이미 있으면 PUT URL 을 발급하지 않는다. 이 엔드포인트는
 *   인증이 없고 키를 호출자가 지정하므로, 발급해 주면 **남의 썸네일을 임의
 *   이미지로 덮어쓸 수 있다** (피해자 키는 공유 링크 og:image 에 노출된다).
 *   내용 주소에서 "이미 있다"는 같은 바이트가 저장돼 있다는 뜻이므로 호출자는
 *   이 응답을 성공으로 취급하면 된다.
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

  const resolved = await resolveOwner(request, env, parsed);
  if (!resolved.ok) return new Response("Invalid token", { status: 401 });

  const key = buildKey(parsed, resolved.owner);
  const publicUrl = `${cfg.cdnBase}/${key}`;

  // 덮어쓰기 차단 — thumbnails/ 에 한해. temp/ 는 1일 만료 작업 공간이라 제외.
  // 조회 자체가 실패하면 fail-closed 로 503 을 준다. 여기서 통과시키면 R2 가
  // 흔들리는 동안 덮어쓰기 창이 열린다 — 호출자는 재시도하면 된다.
  if (parsed.prefix === "thumbnails") {
    const exists = await objectExists(cfg, key);
    if (exists === "error")
      return new Response("Storage unavailable", { status: 503 });
    if (exists === "yes")
      return Response.json({ key, publicUrl, exists: true }, { status: 409 });
  }

  const uploadUrl = await signPut(cfg, key);

  // /analyze 인증 토큰은 temp/ 객체에만 의미 있음.
  let token: string | undefined;
  if (parsed.prefix === "temp") {
    token = await issueFaceToken(cfg, key);
  }

  return Response.json({
    uploadUrl,
    publicUrl,
    key,
    cacheControl: kCacheControl,
    token,
  });
}

// ─── parsing / config ────────────────────────────────────────────────────

type Prefix = "temp" | "thumbnails";

/** 키의 출처 — 내용 주소(hash) 또는 호출자 지정 uuid. */
type KeySource =
  | { kind: "hash"; hash: string }
  | { kind: "uuid"; uuid: string };

interface ParsedBody {
  prefix: Prefix;
  source: KeySource;
  ext: string;
  contentType: string;
  /** 익명 촬영분의 소유자 스코프 (`anon-{metrics_id}`). 로그인이면 무시된다. */
  scope: string | null;
}

function parseBody(b: unknown): ParsedBody | null {
  if (!b || typeof b !== "object") return null;
  const o = b as Record<string, unknown>;
  const prefix = o.prefix === "temp" || o.prefix === "thumbnails"
    ? (o.prefix as Prefix)
    : null;
  if (!prefix) return null;

  const ext = (typeof o.ext === "string" && o.ext) ? o.ext : "jpg";
  if (!/^[a-z0-9]{2,5}$/i.test(ext)) return null;
  const contentType = typeof o.contentType === "string" && o.contentType
    ? o.contentType
    : "image/jpeg";
  if (!contentType.startsWith("image/")) return null;

  // 익명 소유자 스코프. `anon-` 접두사를 강제해 로그인 uid 를 사칭할 수 없게
  // 한다 — uid 는 이 형식과 절대 겹치지 않는다.
  const scope = typeof o.scope === "string" &&
      /^anon-[0-9a-f-]{36}$/i.test(o.scope)
    ? o.scope.toLowerCase()
    : null;

  // 내용 주소 — sha256 hex 64자. thumbnails/ 전용.
  const hash = typeof o.hash === "string" && /^[a-f0-9]{64}$/i.test(o.hash)
    ? o.hash.toLowerCase()
    : null;
  if (prefix === "thumbnails" && hash) {
    return { prefix, source: { kind: "hash", hash }, ext, contentType, scope };
  }

  // uuid 경로 — temp/ 와, hash 를 보내지 않는 호출자.
  const uuid = typeof o.uuid === "string" ? o.uuid : null;
  if (!uuid || !/^[a-f0-9-]{8,}$/i.test(uuid)) return null;
  return { prefix, source: { kind: "uuid", uuid }, ext, contentType, scope };
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

/**
 * 이 요청이 만들 객체의 소유자. `temp/` 와 레거시 uuid 경로는 소유자가 없다.
 *
 * 로그인 토큰이 오면 **서버가 Supabase 에 물어** uid 를 얻는다
 * (`api.account.delete.ts` 와 같은 패턴). 호출자가 보낸 값을 믿지 않는 게
 * 핵심 — 이 엔드포인트로 남의 폴더에 쓰는 길이 없어야 한다.
 */
async function resolveOwner(
  request: Request,
  env: Env,
  parsed: ParsedBody,
): Promise<{ ok: true; owner: string | null } | { ok: false }> {
  if (parsed.prefix !== "thumbnails" || parsed.source.kind !== "hash") {
    return { ok: true, owner: null };
  }
  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    return { ok: true, owner: parsed.scope };
  }
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: auth },
  });
  if (!res.ok) return { ok: false };
  const user = (await res.json()) as { id?: string };
  if (!user.id) return { ok: false };
  return { ok: true, owner: user.id };
}

function buildKey(p: ParsedBody, owner: string | null): string {
  // 내용 주소 — 같은 바이트는 같은 키, 다른 바이트는 다른 URL. 캐시 무효화가
  // 필요 없어지고 재업로드가 멱등해진다.
  // (parseBody 가 thumbnails/ 에만 hash 를 허용한다.)
  if (p.source.kind === "hash") {
    const h = p.source.hash;
    // 소유자 스코프 — 탈퇴가 이 prefix 하나를 지우는 일이 된다. 같은 사진을
    // 두 사람이 가져도 객체가 둘이라 한쪽의 삭제가 다른 쪽을 건드리지 않는다.
    if (owner) return `thumbnails/${owner}/${h}.${p.ext}`;
    // 레거시 — 소유자를 모르는 호출자. 앞 2자 샤딩.
    return `thumbnails/${h.slice(0, 2)}/${h}.${p.ext}`;
  }

  const uuid = p.source.uuid;
  if (p.prefix === "temp") return `temp/${uuid}.${p.ext}`;

  // uuid 경로 — 월 단위 prefix. 일 단위는 대시보드에서 폴더가 너무 많아진다.
  // 클라이언트는 key 를 opaque 하게 저장·사용하므로 형식 차이는 신규 키에만 영향.
  const now = new Date();
  const yyyy = now.getUTCFullYear();
  const mm = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `thumbnails/${yyyy}${mm}/${uuid}.${p.ext}`;
}

/// 내용 주소 키는 불변이므로 무기한 캐시가 안전하다.
const kCacheControl = "public, max-age=31536000, immutable";

/** R2 객체 존재 확인. 조회 자체가 실패하면 "error" — 호출부가 fail-closed. */
async function objectExists(
  cfg: Cfg,
  key: string,
): Promise<"yes" | "no" | "error"> {
  const r2 = new AwsClient({
    accessKeyId: cfg.accessKeyId,
    secretAccessKey: cfg.secretAccessKey,
    service: "s3",
    region: "auto",
  });
  const url =
    `https://${cfg.accountId}.r2.cloudflarestorage.com/${cfg.bucket}/${key}`;
  try {
    const signed = await r2.sign(new Request(url, { method: "HEAD" }));
    const res = await fetch(signed);
    if (res.ok) return "yes";
    if (res.status === 404) return "no";
    return "error";
  } catch {
    return "error";
  }
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
