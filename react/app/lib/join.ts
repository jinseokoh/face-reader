import type { SupabaseClient } from "@supabase/supabase-js";

/** 웹 캡처 body — 앱 FaceReadingReport.toBodyJson() 과 동일 키 계약. */
export type WebCaptureBody = {
  schemaVersion: 1;
  ethnicity: "eastAsian";
  gender: string;
  ageGroup: string;
  timestamp: string;
  source: "camera";
  thumbnailKey?: string;
  metrics: Record<string, number>;
  lateralMetrics: null;
  faceShape: "oval";
};

/** 저장 직전 마감 재확인 — 닫힌 그룹엔 write 하지 않는다. */
export async function isTeamOpen(
  sb: SupabaseClient,
  teamId: string,
): Promise<boolean> {
  const { data } = await sb
    .from("teams")
    .select("closed_at")
    .eq("id", teamId)
    .maybeSingle();
  return data != null && data.closed_at == null;
}

/** 캡처 프레임 200px JPEG → presign PUT. 실패해도 참여는 진행 (null). */
async function uploadThumbnail(id: string, blob: Blob): Promise<string | null> {
  try {
    const res = await fetch("/api/r2/presign", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prefix: "thumbnails", uuid: id }),
    });
    if (!res.ok) return null;
    const { uploadUrl, key } = (await res.json()) as {
      uploadUrl: string;
      key: string;
    };
    const put = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "content-type": "image/jpeg" },
      body: blob,
    });
    return put.ok ? key : null;
  } catch {
    return null;
  }
}

/**
 * metrics 저장 — 1 capture = 1 uuid (썸네일 key 와 metrics.id 공유).
 * is_my_face=true: 본인 얼굴 — 앱 rehydrate 가 내 관상으로 복원.
 * alias=nickname: 앱 saveMetrics 의 my-face 컨벤션과 동일.
 */
export async function saveCapture(
  sb: SupabaseClient,
  args: {
    uid: string;
    nickname: string;
    body: WebCaptureBody;
    thumb: Blob | null;
  },
): Promise<string | null> {
  const id = crypto.randomUUID();
  const key = args.thumb ? await uploadThumbnail(id, args.thumb) : null;
  const body: WebCaptureBody = key
    ? { ...args.body, thumbnailKey: key }
    : args.body;
  const { error } = await sb.from("metrics").upsert(
    {
      id,
      user_id: args.uid,
      body: JSON.stringify(body),
      alias: args.nickname || null,
      is_my_face: true,
    },
    { onConflict: "id" },
  );
  return error ? null : id;
}

/**
 * 그룹 합류 — 앱 joinTeam 과 동일 형태. (team_id,name) upsert:
 * 빈 슬롯이면 claim(RLS claim_slot), 새 이름이면 insert.
 * 점유된 이름이면 RLS 가 막아 error → "name-taken".
 */
export async function joinTeam(
  sb: SupabaseClient,
  args: { teamId: string; metricsId: string; name: string },
): Promise<"ok" | "name-taken" | "failed"> {
  const { error } = await sb.from("team_members").upsert(
    {
      team_id: args.teamId,
      metrics_id: args.metricsId,
      name: args.name,
      is_owner: false,
    },
    { onConflict: "team_id,name" },
  );
  if (!error) return "ok";
  // 23505 = unique violation, 42501 = RLS 거부 — 둘 다 "그 이름은 이미 찼다".
  return error.code === "23505" || error.code === "42501"
    ? "name-taken"
    : "failed";
}

/** sessionStorage stash 용 dataURL → Blob (미리보기→로그인 복귀 경로). */
export function dataUrlToBlob(u: string): Blob {
  const [, b64] = u.split(",");
  const bin = atob(b64);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return new Blob([arr], { type: "image/jpeg" });
}
