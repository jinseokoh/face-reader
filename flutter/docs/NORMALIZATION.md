# 속성 점수 정규화 (Attribute Normalize)

**최종 업데이트**: 2026-04-18
**구현**: `lib/domain/services/attribute_normalize.dart`
**입력**: `deriveAttributeScores()` 의 raw attribute map (10개)
**출력**: 5.0 ~ 10.0 의 사용자 노출 점수 (소수 1자리)

---

## 1. 왜 정규화가 필요한가

### 1.1 Raw 분포가 속성마다 다르다

Monte Carlo 20,000 샘플 측정 결과, 속성별 raw 점수 분포가 구조적으로 다름:

| 속성 | p50 | p90 | p100 |
|---|---|---|---|
| stability | **1.38** | 1.73 | 4.30 |
| trustworthiness | **0.89** | 1.20 | 2.51 |
| leadership | 0.25 | 0.71 | 5.28 |
| intelligence | 0.25 | 0.44 | 4.98 |
| sociability | 0.21 | 0.47 | 2.75 |
| emotionality | **0.27** | 0.44 | 1.99 |
| libido | 0.04 | 0.30 | 4.53 |

원인:
- Weight matrix 행 합은 ≈1.00 이지만 각 노드 입력 z-score 의 correlation 이 다름
- Stage 규칙 firing rate 가 속성마다 다름 (stability: Z-01 ≈11% 발동 / emotionality: 관련 규칙 거의 없음)
- 결과: **동일 raw 0.5 가 stability 에선 p5 수준, emotionality 에선 p95 수준**. 그대로 UI 에 쓰면 속성 간 비교 불가.

### 1.2 사용자 비교 가능성

속성 10개가 통일 스케일이어야 "내 지성 vs 내 사회성" 직관적 비교 가능. Bar chart UI 의 기본 전제.

### 1.3 Self-referential 랭킹

얼굴마다 "가장 강한 속성 / 약한 속성" 이 뚜렷해야 archetype 분류와 리포트 서술이 의미 있음. 100% global percentile 만 쓰면 평범한 얼굴이 6.5/6.3/6.1 같이 빽빽하게 몰려 차별화 실종.

---

## 2. 방법

### 2.1 파이프라인

```
raw score
   ↓
_rawToPercentile(raw, attr, gender)     ← 성별별 21-point quantile table, 선형보간
   ↓  globalPct ∈ [0, 1]
rank by globalPct (desc)                ← 얼굴 내 10 속성 랭킹
   ↓  rankPct = (9 - rank) / 9
blend = 0.60 × rankPct + 0.40 × globalPct
   ↓
score = 5.0 + blend × 5.0               ← [5.0, 10.0]
   ↓ round to 0.1
final
```

### 2.2 블렌드 비율 0.60 / 0.40 의 근거

| 비율 | 효과 |
|---|---|
| 100% global | 모든 얼굴이 평균 근처 몰림 (표준편차 좁음) — 개인 차별화 실종 |
| 100% rank | 객관 위치 정보 소실 — "내가 전체 모집단 대비 어느 정도인지" 모름 |
| **0.60 / 0.40** | 개인 내 차별화 살리면서 객관 위치도 반영 |

0.60 / 0.40 으로 top-bottom spread ≥ 3.0 (목표 UX) 자연스럽게 달성.

### 2.3 성별 분리

남/여 quantile table 별도. 이유: 성별에 따라 attribute 분포가 구조적으로 다름 (예: libido 남성 p50 ≈ 0.00 vs 여성 p50 ≈ 0.01, sensuality 분포 tail 차이). 통합 table 쓰면 한 성별이 체계적으로 과/저평가됨.

---

## 3. 기대 수치

Monte Carlo 20,000 샘플 결과 목표치:

| 지표 | 기대값 | 이유 |
|---|---|---|
| 출력 범위 | 5.0 ~ 10.0 | UI 표시용 5점 스케일 |
| 평균 top 속성 | ≥ 8.0 | rank=0 일 때 blend ≈ 0.6 + 0.4×gPct ≥ 0.6 → ≥ 8.0 |
| 평균 bottom 속성 | ≤ 7.0 | rank=9 일 때 blend = 0 + 0.4×gPct → ≤ 7.0 |
| top-bottom spread | ≥ 3.0 | 블렌드 0.6/0.4 구조적 보장 |
| 속성 간 saturation (모두 ≥9.5) | < 5% | 상관 얼굴 입력에서도 spread 유지 |
| 평균 / 표준편차 | ≈ 7.0 / ≈ 1.2 | 정규화 직후 관측값 |

검증 테스트: `score_distribution_test.dart`, `archetype_fairness_test.dart`, `archetype_template_sanity_test.dart`.

---

## 4. 기대 효과

### 4.1 UX 측면

- **Bar chart 가독성**: 10 속성이 동일 스케일이라 높낮이 즉시 구분
- **직관 해석**: "7.5 = 상위 25%" 같이 사용자가 숫자를 바로 해석
- **Archetype 선명화**: top 2 속성이 뚜렷하게 추출되어 archetype intro 텍스트가 의미 있음
- **Compat 비교 공정**: 두 사람 attribute 를 같은 스케일로 비교 → 궁합 점수 공평

### 4.2 엔진 측면

- Raw 에서 saturation 되던 stability/trustworthiness 가 제대로 구분됨
- Weight matrix 변경해도 UI 스케일 영향 무시 (quantile 재생성만 하면 자동 재보정)
- 성별 구조 차이 자동 흡수

### 4.3 모니터링 측면

- 속성별 p50/p90 이 목표 범위 벗어나면 weight matrix 나 rule 임계값이 한쪽으로 쏠린 신호
- `stage_contribution_test.dart` 가 이 신호를 자동 감지

---

## 5. 운영 — Quantile 재생성 절차

Weight matrix, rule 조건, metric reference 중 하나라도 건드리면 raw 분포가 이동함. 즉시 재생성:

```bash
flutter test test/calibration_test.dart
```

출력된 21-point map 을 `attribute_normalize.dart` 의 `_attrQuantilesMale` / `_attrQuantilesFemale` 에 붙여 넣기. 이후 하위 테스트 전부 그린인지 확인:

- `archetype_fairness_test.dart` — archetype 분포 공정성
- `score_distribution_test.dart` — spread / saturation
- `compat_label_fairness_test.dart` — 궁합 라벨 분포

**재생성 설정**: 20,000 샘플, seed=42, input z ~ N(0.2, 0.85). 재현성 고정.

---

## 6. 한계 / 실패 모드

| 증상 | 원인 | 대응 |
|---|---|---|
| Top 속성 평균 < 8.0 | 블렌드 비율이 너무 globalPct 쏠림 | `_rankWeight` 상향 검토 |
| Spread < 3.0 가 빈번 | Rule 한 stage 가 다수 속성 동시 증가 → 상대 랭킹 뭉개짐 | Rule 효과 분산 (단일 rule 이 여러 속성 +1 동시 적용 지양) |
| 동일 input 에서 점수 튐 | Quantile table 이 신규 엔진 출력과 불일치 | 재생성 필요 |
| 특정 속성이 항상 top | Weight matrix 에서 절대값 우위 노드 과대 | weight row 재배분 |

한계:
- **N(0.2, 0.85) 가정**: 실제 인구 분포와 차이 있을 수 있음. 실측 데이터 누적 시 재측정.
- **성별 2개만 지원**: non-binary 는 fallback 필요 (현재 female 사용).
- **나이 미반영**: quantile table 이 all-age 합산. 연령대별 분리 시 별도 설계 필요.

---

## 7. 참조 구현

- `lib/domain/services/attribute_normalize.dart` — 본체
- `lib/domain/services/score_calibration.dart` — quantile table 생성 로직
- `test/calibration_test.dart` — Monte Carlo 런너
- [ARCHITECTURE.md](ARCHITECTURE.md) §2 — 상위 트리 엔진 맥락

---

## 연관 문서

- [ARCHITECTURE.md](ARCHITECTURE.md) — 상위 아키텍처 (§2 Track 2, §4 Runtime Pipeline)
- [ATTRIBUTE_NODE_MAPPING.md](ATTRIBUTE_NODE_MAPPING.md) — weight matrix + rule 명세
- [TAXONOMY_METRIC_MAPPING.md](TAXONOMY_METRIC_MAPPING.md) — metric ↔ node 매핑
