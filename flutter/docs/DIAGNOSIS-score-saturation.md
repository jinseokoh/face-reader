# 진단: 관상 10속성이 얼굴마다 비슷하게 나오고 "바람기"가 항상 1위인 이유

**작성**: 2026-06-01
**증상**: 전혀 다른 군집의 얼굴 3장을 분석했는데 10속성 프로파일이 거의 동일.
세 명 모두 **"바람기" 1순위 9.9**, 전체 점수가 6.8~9.9 상단에 몰려 있음.

---

## ✅ 해결 (2026-06-01)

근본 원인(추정치 reference → production z 가 +로 떠 saturate)을 **All-Age-Faces 실사진 11,800장**(정면 yaw<18°, male=5361·female=6439)으로 재보정해 교정. 앱과 동일 파이프라인(MediaPipe 468 → `face_metrics.dart::computeAll()`)으로 26 정면 metric 의 empirical μ/σ 를 측정 → `face_reference_data.dart[eastAsian]` 교체.

**검증**: 동일 11,800장을 새 reference 로 엔진 재투입한 결과 — 점수 SD 0.5(붕괴)→**1.0~1.5(정상)**, "바람기"(sensuality) 1위 빈도 100%→**4.9%**, min 점수 6.8→**5.0** (전 범위 사용), 1위 속성 고른 분산. §3 시나리오 A(건강) 패턴 회복. flutter test 145개 green.

도구: `tools/face_shape_ml/extract_aaf.py`, 명세: `tools/face_shape_ml/RECALIBRATION-metrics-spec.md`. 측면 8 metric 은 정면 표본으로 측정 불가 → 미변경. 비-eastAsian 인종 cell 은 데이터 확보 시 후속 재보정 대상.

---

## 0. 결론 먼저 (원인 분석)

| 사용자 가설 | 판정 |
|---|---|
| ① 얼굴 detail 판별 못함 | **부분적으로 맞음** — 엔진 자체는 변별 가능하나, 입력 보정이 어긋나 변별이 상단에서 뭉개짐 |
| ② landmark 뭉뚱그려 grouping, 중복값에 같은 값 | **틀림** — 점수는 연속값. 다만 CDF 상단 꼬리에서 saturate되어 *결과가* 뭉쳐 보임 |
| ③ variation 안 나오는 구조 | **현 운영 상태에선 맞음** — 단, 구조의 한계가 아니라 입력 보정 mismatch의 결과 |
| ④ 바람기에 강하게 biased | **맞음** — 원인은 sensuality 속성의 주력 노드(눈·입·인중)가 레퍼런스 대비 가장 과대 측정됨 |

**큰 코드 과오인가?** 아니다. 점수 도출(`attribute_derivation`)·정규화(`attribute_normalize`) 수학은 내부적으로 일관되며, 입력이 보정 가정과 맞으면 정상적으로 변별한다(아래 §3 시나리오 A).

**분류가 잘못됐나? assumption이 틀렸나?** → **assumption(보정 가정)이 틀렸다.**
`face_reference_data.dart`의 metric 평균·표준편차가 실제 사용자 얼굴의 측정 분포와 어긋나 있어, 실제 z-score가 체계적으로 0보다 크게(특히 눈·입·인중 계열) 나온다. 그 결과 모든 속성이 CDF 상단으로 saturate되어 점수가 6.8~9.9에 압축되고, 가장 크게 치우친 sensuality(=화면의 "바람기")가 거의 항상 1위가 된다.

---

## 1. 라벨 주의 — "바람기"는 sensuality 속성이다

`shared/lib/data/enums/attribute.dart`의 한글 라벨 매핑:

| 화면 라벨 | 내부 Attribute |
|---|---|
| 바람기 | `sensuality` |
| 관능도 | `libido` |
| 매력도 | `attractiveness` |

즉 "항상 1위인 바람기"는 코드상 `sensuality`다. 아래 분석은 모두 `sensuality` 기준.

---

## 2. 파이프라인 구조와 saturation 메커니즘

흐름: `metric z-score` → `scoreTree` → `deriveAttributeScores`(raw) → `normalizeAllScores`(0~10 표시값)

### 2-1. 정규화는 무조건 5.0~10.0으로만 매핑
`attribute_normalize.dart:246` `normalizeAllScores`:

```
blended = 0.35 · rankPct + 0.65 · globalPct
score   = 5.0 + blended · 5.0          // → 5.0 ~ 10.0
```

- `globalPct` = 그 속성의 **자기 분포(calibration CDF) 대비 백분위**
- `rankPct`   = 그 얼굴 안에서의 10속성 순위(상대 spread 강제용)
- 보장: 최상위 ≥ 8.0, 최하위 ≤ 7.0, spread ≥ 3.0

문제의 핵심은 `globalPct`다. **raw가 해당 속성의 calibration 분포 어디에 떨어지는가**로 점수가 정해진다. raw 자체의 크기가 아니라 *백분위*다.

### 2-2. CDF 상단 꼬리가 매우 평평 → saturation
21-point quantile 표(여성 fallback)의 상단 간격:

| 속성 | p90 | p95 | p100 |
|---|---|---|---|
| sensuality | 0.581 | 0.743 | **2.361** |
| attractiveness | 0.685 | 0.848 | **2.555** |

p95~p100 사이가 0.74→2.36처럼 매우 넓다. 즉 **raw가 ~0.8을 넘으면 그 위는 전부 백분위 0.95~1.0으로 압축**되어 9.8~10.0으로 saturate된다. 서로 다른 두 얼굴의 raw가 0.9와 1.6이어도 둘 다 ~9.9가 된다 → "전부 비슷"의 직접 원인.

### 2-3. raw를 상단으로 밀어올리는 것은 입력 z의 체계적 양(+)편향
raw(sensuality) = Σ(노드 signed-z × weight) + 규칙들.
sensuality weight(`attribute_derivation.dart:238`): **eye 0.17, mouth 0.17, philtrum 0.15, eyebrow 0.13** 가 주력.

만약 실제 얼굴의 눈·입·인중·눈썹 metric이 레퍼런스 평균보다 체계적으로 크면(=z가 +1 이상), base만으로 raw ≈ (0.17+0.17+0.15+0.13)×1.3 ≈ 0.8을 넘기고, 여기에 O-PH1(인중 짧음)·Z-04/Z-10(하정)·P-06(처첩궁) 등 규칙이 더해져 raw가 1.0을 쉽게 초과 → §2-2에 의해 9.9 saturate.

---

## 3. 실측 (Monte Carlo, 6,000 faces, 여성·동아·30대, 실제 파이프라인 그대로)

각 시나리오마다 입력 z를 다르게 생성해 정규화 결과의 분포를 측정.

| 시나리오 | 입력 z | 점수 SD(평균) | rank-1 최다 속성 | 증상 재현? |
|---|---|---|---|---|
| **A** | N(0,1) 독립 (보정 가정과 일치) | ~1.2 | 고름(관능 16% / 재물 15%…) | ❌ 정상 변별 |
| **B** | N(0,1) bone-correlated | ~1.4 | 고름 | ❌ 정상 |
| **C** | N(0,0.6) (캡처 노이즈가 작을 때) | ~0.9 | 안정성 22% | △ 압축 시작 |
| **D** | N(0,1) **+0.5 오프셋** | ~0.85 | 신뢰성 24%·재물 18% | ✅ 전부 7.9~9.1 |
| **E** | N(0,0.6) **+0.5 오프셋** | **0.46~0.96** | 신뢰성 38%·매력 23% | ✅ **스크린샷과 동일** |

해석:
- **A/B**: 입력이 보정 가정과 맞으면 SD ~1.2로 충분히 변별되고 특정 속성 쏠림 없음 → **엔진 수학은 건강하다.**
- **D/E**: 입력 z에 **체계적 +오프셋**(레퍼런스 평균이 실제보다 낮을 때 발생)이 들어가면, 전 속성이 8~10으로 압축되고 SD가 0.5 수준으로 붕괴 → **스크린샷 증상 그대로 재현.**

> 단, 일률 +0.5 오프셋(D/E)에서는 신뢰성·사회성이 1위로 올라온다. 스크린샷은 sensuality가 1위 → 실제 오프셋은 **속성마다 다르며, 눈·입·인중 계열(sensuality 주력 노드)에 가장 큰 +편향**이 실려 있다는 뜻이다.

---

## 4. 왜 하필 "바람기(sensuality)"가 1위인가

`face_reference_data.dart`의 정면 metric 평균은 대부분 **소표본·추정치**다(파일 주석에 명시):
- 여성: "real-user **N=14** fixture 로 mean만 재중심, sd는 신뢰 못 해 유지"
- 다수 metric: "**MediaPipe-geometry 추정값**", "실측 누적 후 보정 예정"

sensuality 주력 노드(eye·mouth·philtrum)에 묶인 metric들:
- eye: `eyeFissureRatio`(평균 0.21), `eyeCanthalTilt`, `eyeAspect`, `intercanthalRatio`
- mouth: `lipFullnessRatio`(0.12), `mouthWidthRatio`(0.38), `upperVsLowerLipRatio`…
- philtrum: `philtrumLength`(0.094)

이 추정 평균이 실제 분포보다 낮게 잡혀 있으면 해당 z가 항상 +로 뜨고, 이 노드들에 가중치가 가장 높은 sensuality가 raw를 제일 크게 밀어올려 saturate → **모든 얼굴에서 바람기 1위**.

추가로 sensuality는 규칙 측면에서도 발동 기회가 많다(O-PH1, O-DC2, Z-04, Z-10, Z-EBT, P-06, A-Y01, L-EL). 같은 raw 편향에 규칙 가산이 겹쳐 더 빨리 천장에 닿는다.

---

## 5. 무엇이 문제이고 무엇이 아닌가 (정리)

**문제 아님 (건강함):**
- weight matrix 불변식(row합=1, cos-sim<0.92 등), 규칙 cap, 정규화 blend 수학.
- A/B 시나리오에서 정상 변별 확인.

**문제 (수정 대상):**
1. **레퍼런스 보정 mismatch (근본 원인)** — `face_reference_data.dart`의 평균/표준편차가 실제 production 측정 분포와 어긋남(특히 눈·입·인중 평균이 낮게 추정). → 전 속성 z가 +로 떠 saturate, sensuality 최대 편향.
2. **CDF 상단 꼬리 과대 → saturation** — p95~p100 간격이 너무 넓어 상단에서 변별 소실. 입력 편향이 있으면 즉시 9.9에 몰림.
3. **(부차) 표시 범위가 5.0~10.0 하단 절반 봉인** — 실제로 "나쁜" 점수가 나올 수 없어 모두 후하게 보임. 입력이 정상이어도 체감 변별이 약함.

---

## 6. 권고 방향 (우선순위)

가장 효과 큰 순:

1. **production 측정값으로 레퍼런스 재보정 (P0).**
   실제 사용자 정면 캡처에서 27개 정면 metric의 raw 측정값(z 변환 *전*)을 수집 → 각 metric의 실제 평균·표준편차로 `referenceData[eastAsian]`를 교체. 특히 `eyeFissureRatio`·`lipFullnessRatio`·`philtrumLength`·`mouthWidthRatio`·`eyeAspect`를 우선. N=14는 평균 추정에 부족.
   - 검증: 재보정 후 production 분석들에서 10속성의 평균 백분위가 0.5 근방, 속성별 1위 빈도가 고르게 분산되는지 측정(§3 A 패턴 회복).

2. **정규화 CDF 상단 꼬리 압축 완화 (P1).**
   상단(p95~p100)을 그대로 두면 작은 입력 편향에도 saturate된다. quantile을 production 분포로 재생성(`calibration_test.dart` 재실행)하면 자동 해결되지만, 그 전까지는 `_rawToPercentile`의 상단 포화를 줄이는 임시 완화도 가능.

3. **표시 범위 재고 (P2, UX).**
   5.0~10.0 봉인은 "모두 좋아 보임"을 강제한다. 하단을 더 열거나(예: 3.0~10.0) 백분위 자체를 노출해 변별 체감을 높이는 안 검토.

> ※ 라벨("바람기"=sensuality)은 의도된 매핑이면 그대로 두되, 사용자에게 sensuality가 부정 뉘앙스로 읽히는 점은 별도 UX 판단 사항.

---

## 부록 A. 재현 방법

`flutter/test/`에 임시 진단 테스트를 두고 `metricInfoList` 전 metric에 시나리오별 z를 주입,
`deriveAttributeScores` → `normalizeAllScores`(여성·동아·30대·shape unknown)로 6,000 faces를 돌려
속성별 mean/SD/min/max/rank-1%와 샘플 프로파일을 출력해 측정했다(본 진단의 §3 표).
입력 z만 시나리오별로 바꾸면 동일 재현 가능.
