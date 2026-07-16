# Chemistry Battle — 케미 게임 로비 전환 설계

**작성일**: 2026-07-16
**상태**: 승인된 디자인 (구현 계획 선행 문서)
**대체 대상**: 기존 그룹 케미 전체 (이름 선등록 + lazy sync + 폴링 모델)

---

## 1. 개요

기존 케미는 "방장이 사람 이름을 미리 만들고, 사진을 연결하고, 다 모이길 기다리는 분석 도구"였다.
이를 폐기하고 **게임 로비 기반 Chemistry Battle**로 전환한다.

> 방을 만든다 → 참가자들이 직접 슬롯에 들어온다 → 인원이 모이면 시작 →
> 전 쌍 케미 분석 → 시상식처럼 결과를 공개한다.

사용자는 사람을 관리하지 않는다. 방을 만들고, 각자가 알아서 참여한다.

### 1.1 핵심 결정 요약

| 축 | 결정 |
|---|---|
| 방의 존재론 | 로컬 우선 → **서버 우선** (생성 즉시 Supabase, Hive teams box 삭제) |
| 라이브함 | **Supabase Realtime** (postgres_changes 구독) + 폴링 fallback + cron backstop |
| 참가 모델 | 이름 슬롯 폐기 → **로그인 사용자 셀프 조인** (정체성 = users.nickname) |
| 상태 전이 | **SECURITY DEFINER RPC 상태 머신** (조인·시작·결과 backfill 전부 원자 검증) |
| 명단 데이터 | recruiting = **current my-face live resolve** / 시작 시 **`chemistry_snapshot` 입력 동결**(RPC 서버측 집계 — 치팅 방어) / 출력 동결 = `result_payload` |
| 계산 주체 | 클라이언트 (엔진 결정론 → 누가 계산해도 같은 결과), 그룹 집계는 shared/ 이동 |
| 공약(내기) | **방장이 방 생성 시 설정** — 방의 정체성. 정산형(친목) / 만남형(공개 매칭) |
| 과금 | 불변 — 어워드·밴드 매트릭스 무료, 쌍 상세 1🪙 unlock |

### 1.2 스펙 전제 교정

기획 문서의 "12×12 Chemistry Matrix 엔진"은 실존하지 않는다. 실제 자산은 2인 궁합
파이프라인(`analyzeCompatibility` — 五行·십이궁·기질·성정, 0.20/0.40/0.25/0.15)이고
케미는 N(N-1)/2쌍 반복 + 집계다. "12"는 인원 하드캡(66쌍)이다. 배틀도 이 엔진을
그대로 사용한다 — 결정론이라 "전원이 같은 결과를 본다"가 공짜로 성립한다.

---

## 2. 데이터 모델 (`react/db/migrations/0001_baseline.sql` 직접 개편)

출시 전 단일 baseline 직접 수정 원칙 유지. drop-recreate 자유.

### 2.1 `teams` 재구성

```sql
create table teams (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid references auth.users(id) on delete set null,  -- 생성 시 필수, 탈퇴 시 null
  title          text not null,
  visibility     text not null default 'private',   -- 'public' | 'private'
  password       text,                              -- private 전용. column-grant 로 클라이언트 SELECT 차단
  max_players    int  not null default 8,           -- 4~12. 정원 = hard limit = 시작 조건 (별도 최소 인원 없음)
  age_min        int,   -- 허용 첫 decade (10,20,…). null = 전연령
  age_max        int,   -- 허용 마지막 decade (포함). 예: 20~39세 = age_min 20, age_max 30
  stake_kind     text,          -- 'best_pays' | 'rival_pays' | 'meetup' | null(없음)
  stake_text     text,          -- 프리셋 라벨 또는 직접입력 (40자 캡)
  chat_url       text,          -- 카카오 오픈채팅 링크 (선택, 만남형 연결 고리)
  status         text not null default 'recruiting',
                 -- 'recruiting' | 'revealing' | 'completed' | 'expired'
  started_at     timestamptz,
  closed_at      timestamptz,
  chemistry_snapshot jsonb,   -- 시작 트랜잭션이 집계한 {user_id: metrics body} — 엔진 입력 동결
  result_payload jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
```

- **password 노출 차단**: PostgREST column-level grant — `revoke select on teams from anon, authenticated;` 후 password 를 제외한 컬럼만 `grant select (…)`. 비교는 `join_battle` RPC 내부에서만. (4자리 PIN 은 보안 자산이 아니라 사교적 울타리 — hash 불필요, 단 클라이언트로 절대 안 나감)
- **chat_url 은 UX 게이트**: 컬럼 자체는 읽히지만 UI 가 당첨 쌍에게만 표시. 오픈채팅도 링크-공유 모델이라 방장이 자체 관리 가능 — 링크 read = UUID 아는 사람 모델(PRD §5.1)과 동일 정신.
- 삭제: `matrix_payload` → `result_payload` 로 대체 (어워드 포함, §6.3).

### 2.2 `team_members` 재구성

```sql
create table team_members (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references teams(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
                 -- 계정 삭제 = 참가 행 소멸 → 슬롯 자동 반환. 얼굴은 컬럼이 아니라
                 -- 조회 시 user_id → 현재 my-face live resolve (metrics_id 스냅샷 컬럼 없음 —
                 -- 재촬영이 같은 row 에 body 를 덮어쓰는 모델이라 id 동결은 데이터 동결이 아니다)
  slot_no     int  not null,                        -- 입장 순서
  is_owner    boolean not null default false,
  joined_at   timestamptz not null default now(),
  unique (team_id, user_id),
  unique (team_id, slot_no)
);
```

삭제되는 것: `name` 컬럼, `(team_id, name)` claim 키, 이름 중복 3지점 차단,
walk-in(`user_id null` + metrics 스냅샷) 경로 전체. 표시 이름은 조회 시 `users.nickname` join.

### 2.3 RPC 상태 머신 (전부 SECURITY DEFINER 단일 트랜잭션)

| RPC | 가드 | 동작 |
|---|---|---|
| `join_battle(team_id, password?)` | status='recruiting' · 정원 미달 · 미중복 · password 일치(private) · 연령대 통과(내 my-face `body→ageGroup` decade ∈ [age_min, age_max]) · my-face 존재 | insert. **insert 후 정원 도달 시 같은 트랜잭션에서 시작 수행** |
| `leave_battle(team_id)` | status='recruiting' · 본인 행 존재 · not owner | 본인 행 delete |
| `submit_battle_result(team_id, payload)` | status='revealing' · result_payload is null · caller ∈ 참가자 | payload 기록 + status='completed' + closed_at |

**시작 = 정원 충족 하나뿐.** 방장 수동 시작·마감 시 부분 인원 자동 시작 없음 —
"N명 방이면 N명이 온다"는 자연 기대와 일치 (2026-07-12 전원 등록制 확정과 같은 원칙).
모이면 시작, 48h 안에 안 모이면 expired.

**"시작 수행"** = `status='revealing'` + `started_at=now()` +
**`chemistry_snapshot` 집계** — 같은 트랜잭션에서 참가자 전원의 현재 my-face body 를
`jsonb_object_agg(user_id, body::jsonb)` 로 복사해 입력을 동결한다.

- **치팅 방어가 목적**: 시작 이후의 재촬영·metrics 변경은 결과에 어떤 영향도 못 준다 —
  모든 클라이언트가 live metrics 가 아니라 snapshot 만 읽어 계산하므로.
- 서버(RPC)가 집계하므로 입력에 클라이언트 신뢰가 필요 없고, payload 는 snapshot 으로
  누구나 재계산·검증 가능하다 (결정론).
- id 동결이 아니라 **데이터 동결** — 재촬영이 같은 row 에 body 를 덮어쓰는 모델과 무관.
- my-face 강등/삭제 시멘틱은 공유 링크 세계의 기존 불변식일 뿐 — 배틀은 거기 의존하지 않는다.

**만남형 공개방 성인 게이트**: `stake_kind='meetup' and visibility='public'` 이면
`age_min >= 20` 을 CHECK + 생성 UI 양쪽에서 강제 (10대 + stranger 만남 조합 구조적 차단).

### 2.4 RLS 개편

- `teams`: select 는 column-grant 로 (password 제외). insert/update/delete = owner. 상태 전이는 RPC 전용 (owner 의 직접 status UPDATE 도 컬럼 grant 로 차단).
- `team_members`: select public (링크-공유 모델 유지). insert/delete 는 RPC 전용 (직접 insert 정책 제거 — claim_slot 정책 삭제).
- 공개 목록: `visibility='public' and status='recruiting'` 조회 + 참가자 수 count 를 담은 **view `public_battles`** (컬럼 화이트리스트: id·title·인원·연령대·stake_kind·created_at).

### 2.5 Realtime

`alter publication supabase_realtime add table teams, team_members;` (baseline 에 포함).
클라이언트 구독: 로비 진입 시 `team_members`(INSERT/DELETE, filter team_id) +
`teams`(UPDATE, filter id). 콜백 = 기존 `refreshFromServer` 계열 idempotent merge.
채널 error/timeout → 5초 폴링으로 강등, 재연결 시 복귀. 백그라운드 push 알림은 범위 외.

---

## 3. 상태 머신 & 수명주기

```
recruiting ─ 정원 충족(join_battle 내장) ────────────► revealing
           ─ cron: 48h 경과 (인원 무관) ────────────► expired
revealing  ─ 아무 참가자의 submit_battle_result ─────► completed
           ─ cron: 24h 경과 & payload null ─────────► cron 이 status 만 completed 처리(안전망)
completed / expired ─ closed_at + 30일 ─────────────► cron 실삭제 (기존 정책 유지)
```

- `react/workers/cron.ts`: closeStaleTeams → 48h expired 처리로 교체 (cron 은 시작을 수행하지 않음).
- recruiting 중 참가자 나가기 허용(leave_battle), 방장 방 삭제 허용. 시작 후엔 조인·이탈 불가 (명단 고정 — RPC status 가드).

---

## 4. 공약(내기) 시스템 — 방의 정체성

방장이 생성 스텝에서 설정 (선택, 기본 없음). 참가 = 공약 동의 (join confirm 에 명시).

| 유형 | stake_kind | 용도 | 프리셋 |
|---|---|---|---|
| 정산형 | `best_pays` / `rival_pays` | 비밀방 친목 — 베스트가/라이벌이 쏜다 | ☕ 커피 · 🍚 밥 · 🍦 아이스크림 · 🎤 노래방 · 직접입력 |
| 만남형 | `meetup` | 공개방 매칭 — 베스트 케미 둘이 실행 | 🎬 영화 · ☕ 커피챗 · 🍜 밥 한 끼 · 직접입력 |

- 방 목록 카드·초대장·로비 배너에 공약 상시 노출 — 입장 전에 판돈이 보인다 (참가 훅).
- 회수: 해당 어워드 카드 직후 공약 카드 flip — "이 방의 내기: ☕ 커피는 ○○·○○님이".
  만남형은 당첨 쌍에게만 `chat_url`(오픈채팅) 버튼 노출.
- **chat_url 은 방장 수동 입력** (오픈채팅 만들고 링크 붙여넣기). 자동 발행은 카카오
  오픈링크(오픈채팅) API 가 존재하나 도메인 ID 발급 = 카카오 담당자 승인의 제휴 게이트라
  일반 앱은 즉시 사용 불가 — 제휴 신청은 출시 후 별도 트랙 (§9 확장 아님, 운영 backlog).
- 지역은 스키마로 풀지 않는다 — 방 제목 컨벤션("강남 영화보러가자!")으로 방장이 좁힘.
  region 필터는 수요 관측 후 승격.
- 카피 가드레일: "만남/미팅" 언어만, 데이팅·소개팅 언어 금지 (4.3(b) 프레임 유지).
- 자유텍스트(stake_text·title)는 신고·차단 backlog(PRD §6.2-3)와 같은 모더레이션 표면.

---

## 5. 어워드 5종 — 전부 결정론

계산 우선순위: Best → Rival → Leader → Unexpected → Hidden.
Unexpected/Hidden 이 선순위 어워드와 동일 쌍이면 차순위 후보로, 후보 없으면 해당 어워드 생략.

| 시상 순서 | 어워드 | 정의 |
|---|---|---|
| 1 | 👑 Chemistry Leader | 그룹 전체 평균 케미 최고 1인 |
| 2 | 💥 Chemistry Rival | 최저점 쌍 — 보완 프레임 서술 (비난 금지 유지) |
| 3 | 🎭 Unexpected Chemistry | 五行 상극(relationKind) 쌍 중 최고점 — "겉보기 상극인데 최상위". 상극 쌍 없으면 생략 |
| 4 | 🧩 Hidden Chemistry | (쌍 점수 − 두 사람 각자의 그룹 평균) 잔차 최대 쌍 — "다른 모두와는 평범한데 둘이서만 튐" |
| 5 | 🏆 Best Chemistry | 최고점 쌍 — **피날레**. 직후 공약 카드 회수 |

점수 노출 정책: 어워드 카드의 해당 쌍 점수는 무료(확장된 도파민 모먼트),
매트릭스 셀은 밴드 이모지만, 쌍 상세 해석 = 1🪙 unlock (기존 `unlock_compat` 그대로).

---

## 6. 엔진 & 결과 페이로드

### 6.1 그룹 집계의 shared/ 이동

`flutter/lib/domain/services/team_matrix.dart` 의 집계 로직(쌍 계산·bests·잔차)을
`shared/lib/domain/services/compat/` 아래로 이동 + 어워드 5종 산출 추가.
JS export `runBattle(bodiesJson)` 신설 (기존 runEngine/runCompat/runMetrics 와 나란히) —
앱과 웹 쇼케이스가 단일 코드로 같은 어워드를 계산한다. React 쪽 재구현 금지 원칙 유지.

### 6.2 계산·공개 흐름

status='revealing' broadcast 수신 → 각 클라이언트가 `teams.chemistry_snapshot` 한 컬럼 fetch →
`runBattle(snapshot)` 로컬 계산 → 3-2-1 카운트다운 연출 → 어워드 순차 flip.
최초 도달 클라이언트가 `submit_battle_result` 로 payload backfill — 입력이 snapshot 으로
동결돼 있어 전 클라이언트가 같은 결과를 내고, first-writer-wins 는 형식적 수렴일 뿐이다.
payload 기록 후의 열람·웹 쇼케이스는 전부 payload 렌더.

### 6.3 `result_payload` (웹 쇼케이스·스냅샷 겸용)

```jsonc
{
  "v": 2,
  "players": [{ "n": "닉네임", "slot": 1 }],          // 썸네일은 방장 옵트인 정책 유지
  "pairs":   [{ "a": 1, "b": 2, "band": "geumseul" }], // 밴드만 — 점수 없음
  "awards": {
    "best":       { "a": 3, "b": 7, "score": 94 },
    "rival":      { "a": 1, "b": 5, "score": 48 },
    "leader":     { "p": 3, "avg": 82 },
    "unexpected": { "a": 2, "b": 6, "score": 88 },     // 생략 가능
    "hidden":     { "a": 4, "b": 8, "score": 86 }      // 생략 가능
  }
}
```

내기 정보는 payload 에 넣지 않는다 — `stake_kind`/`stake_text`/`chat_url` 은 teams 컬럼에
이미 있고 생성 후 불변이며, payload 를 읽는 모든 소비자는 teams 행을 함께 fetch 한다.
공약 회수 카드는 컬럼 + `awards.best`(또는 rival) 조합으로 렌더.

---

## 7. 화면 설계 (Flutter — 코드 식별자 team_* 유지, 공식 명칭 "케미 배틀")

DESIGN.md 토큰 체계 전면 준수 (신규 색상 금지, SongMyung 은 display 토큰만, FontAwesome only).

| 화면 | 내용 |
|---|---|
| 케미 탭 (`ChemistryScreen` 개편) | 2탭 재정의: **공개 배틀**(public_battles 실시간 목록 — 제목·n/N·연령대·공약·🔒) / **내 배틀**(참여 중 + 완료). my-face 게이트·FaceScanPill 동작 유지 |
| 방 생성 (`team_create_page` 개편) | 스텝 플로우 재활용: 방 이름 → 인원(최대 4~12) → 공개/비밀(+PIN 4자리) → 연령대 → 내기(선택: 유형+프리셋+오픈채팅 링크) → 생성 즉시 로비. 이름 칩 스텝 삭제 |
| 로비 (`team_lobby_screen` 신설, TeamRoomScreen 대체) | n/N 슬롯 그리드(입장 실시간 반영: 아바타+닉네임 flip-in) · 판돈 배너 · **QR 코드**(현장 셀프 조인 — walk-in 의 계승) · 초대 3버튼 유지 · 참가자 [나가기] (시작 버튼 없음 — 정원 충족 = 자동 시작) |
| 조인 (`TeamJoinScreen` 개편) | 딥링크 `/g/:id` 유지. 로그인 → my-face 보장 → (private) PIN 입력 → 공약 동의 confirm → join_battle → 로비 |
| 결과 연출 (`team_reveal_screen` 신설) | 3-2-1 카운트다운 → 어워드 카드 순차 flip(탭 진행, §5 순서) → 공약 회수 카드 → N×N 밴드 매트릭스(보는 사람 행 최상단 고정 유지) → 쌍 탭 = 1🪙 unlock |
| 매트릭스 | `TeamMatrixScreen` 를 결과 화면 하단부로 흡수, `TeamMatrixSnapshotScreen` 은 result_payload 렌더러로 개편 |

신규 의존성: `qr_flutter` (로비 QR).

### 7.1 삭제 목록 (과감한 rewrite)

이름 선등록·pending 슬롯 UI·`_AssignNameDialog`·직접촬영(walk-in) 루프·
`(team_id,name)` claim·lazy sync(`pushToServer` 지연 푸시)·Hive `teams` box·
"내가 만든/초대받은" 분류·`fillSlot`/`addScannedMember`/`updateRoster` 계열.
`teamsProvider` 는 서버-우선 fetch + Realtime 구독 상태로 재작성.

---

## 8. 웹 표면 (`react/`)

| 라우트 | 변경 |
|---|---|
| `/g/:id` recruiting | JoinWizard 유지하되 쓰기 경로를 join_battle RPC 로 교체(이름 스텝 삭제, PIN·공약 동의 추가). 로비 상태를 Realtime 구독으로 라이브 표시 |
| `/g/:id` completed | 쇼케이스 업그레이드: result_payload 의 어워드 카드 + 밴드 매트릭스 (사진 없음·점수는 어워드만 — 기존 프라이버시 정책 유지) |
| `/g/:id` expired | 종료 안내 유지 |
| 공개방 목록 | **이번 범위 밖** (앱 전용). 웹은 링크 조인 + 쇼케이스만 |

웹 케미 계산은 `runBattle` JS export 사용 (§6.1).

---

## 9. 에러·엣지

- **시작 race**: 정원 도달 시작이 join_battle 트랜잭션에 내장 — 동시 조인은 정원 가드가 직렬화. 방장 수동 시작과의 race 도 status 가드로 무해.
- **Realtime 단절**: 폴링 강등(5s) — 기능 저하일 뿐 차단 아님.
- **revealing 고아**(전 참가자 이탈로 backfill 없음): cron 24h 안전망이 completed 처리, 쇼케이스는 "결과 미생성" 안내.
- **참가 중 my-face 재촬영**: recruiting 중엔 live resolve 가 최신 반영, 시작 후엔 snapshot 이 입력이라 무영향 — 반복 재촬영 치팅이 성립하지 않는다.
- **방장 이탈**: 방장은 leave 불가(방 삭제만). 방장 탈퇴(계정) 시 owner_id set null — cron 수명주기가 정리.
- **연령대 미달 조인 시도**: RPC 가 명시 에러 코드 반환 → "이 방은 20~39세 참가 방입니다" 안내.
- **정원 미충족 expired**: 웹·앱 모두 "인원이 모이지 않아 종료" — 기존 카피 유지.

---

## 10. 검증 계획

1. RPC 단위: SQL 테스트(정원·중복·PIN·연령·상태 가드 + 정원 충족 시 snapshot 집계 원자성) — Supabase 콘솔 스크립트.
2. `shared/` 어워드: Dart 테스트 — 어워드 5종 결정론·중복 dedupe·생략 조건 + 기존 151 green 유지. `pnpm build:shared` 통과 (-O1).
3. 2기기 시나리오: A 생성(내기 포함) → B 웹 조인 → 정원 충족 자동 시작 → 양쪽 동시 카운트다운 → 같은 어워드 → payload backfill 1회 → `/g/:id` 쇼케이스.
4. 현장 시나리오: 4인 방 생성 → 로비 QR 로 3인 셀프 조인 → 정원 충족 자동 시작.
5. cron: 48h 만료, 24h revealing 안전망.

## 11. 문서 후속 갱신 대상

`flutter/docs/ARCHITECTURE.md`(케미 섹션 전면) · `PRD.md`(§1.2, §3, §4.1, §6.3 폴링 non-goal 해제) ·
`react/docs/HOW-IT-WORKS.md`(§g 라우트·cron·RLS) · `flutter/CLAUDE.md` 용어(케미 → 케미 배틀) ·
`KAKAO.md`(초대 카피).
