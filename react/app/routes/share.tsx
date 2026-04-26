import type { Route } from "./+types/share";
import { ShareCard } from "../components/ShareCard";
import { CTA } from "../components/CTA";
import { fetchShareCard } from "../lib/supabase";

export async function loader({ params, context }: Route.LoaderArgs) {
  const { shortId } = params;
  const data = await fetchShareCard(context.cloudflare.env, shortId);
  if (!data) throw new Response("Not Found", { status: 404 });
  if (data.expiresAt && new Date(data.expiresAt) < new Date()) {
    throw new Response("Expired", { status: 410 });
  }
  return data;
}

export function meta({ data, params }: Route.MetaArgs) {
  if (!data) return [{ title: "공유 카드를 찾을 수 없습니다" }];
  const url = `${data.appLinkBase}${params.shortId}`;
  return [
    { title: data.ogTitle },
    { name: "description", content: data.ogDescription },
    { property: "og:type", content: "website" },
    { property: "og:title", content: data.ogTitle },
    { property: "og:description", content: data.ogDescription },
    { property: "og:image", content: data.ogImage },
    { property: "og:image:width", content: "1200" },
    { property: "og:image:height", content: "630" },
    { property: "og:url", content: url },
    { name: "twitter:card", content: "summary_large_image" },
  ];
}

export default function Share({ loaderData, params }: Route.ComponentProps) {
  return (
    <main className="share">
      <ShareCard data={loaderData} />
      <CTA
        shortId={params.shortId}
        appLinkBase={loaderData.appLinkBase}
        appStoreUrl={loaderData.appStoreUrl}
        playStoreUrl={loaderData.playStoreUrl}
      />
    </main>
  );
}
