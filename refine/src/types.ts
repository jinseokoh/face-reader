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

// 케미 그룹 — teams row (서버 계약 SSOT: react/db/migrations/0001_baseline.sql).
export type Team = {
  id: string;
  owner_id: string | null;
  title: string;
  /** service_role 클라이언트만 읽힌다 (anon/authenticated 는 컬럼 grant 봉인). */
  password: string | null;
  is_private: boolean;
  max_players: number;
  age_min: number | null;
  age_max: number | null;
  room_kind: "all" | "match";
  thumb_open: boolean;
  status: "recruiting" | "revealing" | "completed" | "expired";
  started_at: string | null;
  closed_at: string | null;
  result_payload: TeamResultPayload | null;
  created_at: string;
  updated_at: string;
};

/** 발표 시 앱이 올린 결과표 — a/b 는 slot 번호, band = 0~3, 점수는 best 만. */
export type TeamResultPayload = {
  players: { slot: number; name: string; gender: string }[];
  pairs: { a: number; b: number; band: number }[];
  best: { a: number; b: number; score: number };
};

export type TeamMember = {
  id: string;
  team_id: string;
  user_id: string;
  slot_no: number;
  gender: "male" | "female";
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

export type Compatibility = {
  user_id: string;
  /** 궁합 쌍 metrics id — a_id < b_id 정규화, FK 없음(스냅샷은 삭제를 견딘다). */
  a_id: string;
  b_id: string;
  /** 결제 시점 두 body 스냅샷 — metrics row 삭제와 무관하게 궁합을
   *  self-contained 로 복원한다 (해석의 1차 소스). */
  a_body: string | null;
  b_body: string | null;
  /** 결제 시점 두 이름 스냅샷 — 앱 fallback + admin 표시용. */
  a_alias: string | null;
  b_alias: string | null;
  /** 해제 시점 궁합 총점(0~100) — admin 정렬·필터용. */
  total_score: number | null;
  created_at: string;
};

// 채팅 신고 (team_reports) — 사용자 단위 + [메시지] prefix 는 개별 메시지 신고.
export type TeamReport = {
  id: string;
  team_id: string;
  reporter_id: string;
  reported_id: string;
  reason: string;
  created_at: string;
};

// 매칭 채팅 메시지 (team_messages) — 신고 상세의 대화 열람용.
export type TeamMessage = {
  id: string;
  team_id: string;
  sender_id: string;
  body: string;
  created_at: string;
};
