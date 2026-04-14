# Phase 1 실행 계획 — Rule Space Densification PoC

BIGPICTURE.md §5.6에서 정의한 Phase 1 (PoC, +30 룰)의 구체 실행 문서.

---

## 0. 현재 상태 스냅샷

### 0.1 active rules (attribute_engine.dart)

| attribute | R1 | R2 | R3 | R4 | R5 | 총 |
|---|---|---|---|---|---|---|
| wealth | · | · | · | · | ✓ | 1 |
| leadership | ✓ | ✓ | ✓ | ✓ | ✓ | 5 |
| intelligence | ✓ | ✓ | · | ✓ | ✓ | 4 |
| sociability | ✓ | ✓ | ✓ | ✓ | ✓ | 5 |
| emotionality | ✓ | ✓ | ✓ | ✓ | ✓ | 5 |
| stability | · | ✓ | ✓ | ✓ | · | 3 |
| sensuality | ✓ | ✓ | ✓ | ✓ | ✓ | 5 |
| trustworthiness | · | ✓ | · | ✓ | · | 2 |
| attractiveness | ✓ | ✓ | ✓ | ✓ | · | 4 |
| libido | ✓ | · | ✓ | ✓ | ✓ | 4 |

**Common: 38** + gender 10 + age 5 = **53 active rules**

### 0.2 dead text blocks (rule_text_blocks.dart)

`rule_text_blocks.dart`에는 **65개** RuleTextBlock이 있다. active rule은 53개이므로 **12개 블록이 고아(orphan) 텍스트**. 과거에 rule이 제거됐지만 텍스트는 남은 것으로 보임. 이것이 **공짜 shortcut**이다: 조건만 다시 붙이면 12개 룰이 복구된다.

| 고아 텍스트 ID | attribute | 원래 텍스트 요지 | 현재 rule 정의 |
|---|---|---|---|
| W-R1 | wealth | "재물이 모이는 코" — 코 폭 + 콧망울 동시 발달 (최강 재물 상) | 없음 |
| W-R2 | wealth | "새는 코의 상" — 코 폭 넓으나 콧망울 얇음 (contrast) | 없음 |
| W-R3 | wealth | "꾸준한 축적의 코" — 곧은 콧대 + 적당한 코폭 | 없음 |
| W-R4 | wealth | "재물 부족의 상" — 좁은 코 + 얇은 콧망울 | 없음 |
| I-R3 | intelligence | "학자 기질의 상" — 넓은 전택 + 곧은 콧대 | 없음 |
| ST-R1 | stability | "바위 같은 성격" — 곧은 콧대 + 넓은 전택 | 없음 |
| ST-R5 | stability | "변덕의 상" — 휜 콧대 + 좁은 전택 | 없음 |
| T-R1 | trustworthiness | "신뢰의 상" — 곧은 콧대 + 밝은 입꼬리 | 없음 |
| T-R3 | trustworthiness | "의심을 사는 인상" — 휜 콧대 + 처진 입꼬리 | 없음 |
| T-R5 | trustworthiness | "의리의 상" — 진한 눈썹 + 곧은 코 | 없음 |
| AT-R5 | attractiveness | "서구적 미형" — 곧고 좁은 코 (contrast) | 없음 |
| LB-R2 | libido | "왕성한 에너지의 상" — 넓은 코 + 두꺼운 콧망울 | 없음 |

**패턴**: 거의 전부 **`nasalHeightRatio` 기반**이다. 이 메트릭은 현재 active common rule의 **어떤 조건에도 사용되지 않는다** (base weight로는 쓰이지만 rule trigger로는 zero). 12개 고아 텍스트의 존재 자체가 이 빈 공간을 증언한다.

### 0.3 현재 active rule 조건에 쓰인 메트릭 빈도

| 메트릭 | 조건 등장 횟수 |
|---|---|
| mouthCornerAngle | 10 |
| lipFullnessRatio | 10 |
| eyeCanthalTilt | 9 |
| gonialAngle | 6 |
| browEyeDistance | 6 |
| eyeFissureRatio | 5 |
| eyebrowThickness | 5 |
| mouthWidthRatio | 5 |
| philtrumLength | 5 |
| nasalWidthRatio | 3 |
| intercanthalRatio | 3 |
| faceTaperRatio | 2 |
| faceAspectRatio | 2 |
| **nasalHeightRatio** | **0** ← 완전 미사용 |

`nasalHeightRatio`는 수집되고 v9 정규화에도 기여하지만 rule trigger로는 zero. Phase 1에서 이 구멍부터 메우는 게 최대 효율이다.

---

## 1. Phase 1 목표

- **신규/복구 룰 30개** 추가 → 총 common 38 → **~68**
- 그중 **12개는 공짜** (dead text 조건 재부착)
- 나머지 **18개는 신규 텍스트 + 신규 조건** — 비어 있는 패턴 영역 (contrast, balanced, asymmetric) 중심

---

## 2. 12개 공짜 복구 — 조건 제안

각 룰에 대해 기존 텍스트를 읽고, 텍스트 내용과 **모순되지 않는** 조건을 제안한다. 몇몇은 기존 메트릭으로 직접 표현 불가능한 개념 (예: "휜 콧대")이 있어서 proxy로 대체했다. proxy 선택 근거를 명시한다.

### 가용 메트릭 복습

현재 `computeAll()`이 내보내는 17개 메트릭 (face_metrics.dart 참조):
`faceAspectRatio`, `upperFaceRatio`, `midFaceRatio`, `lowerFaceRatio`, `faceTaperRatio`, `gonialAngle`, `intercanthalRatio`, `eyeFissureRatio`, `eyeCanthalTilt`, `eyebrowThickness`, `browEyeDistance`, `nasalWidthRatio`, `nasalHeightRatio`, `mouthWidthRatio`, `mouthCornerAngle`, `lipFullnessRatio`, `philtrumLength`

"곧은 콧대 / 휜 콧대"를 직접 재는 메트릭은 **없다**. Proxy로 `nasalHeightRatio`를 쓴다 — 길고 뚜렷한 코 = "곧다"는 전통적 해석과 일치.

### 복구 후보 12개

| # | id | attr | 제안 조건 | 패턴 | 근거 |
|---|---|---|---|---|---|
| 1 | W-R1 | wealth | `nasalWidthRatio >= 2 && nasalHeightRatio >= 1` | `++ (강)` | 텍스트 "동시에 발달"의 "가장 강력한 재물 징표" — 상위 tier |
| 2 | W-R2 | wealth | `nasalWidthRatio >= 1 && nasalHeightRatio <= -1` | `+-` contrast | 텍스트 "코 폭은 넓은데 콧망울이 얇아" 정확히 대응 |
| 3 | W-R3 | wealth | `nasalHeightRatio >= 1 && nasalWidthRatio.abs() <= 1` | `+0` asymmetric | 텍스트 "곧은 콧대와 적당한 코폭" — 길이 강하고 폭 중간 |
| 4 | W-R4 | wealth | `nasalWidthRatio <= -1 && nasalHeightRatio <= -1` | `--` | 텍스트 "좁은 코와 얇은 콧망울" 직접 대응 |
| 5 | I-R3 | intelligence | `browEyeDistance >= 1 && nasalHeightRatio >= 1` | `++` | 텍스트 "넓은 전택과 곧은 콧대" |
| 6 | ST-R1 | stability | `nasalHeightRatio >= 1 && browEyeDistance >= 1` | `++` | 텍스트 "곧은 콧대와 넓은 전택". I-R3과 동일 조건이지만 다른 attribute에 기여하므로 OK (두 룰이 항상 함께 발동) |
| 7 | ST-R5 | stability | `nasalHeightRatio <= -1 && browEyeDistance <= -1` | `--` | 텍스트 "휜 콧대와 좁은 전택". "휜"을 짧은 코로 proxy (길이 부족은 관상학적으로 중심 부재와 연결 가능) |
| 8 | T-R1 | trustworthiness | `nasalHeightRatio >= 1 && mouthCornerAngle >= 1` | `++` | 텍스트 "곧은 콧대와 밝은 입꼬리" |
| 9 | T-R3 | trustworthiness | `nasalHeightRatio <= -1 && mouthCornerAngle <= -1` | `--` | 텍스트 "휜 콧대와 처진 입꼬리". proxy 같은 이유로 짧은 코 |
| 10 | T-R5 | trustworthiness | `eyebrowThickness >= 1 && nasalHeightRatio >= 1` | `++` | 텍스트 "진한 눈썹과 곧은 코" |
| 11 | AT-R5 | attractiveness | `nasalHeightRatio >= 1 && nasalWidthRatio <= -1` | `+-` contrast | 텍스트 "곧고 좁은 코" — 길이 길고 폭 좁음 |
| 12 | LB-R2 | libido | `nasalWidthRatio >= 1 && nasalHeightRatio >= 1` | `++` | 텍스트 "넓은 코와 두꺼운 콧망울" |

### 복구의 패턴별 기여

| 패턴 | 추가 개수 | 비고 |
|---|---|---|
| `++` | 7 | W-R1, I-R3, ST-R1, T-R1, T-R5, LB-R2, W-R3 (약간 변형) |
| `--` | 3 | W-R4, ST-R5, T-R3 |
| `+-` contrast | 2 | W-R2, AT-R5 |

`nasalHeightRatio` 축에서 12개의 룰이 새로 발동되므로, 이 축에 편차가 있는 얼굴은 12개 중 여러 개가 한 번에 걸린다. 평범한 얼굴도 `nasalHeightRatio` 한 쪽만 튀어도 3~4개 룰을 건지게 됨.

### 잠재 이슈

- **ST-R5 / T-R3의 "휜 콧대" proxy가 약하다.** "휜"은 정상 범위의 굴곡 문제지 "짧다"와 다르다. 텍스트를 읽는 유저가 이질감을 느낄 수 있다. 대안:
  1. proxy 유지 (권장) — 짧고 얕은 코는 관상학적으로 중심축 부재와 연결될 수 있음
  2. 텍스트 수정 — "짧은 콧대"로 바꾸기
  3. 룰 복구 포기 — 해당 텍스트는 고아 상태 유지
- **ST-R1과 I-R3 동일 조건**: 두 룰이 항상 함께 발동. 텍스트는 다른 attribute를 다루므로 내용 중복은 아니지만, 같은 메트릭 조합이 두 번 매칭된다는 점에서 엔진적으로 redundant. 허용할 것인가?

---

## 3. 18개 신규 룰 — 패턴별 배치 전략

Phase 1의 나머지 18개는 **신규 텍스트 + 신규 조건**. 패턴 영역의 큰 구멍부터 메운다.

### 3.1 타겟 패턴 (현재 거의 비어 있는 영역)

| 패턴 | 현재 개수 | Phase 1 목표 추가 |
|---|---|---|
| `A==0 && B==0` (평균 근처) | 0 | **3** |
| `\|A\|<=1 && \|B\|<=1` (중용) | 1 (ST-R3) | **3** |
| `A>=1 && B==0` (asymmetric) | ~2 | **4** |
| `A>=1 && B<=-1` (contrast) | 4 | **4** |
| `A<=-1 && B>=1` (reverse contrast) | 0 | **2** |
| 단일 메트릭 soft | 0 | **2** |
| **합계** | | **18** |

### 3.2 attribute 분배 (신규 18개)

가장 룰이 적은 attribute 우선:
- wealth (1 → 복구 후 5): +1 신규
- trustworthiness (2 → 복구 후 5): +2 신규
- stability (3 → 복구 후 5): +2 신규
- intelligence (4 → 복구 후 5): +2 신규
- libido (4 → 복구 후 5): +2 신규
- attractiveness (4 → 복구 후 5): +2 신규
- leadership (5 → 5): +2 신규 (이미 5개지만 패턴 다양화)
- sociability (5 → 5): +2 신규
- emotionality (5 → 5): +2 신규
- sensuality (5 → 5): +1 신규

합계: 18

### 3.3 신규 룰 후보 (이 단계는 아직 텍스트 미작성)

아래는 **조건만 정의된 초안**. Korean 텍스트는 사용자 승인 후 작성.

#### 중용 패턴 (3개)
1. **W-R6 "중도의 재물"** — `nasalWidthRatio.abs() <= 1 && mouthWidthRatio.abs() <= 1` — 폭주하지 않는 안정적 재물 수명
2. **L-R6 "조정자형"** — `gonialAngle.abs() <= 1 && eyeCanthalTilt.abs() <= 1` — 조직의 균형추, 극단을 조정하는 리더
3. **E-R6 "감정의 중용"** — `lipFullnessRatio.abs() <= 1 && eyebrowThickness.abs() <= 1` — 감정을 절제하되 억압하지는 않는 성격

#### 평균 근처 (3개)
4. **ST-R6 "평온의 상"** — `faceAspectRatio.abs() <= 1 && gonialAngle.abs() <= 1` — 큰 파란 없는 잔잔한 인생
5. **T-R6 "중도의 신뢰"** — `mouthCornerAngle.abs() <= 1 && browEyeDistance.abs() <= 1` — 극단 없이 꾸준한 성실함
6. **AT-R6 "친근 호감형"** — `mouthCornerAngle.abs() <= 1 && eyeCanthalTilt.abs() <= 1` — 편안함으로 호감 얻는 타입

#### Asymmetric (4개)
7. **I-R6 "통찰 우위형"** — `eyeFissureRatio >= 1 && browEyeDistance.abs() <= 1` — 관찰력은 강하나 전택(사고공간)은 평균
8. **S-R6 "발표자형"** — `mouthWidthRatio >= 1 && mouthCornerAngle.abs() <= 1` — 표현력은 크지만 톤은 중립
9. **SN-R6 "은은한 도화"** — `eyeCanthalTilt >= 1 && lipFullnessRatio.abs() <= 1` — 눈매로만 매력 발산
10. **LB-R6 "은근한 활력"** — `philtrumLength <= -1 && lipFullnessRatio.abs() <= 1` — 인중 짧은데 입술은 평균 — 본능적 에너지 타입

#### Contrast (4개)
11. **L-R7 "외유내강"** — `gonialAngle >= 1 && eyeCanthalTilt <= -1` — 강한 턱에 처진 눈 — 부드러운 리더십
12. **E-R7 "냉정한 감성가"** — `lipFullnessRatio >= 1 && mouthCornerAngle <= -1` — 풍부한 감정이지만 외면은 무표정
13. **ST-R7 "역설의 안정"** — `eyebrowThickness >= 1 && browEyeDistance <= -1` — 강한 의지와 급한 판단의 공존
14. **AT-R7 "차가운 매력"** — `eyeFissureRatio >= 1 && mouthCornerAngle <= -1` — 큰 눈에 차가운 입 — 신비로운 매력

#### Reverse contrast (2개)
15. **T-R7 "반전의 신뢰"** — `browEyeDistance <= -1 && mouthCornerAngle >= 1` — 성급해 보이나 밝은 인상으로 보완
16. **LB-R7 "늦된 열정"** — `philtrumLength >= 1 && lipFullnessRatio >= 1` — 긴 인중에도 풍성한 입술, 천천히 타는 열정

#### 단일 메트릭 soft (2개)
17. **SN-R7 "풍성한 입술"** — `lipFullnessRatio >= 2` — 매우 풍성한 입술만으로도 발동 (단일 특성 강조)
18. **L-R8 "카리스마 시선"** — `eyeCanthalTilt >= 2` — 매우 치켜뜬 눈만으로도 리더십 발동

---

## 4. 실행 순서

### Step A (위험 0 — 승인 즉시 실행 가능)
1. `attribute_engine.dart`에 12개 복구 룰 조건 추가
2. `effects` 값 배정 (기존 R1~R5의 스케일 참조 — 대략 1.5~2.5)
3. build 검증 + 기존 테스트 실행

### Step B (텍스트 작성 필요 — 승인 후)
4. 18개 신규 룰에 대해 Korean 텍스트 작성 (기존 톤 매칭)
5. `rule_text_blocks.dart`에 항목 추가
6. `attribute_engine.dart`에 조건 추가
7. build 검증

### Step C (체감 검증)
8. 실제 얼굴 5~10개로 돌려서 텍스트 양과 variation 확인
9. Phase 2 계획 수립 (더 많은 contrast/asymmetric)

---

## 5. 승인 필요 결정 사항

다음 항목은 구현 전에 결정 필요:

**(a) "휜 콧대" proxy 처리** (ST-R5, T-R3에 영향)
- [ ] (a1) `nasalHeightRatio <= -1`을 proxy로 사용 (제안)
- [ ] (a2) 해당 텍스트를 "짧은 콧대"로 수정
- [ ] (a3) 두 룰은 이번 복구에서 제외

**(b) ST-R1과 I-R3 동일 조건 허용?**
- [ ] (b1) 허용 (제안 — 다른 attribute에 기여)
- [ ] (b2) ST-R1 조건을 다르게 수정 (예: `nasalHeightRatio >= 1 && gonialAngle >= 0`)

**(c) Step A (복구 12개)를 Step B (신규 18개)보다 먼저 단독 실행?**
- [ ] (c1) 네 — Step A만 먼저 커밋, 유저가 결과 체감 후 Step B 진행 (제안 — 안전)
- [ ] (c2) 아니오 — Step A+B 한 번에 진행

**(d) 신규 18개 룰의 텍스트 작성 주체**
- [ ] (d1) Claude가 먼저 drafting → 유저 검수 (제안)
- [ ] (d2) 유저가 직접 작성
- [ ] (d3) 조건만 먼저 넣고 텍스트는 나중에 (텍스트 없는 룰은 UI에 안 보임)

**(e) effects 스케일**
- 기존 R1~R5의 effect 값이 ±1.0 ~ ±3.0 사이에서 분포
- 제안: 복구 12개는 모두 **1.5** 기본값 (강한 ++ 패턴은 2.0, 약한 contrast는 1.0)
- 승인하시면 이 기준 적용
