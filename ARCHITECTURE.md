# 관상 앱 아키텍처 — 3-Track 시스템

**최종 업데이트**: 2026-04-17
**상태**: Track 1 완료 · Track 2 미착수 · Track 3 운영중
**이 문서의 역할**: 세션 간·PC 간 context 인수인계의 단일 진실 원본 (single source of truth).

---

## 0. 한눈에 보는 구조

```
MediaPipe Face Mesh (468 landmarks)
          │
          ▼
┌──────────────────────────────────────────────────────────────┐
│  FaceMetrics.computeAll()  ← 28개 raw metric (얼굴형 공통 입력) │
└──────────────────────────────────────────────────────────────┘
          │
   ┌──────┼────────────┬────────────────┐
   ▼      ▼            ▼                ▼
 Track 1  Track 2     Track 3       (공통) Z-score, age adjust,
 얼굴형   관상 속성    측면 관상      archetype
 5-class  10 점수      매부리/들창코
```

---

## 1. Track 1 — 얼굴형 분류 (Face Shape Classifier)

**목적**: "내 얼굴은 둥글다/각지다/길다…" 를 사용자에게 보여주는 1단 레이블.

| 항목 | 내용 |
|---|---|
| 분류기 | 28-feature MLP, TFLite FP16 (≈12 KB) |
| 학습 데이터 | Kaggle niten19 FaceShape Dataset, N=5000 |
| 출력 클래스 | Heart · Oblong · Oval · Round · Square |
| 테스트 정확도 | **76.9%** (vs 20% random, vs 70.4% 기존 18-feature baseline) |
| 한국어 매핑 | 하트형 · 세로로 긴 얼굴형 · 계란형 · 둥근 얼굴형 · 각진 얼굴형 |
| Parity | Python↔TFLite 100% |

### 1.1 28 feature 구성
모두 `flutter/lib/domain/services/face_metrics.dart::computeAll()` 에서 계산.
순서는 `flutter/lib/data/services/face_shape_classifier.dart::featureNames` 와 정확히 일치해야 한다 (학습-추론 정렬).

**기존 18개 (2026-04-17 이전)**
1. faceAspectRatio · 2. faceTaperRatio · 3. lowerFaceFullness · 4. upperFaceRatio
5. midFaceRatio · 6. lowerFaceRatio · 7. gonialAngle · 8. intercanthalRatio
9. eyeFissureRatio · 10. eyeCanthalTilt · 11. eyebrowThickness · 12. browEyeDistance
13. nasalWidthRatio · 14. nasalHeightRatio · 15. mouthWidthRatio · 16. mouthCornerAngle
17. lipFullnessRatio · 18. philtrumLength

**이번 세션 추가 10개 (2026-04-17)**
19. eyebrowLength · 20. eyebrowTiltDirection · 21. eyebrowCurvature · 22. browSpacing
23. eyeAspect · 24. upperVsLowerLipRatio · 25. chinAngle
26. foreheadWidth · 27. cheekboneWidth · 28. noseBridgeRatio

### 1.2 이번 세션에서 고친 버그 2건
- `nasalHeightRatio` ≡ `midFaceRatio` (동일 공식 중복) → `dist(nasion,noseTip)/faceHeight` 로 수정
- `mouthCornerAngle` 에서 `midLipY` 를 x-기준으로 사용한 좌표 오류 → `midLipX` 사용으로 수정

### 1.3 관련 파일
```
# Flutter (배포)
flutter/assets/ml/face_shape_ratios.tflite    # 모델 (12 KB)
flutter/assets/ml/scaler.json                 # mu/sd ×28 + 클래스 리스트
flutter/lib/data/services/face_shape_classifier.dart  # 싱글톤 서비스
flutter/lib/main.dart                         # 앱 시작 시 preload
flutter/lib/domain/models/face_analysis.dart  # 분석 파이프라인 내 호출·stamp
flutter/lib/domain/models/face_reading_report.dart   # faceShapeLabel/Confidence 필드
flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart  # UI 소비

# 학습 (재학습 필요 시)
tools/face_shape_ml/extract_landmarks.py       # 5000장 → landmarks.npz + ratios
tools/face_shape_ml/train_face_shape.py        # MLP 학습 + TFLite FP16 export
tools/face_shape_ml/audit_features.py          # 28 feature 중요도 audit (ANOVA/MI/perm/LOO)
tools/face_shape_ml/out/landmarks.npz          # 재사용 가능한 중간 산출 (5000×468×3)
tools/face_shape_ml/out/feature_audit.md       # 사람이 읽는 audit 결과
```

### 1.4 재학습 방법
```bash
cd /Users/chuck/Code/face/tools
.venv/bin/python face_shape_ml/extract_landmarks.py   # 5000장 추출 (캐시되어 있으면 스킵)
.venv/bin/python face_shape_ml/train_face_shape.py    # MLP 학습
# 산출: out/face_shape_ratios.tflite, out/scaler.json
cp out/face_shape_ratios.tflite out/scaler.json ../flutter/assets/ml/
```

### 1.5 Fallback
ML asset 로드 실패 시 `physiognomy_screen.dart::_faceShapeLegacyLda()` 가
기존 3-class LDA (22장 학습) 로 안전망. 평상시 호출되지 않는다.

---

## 2. Track 2 — 관상 속성 규칙 (Attribute Engine)  ⚠️ 미착수

**목적**: 10개 "속성 점수" (지성, 담대함, 인자함 …) 를 0~10 으로 매겨 archetype 분류의 입력으로 쓴다.

| 항목 | 현 상태 |
|---|---|
| 엔진 | `flutter/lib/domain/services/attribute_engine.dart` |
| 속성 | 10개: wealth, leadership, intelligence, sociability, emotionality, stability, sensuality, trustworthiness, ambition, creativity |
| 규칙 | attribute별 R1~R5 세트 + 성별 전용 규칙 (GM-R1~R5, GF-R1~R5) |
| 입력 metric | **기존 17~18개만 사용 중**. 이번 세션 추가된 10 metric 미반영 |
| Z-score | `face_reference_data.dart` 에 18개 metric만 ethnicity×gender 평균/SD 있음. 10 신규 metric은 평균/SD 없음 (face_analysis.dart 에서 metricInfoList 로만 loop → 새 metric skip) |

### 2.1 착수할 때 해야 할 일
1. `face_reference_data.dart` 에 10 신규 metric 의 6 ethnicity × 2 gender 평균·SD 추가 (MediaPipe 실측 기반)
2. `metricInfoList` 에 10 신규 metric MetricInfo 엔트리 추가 (id, label, type)
3. `attribute_engine.dart` 에 신규 규칙 추가 후보:
   - chinAngle → 담대함/리더십 (날카로운 턱 = 결단력)
   - foreheadWidth → 지성 (넓은 이마 = 사색)
   - cheekboneWidth → 리더십/사회성 (도드라진 광대 = 통솔)
   - eyebrowCurvature → 감성 (곡선 = 부드러움, 직선 = 이성)
   - upperVsLowerLipRatio → 관능성
   - chinAngle + gonialAngle 조합 → 안정성
4. 표본 검증: test/real_photos_test.dart 류에 dataset 추가 후 regression 방지

### 2.2 방향 선택 (대부님 결정 필요)
- **(a) 전통 관상학 규칙 기반**: 문헌·도감에서 규칙 수집 → 수동 계수 튜닝
- **(b) 데이터 주도**: 대부님이 신뢰하는 100~200 샘플에 정답 라벨 → 회귀 학습

---

## 3. Track 3 — 측면 관상 (Lateral Physiognomy)  ✅ 기존 운영

**목적**: 3/4-view 측면 사진에서 얻는 8개 측정값 + 코 유형 분류.

| 항목 | 내용 |
|---|---|
| 엔진 | `flutter/lib/domain/services/face_metrics_lateral.dart` |
| 입력 | 사용자가 2번째로 찍는 3/4 측면 프레임 (옵션) |
| 메트릭 | nasofrontalAngle, nasolabialAngle, facialConvexity, upperLipEline, lowerLipEline, mentolabialAngle, noseTipProjection, dorsalConvexity |
| 코 유형 플래그 | aquilineNose (매부리), snubNose (들창), droopingTip, saddleNose, flatNose + 정면 조합(wide/narrow/long/short/big/small) |
| 활용처 | attribute_engine의 lateral 규칙 + report UI "측면" 섹션 |

현재 상태: 이미 동작중, 변경 불필요.

---

## 4. Pipeline Flow (런타임)

```
[home_screen]
  → 앨범/카메라 캡처 (정면 + 3/4 측면)
     │
     ▼
[analyzeFaceReading()] in face_analysis.dart
  1. FaceMetrics.computeAll()        → 28 raw metric
  2. Z-score (metricInfoList 18개만)  ← Track 2/3 용
  3. FaceShapeClassifier.predict()    ← Track 1: 5-class 라벨 stamp
  4. LateralFaceMetrics.computeAll()  ← Track 3 (측면 있을 때만)
  5. attributeEngine.evaluateRules()  ← Track 2
  6. archetype 분류
     │
     ▼
FaceReadingReport (faceShapeLabel + 10 attributeScores + lateralFlags)
     │
     ▼
[physiognomy_screen]
  _faceShape()  ← report.faceShapeLabel 우선, 없으면 LDA fallback
  archetype  ← attribute 점수 기반
```

---

## 5. 삭제된 레거시 (2026-04-17)

Track 재편 과정에서 제거된 실패/중복 시스템. 복원 금지.

**레거시 3-class LDA 파이프라인 (22장 학습, Session 3 기록)**
- `tools/calibrate_face_shape.py`, `tools/classify_unlabeled.py`, `tools/calibrate_device.py`
- `tools/out/face_calib.csv`, `tools/device_data/`
- `FACEBUG.md` (루트) — 실패 세션 1~2 + LDA 이식 스토리

**앱 내 LDA 재보정용 UI**
- `flutter/lib/presentation/widgets/face_shape_label_dialog.dart` — 앨범 업로드 후 wide/standard/long 자가 라벨링
- `flutter/lib/data/services/face_calib_export.dart` — 히스토리 CSV export
- `FaceReadingReport.calibrationLabel` 필드 + JSON 직렬화
- `home_screen.dart` 의 CSV 내보내기 버튼 및 `_exportCalibCsv()`

**face_metrics.dart 의 칼리브 전용 getter**
- `icdDistance`, `fullnessMin`, `fullnessSlope`, `taperJawLower`, `taperChinSide`, `widthSignature`, `verticalBalance`
- (`jawWidth`, `jawLowerWidth`, `chinSideWidth` 는 `lowerFaceFullness` 가 계속 쓰므로 유지)

**CNN 실험 (파킹)**
- `tools/face_shape_ml/train_cnn.py` (EfficientNetV2B0) — 63.3% 로 MLP(76.9%) 보다 낮아 배포 안 함
- `out/face_shape_cnn.tflite` (12 MB) — 보관만. 향후 dataset 확대 시 재시도 여지.

---

## 6. 현재 남은 미완료 작업

| # | 작업 | 블로커 | 우선순위 |
|---|---|---|---|
| A | 실기기 검증 (iOS/Android) — TFLite FP16 분류기 + MediaPipe parity | 대부님 기기 테스트 | 🔥 최우선 |
| B | Track 2 착수 — `attribute_engine.dart` 에 신규 10 metric 규칙 추가 | 대부님이 방향 (a/b) 결정 | 중 |
| C | `face_reference_data.dart` 10 신규 metric 의 ethnicity×gender 평균/SD 보정 | Track 2 의존 | 중 |
| D | `CLAUDE.md` (flutter/) 내 "17 metric" 표 → "28 metric" 갱신 | 단순 문서 | 낮 |
| E | CNN 재도전 — 데이터셋 확대 or 더 큰 크롭 (112→192) | 학습 자원 | 보류 |

---

## 7. 사전 정보 (다른 PC에서 이어받을 때)

### 7.1 환경
- Flutter SDK `^3.11.0` (`flutter/pubspec.yaml`)
- Python tools: `/Users/chuck/Code/face/tools/.venv/bin/python` (tensorflow, mediapipe, sklearn, scipy, pandas)
- MediaPipe face_landmarker: `tools/face_landmarker.task`

### 7.2 주요 의존성 (tflite_flutter 확인)
```yaml
# flutter/pubspec.yaml
dependencies:
  tflite_flutter: ^0.11.0
flutter:
  assets:
    - assets/ml/
```

### 7.3 Classifier 로드 검증
앱 실행 후 로그에서 아래 둘이 보이면 정상:
```
[FaceShapeClassifier] loaded — 28 features × 5 classes
[FACE SHAPE CNN] label=Oval conf=0.92 probs=0.01,0.05,0.92,0.01,0.01
```

### 7.4 학습 재현 시 경로 전제
- `DATASET = tools/datasets/kaggle_cache/datasets/niten19/face-shape-dataset/versions/2/FaceShape Dataset`
- `OUT = tools/face_shape_ml/out`
- 재학습 결과물 3개는 반드시 `flutter/assets/ml/` 로 복사 (tflite + scaler.json)

### 7.5 중요 상수 (절대 바꾸지 말 것)
- `face_analysis.dart::kLandmark10Correction = 1.05` — 이마 끝점(10) 보정; 학습·추론 모두 이 값 기준
- `extract_landmarks.py` 의 aspect correction `imgH/imgW` — Flutter 와 동일

---

## 8. 이 문서를 업데이트하는 규칙

- 새 세션에서 구조 변경 시 반드시 본 문서 먼저 갱신 → 그 다음 코드
- 완료된 작업은 §6 표에서 제거 (체크박스 대신 삭제)
- Track 간 경계를 넘는 feature 추가 시 §1.1·§2·§3 해당 섹션에 동시 반영
- 재학습 때마다 §1 "테스트 정확도" 값 갱신
