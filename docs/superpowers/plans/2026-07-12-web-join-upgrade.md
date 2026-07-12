# 웹 풀 참여 (/g/:id) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱 미설치자가 `facely.kr/g/{id}`에서 카카오 로그인 → 슬롯 선택 → 정면 캡처 → 그룹 참여(전원 등록 카운트)까지 완료한다.

**Architecture:** react/ 단독 변경. supabase-js 브라우저 클라이언트(PKCE Kakao OAuth)로 앱과 같은 `auth.users` 계정을 쓰고, 기존 RLS(`team_members_claim_slot`/`insert`)와 presign API로 metrics+썸네일+멤버 행을 쓴다. CameraTeaser를 단계형 JoinWizard로 대체.

**Tech Stack:** React Router 7 (Cloudflare Workers SSR), @supabase/supabase-js, @mediapipe/tasks-vision, shared face_engine.js (dart→JS)

## Global Constraints

- 서버 스키마·RLS·Worker API 변경 0. Flutter 변경 0.
- react 디자인: system font, 5단 size(24/16/14/13/12), 4색(`#1a1a1a`/`#666`/`#c44`/`#f7f7f8`)+흰색. (react/CLAUDE.md)
- body JSON 계약: `{schemaVersion:1, ethnicity:"eastAsian", gender, ageGroup, timestamp, source:"camera", thumbnailKey?, metrics, lateralMetrics:null, faceShape:"oval"}` — 앱 `toBodyJson()`과 동일 키.
- metrics 행: `{id, user_id, body, alias: nickname, is_my_face: true}` upsert onConflict `id`.
- team_members 행: `{team_id, metrics_id, name, is_owner:false}` upsert onConflict `team_id,name`.
- 1 capture = 1 uuid (`crypto.randomUUID()` 한 번, 썸네일 key·metrics.id 공유).
- disabled 은닉 금지 — 버튼 항상 가시, 미충족 시 인라인 안내.
- 테스트 인프라 없음(react/) — 검증은 `pnpm typecheck` + `pnpm dev` 스모크 + 실기기.
- typecheck 기왕 결함 1건(contact.tsx `WEB3FORMS_ACCESS_KEY`)은 무시 — 신규 오류 0 기준.
- 모든 명령은 `/Users/chuck/Code/face/react` 에서 실행 (cwd가 매 호출 리셋됨).

**운영 선행 조건 (형이 Supabase 대시보드에서 1회):** Auth → URL Configuration → Redirect URLs에 `https://facely.kr/g/*`, `http://localhost:5173/*` 추가. 없으면 카카오 로그인 후 복귀가 거부된다.

---

### Task 1: supabase-js 의존성 + `app/lib/auth.ts`

**Files:**
- Modify: `react/package.json` (pnpm add)
- Create: `react/app/lib/auth.ts`

**Interfaces:**
- Produces: `getSupabase(url: string, anonKey: string): SupabaseClient` (lazy singleton),
  `loginWithKakao(sb: SupabaseClient): Promise<void>` (redirect),
  `fetchNickname(sb: SupabaseClient, uid: string): Promise<string>`,
  `cleanAuthParams(): boolean` (URL의 ?code= 제거, 있었으면 true)

- [ ] **Step 1: 의존성 설치**

```bash
cd /Users/chuck/Code/face/react && pnpm add @supabase/supabase-js
```

- [ ] **Step 2: auth.ts 작성**

```ts
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * 브라우저 전용 Supabase 클라이언트 — 앱과 같은 프로젝트·같은 auth.users.
 * PKCE flow: 카카오 → 같은 /g/{id} 로 복귀, detectSessionInUrl 이 ?code= 교환.
 * anon key 는 공개키 (loader 가 내려줌).
 */
let client: SupabaseClient | null = null;

export function getSupabase(url: string, anonKey: string): SupabaseClient {
  if (!client) {
    client = createClient(url, anonKey, {
      auth: { flowType: "pkce", detectSessionInUrl: true, persistSession: true },
    });
  }
  return client;
}

/** 카카오 OAuth 시작 — 현재 페이지(쿼리 제거)로 복귀하도록 redirect. */
export async function loginWithKakao(sb: SupabaseClient): Promise<void> {
  const url = new URL(window.location.href);
  await sb.auth.signInWithOAuth({
    provider: "kakao",
    options: { redirectTo: `${url.origin}${url.pathname}` },
  });
}

/** users.nickname (self-read RLS) → 없으면 kakao user_metadata fallback. */
export async function fetchNickname(
  sb: SupabaseClient,
  uid: string,
): Promise<string> {
  const { data } = await sb
    .from("users")
    .select("nickname")
    .eq("id", uid)
    .maybeSingle();
  if (data?.nickname) return data.nickname as string;
  const { data: u } = await sb.auth.getUser();
  const meta = (u.user?.user_metadata ?? {}) as Record<string, unknown>;
  return (meta.name as string) ?? (meta.nickname as string) ?? "";
}

/** OAuth 복귀 흔적(?code=) 을 주소창에서 제거. 있었으면 true (로그인 복귀 판별용). */
export function cleanAuthParams(): boolean {
  const url = new URL(window.location.href);
  if (!url.searchParams.has("code")) return false;
  url.searchParams.delete("code");
  window.history.replaceState(null, "", url.pathname + url.search);
  return true;
}
```

- [ ] **Step 3: typecheck**

```bash
cd /Users/chuck/Code/face/react && pnpm typecheck
```
Expected: 신규 오류 0 (contact.tsx 기왕 1건만).

- [ ] **Step 4: Commit**

```bash
git add react/package.json react/pnpm-lock.yaml react/app/lib/auth.ts
git commit -m "feat(web): supabase-js 카카오 OAuth 브라우저 클라이언트"
```

---

### Task 2: `app/lib/join.ts` — 저장 파이프라인

**Files:**
- Create: `react/app/lib/join.ts`

**Interfaces:**
- Consumes: Task 1의 SupabaseClient
- Produces:
  `type WebCaptureBody`,
  `isTeamOpen(sb, teamId): Promise<boolean>`,
  `saveCapture(sb, args): Promise<string | null>` (metrics id 반환),
  `joinTeam(sb, args): Promise<"ok" | "name-taken" | "failed">`,
  `dataUrlToBlob(u: string): Blob`

- [ ] **Step 1: join.ts 작성**

```ts
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
```

- [ ] **Step 2: typecheck + Commit**

```bash
cd /Users/chuck/Code/face/react && pnpm typecheck
git add react/app/lib/join.ts
git commit -m "feat(web): 웹 캡처 저장·그룹 합류 파이프라인 (presign→metrics→team_members)"
```

---

### Task 3: TeamShowcase 슬롯 상세 + loader config + 초대장 칩

**Files:**
- Modify: `react/app/lib/supabase.ts` (TeamShowcase.memberNames → members)
- Modify: `react/app/routes/g.$id.tsx` (loader + meta + Invite)
- Modify: `react/app/app.css` (초대장 칩 클래스)

**Interfaces:**
- Produces: `TeamShowcase.members: { name: string; joined: boolean; isOwner: boolean }[]`
  (memberNames 필드 삭제 — 소비처는 members 로 파생),
  loader 응답에 `supabaseUrl: string`, `supabaseAnonKey: string`

- [ ] **Step 1: supabase.ts 수정** — `TeamShowcase` 타입에서 `memberNames: string[]` 를 다음으로 교체:

```ts
  // 초대장·위저드용 슬롯 상세 (방장 먼저) — joined = metrics 등록 완료.
  members: { name: string; joined: boolean; isOwner: boolean }[];
```

`fetchTeam` 의 `names` 산출부를 교체:

```ts
  const ordered = [
    ...members.filter((m) => m.is_owner),
    ...members.filter((m) => !m.is_owner),
  ];
  const memberList = ordered.map((m) => ({
    name: m.name,
    joined: m.metrics_id != null,
    isOwner: m.is_owner,
  }));
```

return 의 `memberNames: names,` → `members: memberList,`.

- [ ] **Step 2: g.$id.tsx loader/meta 수정** — loader 반환 객체에 추가:

```ts
    // 웹 카카오 로그인·참여용 공개 config (anon key 는 공개키).
    supabaseUrl: env.SUPABASE_URL ?? "",
    supabaseAnonKey: env.SUPABASE_ANON_KEY ?? "",
```

meta 의 `t.memberNames.length` → `t.members.length`.

- [ ] **Step 3: Invite 컴포넌트 교체** — 시그니처를 `{ title, members }: { title: string; members: TeamShowcase["members"] }` 로 바꾸고 칩 렌더를:

```tsx
      {members.length > 0 && (
        <div className="invite-chips">
          {members.map((m, i) => (
            <span
              key={i}
              className={m.joined ? "invite-chip" : "invite-chip invite-chip--wait"}
            >
              {m.name}
              {m.joined ? " ✓" : ""}
            </span>
          ))}
        </div>
      )}
```

부제도 등록 현황으로: `{members.filter((m) => m.joined).length}명 등록 · 당신 자리가 비어 있어요`.
호출부 `<Invite title={team.title} names={team.memberNames} />` → `<Invite title={team.title} members={team.members} />`.
기존 `Chip` 함수와 inline 칩 스타일 객체는 이 교체로 고아가 되면 제거.

- [ ] **Step 4: app.css 에 초대장 칩 클래스 추가** (`/* ─── CTA ─── */` 위에):

```css
/* ─── /g/:id 초대장·참여 위저드 ─── */
.invite-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: center;
  margin-top: 16px;
}
.invite-chip {
  background: #fff;
  border: 1px solid #ddd;
  border-radius: 10px;
  padding: 6px 14px;
  font-size: 14px;
  color: var(--ink);
}
.invite-chip--wait {
  color: var(--caption);
  border-style: dashed;
}
```

- [ ] **Step 5: typecheck + Commit**

CameraTeaser 가 아직 memberNames 를 안 쓰는지 확인 (`team.owner` 만 사용 — OK).

```bash
cd /Users/chuck/Code/face/react && pnpm typecheck
git add react/app/lib/supabase.ts react/app/routes/g.\$id.tsx react/app/app.css
git commit -m "feat(web): 초대장 슬롯 등록 현황 + supabase 공개 config 전달"
```

---

### Task 4: `.join-*` CSS

**Files:**
- Modify: `react/app/app.css` (Task 3 블록에 이어서)

**Interfaces:**
- Produces: JoinWizard(Task 5)가 쓰는 클래스: `.join`, `.join-q`, `.join-sub`, `.join-notice`, `.join-chips`, `.join-chip`, `.join-chip--on`, `.join-chip--taken`, `.join-input`, `.join-btn`, `.join-btn--ghost`, `.join-video`, `.join-score`, `.join-badge`

- [ ] **Step 1: 클래스 추가** (Task 3에서 만든 `/g/:id` 블록 안):

```css
.join {
  text-align: center;
  padding: 16px;
  margin-top: 8px;
}
.join-q {
  font-size: 16px;
  color: var(--ink);
  margin: 0 0 4px;
}
.join-sub {
  font-size: 13px;
  color: var(--caption);
  margin: 8px 0 0;
}
.join-notice {
  font-size: 13px;
  color: var(--accent);
  margin: 8px 0 0;
}
.join-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: center;
  margin-top: 8px;
}
.join-chip {
  background: #fff;
  color: var(--ink);
  border: 1px solid #ddd;
  border-radius: 10px;
  padding: 10px 16px;
  font-size: 14px;
  min-height: 44px;
  cursor: pointer;
  font-family: inherit;
}
.join-chip--on {
  border-color: var(--ink);
  font-weight: 600;
}
.join-chip--taken {
  color: var(--caption);
  border-style: dashed;
  cursor: default;
}
.join-input {
  font: inherit;
  font-size: 14px;
  padding: 10px 12px;
  border: 1px solid #ddd;
  border-radius: 8px;
  background: #fff;
  color: var(--ink);
  width: 100%;
  max-width: 280px;
  margin-top: 8px;
  text-align: center;
}
.join-input:focus {
  outline: none;
  border-color: var(--ink);
}
.join-btn {
  display: inline-block;
  background: var(--ink);
  color: #fff;
  border: none;
  border-radius: 12px;
  padding: 12px 20px;
  font-size: 16px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  margin-top: 16px;
  text-decoration: none;
}
.join-btn--ghost {
  display: inline-block;
  background: none;
  border: none;
  color: var(--caption);
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
  margin-top: 12px;
  text-decoration: underline;
}
.join-video {
  width: 100%;
  max-width: 320px;
  border-radius: 12px;
  background: #fff;
  transform: scaleX(-1);
}
.join-score {
  font-size: 24px;
  color: var(--accent);
  font-weight: 700;
  margin-top: 8px;
}
.join-badge {
  display: inline-block;
  background: #fff;
  border: 1px solid var(--ink);
  border-radius: 999px;
  padding: 6px 16px;
  font-size: 14px;
  font-weight: 600;
  color: var(--ink);
  margin-bottom: 12px;
}
```

- [ ] **Step 2: Commit**

```bash
git add react/app/app.css
git commit -m "feat(web): 참여 위저드 CSS — 흰 칩 + 항상 가시 버튼 (배경 은닉 폐기)"
```

---

### Task 5: JoinWizard + 배선 + CameraTeaser 삭제

**Files:**
- Create: `react/app/components/JoinWizard.tsx`
- Modify: `react/app/routes/g.$id.tsx` (import·렌더 교체)
- Delete: `react/app/components/CameraTeaser.tsx`

**Interfaces:**
- Consumes: Task 1 `getSupabase/loginWithKakao/fetchNickname/cleanAuthParams`, Task 2 `WebCaptureBody/isTeamOpen/saveCapture/joinTeam/dataUrlToBlob`, Task 3 `TeamShowcase.members`, Task 4 CSS
- Produces: `<JoinWizard team appOpenUrl appStoreUrl playStoreUrl supabaseUrl supabaseAnonKey />`

핵심 설계 (스펙 §3.2·§3.3):
- `<video>` 는 컴포넌트 생애 내내 마운트(카메라 단계 외 `display:none`) — ref race 제거.
- MediaPipe+engine preload 는 **info 단계 진입 시** 시작 (`preloadRef` 1회).
- 캡처 순간: ① canvas 200×200 미러 crop JPEG(q0.8) ② stopCamera ③ 분기.
- 미리보기 경로: 결과에서 [이 결과로 그룹 참여하기] → 세션 있으면 name 단계로, 없으면 sessionStorage stash 후 카카오 redirect → 복귀 시 stash 복원 → name 단계.
- 저장 순서: isTeamOpen → (metricsId 없으면) saveCapture → joinTeam. name-taken 이면 metricsId 보존한 채 name 단계 복귀.
- 20s 무검출 타이머 → 힌트 갱신. 실패 taxonomy 3종 한국어.

- [ ] **Step 1: JoinWizard.tsx 작성** (전문):

```tsx
import { useEffect, useRef, useState } from "react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import type { TeamShowcase } from "../lib/supabase";
import { detectInApp, openInExternalBrowser, type InApp } from "../lib/inapp";
import {
  cleanAuthParams,
  fetchNickname,
  getSupabase,
  loginWithKakao,
} from "../lib/auth";
import {
  dataUrlToBlob,
  isTeamOpen,
  joinTeam,
  saveCapture,
  type WebCaptureBody,
} from "../lib/join";

/**
 * /g/:id 참여 위저드 — 앱 미설치자가 브라우저에서 그룹 참여를 끝까지 완료한다.
 * entry → (kakao) → name → info → camera → saving → done
 * 미리보기 경로: entry → info → camera → done(teaser) → [참여] → stash → kakao → name…
 * 스펙: docs/superpowers/specs/2026-07-12-web-join-upgrade-design.md
 */

// package.json 의 @mediapipe/tasks-vision 과 같은 버전 유지.
const MP_VERSION = "0.10.35";
const MP_WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}/wasm`;
const MP_MODEL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

const STASH_KEY = "facely:pendingJoin";
const NO_FACE_TIMEOUT_MS = 20_000;

type Stage =
  | "entry"
  | "name"
  | "info"
  | "camera"
  | "saving"
  | "done"
  | "error";

type Teaser =
  | { kind: "pair"; total: number; labelKo: string; ownerName: string }
  | { kind: "solo"; primaryLabel: string; catchphrase: string };

type Stash = { teamId: string; body: WebCaptureBody; thumb: string | null };

const GENDERS = [
  { v: "male", ko: "남성" },
  { v: "female", ko: "여성" },
];
const AGES = [
  { v: "10s", ko: "10대" },
  { v: "20s", ko: "20대" },
  { v: "30s", ko: "30대" },
  { v: "40s", ko: "40대" },
  { v: "50s", ko: "50대" },
  { v: "60s", ko: "60대+" },
];

export function JoinWizard({
  team,
  appOpenUrl,
  appStoreUrl,
  playStoreUrl,
  supabaseUrl,
  supabaseAnonKey,
}: {
  team: TeamShowcase;
  appOpenUrl: string;
  appStoreUrl: string;
  playStoreUrl: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
}) {
  const [stage, setStage] = useState<Stage>("entry");
  const [previewOnly, setPreviewOnly] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [nickname, setNickname] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [gender, setGender] = useState<string | null>(null);
  const [age, setAge] = useState<string | null>(null);
  const [teaser, setTeaser] = useState<Teaser | null>(null);
  const [joined, setJoined] = useState(false);
  const [hint, setHint] = useState("얼굴을 화면 안에 맞춰 주세요");
  const [notice, setNotice] = useState("");
  const [errorMsg, setErrorMsg] = useState("");
  const [inApp, setInApp] = useState<InApp>(null);

  const sbRef = useRef<SupabaseClient | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const landmarkerRef = useRef<unknown>(null);
  const preloadRef = useRef<Promise<void> | null>(null);
  const rafRef = useRef<number | null>(null);
  const hitsRef = useRef(0);
  const doneRef = useRef(false);
  const noFaceTimerRef = useRef<number | null>(null);
  // 캡처 산출물 — 단계 넘어도 유지 (name-taken 재시도 시 metrics 재사용).
  const bodyRef = useRef<WebCaptureBody | null>(null);
  const thumbRef = useRef<Blob | null>(null);
  const metricsIdRef = useRef<string | null>(null);

  const sb = () => {
    if (!sbRef.current) sbRef.current = getSupabase(supabaseUrl, supabaseAnonKey);
    return sbRef.current;
  };

  // 마운트: 인앱 감지 + 세션 복구 + OAuth 복귀/stash 처리.
  useEffect(() => {
    setInApp(detectInApp());
    if (!supabaseUrl || !supabaseAnonKey) return;
    const cameFromLogin = cleanAuthParams();
    const client = sb();
    const { data: sub } = client.auth.onAuthStateChange((_e, s) => {
      setSession(s);
      if (s) void fetchNickname(client, s.user.id).then(setNickname);
    });
    void client.auth.getSession().then(({ data }) => {
      setSession(data.session);
      if (data.session) {
        void fetchNickname(client, data.session.user.id).then((n) => {
          setNickname(n);
          setNameInput((cur) => cur || n);
        });
        // 미리보기→로그인 복귀: 캡처를 복원하고 이름 선택으로 점프.
        const raw = sessionStorage.getItem(STASH_KEY);
        if (raw) {
          try {
            const stash = JSON.parse(raw) as Stash;
            if (stash.teamId === team.id) {
              bodyRef.current = stash.body;
              thumbRef.current = stash.thumb ? dataUrlToBlob(stash.thumb) : null;
              setGender(stash.body.gender);
              setAge(stash.body.ageGroup);
              setPreviewOnly(false);
              setStage("name");
            }
          } catch {
            /* 손상된 stash 는 버림 */
          }
          sessionStorage.removeItem(STASH_KEY);
        } else if (cameFromLogin) {
          // 참여하기로 로그인만 하고 온 경우 — 바로 이름 선택.
          setStage("name");
        }
      }
    });
    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => () => stopCamera(), []);

  function stopCamera() {
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    if (noFaceTimerRef.current != null) clearTimeout(noFaceTimerRef.current);
    noFaceTimerRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  function fail(msg: string) {
    stopCamera();
    setErrorMsg(msg);
    setStage("error");
  }

  /** MediaPipe + shared engine 로드 — info 단계 진입 시 1회 백그라운드. */
  function preloadDetector(): Promise<void> {
    if (!preloadRef.current) {
      preloadRef.current = (async () => {
        await import("../lib/shared/face_engine.js");
        const { FaceLandmarker, FilesetResolver } = await import(
          "@mediapipe/tasks-vision"
        );
        const fileset = await FilesetResolver.forVisionTasks(MP_WASM);
        landmarkerRef.current = await FaceLandmarker.createFromOptions(
          fileset,
          {
            baseOptions: { modelAssetPath: MP_MODEL },
            runningMode: "VIDEO",
            numFaces: 1,
          },
        );
      })();
    }
    return preloadRef.current;
  }

  async function startCamera() {
    doneRef.current = false;
    hitsRef.current = 0;
    setHint("얼굴 인식 준비 중…");
    setStage("camera");
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
        audio: false,
      });
    } catch {
      fail("카메라를 열 수 없어요. 브라우저의 카메라 권한을 허용해 주세요.");
      return;
    }
    streamRef.current = stream;
    const video = videoRef.current;
    if (!video) {
      fail("카메라 화면을 준비하지 못했어요. 새로고침 후 다시 시도해 주세요.");
      return;
    }
    video.srcObject = stream;
    await video.play().catch(() => {});
    try {
      await preloadDetector();
    } catch {
      fail("얼굴 인식 모듈을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    setHint("얼굴을 화면 안에 맞춰 주세요");
    noFaceTimerRef.current = window.setTimeout(
      () => setHint("얼굴이 안 보여요. 밝은 곳에서 정면을 맞춰 주세요."),
      NO_FACE_TIMEOUT_MS,
    );
    loop();
  }

  function loop() {
    const video = videoRef.current;
    const landmarker = landmarkerRef.current as {
      detectForVideo: (
        v: HTMLVideoElement,
        t: number,
      ) => { faceLandmarks: { x: number; y: number }[][] };
    } | null;
    if (!video || !landmarker || doneRef.current) return;
    if (video.readyState >= 2) {
      const res = landmarker.detectForVideo(video, performance.now());
      const face = res.faceLandmarks?.[0];
      if (face && face.length >= 468) {
        hitsRef.current += 1;
        setHint("좋아요! 잠시만 그대로…");
        if (hitsRef.current >= 3) {
          doneRef.current = true;
          capture(face.map((p) => [p.x, p.y]));
          return;
        }
      } else {
        hitsRef.current = 0;
        setHint("얼굴을 화면 안에 맞춰 주세요");
      }
    }
    rafRef.current = requestAnimationFrame(loop);
  }

  /** 검출 순간의 video 프레임 → 200×200 미러 crop JPEG (앱 썸네일과 동급). */
  function frameToThumb(video: HTMLVideoElement): Promise<Blob | null> {
    const side = Math.min(video.videoWidth, video.videoHeight);
    if (!side) return Promise.resolve(null);
    const sx = (video.videoWidth - side) / 2;
    const sy = (video.videoHeight - side) / 2;
    const c = document.createElement("canvas");
    c.width = 200;
    c.height = 200;
    const ctx = c.getContext("2d");
    if (!ctx) return Promise.resolve(null);
    ctx.translate(200, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(video, sx, sy, side, side, 0, 0, 200, 200);
    return new Promise((r) => c.toBlob(r, "image/jpeg", 0.8));
  }

  async function capture(points: number[][]) {
    const video = videoRef.current;
    const thumb = video ? await frameToThumb(video) : null;
    stopCamera();
    let body: WebCaptureBody;
    try {
      const metrics = JSON.parse(
        globalThis.runMetrics(JSON.stringify(points)),
      ) as Record<string, number>;
      body = {
        schemaVersion: 1,
        ethnicity: "eastAsian",
        gender: gender ?? "male",
        ageGroup: age ?? "30s",
        timestamp: new Date().toISOString(),
        source: "camera",
        metrics,
        lateralMetrics: null,
        faceShape: "oval",
      };
    } catch {
      fail("측정값을 계산하지 못했어요. 다시 시도해 주세요.");
      return;
    }
    bodyRef.current = body;
    thumbRef.current = thumb;
    setTeaser(computeTeaser(body));
    if (previewOnly) {
      setJoined(false);
      setStage("done");
    } else {
      await runSave();
    }
  }

  /** 저장 시퀀스: 마감 재확인 → metrics(1회) → 합류. */
  async function runSave() {
    const body = bodyRef.current;
    const s = session;
    if (!body || !s) {
      fail("세션이 만료됐어요. 다시 로그인해 주세요.");
      return;
    }
    setStage("saving");
    const client = sb();
    if (!(await isTeamOpen(client, team.id))) {
      fail("모집이 종료된 그룹입니다.");
      return;
    }
    if (!metricsIdRef.current) {
      metricsIdRef.current = await saveCapture(client, {
        uid: s.user.id,
        nickname,
        body,
        thumb: thumbRef.current,
      });
    }
    if (!metricsIdRef.current) {
      fail("등록에 실패했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    const name = nameInput.trim();
    const r = await joinTeam(client, {
      teamId: team.id,
      metricsId: metricsIdRef.current,
      name,
    });
    if (r === "name-taken") {
      setNotice("방금 다른 사람이 그 자리에 들어갔어요. 다른 이름으로 참여해 주세요.");
      setStage("name");
      return;
    }
    if (r === "failed") {
      fail("참여에 실패했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    setJoined(true);
    setStage("done");
  }

  function computeTeaser(body: WebCaptureBody): Teaser | null {
    try {
      const json = JSON.stringify(body);
      if (team.owner) {
        const c = JSON.parse(
          globalThis.runCompat(json, JSON.stringify(team.owner.raw)),
        ) as { total: number; labelKo: string };
        return {
          kind: "pair",
          total: Math.round(c.total),
          labelKo: c.labelKo,
          ownerName: team.owner.name,
        };
      }
      const s = JSON.parse(globalThis.runEngine(json)) as {
        primaryLabel: string;
        catchphrase: string;
      };
      return {
        kind: "solo",
        primaryLabel: s.primaryLabel,
        catchphrase: s.catchphrase,
      };
    } catch {
      return null;
    }
  }

  // ── 액션 핸들러 ──────────────────────────────────────────────────────
  function onJoinStart() {
    setNotice("");
    if (session) setStage("name");
    else void loginWithKakao(sb());
  }

  function onPreviewStart() {
    setPreviewOnly(true);
    setStage("info");
  }

  function onNameNext() {
    const name = nameInput.trim();
    if (!name) {
      setNotice("이름을 입력하거나 자리를 골라 주세요.");
      return;
    }
    const taken = team.members.some((m) => m.joined && m.name === name);
    if (taken) {
      setNotice("같은 그룹내에 동일이름은 허용하지 않습니다.");
      return;
    }
    setNotice("");
    // 미리보기에서 넘어온 경우 캡처가 이미 있음 → 바로 저장.
    if (bodyRef.current) void runSave();
    else setStage("info");
  }

  function onInfoNext() {
    if (!gender || !age) {
      setNotice("성별과 나이대를 골라 주세요.");
      return;
    }
    setNotice("");
    void startCamera();
  }

  function onTeaserJoin() {
    setPreviewOnly(false);
    if (session) {
      setStage("name");
      return;
    }
    // 캡처를 stash 하고 로그인 — 복귀 시 재촬영 없이 이어간다.
    const video = document.createElement("canvas"); // thumb 은 이미 Blob — dataURL 로.
    void video; // (미사용 — thumb 변환은 FileReader 로)
    const stashAndLogin = async () => {
      let thumbUrl: string | null = null;
      const blob = thumbRef.current;
      if (blob) {
        thumbUrl = await new Promise<string | null>((resolve) => {
          const fr = new FileReader();
          fr.onload = () => resolve(fr.result as string);
          fr.onerror = () => resolve(null);
          fr.readAsDataURL(blob);
        });
      }
      const stash: Stash = {
        teamId: team.id,
        body: bodyRef.current!,
        thumb: thumbUrl,
      };
      sessionStorage.setItem(STASH_KEY, JSON.stringify(stash));
      await loginWithKakao(sb());
    };
    void stashAndLogin();
  }

  // ── 렌더 ──────────────────────────────────────────────────────────────
  const video = (
    <video
      ref={videoRef}
      playsInline
      muted
      className="join-video"
      style={stage === "camera" ? undefined : { display: "none" }}
    />
  );

  if (inApp === "kakao") {
    return (
      <div className="join">
        {video}
        <p className="join-sub">카카오톡 안에서는 카메라가 막혀 있어요.</p>
        <button
          className="join-btn"
          onClick={() => openInExternalBrowser(window.location.href)}
        >
          기본 브라우저로 열기
        </button>
        <p className="join-sub">열린 화면에서 참여를 이어가 주세요.</p>
      </div>
    );
  }
  if (inApp === "other") {
    return (
      <div className="join">
        {video}
        <p className="join-sub">
          이 화면에서는 카메라가 안 돼요. 우측 상단 메뉴에서 기본 브라우저로
          열거나, 앱에서 참여해 주세요.
        </p>
        <a className="join-btn" href={appOpenUrl}>
          앱에서 보기
        </a>
        <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
      </div>
    );
  }

  return (
    <div className="join">
      {video}

      {stage === "entry" && (
        <>
          <button className="join-btn" onClick={onJoinStart}>
            카카오로 참여하기
          </button>
          <p className="join-sub">설치 없이 얼굴 등록까지 3분</p>
          <button className="join-btn--ghost" onClick={onPreviewStart}>
            먼저 미리보기
          </button>
        </>
      )}

      {stage === "name" && (
        <>
          <p className="join-q">어떤 이름으로 참여할까요?</p>
          {team.members.some((m) => !m.joined) && (
            <>
              <p className="join-sub">비어 있는 자리</p>
              <div className="join-chips">
                {team.members
                  .filter((m) => !m.joined)
                  .map((m) => (
                    <button
                      key={m.name}
                      className={
                        nameInput === m.name
                          ? "join-chip join-chip--on"
                          : "join-chip"
                      }
                      onClick={() => setNameInput(m.name)}
                    >
                      {m.name}
                    </button>
                  ))}
              </div>
            </>
          )}
          <input
            className="join-input"
            value={nameInput}
            maxLength={10}
            placeholder="이름 직접 입력"
            onChange={(e) => setNameInput(e.target.value)}
          />
          {notice && <p className="join-notice">{notice}</p>}
          <div>
            <button className="join-btn" onClick={onNameNext}>
              다음
            </button>
          </div>
        </>
      )}

      {stage === "info" && (
        <>
          <p className="join-q">나를 알려주세요</p>
          <Picker label="성별" options={GENDERS} value={gender} onPick={(v) => { setGender(v); void preloadDetector().catch(() => {}); }} />
          <Picker label="나이대" options={AGES} value={age} onPick={(v) => { setAge(v); void preloadDetector().catch(() => {}); }} />
          {notice && <p className="join-notice">{notice}</p>}
          <div>
            <button className="join-btn" onClick={onInfoNext}>
              카메라 켜기
            </button>
          </div>
        </>
      )}

      {stage === "camera" && <p className="join-sub">{hint}</p>}

      {stage === "saving" && <p className="join-q">그룹에 등록 중…</p>}

      {stage === "error" && (
        <>
          <p className="join-q">{errorMsg}</p>
          <a className="join-btn" href={appOpenUrl}>
            앱에서 확인하기
          </a>
          <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
        </>
      )}

      {stage === "done" && (
        <>
          {joined && <div className="join-badge">참여 완료 ✓</div>}
          {teaser?.kind === "pair" ? (
            <>
              <p className="join-sub">
                나 ↔ {teaser.ownerName} (방장)
              </p>
              <div className="join-score">{teaser.total}점</div>
              <div style={{ fontSize: 16, color: "#1a1a1a" }}>
                {teaser.labelKo}
              </div>
            </>
          ) : teaser ? (
            <>
              <div style={{ fontSize: 24, color: "#1a1a1a" }}>
                {teaser.primaryLabel}
              </div>
              <p className="join-sub">{teaser.catchphrase}</p>
            </>
          ) : null}
          {joined ? (
            <p className="join-sub">
              전원이 모이면 이 링크에서 그룹 케미 결과표가 공개됩니다.
              측면까지 넣은 정밀 분석은 앱에서 확인할 수 있어요.
            </p>
          ) : (
            <button className="join-btn" onClick={onTeaserJoin}>
              이 결과로 그룹 참여하기
            </button>
          )}
          <p className="join-sub" style={{ marginTop: 16 }}>
            {joined ? "더 정확한 결과와 전원 케미는 앱에서" : "정확한 결과는 앱에서"}
          </p>
          <a className="join-btn" href={appOpenUrl}>
            앱에서 전체 결과 보기
          </a>
          <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
        </>
      )}
    </div>
  );
}

function Picker({
  label,
  options,
  value,
  onPick,
}: {
  label: string;
  options: { v: string; ko: string }[];
  value: string | null;
  onPick: (v: string) => void;
}) {
  return (
    <div style={{ marginTop: 12 }}>
      <p className="join-sub" style={{ margin: "0 0 6px" }}>
        {label}
      </p>
      <div className="join-chips">
        {options.map((o) => (
          <button
            key={o.v}
            className={value === o.v ? "join-chip join-chip--on" : "join-chip"}
            onClick={() => onPick(o.v)}
          >
            {o.ko}
          </button>
        ))}
      </div>
    </div>
  );
}

function Stores({
  appStoreUrl,
  playStoreUrl,
}: {
  appStoreUrl: string;
  playStoreUrl: string;
}) {
  return (
    <div
      style={{
        display: "flex",
        gap: 16,
        justifyContent: "center",
        marginTop: 10,
      }}
    >
      <a
        style={{ fontSize: 13, color: "#666", textDecoration: "none" }}
        href={appStoreUrl}
      >
        App Store
      </a>
      <a
        style={{ fontSize: 13, color: "#666", textDecoration: "none" }}
        href={playStoreUrl}
      >
        Google Play
      </a>
    </div>
  );
}
```

주의: `onTeaserJoin` 안의 `const video = document.createElement("canvas"); void video;` 두 줄은 잔재 — **작성 시 제거**하고 `stashAndLogin` 만 남긴다.

- [ ] **Step 2: g.$id.tsx 배선** — import 를 `JoinWizard` 로 바꾸고 렌더 교체:

```tsx
          <JoinWizard
            team={team}
            appOpenUrl={loaderData.appOpenUrl}
            appStoreUrl={loaderData.appStoreUrl}
            playStoreUrl={loaderData.playStoreUrl}
            supabaseUrl={loaderData.supabaseUrl}
            supabaseAnonKey={loaderData.supabaseAnonKey}
          />
```

주석도 갱신: "비연락처 설치 전 티저" → "미설치자 웹 참여 위저드 (미리보기 겸용)".

- [ ] **Step 3: CameraTeaser.tsx 삭제**

```bash
git rm react/app/components/CameraTeaser.tsx
```

- [ ] **Step 4: typecheck + dev 스모크**

```bash
cd /Users/chuck/Code/face/react && pnpm typecheck
```
Expected: 신규 오류 0. face_engine.js 부재 시 `pnpm build:shared` 먼저.

- [ ] **Step 5: Commit**

```bash
git add -A react/app
git commit -m "feat(web): JoinWizard — 카카오 로그인·슬롯 claim·웹 캡처로 그룹 참여 완결"
```

---

### Task 6: 문서 현행화 + 배포

**Files:**
- Modify: `KAKAO.md` (앱 미설치 bullet)
- Modify: `react/docs/HOW-IT-WORKS.md` (책임 목록 + /g 절)
- Modify: `PRD.md` (웹 티저 관련 절)

- [ ] **Step 1: KAKAO.md** — "앱 미설치" bullet 을 웹 참여로 교체:

```
- **앱 미설치**: 브라우저 `/g/{id}` — 모집 중 = 초대장 + **웹 참여 위저드**
  (카카오 로그인 → 빈 슬롯 claim 또는 새 이름 → 성별/나이 → 정면 캡처 →
  metrics+썸네일 저장 → team_members 합류. 전원 등록 카운트에 포함) /
  완성 = 결과표 쇼케이스 / 종료 = 안내. 웹 참여자가 앱 설치 후 같은 카카오
  계정으로 로그인하면 rehydrate 가 캡처·그룹을 자동 복원.
```

전제 조건의 "합류자: 앱 설치 + 로그인 + 내 관상" 도 "합류자: 앱 또는 웹(카카오 로그인)" 로 갱신.

- [ ] **Step 2: react/docs/HOW-IT-WORKS.md** — 서두 책임 목록에 5번 추가:

```
5. **웹 참여** (`/g/:id` client) — 미설치 합류자가 브라우저에서 카카오 로그인
   (supabase-js PKCE, 앱과 같은 auth.users) 후 정면 캡처로 그룹에 합류.
   write 는 전부 클라이언트→Supabase 직통 (metrics upsert + team_members
   claim/insert, 기존 RLS 그대로) — Worker 는 여전히 presign + SSR read-only.
```

- [ ] **Step 3: PRD.md** — 웹 티저 언급 절을 "웹 참여(티저 겸용)"로 갱신, 🔶부분 구현이던 "웹 티저 재사용(카카오 로그인+capture 귀속)" 항목을 구현 완료로.

- [ ] **Step 4: typecheck 최종 + 배포 + Commit**

```bash
cd /Users/chuck/Code/face/react && pnpm typecheck && pnpm build:shared && pnpm deploy
git add KAKAO.md react/docs/HOW-IT-WORKS.md PRD.md
git commit -m "docs: 웹 풀 참여 반영 (KAKAO/HOW-IT-WORKS/PRD)"
git push
```

배포 후 실기기 체크리스트 (형):
1. Supabase Redirect URLs 등록 확인 (선행 조건).
2. 카톡 링크 → 외부 브라우저 → [카카오로 참여하기] → 로그인 복귀 → 슬롯 → 캡처 → 참여 완료.
3. 방장 앱 pull-to-refresh 로 합류 확인 + 아바타(웹 썸네일) 표시.
4. [먼저 미리보기] 경로: 캡처 → 점수 → [이 결과로 그룹 참여하기] → 로그인 → 재촬영 없이 완료.
5. 웹 참여자가 앱 설치 + 같은 카카오 로그인 → 내 관상·그룹 rehydrate 확인.
