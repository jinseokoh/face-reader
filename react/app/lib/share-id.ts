import {
  base64UrlToBytes,
  bytesToBase64Url,
  bytesToUuid,
  uuidToBytes,
} from "./codec";

const SOLO_BODY_LEN = 22;
const COMPAT_BODY_LEN = 43;
const SIG_LEN = 4;
const SIG_BYTES = 3;

export type SharePayload =
  | { type: "solo"; userA: string }
  | { type: "compat"; userA: string; userB: string };

export async function encode(p: SharePayload, secret: string): Promise<string> {
  const bytes = payloadToBytes(p);
  const body = bytesToBase64Url(bytes);
  const sig = await hmacSig(bytes, secret);
  return `${body}.${sig}`;
}

export async function decode(token: string, secret: string): Promise<SharePayload> {
  const dot = token.indexOf(".");
  if (dot < 0) throw badRequest();
  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  if (sig.length !== SIG_LEN) throw badRequest();
  if (body.length !== SOLO_BODY_LEN && body.length !== COMPAT_BODY_LEN) throw badRequest();

  let bytes: Uint8Array;
  try {
    bytes = base64UrlToBytes(body);
  } catch {
    throw badRequest();
  }
  if (bytes.length !== 16 && bytes.length !== 32) throw badRequest();

  const expected = await hmacSig(bytes, secret);
  if (!constantTimeEq(sig, expected)) throw new Response("Forbidden", { status: 403 });

  return bytesToPayload(bytes);
}

function payloadToBytes(p: SharePayload): Uint8Array {
  if (p.type === "solo") return uuidToBytes(p.userA);
  const a = uuidToBytes(p.userA);
  const b = uuidToBytes(p.userB);
  const out = new Uint8Array(32);
  out.set(a, 0);
  out.set(b, 16);
  return out;
}

function bytesToPayload(bytes: Uint8Array): SharePayload {
  if (bytes.length === 16) return { type: "solo", userA: bytesToUuid(bytes) };
  return {
    type: "compat",
    userA: bytesToUuid(bytes.slice(0, 16)),
    userB: bytesToUuid(bytes.slice(16, 32)),
  };
}

async function hmacSig(bytes: Uint8Array, secret: string): Promise<string> {
  if (!secret) throw new Error("SHARE_TOKEN_SECRET missing");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, bytes as BufferSource),
  );
  return bytesToBase64Url(mac.slice(0, SIG_BYTES));
}

function constantTimeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

function badRequest(): Response {
  return new Response("Bad Request", { status: 400 });
}
