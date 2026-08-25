import type { MetricsRow, RawMetrics } from "./types";

const SELECT = "id,body";

export async function fetchMetrics(env: Env, ids: string[]): Promise<MetricsRow[]> {
  const demoOnly = ids.every((id) => id.startsWith("00000000-0000-0000-0000-"));
  if (demoOnly) {
    console.log("[fetchMetrics] demo-only path, ids=", ids);
    return ids.map(demoRow);
  }

  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) {
    console.warn("[fetchMetrics] SUPABASE_* env 미설정 — SUPABASE_URL?", !!env.SUPABASE_URL, "ANON_KEY?", !!env.SUPABASE_PUBLISHABLE_KEY);
    return [];
  }

  const url =
    `${env.SUPABASE_URL}/rest/v1/metrics` +
    `?id=in.(${ids.map(encodeURIComponent).join(",")})&select=${SELECT}`;
  console.log("[fetchMetrics] GET", url);
  const res = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
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
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return;

  try {
    const res = await fetch(
      `${env.SUPABASE_URL}/rest/v1/rpc/increment_metrics_views`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          apikey: env.SUPABASE_PUBLISHABLE_KEY,
          authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
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

// ── 케미 매칭 — /g/:id 쇼케이스/초대장 ──────────────────────────────

export type TeamSSR = {
  team: {
    id: string;
    title: string;
    isPrivate: boolean;
    maxPlayers: number;
    ageMin: number | null;
    ageMax: number | null;
    roomKind: "all" | "match";
    status: string;
    resultPayload: unknown | null;
    chemistrySnapshot: Record<string, unknown> | null;
  };
  roster: {
    userId: string;
    slotNo: number;
    isOwner: boolean;
    /** 조인 시점 동결 이름 (team_members.alias). */
    alias: string;
    gender: string;
    /** my-face 썸네일 R2 키. 없으면 null. */
    thumbKey: string | null;
    /** metrics body 의 촬영 경로("camera"/"album") — 아바타 border 색 규칙. */
    thumbSource: string | null;
    /** metrics body 의 AgeGroup enum name ("thirties" 등) — 인구통계 라벨용. */
    ageGroup: string | null;
    /** metrics body 의 Ethnicity enum name ("eastAsian" 등) — 인구통계 라벨용. */
    ethnicity: string | null;
  }[];
};

/** teams + team_roster 를 anon 으로 read (link-share, RLS public read). */
export async function fetchTeamSSR(
  env: Env,
  id: string,
): Promise<TeamSSR | null> {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return null;
  const headers = {
    apikey: env.SUPABASE_PUBLISHABLE_KEY,
    authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
  };
  const q = encodeURIComponent(id);

  const teamRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?id=eq.${q}` +
      `&select=id,title,is_private,max_players,age_min,age_max,room_kind,status,result_payload,chemistry_snapshot`,
    { headers },
  );
  if (!teamRes.ok) {
    console.error("[fetchTeamSSR] teams status", teamRes.status, await teamRes.text());
    return null;
  }
  const teams = (await teamRes.json()) as Record<string, unknown>[];
  if (teams.length === 0) return null;
  const t = teams[0];

  const rosterRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/team_roster?team_id=eq.${q}` +
      `&select=user_id,slot_no,is_owner,alias,gender&order=slot_no.asc`,
    { headers },
  );
  const rosterRows = rosterRes.ok
    ? ((await rosterRes.json()) as Record<string, unknown>[])
    : [];

  // 참가자 my-face metrics body 파싱 — 썸네일 키 + 촬영 경로(source, 아바타
  // border 규칙) + 인구통계(ageGroup·ethnicity, 칩 라벨).
  const thumbs = new Map<
    string,
    {
      key: string | null;
      source: string | null;
      ageGroup: string | null;
      ethnicity: string | null;
    }
  >();
  if (rosterRows.length > 0) {
    const ids = rosterRows.map((r) => r.user_id as string).join(",");
    const metricsRes = await fetch(
      `${env.SUPABASE_URL}/rest/v1/metrics?user_id=in.(${ids})` +
        `&is_my_face=eq.true&select=user_id,body`,
      { headers },
    );
    if (metricsRes.ok) {
      for (const m of (await metricsRes.json()) as Record<string, unknown>[]) {
        try {
          const body = JSON.parse(m.body as string) as {
            thumbnailKey?: string;
            source?: string;
            ageGroup?: string;
            ethnicity?: string;
          };
          thumbs.set(m.user_id as string, {
            key: body.thumbnailKey ?? null,
            source: body.source ?? null,
            ageGroup: body.ageGroup ?? null,
            ethnicity: body.ethnicity ?? null,
          });
        } catch {
          /* malformed body — 아바타 없이 렌더 */
        }
      }
    }
  }

  return {
    team: {
      id: t.id as string,
      title: t.title as string,
      isPrivate: (t.is_private as boolean) ?? false,
      maxPlayers: t.max_players as number,
      ageMin: (t.age_min as number) ?? null,
      ageMax: (t.age_max as number) ?? null,
      roomKind: t.room_kind as "all" | "match",
      status: t.status as string,
      resultPayload: t.result_payload ?? null,
      chemistrySnapshot: (t.chemistry_snapshot as Record<string, unknown>) ?? null,
    },
    roster: rosterRows.map((r) => ({
      userId: r.user_id as string,
      slotNo: r.slot_no as number,
      isOwner: r.is_owner as boolean,
      alias: (r.alias as string) ?? "참가자",
      gender: r.gender as string,
      thumbKey: thumbs.get(r.user_id as string)?.key ?? null,
      thumbSource: thumbs.get(r.user_id as string)?.source ?? null,
      ageGroup: thumbs.get(r.user_id as string)?.ageGroup ?? null,
      ethnicity: thumbs.get(r.user_id as string)?.ethnicity ?? null,
    })),
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

// ── 오늘 등록된 관상 — 홈 그리드 (routes/_index.tsx) ──────────────────────────────

export interface DailyFacesFilter {
  todayOnly: boolean;
  optedOnly: boolean;
  myFaceOnly: boolean;
  limit?: number;
}

export interface DailyFaceRow {
  body: string;
  /** 행 소유자의 노출 허용 여부 — false 면 웹이 블러+캔버스로 가린다. */
  opted: boolean;
}

/**
 * daily_faces RPC (baseline §14) — 필터 통과한 metrics.body 원문 + opted 목록.
 * 실패는 빈 배열로 흡수 — 홈은 그리드 없이도 항상 렌더돼야 한다 (RPC 미배포
 * 상태의 배포 순서 문제 포함). opted 컬럼이 없는 구버전 RPC 응답은 전부
 * false(블러) 로 처리.
 */
export async function fetchDailyFaces(env: Env, f: DailyFacesFilter): Promise<DailyFaceRow[]> {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return [];
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/daily_faces`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
      },
      body: JSON.stringify({
        p_today_only: f.todayOnly,
        p_opted_only: f.optedOnly,
        p_my_face_only: f.myFaceOnly,
        p_limit: f.limit ?? 60,
      }),
    });
    if (!res.ok) {
      console.warn("[fetchDailyFaces] rpc status", res.status, await res.text());
      return [];
    }
    const rows = (await res.json()) as Array<{
      body: string | null;
      opted?: boolean;
    }>;
    return rows
      .filter((r): r is { body: string; opted?: boolean } => Boolean(r.body))
      .map((r) => ({ body: r.body, opted: r.opted === true }));
  } catch (e) {
    console.warn("[fetchDailyFaces] rpc threw", e);
    return [];
  }
}
