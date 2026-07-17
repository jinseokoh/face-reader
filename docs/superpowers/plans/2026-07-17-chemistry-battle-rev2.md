# Chemistry Battle rev2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rev2 스펙 구현 — 방 유형(all/match)·남녀 반반 정원·썸네일 공개 옵션·매칭 성사 상호 동의·인앱 1:1 채팅·공약 폐기·인원 6/8/10/12·연령 하한 20/인접 범위 슬라이더·제목 2단 프리셋, 서버→엔진→앱→웹 순.

**Specs (요구사항 SSOT — 모든 구현자는 두 문서의 해당 절을 먼저 읽는다):**
- `docs/superpowers/specs/2026-07-17-chemistry-battle-rev2-design.md` (데이터·RPC·엔진·상태 — 이하 "rev2")
- `docs/superpowers/specs/2026-07-17-battle-create-ux-mentor.md` (화면·카피·제목 카탈로그 — 이하 "UX")
- 단, **연령 UI 는 RangeSlider 유지** (rev2 §1.1/§5 — UX §B 의 버튼 안은 기각됨). UX 문서의 다른 절은 규범.

## Global Constraints

- DDL 은 `react/db/migrations/0001_baseline.sql` 단일 파일 직접 수정. version 필드 금지. payload 키 풀네임(gender — 압축 키 금지).
- 디자인 토큰 규칙 전부 유지 (신규 색 금지·FaIcon·chip 단일톤·CTA 흰+테두리). 카피는 UX 문서의 실카피를 **그대로** 사용 (감정 단정·가운데점 금지 검증됨).
- 게이트: `cd flutter && flutter test && flutter analyze`(기준선 7) · `cd react && pnpm build:shared && pnpm typecheck`(contact.tsx 1건만) `&& pnpm build`.
- 서버 에러 계약 추가: `GENDER_FULL`·`NOT_MATCHED`·`ALREADY_DECIDED`.
- Supabase 적용은 human gate (drop-recreate — **public 스키마 데이터 전체 초기화 수반**, 실행 안내 시 이 사실을 첫 문장으로).
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: SQL 델타 — 스키마·RPC·매칭/채팅 테이블·smoke 확장

**Files:**
- Modify: `react/db/migrations/0001_baseline.sql`
- Modify: `react/db/tests/battle_rpc_smoke.sql`

**Interfaces (Produces):** rev2 §2 전체가 계약. 요점 —
- teams: `room_kind('all'|'match')`·`thumb_open bool`·`pledge/chat_url 삭제`·`max_players in (6,8,10,12)`·`age_min not null >= 20`·`age_max not null = age_min + 10`·공약 성인 게이트 CHECK 삭제. column grant SELECT/INSERT 목록 갱신 (pledge/chat_url 제거, room_kind/thumb_open 추가).
- team_members: `gender text not null check in ('male','female')`. battle_roster view 에 gender 추가.
- 신규 `battle_matches`/`battle_messages` — rev2 §2.3 DDL 그대로 + RLS(쌍 본인만·messages 는 opened 이후·sender 강제) + Realtime publication 추가(battle_messages 전체, battle_matches UPDATE).
- RPC: `join_battle` — my-face body→gender 파싱해 insert 에 기록, match 방이면 성별 카운트 `>= max_players/2` 시 `raise exception 'GENDER_FULL'`. `submit_battle_result` — payload 기록 시 best 쌍 slot→roster user resolve 하여 `battle_matches(team_id, user_a, user_b)` insert (definer). `respond_match(p_team_id uuid, p_accept boolean)` 신규 — rev2 §2.4 가드/에러 그대로, 둘 다 수락되는 호출에서 `opened_at=now()`. grants: respond_match execute → authenticated only.
- public_battles view: pledge 컬럼 제거, room_kind·thumb_open 추가.

**Steps:**
- [x] rev2 §2 를 baseline 에 반영 (기존 §11-2~11-5 수정 + §11-6 매칭/채팅 신설). CHECK·RLS·grant·publication 전부.
- [x] smoke 확장: ⑩ match 방(6인) 남3 채운 뒤 4번째 남성 조인 → GENDER_FULL / ⑪ 시작 후 submit → battle_matches 행의 user_a/user_b = payload best 쌍 검증 / ⑫ respond_match: 쌍 아닌 참가자 NOT_MATCHED · 한쪽 수락 후 상대 거절 → opened_at null 유지 · 재응답 ALREADY_DECIDED / ⑬ battle_messages: 쌍 본인 insert OK(스모크는 definer 아닌 postgres 라 RLS 우회 — RLS 검증은 `set_config`+`set local role authenticated` 블록으로) — 기존 begin…rollback·ALL PASS 마지막 문장 구조 유지. 기존 ①~⑨는 새 스키마에 맞게 최소 수정 (pledge 참조 제거·인원 6/8/10/12·연령 20+·gender 있는 my-face body).
- [x] 검증: `grep -c '\$\$'` 짝수 · node 체크(room_kind 존재·pledge 부재) · 커밋.

```bash
git add react/db/migrations/0001_baseline.sql react/db/tests/battle_rpc_smoke.sql
git commit -m "feat(db): rev2 — 방 유형·성별 정원·매칭 동의·인앱 채팅·공약 폐기

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: shared 엔진 — matchOnly 계산 + runBattle 입력 확장 (TDD)

**Files:**
- Modify: `shared/lib/domain/services/compat/battle.dart`
- Modify: `shared/lib/face_engine.dart`
- Modify: `flutter/test/battle_test.dart`

**Interfaces (Produces):**
- `BattlePlayer` 에 `final String gender;` (required — 'male'|'female').
- `computeBattle(List<BattlePlayer> players, {bool matchOnly = false})` — matchOnly 면 `a.gender != b.gender` 쌍만 생성. 정렬·tie-break·best 규칙 불변.
- `toPayload()`: players 항목에 `'gender': p.gender` 추가. pairs/best 불변.
- `runBattle` 입력: `{"roomKind":"match"|"all", "players":[{"slot","name","gender","body"}]}` — roomKind=='match' → matchOnly.

**Steps:**
- [x] 테스트 먼저: 기존 6개를 gender 필수에 맞게 갱신 + 신규 — matchOnly 에서 (a) pairs 수 = 남수×여수 (b) 모든 쌍이 이성 (c) payload players[].gender 존재 (d) all 모드 무변화 회귀.
- [x] 구현 → `flutter test test/battle_test.dart` green → `cd react && pnpm build:shared` 성공 → 전체 게이트 → 커밋.

```bash
git add shared/lib/domain/services/compat/battle.dart shared/lib/face_engine.dart flutter/test/battle_test.dart
git commit -m "feat(engine): matchOnly 이성 쌍 계산 + payload gender

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Flutter 모델·서비스 델타 + 매칭/채팅 서비스

**Files:**
- Modify: `flutter/lib/domain/models/battle.dart`
- Modify: `flutter/lib/data/services/battle_service.dart`
- Modify: `flutter/test/battle_model_test.dart`

**Interfaces (Produces):**
- Battle: `roomKind('all'|'match' enum BattleRoomKind)`·`thumbOpen bool` 파싱, pledge/chatUrl 제거. PublicBattle 에 roomKind·thumbOpen. RosterEntry 에 `gender`.
- BattleJoinError 에 `genderFull('GENDER_FULL', ...)` — labelKo 는 성별 미지정 중립 "이 방의 남녀 자리 중 한쪽이 다 찼습니다" + 화면에서 본인 성별로 분기한 카피("남자 자리가 다 찼습니다"/"여자 자리가…") 를 쓰도록 helper `String genderFullLabel(String myGender)`.
- 신규 model: `BattleMatch { teamId, userA, userB, aConsent, bConsent, openedAt }` + `BattleMessage { id, teamId, senderId, body, createdAt }` (fromRow).
- BattleService 추가: `fetchMatch(teamId) → BattleMatch?` · `respondMatch(teamId, bool accept)` (RPC) · `fetchMessages(teamId, {limit 100})` · `sendMessage(teamId, body)` · `watchMatch(teamId, onChange)` (battle_matches UPDATE + battle_messages INSERT 구독 채널) · createBattle 시그니처에 `roomKind`/`thumbOpen` (pledge/chatUrl 파라미터 제거) · `_teamCols` 갱신.
- 테스트: fromRow 신규 필드·genderFull 매핑·BattleMatch/Message 파싱.

**Steps:** TDD (모델 테스트 → 구현) → 게이트 → 커밋 `feat(app): rev2 모델·서비스 — 방 유형·성별·매칭·채팅 계약`.

---

### Task 4: 생성 플로우 재작성 (UX §A·§C — 연령만 슬라이더)

**Files:**
- Rewrite: `flutter/lib/presentation/screens/team/battle_create_page.dart`
- Create: `flutter/lib/presentation/screens/team/battle_title_catalog.dart` (UX §C 카탈로그 44종을 Dart 상수로 — 카테고리·제목·허용 방유형 필드 포함, 카피는 UX 문서에서 **그대로 복사**)

**요지:** 5스텝 = ①방 유형(2 choiceTile — UX §A 카피) → ②제목(카테고리 chip 행 → 제목 리스트, 방 유형 비허용 제목은 숨김, 직접입력 없음) → ③인원(6/8/10/12 chip, match 방이면 "남 N·여 N" 보조 표기) → ④연령(RangeSlider — bounds `[max(20,D−10), min(D+10,70)]`, 릴리즈 스냅 = `[D−10,D]`/`[D,D+10]` 중 가까운 쪽, 항상 방장 decade 포함, 툴팁 유지, 전연령 chip 삭제) → ⑤공개 설정(공개/비밀+PIN 4자리 + 썸네일 공개 toggle — UX §A 문구). 진입 게이트: 방장 decade < 20 이면 UX §A 의 사용불가 다이얼로그 (플로우 진입 자체 차단 — chemistry_screen._create 에서 로그인 게이트 다음에). 제출 = createBattle(roomKind·thumbOpen 포함) + joinBattle + 실패 롤백(기존 deleteBattle 패턴 유지). ensureMyFaceOnServer 호출 유지.

**Steps:** UX §A/§C 정독 → 카탈로그 상수 → 페이지 재작성 → 게이트 → 커밋 `feat(app): rev2 생성 플로우 — 방 유형·제목 프리셋·인원 chip·인접 연령 슬라이더·썸네일 공개`.

---

### Task 5: 로비·조인 델타 (UX §D 앞부분·§E 계약 문구)

**Files:**
- Modify: `flutter/lib/presentation/screens/team/team_lobby_screen.dart`
- Modify: `flutter/lib/presentation/screens/team/battle_join_screen.dart`

**요지:** 로비 — match 방은 남/여 2열 슬롯(UX §D: 열 위치+헤더+빈 슬롯 성별 아이콘 alpha 0.35, 색 구분 없음. 아이콘 asset = `assets/icons/male.png`/`female.png` — 실경로 확인), all 방은 기존 그리드. `thumb_open=false` 면 채워진 슬롯도 성별 기본 아이콘 (썸네일 fetch 스킵). 공약 배너 삭제. 조인 — 공약 동의 체크 삭제 → 사진 공개 계약 문구(UX §E 실카피, 정보성 고지 — 체크박스 아님·조인 = 동의) + match 방 남은 성별 자리 표기("남자 N자리·여자 N자리" — 가운데점 금지이므로 줄 분리) + GENDER_FULL 시 본인 성별 분기 카피. 하단 safe area·재진입 가드 등 기존 수정 유지.

**Steps:** 구현 → 게이트 → 커밋 `feat(app): rev2 로비·조인 — 남녀 2열·기본 아이콘·사진 공개 계약`.

---

### Task 6: 리빌 rect 매트릭스 + 매칭 성사 + 인앱 채팅 화면

**Files:**
- Modify: `flutter/lib/presentation/screens/team/team_reveal_screen.dart`
- Create: `flutter/lib/presentation/screens/team/battle_match_card.dart` (성사 카드 — 사진 상호 공개·수락/거절, UX §E 카피·상태 3종)
- Create: `flutter/lib/presentation/screens/team/battle_chat_screen.dart` (1:1 채팅 — 메시지 리스트+입력, Realtime watchMatch, 500자 제한)
- Modify: `flutter/lib/presentation/screens/chemistry/chemistry_screen.dart` (내 배틀 카드 — 성사된 방 [채팅] 진입점)

**요지:** 리빌 — match 방은 남(행)×여(열) 직사각 매트릭스 (`payload.players[].gender` 로 축 분리, 뷰어 행/열 우선 배치), all 방은 기존 정방 유지. 공약 회수 카드 삭제. Best 카드 뒤 — **뷰어가 best 쌍 본인일 때만** `battle_match_card`: 상대 200×200 사진(fetchMyFaceThumbnailUrls 재사용, thumb_open 무관 항상 표시) + "채팅방을 열까요?" [열기]/[이번에는 넘어가기] → respondMatch → 상태별 화면(상대 대기/성사→채팅 진입/종결 "이번에는 채팅방이 열리지 않았습니다"). watchMatch 로 상대 응답 실시간 반영. 채팅 화면 — 최소 구성(버블 좌우 정렬·입력바·전송), 메시지 시간 표기는 caption. 내 배틀 카드: `fetchMatch` 로 openedAt 있으면 [채팅] 버튼.

**Steps:** UX §E 정독 → match card → chat screen → reveal 배선 → chemistry 진입점 → 게이트 → 커밋 `feat(app): rev2 리빌 — rect 매트릭스·매칭 성사·인앱 채팅`.

---

### Task 7: 웹 동기화 (rev2 §6)

**Files:**
- Modify: `react/app/lib/join.ts` (BattleRow: roomKind/thumbOpen/pledge 제거·RosterEntry.gender·joinBattle GENDER_FULL·computeBattlePayload gender/roomKind)
- Modify: `react/app/lib/supabase.ts` (fetchBattleSSR 컬럼 갱신)
- Modify: `react/app/routes/g.$id.tsx` (BattleInvite: 유형·남은 성별 자리·공약 배너 삭제 / BattleShowcase: match 방 rect 매트릭스 / 성사·채팅은 "앱에서 확인하세요" 안내 한 줄)
- Modify: `react/app/components/JoinWizard.tsx` (공약 동의 → 사진 공개 계약 문구·GENDER_FULL 카피·로비 2열은 웹은 리스트에 성별 뱃지로 단순화 허용)
- Modify: `react/app/lib/shared/face_engine.d.ts` 주석 (입력 roomKind 반영 — 시그니처 동일 string)

**Steps:** 구현 → `pnpm build:shared && pnpm typecheck && pnpm build` → 커밋 `feat(web): rev2 동기화 — 방 유형·성별 정원·rect 쇼케이스·공약 제거`.

---

### Task 8: 종결 — smoke/실기기 게이트 안내 + 문서 갱신 + 배포

- [x] Human gate 안내문 작성 (drop-recreate = 데이터 전체 초기화 **첫 문장**, 그 다음 절차: 계정 정리 → reset → baseline → smoke ALL PASS → 42501 확인).
- [x] 실기기 rev2 시나리오 (rev2 §9-3) 체크리스트 전달.
- [x] 문서 5종 rev2 반영 (PRD·ARCHITECTURE·react HOW-IT-WORKS·KAKAO·CLAUDE 테스트 수 — 공약 서술 제거·매칭/채팅·방 유형).
- [x] 웹 배포 (`pnpm build && pnpm run deploy`) — human 승인 후.
- [x] Ledger 종결.

## 완료 기준

rev2 §9 그대로 + 전 게이트 green + 실기기 match 방 6인 시나리오 (human).
