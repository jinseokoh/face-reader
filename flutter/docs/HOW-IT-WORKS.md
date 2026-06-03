# HOW IT WORKS — 관상 엔진 기술 구현

**최종 업데이트**: 2026-06-03 (v1.0.1)
**역할**: 얼굴 입력부터 리포트 본문까지, 엔진이 무엇을 어떻게 계산하는지의 SSOT.
**관련**: 화면·폴더 구조는 [ARCHITECTURE.md](ARCHITECTURE.md), 디자인 토큰은 [DESIGN.md](DESIGN.md).

---

## 1. 파이프라인 한눈에

```
MediaPipe Face Mesh (468 landmarks · 정면 + 3/4 측면)
        │
        ▼
FaceMetrics.computeAll()       → 26 frontal raw metric
LateralFaceMetrics.computeAll() → 8 lateral raw metric (옵션)
        │
        ▼
z-score vs (ethnicity × gender) reference
   + age adjustment (50+ 보정)
        │
   ┌────┴────────────────────────┬──────────────────┐
   ▼                             ▼                  ▼
Track 1 — Face Shape       Track 2 — Attribute  Track 3 — Lateral
TFLite 28-feat MLP         14-node tree +       8 metric + 5 flag
oval/oblong/round/         5-stage pipeline →   (aquiline 등)
square/heart               10 attribute raw
                                 │
                                 ▼
                           rank+quantile normalize
                           → 5.0~10.0 (10 속성)
                                 │
                                 ▼
                           classifyArchetype
                           (primary + secondary + special)
                                 │
                                 ▼
                           report_assembler
                           + life_question_narrative
                           (8 인생 질문 섹션)
                                 │
                                 ▼
                           FaceReadingReport
                           (Hive 저장 + Supabase mirror)
```

핵심 entry point: `flutter/lib/domain/models/face_analysis.dart::analyzeFaceReading()` (오케스트레이션).

### 1.1 코드 위치 — `face_engine` 공유 패키지

엔진 계산은 platform-free 순수 Dart 패키지 **`shared/`** (`package:face_engine`) 에 산다. Flutter 앱은 path dependency 로, React share host 는 `dart compile js -O1` 산출물로 **같은 엔진**을 돌린다 (룰·reference·quantile 은 `shared/` 한 곳에서만 바뀐다). landmark 측정·MediaPipe·Hive·UI 등 platform 의존부만 `flutter/lib/` 에 남는다.

| 위치 | 파일 |
|---|---|
| **`shared/lib/`** (face_engine) | `physiognomy_tree` · `face_reading_report` · `metric_score`(raw→z) · `physiognomy_scoring` · `attribute_derivation` · `attribute_normalize` · `score_calibration` · `archetype` · `age_adjustment` · `yin_yang` · `compat/` · `face_reference_data` · enums · `archetype_catchphrase`/`compat_hashtags`/`ethnicity_factors` |
| **`flutter/lib/`** (앱) | `face_analysis`(analyzeFaceReading) · `face_metrics`(+lateral, landmark→측정) · `life_question_narrative` · `report_assembler` · `node`/`rule`/`archetype`/`metric` text_blocks · `face_shape_classifier` |

React JS export (`shared/lib/face_engine.dart`): `globalThis.runEngine(metricsJson)` → solo 카드, `globalThis.runCompat(jsonA, jsonB)` → 궁합 카드. 빌드 `cd react && pnpm build:shared` (`-O2` 금지 — RTI subtype check 깨짐). 산출물 `react/app/lib/shared/face_engine.js` 는 commit 안 함.

아래 본문의 bare 파일명(`physiognomy_scoring.dart` 등) 은 위 표로 위치를 찾는다.

---

## 2. 26 Frontal + 8 Lateral Metric

### 2.1 Frontal 26 — 핵심 17 + 보조 9 (`face_metrics.dart::computeAll()`)

| Category | Metric | 관상 의미 |
|---|---|---|
| face | `faceAspectRatio` | 얼굴형 기본 구조 (장/원/방형) |
| face | `faceTaperRatio` | V형 vs 사각형 |
| face | `upperFaceRatio` | 초년운 · 지성 |
| face | `midFaceRatio` | 중년운 · 사회 활동성 |
| face | `lowerFaceRatio` | 말년운 · 의지력 |
| face | `gonialAngle` | 의지력 · 리더십 · 항산 |
| eyes | `intercanthalRatio` | 사고 범위 · 개방성 |
| eyes | `eyeFissureRatio` | 통찰력 · 사회성 |
| eyes | `eyeCanthalTilt` | 매력 · 처첩궁 |
| eyes | `eyebrowThickness` | 의지력 · 성격 강도 |
| eyes | `browEyeDistance` | 인내심 · 사고 깊이 |
| nose | `nasalWidthRatio` | 재백궁 핵심 · 재물 |
| nose | `nasalHeightRatio` | 재백궁 규모 · 중년운 |
| mouth | `mouthWidthRatio` | 사회성 · 언변 |
| mouth | `mouthCornerAngle` | 낙관성 · 출납관 |
| mouth | `lipFullnessRatio` | 감정 표현 · 애정 |
| mouth | `philtrumLength` | 생명력 · 자식운 · 정력 |

추가 9개 (face shape classifier 28-feature 입력용 + 보조 metric):
`lowerFaceFullness`, `eyeAspect`, `eyebrowCurvature`, `eyebrowTiltDirection`,
`browSpacing`, `upperVsLowerLipRatio`, `chinAngle`, `foreheadWidth`, `cheekboneWidth`.

전체 ID 목록 + 코드 SSOT: `shared/lib/data/constants/face_reference_data.dart::metricInfoList`.

### 2.2 Lateral 8 (`face_metrics_lateral.dart::computeAll()`)

yaw ∈ [0.70, 0.88] (3/4 view) 만 수락. East Asian baseline (인종 fallback 공용).

| ID | 의미 | reference mean (F) |
|---|---|---|
| `nasofrontalAngle` | 비전두각 | ~141° |
| `nasolabialAngle` | 비순각 (tip rotation) | 130~140° |
| `facialConvexity` | 안면 돌출각 | ~7.7° |
| `upperLipEline` | 상순 E-line 거리 | ~-1mm |
| `lowerLipEline` | 하순 E-line 거리 | 동일 규약 |
| `mentolabialAngle` | 순이각 | ~134° |
| `noseTipProjection` | 코끝 돌출 (Goode 유사) | — |
| `dorsalConvexity` | 코 등선 곡률 | — |

5 lateral flag (정수 z 임계 기반, `face_analysis.dart`):
- `aquilineNose`: dorsalConvexity z ≥ 3 (매부리)
- `snubNose`: nasolabialAngle z ≥ 2 AND raw ≥ 115° (들창)
- `droopingTip`: nasolabialAngle z ≤ -2 AND raw ≤ 112°
- `saddleNose`: dorsalConvexity z ≤ -3
- `flatNose`: noseTipProjection z ≤ -3

### 2.3 선정 근거

- **전통**: 麻衣相法·柳莊相法·神相全編 3 대 고전의 부위별 metric.
- **현대**: Farkas anthropometry (1994) + ICD meta-analysis (PMC9029890) + NIOSH dataset.
- **재보정 (v2.8)**: MediaPipe 좌표계 차이 흡수 위해 2026-04-12 경험적 재보정. N=14 East Asian female 30s 실사용자 empirical z 가 N(0,1) 에 수렴하도록 reference mean 19 metric 재조정.
- **AAF 재보정 (2026-06-01, 현행)**: All-Age-Faces 실사진 11,800장(정면 yaw<18°, male=5361·female=6439)을 앱과 동일 파이프라인으로 측정한 metric별 empirical mean/std 로 `referenceData[eastAsian]` 26 metric 전면 교체. 추정치 reference 가 production z 를 +로 띄워 전 속성이 saturate 되던 문제 근본 해소. 검증: 실측 11,800장 재투입 시 점수 SD 1.0~1.5 회복, sensuality 1위 빈도 4.9% (편향 제거). 추출: `tools/face_shape_ml/extract_aaf.py`. 측면 8 metric 은 정면 표본으로 측정 불가 → 미변경.
- **niten19 비-EA 재보정 (2026-06-03, 현행)**: 비-동아시아 5 인종(caucasian·african·southeastAsian·hispanic·middleEastern)의 frontal 26 metric 을 niten19 Kaggle FaceShape 5,000장으로 **AAF 와 동일 파이프라인**(MediaPipe 468 → compute_ratios, near-frontal yaw/pitch<18°) 재측정한 pooled empirical 값으로 교체. 동기: 임상 anthropometry 추정치가 우리 2D proxy frame 과 frame 이 달라(예: 임상 gonialAngle ~120° vs 우리 파이프라인 ~140°) 체계적 +z 편향을 일으켰음 — niten19 in-frame 재측정으로 EA·비-EA reference 가 같은 frame 에 정렬. 한계(의도적): niten19 는 인종·성별 라벨 없음 → 5 인종 공용 **단일 pooled baseline**, gender-pooled(male=female), 얼굴형 균형 표본이라 SD 약간 inflated. 한국 관상 앱 특성상 비-EA 사용자가 소수라 per-ethnicity 보정 전까지 fallback 으로 충분. 추출: `tools/face_shape_ml/extract_niten_reference.py`. 측면 8 metric 은 정면 표본 측정 불가 → 임상 추정 유지.

### 2.4 측정 명세 — landmark 기하 정의 + z 해석 (관상 해설의 근원)

각 metric 의 z = (측정값 − μ) / σ. 모든 룰은 이 z 임계로 발동하므로 **μ/σ 가 "평균 이상/이하" 판정의 기준선**이고, 아래 z 해석이 곧 관상 해설의 1차 근거다. 좌표 기준: `faceWidth = dist(234,454)`, `faceHeight = dist(10,152)`. 대부분 비율이라 scale-invariant.

코드 SSOT: `face_metrics.dart::computeAll()`. 재보정 운영 명세: `tools/face_shape_ml/RECALIBRATION-metrics-spec.md`.

**A. 정면에서 측정 가능 (26개) — pooled 인간 표본으로 μ/σ 재보정 대상**

> μ/σ 컬럼 = AAF 재보정 여성(N=6439) empirical 값 (남성 등 SSOT 는 `face_reference_data.dart`).

| # | 항목 (id) | 측정 정의 (landmark · 공식) | 타입 | μ/σ (AAF♀) | z>0 (큼) 해석 | z<0 (작음) 해석 | 주 영향 |
|---|---|---|---|---|---|---|---|
| 1 | `faceAspectRatio` 얼굴 종횡비 | faceHeight / faceWidth | ratio | 1.223/0.066 | 세로로 긴 얼굴 → 부유·리더 | 가로로 넓음 | wealth·leadership (Z-FAR) |
| 2 | `faceTaperRatio` 테이퍼 | dist(172,397)/faceWidth | ratio | 0.793/0.025 | 넓은 턱·강한 골격 | 좁은 턱(V) | 얼굴형 |
| 3 | `lowerFaceFullness` 하단 풍만 | (jaw+jawLower+chinSide)/(3·faceWidth) | ratio | 0.507/0.020 | 볼살·턱살 풍만 | 갸름한 하단 | 얼굴형 |
| 4 | `upperFaceRatio` 상안면 | dist(10,168)/faceHeight | ratio | 0.306/0.019 | 이마 큼 → 지성·신뢰 | 이마 좁음 | intelligence·trust (Z-FH) |
| 5 | `midFaceRatio` 중안면 | dist(168,94)/faceHeight | ratio | 0.301/0.020 | 중정 긺 → 재물·사회성 | 중정 짧음 | wealth·sociability (Z-11) |
| 6 | `lowerFaceRatio` 하안면 | dist(94,152)/faceHeight | ratio | 0.394/0.035 | 턱 긺 → 안정·신뢰 | 턱 짧음 → 감정 풍부 | stability·trust (Z-12/13) |
| 7 | `gonialAngle` 하악각 | ∠(132·172·152) 평균 | 각° | 141.7/4.4 | 각진 턱 | 둥근 턱 | leadership·stability |
| 8 | `intercanthalRatio` 눈 사이 | dist(133,362)/faceWidth | ratio | 0.257/0.015 | 눈 사이 넓음 → 카리스마 | 좁음 | leadership·wealth (Z-IC) |
| 9 | `eyeFissureRatio` 눈 길이 | 양안 길이 평균/faceWidth | ratio | 0.189/0.011 | 눈 긺 → 매력·감정·통찰 | 눈 짧음 | eye node |
| 10 | `eyeCanthalTilt` 눈꼬리 각 | 외안각 기울기° 평균 | 각° | 5.9/2.6 | 올라감 → 매력·관능 | 내려감 | attractiveness·sensuality (O-MM·P-06) |
| 11 | `eyebrowThickness` 눈썹 두께 | 눈썹 3구간 두께/faceHeight | shape | 0.034/0.0026 | 두꺼움 → 정력·리더십 | 얇음 | libido·leadership |
| 12 | `browEyeDistance` 눈썹-눈 | dist(105,159)/faceHeight | shape | 0.141/0.016 | 전택궁 넓음 | 가까움 | eyebrow node |
| 13 | `nasalWidthRatio` 코 너비 | dist(98,327)/icd | ratio | 0.947/0.079 | 코 넓음 | 코 좁음 | nose (wealth) |
| 14 | `nasalHeightRatio` 코 길이 | dist(168,1)/faceHeight | ratio | 0.274/0.024 | 콧대 긺 → 중년 재물 | 짧음 | wealth (A-M01) |
| 15 | `mouthWidthRatio` 입 너비 | dist(61,291)/faceWidth | ratio | 0.386/0.047 | 입 넓음 → 사회성 | 작은 입(櫻桃) | sociability (Z-LFR/O-RL) |
| 16 | `mouthCornerAngle` 입꼬리 각 | 입꼬리 vs 중앙 기울기° (부호) | 각° | 6.7/6.0 | 올라감(仰月口) | 내려감(俯月口) | mouth node |
| 17 | `lipFullnessRatio` 입술 두께 | dist(0,17)/faceHeight | ratio | 0.129/0.032 | 두꺼움 → 관능·사회성 | 얇음 | sociability·attractiveness |
| 18 | `philtrumLength` 인중 길이 | dist(94,0)/faceHeight | ratio | 0.086/0.017 | 긺 → 안정·신뢰 | 짧음 → 관능·정력 | O-PH2 vs O-PH1 |
| 19 | `foreheadWidth` 이마 폭 | dist(54,284)/faceWidth | ratio | 0.848/0.032 | 넓음(天庭) → 관록 | 좁음 | forehead node |
| 20 | `cheekboneWidth` 광대 폭 | dist(116,345)/faceWidth | ratio | 0.911/0.014 | 넓음 → 권력·자아 | 좁음 | leadership (O-CK); 過 시 O-CKE 매력− |
| 21 | `chinAngle` 턱 각도 | ∠(148·152·377) | 각° | 169.5/2.5 | 둥근 턱(方頤) | 뾰족(尖頤) | chin node |
| 22 | `eyeAspect` 눈 세로/가로 | 양안 세로/가로 평균 | ratio | 0.296/0.072 | 둥근 눈(圓眼) | 가는 눈(鳳眼) | eye node |
| 23 | `eyebrowCurvature` 눈썹 곡률 | 중앙 솟음/faceHeight | shape | 0.039/0.0038 | 아치(彎眉) | 직선/처짐(八字) | eyebrow node |
| 24 | `eyebrowTiltDirection` 눈썹 기울기 | (머리y−꼬리y)/faceHeight (부호) | shape | 0.002/0.014 | 올라감(劍眉) | 내려감(八字) → 관능·감성 | sensuality·emotionality (Z-EBT) |
| 25 | `upperVsLowerLipRatio` 윗/아랫입술 | 윗입술두께/아랫입술두께 | ratio | 0.597/0.110 | 윗입술 두꺼움(情多) | 아랫입술 두꺼움 | mouth node |
| 26 | `browSpacing` 미간 너비 | dist(55,285)/faceWidth | ratio | 0.193/0.012 | 印堂 넓음 → 관대·재물·매력 | 좁음 → 예민 | wealth·leadership·attractiveness (P-09·P-MJ vs P-09B) |

> `computeAll()` 의 `eyebrowLength`·`noseBridgeRatio` 는 분류기 전용 — referenceData·weight matrix 미사용, 재보정 비대상.

**B. 측면(3/4뷰) 필요 — 정면 표본으로는 측정 불가 (8개)**

`dorsalConvexity`(코 직선도/매부리), `nasofrontalAngle`, `nasolabialAngle`, `facialConvexity`, `noseTipProjection`, `upperLipEline`, `lowerLipEline`, `mentolabialAngle`. 정면 사진엔 측면 기하(z깊이·E-line)가 없어 AAF·niten19 정면 재보정 대상에서 제외. EA 측면은 proxy-frame empirical(2026-04-14), 비-EA 측면은 임상 anthropometry "EA 대비 delta" 추정값을 **의도적으로 유지** (인종 라벨 붙은 3/4 프로파일 데이터셋 확보 전까지). 정면 26 metric 만 전 인종 동일 frame 으로 통일된 상태.

> **frontal vs lateral reference 출처 정리**
> | | frontal 26 | lateral 8 |
> |---|---|---|
> | eastAsian | AAF 실측 (11,800) | proxy-frame empirical (2026-04-14) |
> | 비-EA 5인종 | niten19 pooled in-frame (5,000) | 임상 추정 (의도적 유지) |

---

## 3. 14-Node Tree

```
face (root)
├── 상정 (upper)  ├─ 이마 · 미간 · 눈썹
├── 중정 (middle) ├─ 눈 · 코 · 광대 · 귀
└── 하정 (lower)  └─ 인중 · 입 · 턱
```

**총 14 노드** = root 1 + 삼정 3 + leaf 10.

### 3.1 자료 구조

각 노드는 다음을 보유:
- `metricIds`: 소속 metric (예: 코 → nasalWidth/Height + lateral nose 4종)
- 메타데이터 태그 — **오관(五官)** / **오악(五嶽)** / **사독(四瀆)** / **십이궁(十二宮)**
- `zone`: upper/middle/lower

코드 SSOT: `shared/lib/domain/models/physiognomy_tree.dart`.
`귀(ear)` 는 MediaPipe 정면 mesh 커버리지 부족으로 `unsupported=true` (v1).

### 3.2 Node Scoring

`physiognomy_scoring.dart::scoreTree(z)` 가 입력 z-map 을 tree mirror 로 변환:
- **own stats**: 노드 자신의 metric 만. `ownMeanZ` (signed) + `ownMeanAbsZ` (강도)
- **roll-up stats**: 자신 + descendant 합산. zone/root 는 이것만 의미.

이 분리로 한 노드에서 **방향** 과 **distinctiveness** 독립 규칙 가능.

### 3.3 메타데이터 오버레이

| 체계 | 매핑 |
|---|---|
| 오관 (보수·감찰·심변·출납·채청관) | 눈썹·눈·코·입·귀 |
| 오악 (형·태·화·숭·항산) | 이마·광대좌·광대우·코·턱 |
| 사독 (강·하·회·제) | 귀·눈·코·입 |
| 십이궁 (12 영역) | 명궁=미간, 재백궁=코, 형제궁=눈썹, 전택궁=눈상안검, 남녀궁=와잠, 노복궁=턱, 처첩궁=눈꼬리, 질액궁=산근, 천이궁=이마양옆, 관록궁=이마중앙, 복덕궁=root, 상모궁=root |

---

## 4. 10 Attribute + 5-Stage Pipeline

### 4.1 10 속성

| Attribute | Korean | 핵심 노드 | Archetype |
|---|---|---|---|
| `wealth` | 재물운 | 코 · 광대 · 턱 | 사업가형 |
| `leadership` | 리더십 | 턱 · 광대 · 이마 | 리더형 |
| `intelligence` | 통찰력 | 이마 · 눈 · 눈썹 | 학자형 |
| `sociability` | 사회성 | 입 · 광대 · 턱 | 외교형 |
| `emotionality` | 감정성 | 눈 · 미간 · 입 | 예술가형 |
| `stability` | 안정성 | 턱 · 미간 · 코 | 현자형 |
| `sensuality` | 바람기 | 눈 · 입 · 인중 | 연예인형 |
| `trustworthiness` | 신뢰성 | 이마 · 눈 · 턱 | 신의형 |
| `attractiveness` | 매력도 | 눈 · 입 · 광대 | 미인형 |
| `libido` | 관능도 | 눈썹 · 인중(-) · 눈 | 정열형 |

### 4.2 5-Stage Derivation Pipeline (engine v2.9)

`attribute_derivation.dart::deriveAttributeScores()`. 각 stage 는 누적 합산:

| Stage | 이름 | 동작 |
|---|---|---|
| 1 | **base linear** | 9-node × 10-attr weight matrix (face/ear 제외, 행 합 = 1.00). signed-z × weight × polarity. |
| 1b | distinctiveness | intelligence (upper absZ) + emotionality (lower absZ) 가산 |
| 2 | **zone rules** (20) `Z-##` | 삼정 조화/대립 + root 비율 + 五官端正 등 美 rule |
| 3 | **organ rules** (24) `O-##` | 오관 쌍 조합 (눈-눈썹, 코-입, 광대 등) + 美目流盼·眉目清秀·朱唇小口 등 |
| 4 | **palace rules** (11) `P-##` | 십이궁 cross-node overlay + 印堂明潤 |
| 5 | gender/age/lateral (10+4+3) | 성별 weight delta + 50+ 보정 + 측면 flag (`L-AQ`/`L-SN`/`L-EL`) |

총 **62 rule**. 모든 rule magnitude cap `|Δ| ≤ 0.5` (v2.6 invariant — step-function dominance 차단).

### 4.3 Weight Matrix (engine v2.9, 9-node)

| Attribute \\ Node | 이마 | 미간 | 눈썹 | 눈 | 코 | 광대 | 인중 | 입 | 턱 |
|---|---|---|---|---|---|---|---|---|---|
| wealth | 0.12 | 0.10 | 0.08 | 0.08 | **0.20** | 0.10 | 0.07 | 0.10 | 0.15 |
| leadership | 0.13 | 0.08 | 0.15 | 0.10 | 0.15 | 0.10 | 0.03 | 0.08 | **0.18** |
| intelligence | **0.18** | 0.10 | 0.10 | 0.15 | 0.10 | 0.08 | 0.09 | 0.10 | 0.10 |
| sociability | 0.08 | 0.10 | 0.10 | 0.12 | 0.08 | 0.12 | 0.07 | **0.20** | 0.13 |
| emotionality | 0.06 | 0.13 | 0.12 | **0.20** | 0.08 | 0.08 | 0.10 | 0.13 | 0.10 |
| stability | 0.12 | 0.15 | 0.08 | 0.08 | 0.13 | 0.10 | 0.08 | 0.08 | **0.18** |
| sensuality | 0.05 | 0.08 | 0.13 | **0.17** | 0.10 | 0.08 | 0.15 | **0.17** | 0.07 |
| trustworthiness | **0.15** | 0.12 | 0.06 | **0.15** | 0.13 | 0.07 | 0.07 | 0.10 | **0.15** |
| attractiveness | 0.07 | 0.07 | 0.13 | **0.17** | 0.10 | 0.13 | 0.07 | **0.17** | 0.09 |
| libido | 0.05 | 0.08 | **0.17** | 0.13 | 0.10 | 0.10 | 0.15(−) | 0.12 | 0.10 |

각 행 합 = 1.00. v2.7 dominant decorrelation 으로 10 attribute 가 서로 다른 top node 를 가짐 (cluster 편향 차단).

### 4.4 Archetype + Special Archetype

상위 2 속성으로 primary/secondary 결정. 복합 조건 시 special:

| ID | 조건 | Label |
|---|---|---|
| SP-1 | wealth≥7.5 AND leadership≥7.0 | 제왕상 |
| SP-2 | sensuality≥7.5 AND attractiveness≥7.5 | 도화상 |
| SP-3 | intelligence≥7.5 AND stability≥7.0 | 군사상 |
| SP-4 | sociability≥7.5 AND attractiveness≥7.0 | 연예인상 |
| SP-5 | wealth≥7.0 AND trustworthiness≥7.0 | 복덕상 |
| SP-6 | leadership≥7.0 AND stability≥7.0 AND trust≥7.0 | 대인상 |
| SP-7 | libido≥7.5 AND sensuality≥7.0 | 풍류상 |
| SP-8 | intelligence≥7.0 AND emotionality≥7.0 | 천재상 |
| SP-9 | stability≤3.0 AND emotionality≥7.5 | 광인상 |
| SP-10 | trust≤3.0 AND sociability≥7.0 | 사기상 |

코드: `archetype.dart`. shape-gated overlay (oval→매력 보너스 등) 도 여기서 적용.

---

## 5. Normalize (raw → 5.0~10.0)

`attribute_normalize.dart::normalizeAllScores()`:

```
raw → globalPct = _rawToPercentile(raw, attr, gender)   ← 21-point quantile 보간
       rankPct = (9 - rank) / 9                          ← 얼굴 내 10 속성 desc
       blend   = 0.40 × rankPct + 0.60 × globalPct
       score   = 5.0 + blend × 5.0                       ← [5.0, 10.0]
```

- **성별별 21-point quantile table** (`_attrQuantilesMale` / `_attrQuantilesFemale`). 상관 Monte Carlo 20,000 샘플(seed=42, bone/mid latent + 얼굴형 prior) 로 생성.
- **per-shape × gender quantile** (Opt-D, v2.8): shape-conditional bias 근본 제거.
- **재생성 명령**: `flutter test test/calibration_test.dart` → 출력 map 을 `attribute_normalize.dart` 에 붙여넣기.

### Invariant (test/score_distribution_test.dart)

- spread (top-bottom) ≥ 2.0
- 평균 ~ 7.0, std ~ 1.2
- 상위 saturation (≥9.5 전부) < 5%

---

## 6. Hive 저장 (capture-only)

### 6.1 원칙

> **저장하는 것**: raw metric value + 촬영 맥락 + UI 메타. **저장 안 하는 것**: z-score · nodeScores · attributes · rules · archetype.

엔진 버전(weight/rule/quantile/classifier) 이 오르면 Hive 의 모든 리포트가 자동으로 새 공식 결과를 받는다. `kReportSchemaVersion` bump 는 **capture 필드가 바뀔 때만**.

### 6.2 Top-Level Key

**Hive ↔ Supabase metrics — 개정판 (최종)**

- **Hive DTO** = `toJsonString()` (로컬 영구 라이브러리, 전체 필드)
- **외부 metrics DTO** = Supabase `metrics` row = 컬럼 + `body`(=`toBodyJson()`)
- 규칙: **컬럼 = 관계·소유 메타(snake_case) / body = 분석 payload(camelCase)**

| prop (camelCase) | Hive `toJsonString` | Supabase 위치 | 역할 |
|---|---|---|---|
| id / supabaseId | body `supabaseId` | **column `id`** (body 제외) | 공유 UUID·PK. Hive 는 id 컬럼이 없어 body 보관, 서버는 컬럼 canonical |
| userId | ✗ | **column `user_id`** | 업로더(anon=null), 소유·RLS |
| alias | body | **column** (body 제외) | 소유자 지정 이름 |
| isMyFace | body | **column `is_my_face`** (body 제외) | 본인 얼굴 플래그(궁합·business) |
| views | ✗ | **column** | 서버 조회수 |
| createdAt | ✗ | **column** | 첫 publish 시각 |
| updatedAt | ✗ | **column** | 마지막 활동 → 90일+ 미활동 삭제 기준 |
| schemaVersion | body | body | 버전(호환성 invalidation) |
| ethnicity / gender / ageGroup | body | body | demographics = z-score 재계산 input |
| timestamp | body | body | 분석 시각, 정렬·표시·수신재구성 |
| source | body | body | camera/album/received |
| thumbnailKey | body | body | R2 CDN 키(remote 이미지·og:image) |
| metrics (rawValue map) | body | body | 핵심 capture (z/score 는 load 시 재계산) |
| lateralMetrics | body(조건) | body | 측면 capture rawValue |
| faceShape / Label / Confidence | body | body | 얼굴형 분류 |
| thumbnailPath | body | ✗ (toBodyJson 제외) | 기기 로컬 파일명 |
| (derived) nodeScores·attributes·rules·archetype | ✗ 미저장 | ✗ 미저장 | load 시 현재 엔진 재계산 |

> 제거 이력: `receivedAt`(미사용 로컬 메타) · `deepface*`(never-wired dead) · `expiresAt`(expiry 폐기) · body 의 `supabaseId`(서버 id 컬럼 중복) 는 정리됨.

### 6.3 재계산 흐름 (`fromJsonString()`)

```
저장 capture
   ↓
1. raw → z-score (현재 reference) → age-adjusted
2. lateralFlags 재계산 (현재 임계)
3. scoreTree(zAll) → 14-node NodeScore
4. deriveAttributeScoresDetailed(tree, gender, isOver50, lateralFlags, faceShape)
5. normalizeAllScores(raw, gender, shape)
6. classifyArchetype(normalized, shape)
```

### 6.4 Hive Box 3종

| Box | 내용 |
|---|---|
| `history` | FaceReadingReport JSON list (카메라+앨범 모두) |
| `prefs` | gender / ageGroup / ethnicity (enum name 문자열) |
| `auth` | Supabase 세션 토큰 |

### 6.5 신규 Metric 추가 체크리스트

1. `face_metrics.dart::computeAll()` 에 계산 로직 + id 반환
2. `face_reference_data.dart::metricInfoList` 에 entry 추가
3. 같은 파일 `referenceData` 의 12 (ethnicity × gender) entry mean/sd 추가
4. `physiognomy_tree.dart` 의 적절 노드 `metricIds` 에 추가
5. `attribute_derivation.dart` weight/rule 연결 (필요 시)
6. `flutter test test/calibration_test.dart` → 새 quantile 생성 → `attribute_normalize.dart` 반영
7. `kReportSchemaVersion` bump → Hive 옛 리포트 자동 drop

신규 **rule** 추가는 schemaVersion bump 불필요 (capture-only 효과).

---

## 7. 궁합 엔진 (5 frame)

관상 엔진과 **동등한 별도 엔진** — `shared/lib/domain/services/compat/`. 입력은 두 개의 `FaceReadingReport` (capture만 의존, attributes/archetype 미의존 — double-interpretation 차단).

### 7.1 4 sub-score

| sub | 이름 | weight | 입력 |
|---|---|---|---|
| `elementScore` (L1) | 五形和 | 0.20 | 얼굴형 metric 7개 + faceShape preset → 五行 분류 + 5×5 상생상극 matrix |
| `palaceScore` (L2) | 宮位調 | 0.40 | 26+8 metric ~22개 → 12 궁 state + ~40 PalacePair rule |
| `qiScore` (L3) | 氣質合 | 0.25 | 五官 1:1 (0.55) + 三停 合刑 (0.25) + 陰陽 balance (0.20) |
| `intimacyScore` (L4) | 性情諧 | 0.15 | 男女宮·妻妾宮·lip·eye. 모든 페어에서 항상 계산. narrative tone 만 분기. |

총점:
```
rawTotal = 0.20·element + 0.40·palace + 0.25·qi + 0.15·intimacy
total = clamp(50 + (rawTotal - 50) × 1.4, 5, 99)
```

#### Intimacy tone 분기 (narrative 만)
- `pure`: 동성 페어 OR 한쪽이라도 10대·70대 이상. 현재의 점잖은 산문체 (opener + 4 axis + closer).
- `flirty`: 이성 페어 + 한쪽 20대 또는 60대. 짧은 SNS 영상 자막 톤 (opener + closer).
- `spicy`: 이성 페어 + 양쪽 모두 30~50대. 들키면 안 되는 분위기 punch line (opener + closer).

### 7.2 Label 4-tier

`kCompatLabelThresholds` (`compat_label.dart`) — MC 20k seed=42 의 p30/p60/p90 (61.56 / 81.42 / 90.50) 에 맞춰 10/30/30/30 분포 보장.
- `天作之合` (≥90.5)
- `相敬如賓` (81.5~90.5)
- `磨合可成` (61.5~81.5)
- `刑剋難調` (<61.5)

상세 설계 SSOT (五行 weight 공식, 12궁 state, PalacePair rule 카탈로그) 는 코드 자체로 SSOT 화: `compat_pipeline.dart` + `palace_rules.dart` + `compat_phrase_pool.dart`. 본 문서 §7 은 high-level 요약만.

### 7.3 Capture-only

`CompatibilityReport` 가 Hive 에 저장하는 건 `myReportId` · `albumReportId` · `evaluatedAt` 뿐. element/palace/organ/zone/intimacy/narrative 는 load 시 두 FaceReadingReport 로부터 재계산.

---

## 8. 서술 엔진 (life_question_narrative)

`lib/domain/services/life_question_narrative.dart`. 8 인생 질문 섹션:

1. 타고난 재능
2. 재물운
3. 대인관계
4. 연애운 — **남/여 별도 pool**
5. 바람기 (20대 이상) — **남/여 별도 pool**
6. 관능도 (30대 이상) — **남/여 별도 pool**
7. 건강과 수명
8. 종합 조언

### 8.1 Beat-Fragment Grammar

```
_BeatPool = List<_Frag>
_Frag = (predicate: double Function(_Features), variants: List<String>)
```

- **soft predicate** (v2.9): `bool → double` 전환. band cliff 제거. 인접 z 가 fragment 선택에 연속 반영.
- **face hash seed** (FNV): metrics + attributes + nodeScores 를 섞어 32-bit seed. 같은 얼굴 → 같은 본문 (결정론), 다른 얼굴 → 거의 유일.
- **섹션/빗/슬롯 salting**: `beatSeed = seed ^ (beatSalt × 2654435761)` 로 독립 stream.

### 8.2 슬롯 풀

`@{slot}` 와 `{a|b|c}` 인라인 alternation. 45 카테고리 (수식 정도 · 인물 수식 · 십이궁 · 오악 · 오관 · 삼정 · 기·상 · 사자성어 등) × 슬롯당 3~6 변종.

성별 분기 슬롯: `_m`/`_f` 접미사 쌍. `_genderedKey()` 가 features.gender 로 분기.

### 8.3 연령 게이팅

```dart
if (f.age.isOver20) parts.add('바람기', …);
if (f.age.isOver30) parts.add('관능도', …);
// 50+ 는 종합 조언 stage 가 "덜어내는 기술" 로 분기
```

### 8.4 14-node expandable UI (report_page)

`node_text_blocks.dart` SSOT — 14 node × 3 band (high/mid/low) × shared|male|female 본문. report_page 에서 탭하면 펼침. 성별 분기 4 node (eye/nose/mouth/cheekbone).

---

## 9. Face Shape Classifier (Track 1)

**현재 모델**: 28-feature MLP (TFLite 18 KB) — niten19 4000 + East Asian 사용자 57 mixed 학습. East Asian 5-fold CV honest accuracy 47.6% (train 75.4%).

**`_priorRatio`**: uniform `[1,1,1,1,1]` — 모델 학습 단에서 East Asian 보정 내장.

**입력 28 feature** (`face_shape_classifier.dart::featureNames`): face_metrics.computeAll() 의 ratio 28개. 학습-추론 정렬 필수.

**재학습 + 배포 procedure**: `tools/face_shape_ml/README.md` — extract_user_features → train_28feat_eastasian → export_tflite → flutter assets 자동 교체.

---

## 10. 환경 & 재현

### 빌드/테스트

```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter test             # 145 test 전부 green
flutter analyze          # 0 issues
flutter run              # 실기 (camera 는 simulator 불가)
```

### Reference data 재보정 (Monte Carlo)

weight matrix / rule 수정 후:
```bash
flutter test test/calibration_test.dart
# → 출력 21-point map 을 attribute_normalize.dart 에 paste
flutter test test/archetype_fairness_test.dart test/score_distribution_test.dart  # green 확인
```

### 회귀 차단 test

| Test | 검증 |
|---|---|
| `physiognomy_tree_sanity_test.dart` | row sum, zone 합, per-metric 영향력 ∈ [0.15, 1.20], max/min ≤ 6.5× |
| `shape_archetype_bias_test.dart` | 5 shape × 2000 샘플 top-1 attr 분포 < 35% |
| `archetype_template_sanity_test.dart` | 6 template hit rate ≥ 55% |
| `score_distribution_test.dart` | spread invariant, saturation < 5% |
| `evidence_snapshot_test.dart` | 고정 z-map 의 rule/score/contributor 완전 snapshot |
| `face_shape_posterior_test.dart` | applyPosterior 수학 + posterior 합 = 1 |
| `real_users_recalibration_test.dart` | N=14 실사용자 empirical z + archetype concentration |

### 주요 상수

- `face_analysis.dart::kLandmark10Correction = 1.05` — 이마 끝점 보정
- `kReportSchemaVersion = 1` — Hive capture 스키마
- `album_capture_page::_processAlbumPhoto` — square-padding (MediaPipe non-square distortion 차단)

---

## 11. 참고 문헌

- **전통**: 麻衣相法 (북송 陳摶), 柳莊相法 (명 袁珙), 神相全編 (청대), 水鏡集
- **현대**: Farkas LG. *Anthropometry of the Head and Face* (1994), Todorov A. *Face Value* (2017), Zebrowitz LA. *Reading Faces* (1997), Pallett et al. PNAS 2010 (golden ratios), BiSeNet / CelebAMask-HQ face parsing, FACS (Ekman & Friesen)
