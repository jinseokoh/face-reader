import type { SupabaseClient } from "@supabase/supabase-js";

/** 웹 캡처 body — 앱 FaceReadingReport.toBodyJson() 과 동일 키 계약. */
export type WebCaptureBody = {
  schemaVersion: 1;
  /** Ethnicity enum name — 정보 확인에서 사용자가 선택 (default eastAsian). */
  ethnicity: string;
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

/** metrics.body(JSON 문자열)에서 썸네일 R2 키만 안전하게 꺼낸다. */
function thumbKeyOf(body: string | null): string | null {
  if (!body) return null;
  try {
    const parsed = JSON.parse(body) as { thumbnailKey?: string };
    return parsed.thumbnailKey ?? null;
  } catch {
    return null;
  }
}

/** 로그인 사용자의 기존 내 관상(is_my_face) — id + 썸네일 키. 없으면 null. */
export async function fetchMyFace(
  sb: SupabaseClient,
  uid: string,
): Promise<{ id: string; thumbnailKey: string | null } | null> {
  const { data } = await sb
    .from("metrics")
    .select("id,body")
    .eq("user_id", uid)
    .eq("is_my_face", true)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return null;
  return {
    id: data.id as string,
    thumbnailKey: thumbKeyOf(data.body as string | null),
  };
}

/**
 * 이 그룹에 내가 이미 참여했는지 — 내 metrics 중 하나가 멤버 슬롯을 점유하면
 * 그 슬롯 {name, metricsId, thumbnailKey} 를 반환. 아니면 null.
 */
export async function fetchMembership(
  sb: SupabaseClient,
  teamId: string,
  uid: string,
): Promise<{
  name: string;
  metricsId: string;
  thumbnailKey: string | null;
} | null> {
  const { data: mine } = await sb
    .from("metrics")
    .select("id,body")
    .eq("user_id", uid);
  const rows = mine ?? [];
  if (rows.length === 0) return null;
  const { data } = await sb
    .from("team_members")
    .select("name,metrics_id")
    .eq("team_id", teamId)
    .in(
      "metrics_id",
      rows.map((r) => r.id as string),
    )
    .limit(1)
    .maybeSingle();
  if (!data) return null;
  const mineRow = rows.find((r) => r.id === data.metrics_id);
  return {
    name: data.name as string,
    metricsId: data.metrics_id as string,
    thumbnailKey: thumbKeyOf((mineRow?.body as string | null) ?? null),
  };
}

/** 전체 멤버 명단(방장 먼저) — 미등록 멤버는 joined=false 빈 슬롯으로 렌더. */
export async function fetchRoster(
  sb: SupabaseClient,
  teamId: string,
): Promise<{ name: string; joined: boolean; thumbnailKey: string | null }[]> {
  const { data } = await sb
    .from("team_members")
    .select("name,metrics_id,is_owner,joined_at")
    .eq("team_id", teamId)
    .order("joined_at");
  const rows = data ?? [];
  // 등록 완료(사진) 먼저, 빈 슬롯 나중 — 각 그룹 안에선 방장 우선.
  const byOwner = [
    ...rows.filter((r) => r.is_owner),
    ...rows.filter((r) => !r.is_owner),
  ];
  const ordered = [
    ...byOwner.filter((r) => r.metrics_id != null),
    ...byOwner.filter((r) => r.metrics_id == null),
  ];
  const ids = ordered
    .filter((r) => r.metrics_id != null)
    .map((r) => r.metrics_id as string);
  const thumbs = new Map<string, string | null>();
  if (ids.length > 0) {
    const { data: ms } = await sb.from("metrics").select("id,body").in("id", ids);
    for (const m of ms ?? []) {
      thumbs.set(m.id as string, thumbKeyOf(m.body as string | null));
    }
  }
  return ordered.map((r) => ({
    name: r.name as string,
    joined: r.metrics_id != null,
    thumbnailKey:
      r.metrics_id != null
        ? (thumbs.get(r.metrics_id as string) ?? null)
        : null,
  }));
}

/**
 * 등록 완료 멤버들의 raw body(JSON 문자열) — 웹 즉석 결과표 계산용.
 * runCompat 이 JSON 문자열을 그대로 받으므로 파싱 없이 전달한다. 방장 먼저.
 */
export async function fetchMemberBodies(
  sb: SupabaseClient,
  teamId: string,
): Promise<{ name: string; body: string }[]> {
  const { data } = await sb
    .from("team_members")
    .select("name,metrics_id,is_owner,joined_at")
    .eq("team_id", teamId)
    .order("joined_at");
  const rows = (data ?? []).filter((r) => r.metrics_id != null);
  const ordered = [
    ...rows.filter((r) => r.is_owner),
    ...rows.filter((r) => !r.is_owner),
  ];
  const ids = ordered.map((r) => r.metrics_id as string);
  if (ids.length === 0) return [];
  const { data: ms } = await sb.from("metrics").select("id,body").in("id", ids);
  const bodies = new Map<string, string>();
  for (const m of ms ?? []) {
    if (m.body) bodies.set(m.id as string, m.body as string);
  }
  return ordered
    .filter((r) => bodies.has(r.metrics_id as string))
    .map((r) => ({
      name: r.name as string,
      body: bodies.get(r.metrics_id as string)!,
    }));
}

/** 그룹 등록 현황 — joined = metrics 등록 완료 슬롯 수, total = 전체 슬롯. */
export async function fetchProgress(
  sb: SupabaseClient,
  teamId: string,
): Promise<{ joined: number; total: number } | null> {
  const { data, error } = await sb
    .from("team_members")
    .select("metrics_id")
    .eq("team_id", teamId);
  if (error || !data) return null;
  return {
    joined: data.filter((r) => r.metrics_id != null).length,
    total: data.length,
  };
}

/**
 * metrics 저장 — 1 capture = 1 uuid (썸네일 key 와 metrics.id 공유).
 * is_my_face=true: 본인 얼굴 — 앱 rehydrate 가 내 관상으로 복원.
 * alias=nickname: 앱 saveMetrics 의 my-face 컨벤션과 동일.
 * [id] 를 주면 기존 내 관상 row 를 덮어쓴다 (재촬영 overwrite — my-face 1행 유지).
 */
export async function saveCapture(
  sb: SupabaseClient,
  args: {
    uid: string;
    nickname: string;
    body: WebCaptureBody;
    thumb: Blob | null;
    id?: string;
    /** 재촬영 시 교체 대상인 옛 썸네일 키 — 새 키 성립 후 즉시 삭제. */
    oldKey?: string | null;
    /** 옛 썸네일 삭제 API 인증용 (session.access_token). */
    accessToken?: string;
  },
): Promise<string | null> {
  const id = args.id ?? crypto.randomUUID();
  // 재촬영(overwrite)의 썸네일은 반드시 **새 키**로 — 같은 키에 재업로드하면
  // CDN·브라우저 캐시가 옛 사진을 계속 서빙한다 (키는 불변, 내용 교체 금지).
  // 신규 캡처는 1 capture = 1 uuid 원칙대로 metrics id 를 키에 쓴다.
  const thumbUuid = args.id ? crypto.randomUUID() : id;
  const key = args.thumb ? await uploadThumbnail(thumbUuid, args.thumb) : null;
  // 새 썸네일이 성립했으면 옛 객체를 즉시 삭제 (고아 0, cron 불필요).
  // body 가 아직 옛 키를 참조하는 upsert **이전** 시점이라 서버 소유 검증 통과.
  // 실패해도 참여 흐름은 계속 (고아 1개 감수).
  if (key && args.oldKey && args.accessToken) {
    await fetch("/api/r2/delete", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${args.accessToken}`,
      },
      body: JSON.stringify({ key: args.oldKey }),
    }).catch(() => {});
  }
  // 새 업로드 실패 시엔 옛 키를 보존해 아바타가 깨지지 않게 한다.
  const body: WebCaptureBody = key
    ? { ...args.body, thumbnailKey: key }
    : args.oldKey
      ? { ...args.body, thumbnailKey: args.oldKey }
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
  if (error) return null;
  // 내 관상 불변식 안전망 — is_my_face=true 는 사용자당 1행 (앱 saveMetrics
  // 와 동일). 참여 슬롯 row 가 my-face row 와 다른 잔재 케이스에서 true 2행이
  // 되지 않게, 이번 row 외의 true 행을 일반 카드로 강등. 실패해도 참여는 계속.
  await sb
    .from("metrics")
    .update({ is_my_face: false })
    .eq("user_id", args.uid)
    .eq("is_my_face", true)
    .neq("id", id);
  return id;
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
