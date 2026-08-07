import type { Route } from "./+types/share";
import { ShareCard } from "../components/ShareCard";
import { CTA } from "../components/CTA";
import { parsePairId } from "../lib/share-id";
import { fetchMetrics, incrementMetricsViews } from "../lib/supabase";
import { renderCompat, renderSolo } from "../lib/traits";

/**
 * `GET /r/:id` — 관상·궁합 통합 SSR route.
 *
 *   /r/{uuid}            → 관상 (metrics 1행 fetch + runEngine)
 *   /r/{uuidA}~{uuidB}   → 궁합 (metrics 2행 fetch + runCompat)
 *
 * 시간 기반 만료 없음. fetch 마다 `increment_metrics_views` RPC 로 views++
 * → updated_at 자동 갱신 (HOW-IT-WORKS §5.2). dormant 3개월 정체 시 daily cron
 * 이 정리.
 */
export async function loader({ params, request, context }: Route.LoaderArgs) {
  console.log("[share-loader] raw params.id:", JSON.stringify(params.id));
  const ids = parsePairId(params.id);
  console.log("[share-loader] parsed ids:", JSON.stringify(ids));
  if (!ids) {
    console.warn("[share-loader] 404: parsePairId returned null");
    throw new Response("Not Found", { status: 404 });
  }

  const env = context.cloudflare.env;
  const rows = await fetchMetrics(env, ids);
  console.log(
    `[share-loader] fetched rows.length=${rows.length} expected=${ids.length}`,
    "row ids:", rows.map((r) => r.id),
  );
  if (rows.length !== ids.length) {
    console.warn(
      "[share-loader] 404: row count mismatch — missing ids:",
      ids.filter((id) => !rows.some((r) => r.id === id)),
    );
    throw new Response("Not Found", { status: 404 });
  }

  // fire-and-forget views++. fetch latency 에 더하지 않음.
  for (const id of ids) {
    context.cloudflare.ctx.waitUntil(incrementMetricsViews(env, id));
  }

  const ctx = {
    shortId: params.id,
    origin: new URL(request.url).origin,
    // canonical URL 용 — `${WEBAPP_BASE}/r/{id}` 가 본 페이지 자체.
    appLinkBase: `${env.WEBAPP_BASE}/r/`,
    // CTA 가 navigate 할 nested bridge — `${WEBAPP_BASE}/r/{id}/open`.
    // 같은 페이지 URL 이면 Safari noop 라 sub-path 로 보내 universal link 발동.
    appOpenUrl: `${env.WEBAPP_BASE}/r/${params.id}/open`,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    cdnBase: env.R2_CDN_BASE,
  };
  return ids.length === 2
    ? renderCompat(rows[0], rows[1], ctx)
    : renderSolo(rows[0], ctx);
}

export function meta({ data }: Route.MetaArgs) {
  if (!data) return [{ title: "공유 카드를 찾을 수 없습니다" }];
  return [
    { title: data.ogTitle },
    { name: "description", content: data.ogDescription },
    // PII (얼굴 thumbnail) 가 og:image 로 노출되므로 검색엔진 indexing 차단 (§12.4).
    { name: "robots", content: "noindex,nofollow" },
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
        appOpenUrl={loaderData.appOpenUrl}
        appStoreUrl={loaderData.appStoreUrl}
        playStoreUrl={loaderData.playStoreUrl}
      />
    </main>
  );
}
