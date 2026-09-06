import { parsePairId } from "./share-id";
import { fetchMetrics, incrementMetricsViews } from "./supabase";
import { renderCompat, renderMeasurePair, renderMeasureSolo, renderSolo } from "./traits";
import type { RenderedShare } from "./types";

/** route 모듈의 LoaderArgs 중 쓰는 것만 — /r 과 /s 의 생성 타입이 달라 구조적으로 받는다. */
type Args = {
  params: { id?: string };
  request: Request;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  context: any;
};

/**
 * `/r/:id`(관상·궁합) 와 `/s/:id`(첫인상·비교) 공용 로더. 카드 데이터는 같고
 * 링크 경로가 어느 페이지를 그릴지 정한다 — iOS 가 만든 링크만 `/s/`.
 */
export async function loadShare(
  { params, request, context }: Args,
  { measure }: { measure: boolean },
): Promise<RenderedShare> {
  const seg = measure ? "s" : "r";
  const ids = parsePairId(params.id ?? "");
  if (!ids) throw new Response("Not Found", { status: 404 });
  const env = context.cloudflare.env;
  const rows = await fetchMetrics(env as never, ids);
  if (rows.length !== ids.length) throw new Response("Not Found", { status: 404 });
  for (const id of ids) {
    context.cloudflare.ctx.waitUntil(incrementMetricsViews(env as never, id));
  }
  const ctx = {
    shortId: params.id ?? "",
    origin: new URL(request.url).origin,
    appLinkBase: `${env.WEBAPP_BASE}/${seg}/`,
    appOpenUrl: `${env.WEBAPP_BASE}/${seg}/${params.id}/open`,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    cdnBase: env.R2_CDN_BASE,
  };
  if (measure) {
    return ids.length === 2 ? renderMeasurePair(rows[0], rows[1], ctx) : renderMeasureSolo(rows[0], ctx);
  }
  return ids.length === 2 ? renderCompat(rows[0], rows[1], ctx) : renderSolo(rows[0], ctx);
}
