export type AppUser = {
  id: string;
  kakao_user_id: string | null;
  nickname: string | null;
  profile_image_url: string | null;
  coins: number;
  signup_bonus_skipped: boolean;
  created_at: string;
  email: string | null;
};

export type CoinKind = "purchase" | "spend" | "bonus" | "refund";

export type CoinEntry = {
  id: string;
  user_id: string;
  kind: CoinKind;
  amount: number;
  balance_after: number;
  product_id: string | null;
  store_transaction_id: string | null;
  reference_id: string | null;
  description: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

export type MetricEntry = {
  id: string;
  user_id: string | null;
  body: string;
  is_my_face: boolean;
  alias: string | null;
  views: number;
  updated_at: string;
  created_at: string;
};

export type Demographics = {
  source?: string;
  gender?: string;
  ethnicity?: string;
  ageGroup?: string;
};

export function parseDemographics(body: string | null | undefined): Demographics {
  if (!body) return {};
  try {
    const j = JSON.parse(body);
    return { source: j.source, gender: j.gender, ethnicity: j.ethnicity, ageGroup: j.ageGroup };
  } catch {
    return {};
  }
}

// custom video 광고 — 무료코인 3편 중 1편으로 노출 (per-video reward 없음).
export type AdVideo = {
  id: string;
  title: string;
  storage_path: string;
  duration_sec: number | null;
  active: boolean;
  created_at: string;
};

// 외부 광고주 배너 — 홈 탭 rotation 노출, 탭 시 link_url 이동. 측정 없음.
export type AdImage = {
  id: string;
  title: string;
  storage_path: string;
  link_url: string | null;
  active: boolean;
  sort_order: number;
  created_at: string;
};

export type Unlock = {
  user_id: string;
  pair_key: string;
  total_score: number | null;
  created_at: string;
};
