import type { Route } from "./+types/api.share";
import { encode, type SharePayload } from "../lib/share-id";

export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const payload = parseBody(body);
  if (!payload) return new Response("Bad Request", { status: 400 });

  const env = context.cloudflare.env;
  if (!env.SHARE_TOKEN_SECRET) return new Response("Server misconfigured", { status: 500 });

  const shortId = await encode(payload, env.SHARE_TOKEN_SECRET);
  return Response.json({ shortId });
}

function parseBody(b: unknown): SharePayload | null {
  if (!b || typeof b !== "object") return null;
  const o = b as Record<string, unknown>;
  if (o.type === "solo" && typeof o.userA === "string") {
    return { type: "solo", userA: o.userA };
  }
  if (o.type === "compat" && typeof o.userA === "string" && typeof o.userB === "string") {
    return { type: "compat", userA: o.userA, userB: o.userB };
  }
  return null;
}
