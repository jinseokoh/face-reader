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
├── main.dart                 # App entry point
├── face_mesh_page.dart       # Camera view + mesh overlay + controls
├── face_mesh_painter.dart    # CustomPainter for 468 landmarks + triangles
├── face_metrics.dart         # Landmark index constants + 12 ratio computations
├── face_reference_data.dart  # Population averages by ethnicity (6 groups)
├── face_analysis.dart        # Z-score analysis + multi-frame averaging
└── report_page.dart          # Analysis report UI with save/copy
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
- **Green**: Accurate tracking — all 3 criteria met:
  1. Confidence score >= 0.85
  2. Frame-to-frame stability (avg landmark movement < 0.005)
  3. Face width > 25% of frame

### Facial Analysis

#### 12 Metrics

| # | Metric | Formula | Description |
|---|--------|---------|-------------|
| 1 | 얼굴 종횡비 | face_height / face_width | 세로/가로 비율 |
| 2 | 상안면 비율 | dist(10,168) / face_height | 이마 비율 (forehead~nasion) |
| 3 | 중안면 비율 | dist(168,94) / face_height | 코 영역 (nasion~subnasale) |
| 4 | 하안면 비율 | dist(94,152) / face_height | 턱 영역 (subnasale~chin) |
| 5 | 눈 사이 거리 | dist(133,362) / face_width | 내안각 거리 / 얼굴 폭 |
| 6 | 눈 길이 | avg(EFL) / face_width | 눈 가로 길이 / 얼굴 폭 |
| 7 | 눈 크기 | avg(eye_h) / avg(eye_w) | 눈 세로/가로 비율 |
| 8 | 코 너비 | dist(98,327) / dist(133,362) | 콧볼 폭 / 내안각 거리 |
| 9 | 코 길이 | dist(168,94) / face_height | 코 길이 / 얼굴 높이 |
| 10 | 입 너비 | dist(61,291) / face_width | 입 폭 / 얼굴 폭 |
| 11 | 입술 두께 | dist(0,17) / face_height | 입술 높이 / 얼굴 높이 |
| 12 | 입꼬리 각도 | atan2(corner_y - center_y, dx) | 양수=올라감, 음수=내려감 (degrees) |

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

#### faceAspectRatio 보정 (MediaPipe Landmark 10 한계)

MediaPipe Face Mesh의 landmark 10(foreheadTop)은 실제 헤어라인/이마 상단까지 도달하지 않고 이마 중상부에 위치한다.
따라서 Farkas 인체계측학 기준(헤어라인~턱)으로 산출된 faceAspectRatio 레퍼런스 값을 그대로 사용하면,
faceHeight가 체계적으로 과소측정되어 모든 얼굴이 "가로로 넓은 얼굴형"으로 오판된다.

**보정 내용 (2026-04-10)**:
- 보정 계수: **0.85** (landmark 10이 실제 이마 상단 대비 약 15% 낮은 위치에 있음을 반영)
- 적용 대상: 전체 6개 인종 × 2개 성별 = 12개 faceAspectRatio 레퍼런스 (mean × 0.85, SD × 0.85)
- 예시: 동아시아 남성 1.40±0.08 → **1.19±0.07**
- 보정 계수 0.85는 추정치이며, 실측 데이터에 기반한 정밀 보정이 필요할 수 있음

#### East Asian Reference Values (Default)

비율 기준값은 위 문헌의 mm 측정값을 얼굴 폭/높이 대비 비율로 변환하여 산출 (faceAspectRatio는 MediaPipe 보정 적용):

| Metric | Mean | SD | Derivation |
|--------|------|----|------------|
| faceAspectRatio | 1.19 | 0.07 | Farkas 기준 1.40 × 0.85 보정 (MediaPipe landmark 10 한계) |
| upperFaceRatio | 0.33 | 0.03 | Neoclassical 3등분 기준 |
| midFaceRatio | 0.33 | 0.02 | Neoclassical 3등분 기준 |
| lowerFaceRatio | 0.34 | 0.03 | Neoclassical 3등분 기준 |
| intercanthalRatio | 0.27 | 0.02 | PMC9029890: ICD 36.4mm / bizygomatic ~135mm |
| eyeFissureRatio | 0.24 | 0.02 | Farkas: EFL ~32mm / bizygomatic ~135mm |
| eyeOpenness | 0.35 | 0.05 | Farkas: 동아시아 눈높이/눈길이 비 |
| nasalWidthRatio | 1.05 | 0.10 | Farkas: 콧볼 폭 ~38mm / ICD ~36mm |
| nasalHeightRatio | 0.30 | 0.02 | Farkas: 코 길이 / 얼굴 높이 |
| mouthWidthRatio | 0.38 | 0.03 | Farkas: 입 폭 / 얼굴 폭 |
| lipFullnessRatio | 0.10 | 0.02 | Farkas: 입술 높이 / 얼굴 높이 |
| mouthCornerAngle | 0.0° | 3.0° | 중립 기준, 각도 편차 |

#### Z-Score Interpretation
- |z| < 0.5 → "평균"
- 0.5 ≤ |z| < 1.0 → "약간 큼/작음"
- 1.0 ≤ |z| < 2.0 → "큼/작음"
- |z| ≥ 2.0 → "매우 큼/작음"

#### Analysis Process
1. 5프레임 연속 캡처 후 랜드마크 좌표 평균화 (노이즈 감소)
2. 평균 랜드마크에서 12개 비율 계산
3. 선택된 인종의 reference data (mean, SD)와 비교하여 Z-score 산출
4. Z-score에 따른 판정 텍스트 생성
5. 리포트 페이지에서 카테고리별 (얼굴, 눈, 코, 입) 결과 표시

### Gender-Specific Analysis
분석 파이프라인 4곳에서 성별이 반영됨:

1. **Gender Weight Deltas** (`attribute_engine.dart`): attribute별 metric 가중치가 남/여 다르게 적용
   - 예: `nasalWidthRatio` 남성 +0.05, 여성 -0.05 / `lipFullnessRatio` 남성 -0.05, 여성 +0.05
2. **Gender Rules** (`attribute_engine.dart`): 남성 전용 5개(GM-R1~R5), 여성 전용 5개(GF-R1~R5) 규칙이 해당 성별일 때만 발동
3. **Archetype Intro** (`report_assembler.dart`): archetype 소개 텍스트가 `report.gender`에 따라 다른 문구 반환
4. **Age Adjustment** (`age_adjustment.dart`): 50세 이상 보정값이 남/여 다르게 적용

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

### Album Analysis Flow (`AlbumPreviewPage._analyze`)
```
1. analyzeFaceReading() — 15 metrics, Z-score, attribute scores, archetype
2. Thumbnail 생성 — flutter_image_compress로 128px WebP 변환
   → getApplicationDocumentsDirectory()/{uuid}.webp 저장
   → report.thumbnailPath에 경로 세팅
3. historyProvider.add(report) — state prepend + Hive 저장 (thumbnailPath 포함)
4. selectedTabProvider.selectTab(1) — 히스토리 탭 전환
5. Navigator.pop() — preview 모달 닫기
6. SupabaseService().saveMetrics(report) — 비동기 Supabase 저장
   → 성공 시 report.supabaseId = uuid, Hive 재저장
```

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
