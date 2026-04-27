import type { MetricsRow, RawMetrics } from "./types";

const SELECT = "id,metrics_json,expires_at";

export async function fetchMetrics(env: Env, ids: string[]): Promise<MetricsRow[]> {
  const demoOnly = ids.every((id) => id.startsWith("00000000-0000-0000-0000-"));
  if (demoOnly) return ids.map(demoRow);

  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    console.warn("[share-host] SUPABASE_* env 미설정");
    return [];
  }

  const url =
    `${env.SUPABASE_URL}/rest/v1/metrics` +
    `?id=in.(${ids.map(encodeURIComponent).join(",")})&select=${SELECT}`;
  const res = await fetch(url, {
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
    },
  });
  if (!res.ok) {
    console.error("[share-host] supabase status", res.status, await res.text());
    return [];
  }
  const rows = (await res.json()) as Array<{
    id: string;
    metrics_json: string | null;
    expires_at: string | null;
  }>;

  const now = Date.now();
  const map = new Map<string, MetricsRow>();
  for (const r of rows) {
    if (!r.metrics_json) continue;
    if (r.expires_at && new Date(r.expires_at).getTime() <= now) continue;
    try {
      const raw = JSON.parse(r.metrics_json) as RawMetrics;
      map.set(r.id, { id: r.id, raw });
    } catch (e) {
      console.error("[share-host] metrics_json parse fail", r.id, e);
    }
  }
  return ids.map((id) => map.get(id)).filter((r): r is MetricsRow => Boolean(r));
}

function demoRow(id: string): MetricsRow {
  return {
    id,
    raw: {
      schemaVersion: 1,
      ethnicity: "eastAsian",
      gender: "female",
      ageGroup: "thirties",
      timestamp: "2026-04-27T00:00:00.000Z",
      source: "album",
      metrics: DEMO_RAW_METRICS,
      faceShape: "oval",
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
