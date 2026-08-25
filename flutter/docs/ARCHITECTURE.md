# ARCHITECTURE — 화면 · 패키지 · 데이터 흐름

앱이 어떻게 조립되어 있는가. 엔진 동작은 [HOW-IT-WORKS.md](HOW-IT-WORKS.md),
디자인 토큰은 [DESIGN.md](DESIGN.md).

## 0. 한 장 요약

```
flutter/ (앱 셸: 화면·카메라·Hive·코인·인증·공유·광고·딥링크)
   └─ path dep ─▶ shared/ (face_engine — 관상·궁합 엔진 단일 SSOT)
                     └─ dart compile js -O1 ─▶ web/ (facely.kr Workers SSR + cron)
python/ (DeepFace FastAPI)          Supabase (metrics·coins·compatibilities·teams·team_members)
```

룰·reference·quantile 은 `shared/` 한 곳에서만 바뀐다.

## 1. 앱 화면 구조

**5-Tab IndexedStack** (`app.dart::MainApp`, 탭 상태 = `selectedTabProvider`).
세로 고정 (`SystemChrome.setPreferredOrientations([portraitUp])`).

| Tab | Screen | 역할 |
|---|---|---|
| 0 | `PhysiognomyScreen` | 관상 — 내부 3탭 고정(카메라/앨범/북마크, 개수 표기) + 14-node 리포트 진입 |
| 1 | `CompatibilityScreen` | 궁합 — 내부 2탭(미확인/확인), 1🪙 unlock |
| 2 | `ChemistryScreen` | 케미 그룹 — 내부 2탭(모집중/내 그룹) |
| 3 | `ChatScreen` | 채팅 — 열린 매칭 채팅 목록(`openChatsProvider`), 안읽음 gold dot |
| 4 | `SettingsScreen` | 설정 · 프로필 이름 수정 · 약관 · 차단 목록 · 앱 정보 팝업 · 로그인/탈퇴 — 진입 시 배너 광고 팝업(§5) |

채팅 접근 경로: ① 채팅 탭(아이콘에 안읽음 dot 뱃지) ② 전역 새 메시지 밴드 —
안읽은 채팅이 있으면 어느 탭에서든 바텀 탭바 위에 노출, 탭하면 채팅방(1개) 또는
채팅 탭(여러 개) ③ 푸시 딥링크 `/chat/:id`. 안읽음 판정은 Hive `prefs` 의
`chat_last_seen:{teamId}` (로컬 전용, `TeamChatScreen` 이 메시지 로드마다 갱신).

공통 규칙: 내부 탭은 내 관상 등록 후 상시 노출(0개 포함), 최초 노출 시 개수 많은 탭
기본 선택(1회). 내 관상 미등록이면 관상·궁합·케미 AppBar 에 [내 관상 등록]
pill (`face_scan_pill`, 등록 후엔 [상대방 관상 추가]로 전환).

**온보딩 인트로** (`onboarding_intro.dart`): MainApp 첫 프레임 뒤 — 4페이지
(관상[관상풀이 무료] / 궁합[궁합해석 1코인] / 케미[그룹케미 결과표 무료] /
시작은 내 관상부터, 일러스트 onboarding1~3 + banner-start). 전환은
`concentric_transition` 동심원 리플 — 하단 원판(지름 64, 다음 페이지 배경색 +
화살표) 탭/스와이프로 진행, 페이지 배경은 cream/white/shell/white 교대(+동색
sentinel 로 마지막 장 원판 은닉), warm 페이지는 darkBrown+warmBrown 짝. 상단
바 = 다시 보지 않기 / dots / 건너뛰기 (raw window inset 으로 상태바 회피 —
bottom sheet route 가 MediaQuery 를 가공해 SafeArea 무효). 마지막 장 도착 시
원판이 스케일-아웃으로 흡수된 뒤 같은 자리에 [닫기 1/3 | 내 관상 등록 2/3]
버튼 행이 fade-in — 내 관상 등록 → `startMyFaceCapture`, 닫기 = 기록 없이
닫기. 내 관상 등록 전까지 매 실행 노출하며, "다시 보지 않기"만 Hive `prefs`
box (`onboarding_never_again`) flag 를 남겨 노출을 끈다. 건너뛰기·뒤로가기는
기록 없음. 공유 링크 cold-start 면 이번 실행은 양보.

**캡처 파이프라인** (`screens/chemistry/` 폴더 — 관상·궁합·케미 공용):

- `FaceMeshPage` — 카메라 preview + mesh overlay. 녹색 조건 4: confidence ≥0.85 ·
  프레임 안정(이동 <0.005) · face width >25% · yaw class 일치(정면→frontal, 측면→threeQuarter).
  정면 캡처 시 DeepFace 백그라운드 analyze 시작 → 측면(3/4 yaw) 캡처 → `/capture/confirm`.
- `AlbumCapturePage` — image_picker → **square-padding**(non-square 에서 MediaPipe landmark
  distort 차단) → ML Kit bbox → FaceMesh → `/capture/confirm`.
- `InfoConfirmScreen` — DeepFace 추정 자동 prefill(사용자 수정 우선), 상대방 관상은
  optional 이름 입력(→ alias). [확인] → `analyzeFaceReading()` → 썸네일
  face-center 200 crop → `history.add` → `saveMetrics`(fire-and-forget). 시작한 탭에 잔류.
- `ReportPage` — 10 attribute bar(탭→top-5 contributor) · 음양 bar · 삼정 radar ·
  14-node expandable · 8 인생 질문 본문 · 공유(카카오/OS 시트). 공유받은 카드는 북마크로 보관.

**케미 그룹 화면** (`screens/chemistry/chemistry_screen.dart` 탭 + `screens/team/`):
`ChemistryScreen`(2탭 — 모집중/내 그룹. 필터·정렬 상태는 화면 State 소유 — TabBarView
child dispose 에도 유지. 내 그룹 필터 = 전체/모집중/미달/종료) ·
`showTeamCreatePage`(방 유형(all/match)→
제목(카테고리→제목 2단 프리셋, `team_title_catalog.dart`)→인원(6/8/10/12 chip)→
연령대(방장 나이대 포함 인접 2-decade RangeSlider, 하한 20세 — 10대는 진입 차단)→
공개 설정(공개/비밀 PIN + 썸네일 공개) 스텝 플로우) ·
`TeamStatHeader`(상세·결과표 공용 hero — 좌상단 날짜↔마감, '케미도 과학이다' 라벨 +
송명체 제목 + 그린 연령·정원 chip 의 다크 그라데이션 박스. `extra` 슬롯에 상세는
참가자 그리드·발표 조건 컨테이너를, 결과표는 베스트 케미 섹션을 주입) ·
`TeamDetailScreen`(참가 여부 무관 단일 상세 — 참가자 그리드가 hero 안에 있고(match
방은 남좌·여우 2열, 썸네일 비공개면 성별 실루엣), 미참가면 사진 공개 계약 +
[동의하고 참가]. **PIN 인풋 없음 — capability 모델**: 비밀방 문턱은 목록 문 앞
`TeamPinDialog`(check_team_password) 하나뿐이고 초대 링크(/g/:id, `receivedView` —
AppBar 닫기 X) 진입·join_team 은 검사하지 않는다. 참가자에겐 QR('이 그룹으로의
초대') + 초대 3버튼. Realtime 공통, 조인 성공은 화면 전환 없이 in-place 전환) ·
`TeamRevealScreen`(3-2-1 카운트다운 → hero 안 베스트 케미(인물 2열 + × + 등급
성어) → 케미 매트릭스(all = N×N, match = 남×여 직사각, 보는 사람 행 최상단 고정) →
나와의 케미 순위) · `team_match_card`(베스트 쌍 본인에게만 — 상태 5종: 응답 전/
대기/성사/거절/**만료**(발표+48h 무응답 = 자동 거부, 버튼 숨김)) ·
`TeamChatScreen`(성사된 쌍의 인앱 1:1 채팅, Realtime. ⋮ = 신고/차단/**채팅방
나가기**(leave_chat — 내 목록에서만 숨김·재진입 불가). 상대가 나가면 스트림에
카톡식 시스템 라인, 입력바는 유지). 정원 충족이 유일한 시작 조건 — 방장 수동 시작 없음.

기타: `LedgerPage`(코인 원장 — compat-unlock 행은 쌍 스냅샷으로 상대 사진, 제3자
쌍은 미니 페어 아바타) · `AdRewardScreen`(rewarded video) · `purchase_sheet`(코인
구매) · `UpdateGateScreen`(강제 업그레이드 게이트 — §5 app_config) ·
`AdBannerDialog`(설정 탭 배너 팝업) · `AppInfoDialog`(설정 > 앱 정보 — emotion
12종 3초 로테이션 + 버전).

리스트 공통 문법: 각 탭 필터/정렬 selector 는 스크롤 밖 sticky 바(`SortSelector` —
좌측 리스트 설명 한 줄 + 우측 popup), 아이템엔 timeago 타임스탬프(정렬 근거 데이터).

## 2. monorepo 구조

```
face/
├── shared/    # face_engine 패키지 (엔진 SSOT)
├── flutter/   # 앱 셸
├── web/     # facely.kr Workers (share SSR · /g 초대장·쇼케이스·티저 · cron)
├── python/    # DeepFace FastAPI
└── tools/     # face_shape_ml 학습 · MediaPipe task
```

**shared/lib** — 순수 Dart (platform-free 불변식, `dart compile js` 통과 필수):
`face_engine.dart`(JS export: runEngine/runCompat/runMetrics/runTeam) · `data/constants/`
(face_reference_data = 26+8 mean/sd SSOT, archetype_catchphrase, compat_hashtags,
ethnicity_factors) · `data/enums/` · `domain/models/`(face_reading_report,
physiognomy_tree) · `domain/services/`(metric_score, physiognomy_scoring,
attribute_derivation, attribute_normalize, score_calibration, archetype,
age_adjustment, yin_yang, compat/).

빌드: `cd web && pnpm build:shared` (**`-O2` 금지** — RTI subtype check 깨짐).
산출물 `web/app/lib/shared/face_engine.js` 는 commit 안 함.

**flutter/lib** — 앱 셸:

```
├── main.dart / app.dart            # entry · MainApp(IndexedStack + 딥링크 dedup)
├── config/router.dart              # GoRouter: /main · /main/ledger · /r/:id(/open) · /g/:id · /capture/confirm
├── core/                           # theme(토큰 SSOT) · hive_setup · thumbnail_paths(소유자키→캐시파일·CDN URL)
├── data/services/                  # face_shape_classifier(TFLite) · face_metadata_client(R2+DeepFace)
│                                   # · image_resizer · r2_uploader · supabase_service · auth_service
│                                   # · team_service · wallet/coin/free_coin · admob · compatibility
│                                   # · deep_link_service · analytics · app_config(강제 업그레이드)
│                                   # · ad_image(설정 탭 배너 팝업)
├── domain/services/                # face_metrics(+lateral) · life_question_narrative
│                                   # · report_assembler · share/
├── presentation/providers/         # history(claim+rehydrate) · auth · tab · team · wallet
│                                   # · free_coin · compatibility · recent_unlock_focus
├── presentation/screens/           # physiognomy/ · compatibility/ · chemistry/(캡처 포함)
│                                   # · team/ · ads/ · ledger/ · settings/
└── presentation/widgets/           # detail_avatar · sort_selector · emotion_empty_state
                                    # · coin_chip · face_scan_pill · onboarding_intro
                                    # · my_face_header · primary_button · compact_snack_bar
                                    # · login_bottom_sheet · purchase_sheet · source_badge 등
```

## 3. State Management (Riverpod 3.x)

| Type | 용도 | 예 |
|---|---|---|
| `NotifierProvider` | 상태 + mutation | `selectedTabProvider` · `authProvider` · `historyProvider` |
| `Provider` (computed) | 파생 값 | `selectedReportProvider` |
| `FutureProvider` | 비동기 read | `walletProvider` · `freeCoinProvider` · `compatibilityKeysProvider` · `compatibilityPartnerBodiesProvider` · `publicTeamsProvider` · `myTeamsProvider` |

- `historyProvider` — Hive 히스토리 SoT. 로그인 전이 시 **claim**(anon rows user_id 귀속 +
  내 관상 alias←nickname backfill + 서버의 과거 my-face 행 강등 — 방금 귀속된
  최신 관상만 is_my_face 유지) → **rehydrate**(본인 metrics 서버→로컬 복원). 내 관상
  싱글톤·별칭 '나' 정규화.
- `publicTeamsProvider`/`myTeamsProvider` — 서버 우선(로컬 캐시 없음). `TeamService`
  가 매 호출 `teams`/`public_teams`/`team_roster` 를 직접 fetch, 갱신은
  `ref.invalidate`. 로그인만 하면 웹에서 조인한 매칭도 `team_members` 조회로 그대로
  뜬다 — 별도 rehydrate 불필요. 상세 페이지는 이와 별개로 Supabase Realtime
  (`TeamService.watchTeam`)을 구독해 슬롯·상태 변화를 즉시 반영한다.
- Hive persist: raw JSON 보존, state 에 parsed report. 관상 리스트 pull-to-refresh 는
  `syncFromServer`(서버 metrics 가 진실 — 알려진 uuid 교체·서버 전용 row 복원·서버에서
  삭제된 소유 row 제거. 받은 카드·supabaseId 없는 로컬 전용 카드는 제외, 비로그인이면
  skip) → `reloadFromHive`(현재 엔진으로 완전 재계산) 순.

## 4. 데이터 흐름

**analyze → save → share**: 캡처 → InfoConfirm → `analyzeFaceReading()` →
FaceReadingReport(capture-only) → Hive + 썸네일 + `saveMetrics`(alias 포함) →
공유 = R2 썸네일 + metrics upsert + `facely.kr/r/{uuid}` (카카오 FeedTemplate 또는 OS 시트).
수신 측: 앱 = 딥링크 `/r/:id`(2초 same-path dedup), 미설치 = Workers SSR(runEngine 실계산).
받은 카드는 `ShareReceiveService` 가 `source=received`·alias null 로 override.

내 관상은 서버에 사용자당 1행, row id 영구 고정. 재촬영은 기존 row 에 새 body·새
썸네일 키로 덮어쓰고(웹 saveCapture 와 동일 모델) **옛 썸네일은 지우지 않는다** —
사진의 수명은 카드가 아니라 계정에 묶인다(탈퇴 시 폴더 통째 삭제).
케미 슬롯 FK 와 `/r/{id}` 링크는 항상 유효하며 최신
관상을 가리킨다. 신규 캡처의 "1 capture = 1 uuid" 는 유지 — 재촬영의 분석 uuid 는
썸네일 키로만 쓰인다. 예외 = 익명 촬영 → 로그인 claim: 익명 row 가 새 my-face 로
귀속되며 id 가 바뀐다 — 서버의 옛 my-face 행은 일반 카드로 강등되고(§3 claim),
케미 슬롯은 user_id live resolve 가 새 id 를 따라간다 (아래 "케미 = 최신 데이터").

**궁합 unlock**: `unlock_compat` RPC (SECURITY DEFINER 단일 트랜잭션 — 코인 -1 + compatibilities
insert + 원장 기록). 키 = (구매자, a_id<b_id 정규화 쌍 supabaseId) — 내 쌍이든 케미
매칭의 제3자 쌍이든 규칙 하나("1코인 = 두 사람의 풀이, 구매자에게 영구"), 같은 두
사람은 어디서 만나든 1회 결제. 결제 시 두 body + 두 alias 동결(self-contained) —
metrics 소멸·방 purge 와 무관하게 복원. 지갑·궁합 목록은 a/b 중 내 my-face id 가
낀 행만 필터해 기존 "내 쌍" 뷰를 유지한다.

**케미 그룹**: 방은 생성 즉시 서버에 존재한다(서버 우선, 로컬 캐시 없음). 참가는
이름 선등록이 아니라 `join_team` RPC 셀프 조인이고, 정원 충족 시 같은 트랜잭션이
참가자 전원의 현재 my-face body 를 `teams.chemistry_snapshot` 에 동결하며 상태를
`revealing` 으로 전이한다(시작 후 재촬영이 결과에 영향을 못 주는 치팅 방어). 각
클라이언트는 그 snapshot 으로 `computeTeam`(shared/`compat/team.dart` — match 방은
`matchOnly` 로 이성 쌍만 계산) 을 로컬 계산해 3-2-1 카운트다운 → 🏆 베스트 카드를
그리고, 최초 도달 클라이언트가 `submit_team_result` 로 `result_payload` 를 1회
기록한다(first-writer-wins — 입력이 snapshot 으로 동결돼 있어 후착은 무해). 같은
트랜잭션이 베스트 쌍의 slot→user 를 resolve 해 `team_matches` 에 upsert — 베스트
쌍 각자가 `respond_match` 로 수락/거절(1회, 재응답 불가. 시한 = 발표 후 48h,
경과 = 자동 거부 취급으로 클라이언트도 버튼을 숨긴다)하고 둘 다 수락하면
`opened_at` 이 찍히며 `team_messages` 인앱 1:1 채팅이 열린다. 채팅은 `leave_chat`
으로 나갈 수 있고(본인 left 플래그 — 내 목록·재진입만 닫히고 상대는 대화 유지,
상대 화면엔 카톡식 나감 시스템 라인) 이후 열람은 `result_payload` 를 그대로 렌더.
상세 페이지 슬롯의 아바타·meta·쌍 상세 unlock 은 별도로 참가자의 **현재 my-face** 를
live resolve 한다(`fetchSlotProfiles`/`fetchLiveReport`) — 밴드 계산 입력(snapshot)과
아바타 표시(live)는 서로 다른 신선도를 쓴다. 상세 라이브 반영은 Realtime(`teams`/
`team_members` 구독) + 10초 백업 폴링 상시 병행 — 이탈(`team_members` DELETE)은
filter 매칭 한계로 폴링이 커버.

**무료 코인**: rewarded video 3편 = 1🪙 (`ad_rewards`, KST 자정 reset).
첫 슬롯은 custom 영상(`ad_videos`) 우선, AdMob 폴백 — 상세는 §5 광고 체계.

**멀티디바이스**: 로그인 rehydrate(metrics 전체 + 모집 중 케미 방) + anon claim.
썸네일 표시는 전 화면 공통 3단 — 로컬 캐시 → CDN(thumbnailKey) → fallback.
캐시 파일명은 `thumbnailKey` 의 basename(sha256)에서 파생되므로 카드가 사진을
가리키는 필드는 `thumbnailKey` 하나이고, 소유자가 바뀌어도 파일 이관이 없다.
CDN 렌더는 `cdnThumbnail()` 공용 위젯 (디스크 캐시).

**사진의 주인은 사람이다** — 키가 `thumbnails/{owner}/{sha256}.jpg` 라 재촬영·카드
삭제는 사진을 지우지 않고, 지우는 사건은 탈퇴와 익명 90일뿐이다. 구매한 궁합은
결제 시점에 두 사진을 **구매자 폴더로 복사**해 얼려서, 상대가 지우거나 탈퇴해도
산 사람 화면이 안 깨진다 (`ThumbnailCopier`).

## 5. 외부 인프라

### facely.kr — Cloudflare Workers + R2 (`web/`)

| 경로 | 책임 |
|---|---|
| `GET /r/:id(/open)` | 공유 카드 SSR (1 UUID solo / `~` 2 UUID 궁합) + universal link bridge |
| `GET /g/:id(/open)` | 케미: 초대장(+웹 티저 카메라) / 결과표 쇼케이스 / 종료 안내 |
| `POST /api/r2/presign` | R2 presigned PUT (`temp/{uuid}`·`thumbnails/{owner}/{sha256}`) + /analyze HMAC 토큰. 썸네일 소유자는 서버가 요청 JWT 에서 읽는다(익명은 `scope`) — 남의 폴더에 못 쓴다. 이미 있는 객체면 409 |
| `POST /api/account/delete` | 탈퇴 — R2 `thumbnails/{uid}/` 폴더 통째 삭제 + metrics hard delete + open teams 삭제 |
| `scheduled` (Cron Triggers) | 매시: 7일 방치 방 expired + 24h revealing 고아 안전망 / 매일: 30일 teams·90일 anon metrics 정리(+ 그 행의 `thumbnails/anon-{id}/` 폴더) (`workers/cron.ts`) |
| `.well-known/*` | iOS Universal Link · Android App Link |

R2: `thumbnails/{owner}/{sha256}.jpg`(소유자별·영구, CDN `cdn.facely.kr`) · `temp/{uuid}.jpg`(1일 자동 삭제) ·
`assets/og.png`(공유 배너 800×420).

### Supabase (project `jicaenyzunjdlcxcdbfb`)

DDL SSOT: `web/db/migrations/0001_baseline.sql` (단일 baseline 직접 수정).

| Table | 핵심 컬럼 | 비고 |
|---|---|---|
| `users` | id · kakao_user_id · nickname · coins · signup_bonus_skipped | auth 1:1. nickname 은 설정에서 수정 |
| `metrics` | id · user_id(cascade) · body · alias · is_my_face · views · updated_at | updated_at = 90일 정리 기준 |
| `coins` | user_id · kind · amount · balance_after · store_transaction_id(unique) | 원장 |
| `compatibilities` | (user_id, a_id, b_id) PK (a<b 정규화 쌍) · a/b_body · a/b_alias · total_score | self-contained 스냅샷 (의도된 보존) |
| `teams` | id · owner_id · title · room_kind(all/match) · password · is_private(파생 — 봉인된 password 의 유일한 노출 창구, 제거 금지) · thumb_open · max_players(6/8/10/12) · age_min/age_max(20+, 인접 2-decade) · status · started_at · closed_at · chemistry_snapshot · result_payload | 케미 그룹 방. status `recruiting→revealing→completed/expired`, closed_at+30일 = 수명 |
| `team_members` | id · team_id(cascade) · user_id(cascade) · slot_no · gender · is_owner · joined_at | unique (team_id,user_id)·(team_id,slot_no). 쓰기는 RPC 전용(직접 insert/update/delete 정책 없음) |
| `team_matches` | team_id PK(cascade) · user_a/user_b · a_consent/b_consent · opened_at · a_left/b_left | 베스트 쌍 채팅 개설 상호 동의 — 매칭당 1행, opened_at = 둘 다 수락 시각. 응답 시한 = closed_at+48h(경과 = 자동 거부 취급). left = 채팅방 나가기(본인 목록 숨김·재진입 불가) |
| `team_messages` | id · team_id(→team_matches cascade) · sender_id · body(≤500) · created_at | 성사된 쌍 전용 인앱 1:1 채팅. 수명 = teams 30일 purge cascade |
| `ad_rewards` | (user_id, day) PK · views · claimed | KST reset — 광고 종류 무관 공통 시청 장부 |
| `ad_videos` | id · title · storage_path(`banners/*.mp4`) · duration_sec · active | custom 보상 영상 풀. 쓰기는 refine(service-role)만 |
| `ad_images` | id · title · storage_path · link_url · active · sort_order | 외부 광고주 배너 풀 — 설정 탭 진입 팝업으로 노출 (§5 광고 체계) |
| `app_config` | id(=1 단일 행) · android_min_build · ios_min_build · notice | 강제 업그레이드 정책. anon 읽기 전용, 편집은 refine '시스템' 메뉴(service-role)만. 앱은 시작 시 1회 조회 — buildNumber < min_build 면 UpdateGateScreen, 조회 실패는 fail-open |
| `bonus_recipients` | — | 가입 보너스 dedup |

RPC (SECURITY DEFINER): `increment_metrics_views` · `grant/spend/admin_grant_coins` ·
`unlock_compat` · `ad_reward_status/record_view` · `handle_new_user` · `join_team`
(match 방 성별 정원 = `GENDER_FULL`. **비밀번호 미검사** — capability 모델: 초대
링크 소지 = 초대받음, 문턱은 `check_team_password` 문 앞 dialog 만) · `leave_team` ·
`submit_team_result`(베스트 쌍 `team_matches` upsert 포함) · `respond_match`(응답
시한 closed_at+48h — 경과 시 MATCH_EXPIRED) · `leave_chat`(본인 left 플래그, 되돌리기
없음) · touch 트리거. View:
`public_teams`(모집 중 공개방 목록, 컬럼 화이트리스트) · `team_roster`(team_members
의 alias(조인 시점 이름 동결, 구행은 users.nickname 보충)·gender, owner 권한
실행으로 이름만 노출).

RLS 요점: `metrics` public read + anon insert(PII·landmarks 차단) + owner/anon-claim
update. `teams` select 는 column grant 로 password 제외 공개(link-share), insert/삭제는
owner, 상태 전이는 RPC 전용. `team_members` public read, 쓰기는 전부 RPC(`join_team`/
`leave_team`) — 직접 insert/update/delete 정책 없음. `team_matches` 는 해당 쌍
본인만 select(타 참가자에게 동의 현황 비노출), 쓰기는 RPC 전용. `team_messages` 는
`opened_at` 찍힌 매치의 쌍 본인만 select/insert(sender_id = auth.uid() 강제).
`coins`·`compatibilities`·`ad_rewards` self-read + RPC write. cron·탈퇴는 service-role.

### DeepFace (`python/`) · AdMob · 인증

- `POST /analyze {image_url}` (R2 temp presigned) → `{age, gender, ethnicity}` —
  `face_metadata_client.dart` 가 매 분석마다 사용 (이전 값 기억 안 함).
- 광고 체계 (2026-07-30 기준):
  - **보상 광고 = custom 우선 + AdMob 폴백** (`purchase_sheet._watchAd`).
    일일 3편 중 **첫 슬롯(progress==0)에만** `ad_videos` 활성 영상 무작위
    1건을 자체 플레이어(`AdRewardScreen`, R2 CDN mp4)로 노출. 영상이
    없거나 조회 실패·둘째 슬롯부터는 AdMob rewarded. 시청 완료는 양쪽
    동일하게 `ad_reward_record_view` RPC 로 카운트 (3편 = 1🪙).
  - AdMob unit 선택(`admob_service.dart`): debug 빌드 = Google 공식 test
    unit 고정(정책 보호), release = `.env` 실 unit. `.env` 는 빌드 시점에
    asset 으로 굳는다 — 값 갱신 후엔 재빌드 필수. App ID 는
    AndroidManifest/Info.plist.
  - `ad_images` 배너: 설정 탭 진입 시 팝업(`AdBannerDialog.maybeShow`,
    2026-07-30) — full-width 배너 이미지(탭·확인 = link_url) + 다시 보지
    않기(배너별 Hive 영구 제외)·닫기. 같은 실행에선 배너별 1회, 활성 배너
    중 sort_order 첫 번째 하나만. 조회 실패는 조용히 생략.
- 인증: Kakao OAuth(`facely://auth-callback` 딥링크) + email/OTP. 탈퇴 = `/api/account/delete`.
- 카카오 공유: FeedTemplate(설치) / OS 공유 시트 fallback. 상세 계약은 [KAKAO.md](../../KAKAO.md).

## 6. 빌드 / 실행

- Flutter SDK `^3.11.0` · App id `com.scienceintegration.facely` · MediaPipe `tools/face_landmarker.task`

```bash
cd web && pnpm build:shared       # 엔진 JS 산출물 (-O1)
cd flutter && flutter pub get
flutter analyze                     # 기준선 7건 (경미)
flutter test                        # 전부 green
flutter run                         # 실기 필수 — camera/MediaPipe simulator 불가
```

Platform: iOS = NSCameraUsageDescription·GADApplicationIdentifier·`applinks:facely.kr` /
Android = CAMERA·autoVerify intent-filter(`/r/`·`/g/`)·AdMob meta-data·release 서명
(`key.properties`)·R8 keep rules(TFLite).

`.env`(gitignored): SUPABASE_URL/PUBLISHABLE_KEY · R2_WORKER_BASE · FACE_META_API_BASE ·
ADMOB_REWARDED_UNIT_ID_IOS/ANDROID · WEBAPP_BASE.

모델 재학습: [`tools/face_shape_ml/README.md`](../../tools/face_shape_ml/README.md).

## 7. 신규 기능 체크리스트

1. 엔진 변경은 `shared/lib/` 에서만 (platform-free 유지) → `pnpm build:shared` + test
2. Service = `flutter/lib/data/services/`(platform) 또는 `shared/`(순수 계산)
3. Screen = `presentation/screens/feature/` + 공용 위젯 재사용 (DESIGN §2.5)
4. Supabase 스키마 = `0001_baseline.sql` 직접 수정 (파일 누적 금지) + RLS·RPC 검토
5. Monte Carlo 영향(weight/rule/reference) 시 quantile 재생성
6. 문서: 본 문서 + HOW-IT-WORKS 갱신
