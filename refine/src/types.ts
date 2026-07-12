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

/** metrics.body 의 thumbnailKey → R2 CDN URL (없으면 null). */
export function metricThumbUrl(body: string | null | undefined): string | null {
  if (!body) return null;
  try {
    const key = (JSON.parse(body) as { thumbnailKey?: string }).thumbnailKey;
    return key ? `https://cdn.facely.kr/${key}` : null;
  } catch {
    return null;
  }
}

// 케미 그룹 — 방장이 push 한 teams row (마감 시 matrix_payload 보관).
export type Team = {
  id: string;
  owner_id: string | null;
  title: string;
  closed_at: string | null;
  matrix_payload: TeamMatrixPayload | null;
  created_at: string;
  updated_at: string;
};

/** 마감 시 앱이 올린 결과표 — 이름 + 밴드만 (점수·landmark 없음). */
export type TeamMatrixPayload = {
  v: number;
  title: string;
  members: string[];
  pairs: { a: number; b: number; e: string; l: string; c: string }[];
  best: { a: number; b: number }[];
};

export type TeamMember = {
  id: string;
  team_id: string;
  metrics_id: string | null;
  name: string;
  is_owner: boolean;
  joined_at: string;
};

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
