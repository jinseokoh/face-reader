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
  expires_at: string;
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

export type Ad = {
  id: string;
  title: string;
  storage_path: string;
  duration_sec: number | null;
  reward_coins: number;
  active: boolean;
  created_at: string;
};

export type Unlock = {
  user_id: string;
  pair_key: string;
  total_score: number | null;
  created_at: string;
};
