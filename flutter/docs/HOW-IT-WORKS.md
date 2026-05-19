# HOW IT WORKS — 관상 엔진 기술 구현

**최종 업데이트**: 2026-05-19
**역할**: 얼굴 입력부터 리포트 본문까지, 엔진이 무엇을 어떻게 계산하는지의 SSOT.
**관련**: 화면·폴더 구조는 [ARCHITECTURE.md](ARCHITECTURE.md), 디자인 토큰은 [DESIGN.md](DESIGN.md).

---

## 1. 파이프라인 한눈에

```
MediaPipe Face Mesh (468 landmarks · 정면 + 3/4 측면)
        │
        ▼
FaceMetrics.computeAll()       → 17 frontal raw metric
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

핵심 entry point: `lib/domain/models/face_analysis.dart::analyzeFaceReading()`.

---

## 2. 17 Frontal + 8 Lateral Metric

### 2.1 Frontal 17 (`face_metrics.dart::computeAll()`)

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

전체 ID 목록 + 코드 SSOT: `lib/data/constants/face_reference_data.dart::metricInfoList`.

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
- **재보정**: MediaPipe 좌표계 차이 흡수 위해 2026-04-12 경험적 재보정. N=14 East Asian female 30s 실사용자 empirical z 가 N(0,1) 에 수렴하도록 reference mean 19 metric 재조정 (engine v2.8).

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

코드 SSOT: `lib/domain/models/physiognomy_tree.dart`.
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

`face_reading_report.dart::toJsonString()` SSOT:

```
schemaVersion(1) · ethnicity · gender · ageGroup · timestamp · source
supabaseId · alias · isMyFace · thumbnailPath · expiresAt
metrics (17 frontal raw)
lateralMetrics? (8 lateral raw)
faceShapeLabel? · faceShapeConfidence? · faceShape (enum)
```

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

관상 엔진과 **동등한 별도 엔진** — `lib/domain/services/compat/`. 입력은 두 개의 `FaceReadingReport` (capture만 의존, attributes/archetype 미의존 — double-interpretation 차단).

### 7.1 4 sub-score

| sub | 이름 | weight | 입력 |
|---|---|---|---|
| `elementScore` (L1) | 五形和 | 0.20 | 얼굴형 metric 7개 + faceShape preset → 五行 분류 + 5×5 상생상극 matrix |
| `palaceScore` (L2) | 宮位調 | 0.40 | 17+8 metric ~22개 → 12 궁 state + ~40 PalacePair rule |
| `qiScore` (L3) | 氣質合 | 0.25 | 五官 1:1 (0.55) + 三停 合刑 (0.25) + 陰陽 balance (0.20) |
| `intimacyScore` (L4) | 性情諧 | 0.15 | 30~50 opposite-gender 게이트. 男女宮·妻妾宮·lip·philtrum |

총점:
```
rawTotal = 0.20·element + 0.40·palace + 0.25·qi + 0.15·intimacy
total = clamp(50 + (rawTotal - 50) × 1.4, 5, 99)
```

### 7.2 Label 4-tier

MC p-percentile 보정:
- `天作之合` (≥85)
- `相敬如賓` (72~85)
- `磨合可成` (58~72)
- `刑剋難調` (<58)

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
flutter test             # 149 test 전부 green
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
