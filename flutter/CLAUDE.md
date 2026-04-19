# Face Reader — Claude Code 오리엔테이션

관상 분석 Flutter 앱. MediaPipe Face Mesh(468 landmarks) 을 입력으로 17 frontal + 8 lateral metric → z-score → 14-node tree → 10 attribute → archetype · compat 까지 일관된 파이프라인.

마지막 업데이트: 2026-04-19 (engine v2.8)

---

## 🚀 다음 PC 에서 이어받을 때 먼저 읽기

세션 시작 시 이 섹션 먼저 확인. engine v2.8 (N=14 실사용자 ref re-centering + bias=0.0 MC) 이 현재 stable baseline.

### 엔진 버전 스냅샷 (2026-04-19)

- **engine v2.8** · narrative v3 · Hive schemaVersion 3
- Stage 0 shape preset: **철수** (raw score 에 얼굴형 관여 0)
- 매력도 Stage 1b distinctiveness: **철수** (bell 제거)
- 얼굴형 은 archetype shape-gated overlay + narrative Layer B 에만 남음
- MC sampler **bias=0.0, std=1.0** (N=14 eastAsian female 30s 실사용자 empirical z 가 N(0,1) 에 수렴하도록 ref 재보정 완료)
- eastAsian female reference 19 metric mean 재조정 (faceAspectRatio 1.35→1.30, midFaceRatio 0.30→0.32, cheekboneWidth 0.90→0.93 등)
- compat threshold 84→83 (bias=0 MC p90 이동분 흡수)

#### v2.8 핵심 invariant (회귀 차단용)

1. **attribute row 합 = 1.00 ± 0.01** — 9 node(face/ear 제외) 가중치 정규화.
2. **zone 합 ∈ [0.25, 0.40]** per (attribute × zone) — 각 속성이 상·중·하정 중 어느 한 곳에 55% 이상 몰리지 않도록.
3. **3 zone 모두 non-zero** per attribute — 각 속성이 상·중·하정 3 zone 전부 참여.
4. **per-metric 영향력 ∈ [0.15, 1.20]** — single-metric 노드(glabella=browSpacing, cheekbone=cheekboneWidth, philtrum=philtrumLength)는 구조상 sum-across-attributes ≈ 1.0 까지 오름. 고아 차단(≥0.15) + 다중 metric 노드 dilution 허용.
5. **per-metric max/min ≤ 6.5×** — v2.7 decorrelation 후 single-metric vs 4-metric(mouth) 노드 dilution 격차 5~6× 가 구조적 정상.
6. **rule magnitude cap |Δ| ≤ 0.5** — Zone/Organ/Palace/Age/Lateral rule 의 단일 effect 는 0.5 이상 못 줌. step-function dominance 방지.
7. **decorrelated dominant nodes** — 10 attribute 가 각기 다른 1 개 노드를 top weight(≥0.17) 로 가짐: wealth=nose, leadership=chin, intelligence=forehead, sociability=mouth, emotionality=eye, stability=chin+glabella, sensuality=eye+mouth tied, trustworthiness=forehead+eye+chin tied, attractiveness=eye+mouth tied, libido=eyebrow. 학자형/외교형 cluster-dominance 차단.

### 회귀 차단 test

- `test/physiognomy_tree_sanity_test.dart` (18 assertion) — row sum, zone 합, zone coverage, per-metric 영향력(≤1.20), max/min ratio(≤6.5). v2.7 invariant 강제.
- `test/shape_archetype_bias_test.dart` — 5 shape × 2000 샘플 → 각 shape 의 top-1 attr 분포 < 35%. shape-bound archetype 편향 부활 차단.
- `test/archetype_template_sanity_test.dart` — 6 template hit rate ≥ 55% (rule cap 으로 template 차별 신호 약화를 의도적으로 허용).
- `test/score_distribution_test.dart` — spread invariant, saturation < 5%.
- `test/compat_label_fairness_test.dart` — 10/30/30/30 ± 5%, thresholds **83/73/65**.
- `test/evidence_snapshot_test.dart` — 고정 z-map 에 대한 rule/score/contributor 완전 snapshot.
- `test/real_users_recalibration_test.dart` — N=14 실사용자 empirical z 분포 + archetype concentration 진단 (현재 max 28.6% = 4/14).

### 다음 작업 (우선순위순)

| 우선 | 작업 | 근거 | 재개 지시 |
|---|---|---|---|
| P0 | **실사용자 N 확장** (현 N=14 eastAsian female 30s → ≥100 전 demographic) | v2.8 은 단일 demographic 14 명으로 ref 재보정. 남·타 ethnicity·age 는 아직 idealized MC 기반 | `"test/fixtures/real_users_*.json 에 male/caucasian/40s 등 추가 수집 후 real_users_recalibration_test.dart 로 per-demographic 재보정"` |
| P1 | **Per-shape quantile 테이블** (Opt-D) | oval/oblong/round/square/heart 각각 독립 quantile 로 shape-conditional bias 근본 제거 | `"attribute_normalize.dart 에 _attrQuantilesByShape 도입. 각 shape 당 21-point × 10 attr × 2 gender. MC sampler 에 shape 드로우 stratification 추가."` |
| P1 | **Soft predicate 로 band 전환** (narrative variation) | 현 `_Band.high/mid/low` hard cutoff 가 plateau/cliff 문제 만듦. 연속 확률로 전환 시 인접 z 의 의미 있는 차이가 fragment 선택에 반영 | `"life_question_narrative.dart 의 _Frag predicate 를 bool → double(0~1) 로. weighted sampling."` |
| P2 | **Fragment variant 확장 (재능·재물·사회·건강 섹션)** | 관능도만 7-아키타입 확장 완료. 나머지 섹션도 fallback 에 2~3 variants 추가 | `"_talentOpening, _wealthOpening, _socialOpening 등 fallback variant 수를 2→5 로 확장"` |
| P2 | **UI 에 음양 축 표시** | `yin_yang.dart` 에서 `YinYangBalance` 계산은 되는데 UI 에 라벨만 있고 시각 요소 부족 | `"report_page 부위별 섹션 위에 음양 balance 바 추가"` |
| P3 | **docs/engine 리팩토링** | ATTRIBUTES.md v0.3 가 v2.5 와 부분 동기화 상태. 완전 재작성 필요 | `"docs/engine/ATTRIBUTES.md 를 v2.5 매트릭스·rule 기준 전면 재작성"` |

### 최근 커밋 시퀀스 (역순)
```
<pending> engine v2.8 N=14 eastAsian female 실사용자 ref re-centering + bias=0.0 MC 재보정 (max concentration 28.6%)
<pending> engine v2.7 decorrelated weight matrix + bias=0.2 MC alignment
<pending> engine v2.6 zone-parity + rule cap + per-metric guardrail
5896024 engine v2.5 sync + 다음 작업 handoff 정리
83c9e35 intel/stability weight matrix 분산 + Z-01 재축소
e11fd99 shape-bound archetype 편향 제거 (v2.3 rule mag)
821b3d7 음양 축 + 귀(ear) UI 제거
811c205 Hive capture-only (schemaVersion 3)
3848e4d Stage 0 preset + 매력도 bell 철수
```

---

## 문서 규칙 (이 세션에서 Claude 가 지켜야 할 룰)

### 금지어 (절대 답변·커밋·문서에 쓰지 말 것)

레거시 / 예전 / 구 엔진 / 기존 구현 / 이전에는 / legacy / 마이그레이션 / 호환성 / 참조만 / 참고만

근거 제시는 세 가지로만:

1. **현재 엔진의 구조적 특성** (row 합 = 1.00, stage firing rate, 등)
2. **Monte Carlo 측정** (20,000 샘플, seed=42, input z ~ N(0.2, 0.85))
3. **UX 판단** (bar chart 가독성, 사용자 해석 난이도, 점수 saturation 등)

과거 상태를 비교 기준으로 제시하는 순간 트리거. 설계 제안에 "nullable 로 optional", "기존 호환" 같은 safety hook 금지. 데이터·Hive·스키마 전부 drop-recreate 자유.

### 깊이 있는 레퍼런스

모든 상세 문서는 `docs/` 하위. 진입점은 `docs/README.md` (인덱스). 이 파일(CLAUDE.md)은 현재 상태의 스냅샷과 프로젝트 규칙만 유지 — 수치 표나 연구 인용은 docs/runtime/OUTPUT_SAMPLES.md 로 위임.

---

## Tech Stack

- **Flutter** (Dart SDK ^3.11.0)
- **camera** ^0.11.1 — 카메라 preview + frame streaming
- **mediapipe_face_mesh** ^1.2.4 — face mesh 추론 (FFI + TFLite)
- **Hive** — demographics prefs + history persist
- **Supabase** — metric 원격 저장

## File Structure

```
lib/
├── main.dart
├── core/                                      # Theme, Hive init, shared utils
├── data/
│   ├── constants/
│   │   ├── face_reference_data.dart           # 17 frontal + 8 lateral 기준값 (6 ethnicity × 2 gender) — SSOT
│   │   ├── archetype_text_blocks.dart         # Archetype intro / special archetype 본문
│   │   ├── rule_text_blocks.dart              # Rule ID → 본문 매핑
│   │   └── compatibility_text_blocks.dart     # Compat 섹션별 variant 풀
│   ├── enums/                                 # Attribute, Gender, AgeGroup, Ethnicity, MetricType
│   ├── repositories/metaphor_repository.dart  # Rule → 은유 텍스트 매칭
│   └── services/
│       ├── face_shape_classifier.dart         # TFLite 28-feature MLP (76.9% test acc)
│       └── supabase_service.dart
├── domain/
│   ├── models/
│   │   ├── physiognomy_tree.dart              # 14 node 구조 SSOT (docs/engine/TAXONOMY.md)
│   │   ├── face_analysis.dart                 # analyzeFaceReading() — 엔드투엔드 파이프라인
│   │   ├── face_reading_report.dart           # rich evidence schema (아래 참조)
│   │   └── compatibility_result.dart
│   └── services/
│       ├── face_metrics.dart                  # 17 frontal ratio/angle/shape
│       ├── face_metrics_lateral.dart          # 8 lateral 3/4-view + yaw classify
│       ├── metric_score.dart                  # z → 0-100 정수 메트릭 점수
│       ├── physiognomy_scoring.dart           # 삼정/오관 node tree + scoreTree()
│       ├── attribute_derivation.dart          # 5-stage pipeline → 10 raw attribute
│       ├── attribute_normalize.dart           # 성별 quantile → 5.0~10.0 normalize
│       ├── score_calibration.dart             # Monte Carlo 기반 quantile table 생성
│       ├── archetype.dart                     # 10 attribute → top-2 기반 archetype
│       ├── compat_calibration.dart            # Compat 라벨 threshold Monte Carlo
│       ├── compatibility_engine.dart          # 페어 리포트 비교
│       ├── report_assembler.dart              # 본문 조립 래퍼 (intro/closing + life questions)
│       ├── life_question_narrative.dart       # 인생 질문 8섹션 서술 v2 (Beat-Fragment Grammar, face-hash seed)
│       └── age_adjustment.dart                # 50+ 보정
└── presentation/
    ├── providers/                             # Riverpod: gender, ageGroup, ethnicity(Hive persist), history, auth, tab
    ├── screens/
    │   ├── home/
    │   │   ├── home_screen.dart               # Demographic pickers + 진입
    │   │   ├── face_mesh_page.dart            # 카메라 + mesh overlay + 2단계 캡처
    │   │   ├── album_preview_page.dart        # 앨범 모드 preview/confirm
    │   │   └── report_page.dart               # 리포트 UI + 속성 expand + 14-node tree
    │   ├── compatibility/                     # compat picker + report
    │   └── physiognomy/                       # 관상 설명 스크린
    └── widgets/

docs/                                           # 모든 문서 — 진입은 README.md
test/                                           # 73 tests (calibration, fairness, spread, compat 라벨 분포, …)
```

## Report Schema (rich evidence)

```
FaceReadingReport
├── metrics           : Map<String, MetricResult>          17 frontal
├── lateralMetrics    : Map<String, MetricResult>?         8 lateral (있을 때만)
├── lateralFlags      : Map<String, bool>?                 aquilineNose 등
├── nodeScores        : Map<String, NodeEvidence>          14 node own/rollUp z
├── attributes        : Map<Attribute, AttributeEvidence>  raw+정규화+기여 리스트
│       └── contributors: List<Contributor>                |v|>0.05 전부, |v| desc
├── rules             : List<RuleEvidence>                 stage 태그 포함
├── archetype         : ArchetypeResult                    top-2 + special
├── faceShapeLabel    : String?                            ML classifier 결과
└── faceShapeConfidence: double?

shortcut: report.attributeScores  → Map<Attribute, double>  normalized 5~10 값
```

각 Contributor.id 예: `node:nose`, `distinctiveness`, `Z-03`, `O-NM1`, `P-06`, `A-5X`, `L-AQ`.

## Pipeline at a glance

```
MediaPipe landmarks (468)
  ↓ FaceMetrics / LateralFaceMetrics
17 frontal + 8 lateral raw
  ↓ reference (ethnicity × gender) 대비 z-score
  ↓ age adjustment (50+)
  ↓ scoreTree(z)
14 NodeScore (own + rollUp stats)
  ↓ 5-stage derivation
  │   1. base linear (per node weight)
  │   1b. distinctiveness (abs-z 보정)
  │   2. zone rules  Z-##   (삼정 조화/불균형)
  │   3. organ rules O-##   (오관 쌍)
  │   4. palace rules P-##  (십이궁 overlay)
  │   5. age A-## + lateral L-## + gender delta
10 raw attribute
  ↓ normalizeAllScores (성별 quantile → rank 60% + globalPct 40% → 5.0~10.0)
10 normalized attribute
  ↓ classifyArchetype (top-2 기반)
ArchetypeResult
  ↓ report_assembler  (intro / closing wrapper)
  ↓ life_question_narrative (Beat-Fragment 엔진 · face-hash seed)
본문 텍스트 — 7 인생 질문 섹션 (재능/건강/재물/대인/연애/관능도*/조언)
```

\* 관능도 ≥ 30대. 바람기는 독립 섹션이 아니라 연애운 Shadow 의 1-line 특성(libido 고 & stability 비고 조건)으로 통합됨. 서술 엔진 상세: `docs/runtime/NARRATIVE.md`.

## 3/4 측면 측정·스코어링

측면 캡처는 정면과 **완전히 분리된 두 번째 이미지**. yaw ∈ [0.70, 0.88] (약 45~60° 회전) 구간에서만 수락 — dorsal convexity 같은 sagittal-plane signal 이 2D 에 신뢰성 있게 투영되는 구간. `classifyYaw()` 가 `YawClass.threeQuarter` 반환해야 녹색 overlay + 캡처 버튼 활성.

### 8 연속 lateral metric (`face_metrics_lateral.dart::computeAll()`)

| id | 한국어 | 의미 | 참고 mean |
|---|---|---|---|
| `nasofrontalAngle` | 비전두각 | 168(nasion) 각도, 이마-코 꺾임 | M 131° / F 141° |
| `nasolabialAngle` | 비순각(프록시) | 94(subnasale) 각도, 94→0 ref — tip rotation | 130~140° (클리니컬 NLA 아님) |
| `facialConvexity` | 안면 돌출각 | 180° − ∠10-94-152. 양수=볼록 프로파일 | ~7.7° |
| `upperLipEline` | 상순 E-line | 0 → (1-152) E-line 수직거리 / faceHeight | ~−1mm 근방 |
| `lowerLipEline` | 하순 E-line | 17 → (1-152) E-line 수직거리 | 동일 규약 |
| `mentolabialAngle` | 순이각 | 17(lowerLipBottom) 각도, 14·152 ray | 동아시아 ~134° |
| `noseTipProjection` | 코끝 돌출 | dist(168, 1) / faceHeight — Goode 유사 |  |
| `dorsalConvexity` | 코 등선 | 195 의 168→1 line 수직거리 abs / faceHeight |  |

reference mean/sd: `face_reference_data.dart::lateralMetricInfoList`. 6 ethnicity × 2 gender fallback 동일.

### 5 lateral flag (정면+측면 z 기반, `face_analysis.dart`)

z-score (정수 `metricScore`) 임계로 산출 — 절대 mm 임계는 mesh noise·projection geometry 로 불안정해 사용하지 않음.

| flag | 조건 | 의미 |
|---|---|---|
| `aquilineNose` | `dorsalConvexity` z ≥ 3 | 매부리코 |
| `snubNose` | `nasolabialAngle` z ≥ 2 **and** raw ≥ 115° | 들창코 |
| `droopingTip` | `nasolabialAngle` z ≤ −2 **and** raw ≤ 112° | 처진 코끝 |
| `saddleNose` | `dorsalConvexity` z ≤ −3 | 안장코 |
| `flatNose` | `noseTipProjection` z ≤ −3 | 납작코 |

### Lateral rule (Stage 5, `attribute_derivation.dart::_lateralFlagRules`)

| rule | 트리거 | attribute delta |
|---|---|---|
| `L-AQ` | `aquilineNose == true` | leadership +1.5, wealth +0.5, stability −0.3 |
| `L-SN` | `snubNose == true` | sociability +1.0, attractiveness +0.5 |
| `L-EL` | mouth.ownZ 의 `upperLipEline` ≥ 1 **and** `lowerLipEline` ≥ 1 | sensuality +0.5, libido +0.5 |

L-AQ/L-SN 은 binary flag 만 소비, L-EL 은 mouth 노드의 직계 lateral z 를 직접 탐색. 측면 없으면 `hasLateral == false` 로 전 stage skip (delta 0, 정면 파이프라인만 돈다).

### dark metric 경보

`dorsalConvexity` 의 z ∈ [1, 3) "살짝 매부리" 는 현재 연속 rule 없음 — aquiline flag 임계(z≥3) 이상에서만 해석 발동. `nasofrontalAngle` 도 직접 rule 희소 → 산근(질액궁) 해석 여지 남음. 추후 연속 대역 rule 도입 시 이 둘이 1순위.

---

## Frame Processing (카메라 모드)

```
CameraController.startImageStream()
  → 플랫폼 분기
    Android: NV21 (yPlane + vuPlane split) → processNv21()
    iOS:     BGRA → process()
  → FaceMeshResult (468 landmarks, triangles, score)
  → 추적 품질 체크 → overlay 색 (Red/Green)
  → CustomPainter 오버레이
```

### Key Design Decisions (까먹지 말 것)

- **Android NV21**: camera 가 `planes[0]` 에 단일 버퍼로 delivery → Y (width×height bytes) 와 VU (나머지) 로 분리해야 `FaceMeshNv21Image` 로 넘길 수 있음
- **Portrait aspect**: `controller.value.previewSize` 는 센서 orientation(landscape) → portrait 에선 width/height swap
- **Overlay 정렬**: camera preview + mesh overlay 를 같은 `SizedBox` in `FittedBox(fit: BoxFit.cover)` 에 배치 → 좌표 자동 매치
- **Frame throttling**: `_isProcessing` flag 로 이전 frame 처리 중이면 skip
- **ROI tracking**: `enableRoiTracking: true` — 별도 face detector 불필요
- **Ratios over absolute**: normalized landmarks (0~1) → 비율이 scale-invariant

### Overlay 색 기준

- **Red** (기본): 평범 tracking
- **Green**: accurate tracking — 4가지 동시 만족
  1. confidence ≥ 0.85
  2. 프레임 간 안정성 (landmark 평균 이동 < 0.005)
  3. face width > 프레임 25%
  4. yaw class 가 현재 캡처 단계와 일치 (frontal → `YawClass.frontal`, lateral → `YawClass.threeQuarter`)

## Album Analysis Flow (`home_screen.dart::_openAlbum`)

```
1. 스낵바 "정면 사진을 올려주세요" → pickImage (single)
2. MediaPipe 추론 → AlbumPreviewPage(phase=frontal) 모달
   - "정면 분석" 버튼 → pop(true)
3. 스낵바 "측면(3/4) 사진을 올려주세요" → pickImage (single)
4. MediaPipe 추론 → AlbumPreviewPage(phase=lateral) 모달
   - "측면 분석" 버튼 → pop(true) → _runAnalysis()
5. analyzeFaceReading() — 17 frontal + 8 lateral + rich evidence 전부 채움
6. Thumbnail 생성 (flutter_image_compress, 128px WebP) → Documents/{uuid}.webp
7. historyProvider.add(report) → Hive 저장 (thumbnailPath 포함)
8. 히스토리 탭 전환 → SupabaseService().saveMetrics(report) 비동기
```

- Demographics (gender / ageGroup / ethnicity) 는 Hive `prefs` box 에 persist
- 셋 중 하나라도 미선택이면 홈 화면의 카메라/앨범 버튼 비활성
- 리포트 Hive box 는 schema 변경 시 drop-recreate — `fromJsonString` 실패 시 history_provider 가 `_box.clear()` 호출

## Gender-Specific Analysis

현 파이프라인에서 성별이 분기되는 지점:

1. **Weight matrix delta** (`attribute_derivation.dart::_genderDelta`): attribute별 base 노드 가중치가 남/여 다르게 (예: attractiveness 의 nose 남 +0.05 / 여 −0.05). Row 합은 1.00 유지.
2. **Quantile normalize** (`attribute_normalize.dart`): 성별별 21-point quantile 테이블로 raw → 5~10 변환. 남/여 attribute 분포 차이(특히 sensuality/libido)를 흡수.
3. **Archetype intro** (`report_assembler.dart`): archetype 소개 문구가 `report.gender` 로 분기.
4. **Age adjustment** (`age_adjustment.dart`): 50+ 보정이 성별마다 다른 값.

## 테스트 · 빌드

```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter test                         # 현 baseline 73 pass
flutter run                          # 실기 (카메라는 simulator 불가)
```

### Monte Carlo 재보정 (weight matrix / rule / reference 건드린 뒤)

```bash
flutter test test/calibration_test.dart
```

출력된 21-point map 을 `attribute_normalize.dart` 의 `_attrQuantilesMale` / `_attrQuantilesFemale` 에 붙여 넣고, 하위 테스트 green 확인:

- `archetype_fairness_test.dart` — archetype 분포 공정성
- `archetype_template_sanity_test.dart` — 6 template 별 ≥70% hit
- `score_distribution_test.dart` — spread ≥ 3.0, saturation < 5%
- `compat_label_fairness_test.dart` — 10/30/30/30 분포 (thresholds 84/73/65, 2026-04-19 v2.6 재보정)

## Platform Setup

- **Android**: `CAMERA` permission in `AndroidManifest.xml`
- **iOS**: `NSCameraUsageDescription` in `Info.plist`
- 실기기 필수 (simulator/emulator 는 camera 불가)
