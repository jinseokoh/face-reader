# Chemistry Battle rev2 — 매칭방·썸네일 공개·인앱 채팅 개정 설계

**작성일**: 2026-07-17
**베이스**: `2026-07-16-chemistry-battle-design.md` (구현 완료 상태에서의 델타 스펙)
**UX SSOT**: `2026-07-17-battle-create-ux-mentor.md` (생성 플로우·연령 컨트롤·제목 카탈로그 44종·로비/결과표 시각화·매칭 성사 카피 — 화면 설계는 전부 이 문서가 규범)

---

## 1. 개정 요약

| 축 | 결정 |
|---|---|
| 방 유형 | `room_kind: 'all'`(전체 케미) / `'match'`(남녀 반반 이성 케미) |
| match 방 계산 | **동성 쌍은 계산·저장·표시 자체가 없음** — 이성 쌍만. 결과표 = 남×여 직사각 매트릭스 |
| 썸네일 공개 | `thumb_open` 방 속성 — 비공개면 로비는 성별 기본 아이콘(male/female.png) |
| 매칭 성사 | best 쌍에게 서로의 200×200 사진 공개 + "채팅방을 열까요?" 상호 동의 → 둘 다 수락 시 **인앱 1:1 채팅** |
| 공약 | **전면 폐기** (컬럼·UI·payload 전부) — 재미는 제목 프리셋이 흡수 |
| 인원 | 6 / 8 / 10 / 12 만 (match 방은 성별 각 절반) |
| 연령 | 하한 20세 전면(생성·참가) — 10대는 생성 진입 시 사용불가 안내. 범위 = 방장 decade 포함 인접 2-decade, **RangeSlider 유지** (사용자 결정 2026-07-17 — UX 문서 §B 버튼 안 기각) |
| 제목 | 직접 입력 폐기 — 카테고리 → 제목 2단 프리셋 선택 (카탈로그는 UX 문서 §C) |
| 웹 배포 | rev2 반영 후 일괄 (기존 Task 4 보류 유지) |

## 2. 스키마 델타 (`0001_baseline.sql` 직접 수정)

### 2.1 teams

```sql
  room_kind    text  not null default 'all' check (room_kind in ('all', 'match')),
  thumb_open   boolean not null default false,
  -- 삭제: pledge, chat_url (공약 폐기)
  -- 변경: max_players check (max_players in (6, 8, 10, 12))
  -- 변경: age_min/age_max not null + check (age_min >= 20)
  --        + check (age_max = age_min + 10)   -- 항상 인접 2-decade 범위
  -- 삭제: 공약 성인 게이트 CHECK (연령 하한 20 전면화로 흡수)
```

- 표기 규칙 불변: `age_min=20, age_max=30` = "20~39세".
- column grant: SELECT/INSERT 목록에 `room_kind`·`thumb_open` 추가, `pledge`·`chat_url` 제거.

### 2.2 team_members

```sql
  gender  text  not null check (gender in ('male', 'female')),
```

- `join_battle` 이 조인 시점 my-face `body→gender` 로 기록 — 로비 남녀 슬롯·기본 아이콘·성별 정원 카운트·rect 매트릭스 축의 소스.
- `battle_roster` view 에 `gender` 컬럼 추가.

### 2.3 매칭·채팅 (신규)

```sql
-- best 쌍의 채팅 개설 상호 동의. battle 당 1행, 시작은 리빌 페이즈의
-- 각자 응답. consent: null=무응답, true=수락, false=거절.
create table battle_matches (
  team_id    uuid primary key references teams(id) on delete cascade,
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  a_consent  boolean,
  b_consent  boolean,
  opened_at  timestamptz            -- 둘 다 true 가 된 시각 = 채팅 개설
);

-- 인앱 1:1 채팅 — 성사된 쌍 전용. 방 삭제(30일 purge)와 함께 cascade.
create table battle_messages (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references battle_matches(team_id) on delete cascade,
  sender_id  uuid not null references auth.users(id) on delete cascade,
  body       text not null check (char_length(body) <= 500),
  created_at timestamptz not null default now()
);
```

- RLS: `battle_matches` select = 해당 쌍 본인만 (user_a/user_b = auth.uid()) — 타 참가자에게 동의 현황 비노출. write = RPC 전용. `battle_messages` select/insert = `opened_at is not null` 인 매치의 쌍 본인만, insert 는 `sender_id = auth.uid()` 강제.
- Realtime publication 에 `battle_messages` 추가 (+ `battle_matches` UPDATE — 상대 응답 감지).
- 사진 상호 공개: 성사 화면의 UX 게이트 (CDN unguessable-URL 모델 그대로 — 조인 시점 일괄 동의가 계약, UX 문서 §E).

### 2.4 RPC 델타

| RPC | 변경 |
|---|---|
| `join_battle` | ① my-face `gender` 파싱(없으면 NO_MY_FACE 준용 새 코드 `NO_GENDER` 불요 — gender 는 body 필수 필드) ② `room_kind='match'` 면 해당 성별 카운트 ≥ max/2 시 **`GENDER_FULL`** ③ insert 에 gender 기록 ④ 시작 수행 시 `battle_matches` 행 생성(best 는 payload 이후 확정되므로 **user_a/user_b 는 submit_battle_result 가 채움** — 아래) |
| `submit_battle_result` | payload 기록 시 best 쌍의 slot→user 를 roster 로 resolve 해 `battle_matches (team_id, user_a, user_b)` upsert. **신뢰 모델**: payload 는 first-writer 클라이언트 산출물 — 참가자가 best 를 위조해 방 안 두 참가자를 강제 페어링할 수는 있으나, 사진은 본래 metrics link-share 공개 모델이라 신규 노출면이 아니고(전원 조인 시 공개 동의), 영향은 오도된 매칭 카드 수준. 수용된 잔여 리스크 (참가자 한정·결과표 이상이 즉시 가시화) |
| `respond_match(p_team_id, p_accept boolean)` (신규) | 가드: status='completed' · caller ∈ {user_a, user_b}. 본인 consent 기록. 둘 다 true 가 되는 호출에서 `opened_at = now()`. 에러: `NOT_MATCHED`(쌍 아님)·`ALREADY_DECIDED`(재응답 불가 — 거절 즉시 종결 정책) |

- 에러 카피: `GENDER_FULL` → "남자 자리가 다 찼습니다" / "여자 자리가 다 찼습니다" (클라이언트가 본인 성별로 분기).

## 3. 엔진 델타 (shared)

- `computeBattle(players, {required bool matchOnly})` — matchOnly 면 **다른 성별 쌍만** 계산 (동성 쌍은 pairs 에 존재하지 않음). `BattlePlayer` 에 `gender` 추가.
- `runBattle` 입력: `{"roomKind":"match"|"all", "players":[{"slot","name","gender","body"}]}`.
- payload 델타: `players[].gender` 추가 (`{ "slot": 1, "name": "지은", "gender": "female" }`) — match 방 rect 매트릭스 축·기본 아이콘용. pairs·best 구조 불변 (match 방은 이성 쌍만 담김).
- tie-break·정렬=순위 규칙 불변.

## 4. 상태 흐름 델타

```
completed ─(리빌 Best 공개 직후, best 쌍 각자에게)─► 매칭 성사 카드
  · 서로의 200×200 사진 공개 (thumb_open 무관 — 성사 단계는 항상 공개, 조인 시 일괄 동의)
  · "채팅방을 열까요?" [열기] / [이번에는 넘어가기]
  · 둘 다 열기 → battle_messages 채팅 화면 (Realtime)
  · 한쪽 거절 → 즉시 종결, 양쪽에 "이번에는 채팅방이 열리지 않았습니다" (주어 없는 카피)
  · 무응답 → 상대 화면은 "상대의 응답을 기다리는 중" — 방 30일 purge 와 함께 자연 소멸
```

- best 쌍이 아닌 참가자에겐 이 단계 자체가 없음.
- 채팅 수명 = teams 30일 purge cascade (별도 보존 없음).

## 5. 화면 델타 (Flutter — UX 문서가 규범)

| 화면 | 변경 |
|---|---|
| 생성 5스텝 | ①방 유형 → ②제목(카테고리→제목 2단, 직접입력 없음) → ③인원(6/8/10/12 chip) → ④연령(**RangeSlider** — bounds 를 방장 인접 구간 `[max(20, D−10), min(D+10, 70)+9세]` 로 좁히고, 핸들 릴리즈 시 유효 2범위 `[D−10~D]`/`[D~D+10]` 중 가까운 쪽으로 스냅, 드래그 툴팁 유지) → ⑤공개 설정(공개/비밀+PIN + 썸네일 공개). 10대 = 진입 다이얼로그 차단 |
| 로비 | match 방 = 남녀 2열 슬롯(색 구분 없이 열+헤더+성별 아이콘), thumb_open=false 면 male/female.png 아이콘 |
| 조인 | 공약 동의 삭제 → 사진 공개 계약 문구로 대체 (UX §E), match 방은 남은 성별 자리 표기 |
| 리빌 | match 방 = 남×여 직사각 매트릭스. Best 카드 뒤 (best 쌍 본인에게만) 매칭 성사 카드 → 상호 동의 → 채팅 |
| 채팅 (신규) | 최소 1:1 — 메시지 리스트 + 입력, Realtime 구독, 내 배틀 탭에서 성사된 방은 [채팅] 진입점 |

## 6. 웹 델타 (react — rev2 반영 후 일괄 배포)

- 조인: 공약 동의 → 사진 공개 계약 문구, match 방 성별 자리 표기, GENDER_FULL 카피.
- 쇼케이스: match 방 rect 매트릭스 렌더 (`players[].gender` 사용). 매칭 성사·채팅은 **앱 전용** (웹은 "앱에서 확인" 안내 — 웹 채팅은 범위 밖).
- 로비: 남녀 2열 + 기본 아이콘 규칙 동일.

## 7. 삭제 목록

pledge/chat_url 컬럼·공약 스텝·공약 배너(로비/조인)·공약 회수 카드(리빌)·공약 프리셋 상수·공개방 공약 성인 게이트 CHECK·`RangeSlider` 연령 UI·제목 TextField·인원 스텝퍼(4~12) — 문서(PRD 등)의 공약 서술은 구현 완료 후 docs 태스크에서 일괄 제거.

## 8. 엣지

- match 방 정원: 시작 조건은 여전히 "정원 충족" 하나 — 성별 각 절반이 차야 정원이 참. 한쪽 성별만 몰리면 GENDER_FULL 로 대기 지속, 48h expired 규칙 그대로.
- best 쌍 중 한 명 계정 삭제: battle_matches cascade 로 소멸 → 성사 카드 없음(리빌은 payload 로 정상). 채팅 중 삭제 → 메시지 cascade.
- 'all' 방: 매칭 성사 단계 동일 적용? — **적용** (best 쌍 상호 동의 채팅은 방 유형 무관 — 전체방도 성사 재미 유지. 사진 공개도 동일 규칙).
- 연령: 60대 방장 = [50~69]/[60~79], 70대 방장 = [60~79] 1개만 활성.

## 9. 검증 게이트

1. SQL smoke 확장: GENDER_FULL·respond_match 상태(수락/거절/무응답)·battle_messages RLS(쌍 외 접근 차단).
2. shared: matchOnly 계산 테스트 (동성 쌍 부재·rect 완전성 = 남×여 전 조합).
3. 실기기: match 방 6인(남3여3) 시나리오 — 남녀 정원·2열 로비·rect 결과표·성사 상호 동의·채팅 왕복.
4. 기존 게이트 (flutter test·analyze·typecheck·build) 전부 green.
