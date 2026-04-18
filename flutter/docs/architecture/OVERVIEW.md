# 관상 앱 아키텍처

**최종 업데이트**: 2026-04-18
**상태**: Track 1 운영 · Track 2 hierarchical engine 구현중 · Track 3 운영
**역할**: 세션 간·머신 간 context 인수인계의 단일 진실 원본.

---

## 0. 한눈에 보는 구조

```
MediaPipe Face Mesh (468 landmarks)
             │
             ▼
┌──────────────────────────────────────────────┐
│ FaceMetrics.computeAll() — frontal 17+ raw   │
│ LateralFaceMetrics.computeAll() — lateral 8  │
└──────────────────────────────────────────────┘
             │
             ▼
       Z-score vs 인종·성별 reference
             │
   ┌─────────┼──────────────────────┐
   ▼         ▼                      ▼
 Track 1    Track 2                Track 3
 얼굴형    관상 속성 엔진           측면 관상
 5-class   Tree → 10 attribute     매부리/들창코
 MLP       5-stage pipeline        lateral flags
```

세 track 은 동일 z-score 입력을 공유한다. archetype 분류는 Track 2 산출(10 attribute) 위에서 동작.

---

## 1. Track 1 — 얼굴형 분류 (Face Shape Classifier)

**산출**: "하트형/계란형/둥근/각진/세로로 긴 얼굴" 5-class 레이블 + confidence.

| 항목 | 내용 |
|---|---|
| 분류기 | 28-feature MLP, TFLite FP16 (≈12 KB) |
| 학습 데이터 | Kaggle niten19 FaceShape Dataset, N=5000 |
| 테스트 정확도 | 76.9% (vs 20% random) |
| Parity | Python ↔ TFLite 100% |
| 입력 | `face_metrics.dart::computeAll()` 의 28개 ratio/angle/shape |

feature 순서는 `face_shape_classifier.dart::featureNames` 와 `train_face_shape.py` 가 정확히 일치해야 한다 (학습-추론 정렬).

### 1.1 파일

```
flutter/assets/ml/face_shape_ratios.tflite       # 모델 (12 KB)
flutter/assets/ml/scaler.json                    # mu/sd ×28 + class list
flutter/lib/data/services/face_shape_classifier.dart
flutter/lib/domain/services/face_metrics.dart    # 28 feature 공식
tools/face_shape_ml/                             # 학습 스크립트
```

### 1.2 재학습

```bash
cd tools
.venv/bin/python face_shape_ml/extract_landmarks.py
.venv/bin/python face_shape_ml/train_face_shape.py
cp face_shape_ml/out/{face_shape_ratios.tflite,scaler.json} ../flutter/assets/ml/
```

---

## 2. Track 2 — Hierarchical Attribute Engine

**산출**: 10개 속성 점수 (wealth · leadership · intelligence · sociability · emotionality · stability · sensuality · trustworthiness · attractiveness · libido) 를 raw → normalize(v9) 로 0–100 스케일화.

핵심 설계: 관상 전통 taxonomy 를 tree 자료구조로 1:1 매핑한 뒤, 각 node 의 z-score 를 5-stage pipeline 에 흘려 속성별 기여를 누적한다.

### 2.1 Tree 구조 (14 노드)

```
face (root)
├── 상정 (upper)  ├─ 이마 · 미간 · 눈썹
├── 중정 (middle) ├─ 눈 · 코 · 광대 · 귀
└── 하정 (lower)  └─ 인중 · 입 · 턱
```

- **루트 metric**: faceAspectRatio, faceTaperRatio, midFaceRatio (전체 프로포션)
- **Leaf metric**: 각 부위 소속 frontal+lateral 측정치 (예: 코 → nasalWidth/Height/Angle/Projection/Dorsal…)
- **Zone**: own metric 없음. roll-up 으로만 집계 (삼정 조화 판정용)
- **귀 노드**: MediaPipe 정면 mesh 커버리지 부족으로 v1.0 미지원 (`unsupported=true`)

모든 node 는 전통 관상 메타데이터를 태그로 보유:
- **오관(五官)** — eyebrow/eye/nose/mouth/ear
- **오악(五嶽)** — forehead(남) · cheekbone(동·서) · nose(중) · chin(북)
- **사독(四瀆)** — eye(he) · nose(huai) · mouth(ji) · ear(jiang)
- **십이궁(十二宮)** — 각 leaf 가 해당 궁 매핑 (예: 코 → 재백궁·질액궁)

SSOT: `docs/engine/TAXONOMY.md`, 코드 `flutter/lib/domain/models/physiognomy_tree.dart`.

### 2.2 Node Scoring

`physiognomy_scoring.dart::scoreTree(z)` 가 입력 z-map 을 tree mirror (`NodeScore`) 로 변환:

- **own stats**: 이 node 자신의 metric 만. `ownMeanZ` (부호, 방향) + `ownMeanAbsZ` (강도)
- **roll-up stats**: 자신 + 모든 descendant metric 합산. zone/root 는 이것만 의미 있음.

이 분리 덕에 한 node 에서 **방향(signed)** 과 **distinctiveness(abs)** 를 독립 규칙으로 쓸 수 있다 — 하정이 "긍정 방향으로 강함" 과 "단순히 극단적임" 을 구분.

### 2.3 6-Stage Derivation Pipeline (engine v2, 2026-04-18)

`attribute_derivation.dart` 에서 순차 적용. 각 stage 는 기여량을 단순 합산(re-normalization 없음).

| Stage | 이름 | 역할 |
|---|---|---|
| 0 | **shape preset** | FaceShape(oval/oblong/round/square/heart/unknown) × ML 확신도 → attribute delta. 얼굴형이 관상 해석 첫 관문임을 반영 |
| 1 | **base linear** | 9-node weight matrix ×10 속성 (face/ear 제외). node 별 signed-z × weight × polarity |
| 1b | **distinctiveness** | attractiveness = symmetric bell (faceAbs≈0.7 피크 +0.20, 극단 −0.25) · intelligence(+ upper abs) · emotionality(+ lower abs) |
| 2 | **zone rules** (13) | 삼정 조화/대립 + 비율 rule (Z-01 균형·Z-04 하정 우세·Z-11 중정 비율 등) |
| 3 | **organ rules** (19) | 오관 쌍 조합 (O-EB1 눈+눈썹·O-NM1 코+입·O-EM 눈+입 임계 0.5·O-CK 광대 강 등) |
| 4 | **palace rules** (10) | 십이궁 cross-node overlay (P-01 재백+전택·P-03 복덕 임계 0.3·P-09 명궁 등) |
| 5 | gender/age/lateral | 성별 weight delta 5속성 · 50+ 규칙 4개 · 측면 flag 규칙 3개 (L-AQ 매부리 등) |

각 stage 는 `TriggeredRule` 리스트로 기록되어 **AttributeBreakdown** 에 남는다 — UI 에서 "왜 이 점수?" top-N 근거 표시에 사용. Stage 0 기여는 `'shape'` contributor 로 노출.

가중치·극성·규칙 숫자 근거: `docs/engine/ATTRIBUTES.md` v0.2. 출처는 마의상법·유장상법·신상전편 + Pallett et al. 2010 PNAS + BiSeNet parsing 영역.

### 2.4 공개 API

```dart
// 평상시 진입점
Map<Attribute, double> scores = deriveAttributeScores(
  tree: scoreTree(zMap),
  gender: Gender.male,
  isOver50: false,
  hasLateral: hasLateral,
  lateralFlags: {'aquilineNose': true, ...},
);

// 디버그·UI top-3 근거용 — stage 분해 동반
AttributeBreakdown breakdown = deriveAttributeScoresDetailed(...);
List<MapEntry<String, double>> top = breakdown.topContributors(Attribute.wealth, n: 3);
// → [('node:nose', +1.10), ('O-NM1', +2.00), ('P-01', +1.00)]
```

### 2.5 파일

```
flutter/lib/domain/models/physiognomy_tree.dart        # 14-node const tree + 메타데이터
flutter/lib/domain/services/physiognomy_scoring.dart   # NodeScore + scoreTree
flutter/lib/domain/services/attribute_derivation.dart  # 5-stage pipeline + weight matrix + rules
flutter/test/physiognomy_scoring_test.dart             # tree roll-up 단위 테스트
flutter/test/attribute_derivation_test.dart            # 5-stage + breakdown 단위 테스트

docs/engine/TAXONOMY.md                           # Tree SSOT + 노드별 metric/rule 매칭 (v2.0)
docs/engine/ATTRIBUTES.md                         # weight matrix + rule 명세 (v0.2)
```

---

## 3. Track 3 — Lateral Physiognomy

**산출**: 3/4-view 측면 프레임의 8개 각도/비율 + 코 유형 플래그.

| 항목 | 내용 |
|---|---|
| 엔진 | `flutter/lib/domain/services/face_metrics_lateral.dart` |
| 입력 | 2단계 캡처 중 두 번째 3/4 yaw 프레임 (옵션) |
| 메트릭 | nasofrontalAngle · nasolabialAngle · facialConvexity · upperLipEline · lowerLipEline · mentolabialAngle · noseTipProjection · dorsalConvexity |
| 플래그 | aquilineNose (매부리), snubNose (들창), droopingTip, saddleNose, flatNose |
| 소비자 | Track 2 stage 5 lateral 규칙 + report UI "측면" 섹션 |

Reference 는 East Asian (Korean/Han Chinese) baseline 을 타 인종에도 공용 (`_eastAsianLateral`) — 측면 인종별 데이터 부족.

---

## 4. Runtime Pipeline

```
[home_screen]
   앨범/카메라 → 정면 + 3/4 측면 캡처 (각 5프레임 평균)
          │
          ▼
[analyzeFaceReading()]  in domain/models/face_analysis.dart
   1. FaceMetrics.computeAll()          → frontal raw
   2. LateralFaceMetrics.computeAll()   → lateral raw (옵션)
   3. Z-score vs (ethnicity × gender) reference
   4. FaceShapeClassifier.predict()     → Track 1 label + confidence
      · ML < 0.5 confidence 면 3-metric fallback → 중립 입력은 unknown
      · 결과는 FaceShape 도메인 enum 으로 승격
   5. scoreTree(zMap)                   → Track 2 NodeScore
   6. deriveAttributeScores(tree, faceShape, shapeConfidence, ...) → Track 2 raw (6-stage)
   7. normalize — 40% within-face rank + 60% global quantile
   8. archetype 분류 (shape-gated special archetype overlay 포함)
          │
          ▼
FaceReadingReport (schemaVersion=2)
   · faceShape (FaceShape enum) + legacy faceShapeLabel/Confidence  (Track 1)
   · attributeScores(10) + breakdown (shapePreset 포함)              (Track 2)
   · lateralMetrics + flags                                           (Track 3)
          │
          ▼
[report_assembler.assembleReport()]
   · archetype intro (정적 블록)
   · assembleLifeQuestions()            → 8 섹션 본문 (Beat-Fragment Grammar)
   · specialArchetype / age closing     (정적 블록)
          │
          ▼
[report_page / physiognomy_screen]  — 속성 점수 차트 + top-3 근거 + archetype 스토리 + 본문
```

본문 서술 엔진은 face hash seed 로 결정론적이면서 얼굴마다 거의 겹치지 않는 prose 를 생성. 상세: [../runtime/NARRATIVE.md](../runtime/NARRATIVE.md).

---

## 5. Reference Data

- **Frontal**: Farkas anthropometry + ICD meta-analysis (PMC9029890) + NIOSH dataset.
  MediaPipe 랜드마크 분포 차이를 반영해 **2026-04-12 경험적 재보정**. 진본: `face_reference_data.dart`.
- **Lateral**: East Asian (Korean/Han Chinese) 문헌 baseline.
- **Quantile (normalize v10)**: 상관 Monte Carlo 기반 21-point CDF per gender. bone-latent + mid-latent 공동 성분 + `koreanShapeDistribution` prior 주입. 재생성은 `test/calibration_test.dart`.

---

## 6. 환경 & 재현

### 6.1 필수 환경

- Flutter SDK `^3.11.0` (`flutter/pubspec.yaml`)
- Python tools: `tools/.venv/bin/python` (tensorflow, mediapipe, sklearn)
- MediaPipe face_landmarker: `tools/face_landmarker.task`

### 6.2 주요 상수 (학습-추론 정렬 필수)

- `face_analysis.dart::kLandmark10Correction = 1.05` — 이마 끝점(10) 보정
- `extract_landmarks.py` 의 aspect correction `imgH/imgW` — Flutter 동일 적용

### 6.3 Classifier 로드 검증

앱 기동 후 로그 예:
```
[FaceShapeClassifier] loaded — 28 features × 5 classes
```

---

## 7. 문서 업데이트 규칙

- 구조 변경 시 본 문서부터 갱신 → 그 다음 코드.
- Track 경계를 넘는 feature 는 해당 섹션 모두에 동기화.
- Track 2 weight/rule 숫자 변경 시 `docs/engine/ATTRIBUTES.md` 버전 올리고 본 문서 §2 링크만 유지.
- Track 1 재학습 시 §1 "테스트 정확도" 갱신.

---

## 연관 문서

- [ATTRIBUTES.md](../engine/ATTRIBUTES.md) — weight matrix + 5-stage rule 명세
- [NORMALIZATION.md](../engine/NORMALIZATION.md) — raw → 5~10 정규화 파이프라인
- [TAXONOMY.md](../engine/TAXONOMY.md) — 14-node tree SSOT
- [COMPATIBILITY.md](../engine/COMPATIBILITY.md) — 궁합 엔진 구조
