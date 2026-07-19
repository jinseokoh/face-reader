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
): Promise<{
  id: string;
  thumbnailKey: string | null;
  alias: string | null;
} | null> {
  const { data } = await sb
    .from("metrics")
    .select("id,body,alias")
    .eq("user_id", uid)
    .eq("is_my_face", true)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return null;
  return {
    id: data.id as string,
    thumbnailKey: thumbKeyOf(data.body as string | null),
    alias: (data.alias as string | null) ?? null,
  };
}

/** python 나이(정수) → 앱 decade 라벨 ("10s".."70s", 70+ 는 70s 로 클램프). */
function ageToGroup(age: number): string {
  const decade = Math.min(Math.max(Math.floor(age / 10) * 10, 10), 70);
  return `${decade}s`;
}

/**
 * DeepFace 추정 — 앱과 동일 경로: 캡처 프레임을 R2 temp/ 에 presign PUT 후
 * Worker 프록시(/api/analyze)로 python 을 호출한다 (python 이 temp 즉시 삭제).
 * 실패 시 null — 확인 페이지가 수동 선택 fallback 으로 동작.
 */
export async function estimateDemographics(frame: Blob): Promise<{
  gender: string;
  ageGroup: string;
  ethnicity: string;
} | null> {
  try {
    const uuid = crypto.randomUUID();
    const pres = await fetch("/api/r2/presign", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prefix: "temp", uuid }),
    });
    if (!pres.ok) return null;
    const { uploadUrl, key, token } = (await pres.json()) as {
      uploadUrl: string;
      key: string;
      token?: string;
    };
    if (!token) return null;
    const put = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "content-type": "image/jpeg" },
      body: frame,
    });
    if (!put.ok) return null;
    const res = await fetch("/api/analyze", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ key, token }),
    });
    if (!res.ok) return null;
    const out = (await res.json()) as {
      age: number;
      gender: string;
      ethnicity: string;
    };
    if (!out.gender || !out.ethnicity || typeof out.age !== "number") {
      return null;
    }
    return {
      gender: out.gender,
      ageGroup: ageToGroup(out.age),
      ethnicity: out.ethnicity,
    };
  } catch {
    return null;
  }
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
    /** 확인 페이지에서 입력한 이름 — 없으면 nickname fallback. */
    alias?: string | null;
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
      alias: args.alias?.trim() || args.nickname || null,
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

// ── Chemistry Battle 계약 (Plan 1 서버) ─────────────────────────────
export type BattleStatus = "recruiting" | "revealing" | "completed" | "expired";

export type BattlePayload = {
  players: { slot: number; name: string; gender: string }[];
  pairs: { a: number; b: number; band: number }[]; // 정렬 = 순위, band 0~3
  best: { a: number; b: number; score: number };
};

export type BattleRow = {
  id: string;
  ownerId: string | null;
  title: string;
  isPrivate: boolean;
  maxPlayers: number;
  ageMin: number | null;
  ageMax: number | null;
  roomKind: "all" | "match";
  thumbOpen: boolean;
  status: BattleStatus;
  chemistrySnapshot: Record<string, unknown> | null;
  resultPayload: BattlePayload | null;
};

export type RosterEntry = {
  userId: string;
  slotNo: number;
  isOwner: boolean;
  nickname: string;
  gender: string;
};

const BATTLE_COLS =
  "id, owner_id, title, is_private, max_players, age_min, age_max, room_kind, thumb_open, status, chemistry_snapshot, result_payload";

function rowToBattle(r: Record<string, unknown>): BattleRow {
  return {
    id: r.id as string,
    ownerId: (r.owner_id as string) ?? null,
    title: r.title as string,
    isPrivate: (r.is_private as boolean) ?? false,
    maxPlayers: r.max_players as number,
    ageMin: (r.age_min as number) ?? null,
    ageMax: (r.age_max as number) ?? null,
    roomKind: r.room_kind as "all" | "match",
    thumbOpen: r.thumb_open as boolean,
    status: r.status as BattleStatus,
    chemistrySnapshot:
      (r.chemistry_snapshot as Record<string, unknown>) ?? null,
    resultPayload: (r.result_payload as BattlePayload) ?? null,
  };
}

/** 이성방 조인 confirm/초대장 사진 공개 계약 문구 (UX §E.1 — 웹도 동일 카피). */
export function photoConsentText(roomKind: "all" | "match"): string {
  return roomKind === "match"
    ? "베스트 매칭이 되면 상대에게 내 사진이 공개되고, 서로 동의하면 1:1 채팅이 열립니다"
    : "베스트 케미로 뽑히면 상대에게 내 사진이 공개됩니다";
}

/** 이성방 — 성별 남은 자리 수 (roster gender 카운트 기준, 0 미만 표시 방지). */
export function remainingGenderSlots(
  roster: { gender: string }[],
  maxPlayers: number,
  gender: "male" | "female",
): number {
  const per = Math.floor(maxPlayers / 2);
  const count = roster.filter((r) => r.gender === gender).length;
  return Math.max(0, Math.min(per, per - count));
}

export async function fetchBattle(
  sb: SupabaseClient,
  battleId: string,
): Promise<BattleRow | null> {
  const { data } = await sb
    .from("teams")
    .select(BATTLE_COLS)
    .eq("id", battleId)
    .maybeSingle();
  return data ? rowToBattle(data) : null;
}

export async function fetchBattleRoster(
  sb: SupabaseClient,
  battleId: string,
): Promise<RosterEntry[]> {
  const { data } = await sb
    .from("team_roster")
    .select("user_id, slot_no, is_owner, nickname, gender")
    .eq("team_id", battleId)
    .order("slot_no", { ascending: true });
  return (data ?? []).map((r) => ({
    userId: r.user_id as string,
    slotNo: r.slot_no as number,
    isOwner: r.is_owner as boolean,
    nickname: (r.nickname as string) ?? "참가자",
    gender: r.gender as string,
  }));
}

/** join_team RPC — 성공 'ok', 실패는 서버 에러 코드 문자열 그대로. */
export async function joinBattle(
  sb: SupabaseClient,
  battleId: string,
  password?: string,
): Promise<string> {
  const { error } = await sb.rpc("join_team", {
    p_team_id: battleId,
    ...(password ? { p_password: password } : {}),
  });
  if (!error) return "ok";
  const known = [
    "AUTH_REQUIRED", "NOT_FOUND", "NOT_RECRUITING", "BAD_PASSWORD",
    "NO_MY_FACE", "AGE_NOT_ALLOWED", "GENDER_FULL", "FULL", "ALREADY_JOINED",
  ];
  return known.find((k) => error.message.includes(k)) ?? "FAILED";
}

export async function submitBattleResult(
  sb: SupabaseClient,
  battleId: string,
  payload: BattlePayload,
): Promise<void> {
  // first-writer-wins — 실패(후착·비참가자) 무해.
  await sb.rpc("submit_team_result", {
    p_team_id: battleId,
    p_payload: payload,
  });
}

/** 로비 라이브 — teams UPDATE + team_members 변화 신호. 수신 시 refetch. */
export function watchBattle(
  sb: SupabaseClient,
  battleId: string,
  onChange: () => void,
) {
  return sb
    .channel(`battle:${battleId}`)
    .on(
      "postgres_changes",
      { event: "UPDATE", schema: "public", table: "teams",
        filter: `id=eq.${battleId}` },
      onChange,
    )
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "team_members",
        filter: `team_id=eq.${battleId}` },
      onChange,
    )
    .subscribe();
}

/** snapshot({user_id: body, blocked?: [[slot,slot]]}) + roster → runBattle.
 *  blocked = 시작 시 동결된 차단 쌍 — 엔진이 상한 60점(형극난조)으로 눌러
 *  베스트에서 제외한다. 입력 부족 시 null. */
export function computeBattlePayload(
  roster: RosterEntry[],
  snapshot: Record<string, unknown>,
  roomKind: "all" | "match",
): BattlePayload | null {
  const players = roster
    .filter((r) => snapshot[r.userId])
    .map((r) => ({
      slot: r.slotNo,
      name: r.nickname,
      gender: r.gender,
      body: snapshot[r.userId],
    }));
  if (players.length < 2) return null;
  const blocked = Array.isArray(snapshot.blocked) ? snapshot.blocked : [];
  return JSON.parse(
    globalThis.runBattle(JSON.stringify({ roomKind, players, blocked })),
  ) as BattlePayload;
}
