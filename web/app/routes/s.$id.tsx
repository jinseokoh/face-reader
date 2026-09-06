import type { Route } from "./+types/s.$id";
import { ShareCard } from "../components/ShareCard";
import { CTA } from "../components/CTA";
import { loadShare } from "../lib/share-loader";

/**
 * `GET /s/:id` — 첫인상(runMeasure)·비교(runMeasurePair) SSR. iOS(measure 에디션)가
 * 만드는 공유 링크. 카드 데이터는 `/r/:id` 와 같고 페이지만 다르다 — 관상 문구 없음.
 */
export async function loader(args: Route.LoaderArgs) {
  return loadShare(args, { measure: true });
}

export function meta({ data }: Route.MetaArgs) {
  if (!data) return [{ title: "공유 카드를 찾을 수 없습니다" }];
  return [
    { title: data.ogTitle },
    { name: "description", content: data.ogDescription },
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

export default function ShareMeasure({ loaderData }: Route.ComponentProps) {
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
