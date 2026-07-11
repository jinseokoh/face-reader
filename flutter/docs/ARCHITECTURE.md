# ARCHITECTURE — 화면 · 패키지 · 데이터 흐름

**최종 업데이트**: 2026-06-08 (v1.0.1)
**역할**: 앱이 어떻게 조립되어 있는가 — 화면 구조, 2-package monorepo layout, Riverpod provider 패턴, 데이터 흐름, 코인/궁합 경제, 외부 인프라 연결.
**관련**: 엔진 동작은 [HOW-IT-WORKS.md](HOW-IT-WORKS.md), 디자인 토큰은 [DESIGN.md](DESIGN.md).

---

## 0. 한 장 요약

```
┌──────────────────────────────┐   path dep    ┌──────────────────────────────┐
│  flutter/  (앱 셸)           │ ────────────▶ │  shared/  (face_engine)      │
│  화면·카메라·Hive·코인·결제  │   import      │  26+8 metric · 14 node · 10  │
│  ·인증·공유·광고·딥링크      │               │  attribute · archetype ·     │
└──────────────────────────────┘               │  궁합 5 frame · reference    │
                                                │  (단일 엔진 SSOT)            │
┌──────────────────────────────┐  dart→JS(-O1) └──────────────────────────────┘
│  react/  (share host)        │ ◀───────────────────────┘
│  facely.kr Workers SSR       │  runEngine/runCompat 호출 — 같은 엔진을 JS 로
└──────────────────────────────┘  컴파일해 share 카드를 line-by-line 동일 렌더
```

핵심: **관상·궁합 엔진은 `shared/face_engine` 단일 패키지**. Flutter 는 path dependency 로, React share host 는 `dart compile js` 산출물로 같은 엔진을 돌린다. 룰·reference·quantile 은 이 패키지 한 곳에서만 바뀐다.

---

## 1. 앱 화면 구조

### 1.1 4-Tab IndexedStack

`main.dart` → `app.dart::MainApp` 의 `Scaffold` + `BottomNavigationBar`. 탭 전환 시 상태 유지 (IndexedStack).

| Tab | Screen | 역할 |
|---|---|---|
| 0 | `ChemistryScreen` | 카메라/앨범 진입 + illustration |
| 1 | `PhysiognomyScreen` | 내 관상 + 히스토리 (카메라/앨범 리스트) + 14-node expandable |
| 2 | `CompatibilityScreen` | 궁합 (compat) — 두 리포트 짝지어 매칭 + 코인 결제 unlock |
| 3 | `SettingsScreen` | 설정 · 약관 · 로그인/로그아웃 · 계정 삭제 |

탭 상태 SSOT: `presentation/providers/tab_provider.dart::selectedTabProvider`.

**세로 고정**: `main.dart` 에서 `SystemChrome.setPreferredOrientations([portraitUp])`. 가로 미지원 — 카메라 mesh overlay·radar·hero 카드 레이아웃이 세로 전제.

### 1.2 진입 화면 (ChemistryScreen)

```
[ChemistryScreen]
  └─ Image.asset('assets/images/home.png') + "관상은 과학이다." 타이틀
  ├─ [카메라로 촬영] → fullSize sheet → FaceMeshPage
  └─ [앨범에서 선택]  → fullSize sheet → AlbumCapturePage
```

두 path 모두 동일 `showModalBottomSheet` (fullSize, isScrollControlled, useSafeArea) 으로 통일감.

### 1.3 카메라 path

```
FaceMeshPage
  ├─ 흰 카드 popup modal (frontal.png + 설명) — instructional
  ├─ camera preview + mesh overlay (Red/Green)  ← face_mesh_painter.dart
  ├─ Auto-countdown (overlay green 안정 시 3-2-1)
  ├─ 정면 캡처 → DeepFace 백그라운드 analyze 시작
  ├─ 흰 카드 popup modal (lateral.png + 설명)
  ├─ 측면 캡처 (3/4 yaw) — 정적 banner "한쪽 귀가 안 보일 때까지 얼굴을 돌려주세요"
  └─ → /capture/confirm (InfoConfirmScreen)
```

`face_mesh_page.dart` SSOT. overlay 녹색 조건 4가지:
1. confidence ≥ 0.85
2. 프레임 간 안정성 (평균 이동 < 0.005)
3. face width > 프레임 25%
4. yaw class 가 단계와 일치 (frontal → `YawClass.frontal`, lateral → `YawClass.threeQuarter`)

### 1.4 앨범 path

```
AlbumCapturePage  ← 검정 Scaffold + "얼굴 정면"/"얼굴 측면" AppBar
  ├─ image_picker → square-padding → ML Kit bbox → MediaPipe FaceMesh
  ├─ Preview + "정면 분석" 버튼
  ├─ "측면사진 선택" Dialog (lateral.png + 설명)
  ├─ 측면 사진 같은 흐름
  └─ → /capture/confirm (InfoConfirmScreen)
```

**square-padding**: non-square image (예: 9:20 phone screenshot) 에서 MediaPipe 가 landmark Y 좌표 distort 시키는 버그 차단. shorter dimension 을 흰색 padding 으로 square 화 후 MediaPipe 호출. 코드: `album_capture_page.dart::_processAlbumPhoto`.

### 1.5 InfoConfirmScreen (`/capture/confirm`)

```
DeepFace 추정값 (age/gender/ethnicity) 백그라운드 await
  ↓
사용자가 안 만지면 자동 prefill ("AI 추정 결과가 채워졌어요")
사용자가 만지면 그 값 유지
  ↓
[분석 시작] → analyzeFaceReading() → 리포트 생성
  ↓
thumbnail: ImageResizer.faceCenterSquareCropFromBytes (ML Kit bbox + 200 square JPG)
  ↓
history.add(report) → Hive 저장 → 관상 탭 전환
  ↓
SupabaseService.saveMetrics(report) (비동기 fire-and-forget)
```

route extra 는 `CaptureExtras { capture, metadataFuture }` — GoRouter 가 한 객체만 받으므로 wrapper 로 묶어 전달 (`config/router.dart`).

### 1.6 리포트 화면 (PhysiognomyScreen + ReportPage)

- **AppBar**: alias 또는 demographic 라벨 (`30대 여성 동아시아인`). deep-link 진입 시 닫기(X)/뒤로 leading 보장 (cold-start 갇힘 방지).
- **속성 차트**: 10 attribute bar, `_ExpandableAttributeBar` 탭 → top-5 contributor (node:xx · 규칙 id · ±값)
- **음양 bar**: `_YinYangBar` 그라디언트 + skew marker
- **삼정 radar**: 상정/중정/하정 비율 시각화
- **14-node expandable**: `_ExpandableNodeBar` 탭 → band-맞춤 본문 + 세부 metric z 리스트. 성별 분기 4 node (eye/nose/mouth/cheekbone)
- **본문**: archetype intro + 8 인생 질문 + special archetype + age closing
- **source badge**: 내 얼굴 / 받은 카드 구분 (`source_badge.dart`)
- **공유**: `[공유]` 버튼 → R2 thumbnail PUT + Supabase metrics upsert + `share_plus(https://facely.kr/r/{uuid})`

### 1.7 궁합 · 코인 · 지갑 화면

| Screen | route | 역할 |
|---|---|---|
| `CompatibilityScreen` | tab 2 | 두 리포트 짝짓기. 본인 얼굴(isMyFace)은 진입 시 서버 upsert |
| `CompatibilityDetailScreen` | `/r/{a}~{b}` | 궁합 결과 본문. unlock 안 됐으면 결제 sheet, 됐으면 전체 본문 |
| `LedgerPage` | `/main/ledger` | 코인 잔액 + 거래 내역 (coins 테이블) |
| `AdRewardScreen` | modal | AdMob rewarded video 시청 → 무료 코인 적립 |

결제 흐름은 `purchase_sheet.dart` (코인 구매) + `compat_unlock_service.dart` (궁합 1코인 차감 + unlock). 자세한 흐름은 §4.2.

---

## 2. monorepo 구조

```
face/
├── shared/        # ← face_engine 패키지 (관상·궁합 엔진 SSOT)
├── flutter/       # ← 앱 셸 (이 문서의 lib/)
├── react/         # ← facely.kr Cloudflare Workers share host
├── python/        # ← DeepFace FastAPI 서버
└── tools/         # ← face_shape_ml 학습 · MediaPipe task
```

### 2.1 shared/ — `face_engine` 패키지

순수 Dart 패키지. Flutter/Camera/Hive 등 platform 의존 없이 **순수 계산 로직**만. `dart compile js` 로 React 에서도 돌도록 platform-free 유지가 불변식.

```
shared/lib/
├── face_engine.dart                  # 단일 entry — runEngine / runCompat (JS export)
├── data/
│   ├── constants/
│   │   ├── face_reference_data.dart   # 26 frontal + 8 lateral mean/sd × ethnicity × gender — SSOT
│   │   │                              #   frontal: EA=AAF 11,800 gendered · 비-EA=niten19 5,000 pooled in-frame
│   │   │                              #   lateral: 정면 측정 불가 → 임상 추정 유지
│   │   ├── archetype_catchphrase.dart # archetype 카피 (share 카드 노출)
│   │   ├── compat_hashtags.dart       # 궁합 해시태그 풀
│   │   └── ethnicity_factors.dart     # 인종 보정 계수
│   └── enums/                         # Attribute, Gender, AgeGroup, Ethnicity, FaceShape, MetricType
└── domain/
    ├── models/
    │   ├── face_reading_report.dart   # rich evidence schema + JSON serde (capture-only v3)
    │   └── physiognomy_tree.dart      # 14-node tree SSOT
    └── services/
        ├── metric_score.dart          # raw metric → z
        ├── physiognomy_scoring.dart   # 14-node tree + scoreTree(z)
        ├── attribute_derivation.dart  # 5-stage pipeline + weight matrix + rule set
        ├── attribute_normalize.dart   # rank+quantile → 5.0~10.0
        ├── score_calibration.dart     # Monte Carlo quantile 생성
        ├── archetype.dart             # 10 attr → archetype + special
        ├── age_adjustment.dart        # 50+ 보정
        ├── yin_yang.dart              # 陰陽 축
        └── compat/                    # 궁합 엔진 (五行·十二宮·五官·三停·陰陽, 5 frame)
```

**빌드** (`react/` 에서 `pnpm build:shared`): `cd shared && dart compile js -O1 lib/face_engine.dart -o ../react/app/lib/shared/face_engine.js`.
**`-O2` 금지** — type elimination + class minification 이 vite/rollup ESM + workerd 단계에서 RTI subtype check 를 깨뜨린다. `-O1` (WPO + inlining 포함) 만 안전.
**JS API**: `globalThis.runEngine(metricsJson)` → solo 카드 payload, `globalThis.runCompat(jsonA, jsonB)` → 궁합 카드 payload. 둘 다 share 카드가 렌더할 minimal subset 만 노출 (친밀 챕터·갈등 시나리오 본문은 외부 노출 금지).
**산출물 commit 금지**: `react/app/lib/shared/face_engine.js(.map)` 은 `.gitignore`.

### 2.2 flutter/lib — 앱 셸

엔진을 뺀 나머지 — 화면, 카메라/MediaPipe, Hive, 인증, 코인/결제, 공유, 광고, 딥링크. 엔진 타입은 `package:face_engine/...` 로 import.

```
lib/
├── main.dart                         # entry: orientation lock + Firebase + Hive + Supabase + Kakao + dotenv
├── app.dart                          # MainApp: IndexedStack + BottomNav + 딥링크 dedup
├── config/
│   ├── router.dart                    # GoRouter (/main · /main/ledger · /r/:id(/open) · /capture/confirm)
│   └── api_config.dart
├── core/
│   ├── theme.dart                    # AppTheme / AppColors / AppText / AppSpacing / AppRadius
│   ├── http/http_client.dart         # Dio Provider
│   ├── hive/hive_setup.dart          # Hive 초기화 + Box 정의
│   └── storage/thumbnail_paths.dart  # 로컬 thumbnail 경로 helper
├── data/
│   ├── constants/                     # archetype/rule/node/metric 본문 텍스트 블록 (앱 표시 전용)
│   ├── datasources/                   # remote (Dio) / local (Hive) — metaphor
│   ├── repositories/
│   └── services/
│       ├── face_shape_classifier.dart # TFLite 28-feat MLP (East Asian fine-tuned)
│       ├── face_metadata_client.dart  # R2 PUT + /analyze (DeepFace) + thumbnail upload
│       ├── image_resizer.dart         # faceCenterSquareCrop, resizeToWidth
│       ├── r2_uploader.dart           # Cloudflare R2 presigned PUT
│       ├── supabase_service.dart      # metrics 테이블 CRUD + upsertMetricsBody
│       ├── auth_service.dart          # Kakao OAuth · email/OTP · 계정 삭제 · coins
│       ├── coin_service.dart          # 코인 상품 정의
│       ├── wallet_service.dart        # coins 원장 RPC 래퍼
│       ├── free_coin_service.dart     # 일일 무료 코인 (AdMob 3편 = 1코인, ad_rewards)
│       ├── ad_service.dart            # 광고 추상
│       ├── admob_service.dart         # AdMob rewarded video
│       ├── compat_unlock_service.dart # unlocks 테이블 + unlock_compat RPC + self-contained 복원
│       ├── deep_link_service.dart     # https://facely.kr/r/{id} universal/app link 수신
│       ├── legal_doc_service.dart     # 약관/개인정보 문서
│       └── analytics_service.dart
├── domain/
│   ├── models/                        # capture_result · face_metadata · face_analysis · coin_transaction
│   └── services/
│       ├── face_metrics.dart          # 26 frontal raw metric (landmark → 측정)
│       ├── face_metrics_lateral.dart  # 8 lateral + yaw 분류
│       ├── life_question_narrative.dart # 8 섹션 Beat-Fragment 엔진 (앱 전용 본문)
│       ├── report_assembler.dart      # 본문 조립 (intro/closing wrap)
│       ├── mc_fixtures.dart           # Monte Carlo 입력 fixture
│       └── share/                     # share_publisher · share_receive_service
└── presentation/
    ├── providers/                     # Riverpod: history · auth · tab · wallet · free_coin · compat_unlock · di
    ├── screens/
    │   ├── home/                      # ChemistryScreen · FaceMeshPage(+painter) · AlbumCapturePage · InfoConfirmScreen · ReportPage
    │   ├── physiognomy/               # 관상 탭 (히스토리 + 부위 expand UI)
    │   ├── compatibility/             # CompatibilityScreen · CompatibilityDetailScreen
    │   ├── ads/                       # AdRewardScreen
    │   ├── ledger/                    # LedgerPage (코인 잔액 + 거래 내역)
    │   └── settings/
    └── widgets/                       # login_bottom_sheet · otp_verification_sheet · login_entry_button
                                       # · purchase_sheet · account_deletion_dialog · legal_doc_sheet
                                       # · source_badge · compact_snack_bar · empty_state_placeholder
                                       # · physiognomy_info_dialog
```

`shared/lib` Dart 파일 43개 · `flutter/lib` Dart 파일 71개 (test 제외).

### 2.3 react/ — share host (요약, §6.1 상세)

`react/app/lib/traits.ts` 가 `./shared/face_engine.js` 를 import 해 `runEngine`/`runCompat` 호출. share 카드를 Flutter hero 카드와 line-by-line 동일하게 SSR. PAIR_SEP(`~`) 은 `react/app/lib/share-id.ts` 와 Flutter `deep_link_service.dart` 가 공유 — 변경 시 양쪽 동시 PR.

---

## 3. State Management (Riverpod 3.x)

### 3.1 Provider 종류

| Type | 용도 | 예 |
|---|---|---|
| `NotifierProvider` | 단순 상태 + mutation | `selectedTabProvider`, `authProvider` |
| `Notifier` (복합) | 비동기 상태 + 다단계 mutation | `historyProvider` |
| `Provider` (computed) | 파생 값 | `selectedReportProvider` (history + index) |
| `FutureProvider` | 비동기 read | `walletProvider`, `freeCoinProvider`, `compatUnlockProvider` |

주요 provider:
- `authProvider` — `AuthService.profileStream` 구독. Kakao OAuth / email+OTP 로그인, 코인 잔액, 계정 삭제.
- `historyProvider` — Hive 히스토리 + 재계산 + isMyFace 토글 + 서버 upsert.
- `walletProvider` / `freeCoinProvider` — 코인 원장 / 일일 무료 코인 진행도.
- `compatUnlockProvider` — 현 사용자의 unlock 된 pair_key 집합.
- DI 분산: 각 service 는 singleton (`Foo._()`) 또는 `di_providers.dart` 의 Provider.

### 3.2 Hive persist 패턴 (`history_provider.dart`)

```dart
class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  Future<void> add(FaceReadingReport r) async {
    state = [r, ...state];
    await _saveToHive();   // clear + 전량 재삽입 + flush
  }

  Future<void> reloadFromHive() async {
    // 1. 각 entry 를 fromJsonString 으로 rehydrate — 현재 reference·age
    //    adjustment·rule·quantile 로 완전 재계산
    // 2. parse 성공 entry 만 slim capture (rawValue only) 로 Hive 덮어쓰기
    //    parse 실패 entry 는 raw 보존, state 에서만 드롭
    // 3. 성공 entry 는 Supabase metrics.body 도 upsert (멀티디바이스 동기화)
  }
}
```

핵심: **Hive 에 raw JSON 보존**, state 에는 parsed report 만. abort guard 로 race 시 데이터 손실 방지. pull-to-refresh 가 `reloadFromHive()` 트리거.

### 3.3 의존성 흐름

```
Screen → Provider (ref.watch / ref.read)
       → Service (face_engine 엔진 호출 + Supabase/R2/Hive/AdMob)
       → DataSource (Dio / Hive / Supabase / DeepFace)
```

---

## 4. 데이터 흐름

### 4.1 analyze → save → share

```
[카메라/앨범]
   캡처 + (square-padding) + MediaPipe FaceMesh + ML Kit FaceDetector
        │
        ▼
[InfoConfirmScreen]  (/capture/confirm)
   DeepFace 자동 추정 + 사용자 confirm
        │
        ▼
[analyzeFaceReading()]   ← face_engine
   26 frontal + 8 lateral raw → z → tree → attribute → normalize → archetype
        │
        ▼
[FaceReadingReport (capture-only)]
   ├─ Hive history box (auto-increment key)
   ├─ thumbnail: ImageResizer.faceCenterSquareCropFromBytes → Documents/{uuid}.jpg
   └─ SupabaseService.saveMetrics(report) (비동기, fire-and-forget)
        │
        ▼
[관상 탭 UI 진입]
   report_page.dart 가 nodeScores/attributes/rules/archetype 재계산 후 render
        │
        ▼
[공유 버튼]
   share_publisher.publishSolo(uuid)
   ├─ R2 presign + PUT thumbnail 200 JPG
   ├─ Supabase REST upsert /rest/v1/metrics
   └─ share_plus(https://facely.kr/r/{uuid})
        │
        ▼
[수신자 카톡 탭]
   ├─ 앱 설치: universal/app link → DeepLinkService → /r/:id → ReportPage(uuid)
   │            (cold-start 이중 전달은 2초 내 same-path dedup 으로 화면 1장만)
   ├─ 앱 미설치: facely.kr Workers SSR 페이지 (runEngine 실제 엔진) + store fallback
   └─ 카톡 크롤러: react/app/routes/share.tsx OG meta 동적 주입
```

받은 카드는 `ShareReceiveService` 가 `source=received`, `isMyFace=false`, `alias/thumbnailPath=null` 로 override 후 parse — 원본 alias·local thumbnail leak 차단. Supabase row 는 read-only.

### 4.2 궁합 결제 unlock (코인 경제)

```
[CompatibilityDetailScreen]  (잠긴 상태)
   "1코인으로 전체 보기" → purchase_sheet 또는 즉시 unlock
        │
        ▼
[compat_unlock_service.unlock(pairKey, ownerBody, partnerBody, totalScore)]
   Supabase RPC unlock_compat (SECURITY DEFINER, 단일 트랜잭션):
   ├─ coins 잔액 -1 (부족하면 -1 반환)
   ├─ unlocks row insert — owner_body / partner_body / total_score 동결
   └─ coins 원장에 spend -1 기록
        │
        ▼
[전체 본문 해제]  compatUnlockProvider 가 pair_key 집합 갱신
```

**self-contained 보존**: 결제 시점에 두 사람 body 를 그대로 `unlocks` 에 동결. metrics row 가 업로드 누락·삭제·정리돼도 구매한 궁합은 `reconstructUnlockedPartners()` 로 단독 복원/표시. pair_key = `{ownerUuid}~{partnerUuid}`.

### 4.3 무료 코인 (광고 보상)

```
[AdRewardScreen] → AdMob rewarded video 시청
   → free_coin_service → RPC ad_reward_record_view
   → ad_rewards (user_id, KST day) views++
   → 3편 누적 시 1코인 자동 지급 (claimed)
```

KST 자정 기준 reset. 진행도는 `freeCoinProvider` 가 `ad_reward_status` RPC 로 read.

### 4.4 멀티디바이스

- **본인 얼굴 upsert**: isMyFace 카드는 궁합 진입·재계산 시 항상 `upsertMetricsBody` 로 서버 반영.
- **로그인 rehydrate**: 로그인하면 본인 metrics 를 서버에서 로컬 history 로 복원.
- **anon→authed claim**: anon 으로 분석·공유(user_id=null)한 row 를 로그인 후 재공유 시 본인 소유로 claim (RLS, §6.2).

---

## 5. Hive 저장 스키마 (요약)

3 개 Box (`Box<String>`):

| Box | 내용 | value 형태 |
|---|---|---|
| `history` | FaceReadingReport JSON list | JSON 문자열 (rawValue capture-only) |
| `prefs` | gender/ageGroup/ethnicity | enum name 문자열 |
| `auth` | Supabase 세션 | 토큰 문자열 |

**capture-only 원칙**: 저장은 raw metric + 촬영 맥락만. z-score, attributes, rules, archetype 은 load 시 현재 엔진(`face_engine`)으로 재계산. 자세한 schema 와 Hive↔Supabase DTO 매핑은 [HOW-IT-WORKS.md §6](HOW-IT-WORKS.md#6-hive-저장-capture-only) 참조.

---

## 6. 외부 인프라

### 6.1 Cloudflare Workers + R2 (`facely.kr`)

소스: `react/` (React Router v7 SSR). **share host 가 실제 엔진을 돌린다** — `face_engine` 을 JS 로 컴파일해 `runEngine`/`runCompat` 호출 (OG meta 만 찍는 게 아니라 카드 본문까지 동일 계산).

| 경로 | 책임 |
|---|---|
| `GET /r/:id` | 공유 link landing (1 UUID 관상 / 2 UUID `~` 분리 궁합) — `react/app/routes/share.tsx` |
| `GET /r/:id/open` | Safari same-URL guard 회피용 web bridge — `r.$id.open.tsx` (redirect-loop 수정 완료) |
| `POST /api/r2/presign` | R2 presigned PUT URL 발급 (Flutter thumbnail 업로드용) — `api.r2.presign.ts` |
| `POST /api/account/delete` | 계정 삭제 — `api.account.delete.ts` |
| `/contact` · `/privacy` · `/terms` | 정적 문서 |
| `.well-known/apple-app-site-association` | iOS Universal Link |
| `.well-known/assetlinks.json` | Android App Link |
| R2 bucket `thumbnails/` | 200 JPG face-centered thumbnail (영구) |
| R2 bucket `temp/` | 720 JPG analyze 입력 (lifecycle 1일 자동 삭제) |

엔진 산출물 `react/app/lib/shared/face_engine.js` 는 `pnpm build:shared` 로 생성 (commit 안 함). `react/app/lib/traits.ts` 가 로드 실패 시 명시적 에러로 fail-fast.

### 6.2 Supabase

- **Project**: `jicaenyzunjdlcxcdbfb`
- **DDL SSOT**: `react/db/migrations/0001_baseline.sql` (단일 baseline 파일 직접 수정 — 별도 파일 누적 금지).

테이블:

| Table | 핵심 컬럼 | 비고 |
|---|---|---|
| `users` | id · kakao_user_id · nickname · coins · signup_bonus_skipped | auth.users 1:1 프로필 |
| `metrics` | id(UUID) · user_id · body(JSON) · alias · is_my_face · views · created/updated_at | 공유 카드. updated_at 인덱스 = 90일+ 미활동 정리용 |
| `coins` | user_id · kind(purchase/spend/bonus/refund) · amount · balance_after · store_transaction_id | 코인 원장. store_tx unique 인덱스 (중복 결제 차단) |
| `unlocks` | (user_id, pair_key) PK · owner_body · partner_body · total_score | 결제한 궁합의 self-contained 스냅샷 |
| `ad_rewards` | (user_id, day) PK · views · claimed | 일일 무료 코인 진행도 (KST 자정 reset) |
| `bonus_recipients` | — | 가입 보너스 중복 차단 (no client access) |

RPC (전부 `SECURITY DEFINER`):
- `increment_metrics_views(uuid)` — 공유 link 조회 시 views++ (inactivity cleanup 신호)
- `grant_coins` / `spend_coins` / `admin_grant_coins` — 코인 증감 (service_role/authenticated 분리)
- `unlock_compat(pair_key, total_score, owner_body, partner_body)` — 코인 1 차감 + unlock insert 를 한 트랜잭션
- `ad_reward_status` / `ad_reward_record_view` — 무료 코인 진행도 read/write
- `handle_new_user` — auth.users insert 트리거 → users 프로필 + 가입 보너스
- `touch_metrics_updated_at` — 모든 UPDATE 시 updated_at 자동 touch

RLS 요점:
- `metrics`: public read. anon insert (landmarks 키 차단). owner update/delete 는 `user_id is null or user_id = auth.uid()` — 본인 행 + anon 행(claim) 허용, 타 유저 행 차단. WITH CHECK 가 결과 소유권을 본인으로 강제.
- `coins` / `ad_rewards` / `unlocks`: `user_id = auth.uid()` self-read 만. write 는 RPC 경유.
- cron · `/api/account/delete` 는 service-role 로 RLS bypass.

### 6.3 DeepFace Server (Python FastAPI)

소스: `python/`. Cloud Run 또는 자체 호스팅.

- **Endpoint**: `POST /analyze {image_url}` (R2 temp/ presigned URL 입력)
- **출력**: `{age: int, gender: "male"/"female", ethnicity: "eastAsian"/...}` — Flutter enum name 으로 정규화
- **Flutter 호출**: `face_metadata_client.dart::analyze(File)` — 720 PUT → /analyze → 200 face-center JPG PUT → FaceMetadata 반환

### 6.4 AdMob (광고 수익화)

- **App ID (Android)**: `ca-app-pub-6207520648206097~7238724168` (`AndroidManifest.xml` meta-data, production)
- **iOS**: `Info.plist` 의 `GADApplicationIdentifier`
- **Rewarded unit ID**: `.env` 의 `ADMOB_REWARDED_UNIT_ID_IOS/ANDROID` (`admob_service.dart`)
- rewarded video 3편 시청 = 무료 코인 1 (§4.3)

### 6.5 인증 (Supabase Auth)

- **Kakao OAuth**: 브라우저 → `facely://auth-callback/?code=…` deep link → Supabase SDK session 교환. router 가 auth-callback URI 를 `/main` 으로 흘려 "Page Not Found" 깜빡임 제거.
- **Email + OTP**: 가입 → 6자리 OTP 검증(`otp_verification_sheet.dart`) → 로그인. `auth_service.dart` 가 signUp/verifyOtp/resendOtp/login.
- **계정 삭제**: `account_deletion_dialog.dart` → `/api/account/delete` (service-role 로 metrics/coins/unlocks cascade).

### 6.6 카카오 (공유)

- `share_plus` 사용 (앱 미설치 fallback 포함)
- 카톡 크롤러 → Workers SSR OG meta 동적 주입

---

## 7. 빌드 / 실행

### 7.1 환경

- Flutter SDK `^3.11.0` / Dart `^3.11.0`
- Python 3.11 (`tools/.venv/bin/python`) — face_shape_ml 학습용
- MediaPipe face_landmarker: `tools/face_landmarker.task`
- App id: `com.scienceintegration.facely`

### 7.2 명령

```bash
# 엔진 패키지 (React 용 JS 산출물)
cd /Users/chuck/Code/face/react
pnpm build:shared          # shared/lib/face_engine.dart → react/app/lib/shared/face_engine.js (-O1)

# Flutter 앱
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter analyze            # 0 issues 기대
flutter test               # test 24 파일 전부 green
flutter test test/calibration_test.dart   # Monte Carlo 재보정
flutter run                # 실기 필수 — camera/MediaPipe simulator 불가
```

엔진 룰/reference/quantile 은 `shared/` 에서만 수정. 수정 후 Flutter test + (React 반영 시) `pnpm build:shared` 재실행.

### 7.3 Platform setup

- **iOS**: `NSCameraUsageDescription` + `GADApplicationIdentifier` in `Info.plist`, `applinks:facely.kr` in `Runner.entitlements`
- **Android**:
  - `CAMERA` permission + autoVerify `intent-filter` for `https://facely.kr/r/`
  - AdMob `APPLICATION_ID` meta-data (production)
  - **릴리스 서명**: `android/key.properties` (gitignored) 존재 시 release 서명, 없으면 debug fallback (`build.gradle.kts` signingConfigs)
  - **R8 keep rules**: `proguard-rules.pro` — TFLite GPU delegate 누락 클래스로 R8 가 release appbundle 빌드를 깨지 않게 keep/dontwarn

### 7.4 환경 변수 (`.env`, gitignored)

```
SUPABASE_URL=https://jicaenyzunjdlcxcdbfb.supabase.co
SUPABASE_ANON_KEY=...
R2_WORKER_BASE=https://api.facely.kr
FACE_META_API_BASE=https://analyze.facely.kr
ADMOB_REWARDED_UNIT_ID_IOS=...
ADMOB_REWARDED_UNIT_ID_ANDROID=...
```

`flutter_dotenv` 로 로드 (`main.dart` 초기화 시).

### 7.5 모델 재학습 + 배포

face shape classifier 재학습 SSOT: [`tools/face_shape_ml/README.md`](../../tools/face_shape_ml/README.md). 전체 procedure (extract → train → TFLite export → Flutter assets 자동 교체) 그 문서 참조.

---

## 8. 신규 기능 추가 체크리스트

1. **엔진 변경?** → `shared/lib/` 에서만. 룰·reference·quantile·궁합 frame 은 platform-free 유지 (`dart compile js` 통과). 변경 후 `pnpm build:shared` + Flutter test.
2. **Data Model**: 앱 전용은 `flutter/lib/data/models/`, 엔진 공유는 `shared/lib/domain/models/`
3. **Service**: `flutter/lib/data/services/` (platform) 또는 `shared/lib/domain/services/` (순수 계산)
4. **Provider**: NotifierProvider 또는 FutureProvider
5. **Screen**: `presentation/screens/feature/` + 위젯
6. **Router**: `config/router.dart` 에 GoRoute 추가 (필요 시)
7. **Supabase**: 스키마 변경은 `react/db/migrations/0001_baseline.sql` 직접 수정 (단일 baseline). RLS·RPC 동반 검토
8. **Test**: 단위 + integration. Monte Carlo 영향 시 quantile 재생성
9. **문서**: 본 문서 + HOW-IT-WORKS.md 갱신
