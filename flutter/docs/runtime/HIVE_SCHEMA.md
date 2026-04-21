# Hive 저장 스키마 · Metric/관상 조합 Key Map

**버전**: v1 (capture-only)
**마지막 업데이트**: 2026-04-21
**역할**: Hive 에 **무엇을 저장하는가**, **무엇을 저장하지 않는가(load 시 재계산)**, 그리고 저장된 JSON 의 모든 top-level key · 17 frontal + 8 lateral metric ID 를 한 장에 정리한 SSOT. 스키마 확장 · metric 추가 · 새 해석 layer 도입 시 진입점.

---

## 0. 왜 이 문서가 필요한가

`engine/TAXONOMY.md` 는 "14-node tree 관점" 으로 metric 을 본다.
`engine/ATTRIBUTES.md` 는 "10 attribute × 5-stage rule 관점" 으로 metric 을 본다.
`runtime/OUTPUT_SAMPLES.md` 는 "파이프라인 출력 샘플" 을 보여준다.

그러나 **"Hive 디스크에 실제로 뭐가 들어가는가"** 를 단일 view 로 정리한 문서는 없었다. Hive 에 무엇이 저장되는지 명확해야:

1. **엔진 확장**: metric 을 추가할 때 어느 파일·어느 리스트를 손 대야 기존 저장본이 깨지지 않는지 안다.
2. **파생 재계산 경계**: 엔진 버전을 올릴 때 무엇이 자동 반영되고 무엇이 schemaVersion bump 대상인지 안다.
3. **Supabase mirror**: 원격 저장 포맷이 로컬 Hive 와 어떻게 대응되는지 안다.
4. **실측 데이터 누적**: rawValue 만 축적되므로 누적된 샘플로 reference 재보정 · quantile 재생성이 가능함을 보장한다.

---

## 1. Hive Box 개요

`core/hive/hive_setup.dart::HiveBoxes` 에 정의된 3 개 box 전부 `Box<String>`. value 는 항상 문자열 — 복잡 데이터는 JSON 직렬화로 owned.

| Box | 상수 이름 | 저장 내용 | value 타입 | Provider |
|---|---|---|---|---|
| `history` | `HiveBoxes.history` | FaceReadingReport JSON (카메라 + 앨범 리포트 모두) | `String` (JSON) | `history_provider.dart::HistoryNotifier` |
| `prefs` | `HiveBoxes.prefs` | 사용자 데모그래픽 prefs (gender/age/ethnicity) | `String` (enum name) | `gender_provider` · `age_group_provider` · `ethnicity_provider` |
| `auth` | `HiveBoxes.auth` | Supabase 세션 토큰 / Kakao OAuth 잔여물 | `String` | `auth_*_provider` |

`history` 가 **관상 해석의 유일한 SSOT**. 나머지 2 개는 UI state/auth.

### 1.1 history box 의 key 생성 규칙

- `_box.add(json)` 만 사용 → Hive 가 auto-increment int key 할당
- 저장 순서 = 최신 리포트가 앞 (history_provider `add()` 가 `state = [report, ...state]` 후 `_box.clear()` + 전량 재삽입)
- **Hive key 자체는 의미 없음** — 리포트 식별자는 value JSON 안의 `supabaseId` (UUID)

### 1.2 prefs box 의 key

| Key | Value 예시 | 출처 |
|---|---|---|
| `gender` | `'male'` · `'female'` | `Gender.values.byName()` |
| `ageGroup` | `'twenties'` · `'thirties'` · `'forties'` · `'fifties'` · `'sixties'` | `AgeGroup.values.byName()` |
| `ethnicity` | `'eastAsian'` · `'southAsian'` · `'european'` · `'african'` · `'middleEastern'` · `'latinAmerican'` | `Ethnicity.values.byName()` |

세 값 모두 필수 — 하나라도 미선택이면 홈에서 카메라/앨범 진입 버튼이 비활성 (reference table lookup 에 필요).

---

## 2. FaceReadingReport JSON — v1 Capture-Only 원칙

### 2.1 원칙

> **저장되는 것은 "카메라가 본 raw 측정값 + 촬영 맥락(인종/성별/연령대/얼굴형) + UI 메타(썸네일/alias/supabaseId)" 뿐이다. 엔진이 만들어낸 모든 해석(z-score · nodeScores · attributes · rules · archetype)은 load 시점에 현재 엔진으로 재계산된다.**

#### 왜?

| 저장하면 생기는 문제 | v3 해결 방식 |
|---|---|
| reference 를 재보정하면 기존 리포트의 z 가 stale | rawValue 만 저장 → load 때 새 ref 로 즉시 재 z-score |
| weight matrix 를 수정하면 기존 attribute 점수가 옛 공식 결과 | attribute 저장 안 함 → load 때 현재 matrix 로 재계산 |
| 새 rule 을 도입하면 기존 리포트에 발동 안 됨 | rule 결과 저장 안 함 → load 때 현재 rule 세트로 재발동 |
| quantile table 재생성하면 5~10 정규화가 shift | normalizedScore 저장 안 함 → load 때 현재 quantile 로 재 blend |
| archetype 분류 기준 바뀌면 historical 리포트의 archetype label 이 stale | archetype 저장 안 함 → load 때 현재 top-2 로 재분류 |

**결과**: 엔진 버전(weight · rule · quantile · classifier cutoff) 이 오르면 Hive 의 모든 리포트가 자동으로 새 공식의 결과를 받는다. `schemaVersion` 을 올릴 필요가 없다.

`schemaVersion` 은 **capture 필드 자체가 바뀔 때만** 증가: metric 리스트 add/remove, rawValue 의미 변경 등.

### 2.2 Top-Level Key 전체 목록

코드 SSOT: `lib/domain/models/face_reading_report.dart::toJsonString()`.

| Key | Type | 용도 | 변경 시 schemaVersion bump? |
|---|---|---|---|
| `schemaVersion` | int | 항상 `1` | — (이 값 자체가 bump 신호) |
| `ethnicity` | string (enum name) | reference table lookup | 값 추가 시 bump (남은 reference 없으면 null-deref) |
| `gender` | string (enum name) | reference + quantile + gender delta | bump |
| `ageGroup` | string (enum name) | `isOver50` 게이팅 (Age rule A-## + quantile 미반영) | 값 추가 시 bump |
| `timestamp` | ISO8601 string | 촬영 시각 (UI 히스토리 정렬) | — |
| `source` | string (`'camera'` \| `'album'`) | 썸네일 아이콘 분기 | — |
| `supabaseId` | string? (UUID) | 원격 mirror / compat 탭 ref | — |
| `alias` | string? | 사용자 지정 이름 (compat 탭 표시용) | — |
| `isMyFace` | bool | "내 얼굴" 한 건 배타 플래그 | — |
| `thumbnailPath` | string? | Documents 내부 128px WebP 경로 | — |
| `expiresAt` | ISO8601 string | 기본 촬영+90일, 지나면 load 때 드롭 | — |
| `metrics` | `Map<string, double>` | **17 frontal raw value** (아래 §3) | metric id 추가 시 **bump** |
| `lateralMetrics` | `Map<string, double>?` | **8 lateral raw value** (측면 있을 때만) | 추가 시 **bump** |
| `faceShapeLabel` | string? | TFLite classifier 영어 label (`'Oval'` 등) | — |
| `faceShapeConfidence` | double? | classifier softmax max (0~1) | — |
| `faceShape` | string (enum name) | 도메인 FaceShape enum name — archetype overlay · 서술 엔진 key | 값 추가 시 bump |

**주의**: `lateralFlags` · `nodeScores` · `attributes` · `rules` · `archetype` 는 **저장되지 않는다** (§4 참조).

### 2.3 최소 리포트 예시 (frontal only)

```json
{
  "schemaVersion": 1,
  "ethnicity": "eastAsian",
  "gender": "female",
  "ageGroup": "thirties",
  "timestamp": "2026-04-20T10:01:00.000Z",
  "source": "camera",
  "supabaseId": "a1b2c3d4-...",
  "alias": null,
  "isMyFace": true,
  "thumbnailPath": "/data/user/0/.../Documents/a1b2c3d4-...webp",
  "expiresAt": "2026-07-19T10:01:00.000Z",
  "metrics": {
    "faceAspectRatio": 1.28,
    "faceTaperRatio": 0.81,
    "upperFaceRatio": 0.32,
    "midFaceRatio": 0.29,
    "lowerFaceRatio": 0.39,
    "lowerFaceFullness": 0.82,
    "gonialAngle": 145.0,
    "intercanthalRatio": 0.27,
    "eyeFissureRatio": 0.21,
    "eyeCanthalTilt": 7.0,
    "eyeAspect": 0.30,
    "eyebrowThickness": 0.036,
    "browEyeDistance": 0.155,
    "eyebrowCurvature": 0.08,
    "eyebrowTiltDirection": 2.0,
    "browSpacing": 0.12,
    "nasalWidthRatio": 0.88,
    "nasalHeightRatio": 0.31,
    "mouthWidthRatio": 0.40,
    "mouthCornerAngle": 4.5,
    "lipFullnessRatio": 0.13,
    "upperVsLowerLipRatio": 0.7,
    "philtrumLength": 0.085,
    "foreheadWidth": 0.74,
    "cheekboneWidth": 0.92,
    "chinAngle": 85.0
  },
  "faceShapeLabel": "Oval",
  "faceShapeConfidence": 0.83,
  "faceShape": "oval"
}
```

측면까지 포함되면 `"lateralMetrics"` 블록이 추가되고 파이프라인이 Track 3 를 완전히 돈다.

---

## 3. Metrics — 17 Frontal + 8 Lateral ID 완전 목록

코드 SSOT: `lib/data/constants/face_reference_data.dart::metricInfoList` · `lateralMetricInfoList`.

### 3.1 Frontal Metric (17 × 6 ethnicity × 2 gender mean/sd)

| # | Metric ID | 소속 Node | 관상 의미 | Attribute 소비 경로 |
|---|---|---|---|---|
| 1 | `faceAspectRatio` | face(root) | 얼굴형 기본 구조 (장/원/방형) | Z-FAR (v2.9) · Track 1 classifier |
| 2 | `faceTaperRatio` | face(root) | V형 vs 사각형 | 성별 delta 만 (Stage 5) |
| 3 | `upperFaceRatio` | 이마(forehead) | 초년운 · 지성 · 사고 | Z-02/05/09, forehead.ownZ |
| 4 | `midFaceRatio` | face(root) | 중년운 · 사회 활동성 | Z-11 (중정 비율 큼) |
| 5 | `lowerFaceRatio` | 턱(chin) | 말년운 · 의지력 | Z-12/13 |
| 6 | `lowerFaceFullness` | 턱(chin) | 턱살 볼륨 | chin.ownZ |
| 7 | `gonialAngle` | 턱(chin) | 의지력 · 권위 · 리더십 | chin.ownZ · O-CH · P-SV |
| 8 | `intercanthalRatio` | 눈(eye) | 사고 범위 · 개방성 | Z-IC (v2.9) · eye.ownZ |
| 9 | `eyeFissureRatio` | 눈(eye) | 통찰력 · 사회성 | eye.ownZ |
| 10 | `eyeCanthalTilt` | 눈(eye) | 매력 · 성격 방향성 · 처첩궁 | O-MM (v2.9 도화안) · P-06 (처첩궁) |
| 11 | `eyeAspect` | 눈(eye) | 눈매 길이/높이 | eye.ownZ |
| 12 | `eyebrowThickness` | 눈썹(eyebrow) | 의지력 · 성격 강도 | eyebrow.ownZ · O-EB* |
| 13 | `browEyeDistance` | 눈썹(eyebrow) | 인내심 · 사고 깊이 | eyebrow.ownZ |
| 14 | `eyebrowCurvature` | 눈썹(eyebrow) | 눈썹 굴곡 | eyebrow.ownZ |
| 15 | `eyebrowTiltDirection` | 눈썹(eyebrow) | 八字眉 여부 (음=처진 눈썹) | Z-EBT (v2.9) · O-EM2 (v2.9) |
| 16 | `browSpacing` | 미간(glabella) | 명궁 너비 | **classifier-only** (face_shape_classifier 28-feature) + glabella.ownZ |
| 17 | `nasalWidthRatio` | 코(nose) | 재백궁 핵심 · 재물 | nose.ownZ · O-NM · P-01 |
| 18 | `nasalHeightRatio` | 코(nose) | 재백궁 규모 · 중년운 | nose.ownZ |
| 19 | `mouthWidthRatio` | 입(mouth) | 사회성 · 언변 | mouth.ownZ · O-RL (v2.9) |
| 20 | `mouthCornerAngle` | 입(mouth) | 낙관성 · 인간관계 | mouth.ownZ |
| 21 | `lipFullnessRatio` | 입(mouth) | 감정 표현 · 애정 | Z-LFR · O-RL (v2.9) |
| 22 | `upperVsLowerLipRatio` | 입(mouth) | 상하순 균형 | mouth.ownZ |
| 23 | `philtrumLength` | 인중(philtrum) | 생명력 · 자식운 · 정력 | philtrum.ownZ · O-PH1/2 |
| 24 | `foreheadWidth` | 이마(forehead) | 이마 폭 (정규화) | forehead.ownZ |
| 25 | `cheekboneWidth` | 광대(cheekbone) | 권위 · 사회 활동력 · 오악 태/화산 | cheekbone.ownZ · O-CK/CB · O-CKE |
| 26 | `chinAngle` | 턱(chin) | 턱끝 각도 | chin.ownZ |

실제 저장되는 id 는 26 개. "17 frontal" 이라는 표현은 **tree 에 직접 투입되는 rule-있는 metric** 만 센 것이고, 일부(browSpacing·foreheadWidth 등)는 classifier-only 혹은 보조 metric. 모두 Hive `metrics` 블록에 동일한 형태(key=id, value=rawValue)로 저장된다.

### 3.2 Lateral Metric (8 × East Asian baseline, 인종 fallback)

| # | Metric ID | 소속 Node | 참고 평균 (여성 동아시아) | 소비 rule |
|---|---|---|---|---|
| 1 | `nasofrontalAngle` | 코(nose) | ~141° | O-NF1/2 |
| 2 | `nasolabialAngle` | 코(nose) | 130~140° | snubNose · droopingTip flag |
| 3 | `facialConvexity` | face(root) | ~7.7° | root.ownZ |
| 4 | `upperLipEline` | 입(mouth) | ~-1mm / faceHeight | mouth.ownZ (L-EL trigger) |
| 5 | `lowerLipEline` | 입(mouth) | 동일 규약 | L-EL |
| 6 | `mentolabialAngle` | 턱(chin) | ~134° | chin.ownZ |
| 7 | `noseTipProjection` | 코(nose) | (Goode 유사) | flatNose flag (z ≤ -3) |
| 8 | `dorsalConvexity` | 코(nose) | (signed) | aquilineNose/saddleNose flag · O-DC1/2 |

측면이 없으면 `lateralMetrics` 키 자체가 JSON 에서 빠진다. `hasLateral = false` 로 흐르며 Stage 5 의 lateral rule 3 개(`L-AQ`·`L-SN`·`L-EL`)가 전부 skip.

---

## 4. 저장 안 되는 것 (Load 시 재계산)

`face_reading_report.dart::fromJsonString()` 의 rehydrate 순서. capture → derived 흐름이 fresh capture 경로(`analyzeFaceReading()`)와 **1:1 동일** 해야 한다.

```
저장된 capture
  ↓
1. rawValue → ref.mean/sd 로 z-score 재계산           (stale-z 차단)
2. z → adjustForAge(age, gender) → zAdjusted
3. zAdjusted → convertToScore() → metricScore (0~100 정수)
4. lateralFlags 재계산 (dorsalConvexity z≥3 → aquilineNose 등)
5. scoreTree(zAll) → 14-node NodeScore (own + rollUp 이중축)
6. deriveAttributeScoresDetailed(tree, gender, isOver50, lateralFlags, faceShape)
   → base (9-node matrix) + distinctiveness + Zone rules + Organ rules
   + Palace rules + Age rules + Lateral flag rules → Map<Attribute, double> raw
7. normalizeAllScores(raw, gender) → 40% rank + 60% quantile blend → 5.0~10.0
8. classifyArchetype(normalized, shape) → primary + secondary + special archetype
9. _rehydrate* 헬퍼가 위 산출을 NodeEvidence · AttributeEvidence · RuleEvidence
   로 패킹 → FaceReadingReport 런타임 필드로 복원
```

### 4.1 재계산되는 필드 목록 (저장 금지)

| 필드 | 재계산 근거 | 저장 시 발생할 문제 |
|---|---|---|
| `MetricResult.zScore` | `(raw - ref.mean) / ref.sd` — 현재 `face_reference_data.dart` | reference 재보정 시 기존 리포트가 옛 ref 로 고착 |
| `MetricResult.zAdjusted` | `adjustForAge()` 현재 규칙 | 연령 보정 공식 바꿔도 반영 안 됨 |
| `MetricResult.metricScore` | `convertToScore(zAdj)` — 현재 threshold | 스코어 스케일 바꿔도 반영 안 됨 |
| `lateralFlags` | 현재 z 임계 (`dorsalConvexity z ≥ 3` 등) | 임계 조정 시 stale |
| `nodeScores` | `scoreTree(zAll)` 현재 tree 구조 | 노드 추가/제거 시 inconsistent |
| `attributes` | 5-stage pipeline 현재 weight matrix + 모든 rule | weight/rule 바꿀 때마다 매번 schemaVersion bump 필요해져서 운용 불가 |
| `attributes[*].normalizedScore` | `_attrQuantilesMale/Female` 현재 quantile table | calibration 재생성이 기존 리포트에 반영 안 됨 |
| `rules` (triggered) | 현재 rule 세트 재발동 | 새 rule (예: v2.9 美人相 7개) 이 기존 리포트에 미적용 |
| `archetype` | `classifyArchetype()` 현재 분류 기준 | archetype label/special 조건 변경 시 stale |

**golden rule**: 공식에서 나오는 값은 전부 derived. Hive 는 카메라·사용자 입력 원본만 담는다.

### 4.2 이 원칙의 예외 (저장되는 "semi-derived")

| 필드 | 이유 |
|---|---|
| `faceShape` · `faceShapeLabel` · `faceShapeConfidence` | TFLite classifier 출력. 모델 교체는 schemaVersion bump 대상이 아니라 새 모델 배포 + 앱 업데이트로 처리. classifier 결과를 저장해야 archetype shape-gated overlay 와 narrative Layer B 가 load 시점에 결정론적으로 동일한 결과를 준다. 재계산하려면 load 시점에 landmark 를 다시 가지고 있어야 하는데 Hive 엔 없음. |

---

## 5. Metric × Attribute × Rule 조합 교차 참조

Hive 에 저장된 rawValue 가 어디로 흘러가는지의 **전체 의존 그래프**. 확장 시 새 metric 이 어떤 레이어에 소비될지 결정할 때 참고.

### 5.1 경로 요약

```
rawValue (Hive metrics/lateralMetrics 블록의 한 entry)
   ↓  face_reference_data.dart::metricInfoList|lateralMetricInfoList 의 id 매칭
z-score per metric
   ↓  physiognomy_tree.dart 의 노드.metricIds 에 따라 node 로 집계
NodeScore.ownMeanZ / ownMeanAbsZ / rollUpMeanZ / rollUpMeanAbsZ
   ↓  attribute_derivation.dart 의 5 stage
base (9-node × 10-attr weight) + distinctiveness + Z-## + O-## + P-## + A-## + L-##
   ↓
raw attribute score (10 값)
   ↓  attribute_normalize.dart 의 gender quantile + rank blend
normalized score 5.0~10.0 (UI 바 차트)
   ↓  archetype.dart (top-2 + special condition)
ArchetypeResult (primary · secondary · special · faceShape overlay)
```

### 5.2 관상학 전통 조합 layer (메타데이터 오버레이)

`physiognomy_tree.dart` 의 각 노드가 태그로 보유. Hive 에는 저장 안 되지만 rule ID 체계의 네이밍 규칙으로 드러남.

| 체계 | 태그 수 | 해석 레이어 | 대표 rule prefix |
|---|---|---|---|
| 오관(五官) 보수·감찰·심변·출납·채청 | 5 | Organ pair rules | O-EB*, O-EM*, O-NM*, O-CK* |
| 오악(五嶽) 형·태·화·숭·항산 | 5 | Organ volume rules | O-CK*, O-CH, O-NC |
| 사독(四瀆) 강·하·회·제 | 4 | (currently implicit in nose/eye/mouth) | — |
| 십이궁(十二宮) 명·재백·형제·전택·남녀·노복·처첩·질액·천이·관록·복덕·상모 | 12 | Palace overlay rules | P-01 재백+전택, P-04 형제, P-05 남녀, P-06 처첩, P-07 질액, P-08 천이, P-09/09B 명궁, P-02 관록+천이, P-03 복덕, P-MJ 印堂 |
| 삼정(三停) 상·중·하 | 3 (zone roll-up) | Zone rules | Z-01~13 + Z-FH/IC/LFR/FAR/EBT/NG |

### 5.3 현재 활성화된 rule 총량 (engine v2.9)

| Stage | 규칙 수 | prefix |
|---|---|---|
| Zone | 20 (v2.9: +Z-FH/IC/FAR/EBT/NG) | `Z-##` |
| Organ | 24 (v2.9: +O-MM/EM2/RL/CKE/EZ) | `O-##` |
| Palace | 11 (v2.9: +P-MJ) | `P-##` |
| Age (50+) | 4 | `A-##` |
| Lateral flag | 3 | `L-##` |
| **total** | **62** | — |

모든 규칙의 `|Δ| ≤ 0.5` cap (v2.6 이후 invariant). 규칙 완전 명세는 `engine/ATTRIBUTES.md` §4.1–5.3.

---

## 6. 확장 체크리스트

### 6.1 신규 Frontal Metric 추가

1. `lib/domain/services/face_metrics.dart::computeAll()` 에 계산 로직 + id 반환
2. `lib/data/constants/face_reference_data.dart::metricInfoList` 에 `MetricInfo(id: ..., type: ...)` entry 추가
3. 같은 파일 `referenceData` 의 모든 (ethnicity × gender) 12 entry 에 mean/sd 추가 (empirical 데이터 없으면 East Asian 값 fallback)
4. `lib/domain/models/physiognomy_tree.dart` 의 적절한 노드 `metricIds` 에 추가 (어느 부위 소속인지)
5. `docs/engine/TAXONOMY.md` §3 의 해당 노드 Metrics 줄 갱신
6. `lib/domain/services/attribute_derivation.dart` 의 weight matrix · rule 에 소비처 연결 (필요 시)
7. `test/calibration_test.dart` 실행 → 신규 metric 포함된 새 quantile table 을 `attribute_normalize.dart` 에 반영
8. **schemaVersion bump** (`face_reading_report.dart::kReportSchemaVersion`) — Hive 내 옛 리포트는 `FormatException` → history_provider 가 자동 drop
9. `docs/runtime/HIVE_SCHEMA.md` (이 문서) §3.1 테이블 갱신
10. `physiognomy_tree_sanity_test.dart` · `real_users_recalibration_test.dart` 그린 확인

### 6.2 신규 Lateral Metric 추가

Frontal 과 동일하되:
- `face_metrics_lateral.dart::computeAll()` 사용
- `lateralMetricInfoList` + `lateralReferenceData` 갱신 (인종 fallback 는 East Asian 공용)
- schemaVersion bump 동일

### 6.3 신규 Rule (Zone/Organ/Palace/Age/Lateral) 추가

**schemaVersion bump 불필요** — capture-only 덕에 새 rule 이 load 때 자동 발동.

1. `attribute_derivation.dart` 의 해당 stage 리스트에 rule entry 추가
2. `ATTRIBUTES.md` §4.x 테이블 + (신규면) §12 전통 근거
3. `rule_text_blocks.dart` 에 rule ID → 본문 매핑 추가
4. `evidence_snapshot_test.dart` 의 예상 rule 개수 갱신
5. `calibration_test.dart` 재실행 → quantile table 재생성 → `attribute_normalize.dart` 반영
6. 궁합 엔진 calibration 재실행 — 자세한 절차는 `docs/compat/FRAMEWORK.md` §8.1

### 6.4 신규 Attribute (11번째 속성) 추가

**schemaVersion bump 불필요** — attribute 도 derived.

1. `data/enums/attribute.dart` 에 enum value 추가
2. `attribute_derivation.dart::_weightMatrix` 의 모든 9 노드 행에 weight 추가 (행 합 = 1.00 invariant 유지)
3. `archetype.dart::attributeLabels` · archetype pairing map 갱신
4. `attribute_normalize.dart::_attrQuantilesMale/Female` 재생성
5. `data/constants/archetype_text_blocks.dart` · `rule_text_blocks.dart` 신규 attribute 본문
6. `attribute_derivation_test.dart` · `score_distribution_test.dart` 갱신
7. `ATTRIBUTES.md` §2.2 matrix + archetype 표 갱신

### 6.5 신규 해석 오버레이 (예: 음양 축 UI 노출)

`lib/domain/services/yin_yang.dart` 가 이미 계산은 하지만 UI 에 붙지 않음. Hive 스키마 불변. capture 재계산 경로에 새 derived 객체 추가하면 끝 (report_page 에 widget 바인딩).

---

## 7. Supabase Mirror

`supabase_service.dart::saveMetrics()` 가 `FaceReadingReport.toJsonString()` 결과를 그대로 `metrics` 테이블의 `metrics_json` TEXT 컬럼에 저장. 스키마 대응:

| Hive JSON key | Supabase column |
|---|---|
| (전체 JSON) | `metrics_json` (TEXT) |
| `source` | `source` (TEXT, `'camera'` or `'album'`) |
| `ethnicity` | `ethnicity` (TEXT) |
| `gender` | `gender` (TEXT) |
| `ageGroup` | `age_group` (TEXT) |
| `expiresAt` | `expires_at` (TIMESTAMPTZ) |
| `alias` | `alias` (TEXT, nullable) |
| `supabaseId` | `id` (UUID PK) |
| — | `user_id` (auth.uid() FK, Phase 3) |
| — | `created_at` (now()) |

**중요**: Supabase 쪽도 capture-only. 원격에 z-score/attribute/archetype 을 중복 저장하지 않는다 → reference 재보정이나 엔진 업그레이드가 전 리포트에 투명하게 반영. 원격 열람 시 Flutter 앱이 `metrics_json` 을 `FaceReadingReport.fromJsonString()` 에 넘겨 **열람한 앱의 현재 엔진 버전**으로 재계산.

자세한 SQL: `docs/supabase/SQL.md`.

---

## 8. 디버깅 참고

### 8.1 리포트가 사라질 때

`history_provider._loadFromHive()` / `reloadFromHive()` 에 `_log()` trace 삽입되어 있음. `flutter logs` 에서:

- `[History] load entry $i: ...` — 순차 처리 시작
- `[Report.rehydrate] ...` — `fromJsonString()` 의 각 단계 (enum decode · rawMetrics · frontalRefs lookup · z 계산 · scoreTree · derive · normalize · archetype)
- `[History] load FAIL entry $i: ...` + stacktrace — 실패 시 어느 단계에서 터졌는지

parse 실패 entry 는 raw JSON 을 살려두고 state 에서만 드롭. `schemaVersion` 이 `kReportSchemaVersion` 과 불일치하는 payload(포맷 불일치 또는 필드 누락) 도 이 경로로 조용히 빠진다.

### 8.2 "저장한 게 다음 세션에 안 남아있다"

1. `HistoryNotifier._saveToHive()` 는 `_box.clear()` + 전량 재삽입 후 `await _box.flush()`. flush 전에 앱 죽으면 손실.
2. `add()` 호출 순서: `state = [...]` → `_saveToHive()` 는 await. Provider 가 await 하기 전에 화면이 pop 되면 flush 미완료.
3. `reloadFromHive()` 의 abort 가드: `parsed.isEmpty && state.isNotEmpty && failedCount == 0` 이면 box 재기록 skip — Hive async race 로 비어 보이는 경우에도 state 보존.

### 8.3 Hive box 초기화

개발 중 리포트 스키마가 불일치하면:

```dart
// main.dart 또는 개발 hook
await Hive.box<String>(HiveBoxes.history).clear();
```

프로덕션에선 schemaVersion mismatch 가 자동으로 entry 드롭하므로 수동 clear 불필요. `prefs` box 는 따로 손 대지 않는 한 남는다.

---

## 9. 참고 링크

- `lib/domain/models/face_reading_report.dart` — `toJsonString()` / `fromJsonString()` 코드 SSOT
- `lib/core/hive/hive_setup.dart` — Hive box 이름
- `lib/presentation/providers/history_provider.dart` — load/save/reload 로직
- `lib/data/constants/face_reference_data.dart` — metric 정의 + reference mean/sd SSOT
- `docs/engine/TAXONOMY.md` — 노드-metric 매핑
- `docs/engine/ATTRIBUTES.md` — weight matrix + 62 rule 명세
- `docs/engine/NORMALIZATION.md` — 40/60 blend + quantile table
- `docs/runtime/OUTPUT_SAMPLES.md` — 파이프라인 출력 샘플
- `docs/supabase/SQL.md` — 원격 스키마

---

## 10. 문서 갱신 규칙

- 이 문서는 **Hive / 원격 저장 포맷 변경 시 반드시 먼저 갱신** → 그 다음 코드.
- §2.2 top-level key 표는 `face_reading_report.dart::toJsonString()` 과 1:1 동기.
- §3.1·§3.2 metric 표는 `face_reference_data.dart::metricInfoList` · `lateralMetricInfoList` 과 1:1 동기.
- schemaVersion bump 시 이 문서 제목의 버전 + `kReportSchemaVersion` + `CLAUDE.md "Hive schemaVersion"` 세 곳 동시 갱신.
