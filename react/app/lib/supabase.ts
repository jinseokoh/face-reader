import type { MetricsRow, RawMetrics } from "./types";

const SELECT = "id,body";

export async function fetchMetrics(env: Env, ids: string[]): Promise<MetricsRow[]> {
  const demoOnly = ids.every((id) => id.startsWith("00000000-0000-0000-0000-"));
  if (demoOnly) {
    console.log("[fetchMetrics] demo-only path, ids=", ids);
    return ids.map(demoRow);
  }

  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    console.warn("[fetchMetrics] SUPABASE_* env 미설정 — SUPABASE_URL?", !!env.SUPABASE_URL, "ANON_KEY?", !!env.SUPABASE_ANON_KEY);
    return [];
  }

  const url =
    `${env.SUPABASE_URL}/rest/v1/metrics` +
    `?id=in.(${ids.map(encodeURIComponent).join(",")})&select=${SELECT}`;
  console.log("[fetchMetrics] GET", url);
  const res = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
    },
  });
  if (!res.ok) {
    console.error("[fetchMetrics] supabase status", res.status, await res.text());
    return [];
  }
  const rows = (await res.json()) as Array<{
    id: string;
    body: string | null;
  }>;
  console.log(
    `[fetchMetrics] raw rows.length=${rows.length} ids requested=${ids.length}`,
    "rows:", rows.map((r) => ({
      id: r.id,
      bodyNull: r.body == null,
      bodyLen: r.body?.length ?? 0,
    })),
  );

  const map = new Map<string, MetricsRow>();
  for (const r of rows) {
    if (!r.body) {
      console.warn("[fetchMetrics] drop: body null id=", r.id);
      continue;
    }
    try {
      const raw = JSON.parse(r.body) as RawMetrics;
      map.set(r.id, { id: r.id, raw });
    } catch (e) {
      console.error("[fetchMetrics] body parse fail", r.id, e);
    }
  }
  return ids.map((id) => map.get(id)).filter((r): r is MetricsRow => Boolean(r));
}

/**
 * `/r/{id}` SSR fetch 마다 호출 — views++ + updated_at 자동 갱신 (trigger).
 * inactivity cron 의 active 신호 (HOW-IT-WORKS §5.2 / §12.2).
 *
 * fire-and-forget 으로 `context.cloudflare.ctx.waitUntil(...)` 안에서 호출
 * 권장 — fetch latency 에 더하지 않게.
 */
export async function incrementMetricsViews(env: Env, id: string): Promise<void> {
  if (id.startsWith("00000000-0000-0000-0000-")) return; // demo id 는 skip
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return;

  try {
    const res = await fetch(
      `${env.SUPABASE_URL}/rest/v1/rpc/increment_metrics_views`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          apikey: env.SUPABASE_ANON_KEY,
          authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({ card_id: id }),
      },
    );
    if (!res.ok) {
      console.warn("[share-host] views++ rpc fail", id, res.status, await res.text());
    }
  } catch (e) {
    console.warn("[share-host] views++ rpc threw", id, e);
  }
}

// ── 교감도 그룹 (P3) — /g/:id 쇼케이스/초대장 ──────────────────────────────

/** 마감 시 앱이 올린 매트릭스 — 이름 + 밴드만 (점수·landmark 없음). */
export type TeamPayload = {
  v: number;
  title: string;
  members: string[]; // 표시 이름 (방장 먼저)
  pairs: { a: number; b: number; e: string; l: string; c: string }[]; // a<b 인덱스
  best: { a: number; b: number }[];
  surprises: { a: number; b: number }[];
};

export type TeamShowcase = {
  id: string;
  title: string;
  closed: boolean;
  // 초대장·참여 위저드용 슬롯 상세 (방장 먼저) — joined = metrics 등록 완료.
  members: { name: string; joined: boolean; isOwner: boolean }[];
  // 전원 등록 여부 — 모든 슬롯이 metrics 로 채워짐(≥3). 결과표는 전원 등록
  // 시에만 생성되므로, closed+payload 없음 상태의 안내 분기가 이 값을 쓴다:
  // true = "결과표 준비 중"(방장 앱 backfill 대기), false = 전원 미충족 종료.
  allJoined: boolean;
  payload: TeamPayload | null; // 마감 후 결과
  // 웹 티저용 — 방장의 이름 + raw 메트릭. 방장 미참여/미스캔이면 null
  // (그 경우 티저는 solo 관상 한 입으로 fallback).
  owner: { name: string; raw: RawMetrics } | null;
};

/** teams + team_members 를 anon 으로 read (link-share, RLS public read). */
export async function fetchTeam(
  env: Env,
  id: string,
): Promise<TeamShowcase | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const headers = {
    apikey: env.SUPABASE_ANON_KEY,
    authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
  };
  const q = encodeURIComponent(id);

  const tRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?id=eq.${q}` +
      `&select=id,title,closed_at,matrix_payload`,
    { headers },
  );
  if (!tRes.ok) {
    console.error("[fetchTeam] teams status", tRes.status, await tRes.text());
    return null;
  }
  const teams = (await tRes.json()) as Array<{
    id: string;
    title: string;
    closed_at: string | null;
    matrix_payload: TeamPayload | null;
  }>;
  if (teams.length === 0) return null;
  const t = teams[0];

  const mRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/team_members?team_id=eq.${q}` +
      `&select=name,is_owner,metrics_id,joined_at&order=joined_at`,
    { headers },
  );
  const members = mRes.ok
    ? ((await mRes.json()) as Array<{
        name: string;
        is_owner: boolean;
        metrics_id: string | null;
      }>)
    : [];
  const memberList = [
    ...members.filter((m) => m.is_owner),
    ...members.filter((m) => !m.is_owner),
  ].map((m) => ({
    name: m.name,
    joined: m.metrics_id != null,
    isOwner: m.is_owner,
  }));

  // 방장 raw 메트릭 — 웹 티저 "나 ↔ 방장" 점수 계산용.
  const ownerRow = members.find((m) => m.is_owner);
  let owner: { name: string; raw: RawMetrics } | null = null;
  if (ownerRow?.metrics_id) {
    const [row] = await fetchMetrics(env, [ownerRow.metrics_id]);
    if (row) owner = { name: ownerRow.name, raw: row.raw };
  }

  return {
    id: t.id,
    title: t.title,
    closed: t.closed_at != null,
    members: memberList,
    allJoined:
      members.length >= 3 && members.every((m) => m.metrics_id != null),
    payload: t.matrix_payload ?? null,
    owner,
  };
}

function demoRow(id: string): MetricsRow {
  // 마지막 글자로 demo persona 분기 — '1' 은 여성/30대/계란형, '2' 는 남성/40대/긴얼굴.
  // 솔로 데모는 A (id 끝 1), compat 데모는 A × B (남녀 페어) 로 보이도록.
  const isB = id.endsWith("2");
  return {
    id,
    raw: {
      schemaVersion: 1,
      ethnicity: "eastAsian",
      gender: isB ? "male" : "female",
      ageGroup: "thirties",
      timestamp: "2026-04-27T00:00:00.000Z",
      source: "album",
      metrics: DEMO_RAW_METRICS,
      faceShape: isB ? "oblong" : "oval",
    } as unknown as RawMetrics,
  };
}

// 17 frontal rawValue + extra calibration metrics (eyebrowLength, chinAngle 등).
// 데모 페이지·smoke test 용 — 실 프로덕션 row 는 Flutter 가 mediapipe 로 채운다.
const DEMO_RAW_METRICS: Record<string, number> = {
  faceAspectRatio: 1.30,
  upperFaceRatio: 0.33,
  midFaceRatio: 0.32,
  lowerFaceRatio: 0.35,
  faceTaperRatio: 0.78,
  lowerFaceFullness: 0.60,
  gonialAngle: 122.0,
  intercanthalRatio: 0.30,
  eyeFissureRatio: 0.31,
  eyeCanthalTilt: 8.0,
  eyebrowThickness: 0.018,
  browEyeDistance: 0.045,
  nasalWidthRatio: 0.28,
  nasalHeightRatio: 0.42,
  mouthWidthRatio: 0.42,
  mouthCornerAngle: 5.0,
  lipFullnessRatio: 0.38,
  philtrumLength: 0.10,
  foreheadWidth: 0.78,
  cheekboneWidth: 0.93,
  chinAngle: 130.0,
  eyeAspect: 0.32,
  eyebrowCurvature: 0.06,
  eyebrowTiltDirection: 1.0,
  upperVsLowerLipRatio: 0.55,
  browSpacing: 0.18,
};
