# ARCHITECTURE — 화면 · 폴더 · 데이터 흐름

**최종 업데이트**: 2026-05-19
**역할**: 앱이 어떻게 조립되어 있는가 — 화면 구조, lib/ 폴더 layout, Riverpod provider 패턴, 데이터 흐름, 외부 인프라 연결.
**관련**: 엔진 동작은 [HOW-IT-WORKS.md](HOW-IT-WORKS.md), 디자인 토큰은 [DESIGN.md](DESIGN.md).

---

## 1. 앱 화면 구조

### 1.1 4-Tab IndexedStack

`main.dart` → `app.dart::MainApp` 의 `Scaffold` + `BottomNavigationBar`. 탭 전환 시 상태 유지 (IndexedStack).

| Tab | Screen | 역할 |
|---|---|---|
| 0 | `HomeScreen` | 카메라/앨범 진입 + illustration + Demographic confirm |
| 1 | `PhysiognomyScreen` | 내 관상 + 히스토리 (카메라/앨범 리스트) + 14-node expandable |
| 2 | `CompatibilityScreen` | 궁합 (compat) — 두 리포트 짝지어 매칭 |
| 3 | `SettingsScreen` | 설정 · 약관 · 로그아웃 |

탭 상태 SSOT: `presentation/providers/tab_provider.dart::selectedTabProvider`.

### 1.2 진입 화면 (HomeScreen)

```
[HomeScreen]
  └─ Image.asset('assets/images/home.png') + "관상은 과학이다." 타이틀
  ├─ [카메라로 촬영] → fullSize sheet → FaceMeshPage
  └─ [앨범에서 선택]  → fullSize sheet → AlbumCapturePage
```

두 path 모두 동일 `showModalBottomSheet` (fullSize, isScrollControlled, useSafeArea) 으로 통일감.

### 1.3 카메라 path

```
FaceMeshPage
  ├─ 흰 카드 popup modal (frontal.png + 설명) — instructional
  ├─ camera preview + mesh overlay (Red/Green)
  ├─ Auto-countdown (overlay green 안정 시 3-2-1)
  ├─ 정면 캡처 → DeepFace 백그라운드 analyze 시작
  ├─ 흰 카드 popup modal (lateral.png + 설명)
  ├─ 측면 캡처 (3/4 yaw) — 정적 banner "한쪽 귀가 안 보일 때까지 얼굴을 돌려주세요"
  └─ → DemographicConfirmScreen
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
  └─ → DemographicConfirmScreen
```

**square-padding**: non-square image (예: 9:20 phone screenshot) 에서 MediaPipe 가 landmark Y 좌표 distort 시키는 버그 차단. shorter dimension 을 흰색 padding 으로 square 화 후 MediaPipe 호출. 코드: `album_capture_page.dart::_processAlbumPhoto`.

### 1.5 DemographicConfirmScreen

```
DeepFace 추정값 (age/gender/ethnicity) 백그라운드 await
  ↓
사용자가 안 만지면 자동 prefill ("AI 추정 결과가 채워졌어요")
사용자가 만지면 그 값 유지
  ↓
[분석 시작] → analyzeFaceReading() → 리포트 생성
  ↓
thumbnail: ImageResizer.faceCenterSquareCropFromBytes (ML Kit bbox + 256 square JPG)
  ↓
history.add(report) → Hive 저장 → 관상 탭 전환
  ↓
SupabaseService.saveMetrics(report) (비동기 fire-and-forget)
```

### 1.6 리포트 화면 (PhysiognomyScreen + report)

- **AppBar**: alias 또는 demographic 라벨 (`30대 여성 동아시아인`)
- **속성 차트**: 10 attribute bar, `_ExpandableAttributeBar` 탭 → top-5 contributor (node:xx · 규칙 id · ±값)
- **음양 bar**: `_YinYangBar` 그라디언트 + skew marker
- **삼정 radar**: 상정/중정/하정 비율 시각화
- **14-node expandable**: `_ExpandableNodeBar` 탭 → band-맞춤 본문 + 세부 metric z 리스트. 성별 분기 4 node (eye/nose/mouth/cheekbone)
- **본문**: archetype intro + 8 인생 질문 + special archetype + age closing
- **공유**: `[공유]` 버튼 → R2 thumbnail PUT + Supabase metrics upsert + `share_plus(https://facely.kr/r/{uuid})`

---

## 2. lib/ 폴더 구조

```
lib/
├── main.dart                         # entry: Firebase + Hive + Supabase init
├── app.dart                          # MainApp: IndexedStack + BottomNav
├── config/
│   ├── router.dart                    # GoRouter
│   └── api_config.dart                # API base URL
├── core/
│   ├── theme.dart                    # AppTheme / AppColors / AppText / AppSpacing / AppRadius
│   ├── http/http_client.dart         # Dio Provider
│   └── hive/hive_setup.dart          # Hive 초기화 + Box 정의
├── data/
│   ├── constants/
│   │   ├── face_reference_data.dart   # 17 frontal + 8 lateral mean/sd × 6 ethnicity × 2 gender — SSOT
│   │   ├── archetype_text_blocks.dart # archetype intro/closing 정적 텍스트
│   │   ├── rule_text_blocks.dart      # Rule ID → 본문 매핑
│   │   └── node_text_blocks.dart      # 14 node × 3 band 본문 (성별 분기 포함)
│   ├── enums/                         # Attribute, Gender, AgeGroup, Ethnicity, MetricType
│   ├── datasources/
│   │   ├── remote/                    # Dio API client
│   │   └── local/                     # Hive LocalDataSource
│   ├── repositories/
│   └── services/
│       ├── face_shape_classifier.dart # TFLite 28-feat MLP (East Asian fine-tuned)
│       ├── face_metadata_client.dart  # R2 PUT + /analyze (DeepFace) + thumbnail upload
│       ├── image_resizer.dart         # faceCenterSquareCrop, resizeToWidth
│       ├── r2_uploader.dart           # Cloudflare R2 presigned PUT
│       ├── supabase_service.dart      # metrics 테이블 CRUD
│       └── analytics_service.dart
├── domain/
│   ├── models/
│   │   ├── physiognomy_tree.dart      # 14-node tree SSOT
│   │   ├── face_analysis.dart         # analyzeFaceReading() — 엔드투엔드
│   │   ├── face_reading_report.dart   # rich evidence schema + JSON serde
│   │   ├── capture_result.dart        # 카메라/앨범 캡처 결과 wrapper
│   │   ├── face_metadata.dart         # DeepFace 응답 모델
│   │   └── compatibility_report.dart
│   └── services/
│       ├── face_metrics.dart          # 17 frontal raw metric
│       ├── face_metrics_lateral.dart  # 8 lateral + yaw 분류
│       ├── physiognomy_scoring.dart   # 14-node tree + scoreTree(z)
│       ├── attribute_derivation.dart  # 5-stage pipeline + weight matrix + 62 rule
│       ├── attribute_normalize.dart   # rank+quantile → 5.0~10.0
│       ├── score_calibration.dart     # Monte Carlo quantile 생성
│       ├── archetype.dart             # 10 attr → archetype + special
│       ├── age_adjustment.dart        # 50+ 보정
│       ├── report_assembler.dart      # 본문 조립 (intro/closing wrap)
│       ├── life_question_narrative.dart # 8 섹션 Beat-Fragment 엔진
│       ├── yin_yang.dart              # 陰陽 축
│       ├── compat/                    # 궁합 엔진 (5 frame)
│       └── share/share_publisher.dart # 공유 link 생성
└── presentation/
    ├── providers/                     # Riverpod: history · auth · gender · age · ethnicity · tab · selectedTab
    ├── screens/
    │   ├── home/                      # HomeScreen · FaceMeshPage · AlbumCapturePage · DemographicConfirmScreen · ReportPage
    │   ├── physiognomy/               # 관상 탭 (히스토리 + 부위 expand UI)
    │   ├── compatibility/             # 궁합 탭
    │   ├── ads/                       # 코인 광고 시청
    │   ├── wallet/                    # 코인 잔액 + 거래 내역
    │   └── settings/
    └── widgets/                       # 공유 UI (login_bottom_sheet 등)
```

코드 파일 61개 (test 제외).

---

## 3. State Management (Riverpod 3.x)

### 3.1 Provider 종류

| Type | 용도 | 예 |
|---|---|---|
| `NotifierProvider` | 단순 상태 + mutation | `selectedTabProvider`, `genderProvider` |
| `Notifier` (복합) | 비동기 상태 + 다단계 mutation | `historyProvider`, `authProvider` |
| `Provider` (computed) | 파생 값 | `selectedReportProvider` (history + index) |
| `FutureProvider.family` | 파라미터 있는 비동기 | `metricsProvider(uuid)` |

### 3.2 Hive persist 패턴 (`history_provider.dart`)

```dart
class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  Future<void> add(FaceReadingReport r) async {
    state = [r, ...state];
    await _saveToHive();   // clear + 전량 재삽입 + flush
  }

  Future<void> reloadFromHive() async {
    // 각 entry 를 fromJsonString 으로 rehydrate
    // parse 실패 entry 는 raw JSON 살려두고 state 에서만 드롭
    // schemaVersion mismatch 자동 drop
  }
}
```

핵심: **Hive 에 raw JSON 보존**, state 에는 parsed report 만. abort guard 로 race 시 데이터 손실 방지.

### 3.3 의존성 흐름

```
Screen → Provider (ref.watch / ref.read)
       → Repository / Service
       → DataSource (Dio / Hive / Supabase)
```

DI 는 분산 — 각 service/repository 가 자체 Provider 정의 (`final fooProvider = Provider((ref) => Foo(...))`).

---

## 4. 데이터 흐름 (analyze → save → share)

```
[카메라/앨범]
   캡처 + (square-padding) + MediaPipe FaceMesh + ML Kit FaceDetector
        │
        ▼
[DemographicConfirmScreen]
   DeepFace 자동 추정 + 사용자 confirm
        │
        ▼
[analyzeFaceReading()]
   17 frontal + 8 lateral raw → z → tree → attribute → normalize → archetype
        │
        ▼
[FaceReadingReport (capture-only)]
   ├─ Hive history box (auto-increment key)
   ├─ thumbnail 생성: ImageResizer.faceCenterSquareCropFromBytes → Documents/{uuid}.jpg
   └─ SupabaseService.saveMetrics(report) (비동기, fire-and-forget)
        │
        ▼
[관상 탭 UI 진입]
   report_page.dart 가 nodeScores/attributes/rules/archetype 재계산 후 render
        │
        ▼
[공유 버튼]
   share_publisher.publishSolo(uuid)
   ├─ R2 presign + PUT thumbnail 256 JPG
   ├─ Supabase REST upsert /rest/v1/metrics (anon key, Worker 미경유)
   └─ share_plus(https://facely.kr/r/{uuid})
        │
        ▼
[수신자 카톡 탭]
   ├─ 앱 설치: universal/app link → app_links 패키지 → /r/:id → ReportPage(uuid)
   ├─ 앱 미설치: facely.kr Workers SSR 페이지 + store fallback
   └─ 카톡 크롤러: app/routes/share.tsx OG meta 동적 주입
```

---

## 5. Hive 저장 스키마 (요약)

3 개 Box (`Box<String>`):

| Box | 내용 | value 형태 |
|---|---|---|
| `history` | FaceReadingReport JSON list | JSON 문자열 |
| `prefs` | gender/ageGroup/ethnicity | enum name 문자열 |
| `auth` | Supabase 세션 | 토큰 문자열 |

**capture-only 원칙**: 저장은 raw metric + 촬영 맥락만. z-score, attributes, rules, archetype 은 load 시 현재 엔진으로 재계산. 자세한 schema 와 확장 체크리스트는 [HOW-IT-WORKS.md §6](HOW-IT-WORKS.md#6-hive-저장-capture-only) 참조.

---

## 6. 외부 인프라

### 6.1 Cloudflare Workers + R2 (`facely.kr`)

소스: `react/` (별도 디렉토리, React Router v7 SSR).

| 경로 | 책임 |
|---|---|
| `GET /r/:id` | 공유 link landing (1 UUID 관상 / 2 UUID `~` 분리 궁합) — `react/app/routes/share.tsx` |
| `POST /api/r2/presign` | R2 presigned PUT URL 발급 (Flutter thumbnail 업로드용) |
| `.well-known/apple-app-site-association` | iOS Universal Link |
| `.well-known/assetlinks.json` | Android App Link |
| R2 bucket `thumbnails/` | 256 JPG face-centered thumbnail (영구) |
| R2 bucket `temp/` | 720 JPG analyze 입력 (lifecycle 1일 자동 삭제) |

### 6.2 Supabase

- **Project**: `jicaenyzunjdlcxcdbfb`
- **Table `metrics`**: `id` (UUID) · `body` (TEXT, FaceReadingReport JSON) · `alias` · `is_my_face` · `views` · `created_at` · `updated_at`
- **RPC**: `increment_metrics_views(uuid)` — 공유 link 조회 시 views++ (inactivity cleanup active 신호)
- **DDL SSOT**: `react/db/migrations/0001_baseline.sql`. 운영 안내(접속/스모크/dev reset) 는 `flutter/docs.bak/supabase/SQL.md` (현재 react/db SSOT 와 일치하는지 확인 후 폐기 예정).

### 6.3 DeepFace Server (Python FastAPI)

소스: `python/`. Cloud Run 또는 자체 호스팅.

- **Endpoint**: `POST /analyze {image_url}` (R2 temp/ presigned URL 입력)
- **출력**: `{age: int, gender: "male"/"female", ethnicity: "eastAsian"/.../...}` — Flutter enum name 으로 정규화
- **Flutter 호출**: `face_metadata_client.dart::analyze(File)` — 720 PUT → /analyze → 256 face-center JPG PUT → FaceMetadata 반환

### 6.4 카카오 (공유)

- `share_plus` 사용 (앱 미설치 fallback 포함)
- 카톡 크롤러 → Workers SSR OG meta 동적 주입

---

## 7. 빌드 / 실행

### 7.1 환경

- Flutter SDK `^3.11.0`
- Dart `^3.11.0`
- Python 3.11 (`tools/.venv/bin/python`) — face_shape_ml 학습용
- MediaPipe face_landmarker: `tools/face_landmarker.task`

### 7.2 명령

```bash
cd /Users/chuck/Code/face/flutter

# 의존성
flutter pub get

# 정적 분석
flutter analyze

# 테스트
flutter test                              # 149 test
flutter test test/<file>.dart             # 단일 파일
flutter test test/calibration_test.dart   # Monte Carlo 재보정

# 실행 (실기 필수 — camera/MediaPipe simulator 불가)
flutter run
```

### 7.3 Platform setup

- **iOS**: `NSCameraUsageDescription` in `Info.plist`, `applinks:facely.kr` in `Runner.entitlements`
- **Android**: `CAMERA` permission + autoVerify `intent-filter` for `https://facely.kr/r/`

### 7.4 환경 변수 (`.env`, gitignored)

```
SUPABASE_URL=https://jicaenyzunjdlcxcdbfb.supabase.co
SUPABASE_ANON_KEY=...
R2_WORKER_BASE=https://api.facely.kr
FACE_META_API_BASE=https://analyze.facely.kr
```

`flutter_dotenv` 로 로드 (`main.dart` 초기화 시).

### 7.5 모델 재학습 + 배포

face shape classifier 재학습 SSOT: [`tools/face_shape_ml/README.md`](../../tools/face_shape_ml/README.md). 전체 procedure (extract → train → TFLite export → Flutter assets 자동 교체) 그 문서 참조.

---

## 8. 신규 기능 추가 체크리스트

1. **Data Model**: `data/models/` 에 Freezed 모델 (필요 시) → `flutter pub run build_runner build --delete-conflicting-outputs`
2. **DataSource**: remote (Dio) or local (Hive) abstract + Impl
3. **Service**: `data/services/` 또는 `domain/services/` 에 비즈니스 로직
4. **Provider**: NotifierProvider 또는 FutureProvider
5. **Screen**: `presentation/screens/feature/` + 위젯
6. **Router**: `config/router.dart` 에 GoRoute 추가 (필요 시)
7. **Test**: 단위 + integration. Monte Carlo 영향 시 quantile 재생성
8. **문서**: 본 문서 + HOW-IT-WORKS.md + TODO.md 갱신
