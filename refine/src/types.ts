export type AppUser = {
  id: string;
  kakao_user_id: string | null;
  nickname: string | null;
  profile_image_url: string | null;
  coins: number;
  signup_bonus_skipped: boolean;
  created_at: string;
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

export type MetricSource = "camera" | "album";

export type MetricEntry = {
  id: string;
  user_id: string | null;
  metrics_json: string;
  source: MetricSource;
  ethnicity: string;
  gender: string;
  age_group: string;
  alias: string | null;
  expires_at: string;
  created_at: string;
};

export type Unlock = {
  user_id: string;
  pair_key: string;
  total_score: number | null;
  created_at: string;
};
