import type { Route } from "./+types/share";
import { ShareCard } from "../components/ShareCard";
import { CTA } from "../components/CTA";
import { decode } from "../lib/share-id";
import { fetchMetrics } from "../lib/supabase";
import { renderCompat, renderSolo } from "../lib/traits";

export async function loader({ params, request, context }: Route.LoaderArgs) {
  const env = context.cloudflare.env;
  if (!env.SHARE_TOKEN_SECRET) throw new Response("Server misconfigured", { status: 500 });

  const payload = await decode(params.shortId, env.SHARE_TOKEN_SECRET);
  const ids = payload.type === "compat" ? [payload.userA, payload.userB] : [payload.userA];
  const rows = await fetchMetrics(env, ids);
  if (rows.length !== ids.length) throw new Response("Not Found", { status: 404 });

  const ctx = {
    shortId: params.shortId,
    origin: new URL(request.url).origin,
    appLinkBase: env.APP_LINK_BASE,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
  };
  return payload.type === "compat"
    ? renderCompat(rows[0], rows[1], ctx)
    : renderSolo(rows[0], ctx);
}

export function meta({ data }: Route.MetaArgs) {
  if (!data) return [{ title: "공유 카드를 찾을 수 없습니다" }];
  return [
    { title: data.ogTitle },
    { name: "description", content: data.ogDescription },
    { property: "og:type", content: "website" },
    { property: "og:title", content: data.ogTitle },
    { property: "og:description", content: data.ogDescription },
    { property: "og:image", content: data.ogImage },
    { property: "og:image:width", content: "1200" },
    { property: "og:image:height", content: "630" },
    { property: "og:url", content: data.canonicalUrl },
    { name: "twitter:card", content: "summary_large_image" },
  ];
}

export default function Share({ loaderData }: Route.ComponentProps) {
  return (
    <main className="share">
      <ShareCard data={loaderData} />
      <CTA
        shortId={loaderData.shortId}
        appLinkBase={loaderData.appLinkBase}
        appStoreUrl={loaderData.appStoreUrl}
        playStoreUrl={loaderData.playStoreUrl}
      />
    </main>
  );
}
