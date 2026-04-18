# Face Mesh Analyzer App

## Overview
Flutter app that streams camera frames through MediaPipe Face Mesh (468 landmarks) and provides facial proportion analysis compared against population averages.

## Tech Stack
- **Flutter** (Dart SDK ^3.11.0)
- **camera** ^0.11.1 — camera preview and frame streaming
- **mediapipe_face_mesh** ^1.2.4 — face mesh inference (FFI + TFLite)
- **path_provider** ^2.1.0 — file saving

## Architecture

### File Structure
```
lib/
├── main.dart
├── core/                                   # Theme, Hive setup, shared utils
├── data/
│   ├── constants/face_reference_data.dart  # MetricInfo + population means/SDs (6 ethnicities × 2 genders)
│   ├── enums/                              # Gender, AgeGroup, Ethnicity, MetricType
│   └── services/supabase_service.dart
├── domain/
│   ├── models/
│   │   ├── face_analysis.dart              # analyzeFaceReading() — Z-score pipeline
│   │   └── face_reading_report.dart
│   └── services/
│       ├── face_metrics.dart               # 17 frontal ratio/angle/shape getters
│       ├── face_metrics_lateral.dart       # 8 lateral 3/4-view metrics + yaw classify
│       ├── metric_score.dart               # Z → 0-100 metric score conversion
│       ├── physiognomy_scoring.dart        # 삼정/오관 node tree + scoreTree()
│       ├── attribute_derivation.dart       # 5-stage tree → 10 raw attribute scores
│       ├── attribute_normalize.dart        # Monte Carlo quantile → normalized 5-10
│       ├── archetype.dart                  # Attribute profile → archetype classifier
│       ├── score_calibration.dart          # Offline quantile table generator
│       ├── compat_calibration.dart         # Compat label threshold Monte Carlo
│       ├── compatibility_engine.dart       # Pairwise report comparison
│       ├── report_assembler.dart           # Deterministic reading block composer
│       └── age_adjustment.dart             # 50+ adjustments
└── presentation/
    ├── providers/                          # Riverpod: gender, ageGroup, ethnicity (Hive-persisted), history, auth, tab
    ├── screens/
    │   └── home/
    │       ├── home_screen.dart            # Demographic pickers + camera/album entry
    │       ├── face_mesh_page.dart         # Camera view + mesh overlay + 2-phase capture
    │       ├── face_mesh_painter.dart
    │       ├── album_preview_page.dart     # Frontal/lateral preview with confirm callback
    │       └── report_page.dart            # Analysis report UI + PDF export
    └── widgets/
```

### Frame Processing Pipeline
```
CameraController.startImageStream()
  → Platform branch:
    Android: NV21 (yPlane + vuPlane split) → processNv21()
    iOS: BGRA → process()
  → FaceMeshResult (468 landmarks, triangles, score)
  → Tracking quality check → overlay color (Red/Green)
  → CustomPainter renders overlay
```

### Key Design Decisions
- **NV21 on Android**: Camera delivers single buffer in `planes[0]`; must split into Y (width*height bytes) and VU (remainder) for `FaceMeshNv21Image`
- **Portrait aspect ratio**: `controller.value.previewSize` is in sensor orientation (landscape); swap width/height for portrait display
- **FittedBox.cover**: Camera preview + mesh overlay share same `SizedBox` inside `FittedBox(fit: BoxFit.cover)` to keep coordinates aligned
- **Frame throttling**: `_isProcessing` flag skips frames while previous is still processing
- **ROI tracking**: `enableRoiTracking: true` — no separate face detector needed
- **Ratios over absolute values**: Normalized landmarks (0~1) make facial ratios scale-invariant

### Overlay Color System
- **Red** (default): Normal tracking
- **Green**: Accurate tracking — all 4 criteria met:
  1. Confidence score >= 0.85
  2. Frame-to-frame stability (avg landmark movement < 0.005)
  3. Face width > 25% of frame
  4. Yaw class matches current capture phase (frontal phase → `YawClass.frontal`; lateral phase → `YawClass.threeQuarter`)

### Facial Analysis

#### Frontal Metrics (17)

| # | id | 한글 | Formula | Category |
|---|----|------|---------|----------|
| 1 | faceAspectRatio | 얼굴 종횡비 | face_height / face_width | face |
| 2 | faceTaperRatio | 얼굴 테이퍼 (황금비) | jaw_width / cheekbone_width | face |
| 3 | upperFaceRatio | 상안면 비율 | dist(10,168) / face_height | face |
| 4 | midFaceRatio | 중안면 비율 | dist(168,94) / face_height | face |
| 5 | lowerFaceRatio | 하안면 비율 | dist(94,152) / face_height | face |
| 6 | gonialAngle | 하악각 | jaw angle at gonion (degrees) | face |
| 7 | intercanthalRatio | 눈 사이 거리 | dist(133,362) / face_width | eyes |
| 8 | eyeFissureRatio | 눈 길이 | avg(EFL) / face_width | eyes |
| 9 | eyeCanthalTilt | 눈꼬리 각도 | atan2 per eye, averaged (degrees) | eyes |
| 10 | eyebrowThickness | 눈썹 두께 | eyebrow arc thickness / face_height | eyes |
| 11 | browEyeDistance | 눈썹-눈 거리 | dist(brow,eye_top) / face_height | eyes |
| 12 | nasalWidthRatio | 코 너비 | dist(98,327) / dist(133,362) | nose |
| 13 | nasalHeightRatio | 코 길이 | dist(168,94) / face_height | nose |
| 14 | mouthWidthRatio | 입 너비 | dist(61,291) / face_width | mouth |
| 15 | mouthCornerAngle | 입꼬리 각도 | atan2(corner_y - center_y, dx) (degrees) | mouth |
| 16 | lipFullnessRatio | 입술 두께 | dist(0,17) / face_height | mouth |
| 17 | philtrumLength | 인중 길이 | dist(subnasale,lip_top) / face_height | mouth |

#### Lateral (3/4-view) Metrics (8)
Computed only when a second ~30-60° yaw photo is captured. Reference values
are East Asian (Korean/Han Chinese); other ethnicities currently reuse the
same baselines (`_eastAsianLateral`).

| id | 한글 | Description |
|----|------|-------------|
| nasofrontalAngle | 비전두각 | 이마-코 경계 각도 |
| nasolabialAngle | 비순각 | 코끝-인중 각도 |
| facialConvexity | 안면 돌출각 | G-Sn-Pog 각도 |
| upperLipEline | 상순 E-line 거리 | 상순 돌출 (faceHeight 정규화) |
| lowerLipEline | 하순 E-line 거리 | 하순 돌출 (faceHeight 정규화) |
| mentolabialAngle | 순이각 | 아래입술-턱 각도 |
| noseTipProjection | 코끝 돌출 | Goode-style ratio |
| dorsalConvexity | 코 등선 돌출도 | 매부리 감지용 곡률 |

Plus binary flags: `aquilineNose`, `snubNose`.

#### Reference Data Sources

**1. Farkas Anthropometric Studies**
- Leslie Farkas (1915–2008), craniofacial anthropometry의 표준 체계 수립
- 2,500명+ 대상, 166개 비율 인덱스, 5개 얼굴 영역
- Neoclassical canons: 얼굴 수직 3등분 (이마:코:턱 = 1:1:1), 수평 5등분
- 사용 데이터: 얼굴 종횡비, 눈 길이, 눈 크기, 코 너비/길이, 입 너비, 입술 두께의 인종별 평균 및 표준편차
- 참고: Farkas LG. "Anthropometry of the Head and Face." Raven Press, 1994

**2. ICD Meta-Analysis (PMC9029890)**
- "Expanding the Classic Facial Canons: A Systematic Review and Meta-Analysis of the Intercanthal Distance"
- 67개 연구, 22,638명, 118개 인종 코호트 분석
- 6개 인종 그룹별 ICD(눈 사이 거리) 평균±표준편차 (mm):
  - 동아시아: 36.4 ± 1.6
  - 백인: 31.4 ± 2.5
  - 아프리카: 38.5 ± 3.2
  - 동남아시아: 32.8 ± 2.0
  - 히스패닉: 32.3 ± 2.0
  - 중동: 31.2 ± 1.5
- 사용 데이터: `intercanthalRatio`의 인종별 기준값 산출에 사용 (ICD/bizygomatic width로 비율 변환)
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC9029890/

**3. Neoclassical Canon Validation (PMC4369102)**
- "Are Neoclassical Canons Still Valid in People From the Arabian Peninsula?"
- N=168 (남 84, 여 84), 사우디아라비아 성인
- 얼굴 3등분 비율의 실제 유효성 검증 (30~40%만 정확히 1:1:1)
- 사용 데이터: 상/중/하안면 비율의 평균±표준편차 참고
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC4369102/

**4. NIOSH Facial Anthropometric Dataset**
- 미국 3,997명 근로자, 18개 얼굴 측정값
- 인종(백인, 아프리카계, 히스패닉, 아시아계) 및 성별별 분류
- 사용 데이터: 인종 간 코 너비, 입 너비 등의 차이 패턴 참고
- URL: https://stacks.cdc.gov/view/cdc/187926
- 논문: https://pubmed.ncbi.nlm.nih.gov/20219836/

**5. MediaPipe Face Mesh Landmark Map**
- Google MediaPipe 공식 소스: `face_mesh_connections.py`
- 468개 랜드마크의 그룹 정의 (LIPS, LEFT_EYE, RIGHT_EYE, NOSE, FACE_OVAL 등)
- 개별 인덱스 매핑은 커뮤니티 참고 (GitHub Issue #1615)
- URL: https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/python/solutions/face_mesh_connections.py

#### MediaPipe Calibration (2026-04-12)

Farkas/NIOSH 등 고전 인체계측학 데이터는 **caliper 실측값 기반**이라 MediaPipe Face Mesh
랜드마크 분포와 체계적으로 차이가 난다. 원본 Farkas 값을 그대로 쓰면 실제 한국 성인 얼굴에서
z=±6~7(클램프 ±3.5)이 나와 속성 점수가 포화되었음.

**2026-04-12 재보정**: 동아시아(기본) reference mean/SD를 **MediaPipe 실제 측정 분포**에 맞춰
경험적으로 재산출. SD는 일반 얼굴이 z ∈ [-2, +2] 구간에 들어오도록 보수적으로 넓힘.

대표 조정 예:
- `faceAspectRatio` Farkas 1.40 → 측정값 기준 남 **1.32**, 여 **1.29** (SD 0.07)
- `nasalWidthRatio` Farkas ~1.05 → 측정값 기준 남 **0.93**, 여 **0.89** (SD 0.10)
  - MediaPipe 98/327이 실제 alar 최외곽이 아닌 콧구멍 옆 피부점이라 분자가 작게 잡히고,
    133/362는 epicanthal fold 영향으로 내안각이 안쪽으로 당겨져 분모는 더 작게 잡힘 → 실측 비율이 Farkas 기준보다 낮아짐.

상세 값은 `lib/data/constants/face_reference_data.dart` 참조 (진본).

#### East Asian Reference Values (Default, Female)

코드와 100% 동기화된 값. 다른 인종·성별은 같은 파일에서 확인.

| Metric | Mean | SD |
|--------|------|----|
| faceAspectRatio | 1.29 | 0.07 |
| faceTaperRatio | 0.79 | 0.05 |
| upperFaceRatio | 0.31 | 0.04 |
| midFaceRatio | 0.30 | 0.03 |
| lowerFaceRatio | 0.39 | 0.05 |
| gonialAngle | 141.0° | 6.0° |
| intercanthalRatio | 0.26 | 0.02 |
| eyeFissureRatio | 0.20 | 0.025 |
| eyeCanthalTilt | 5.0° | 4.0° |
| eyebrowThickness | 0.034 | 0.005 |
| browEyeDistance | 0.150 | 0.020 |
| nasalWidthRatio | 0.89 | 0.10 |
| nasalHeightRatio | 0.30 | 0.03 |
| mouthWidthRatio | 0.39 | 0.05 |
| mouthCornerAngle | 3.0° | 5.0° |
| lipFullnessRatio | 0.12 | 0.025 |
| philtrumLength | 0.090 | 0.020 |

#### Z-Score Interpretation
- |z| < 0.5 → "평균"
- 0.5 ≤ |z| < 1.0 → "약간 큼/작음"
- 1.0 ≤ |z| < 2.0 → "큼/작음"
- |z| ≥ 2.0 → "매우 큼/작음"

#### Analysis Process
1. 카메라 모드: 2단계 캡처 (정면 → 3/4 측면). 각 단계에서 5프레임 평균화.
   앨범 모드: 정면 사진 1장 업로드 → 3/4 측면 사진 1장 업로드 (2단계 필수).
2. 평균 랜드마크에서 17개 frontal + (있으면) 8개 lateral metric 계산
3. 선택된 인종·성별의 reference data (mean, SD)와 비교하여 Z-score 산출
4. Z-score에 따른 판정 텍스트 생성 + 10개 속성 점수 + archetype 결정
5. 리포트 페이지에서 카테고리별 (얼굴, 눈, 코, 입, 측면) 결과 표시

### Gender-Specific Analysis
분석 파이프라인 4곳에서 성별이 반영됨:

1. **Gender Weight Deltas** (`attribute_derivation.dart`, §5.1 `_genderDelta`):
   attribute별 base 노드 가중치가 남/여 다르게 적용 (예: attractiveness 에서
   `nose` 남성 +0.05·여성 -0.05, `mouth` 남성 -0.05·여성 +0.05). 신규 트리 엔진에선
   규칙 분기가 아닌 weight matrix 레벨에서 성별 차이를 반영 — 구 엔진의 GM-R/GF-R
   규칙군은 폐기됨.
2. **Quantile Normalization** (`attribute_normalize.dart`): 성별별 10-attribute
   quantile 테이블로 raw score → 5.0~10.0 정규화. 남녀 분포가 다른 attribute
   (sensuality/libido 등)에서 self-referential 랭킹 유지.
3. **Archetype Intro** (`report_assembler.dart`): archetype 소개 텍스트가
   `report.gender`에 따라 다른 문구 반환.
4. **Age Adjustment** (`age_adjustment.dart`): 50세 이상 보정값이 남/여 다르게 적용.

### Landmark Indices (most used)
| Point | Index |
|-------|-------|
| Forehead top | 10 |
| Nasion | 168 |
| Nose tip | 1 |
| Subnasale | 94 |
| Nostrils (R/L) | 98 / 327 |
| Inner eye corners | 133 / 362 |
| Outer eye corners | 33 / 263 |
| Mouth corners | 61 / 291 |
| Lip top/bottom | 0 / 17 |
| Chin | 152 |
| Face edges | 234 / 454 |

### Album Analysis Flow (`home_screen.dart::_openAlbum`)
```
1. top snackbar "정면 사진을 올려주세요" → pickImage (single)
2. MediaPipe 추론 → AlbumPreviewPage(phase=frontal) 모달
   - 사용자가 "정면 분석" 버튼 누르면 pop(true)
3. top snackbar "...측면(3/4)사진을 올려주세요." → pickImage (single)
4. MediaPipe 추론 → AlbumPreviewPage(phase=lateral) 모달
   - 사용자가 "측면 분석" 버튼 누르면 pop(true) → _runAnalysis() 실행
5. analyzeFaceReading() — 17 frontal + 8 lateral metrics, Z-score, attribute scores, archetype
6. Thumbnail 생성 — flutter_image_compress로 128px WebP 변환 → Documents/{uuid}.webp
7. historyProvider.add(report) → Hive 저장 (thumbnailPath 포함)
8. 히스토리 탭 전환 → SupabaseService().saveMetrics(report) 비동기 저장
```

* Top snackbar는 preview 화면이 열릴 때 dismiss되어 보이지 않음.
* Demographics(gender/ageGroup/ethnicity)는 Hive `prefs` 박스에 persist, 앱 재실행 시 복원.
* 셋 중 하나라도 미선택이면 홈 화면의 카메라/앨범 버튼이 비활성화.

- 히스토리 리스트에서 thumbnailPath가 있으면 40x40 둥근 썸네일, 없으면 카메라/앨범 아이콘 fallback

## Platform Setup
- **Android**: `CAMERA` permission in AndroidManifest.xml
- **iOS**: `NSCameraUsageDescription` in Info.plist
- Physical device required (camera doesn't work in simulator/emulator)

## Build & Run
```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter run
```
