# Face Reading Formula Engine (관상학 공식 엔진)

## 1. 시스템 파이프라인

```
카메라 캡처 (5프레임 평균화)
  ↓
468 랜드마크 추출 (MediaPipe Face Mesh)
  ↓
사용자 입력: 인종, 성별(M/F), 연령대(50대 미만/이상)
  ↓
17 Metrics 계산 (scale-invariant ratios/angles)
  ↓
Z-score 정규화 (인종 × 성별 × 연령 기준값 조회)
  ↓
노화 보정 (age-affected metrics에 한해 z-score 조정)
  ↓
Metric Score 변환 (z → S: -3 ~ +3)
  ↓
10 Attribute Base Score (가중합, 성별 가중치 적용)
  ↓
Interaction Rule Engine (조건부 보너스/페널티, 성별 전용 Rule 포함)
  ↓
Score 정규화 (0 ~ 10)
  ↓
Archetype 분류 (성별별 Archetype 표현)
  ↓
LLM 총평 래핑 (deterministic 데이터 + 성별/나이 컨텍스트 + 자연어 해석)
```

---

## 2. 17 Metrics 정의

### 2.1 FACE (얼굴 윤곽) — 6개

| #   | ID              | 한글명      | 수식                                   | 랜드마크                                    |
| --- | --------------- | ----------- | -------------------------------------- | ------------------------------------------- |
| 1   | faceAspectRatio | 얼굴 종횡비 | faceHeight / faceWidth                 | dist(10,152) / dist(234,454)                |
| 2   | upperFaceRatio  | 상안면 비율 | dist(foreheadTop, nasion) / faceHeight | dist(10,168) / dist(10,152)                 |
| 3   | midFaceRatio    | 중안면 비율 | dist(nasion, subnasale) / faceHeight   | dist(168,94) / dist(10,152)                 |
| 4   | lowerFaceRatio  | 하안면 비율 | dist(subnasale, chin) / faceHeight     | dist(94,152) / dist(10,152)                 |
| 5   | faceTaperRatio  | 얼굴 테이퍼 | jawWidth / faceWidth                   | dist(172,397) / dist(234,454)               |
| 6   | gonialAngle     | 하악각      | angle(ear, gonion, chin) 양측 평균     | angle(132,172,152) + angle(361,397,152) / 2 |

### 2.2 EYES (눈) — 4개

| #   | ID                | 한글명       | 수식                                          | 랜드마크                                                     |
| --- | ----------------- | ------------ | --------------------------------------------- | ------------------------------------------------------------ |
| 7   | intercanthalRatio | 눈 사이 거리 | ICD / faceWidth                               | dist(133,362) / dist(234,454)                                |
| 8   | eyeFissureRatio   | 눈 길이      | avg(EFL) / faceWidth                          | avg(dist(33,133), dist(263,362)) / faceWidth                 |
| 9   | eyeCanthalTilt    | 눈꼬리 각도  | atan2(exo.y - endo.y, dx) 양측 평균 (degrees) | (33,133) + (263,362)                                         |
| 10  | eyebrowThickness  | 눈썹 두께    | avg(dist(upper[i], lower[i])) / faceHeight    | R:(46,70),(53,63),(52,105) / L:(276,300),(283,293),(282,334) |

### 2.3 EYES-BROW (눈썹-눈 관계) — 1개

| #   | ID              | 한글명       | 수식                                           | 랜드마크                                       |
| --- | --------------- | ------------ | ---------------------------------------------- | ---------------------------------------------- |
| 11  | browEyeDistance | 눈썹-눈 거리 | dist(browLower, eyeTop) / faceHeight 양측 평균 | avg(dist(105,159), dist(334,386)) / faceHeight |

### 2.4 NOSE (코) — 2개

| #   | ID               | 한글명  | 수식                                  | 랜드마크                     |
| --- | ---------------- | ------- | ------------------------------------- | ---------------------------- |
| 12  | nasalWidthRatio  | 코 너비 | dist(alaR, alaL) / dist(endoR, endoL) | dist(98,327) / dist(133,362) |
| 13  | nasalHeightRatio | 코 길이 | dist(nasion, subnasale) / faceHeight  | dist(168,94) / dist(10,152)  |

### 2.5 MOUTH (입) — 4개

| #   | ID               | 한글명      | 수식                                               | 랜드마크                     |
| --- | ---------------- | ----------- | -------------------------------------------------- | ---------------------------- |
| 14  | mouthWidthRatio  | 입 너비     | dist(cheilionR, cheilionL) / faceWidth             | dist(61,291) / dist(234,454) |
| 15  | mouthCornerAngle | 입꼬리 각도 | atan2(corner_y - midLip_y, dx) 양측 평균 (degrees) | (61,291,13,14)               |
| 16  | lipFullnessRatio | 입술 두께   | dist(upperLipTop, lowerLipBottom) / faceHeight     | dist(0,17) / dist(10,152)    |
| 17  | philtrumLength   | 인중 길이   | dist(subnasale, upperLipTop) / faceHeight          | dist(94,0) / dist(10,152)    |

---

## 3. 성별/연령 변수 정의

### 3.1 입력 변수

```dart
enum Gender { male, female }
enum AgeGroup { under50, over50 }
```

사용자가 앱에서 선택하는 2개 추가 입력:

- **성별 (Gender):** 남성 / 여성
- **연령대 (AgeGroup):** 50대 미만 / 50대 이상

### 3.2 노화 영향 메트릭 (Age-Affected Metrics)

468 랜드마크 기반 메트릭 중 **골격 구조** 메트릭은 나이에 영향을 받지 않지만,
**연조직(soft tissue)** 메트릭은 50대 이상에서 체계적 변화가 발생한다.

| Metric            | 나이 영향 | 50대 이상 변화 방향 | 원인                                      |
| ----------------- | --------- | ------------------- | ----------------------------------------- |
| lipFullnessRatio  | **있음**  | 감소 ↓              | 입술 볼륨 감소, 콜라겐 손실               |
| mouthCornerAngle  | **있음**  | 감소 ↓              | 구각(mouth corner) 하수, 중력             |
| browEyeDistance   | **있음**  | 감소 ↓              | 눈썹 처짐 (brow ptosis)                   |
| philtrumLength    | **있음**  | 증가 ↑              | 인중 연장 (상순 하수)                     |
| eyebrowThickness  | **있음**  | 변화 ↕              | 남성: 증가(숱 많아짐), 여성: 감소(얇아짐) |
| faceAspectRatio   | 없음      | —                   | 골격                                      |
| faceTaperRatio    | 없음      | —                   | 골격                                      |
| gonialAngle       | 없음      | —                   | 골격                                      |
| intercanthalRatio | 없음      | —                   | 골격                                      |
| eyeFissureRatio   | 없음      | —                   | 골격                                      |
| eyeCanthalTilt    | 없음      | —                   | 골격 (외안각/내안각 위치)                 |
| nasalWidthRatio   | 없음      | —                   | 연골이나 변화 극소                        |
| mouthWidthRatio   | 없음      | —                   | 골격 기반 구각 위치                       |

### 3.3 노화 보정 공식

50대 이상인 경우, 측정된 z-score에서 **노화에 의한 체계적 편향**을 제거하여
"이 사람의 원래 골상(bone structure)이었다면 어떤 값이었을까"를 추정한다.

```
z_adjusted = z_raw - age_offset
```

#### 노화 보정 오프셋 테이블 (AgeGroup.over50 일때만 적용)

| Metric           | age_offset (male) | age_offset (female) | 보정 의미                           |
| ---------------- | ----------------- | ------------------- | ----------------------------------- |
| lipFullnessRatio | -0.5              | -0.7                | 입술 얇아짐 보정 → 원래 더 두꺼웠음 |
| mouthCornerAngle | -0.6              | -0.8                | 입꼬리 처짐 보정 → 원래 더 올라갔음 |
| browEyeDistance  | -0.4              | -0.5                | 눈썹 처짐 보정 → 원래 더 높았음     |
| philtrumLength   | +0.5              | +0.6                | 인중 길어짐 보정 → 원래 더 짧았음   |
| eyebrowThickness | +0.3              | -0.3                | 남: 숱 증가 보정, 여: 숱 감소 보정  |

> **해석:** lipFullnessRatio의 z_raw가 -1.2인 50대 여성의 경우,
> z_adjusted = -1.2 - (-0.7) = **-0.5** → 젊었을 때는 "약간 얇은 입술" 수준.
> 관상 판정은 **z_adjusted**로 수행한다.

> **50대 미만은 보정 없음:** age_offset = 0 (모든 메트릭)

#### 구현 의사코드

```dart
double adjustForAge(String metricId, double zRaw, Gender gender, AgeGroup age) {
  if (age == AgeGroup.under50) return zRaw;

  final offsets = _ageOffsets[metricId];
  if (offsets == null) return zRaw; // 노화 영향 없는 메트릭

  final offset = gender == Gender.male ? offsets.male : offsets.female;
  return zRaw - offset;
}
```

### 3.4 성별 영향: Reference Data 분리

동일 인종 내에서도 남녀의 안면 비율 기준값(mean/SD)이 다르다.

#### 동아시아인 남녀 차이 (예시)

| Metric            | Male Mean | Male SD | Female Mean | Female SD | 차이 근거                  |
| ----------------- | --------- | ------- | ----------- | --------- | -------------------------- |
| faceAspectRatio   | 1.40      | 0.08    | 1.36        | 0.07      | 남성 얼굴 세로 비율 더 큼  |
| upperFaceRatio    | 0.33      | 0.03    | 0.33        | 0.03      | 성별 차이 없음             |
| midFaceRatio      | 0.33      | 0.02    | 0.33        | 0.02      | 성별 차이 없음             |
| lowerFaceRatio    | 0.34      | 0.03    | 0.34        | 0.03      | 성별 차이 없음             |
| faceTaperRatio    | 0.85      | 0.05    | 0.79        | 0.05      | 여성 턱이 더 좁음 (V라인)  |
| gonialAngle       | 118.0     | 7.0     | 122.0       | 8.0       | 남성 턱 더 각짐            |
| intercanthalRatio | 0.27      | 0.02    | 0.27        | 0.02      | 차이 없음                  |
| eyeFissureRatio   | 0.23      | 0.02    | 0.25        | 0.02      | 여성 눈이 약간 더 큼       |
| eyeCanthalTilt    | 3.5       | 3.0     | 4.5         | 3.0       | 여성 눈꼬리 약간 더 올라감 |
| eyebrowThickness  | 0.017     | 0.004   | 0.013       | 0.003     | 남성 눈썹 더 두꺼움        |
| browEyeDistance   | 0.058     | 0.014   | 0.062       | 0.015     | 여성 전택 약간 더 넓음     |
| nasalWidthRatio   | 1.08      | 0.10    | 1.02        | 0.09      | 남성 코 더 넓음            |
| mouthWidthRatio   | 0.39      | 0.03    | 0.37        | 0.03      | 남성 입 약간 더 넓음       |
| mouthCornerAngle  | -0.5      | 3.0     | 0.5         | 3.0       | 여성 입꼬리 약간 더 올라감 |
| lipFullnessRatio  | 0.09      | 0.02    | 0.11        | 0.02      | 여성 입술 더 두꺼움        |
| philtrumLength    | 0.085     | 0.015   | 0.075       | 0.013     | 남성 인중 더 긴 경향       |

> **핵심:** z-score 계산 시 `referenceData[ethnicity][gender]`로 조회.
> 같은 측정값이라도 남성 기준과 여성 기준에서 z-score가 달라진다.

#### Reference Data 구조 변경

```dart
// 기존: referenceData[Ethnicity] → Map<String, MetricReference>
// 변경: referenceData[Ethnicity][Gender] → Map<String, MetricReference>

const Map<Ethnicity, Map<Gender, Map<String, MetricReference>>> referenceData = {
  Ethnicity.eastAsian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.40, 0.08),
      'faceTaperRatio': MetricReference(0.85, 0.05),
      ...
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.36, 0.07),
      'faceTaperRatio': MetricReference(0.79, 0.05),
      ...
    },
  },
  ...
};
```

### 3.5 성별 가중치 차이 (Attribute Base Score)

관상학에서 동일 메트릭이라도 남녀에 따라 해석이 다르다.
아래는 **기본 공식(Section 5)의 weight를 성별로 조정**하는 delta 값이다.

```
실제 weight = base_weight + gender_delta
```

#### 성별 가중치 Delta 테이블

| Attribute          | Metric           | Base Weight | Male Delta | Female Delta | 근거                              |
| ------------------ | ---------------- | ----------- | ---------- | ------------ | --------------------------------- |
| **wealth**         | nasalWidthRatio  | 0.30        | +0.05      | -0.05        | 남성 관상에서 코=재물 더 강조     |
| **wealth**         | mouthWidthRatio  | 0.15        | -0.05      | +0.05        | 여성은 사교적 재물 획득 비중 높음 |
| **leadership**     | gonialAngle      | 0.30        | +0.05      | -0.05        | 남성 턱=리더십 전통적 강조        |
| **leadership**     | eyeCanthalTilt   | 0.25        | -0.05      | +0.05        | 여성 눈=리더십 현대적 해석        |
| **sensuality**     | lipFullnessRatio | 0.25        | -0.05      | +0.05        | 여성 입술=색기 전통적 강조        |
| **sensuality**     | eyeCanthalTilt   | 0.25        | +0.05      | -0.05        | 남성 눈꼬리=색기 더 강조          |
| **libido**         | nasalWidthRatio  | 0.20        | +0.05      | -0.05        | 남성 코=성적에너지 전통적 상징    |
| **libido**         | lipFullnessRatio | 0.25        | -0.05      | +0.05        | 여성 입술=성적에너지 전통적 상징  |
| **attractiveness** | faceTaperRatio   | 0.15        | -0.05      | +0.05        | V라인=여성 미의 기준 더 강함      |
| **attractiveness** | gonialAngle      | 0 (미포함)  | +0.05      | 0            | 남성 매력에 턱 각도 추가 기여     |

> **나머지 Attribute (intelligence, sociability, emotionality, stability, trustworthiness):**
> 성별 delta 없음. 관상학적으로 성별 차이가 유의미하지 않은 영역.

#### 구현 의사코드

```dart
double getWeight(String attributeId, String metricId, Gender gender) {
  final base = baseWeights[attributeId]![metricId] ?? 0.0;
  final delta = genderDeltas[attributeId]?[metricId];
  if (delta == null) return base;
  return base + (gender == Gender.male ? delta.male : delta.female);
}
```

### 3.6 성별 전용 Interaction Rules

기존 38개 Rule에 추가되는 성별 조건부 Rule.

```
=== 남성 전용 Rules ===

GM-R1: IF gender == male
       AND S_gonialAngle ≥ +2 AND S_eyebrowThickness ≥ +1
       THEN leadership += +2.0, attractiveness += +1.0
       // 매우 각진 턱 + 진한 눈썹 = 남성적 권위/매력

GM-R2: IF gender == male
       AND S_nasalWidthRatio ≥ +1 AND S_gonialAngle ≥ +1
       THEN wealth += +1.5
       // 남성: 넓은 코 + 각진 턱 = 사업 성공형

GM-R3: IF gender == male
       AND S_philtrumLength ≤ -1 AND S_nasalWidthRatio ≥ +1
       THEN libido += +2.0
       // 남성: 짧은 인중 + 넓은 코 = "정력가"

GM-R4: IF gender == male
       AND S_lipFullnessRatio ≥ +2
       THEN sensuality += +2.0, emotionality += +1.0
       // 남성의 두꺼운 입술 = 비범한 감각/감정 (남성에서는 드문 특성)

GM-R5: IF gender == male
       AND S_eyeCanthalTilt ≤ -1 AND S_browEyeDistance ≥ +1
       THEN trustworthiness += +1.5
       // 남성: 처진 눈 + 넓은 전택 = 온후한 인상 (남성에서 신뢰감↑)

=== 여성 전용 Rules ===

GF-R1: IF gender == female
       AND S_eyeCanthalTilt ≥ +1 AND S_lipFullnessRatio ≥ +1
       THEN sensuality += +2.0, attractiveness += +1.5
       // 올라간 눈 + 풍성한 입술 = 여성적 매력의 정수

GF-R2: IF gender == female
       AND S_faceTaperRatio ≤ -1 AND S_lipFullnessRatio ≥ +1
       THEN attractiveness += +2.0
       // 여성: V라인 + 풍성한 입술 = 현대적 미인상

GF-R3: IF gender == female
       AND S_philtrumLength ≤ -1 AND S_lipFullnessRatio ≥ 0
       THEN libido += +1.5, sensuality += +1.0
       // 여성: 짧은 인중 = 정열적 (입술과의 상호작용)

GF-R4: IF gender == female
       AND S_eyebrowThickness ≥ +1 AND S_gonialAngle ≥ +1
       THEN leadership += +2.5
       // 여성: 진한 눈썹 + 각진 턱 = 여장부상 (여성에서 드문 조합이라 가중치 ↑)

GF-R5: IF gender == female
       AND S_mouthCornerAngle ≥ +1 AND S_eyeFissureRatio ≥ +1
       THEN sociability += +2.0, attractiveness += +1.0
       // 여성: 밝은 미소 + 큰 눈 = 사교계의 꽃
```

### 3.7 연령 전용 Interaction Rules

50대 이상 전용 Rule. **보정된 z_adjusted 기반**으로 평가.

```
=== 50대 이상 공통 Rules ===

AG-R1: IF age == over50
       AND S_adjusted_mouthCornerAngle ≥ +1
       THEN stability += +2.0, attractiveness += +1.5
       // 노화에도 올라간 입꼬리 유지 = 타고난 낙천성 (보정 후에도 높으면 진짜)

AG-R2: IF age == over50
       AND S_adjusted_browEyeDistance ≥ +1 AND S_adjusted_lipFullnessRatio ≥ 0
       THEN attractiveness += +1.5
       // 노화에도 유지되는 전택과 입술 = 노년 미 (나이 들어도 품위)

AG-R3: IF age == over50
       AND S_adjusted_philtrumLength ≤ -1
       THEN libido += +1.5, sensuality += +1.0
       // 보정 후에도 짧은 인중 = 타고난 성적 에너지 (나이와 무관한 체질)

AG-R4: IF age == over50
       AND S_adjusted_lipFullnessRatio ≥ +1
       THEN emotionality += +1.5, sensuality += +1.0
       // 보정 후에도 풍성한 입술 = 타고난 감성/관능 (구조적 특성)

AG-R5: IF age == over50
       AND S_adjusted_mouthCornerAngle ≤ -1 AND S_adjusted_browEyeDistance ≤ -1
       THEN stability += -1.5
       // 보정 후에도 처진 인상 = 구조적 불안정성 (노화 탓이 아닌 본래 특성)
```

### 3.8 전체 처리 흐름 (성별/연령 포함)

```
INPUT: landmarks[468], ethnicity, gender, ageGroup

STEP 1: Compute 17 raw metrics
  metrics = FaceMetrics(landmarks).computeAll()

STEP 2: Z-score with gender-specific reference
  for each metric:
    ref = referenceData[ethnicity][gender][metric.id]
    z_raw = (measured - ref.mean) / ref.sd

STEP 3: Age adjustment (over50 only)
  for each age-affected metric:
    z_adjusted = adjustForAge(metric.id, z_raw, gender, ageGroup)
  for non-affected metrics:
    z_adjusted = z_raw

STEP 4: Metric Score (z_adjusted → S)
  S = convertToScore(z_adjusted, metric.type)  // ratio/angle/shape

STEP 5: Attribute Base Score (gender-weighted)
  for each attribute:
    base = Σ(getWeight(attr, metric, gender) × polarity × S[metric])

STEP 6: Interaction Rules (common + gender-specific + age-specific)
  bonus = 0
  for each rule in commonRules:
    if rule.condition(S) → bonus += rule.value
  for each rule in genderRules[gender]:
    if rule.condition(S) → bonus += rule.value
  if ageGroup == over50:
    for each rule in ageRules:
      if rule.condition(S_adjusted) → bonus += rule.value
  raw_score = base + bonus

STEP 7: Normalize (0~10)
  normalized = 10 / (1 + exp(-0.5 × raw_score))

STEP 8: Archetype (gender-aware labels)
  primary = maxAttribute(normalized)
  secondary = secondMaxAttribute(normalized)
  special = checkSpecialArchetypes(normalized)

STEP 9: Package result
  return FaceReadingReport(
    gender, ageGroup, ethnicity,
    metrics, scores, archetype,
    rulesTriggered
  )
```

### 3.9 Variations 업데이트 (성별/연령 포함)

```
기존: 인종(6) × Metric Score 조합
추가: 성별(2) × 연령대(2)

17 Metrics 조합:
  Ratio(11): 7^11 = 1,977,326,743
  Angle(3): 5^3 = 125
  Shape(2): 3^2 = 9
  = 22,244,925,859,375

전체 Variations:
  인종(6) × 성별(2) × 연령(2) × Metric조합 = 24 × 22,244,925,859,375
  = 533,878,220,625,000 (~534조)
```

---

## 4. Z-Score → Metric Score 변환

### 4.1 Ratio 계열 (7단계) — #1,2,3,4,5,7,8,12,13,14,16,17

비율 메트릭은 연속적인 크기 스펙트럼이므로 7단계로 세분화한다.

```
z ≥ +2.0  → S = +3  (매우 큼)
+1.0 ~ +2.0 → S = +2  (큼)
+0.5 ~ +1.0 → S = +1  (약간 큼)
-0.5 ~ +0.5 → S =  0  (평균)
-1.0 ~ -0.5 → S = -1  (약간 작음)
-2.0 ~ -1.0 → S = -2  (작음)
z ≤ -2.0  → S = -3  (매우 작음)
```

### 4.2 Angle 계열 (5단계) — #6,9,16

각도 메트릭은 방향성이 핵심이므로 5단계로 분류한다.

```
z ≥ +1.5  → S = +2  (강한 positive)
+0.5 ~ +1.5 → S = +1  (약한 positive)
-0.5 ~ +0.5 → S =  0  (중립)
-1.5 ~ -0.5 → S = -1  (약한 negative)
z ≤ -1.5  → S = -2  (강한 negative)
```

| Metric           | S > 0              | S = 0 | S < 0              |
| ---------------- | ------------------ | ----- | ------------------ |
| gonialAngle      | 각진 턱 (sharp)    | 보통  | 둥근 턱 (wide)     |
| eyeCanthalTilt   | 올라간 눈 (upturn) | 수평  | 처진 눈 (downturn) |
| mouthCornerAngle | 올라간 입꼬리 (up) | 수평  | 처진 입꼬리 (down) |

### 4.3 Shape 계열 (3단계) — #10,11

형태 메트릭은 "발달/보통/미발달"의 단순 구조가 적합하다.

```
|z| ≥ 1.0  → S = sign(z) × 2  (발달 또는 미발달)
0.3 ≤ |z| < 1.0 → S = sign(z) × 1  (약간)
|z| < 0.3  → S = 0            (보통)
```

---

## 5. 10 Attributes 정의

| #   | ID              | 한글명 | 영문            | 성격                         |
| --- | --------------- | ------ | --------------- | ---------------------------- |
| A1  | wealth          | 재물운 | Wealth Fortune  | 코 중심, 재물 축적/소비 성향 |
| A2  | leadership      | 리더십 | Leadership      | 턱/눈 중심, 결단력/권위      |
| A3  | intelligence    | 통찰력 | Intelligence    | 눈 중심, 분석력/직관         |
| A4  | sociability     | 사회성 | Sociability     | 입 중심, 대인관계/언변       |
| A5  | emotionality    | 감정성 | Emotionality    | 입술/눈썹 중심, 감정 표현    |
| A6  | stability       | 안정성 | Stability       | 전체 균형, 성격 안정         |
| A7  | sensuality      | 바람기 | Sensuality      | 입술/눈/인중, 관능적 매력    |
| A8  | trustworthiness | 신뢰성 | Trustworthiness | 눈썹-눈/입꼬리/눈썹, 정직함  |
| A9  | attractiveness  | 매력도 | Attractiveness  | 전체 조합, 종합적 인상       |
| A10 | libido          | 관능도 | Sexual Energy   | 인중/입술/코, 생식 에너지    |

---

## 6. Base Score 공식 (가중합)

각 Attribute의 Base Score = Sigma(weight × polarity × S_metric)

**polarity**: +1 = 높을수록 기여, -1 = 낮을수록 기여

### A1. 재물운 (Wealth)

```
wealth_base =
    0.45 × (+1) × S_nasalWidthRatio        // 넓은 코 = 재물 유입
  + 0.25 × (+1) × S_nasalHeightRatio         // 긴 코 = 재백궁 규모
  + 0.20 × (+1) × S_mouthWidthRatio         // 넓은 입 = 사업 수완
  + 0.10 × (+1) × S_gonialAngle             // 각진 턱 = 실행력
```

**관상학 근거:** 코는 재백궁(財帛宮)으로, 코의 크기와 형태가 재물운의 핵심 지표. 코 길이(nasalHeightRatio)는 얼굴 높이 대비 코의 규모를 측정하여 재백궁의 실질적 크기를 반영한다.

### A2. 리더십 (Leadership)

```
leadership_base =
    0.30 × (+1) × S_gonialAngle             // 각진 턱 = 권위/결단
  + 0.25 × (+1) × S_eyeCanthalTilt          // 올라간 눈 = 지배력
  + 0.15 × (+1) × S_eyebrowThickness        // 진한 눈썹 = 강한 의지
  + 0.15 × (+1) × S_faceTaperRatio          // 역삼각형 = 날카로운 판단
  + 0.15 × (+1) × S_browEyeDistance         // 눈썹-눈 거리 = 깊은 사고
```

**관상학 근거:** 턱(지각)은 실행력과 의지의 상징. 눈꼬리 각도는 사회적 지배/복종 성향을 결정하는 핵심 요소.

### A3. 지능/통찰 (Intelligence)

```
intelligence_base =
    0.35 × (+1) × S_eyeFissureRatio         // 긴 눈 = 관찰력
  + 0.30 × (+1) × S_browEyeDistance         // 넓은 전택 = 깊은 사고
  + 0.20 × (-1) × S_intercanthalRatio       // 좁은 눈 사이 = 집중력
  + 0.15 × (+1) × S_faceAspectRatio         // 긴 얼굴 = 분석적 사고
```

**관상학 근거:** 눈(감찰관)은 지혜의 창. 전택(눈썹-눈 사이)이 넓으면 사고가 깊고, 눈 사이가 좁으면 집중력이 강하다.

### A4. 사회성 (Sociability)

```
sociability_base =
    0.30 × (+1) × S_mouthWidthRatio         // 넓은 입 = 언변/교류
  + 0.30 × (+1) × S_mouthCornerAngle        // 올라간 입꼬리 = 친화력
  + 0.15 × (+1) × S_intercanthalRatio       // 넓은 눈 사이 = 개방적 성향
  + 0.15 × (+1) × S_lipFullnessRatio        // 두꺼운 입술 = 표현력
  + 0.10 × (+1) × S_eyeFissureRatio         // 긴 눈 = 소통 능력
```

**관상학 근거:** 입(출납관)은 대인관계의 핵심. 입꼬리는 낙관/비관을 직접적으로 보여주며, 입이 넓으면 사회적 활동 반경이 넓다.

### A5. 감정성 (Emotionality)

```
emotionality_base =
    0.30 × (+1) × S_lipFullnessRatio        // 두꺼운 입술 = 감정 풍부
  + 0.20 × (-1) × S_eyebrowThickness        // 얇은 눈썹 = 감정적 (역)
  + 0.20 × (+1) × S_mouthCornerAngle        // 올라간 입꼬리 = 감정 표현
  + 0.15 × (-1) × S_browEyeDistance         // 좁은 전택 = 즉각적 반응 (역)
  + 0.15 × (+1) × S_philtrumLength          // 긴 인중 = 감정 깊이
```

**관상학 근거:** 입술은 감정의 직접적 표현 기관. 얇은 눈썹은 세밀한 감정 감지를 의미하며, 전택이 좁으면 감정 반응이 빠르다.

### A6. 안정성 (Stability)

```
stability_base =
    0.35 × (+1) × S_browEyeDistance         // 넓은 전택 = 인내/침착
  + 0.25 × (+1) × S_eyebrowThickness        // 진한 눈썹 = 강한 의지
  + 0.20 × proximity × S_faceAspectRatio    // 평균에 가까울수록 안정 (특수)
  + 0.20 × (+1) × S_gonialAngle             // 각진 턱 = 흔들리지 않음
```

> **proximity 함수:** `proximity(S) = 2 - |S|` (S=0일때 최대 2, |S|=3일때 최소 -1)
> 얼굴 종횡비가 극단적이면 안정성 감소, 평균에 가까우면 증가.

**관상학 근거:** 안정성은 단일 특성보다 전체 균형이 중요. 전택 넓이는 인내심을 나타내며, 진한 눈썹과 각진 턱은 의지력과 흔들리지 않는 성품을 의미한다.

### A7. 바람기 (Sensuality)

```
sensuality_base =
    0.25 × (+1) × S_lipFullnessRatio        // 두꺼운 입술 = 관능미
  + 0.25 × (+1) × S_eyeCanthalTilt          // 올라간 눈꼬리 = 요염함
  + 0.20 × (+1) × S_mouthCornerAngle        // 올라간 입꼬리 = 유혹적 미소
  + 0.15 × (-1) × S_philtrumLength          // 짧은 인중 = 정열적 (역)
  + 0.15 × (+1) × S_eyeFissureRatio         // 긴 눈 = 매혹적 눈매
```

**관상학 근거:** 도화살(桃花煞) 관상. 입술의 풍만함과 눈꼬리의 각도가 색기의 양대 축. 인중이 짧으면 정열적이고 충동적인 성향이 강하다. 관상에서 "도화안(桃花眼)"은 올라간 눈꼬리 + 긴 눈의 조합이다.

### A8. 신뢰성 (Trustworthiness)

```
trustworthiness_base =
    0.35 × (+1) × S_browEyeDistance         // 넓은 전택 = 침착/신중
  + 0.25 × (+1) × S_mouthCornerAngle        // 올라간 입꼬리 = 밝은 인상
  + 0.20 × (+1) × S_eyebrowThickness        // 진한 눈썹 = 신의
  + 0.20 × proximity × S_intercanthalRatio  // 평균 눈 사이 = 균형잡힌 시선
```

> 눈 사이 거리도 proximity 적용: 너무 넓으면 산만, 너무 좁으면 의심을 사기 쉬움.

**관상학 근거:** 전택(눈썹-눈)이 넓으면 감정을 쉽게 드러내지 않아 신뢰감을 준다. 진한 눈썹은 신의를, 올라간 입꼬리는 밝은 인상을 나타낸다.

### A9. 매력 (Attractiveness)

```
attractiveness_base =
    0.20 × (+1) × S_mouthCornerAngle        // 밝은 인상
  + 0.20 × (+1) × S_eyeCanthalTilt          // 매력적 눈매
  + 0.15 × proximity × S_faceAspectRatio    // 황금비에 가까운 얼굴
  + 0.15 × (+1) × S_lipFullnessRatio        // 풍성한 입술
  + 0.15 × (+1) × S_faceTaperRatio          // V라인
  + 0.15 × (+1) × S_eyeFissureRatio         // 또렷한 눈
```

> **참고:** weight 합이 1.00이며, faceTaperRatio는 값이 작을수록(=역삼각형) V라인이므로, 실제 구현에서 faceTaperRatio의 z-score 방향을 확인할 것. 만약 작은 값이 V라인이면 polarity를 -1로 조정.

**관상학 근거:** 매력은 단일 요소가 아닌 전체 조화. 현대 미학 연구에서도 얼굴 비율이 평균에 가깝고, 눈꼬리가 약간 올라가며, 입꼬리가 올라간 얼굴이 매력적으로 평가된다.

### A10. 성적 욕구 (Libido)

```
libido_base =
    0.25 × (-1) × S_philtrumLength          // 짧은 인중 = 강한 생식력 (역)
  + 0.20 × (+1) × S_lipFullnessRatio        // 두꺼운 입술 = 욕구 표현
  + 0.20 × (+1) × S_nasalWidthRatio         // 넓은 코 = 성적 에너지
  + 0.25 × (+1) × S_nasalHeightRatio         // 긴 코 = 성적 에너지 상징
  + 0.10 × (+1) × S_eyeCanthalTilt          // 올라간 눈꼬리 = 정열
```

**관상학 근거:** 인중(人中)은 전통 관상학에서 생식 에너지의 직접적 지표. 짧고 깊은 인중은 강한 성적 에너지를 의미. 코는 남성의 경우 성기를 상징하며, 넓고 긴 코는 왕성한 성 에너지로 해석된다. 코 길이(nasalHeightRatio)는 얼굴 높이 대비 코의 실질적 크기를 반영하여 성적 에너지의 물리적 기반을 측정한다. 입술은 감각적 욕구의 표현.

---

## 7. Interaction Rules (조합 규칙)

단일 메트릭보다 **메트릭 간 조합**이 관상학에서 핵심이다.
각 Rule은 조건이 충족되면 해당 Attribute에 보너스(+) 또는 페널티(-)를 적용한다.

### 7.1 재물운 (Wealth) Rules

```
W-R5: IF S_mouthWidthRatio ≥ +1 AND S_nasalWidth ≥ +1
      THEN wealth += +1.0
      // 넓은 입 + 넓은 코 = 사업으로 재물 획득
```

### 7.2 리더십 (Leadership) Rules

```
L-R1: IF S_gonialAngle ≥ +1 AND S_eyeCanthalTilt ≥ +1
      THEN leadership += +3.0
      // 각진 턱 + 올라간 눈 = "제왕상"

L-R2: IF S_gonialAngle ≥ +1 AND S_eyebrowThickness ≥ +1
      THEN leadership += +2.0
      // 강한 턱 + 진한 눈썹 = 위엄

L-R3: IF S_browEyeDistance ≥ +1 AND S_gonialAngle ≥ 0
      THEN leadership += +1.5
      // 넓은 전택 + 단단한 턱 = 심사숙고하는 리더

L-R4: IF S_eyeCanthalTilt ≤ -1 AND S_gonialAngle ≤ -1
      THEN leadership += -2.0
      // 처진 눈 + 둥근 턱 = 유약한 인상

L-R5: IF S_faceTaperRatio ≤ -1 AND S_eyeCanthalTilt ≥ +1
      THEN leadership += +1.5
      // 역삼각 + 올라간 눈 = 날카로운 리더
```

### 7.3 지능/통찰 (Intelligence) Rules

```
I-R1: IF S_eyeFissureRatio ≥ +1 AND S_browEyeDistance ≥ +1
      THEN intelligence += +3.0
      // 긴 눈 + 넓은 전택 = "지혜의 상"

I-R2: IF S_intercanthalRatio ≤ -1 AND S_eyeFissureRatio ≥ +1
      THEN intelligence += +2.0
      // 좁은 눈 사이 + 긴 눈 = 집중적 분석 능력

I-R4: IF S_eyeFissureRatio ≤ -1 AND S_browEyeDistance ≤ -1
      THEN intelligence += -1.5
      // 짧은 눈 + 좁은 전택 = 직관보다 행동 우선

I-R5: IF S_faceAspectRatio ≥ +1 AND S_browEyeDistance ≥ +1
      THEN intelligence += +1.0
      // 긴 얼굴 + 넓은 전택 = 사색형
```

### 7.4 사회성 (Sociability) Rules

```
S-R1: IF S_mouthWidthRatio ≥ +1 AND S_mouthCornerAngle ≥ +1
      THEN sociability += +3.0
      // 넓은 입 + 올라간 입꼬리 = "카리스마 사교가"

S-R2: IF S_mouthCornerAngle ≥ +1 AND S_lipFullnessRatio ≥ +1
      THEN sociability += +2.0
      // 밝은 미소 + 풍성한 입술 = 매력적 화술

S-R3: IF S_intercanthalRatio ≥ +1 AND S_mouthWidthRatio ≥ +1
      THEN sociability += +1.5
      // 넓은 눈 사이 + 넓은 입 = 개방적 사교

S-R4: IF S_mouthCornerAngle ≤ -1 AND S_mouthWidthRatio ≤ -1
      THEN sociability += -2.0
      // 처진 입꼬리 + 좁은 입 = 내성적/비관적 인상

S-R5: IF S_mouthCornerAngle ≥ +1 AND S_eyeFissureRatio ≥ +1
      THEN sociability += +1.0
      // 밝은 표정 + 또렷한 눈 = 소통 능력
```

### 7.5 감정성 (Emotionality) Rules

```
E-R1: IF S_lipFullnessRatio ≥ +1 AND S_eyebrowThickness ≤ -1
      THEN emotionality += +3.0
      // 풍성한 입술 + 가는 눈썹 = "감성의 극치"

E-R2: IF S_lipFullnessRatio ≥ +1 AND S_mouthCornerAngle ≥ +1
      THEN emotionality += +2.0
      // 풍성한 입술 + 밝은 표정 = 감정 표현이 풍부

E-R3: IF S_browEyeDistance ≤ -1 AND S_lipFullnessRatio ≥ +1
      THEN emotionality += +2.0
      // 좁은 전택 + 풍성한 입술 = 즉각적 감정 반응

E-R4: IF S_eyebrowThickness ≥ +2 AND S_browEyeDistance ≥ +1
      THEN emotionality += -2.0
      // 진한 눈썹 + 넓은 전택 = 감정 억제

E-R5: IF S_philtrumLength ≥ +1 AND S_lipFullnessRatio ≥ 0
      THEN emotionality += +1.0
      // 긴 인중 = 감정의 깊이
```

### 7.6 안정성 (Stability) Rules

```
ST-R2: IF S_eyebrowThickness ≥ +1 AND S_gonialAngle ≥ +1
       THEN stability += +2.0
       // 진한 눈썹 + 각진 턱 = 흔들리지 않음

ST-R3: IF |S_faceAspectRatio| ≤ 1 AND |S_faceTaperRatio| ≤ 1
       THEN stability += +1.5
       // 얼굴 비율 균형 = 성격 안정

ST-R4: IF S_eyeCanthalTilt ≤ -1 AND S_mouthCornerAngle ≤ -1
       THEN stability += -2.0
       // 처진 눈 + 처진 입 = 불안정한 감정

```

### 7.7 색기/바람기 (Sensuality) Rules

```
SN-R1: IF S_eyeCanthalTilt ≥ +1 AND S_lipFullnessRatio ≥ +1
       THEN sensuality += +3.0
       // 올라간 눈꼬리 + 풍성한 입술 = "도화상(桃花相)"

SN-R2: IF S_eyeCanthalTilt ≥ +1 AND S_eyeFissureRatio ≥ +1
       THEN sensuality += +2.0
       // 올라간 긴 눈 = "도화안(桃花眼)"

SN-R3: IF S_mouthCornerAngle ≥ +1 AND S_lipFullnessRatio ≥ +1
       THEN sensuality += +2.0
       // 관능적 미소 + 풍성한 입술 = 유혹적

SN-R4: IF S_philtrumLength ≤ -1 AND S_lipFullnessRatio ≥ +1
       THEN sensuality += +2.0
       // 짧은 인중 + 풍성한 입술 = 정열적

SN-R5: IF S_eyeCanthalTilt ≤ -1 AND S_lipFullnessRatio ≤ -1
       THEN sensuality += -2.0
       // 처진 눈 + 얇은 입술 = 색기 부족
```

### 7.8 신뢰성 (Trustworthiness) Rules

```
T-R2: IF S_browEyeDistance ≥ +1 AND S_eyebrowThickness ≥ +1
      THEN trustworthiness += +2.0
      // 침착함 + 의지력 = 믿음직함

T-R4: IF S_intercanthalRatio ≥ +2 AND S_browEyeDistance ≤ -1
      THEN trustworthiness += -2.0
      // 너무 넓은 눈 사이 + 좁은 전택 = 산만/충동적

```

### 7.9 매력 (Attractiveness) Rules

```
AT-R1: IF S_mouthCornerAngle ≥ +1 AND S_eyeCanthalTilt ≥ +1 AND S_lipFullnessRatio ≥ 0
       THEN attractiveness += +3.0
       // 밝은 인상 + 매력적 눈매 + 적당한 입술 = "미인상"

AT-R2: IF |S_faceAspectRatio| ≤ 1 AND S_faceTaperRatio ≤ 0
       THEN attractiveness += +2.0
       // 균형잡힌 비율 + V라인 = 현대적 미인

AT-R3: IF S_eyeFissureRatio ≥ +1 AND S_eyeCanthalTilt ≥ 0
       THEN attractiveness += +1.5
       // 또렷한 큰 눈 = 눈매 매력

AT-R4: IF S_mouthCornerAngle ≤ -1 AND S_eyeCanthalTilt ≤ -1
       THEN attractiveness += -2.0
       // 처진 인상 = 매력 감소

```

### 7.10 성적 욕구 (Libido) Rules

```
LB-R1: IF S_philtrumLength ≤ -1 AND S_lipFullnessRatio ≥ +1
       THEN libido += +3.0
       // 짧은 인중 + 풍성한 입술 = "정력의 상"

LB-R3: IF S_philtrumLength ≤ -1 AND S_nasalWidthRatio ≥ +1
       THEN libido += +2.0
       // 짧은 인중 + 넓은 코 = 원초적 에너지

LB-R4: IF S_philtrumLength ≥ +2 AND S_lipFullnessRatio ≤ -1
       THEN libido += -2.0
       // 긴 인중 + 얇은 입술 = 성적 에너지 부족

LB-R5: IF S_eyeCanthalTilt ≥ +1 AND S_lipFullnessRatio ≥ +1
       THEN libido += +1.5
       // 올라간 눈 + 풍성한 입술 = 적극적 욕구
```

---

## 7.11 전체 Rule 일람표 (53개)

### Common Rules (38개)

| #   | Rule ID | Attribute       | 조건                                                           | 효과 | 해석                                    |
| --- | ------- | --------------- | -------------------------------------------------------------- | ---- | --------------------------------------- |
| 1   | W-R5    | wealth          | mouthWidthRatio ≥+1 AND nasalWidth ≥+1                         | +1.0 | 넓은 입+넓은 코 = 사업 재물             |
| 6   | L-R1    | leadership      | gonialAngle ≥+1 AND eyeCanthalTilt ≥+1                         | +3.0 | 각진 턱+올라간 눈 = 제왕상              |
| 7   | L-R2    | leadership      | gonialAngle ≥+1 AND eyebrowThickness ≥+1                       | +2.0 | 강한 턱+진한 눈썹 = 위엄                |
| 8   | L-R3    | leadership      | browEyeDistance ≥+1 AND gonialAngle ≥0                         | +1.5 | 넓은 전택+단단한 턱 = 심사숙고 리더     |
| 9   | L-R4    | leadership      | eyeCanthalTilt ≤-1 AND gonialAngle ≤-1                         | -2.0 | 처진 눈+둥근 턱 = 유약한 인상           |
| 10  | L-R5    | leadership      | faceTaperRatio ≤-1 AND eyeCanthalTilt ≥+1                      | +1.5 | 역삼각+올라간 눈 = 날카로운 리더        |
| 11  | I-R1    | intelligence    | eyeFissureRatio ≥+1 AND browEyeDistance ≥+1                    | +3.0 | 긴 눈+넓은 전택 = 지혜의 상             |
| 12  | I-R2    | intelligence    | intercanthalRatio ≤-1 AND eyeFissureRatio ≥+1                  | +2.0 | 좁은 눈 사이+긴 눈 = 집중 분석력        |
| 14  | I-R4    | intelligence    | eyeFissureRatio ≤-1 AND browEyeDistance ≤-1                    | -1.5 | 짧은 눈+좁은 전택 = 행동 우선           |
| 15  | I-R5    | intelligence    | faceAspectRatio ≥+1 AND browEyeDistance ≥+1                    | +1.0 | 긴 얼굴+넓은 전택 = 사색형              |
| 16  | S-R1    | sociability     | mouthWidthRatio ≥+1 AND mouthCornerAngle ≥+1                   | +3.0 | 넓은 입+올라간 입꼬리 = 카리스마 사교가 |
| 17  | S-R2    | sociability     | mouthCornerAngle ≥+1 AND lipFullnessRatio ≥+1                  | +2.0 | 밝은 미소+풍성한 입술 = 매력적 화술     |
| 18  | S-R3    | sociability     | intercanthalRatio ≥+1 AND mouthWidthRatio ≥+1                  | +1.5 | 넓은 눈 사이+넓은 입 = 개방적 사교      |
| 19  | S-R4    | sociability     | mouthCornerAngle ≤-1 AND mouthWidthRatio ≤-1                   | -2.0 | 처진 입꼬리+좁은 입 = 내성적/비관       |
| 20  | S-R5    | sociability     | mouthCornerAngle ≥+1 AND eyeFissureRatio ≥+1                   | +1.0 | 밝은 표정+또렷한 눈 = 소통 능력         |
| 21  | E-R1    | emotionality    | lipFullnessRatio ≥+1 AND eyebrowThickness ≤-1                  | +3.0 | 풍성한 입술+가는 눈썹 = 감성의 극치     |
| 22  | E-R2    | emotionality    | lipFullnessRatio ≥+1 AND mouthCornerAngle ≥+1                  | +2.0 | 풍성한 입술+밝은 표정 = 감정 풍부       |
| 23  | E-R3    | emotionality    | browEyeDistance ≤-1 AND lipFullnessRatio ≥+1                   | +2.0 | 좁은 전택+풍성한 입술 = 즉각 감정 반응  |
| 24  | E-R4    | emotionality    | eyebrowThickness ≥+2 AND browEyeDistance ≥+1                   | -2.0 | 진한 눈썹+넓은 전택 = 감정 억제         |
| 25  | E-R5    | emotionality    | philtrumLength ≥+1 AND lipFullnessRatio ≥0                     | +1.0 | 긴 인중 = 감정의 깊이                   |
| 27  | ST-R2   | stability       | eyebrowThickness ≥+1 AND gonialAngle ≥+1                       | +2.0 | 진한 눈썹+각진 턱 = 흔들리지 않음       |
| 28  | ST-R3   | stability       | \|faceAspectRatio\| ≤1 AND \|faceTaperRatio\| ≤1               | +1.5 | 얼굴 비율 균형 = 성격 안정              |
| 29  | ST-R4   | stability       | eyeCanthalTilt ≤-1 AND mouthCornerAngle ≤-1                    | -2.0 | 처진 눈+처진 입 = 불안정 감정           |
| 31  | SN-R1   | sensuality      | eyeCanthalTilt ≥+1 AND lipFullnessRatio ≥+1                    | +3.0 | 올라간 눈+풍성한 입술 = 도화상          |
| 32  | SN-R2   | sensuality      | eyeCanthalTilt ≥+1 AND eyeFissureRatio ≥+1                     | +2.0 | 올라간 긴 눈 = 도화안                   |
| 33  | SN-R3   | sensuality      | mouthCornerAngle ≥+1 AND lipFullnessRatio ≥+1                  | +2.0 | 관능적 미소+풍성한 입술 = 유혹적        |
| 34  | SN-R4   | sensuality      | philtrumLength ≤-1 AND lipFullnessRatio ≥+1                    | +2.0 | 짧은 인중+풍성한 입술 = 정열적          |
| 35  | SN-R5   | sensuality      | eyeCanthalTilt ≤-1 AND lipFullnessRatio ≤-1                    | -2.0 | 처진 눈+얇은 입술 = 색기 부족           |
| 37  | T-R2    | trustworthiness | browEyeDistance ≥+1 AND eyebrowThickness ≥+1                   | +2.0 | 침착+의지력 = 믿음직                    |
| 39  | T-R4    | trustworthiness | intercanthalRatio ≥+2 AND browEyeDistance ≤-1                  | -2.0 | 넓은 눈 사이+좁은 전택 = 산만/충동      |
| 41  | AT-R1   | attractiveness  | mouthCornerAngle ≥+1 AND eyeCanthalTilt ≥+1 AND lipFullness ≥0 | +3.0 | 밝은 인상+매력 눈매 = 미인상            |
| 42  | AT-R2   | attractiveness  | \|faceAspectRatio\| ≤1 AND faceTaperRatio ≤0                   | +2.0 | 균형 비율+V라인 = 현대 미인             |
| 43  | AT-R3   | attractiveness  | eyeFissureRatio ≥+1 AND eyeCanthalTilt ≥0                      | +1.5 | 또렷한 큰 눈 = 눈매 매력                |
| 44  | AT-R4   | attractiveness  | mouthCornerAngle ≤-1 AND eyeCanthalTilt ≤-1                    | -2.0 | 처진 인상 = 매력 감소                   |
| 46  | LB-R1   | libido          | philtrumLength ≤-1 AND lipFullnessRatio ≥+1                    | +3.0 | 짧은 인중+풍성한 입술 = 정력의 상       |
| 47  | LB-R3   | libido          | philtrumLength ≤-1 AND nasalWidthRatio ≥+1                     | +2.0 | 짧은 인중+넓은 코 = 원초적 에너지       |
| 49  | LB-R4   | libido          | philtrumLength ≥+2 AND lipFullnessRatio ≤-1                    | -2.0 | 긴 인중+얇은 입술 = 성적 에너지 부족    |
| 50  | LB-R5   | libido          | eyeCanthalTilt ≥+1 AND lipFullnessRatio ≥+1                    | +1.5 | 올라간 눈+풍성한 입술 = 적극적 욕구     |

### Gender Rules (10개)

| #   | Rule ID | 성별 | Attribute(s)                       | 조건                                       | 효과 | 해석                                     |
| --- | ------- | ---- | ---------------------------------- | ------------------------------------------ | ---- | ---------------------------------------- |
| 51  | GM-R1   | M    | leadership +2, attractiveness +1   | gonialAngle ≥+2 AND eyebrowThickness ≥+1   | +3.0 | 각진 턱+진한 눈썹 = 남성적 권위/매력     |
| 52  | GM-R2   | M    | wealth                             | nasalWidth ≥+1 AND gonialAngle ≥+1         | +1.5 | 넓은 코+각진 턱 = 사업 성공형            |
| 53  | GM-R3   | M    | libido                             | philtrumLength ≤-1 AND nasalWidth ≥+1      | +2.0 | 짧은 인중+넓은 코 = 정력가               |
| 54  | GM-R4   | M    | sensuality +2, emotionality +1     | lipFullnessRatio ≥+2                       | +3.0 | 남성의 두꺼운 입술 = 비범한 감각         |
| 55  | GM-R5   | M    | trustworthiness                    | eyeCanthalTilt ≤-1 AND browEyeDistance ≥+1 | +1.5 | 처진 눈+넓은 전택 = 온후한 인상          |
| 56  | GF-R1   | F    | sensuality +2, attractiveness +1.5 | eyeCanthalTilt ≥+1 AND lipFullness ≥+1     | +3.5 | 올라간 눈+풍성한 입술 = 여성적 매력 정수 |
| 57  | GF-R2   | F    | attractiveness                     | faceTaperRatio ≤-1 AND lipFullness ≥+1     | +2.0 | V라인+풍성한 입술 = 현대 미인상          |
| 58  | GF-R3   | F    | libido +1.5, sensuality +1         | philtrumLength ≤-1 AND lipFullness ≥0      | +2.5 | 짧은 인중 = 여성적 정열                  |
| 59  | GF-R4   | F    | leadership                         | eyebrowThickness ≥+1 AND gonialAngle ≥+1   | +2.5 | 진한 눈썹+각진 턱 = 여장부상             |
| 60  | GF-R5   | F    | sociability +2, attractiveness +1  | mouthCornerAngle ≥+1 AND eyeFissure ≥+1    | +3.0 | 밝은 미소+큰 눈 = 사교계의 꽃            |

### Age Rules (5개, 50대 이상 전용)

| #   | Rule ID | Attribute(s)                      | 조건 (z_adjusted 기반)                               | 효과 | 해석                                   |
| --- | ------- | --------------------------------- | ---------------------------------------------------- | ---- | -------------------------------------- |
| 61  | AG-R1   | stability +2, attractiveness +1.5 | mouthCornerAngle_adj ≥+1                             | +3.5 | 노화에도 올라간 입꼬리 = 타고난 낙천성 |
| 62  | AG-R2   | attractiveness                    | browEyeDistance_adj ≥+1 AND lipFullness_adj ≥0       | +1.5 | 유지된 전택+입술 = 노년의 품위         |
| 63  | AG-R3   | libido +1.5, sensuality +1        | philtrumLength_adj ≤-1                               | +2.5 | 보정 후에도 짧은 인중 = 타고난 에너지  |
| 64  | AG-R4   | emotionality +1.5, sensuality +1  | lipFullness_adj ≥+1                                  | +2.5 | 보정 후에도 풍성한 입술 = 구조적 감성  |
| 65  | AG-R5   | stability                         | mouthCornerAngle_adj ≤-1 AND browEyeDistance_adj ≤-1 | -1.5 | 보정 후에도 처진 인상 = 본래 불안정성  |

---

## 8. Score 정규화

### 8.1 Raw Score 범위 분석

각 Attribute의 Raw Score = Base Score + Interaction Bonus

```
Base Score 이론적 범위:
  최대: Σ(weight × 3) = 3.0 (모든 기여 메트릭이 +3일때)
  최소: Σ(weight × -3) = -3.0

Interaction Bonus 실질적 범위:
  최대: +3.0 ~ +6.0 (2~3개 Rule 동시 충족시)
  최소: -3.0 ~ -5.0

합산 Raw Score 실질적 범위: 약 -8.0 ~ +9.0
```

### 8.2 정규화 공식 (Raw → 0~10)

Sigmoid 기반 정규화로 극단값을 부드럽게 처리:

```
normalized = 10 / (1 + exp(-0.5 × raw_score))
```

| Raw Score | Normalized (0~10) |
| --------- | ----------------- |
| -8.0      | 0.2               |
| -4.0      | 1.2               |
| -2.0      | 2.7               |
| -1.0      | 3.8               |
| 0.0       | 5.0               |
| +1.0      | 6.2               |
| +2.0      | 7.3               |
| +4.0      | 8.8               |
| +8.0      | 9.8               |

> 이 공식은 raw=0일때 정확히 5.0을 반환하며, 극단값에서도 0과 10에 수렴하되 도달하지 않아 자연스러운 분포를 만든다.

### 8.3 최종 Score 반올림

```
final_score = round(normalized × 10) / 10  // 소수 첫째자리
```

예: 7.312... → **7.3**

---

## 9. Archetype 분류

### 9.1 Primary Archetype (주 유형)

10개 Attribute 중 **최고 점수** Attribute가 Primary Archetype을 결정한다.

| 최고 Attribute  | Archetype | 한글     | 설명                           |
| --------------- | --------- | -------- | ------------------------------ |
| wealth          | 사업가형  | 사업가형 | 재물 축적과 사업 수완이 뛰어남 |
| leadership      | 리더형    | 리더형   | 결단력과 통솔력이 강함         |
| intelligence    | 학자형    | 학자형   | 분석력과 직관이 뛰어남         |
| sociability     | 외교형    | 외교형   | 대인관계와 소통 능력이 탁월    |
| emotionality    | 예술가형  | 예술가형 | 감정이 풍부하고 창의적         |
| stability       | 현자형    | 현자형   | 침착하고 안정적인 성품         |
| sensuality      | 연예인형  | 연예인형 | 관능적 매력과 카리스마 보유    |
| trustworthiness | 신의형    | 신의형   | 믿음직하고 정직한 인상         |
| attractiveness  | 미인형    | 미인형   | 종합적 외모 매력이 높음        |
| libido          | 정열형    | 정열형   | 원초적 에너지와 생명력이 강함  |

### 9.2 Secondary Archetype (부 유형)

2번째로 높은 Attribute가 Secondary Archetype을 결정한다.
최종 표현: **"리더형 (사업가 기질)"** 형태로 조합.

### 9.3 Special Archetype (특수 조합)

특정 Attribute 조합이 임계값을 넘으면 특수 Archetype을 부여한다.

```
SP-1: IF wealth ≥ 7.5 AND leadership ≥ 7.0
      → "제왕상" (帝王相)

SP-2: IF sensuality ≥ 7.5 AND attractiveness ≥ 7.5
      → "도화상" (桃花相)

SP-3: IF intelligence ≥ 7.5 AND stability ≥ 7.0
      → "군사상" (軍師相) — 책사/참모형

SP-4: IF sociability ≥ 7.5 AND attractiveness ≥ 7.0
      → "연예인상" (演藝人相)

SP-5: IF wealth ≥ 7.0 AND trustworthiness ≥ 7.0
      → "복덕상" (福德相) — 복 있는 상

SP-6: IF leadership ≥ 7.0 AND stability ≥ 7.0 AND trustworthiness ≥ 7.0
      → "대인상" (大人相) — 대인배

SP-7: IF libido ≥ 7.5 AND sensuality ≥ 7.0
      → "풍류상" (風流相) — 풍류객

SP-8: IF intelligence ≥ 7.0 AND emotionality ≥ 7.0
      → "천재상" (天才相) — 예술적 천재

SP-9: IF stability ≤ 3.0 AND emotionality ≥ 7.5
      → "광인상" (狂人相) — 미친 천재

SP-10: IF trustworthiness ≤ 3.0 AND sociability ≥ 7.0
       → "사기상" (詐欺相) — 주의 인물
```

---

## 10. 리포트 생성 아키텍처 (블록 조립 + LLM 래핑)

### 10.1 핵심 전략

```
사전 작성: Rule별 텍스트 블록 (~85개)
런타임:    발동된 Rule의 블록을 수집 → 조립 → LLM이 자연어 총평으로 래핑
```

DB에 수만 개의 결과를 저장하는 대신, **Rule 텍스트 블록 85개만 사전 작성**하면
런타임에서 무한에 가까운 variation을 조합으로 생성할 수 있다.

### 10.2 텍스트 블록 분류 및 수량

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 블록 유형              수량    내용
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Common Rule 블록       38개   각 2~3 paragraph
 Gender Rule 블록       10개   성별 특화 해석
 Age Rule 블록           5개   노화 보정 해석
 ─────────────────────────────────────────────────
 Rule 블록 소계          53개
 ─────────────────────────────────────────────────
 Archetype 인트로       20개   10 Archetype × 2 성별
 Special Archetype      10개   제왕상, 도화상 등
 연령 마감문              2개   under50 / over50
 ─────────────────────────────────────────────────
 보조 블록 소계          32개
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 총 작성량:             ~85개 블록
 (약 170~260 paragraph)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 10.3 블록 데이터 구조

```dart
class RuleTextBlock {
  final String ruleId;          // "W-R1", "GM-R2", "AG-R1" 등
  final String attribute;       // "wealth", "leadership" 등
  final String titleKo;         // "돈 벌고 돈 모으는 코"
  final String bodyKo;          // 2~3 paragraph 관상 해석 텍스트
  final double scoreImpact;     // +3.0, -2.0 등
}

class ArchetypeTextBlock {
  final String archetypeId;     // "사업가형"
  final Gender gender;          // male / female
  final String introKo;         // 오프닝 paragraph
}

class SpecialArchetypeBlock {
  final String specialId;       // "제왕상"
  final String bodyKo;          // 특수 Archetype 해석
}
```

### 10.4 블록 내용 예시

#### W-R1 (코폭 + 콧망울 동시 발달)

```
ruleId: "W-R1"
attribute: "wealth"
titleKo: "재물이 모이는 코"

bodyKo: """
코의 폭과 콧망울이 동시에 발달한 것은 관상학에서 가장 강력한 재물의 징표입니다.
넓은 콧구멍은 재물이 들어오는 입구를 상징하고, 풍성한 콧망울(준두)은 들어온
재물을 지키는 창고와 같습니다. 이른바 '재백궁(財帛宮)'이 충실한 상으로,
돈을 버는 능력과 모으는 능력을 동시에 갖춘 드문 구조입니다.

사업이나 투자에서 직감이 뛰어나며, 특히 실물 자산과 관련된 영역에서
탁월한 판단력을 보일 수 있습니다. 다만 코가 발달한 만큼 자존심도 강해,
금전 문제에서 타협을 꺼리는 경향이 있을 수 있습니다.
"""
```

#### L-R1 (각진 턱 + 올라간 눈)

```
ruleId: "L-R1"
attribute: "leadership"
titleKo: "제왕의 기운"

bodyKo: """
각진 턱과 올라간 눈꼬리의 조합은 전통 관상학에서 '제왕지상(帝王之相)'으로
불리는 대표적인 리더의 얼굴입니다. 턱의 각진 형태는 결단력과 실행력을,
올라간 눈꼬리는 상대를 압도하는 카리스마와 지배력을 나타냅니다.

이 조합을 가진 사람은 조직에서 자연스럽게 중심이 되며, 위기 상황에서
오히려 빛을 발하는 유형입니다. 명확한 판단과 빠른 실행으로 주변의 신뢰를
얻지만, 때로는 지나친 자신감이 독선으로 비칠 수 있어 경청의 자세가 필요합니다.
"""
```

#### GM-R2 (남성: 넓은 코 + 각진 턱)

```
ruleId: "GM-R2"
attribute: "wealth"
titleKo: "사업 성공의 관록"

bodyKo: """
남성에게 넓은 코와 각진 턱의 조합은 특히 사업 분야에서 성공을 암시합니다.
관상학에서 남성의 코는 '관록궁(官祿宮)'과 직결되며, 이를 뒷받침하는
단단한 턱은 사업을 끝까지 밀고 나갈 수 있는 추진력을 상징합니다.

특히 대인 관계에서 신뢰감을 주는 인상이어서, 사업 파트너십이나
팀 리딩에서 유리한 위치를 점할 수 있습니다.
"""
```

#### AG-R1 (50대+: 보정 후에도 올라간 입꼬리)

```
ruleId: "AG-R1"
attribute: "stability"
titleKo: "세월이 증명한 낙천성"

bodyKo: """
세월의 흐름에도 불구하고 입꼬리가 자연스럽게 올라가 있다는 것은,
노화에 의한 중력 효과를 이겨낼 만큼 타고난 근육 구조와 성격적 낙천성을
가지고 있다는 의미입니다. 이는 단순한 외모가 아니라 수십 년간의
삶의 태도가 만들어낸 '얼굴의 역사'입니다.

이런 분은 주변에 긍정적인 에너지를 전파하며,
나이가 들수록 오히려 주변에 사람이 모이는 유형입니다.
"""
```

### 10.5 런타임 조립 로직

```dart
FaceReadingReport generateReport(RuleEngineResult result) {

  // Step 1: 발동된 Rule들의 텍스트 블록 수집
  final blocks = <RuleTextBlock>[];
  for (final rule in result.triggeredRules) {
    blocks.add(ruleTextDB[rule.id]!);
  }

  // Step 2: Attribute별로 그룹핑 & 중요도순 정렬
  final grouped = groupBy(blocks, (b) => b.attribute);
  final sorted = grouped.entries.toList()
    ..sort((a, b) => result.attributeScore(b.key)
        .compareTo(result.attributeScore(a.key)));

  // Step 3: 상위 3~5개 Attribute의 블록만 선택 (리포트 길이 제한)
  final selectedBlocks = sorted.take(5)
    .expand((e) => e.value)
    .toList();

  // Step 4: Archetype 인트로 + 블록 + Special + 마감문 조립
  final assembled = StringBuffer();

  // 인트로
  assembled.writeln(archetypeIntros[result.primaryArchetype]![result.gender]!);

  // Rule 블록들 (Attribute별 소제목 포함)
  String? currentAttr;
  for (final block in selectedBlocks) {
    if (block.attribute != currentAttr) {
      currentAttr = block.attribute;
      assembled.writeln('\n## ${attributeNameKo[currentAttr]}');
    }
    assembled.writeln(block.bodyKo);
  }

  // Special Archetype
  if (result.specialArchetype != null) {
    assembled.writeln(specialTexts[result.specialArchetype]!);
  }

  // 연령 마감문
  assembled.writeln(ageClosings[result.ageGroup]!);

  // Step 5: LLM 래핑 (조립된 블록 → 자연스러운 총평)
  final llmInput = LLMReportRequest(
    assembledBlocks: assembled.toString(),
    scores: result.normalizedScores,
    archetype: result.archetype,
    gender: result.gender,
    ageGroup: result.ageGroup,
  );

  return callLLM(llmInput);
}
```

### 10.6 LLM 래핑 프롬프트

```
당신은 전통 동양 관상학과 현대 안면 인류학을 결합한 관상 분석가입니다.

아래의 관상 분석 블록들을 읽고, 하나의 자연스러운 종합 리포트로 래핑하세요.

[대상]
성별: {gender_ko}
연령대: {age_group_ko}
Archetype: {primary} ({secondary} 기질)
{special이 있으면: "특수상: {special}"}

[분석 블록]
{assembled_blocks}

[Attribute 점수 (내부 참고용, 텍스트에 숫자 노출 금지)]
{scores_summary}

[래핑 규칙]
1. 블록들의 핵심 내용을 보존하되, 중복을 제거하고 자연스럽게 연결
2. 관상학 전통 용어를 살리되 현대적 표현으로 풀어서 설명
3. 긍정적 특성을 먼저 배치, 주의점은 부드럽게 표현
4. Archetype을 자연스럽게 녹여 총평에 반영
5. 성별에 맞는 표현 (남성: "관록/기개", 여성: "기품/품격")
6. {50대 이상이면: "노화 보정 사실을 자연스럽게 언급 (예: '세월을 감안해도~')"}
7. 재미 요소(색기, 성적 욕구 등)는 유머러스하면서 품위있게
8. 총 800~1200자로 작성
9. 소제목 없이 하나의 흐름으로 서술
```

### 10.7 Variation 분석

```
한 사람에게 평균 발동되는 Rule: 8~15개
이 중 리포트에 포함: 상위 5 Attribute에 해당하는 ~8개

8개 Rule 선택 조합: C(53, 8) = 약 8.9억 가지 (이론)
실질적으로 구조적으로 가능한 조합: ~수천만 가지

+ Archetype 조합(10 × 9 = 90)
+ 성별(2) × 연령(2) = 4
+ LLM 래핑에 의한 표현 변주

→ 사실상 동일 리포트가 나올 확률: 거의 0%
→ 사전 작성량: 85개 블록 (약 170~260 paragraph)
```

### 10.8 이 구조의 장점

```
1. 작성량 최소: 85개 블록 작성 = 1~2일 작업
2. Variation 최대: 수천만 가지 고유 조합
3. 품질 보장:  각 블록이 전문가 수준으로 작성됨
4. LLM 비용 최소: 래핑만 수행 (생성 아닌 편집)
5. 유지보수 용이: 블록 단위로 수정/추가/삭제
6. DB 부담 제로: 사전 저장 필요 없음, 런타임 조립
7. 확장 용이: Rule 추가 = 블록 1개 추가
```

---

## 11. Reference Dataset 정의

### 11.1 인종 × 성별 17 Metrics 기준값

각 메트릭의 (mean, SD)는 **인종 × 성별**로 정의된다. (Section 3.4 참조)
아래는 동아시아인 남성 기준값이며, 여성 및 타 인종은 Section 3.4의 delta 적용.

#### 동아시아인 남성 (East Asian Male) — 기본값

| #   | Metric            | Mean  | SD    | 출처/근거                                 |
| --- | ----------------- | ----- | ----- | ----------------------------------------- |
| 1   | faceAspectRatio   | 1.40  | 0.08  | Farkas 동아시아 데이터                    |
| 2   | upperFaceRatio    | 0.33  | 0.03  | Neoclassical 3등분 기준                   |
| 3   | midFaceRatio      | 0.33  | 0.02  | Neoclassical 3등분 기준                   |
| 4   | lowerFaceRatio    | 0.34  | 0.03  | Neoclassical 3등분 기준                   |
| 5   | faceTaperRatio    | 0.85  | 0.05  | 추정: 턱폭/광대폭                         |
| 6   | gonialAngle       | 118.0 | 7.0   | 추정: 동아시아 하악각 평균 (degrees)      |
| 7   | intercanthalRatio | 0.27  | 0.02  | PMC9029890 ICD 메타분석                   |
| 8   | eyeFissureRatio   | 0.23  | 0.02  | Farkas EFL 데이터                         |
| 9   | eyeCanthalTilt    | 3.5   | 3.0   | 추정: 동아시아 평균 약간 upturn (degrees) |
| 10  | eyebrowThickness  | 0.017 | 0.004 | 추정: 눈썹 두께/얼굴높이                  |
| 11  | browEyeDistance   | 0.058 | 0.014 | 추정: 전택/얼굴높이                       |
| 12  | nasalWidthRatio   | 1.08  | 0.10  | Farkas 콧볼/ICD 비율                      |
| 13  | nasalHeightRatio  | 0.30  | 0.02  | Farkas: 코 길이/얼굴 높이                 |
| 14  | mouthWidthRatio   | 0.39  | 0.03  | Farkas 입폭/얼굴폭                        |
| 15  | mouthCornerAngle  | -0.5  | 3.0   | 중립 기준 (degrees)                       |
| 16  | lipFullnessRatio  | 0.09  | 0.02  | Farkas 입술높이/얼굴높이                  |
| 17  | philtrumLength    | 0.085 | 0.015 | 추정: 인중/얼굴높이                       |

> **"추정" 표기된 항목은 문헌 데이터 부재로 기존 메트릭에서 파생 추정한 값.**
> 실제 서비스 전 N=100+ 수집 데이터로 calibration 필요.

### 11.2 6개 인종별 차이 요약

| Metric            | East Asian | Caucasian | African | SE Asian | Hispanic | Middle Eastern |
| ----------------- | ---------- | --------- | ------- | -------- | -------- | -------------- |
| faceAspectRatio   | 1.38       | 1.35      | 1.32    | 1.36     | 1.35     | 1.36           |
| upperFaceRatio    | 0.33       | 0.33      | 0.32    | 0.33     | 0.33     | 0.33           |
| midFaceRatio      | 0.33       | 0.34      | 0.32    | 0.33     | 0.33     | 0.34           |
| lowerFaceRatio    | 0.34       | 0.33      | 0.36    | 0.34     | 0.34     | 0.33           |
| faceTaperRatio    | 0.82       | 0.80      | 0.85    | 0.83     | 0.81     | 0.80           |
| gonialAngle       | 120        | 125       | 118     | 121      | 123      | 124            |
| intercanthalRatio | 0.27       | 0.23      | 0.29    | 0.25     | 0.24     | 0.23           |
| eyeFissureRatio   | 0.24       | 0.23      | 0.24    | 0.24     | 0.23     | 0.24           |
| eyeCanthalTilt    | 4.0        | 2.0       | 2.0     | 3.5      | 2.5      | 2.5            |
| eyebrowThickness  | 0.015      | 0.016     | 0.017   | 0.015    | 0.016    | 0.017          |
| browEyeDistance   | 0.060      | 0.065     | 0.058   | 0.062    | 0.063    | 0.064          |
| nasalWidthRatio   | 1.05       | 0.95      | 1.20    | 1.10     | 1.00     | 1.00           |
| mouthWidthRatio   | 0.38       | 0.37      | 0.40    | 0.39     | 0.38     | 0.37           |
| mouthCornerAngle  | 0.0        | 0.0       | 0.0     | 0.0      | 0.0      | 0.0            |
| lipFullnessRatio  | 0.10       | 0.09      | 0.12    | 0.11     | 0.10     | 0.09           |
| philtrumLength    | 0.080      | 0.085     | 0.075   | 0.078    | 0.082    | 0.083          |

### 11.3 Calibration 필요 데이터

서비스 출시 전 수집해야 할 데이터:

```
1. 최소 표본:
   - 인종별 100명 이상 (총 600명+)
   - 남녀 50:50

2. 수집 항목:
   - 468 랜드마크 좌표 (raw)
   - 17 metrics 계산값
   - 자가 평가 설문 (10 Attributes 자가 진단, 1~10)
   - 제3자 평가 (외모 매력, 신뢰성 등)

3. 보정 방식:
   - 수집 데이터로 mean/SD 업데이트
   - 자가 평가와의 상관 분석 → weight 조정
   - A/B 테스트로 rule 효과 검증
```

---

## 12. Variations 최종 계산

### 17 Metrics 기준 (Metric-Type별 단계 적용)

```
Ratio 계열 (11개): 7단계 → 7^11 = 1,977,326,743
Angle 계열 (3개): 5단계 → 5^3 = 125
Shape 계열 (2개): 3단계 → 3^2 = 9

총 Metric 조합: 1,977,326,743 × 125 × 9 = 22,244,925,859,375 (~22.2조)
인종 포함: 6 × 22,244,925,859,375 = 133,469,555,156,250 (~133.5조)
```

### 성별/연령 포함 전체 Variations

```
인종(6) × 성별(2) × 연령(2) × Metric조합(22,244,925,859,375)
= 24 × 22,244,925,859,375 = 533,878,220,625,000 (~534조)
```

### Attribute Score 기반 (사용자 체감 유형)

```
10 Attributes × 소수 1자리 (0.0~10.0) = 101^10
→ 이론상 무한에 가까우나, 실질적으로:

각 Attribute를 5구간으로 분류:
  0~2: 매우 낮음
  2~4: 낮음
  4~6: 보통
  6~8: 높음
  8~10: 매우 높음

사용자 체감 유형: 5^10 × 2(성별) × 2(연령) = 39,062,500 (~3,906만 유형)
```

---

## 13. 구현 체크리스트

```
Phase 1 — Core Engine
  □ Gender enum + AgeGroup enum 정의
  □ 17 Metrics 계산 함수 (face_metrics.dart 확장)
  □ 인종 × 성별 reference data (6 × 2 = 12세트, face_reference_data.dart)
  □ Z-score 계산 (referenceData[ethnicity][gender] 조회)
  □ 노화 보정 함수 adjustForAge() (age_offset 테이블)
  □ Z-score → Metric Score 변환 (ratio/angle/shape 분기)
  □ 10 Attribute Base Score (성별 가중치 delta 적용)
  □ Common Interaction Rules (38개)
  □ Gender-specific Rules (남성 5개 + 여성 5개)
  □ Age-specific Rules (50대 이상 5개)
  □ Sigmoid 정규화 (0~10)
  □ Archetype 분류 (성별별 표현)

Phase 2 — Report
  □ LLM API 연동 (성별/연령 컨텍스트 포함 프롬프트)
  □ Structured Data → LLM Prompt 조립 (gender, ageGroup 필드)
  □ 리포트 UI (Attribute 레이더 차트, Archetype 카드)
  □ 성별/연령 선택 UI (앱 온보딩 또는 설정)

Phase 3 — Calibration
  □ 표본 데이터 수집 (성별 × 연령별 각 50명 = 200명+)
  □ 성별별 Mean/SD 보정
  □ 노화 보정 오프셋 검증 (50대 이상 표본 vs 50대 미만 비교)
  □ Weight/Rule 튜닝
  □ A/B 테스트 (성별/연령 보정 on/off 비교)
```
