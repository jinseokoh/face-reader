# Chemistry Battle — Plan 3/3: 웹 표면 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `facely.kr/g/:id` 를 Chemistry Battle 서버 계약(Plan 1)으로 전환 — JoinWizard 를 join_battle RPC 로 수술, supabase-js Realtime 라이브 로비, status 기반 분기, result_payload 쇼케이스(Best 카드 + 밴드 매트릭스), runBattle fallback 계산 — 그리고 monorepo 문서 일괄 갱신으로 전체 프로젝트를 종결한다.

**Architecture:** 큰 재작성 없음 — 죽는 것은 name/slot claim 모델 하나뿐. `lib/join.ts` 의 팀 함수들을 새 스키마/RPC 로 교체하고, `g.$id.tsx` 분기를 `closed_at`/`matrix_payload` → `status`/`result_payload` 로 재키잉, JoinWizard 는 name 스테이지 제거 + entry 에 PIN·공약 동의 + done 스테이지를 Realtime 라이브 로비로. 카메라·MediaPipe·demographic confirm·saveCapture·inapp 탈출은 전부 그대로 재사용.

**Tech Stack:** React Router 7 on Workers · supabase-js 2.110.2 (Realtime greenfield) · face_engine.js (`runBattle` — 아티팩트에 이미 존재, 타이핑만 추가).

**Spec:** `docs/superpowers/specs/2026-07-16-chemistry-battle-design.md` §6·§8. 서버 계약 = Plan 1, 앱 = Plan 2 완료.

## Global Constraints

- 웹 디자인 규칙 (react/CLAUDE.md): system font only · 5단 size 24/16/14/13/12px · 4컬러 `#1a1a1a`/`#666`/`#c44`(점수만)/`#f7f7f8`. 스타일은 `app/app.css` 클래스(BEM-ish) 또는 기존 관례의 inline CSSProperties — Tailwind/CSS-in-JS 금지. 매트릭스는 이모지만, 색 채움 금지 (기존 원칙).
- 엔진 React 재구현 금지 — 계산은 `globalThis.runBattle`/`runCompat` 만.
- Worker 는 Supabase 에 write 하지 않는다 (평상시) — 쓰기는 전부 브라우저 supabase-js (RPC 포함).
- payload·계약에 version 필드 금지.
- result_payload 계약: `{players:[{slot,name}], pairs:[{a,b,band}], best:{a,b,score}}` — pairs 정렬=순위, band 0~3(0=🟢 천작지합·1=🔵 금슬상화·2=🟠 마합가성·3=🔴 형극난조), 점수는 best.score 만.
- 서버 에러 계약: AUTH_REQUIRED·NOT_FOUND·NOT_RECRUITING·BAD_PASSWORD·NO_MY_FACE·AGE_NOT_ALLOWED·FULL·ALREADY_JOINED (join 경로).
- 게이트: `cd react && pnpm typecheck` — **유일한 pre-existing 실패는 contact.tsx 의 WEB3FORMS_ACCESS_KEY 1건** (로컬 typegen stale). 그 외 신규 에러 0. `pnpm build` 성공.
- 배포는 `pnpm build && pnpm run deploy` — **deploy 는 빌드 안 함, build 생략 금지.**
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## 파일 구조

| 파일 | 변경 | 책임 |
|---|---|---|
| `app/lib/join.ts` | 수술 | 팀 함수 → battle 함수 (RPC·view), 캡처 함수 유지 |
| `app/lib/shared/face_engine.d.ts` | 수정 | `runBattle` 선언 추가 |
| `app/lib/supabase.ts` | 수정 | 서버측 `fetchTeam` → 새 컬럼/roster (SSR loader 용) |
| `app/routes/g.$id.tsx` | 재작성 | status 분기·meta·Invite·Showcase(신형)·reveal fallback |
| `app/components/JoinWizard.tsx` | 수술 | name 스테이지 삭제·PIN/동의·RPC 조인·라이브 로비 |
| `app/app.css` | 추가 | 신규 클래스 (pledge 배너·PIN 필드 재사용 위주 최소) |
| docs 5종 | 갱신(T5) | PRD·flutter ARCHITECTURE·react HOW-IT-WORKS·flutter CLAUDE.md·spec §11 정리 |

---

### Task 1: lib 계층 — battle 계약 함수 + runBattle 타이핑

**Files:**
- Modify: `react/app/lib/join.ts`
- Modify: `react/app/lib/shared/face_engine.d.ts`
- Modify: `react/app/lib/supabase.ts` (서버측 fetch 함수)

**Interfaces:**
- Consumes: Plan 1 스키마 (teams 새 컬럼·battle_roster·public_battles·RPC 3종), 기존 `getSupabase` 브라우저 클라이언트.
- Produces (Task 2·3 이 사용):
  - `type BattleStatus = 'recruiting' | 'revealing' | 'completed' | 'expired'`
  - `type BattleRow = { id; title; visibility:'public'|'private'; maxPlayers; ageMin; ageMax; pledge; chatUrl; status:BattleStatus; startedAt; chemistrySnapshot: Record<string,unknown>|null; resultPayload: BattlePayload|null; ownerId }`
  - `type BattlePayload = { players:{slot:number;name:string}[]; pairs:{a:number;b:number;band:number}[]; best:{a:number;b:number;score:number} }`
  - `type RosterEntry = { userId:string; slotNo:number; isOwner:boolean; nickname:string }`
  - browser: `fetchBattle(sb,id)` · `fetchBattleRoster(sb,id)` · `joinBattle(sb,id,password?) → 'ok'|<에러코드>` · `submitBattleResult(sb,id,payload)` · `watchBattle(sb,id,onChange) → RealtimeChannel` · `computeBattlePayload(roster,snapshot) → BattlePayload|null` (runBattle 호출)
  - server(SSR): `fetchBattleSSR(env,id) → {battle:BattleRow, roster:RosterEntry[]}|null` (supabase.ts — 기존 fetchTeam 대체)
  - 삭제: `isTeamOpen`·`fetchMembership`(name 반환형)·`fetchRoster`(name 기반)·`fetchProgress`·`joinTeam`·`fetchMemberBodies`. 유지: `WebCaptureBody`·`fetchMyFace`·`estimateDemographics`·`saveCapture`·`ageToGroup`·private 헬퍼.

- [ ] **Step 1: face_engine.d.ts 에 runBattle 선언 추가**

기존 세 선언 옆에:

```typescript
declare global {
  // Chemistry Battle — 입력 {"players":[{"slot","name","body"}]}, 출력 result_payload.
  var runBattle: (battleJson: string) => string;
}
```

(파일의 기존 선언 스타일에 맞춰 병합 — `var runEngine…` 과 같은 블록이면 그 안에 한 줄.)

- [ ] **Step 2: join.ts 수술**

`react/app/lib/join.ts` 에서 위 "삭제" 목록의 함수들을 제거하고 다음을 추가 (유지 목록은 무수정):

```typescript
// ── Chemistry Battle 계약 (Plan 1 서버) ─────────────────────────────
export type BattleStatus = 'recruiting' | 'revealing' | 'completed' | 'expired'

export type BattlePayload = {
  players: { slot: number; name: string }[]
  pairs: { a: number; b: number; band: number }[]  // 정렬 = 순위, band 0~3
  best: { a: number; b: number; score: number }
}

export type BattleRow = {
  id: string
  ownerId: string | null
  title: string
  visibility: 'public' | 'private'
  maxPlayers: number
  ageMin: number | null
  ageMax: number | null
  pledge: string | null
  chatUrl: string | null
  status: BattleStatus
  chemistrySnapshot: Record<string, unknown> | null
  resultPayload: BattlePayload | null
}

export type RosterEntry = {
  userId: string
  slotNo: number
  isOwner: boolean
  nickname: string
}

const BATTLE_COLS =
  'id, owner_id, title, visibility, max_players, age_min, age_max, ' +
  'pledge, chat_url, status, chemistry_snapshot, result_payload'

function rowToBattle(r: Record<string, unknown>): BattleRow {
  return {
    id: r.id as string,
    ownerId: (r.owner_id as string) ?? null,
    title: r.title as string,
    visibility: r.visibility as 'public' | 'private',
    maxPlayers: r.max_players as number,
    ageMin: (r.age_min as number) ?? null,
    ageMax: (r.age_max as number) ?? null,
    pledge: (r.pledge as string) ?? null,
    chatUrl: (r.chat_url as string) ?? null,
    status: r.status as BattleStatus,
    chemistrySnapshot:
      (r.chemistry_snapshot as Record<string, unknown>) ?? null,
    resultPayload: (r.result_payload as BattlePayload) ?? null,
  }
}

export async function fetchBattle(
  sb: SupabaseClient,
  battleId: string,
): Promise<BattleRow | null> {
  const { data } = await sb
    .from('teams')
    .select(BATTLE_COLS)
    .eq('id', battleId)
    .maybeSingle()
  return data ? rowToBattle(data) : null
}

export async function fetchBattleRoster(
  sb: SupabaseClient,
  battleId: string,
): Promise<RosterEntry[]> {
  const { data } = await sb
    .from('battle_roster')
    .select('user_id, slot_no, is_owner, nickname')
    .eq('team_id', battleId)
    .order('slot_no', { ascending: true })
  return (data ?? []).map((r) => ({
    userId: r.user_id as string,
    slotNo: r.slot_no as number,
    isOwner: r.is_owner as boolean,
    nickname: (r.nickname as string) ?? '참가자',
  }))
}

/** join_battle RPC — 성공 'ok', 실패는 서버 에러 코드 문자열 그대로. */
export async function joinBattle(
  sb: SupabaseClient,
  battleId: string,
  password?: string,
): Promise<string> {
  const { error } = await sb.rpc('join_battle', {
    p_team_id: battleId,
    ...(password ? { p_password: password } : {}),
  })
  if (!error) return 'ok'
  const known = [
    'AUTH_REQUIRED', 'NOT_FOUND', 'NOT_RECRUITING', 'BAD_PASSWORD',
    'NO_MY_FACE', 'AGE_NOT_ALLOWED', 'FULL', 'ALREADY_JOINED',
  ]
  return known.find((k) => error.message.includes(k)) ?? 'FAILED'
}

export async function submitBattleResult(
  sb: SupabaseClient,
  battleId: string,
  payload: BattlePayload,
): Promise<void> {
  // first-writer-wins — 실패(후착·비참가자) 무해.
  await sb.rpc('submit_battle_result', {
    p_team_id: battleId,
    p_payload: payload,
  })
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
      'postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'teams',
        filter: `id=eq.${battleId}` },
      onChange,
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'team_members',
        filter: `team_id=eq.${battleId}` },
      onChange,
    )
    .subscribe()
}

/** snapshot({user_id: body}) + roster → runBattle. 입력 부족 시 null. */
export function computeBattlePayload(
  roster: RosterEntry[],
  snapshot: Record<string, unknown>,
): BattlePayload | null {
  const players = roster
    .filter((r) => snapshot[r.userId])
    .map((r) => ({ slot: r.slotNo, name: r.nickname, body: snapshot[r.userId] }))
  if (players.length < 2) return null
  return JSON.parse(
    globalThis.runBattle(JSON.stringify({ players })),
  ) as BattlePayload
}
```

주의: `SupabaseClient` import 는 파일 기존 import 관례 유지. 삭제 함수들의 소비처는 Task 2·3 이 함께 고친다 — **이 task 의 typecheck 는 join.ts/d.ts/supabase.ts 자체 에러만 0 이면 되고, g.$id.tsx·JoinWizard.tsx 의 참조 에러는 Task 2·3 전까지 허용** (task 별 커밋은 되지만 typecheck 완전 green 은 Task 3 종료 시점 게이트).

→ **단순화 결정**: 중간 상태의 빨간 typecheck 를 피하려면 이 task 에서 **삭제하지 말고 추가만** 하고, 구 함수 삭제는 Task 3(소비처 제거 완료) 마지막 스텝으로 미룬다. 이 방식이 규범 — 매 커밋 typecheck green 유지 (contact.tsx 1건 제외).

- [ ] **Step 3: supabase.ts 서버측 fetch 교체**

기존 `fetchTeam`(구 컬럼) 을 다음으로 대체 — 단 Step 2 와 같은 원칙으로 **일단 추가**(`fetchBattleSSR`), 구 `fetchTeam` 삭제는 Task 2 에서 소비처 교체와 동시에:

```typescript
export type BattleSSR = {
  battle: {
    id: string; title: string; visibility: string
    maxPlayers: number; ageMin: number | null; ageMax: number | null
    pledge: string | null; chatUrl: string | null
    status: string
    resultPayload: unknown | null
    chemistrySnapshot: Record<string, unknown> | null
  }
  roster: { userId: string; slotNo: number; isOwner: boolean; nickname: string }[]
}

export async function fetchBattleSSR(
  env: Env,
  id: string,
): Promise<BattleSSR | null> {
  const headers = {
    apikey: env.SUPABASE_ANON_KEY,
    Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
  }
  const teamRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?id=eq.${id}&select=` +
      encodeURIComponent(
        'id,title,visibility,max_players,age_min,age_max,pledge,chat_url,status,result_payload,chemistry_snapshot',
      ),
    { headers },
  )
  if (!teamRes.ok) return null
  const teams = (await teamRes.json()) as Record<string, unknown>[]
  if (teams.length === 0) return null
  const t = teams[0]
  const rosterRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/battle_roster?team_id=eq.${id}&select=user_id,slot_no,is_owner,nickname&order=slot_no.asc`,
    { headers },
  )
  const rosterRows = rosterRes.ok
    ? ((await rosterRes.json()) as Record<string, unknown>[])
    : []
  return {
    battle: {
      id: t.id as string,
      title: t.title as string,
      visibility: t.visibility as string,
      maxPlayers: t.max_players as number,
      ageMin: (t.age_min as number) ?? null,
      ageMax: (t.age_max as number) ?? null,
      pledge: (t.pledge as string) ?? null,
      chatUrl: (t.chat_url as string) ?? null,
      status: t.status as string,
      resultPayload: t.result_payload ?? null,
      chemistrySnapshot:
        (t.chemistry_snapshot as Record<string, unknown>) ?? null,
    },
    roster: rosterRows.map((r) => ({
      userId: r.user_id as string,
      slotNo: r.slot_no as number,
      isOwner: r.is_owner as boolean,
      nickname: (r.nickname as string) ?? '참가자',
    })),
  }
}
```

(함수 시그니처의 `Env`·헤더 조립은 파일 내 기존 `fetchTeam` 관례 그대로.)

- [ ] **Step 4: 게이트 + Commit**

Run: `cd react && pnpm typecheck`
Expected: contact.tsx 1건 외 신규 에러 0 (추가만 했으므로)

```bash
git add react/app/lib/join.ts react/app/lib/shared/face_engine.d.ts react/app/lib/supabase.ts
git commit -m "feat(web): battle lib 계약 — RPC·roster view·Realtime watch·runBattle 타이핑

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: g.$id.tsx — status 분기 + 신형 Showcase + reveal fallback

**Files:**
- Modify: `react/app/routes/g.$id.tsx` (전면 개편 — Invite/ClosedNotice/Showcase 부분)
- Modify: `react/app/lib/supabase.ts` (구 `fetchTeam` 삭제 — 소비처가 이 파일뿐임을 grep 확인 후)
- Modify: `react/app/app.css` (신규 클래스 최소 추가)

**Interfaces:**
- Consumes: Task 1 의 `fetchBattleSSR`/`BattlePayload`/`computeBattlePayload`/`submitBattleResult`/`fetchBattle`/`fetchBattleRoster`, 기존 `getSupabase`·CTA·OpenBridge.
- Produces: status 4분기 라우트 —
  - `recruiting` → 초대장(공약·연령대·n/N 노출) + JoinWizard (Task 3 개편본과 접점: props `battle`/`roster` 전달)
  - `revealing`/`completed` + payload → `<BattleShowcase payload>` (Best 카드 + 밴드 매트릭스)
  - `revealing`/`completed` + payload null + snapshot → `<RevealFallback>` — 클라이언트에서 `computeBattlePayload` → (로그인 참가자면) `submitBattleResult` → 렌더
  - `expired` (또는 completed + payload/snapshot 둘 다 null) → 종료 안내

- [ ] **Step 1: loader·meta 교체**

loader 를 `fetchBattleSSR` 기반으로:

```tsx
export async function loader({ context, params }: Route.LoaderArgs) {
  const env = context.cloudflare.env
  const data = await fetchBattleSSR(env, params.id!)
  if (!data) throw new Response('Not Found', { status: 404 })
  return {
    battle: data.battle,
    roster: data.roster,
    appOpenUrl: `${env.WEBAPP_BASE}/g/${params.id}/open`,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    canonicalUrl: `${env.WEBAPP_BASE}/g/${params.id}`,
    ogImage: `${env.R2_CDN_BASE}/assets/og.png`,
    supabaseUrl: env.SUPABASE_URL,
    supabaseAnonKey: env.SUPABASE_ANON_KEY,
    cdnBase: env.R2_CDN_BASE,
  }
}
```

meta: status 로 분기 —

```tsx
export const meta: Route.MetaFunction = ({ data }) => {
  if (!data) return []
  const { battle, roster, canonicalUrl, ogImage } = data
  const title =
    battle.status === 'recruiting'
      ? `${battle.title} — 케미 배틀 참가`
      : `${battle.title} — 케미 배틀 결과`
  const description =
    battle.status === 'recruiting'
      ? `${roster.length} / ${battle.maxPlayers} 명 모집 중`
      : battle.status === 'expired'
        ? '인원이 모이지 않아 종료된 배틀입니다'
        : '케미 배틀 결과가 공개되었습니다'
  return [
    { title },
    { name: 'description', content: description },
    { name: 'robots', content: 'noindex,nofollow' },
    { property: 'og:type', content: 'website' },
    { property: 'og:title', content: title },
    { property: 'og:description', content: description },
    { property: 'og:url', content: canonicalUrl },
    { property: 'og:image', content: ogImage },
    { name: 'twitter:card', content: 'summary_large_image' },
  ]
}
```

(기존 파일의 Route 타입 import·export 관례를 그대로 따른다.)

- [ ] **Step 2: 컴포넌트 분기 재작성**

```tsx
export default function Group() {
  const data = useLoaderData<typeof loader>()
  const { battle } = data
  const [wizardActive, setWizardActive] = useState(false)

  let body: React.ReactNode
  if (battle.status === 'recruiting') {
    body = (
      <>
        {!wizardActive && <BattleInvite data={data} />}
        <JoinWizard
          battle={battle}
          roster={data.roster}
          supabaseUrl={data.supabaseUrl}
          supabaseAnonKey={data.supabaseAnonKey}
          cdnBase={data.cdnBase}
          onActive={setWizardActive}
        />
      </>
    )
  } else if (battle.resultPayload) {
    body = <BattleShowcase title={battle.title} payload={battle.resultPayload as BattlePayload} pledge={battle.pledge} />
  } else if (battle.status !== 'expired' && battle.chemistrySnapshot) {
    body = <RevealFallback data={data} />
  } else {
    body = <BattleClosedNotice expired={battle.status === 'expired'} />
  }
  return (
    <main className="join">
      {body}
      <CTA appOpenUrl={data.appOpenUrl} appStoreUrl={data.appStoreUrl} playStoreUrl={data.playStoreUrl} />
    </main>
  )
}
```

`BattleInvite`: 제목 + `${roster.length} / ${maxPlayers} 명` + 연령대 라벨(전연령/N대/N~M+9세 — Task 1 헬퍼 없으므로 파일-로컬 `ageLabel(min,max)` 함수) + 공약 배너(있을 때: "이 방의 공약 · <pledge> — 베스트 케미 둘이 실행") + 참가자 닉네임 chips (`invite-chip` 재사용, 대기 슬롯 수만큼 `invite-chip--wait` '대기 중').

`BattleClosedNotice`: expired → "인원이 모이지 않아 종료된 배틀입니다" / 그 외 → "결과가 생성되지 않은 배틀입니다" (기존 ClosedNotice 클래스 재사용).

- [ ] **Step 3: BattleShowcase (신형 payload 렌더)**

```tsx
const BAND_EMOJI_BY_CODE = ['🟢', '🔵', '🟠', '🔴'] as const
const BAND_LABEL_BY_CODE = ['천작지합', '금슬상화', '마합가성', '형극난조'] as const

function BattleShowcase({ title, payload, pledge }: {
  title: string
  payload: BattlePayload
  pledge: string | null
}) {
  const nameOf = (slot: number) =>
    payload.players.find((p) => p.slot === slot)?.name ?? '참가자'
  const bandOf = (a: number, b: number) => {
    const lo = Math.min(a, b)
    const hi = Math.max(a, b)
    return payload.pairs.find((p) => p.a === lo && p.b === hi)?.band
  }
  const slots = payload.players.map((p) => p.slot)
  return (
    <section className="showcase">
      <h1 className="showcase-title">{title}</h1>
      <div className="showcase-best">
        <p className="showcase-best-eyebrow">🏆 베스트 케미</p>
        <p className="showcase-best-pair">
          {nameOf(payload.best.a)} × {nameOf(payload.best.b)}
        </p>
        <p className="showcase-best-score">{payload.best.score}점</p>
      </div>
      {pledge && (
        <p className="showcase-pledge">
          이 방의 공약 — {pledge}
          <br />
          {nameOf(payload.best.a)}, {nameOf(payload.best.b)} 두 분의 몫입니다
        </p>
      )}
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={head} />
            {slots.map((s) => (
              <th key={s} style={head}>{nameOf(s)}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {slots.map((row) => (
            <tr key={row}>
              <th style={head}>{nameOf(row)}</th>
              {slots.map((col) => (
                <td key={col} style={cell}>
                  {row === col
                    ? '·'
                    : BAND_EMOJI_BY_CODE[bandOf(row, col) ?? 3]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="showcase-legend">
        {BAND_EMOJI_BY_CODE.map((e, i) => `${e} ${BAND_LABEL_BY_CODE[i]}`).join('  ')}
      </p>
    </section>
  )
}
```

`tableStyle`/`head`/`cell` inline CSSProperties 는 기존 Showcase 의 것(L274-288)을 승계. `showcase-*` 클래스는 기존 app.css 에 있으면 재사용, 없으면 4컬러·5사이즈 안에서 추가. **점수는 best.score 하나만** — 매트릭스 셀·범례에 점수 없음.

- [ ] **Step 4: RevealFallback (클라이언트 계산 + 제출)**

```tsx
function RevealFallback({ data }: { data: ReturnType<typeof useLoaderData<typeof loader>> }) {
  const [payload, setPayload] = useState<BattlePayload | null>(null)
  const [failed, setFailed] = useState(false)
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        await import('../lib/shared/face_engine.js')
        const roster = data.roster.map((r) => ({
          userId: r.userId, slotNo: r.slotNo, isOwner: r.isOwner, nickname: r.nickname,
        }))
        const computed = computeBattlePayload(
          roster,
          data.battle.chemistrySnapshot as Record<string, unknown>,
        )
        if (!computed) { if (!cancelled) setFailed(true); return }
        // 로그인 참가자면 정본 backfill (first-writer-wins, 실패 무해).
        const sb = getSupabase(data.supabaseUrl, data.supabaseAnonKey)
        const { data: session } = await sb.auth.getSession()
        if (session.session) {
          await submitBattleResult(sb, data.battle.id, computed).catch(() => {})
        }
        if (!cancelled) setPayload(computed)
      } catch {
        if (!cancelled) setFailed(true)
      }
    })()
    return () => { cancelled = true }
  }, [])
  if (failed) return <BattleClosedNotice expired={false} />
  if (!payload) return <p className="join-sub">결과를 계산하는 중…</p>
  return (
    <BattleShowcase
      title={data.battle.title}
      payload={payload}
      pledge={data.battle.pledge}
    />
  )
}
```

- [ ] **Step 5: 구 코드 정리 + 게이트 + Commit**

- 구 `Showcase`/`ClosedNotice`/`Invite`(멤버 name chips)/`TeamPayload` 타입 삭제. `lib/supabase.ts` 의 구 `fetchTeam`·`TeamShowcase` 타입 삭제 (소비처 grep 으로 이 라우트뿐임을 확인).
- JoinWizard 신 props (`battle`/`roster`) 는 Task 3 에서 구현 — **이 task 커밋 시점의 typecheck 를 위해**, Task 3 을 같은 브랜치에서 바로 잇는다면 JoinWizard 호출부를 임시로 남기지 말고 **Task 2·3 을 같은 구현자가 연속 수행 후 task 별 커밋** (Task 2 커밋은 JoinWizard 호출부를 신 props 형태로 작성해두고, Task 3 이 JoinWizard 쪽 시그니처를 맞춘 뒤에야 typecheck 가 green — Task 2 커밋 직전 게이트는 `pnpm typecheck 2>&1 | grep -v contact.tsx | grep -c "error TS"` 가 **JoinWizard props 불일치 에러만** 남는지 확인으로 대체).

Run: `cd react && pnpm typecheck` (JoinWizard props 에러 외 신규 0)

```bash
git add react/app/routes/g.\$id.tsx react/app/lib/supabase.ts react/app/app.css
git commit -m "feat(web): /g/:id status 분기 — 신형 쇼케이스·reveal fallback·만료 안내

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: JoinWizard 수술 — RPC 조인 + 라이브 로비

**Files:**
- Modify: `react/app/components/JoinWizard.tsx`
- Modify: `react/app/lib/join.ts` (구 팀 함수 삭제 — 최종 정리)
- Modify: `react/app/app.css` (필요 클래스)

**Interfaces:**
- Consumes: Task 1 lib (joinBattle/fetchBattle/fetchBattleRoster/watchBattle), Task 2 의 신 props 계약 `JoinWizard({ battle, roster, supabaseUrl, supabaseAnonKey, cdnBase, onActive })`.
- Produces: name/slot 없는 배틀 조인 위저드 + done 스테이지 = 라이브 로비.

수술 목록 (기존 1156줄 파일 — 아래 외에는 손대지 않는다):

1. **Props 교체**: `team`(구 TeamShowcase) → `battle: <Task2 loader battle 형>`, `roster: RosterEntry[]`, `onProgress`/`onJoined` → `onActive(active: boolean)`. 내부의 `team.members` 파생(openSlots·joined counts) 전부 roster 기반으로.
2. **스테이지 축소**: `'entry' | 'reuse' | 'camera' | 'confirm' | 'saving' | 'done' | 'error'` — `name` 삭제. `goNameOrSkip`/`onSlotSelect`/`joinNameRef`/open-slot chips JSX (L888-915) 삭제.
3. **entry 스테이지 확장**: 기존 카카오 버튼 위에 (a) 비밀방이면 PIN 입력(`join-name-input` 클래스 재사용, `inputMode="numeric"` maxLength 4), (b) 공약 있으면 배너 + 동의 체크박스 — 미충족 시 참가 버튼 disabled. PIN 값은 ref 로 보존해 OAuth 왕복 후에도 sessionStorage 에 저장/복원 (`sessionStorage 'facely:battle-pin:<id>'` — OAuth 리다이렉트가 state 를 날리므로).
4. **조인 흐름 교체**: `runSave` 는 saveCapture(my-face upsert)까지 동일하되, 마지막 `joinTeam(...)` 호출을 `joinBattle(sb, battle.id, pin)` 으로. 반환 코드 매핑: `'ok'|'ALREADY_JOINED'` → done, `BAD_PASSWORD` → entry 로 롤백 + 에러 문구 '비밀번호가 일치하지 않습니다', `AGE_NOT_ALLOWED` → '이 방의 연령대에 해당하지 않습니다', `FULL` → '정원이 가득 찼습니다', `NOT_RECRUITING` → '모집이 끝난 방입니다' (+ 새로고침 유도), `NO_MY_FACE` → confirm 단계 유지 + 재시도. reuse 경로(기촬영 my-face)는 카메라 없이 바로 joinBattle.
5. **done 스테이지 = 라이브 로비**: `watchBattle(sb, battle.id, refetch)` 구독 + 15초 폴링. refetch = `fetchBattle`+`fetchBattleRoster` → roster 를 `join-roster` 클래스로 렌더(닉네임 + 빈 슬롯 `join-slot-empty` '대기 중' × (max−n)), `n / max 명` 카운터, 공약 배너 유지. `battle.status` 가 recruiting 이 아니게 되면 `window.location.reload()` — SSR 분기(Task 2)가 쇼케이스/fallback 을 렌더한다 (웹 카운트다운 연출은 넣지 않는다 — 리로드 한 번이 웹에선 가장 단순·견고). 언마운트 시 `sb.removeChannel(channel)`.
6. **onShowMatrix/MatrixTable/BAND_EMOJI 삭제** — 부분 결과 미리보기는 배틀 세계에 없음 (결과는 시작 후 쇼케이스가 전담). `fetchMemberBodies` 의존 소멸.
7. **join.ts 최종 정리**: `isTeamOpen`/`fetchMembership`/`fetchRoster`(구형)/`fetchProgress`/`joinTeam`/`fetchMemberBodies` 삭제. dangling grep: `grep -rn "joinTeam\|fetchMembership\|fetchProgress\|isTeamOpen\|fetchMemberBodies\|matrix_payload\|closed_at" react/app/ && exit 1 || echo CLEAN` (workers/cron.ts 의 closed_at 은 서버 정리용이라 예외 — grep 범위가 app/ 라 안 걸림).

- [ ] **Step 1~7 구현** (위 수술 목록 순서대로 — 각 항목이 곧 스텝)

- [ ] **Step 8: 게이트**

Run: `cd react && pnpm build:shared && pnpm typecheck && pnpm build`
Expected: typecheck 는 contact.tsx 1건 외 0 (JoinWizard props 에러 이제 해소) · build 성공

- [ ] **Step 9: Commit**

```bash
git add react/app/components/JoinWizard.tsx react/app/lib/join.ts react/app/app.css
git commit -m "feat(web): JoinWizard 배틀 전환 — RPC 조인·PIN·공약 동의·라이브 로비, 이름 슬롯 폐기

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 배포 + 브라우저 검증

**Files:** 없음 (배포 절차)

- [ ] **Step 1: 빌드·배포** — `cd react && pnpm build:shared && pnpm build && pnpm run deploy` (deploy 는 빌드 안 하므로 build 생략 금지)
- [ ] **Step 2: 브라우저 스모크 (사람 또는 브라우저 자동화)**
  1. 앱에서 공개방 생성 → `facely.kr/g/<id>` 열기 → 초대장에 n/N·연령대·공약 표시
  2. 웹 카카오 로그인 → (비밀방이면 PIN) → 공약 동의 → 캡처/재사용 → 참가 → 로비에 내 닉네임 등장, 앱 로비에도 실시간 반영
  3. 정원 충족 → 웹이 리로드되어 쇼케이스(Best 카드 + 매트릭스) 표시, 앱과 동일 Best
  4. expired 방 링크 → 종료 안내
- [ ] **Step 3: 완료 기록** — ledger 에 배포 시각·검증 결과.

---

### Task 5: 문서 일괄 갱신 (프로젝트 종결)

**Files:**
- Modify: `PRD.md` — §1.2(케미→케미 배틀 정의)·§3(시나리오: 로비/QR/공약)·§4.1 전면(그룹 생성→배틀 생성·인원 정책→정원 하드리밋·이름 슬롯/직접촬영 폐기 반영)·§5.3(실시간: 폴링 non-goal 해제, Supabase Realtime 채택)·§6(상태 스냅샷 갱신)
- Modify: `flutter/docs/ARCHITECTURE.md` — §1 케미 화면(배틀 화면 5종)·§3(teamsProvider→battle providers)·§4 케미 원격 경로(서버 우선·RPC·snapshot/payload)·§5 Supabase 표(teams/team_members 새 스키마·RPC·view)
- Modify: `react/docs/HOW-IT-WORKS.md` — /g 라우트 상태 분기·JoinWizard 배틀 흐름·cron 4종·RLS/column grant/Realtime 발행 요약
- Modify: `flutter/CLAUDE.md` — 용어 규칙(공식 명칭 "케미 배틀")·테스트 수 151→현재값·§SSOT 링크 유지
- Modify: `KAKAO.md` — 초대 FeedTemplate 카피가 배틀 언어와 일치하는지 확인·갱신

원칙: 각 문서의 기존 톤·구조 유지, 배틀 세계의 사실만 반영 (금지어 규칙 준수 — 과거 구조를 비교 기준으로 쓰지 않고 현재 구조만 서술). 스펙 문서(`2026-07-16-chemistry-battle-design.md`)는 이력이므로 무수정.

- [ ] **Step 1: 5개 문서 갱신** (각 문서를 열어 케미 관련 구획만 현행화)
- [ ] **Step 2: 사실 대조** — 문서의 모든 구체 값(테이블 컬럼·RPC 이름·화면 이름·상태 문자열)을 실코드와 grep 대조
- [ ] **Step 3: Commit**

```bash
git add PRD.md flutter/docs/ARCHITECTURE.md react/docs/HOW-IT-WORKS.md flutter/CLAUDE.md KAKAO.md
git commit -m "docs: Chemistry Battle 전환 반영 — PRD·ARCHITECTURE·HOW-IT-WORKS·CLAUDE·KAKAO 일괄 현행화

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 완료 기준 (Plan 3 = 프로젝트 종결)

1. `pnpm typecheck`(contact.tsx 1건 외 0)·`pnpm build` 성공, 배포 완료.
2. 웹 E2E: 초대장→조인(PIN·동의)→라이브 로비→쇼케이스, expired 안내 — Task 4 스모크 통과.
3. dangling grep CLEAN (구 팀 함수·matrix_payload·closed_at 참조가 app/ 에 없음).
4. 문서 5종 현행화 — 스펙 §11 목록 소화.
5. Plan 2 deferred 목록(조인·리빌 재시도 UI 등)은 출시 후 backlog 로 ledger 에 이관.
