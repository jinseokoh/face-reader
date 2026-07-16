# ARCHITECTURE — 화면 · 패키지 · 데이터 흐름

앱이 어떻게 조립되어 있는가. 엔진 동작은 [HOW-IT-WORKS.md](HOW-IT-WORKS.md),
디자인 토큰은 [DESIGN.md](DESIGN.md).

## 0. 한 장 요약

```
flutter/ (앱 셸: 화면·카메라·Hive·코인·인증·공유·광고·딥링크)
   └─ path dep ─▶ shared/ (face_engine — 관상·궁합 엔진 단일 SSOT)
                     └─ dart compile js -O1 ─▶ react/ (facely.kr Workers SSR + cron)
python/ (DeepFace FastAPI)          Supabase (metrics·coins·unlocks·teams·team_members)
```

룰·reference·quantile 은 `shared/` 한 곳에서만 바뀐다.

## 1. 앱 화면 구조

**4-Tab IndexedStack** (`app.dart::MainApp`, 탭 상태 = `selectedTabProvider`).
세로 고정 (`SystemChrome.setPreferredOrientations([portraitUp])`).

| Tab | Screen | 역할 |
|---|---|---|
| 0 | `PhysiognomyScreen` | 관상 — 내부 3탭 고정(카메라/앨범/북마크, 개수 표기) + 14-node 리포트 진입 |
| 1 | `CompatibilityScreen` | 궁합 — 내부 2탭(미확인/확인), 1🪙 unlock |
| 2 | `ChemistryScreen` | 케미 — 내부 2탭(내가 만든/초대받은 그룹) |
| 3 | `SettingsScreen` | 설정 · 프로필 이름 수정 · 약관 · 로그인/탈퇴 |

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

**케미 화면** (`screens/team/`): `TeamCreatePage`(스텝 플로우) · `TeamRoomScreen`(멤버
그리드 + 직접촬영/초대 3버튼 + [생성된 케미 결과표 보기]) · `TeamMatrixScreen`(N×N 밴드,
보는 사람 행 최상단, 이름 = roster 기준·방장은 nickname) · `TeamJoinScreen`(초대 합류 —
원탭/슬롯 claim). 결과표는 전원 등록 시에만 생성, 이름 중복은 입력 3지점에서 차단.

기타: `LedgerPage`(코인 원장) · `AdRewardScreen`(rewarded video) · `purchase_sheet`(코인 구매).

## 2. monorepo 구조

```
face/
├── shared/    # face_engine 패키지 (엔진 SSOT)
├── flutter/   # 앱 셸
├── react/     # facely.kr Workers (share SSR · /g 초대장·쇼케이스·티저 · cron)
├── python/    # DeepFace FastAPI
└── tools/     # face_shape_ml 학습 · MediaPipe task
```

**shared/lib** — 순수 Dart (platform-free 불변식, `dart compile js` 통과 필수):
`face_engine.dart`(JS export: runEngine/runCompat/runMetrics) · `data/constants/`
(face_reference_data = 26+8 mean/sd SSOT, archetype_catchphrase, compat_hashtags,
ethnicity_factors) · `data/enums/` · `domain/models/`(face_reading_report,
physiognomy_tree) · `domain/services/`(metric_score, physiognomy_scoring,
attribute_derivation, attribute_normalize, score_calibration, archetype,
age_adjustment, yin_yang, compat/).

빌드: `cd react && pnpm build:shared` (**`-O2` 금지** — RTI subtype check 깨짐).
산출물 `react/app/lib/shared/face_engine.js` 는 commit 안 함.

**flutter/lib** — 앱 셸:

```
├── main.dart / app.dart            # entry · MainApp(IndexedStack + 딥링크 dedup)
├── config/router.dart              # GoRouter: /main · /main/ledger · /r/:id(/open) · /g/:id · /capture/confirm
├── core/                           # theme(토큰 SSOT) · hive_setup · thumbnail_paths(로컬+CDN URL)
├── data/services/                  # face_shape_classifier(TFLite) · face_metadata_client(R2+DeepFace)
│                                   # · image_resizer · r2_uploader · supabase_service · auth_service
│                                   # · team_sync_service · wallet/coin/free_coin · admob · compat_unlock
│                                   # · deep_link_service · analytics
├── domain/services/                # face_metrics(+lateral) · life_question_narrative
│                                   # · report_assembler · team_matrix · share/
├── presentation/providers/         # history(claim+rehydrate) · auth · tab · team · wallet
│                                   # · free_coin · compat_unlock · recent_unlock_focus
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
| `NotifierProvider` | 상태 + mutation | `selectedTabProvider` · `authProvider` · `historyProvider` · `teamsProvider` |
| `Provider` (computed) | 파생 값 | `selectedReportProvider` |
| `FutureProvider` | 비동기 read | `walletProvider` · `freeCoinProvider` · `compatUnlocksProvider` · `unlockedPartnerBodiesProvider` |

- `historyProvider` — Hive 히스토리 SoT. 로그인 전이 시 **claim**(anon rows user_id 귀속 +
  내 관상 alias←nickname backfill + 서버의 과거 my-face 행 강등 — 방금 귀속된
  최신 관상만 is_my_face 유지) → **rehydrate**(본인 metrics 서버→로컬 복원) →
  팀 rehydrate 체인. 내 관상 싱글톤·별칭 '나' 정규화.
- `teamsProvider` — 케미 방 Hive SoT + lazy sync(초대 시 push, 유령 행 diff 삭제) +
  `refreshFromServer`(합류·마감 pull, 전원 등록 시 matrix_payload backfill) +
  rehydrate(모집 중인 방만 — closed 방 부활 금지).
- Hive persist: raw JSON 보존, state 에 parsed report. `reloadFromHive` 가 현재 엔진으로
  완전 재계산 (pull-to-refresh).

## 4. 데이터 흐름

**analyze → save → share**: 캡처 → InfoConfirm → `analyzeFaceReading()` →
FaceReadingReport(capture-only) → Hive + 썸네일 + `saveMetrics`(alias 포함) →
공유 = R2 썸네일 + metrics upsert + `facely.kr/r/{uuid}` (카카오 FeedTemplate 또는 OS 시트).
수신 측: 앱 = 딥링크 `/r/:id`(2초 same-path dedup), 미설치 = Workers SSR(runEngine 실계산).
받은 카드는 `ShareReceiveService` 가 `source=received`·alias/thumbnailPath null 로 override.

내 관상은 서버에 사용자당 1행, row id 영구 고정. 재촬영은 기존 row 에 새 body·새
썸네일 키로 덮어쓰고(웹 saveCapture 와 동일 모델) 옛 썸네일은 upsert 전에
`/api/r2/delete` 로 즉시 삭제. 케미 슬롯 FK 와 `/r/{id}` 링크는 항상 유효하며 최신
관상을 가리킨다. 신규 캡처의 "1 capture = 1 uuid" 는 유지 — 재촬영의 분석 uuid 는
썸네일 키로만 쓰인다. 예외 = 익명 촬영 → 로그인 claim: 익명 row 가 새 my-face 로
귀속되며 id 가 바뀐다 — 서버의 옛 my-face 행은 일반 카드로 강등되고(§3 claim),
케미 슬롯은 user_id live resolve 가 새 id 를 따라간다 (아래 "케미 = 최신 데이터").

**궁합 unlock**: `unlock_compat` RPC (SECURITY DEFINER 단일 트랜잭션 — 코인 -1 + unlocks
insert + 원장 기록). 결제 시 두 body + 두 alias 동결(self-contained) — metrics 소멸과
무관하게 `reconstructUnlockedPartners()` 복원. partner_id = 상대 supabaseId.

**케미 원격 경로**: 방은 로컬 우선(lazy sync). [카톡 초대] 첫 탭 시 push(방장 로그인 필수,
FeedTemplate hero = `cdn.facely.kr/assets/og.png`) → 합류 = `/g/:id` 딥링크 → 슬롯
claim(키 `(team_id, name)`) 또는 새 이름 → 폴링 반영. 결과표 계산은 앱에서만, 서버는
명단 + `matrix_payload`(이름+밴드) 보관.

**케미 = 최신 데이터**: `team_members` 는 metrics 스냅샷 + **user_id 사람 참조**
이중 구조. 본인 합류·방장 슬롯은 user_id 가 기록되고, 읽기(`fetchMemberReports`)가
그 유저의 **현재 my-face** 로 live resolve — my-face row 가 claim 귀속·재촬영으로
바뀌어도 결과표는 항상 최신 관상. refresh 가 live id 로 로컬 슬롯 reportId 를
self-heal 한다. 직접촬영/walk-in 슬롯(본인 계정 없음)은 user_id null, metrics
스냅샷 유지. 결과표 열람은 3단: live 계산(resolve ≥2, resolve 실패 멤버는 화면에
"계산 제외" 표기) → `matrix_payload` 스냅샷(`TeamMatrixSnapshotScreen`, 탈퇴
등으로 live 불가 시 최후 fallback) → 안내 스낵바. 유일한 동결 데이터는 궁합
unlock (구매 당시 two-body 보존 — 유료의 의미).

**무료 코인**: rewarded video 3편 = 1🪙 (`ad_rewards`, KST 자정 reset).

**멀티디바이스**: 로그인 rehydrate(metrics 전체 + 모집 중 케미 방) + anon claim.
썸네일 표시는 전 화면 공통 3단 — 로컬 파일 → CDN(thumbnailKey) → fallback.

## 5. 외부 인프라

### facely.kr — Cloudflare Workers + R2 (`react/`)

| 경로 | 책임 |
|---|---|
| `GET /r/:id(/open)` | 공유 카드 SSR (1 UUID solo / `~` 2 UUID 궁합) + universal link bridge |
| `GET /g/:id(/open)` | 케미: 초대장(+웹 티저 카메라) / 결과표 쇼케이스 / 종료 안내 |
| `POST /api/r2/presign` | R2 presigned PUT (`temp/`·`thumbnails/{YYYYMM}/`) + /analyze HMAC 토큰 |
| `POST /api/account/delete` | 탈퇴 — metrics hard delete + R2 썸네일 + open teams 삭제 |
| `scheduled` (Cron Triggers) | 매시: 48h 방치 방 종료 / 매일: 30일 teams·90일 anon metrics 정리 (`workers/cron.ts`) |
| `.well-known/*` | iOS Universal Link · Android App Link |

R2: `thumbnails/{YYYYMM}/{uuid}.jpg`(영구, CDN `cdn.facely.kr`) · `temp/`(1일 자동 삭제) ·
`assets/og.png`(공유 배너 800×420).

### Supabase (project `jicaenyzunjdlcxcdbfb`)

DDL SSOT: `react/db/migrations/0001_baseline.sql` (단일 baseline 직접 수정).

| Table | 핵심 컬럼 | 비고 |
|---|---|---|
| `users` | id · kakao_user_id · nickname · coins · signup_bonus_skipped | auth 1:1. nickname 은 설정에서 수정 |
| `metrics` | id · user_id(cascade) · body · alias · is_my_face · views · updated_at | updated_at = 90일 정리 기준 |
| `coins` | user_id · kind · amount · balance_after · store_transaction_id(unique) | 원장 |
| `unlocks` | (user_id, partner_id) PK · user_body/partner_body · user_alias/partner_alias · total_score | self-contained 스냅샷 (의도된 보존) |
| `teams` | id · owner_id · title · closed_at · matrix_payload | 케미 방. closed_at+30일 = 수명 |
| `team_members` | id · team_id(cascade) · metrics_id(set null) · name · is_owner | unique (team_id,name)·(team_id,metrics_id) |
| `ad_rewards` | (user_id, day) PK · views · claimed | KST reset |
| `bonus_recipients` | — | 가입 보너스 dedup |

RPC (SECURITY DEFINER): `increment_metrics_views` · `grant/spend/admin_grant_coins` ·
`unlock_compat` · `ad_reward_status/record_view` · `handle_new_user` · touch 트리거.

RLS 요점: `metrics` public read + anon insert(PII·landmarks 차단) + owner/anon-claim
update. `teams`/`team_members` public read(link-share), owner 관리 + 합류자 빈 슬롯
claim. `coins`·`unlocks`·`ad_rewards` self-read + RPC write. cron·탈퇴는 service-role.

### DeepFace (`python/`) · AdMob · 인증

- `POST /analyze {image_url}` (R2 temp presigned) → `{age, gender, ethnicity}` —
  `face_metadata_client.dart` 가 매 분석마다 사용 (이전 값 기억 안 함).
- AdMob rewarded: App ID = AndroidManifest/Info.plist, unit ID = `.env`.
- 인증: Kakao OAuth(`facely://auth-callback` 딥링크) + email/OTP. 탈퇴 = `/api/account/delete`.
- 카카오 공유: FeedTemplate(설치) / OS 공유 시트 fallback. 상세 계약은 [KAKAO.md](../../KAKAO.md).

## 6. 빌드 / 실행

- Flutter SDK `^3.11.0` · App id `com.scienceintegration.facely` · MediaPipe `tools/face_landmarker.task`

```bash
cd react && pnpm build:shared       # 엔진 JS 산출물 (-O1)
cd flutter && flutter pub get
flutter analyze                     # 기준선 7건 (경미)
flutter test                        # 전부 green
flutter run                         # 실기 필수 — camera/MediaPipe simulator 불가
```

Platform: iOS = NSCameraUsageDescription·GADApplicationIdentifier·`applinks:facely.kr` /
Android = CAMERA·autoVerify intent-filter(`/r/`·`/g/`)·AdMob meta-data·release 서명
(`key.properties`)·R8 keep rules(TFLite).

`.env`(gitignored): SUPABASE_URL/ANON_KEY · R2_WORKER_BASE · FACE_META_API_BASE ·
ADMOB_REWARDED_UNIT_ID_IOS/ANDROID · WEBAPP_BASE.

모델 재학습: [`tools/face_shape_ml/README.md`](../../tools/face_shape_ml/README.md).

## 7. 신규 기능 체크리스트

1. 엔진 변경은 `shared/lib/` 에서만 (platform-free 유지) → `pnpm build:shared` + test
2. Service = `flutter/lib/data/services/`(platform) 또는 `shared/`(순수 계산)
3. Screen = `presentation/screens/feature/` + 공용 위젯 재사용 (DESIGN §2.5)
4. Supabase 스키마 = `0001_baseline.sql` 직접 수정 (파일 누적 금지) + RLS·RPC 검토
5. Monte Carlo 영향(weight/rule/reference) 시 quantile 재생성
6. 문서: 본 문서 + HOW-IT-WORKS 갱신
