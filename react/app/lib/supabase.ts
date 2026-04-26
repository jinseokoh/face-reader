import { createClient } from "@supabase/supabase-js";
import type { ShareCardData } from "./types";

export async function fetchShareCard(
  env: Env,
  shortId: string,
): Promise<ShareCardData | null> {
  // demo fallback so /r/demo 가 supabase 없이도 동작.
  if (shortId === "demo") return demoCard(env);

  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    console.warn("[share-host] SUPABASE_* env 미설정");
    return null;
  }

  const sb = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
  });

  const { data, error } = await sb
    .from("share_card")
    .select(
      "id, kind, card_image_url, label, total_score, tagline, highlights, og_title, og_description, og_image, expires_at",
    )
    .eq("id", shortId)
    .maybeSingle();

  if (error) {
    console.error("[share-host] supabase error", error);
    return null;
  }
  if (!data) return null;
  return mapRow(data, env);
}

interface Row {
  id: string;
  kind: ShareCardData["kind"];
  card_image_url: string;
  label: string;
  total_score: number;
  tagline: string;
  highlights: ShareCardData["highlights"] | null;
  og_title: string;
  og_description: string;
  og_image: string | null;
  expires_at: string | null;
}

function mapRow(row: Row, env: Env): ShareCardData {
  return {
    shortId: row.id,
    kind: row.kind,
    cardImageUrl: row.card_image_url,
    label: row.label,
    totalScore: row.total_score,
    tagline: row.tagline,
    highlights: row.highlights ?? [],
    ogTitle: row.og_title,
    ogDescription: row.og_description,
    ogImage: row.og_image ?? row.card_image_url,
    expiresAt: row.expires_at,
    appLinkBase: env.APP_LINK_BASE,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
  };
}

function demoCard(env: Env): ShareCardData {
  return {
    shortId: "demo",
    kind: "compat",
    cardImageUrl: "https://picsum.photos/seed/face-demo/1200/630",
    label: "잘 맞는 흐름",
    totalScore: 87,
    tagline: "끌림이 자연스럽게 이어지는 관계입니다.",
    highlights: [
      { title: "五行 — 相生", detail: "기운이 서로를 살리는 자리" },
      { title: "妻妾宮", detail: "관계 시작에 방어가 적은 얼굴" },
      { title: "性情 — 친밀", detail: "분위기보다 솔직함이 통하는 조합" },
    ],
    ogTitle: "둘의 궁합 87점 — AI 관상가",
    ogDescription: "끌림이 자연스럽게 이어지는 관계입니다.",
    ogImage: "https://picsum.photos/seed/face-demo/1200/630",
    expiresAt: null,
    appLinkBase: env.APP_LINK_BASE,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
  };
}
