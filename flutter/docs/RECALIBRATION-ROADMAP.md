# 재보정 로드맵 — 한국인 기준 정밀화

**작성**: 2026-06-07 · **상태**: 설계 합의 (구현 전)

엔진 점수 보정(calibration)을 사용자 데이터로 정밀화하는 방향. 이 문서는
어느 기기·세션에서든 논의를 이어가기 위한 휴대용 합의 기록이다. 코드 진실의
출처는 `docs/HOW-IT-WORKS.md`; 이 문서는 "앞으로 무엇을 왜 바꾸나"만 다룬다.

목표 모집단은 **한국인 한정**. 타 인종은 고려 대상이 아니다.

---

## 0. 두 개의 보정 층 (혼동 금지)

| 층 | 무엇 | 데이터 출처 | 코드 |
|---|---|---|---|
| **Metric 층** | 25개 기하 비율을 인구통계별 mean/std 로 z-score | AAF(동아 12k) + Kaggle + N=14 실측 보정 | `face_reference_data.dart`, `ethnicity_factors.dart` |
| **Attribute 층** | 10개 attribute raw 점수 → 5.0~10.0 매핑 | **Monte Carlo 합성 2만** 통과 결과의 분위수 | `attribute_normalize.dart`, `score_calibration.dart` |

- AAF 는 **metric 층 reference**. attribute 점수 정규화는 **MC 합성 분포** (실제 얼굴 아님).
- MC 는 매 분석이 아니라 **offline 1회** (`calibration_test.dart`) → quantile 을 상수로 박음 → 런타임은 lookup.

---

## 1. 현재 구조의 정밀도 한계 (사실)

### 1.1 N=14 실측 보정의 통계적 취약성
`score_calibration.dart:331-335` 주석 + `real_users_recalibration_test.dart`.
- 보정 공식: `new_mean = old_mean + old_std·z̄`, `new_std = old_std·z_std`.
- 동아 여성 30대 **14명**으로 metric 25개 × (mean+std) = **파라미터 50개** 추정 → 과적합 구조.
  - 평균 표준오차 ≈ σ/√14 ≈ **0.27σ** (작은 shift 는 노이즈와 구분 불가).
  - std 95% CI ≈ [0.72σ, 1.44σ] → **std 재척도는 사실상 노이즈 적합**.
- 취지(셀카·MediaPipe 계측기 편향 보정)는 **정당**. 정밀도가 부족할 뿐 → 출시용 1차 보정으로는 수용, 최종으로는 부적합.

### 1.2 연령 차원 부재
`referenceData` 키는 **`[Ethnicity][Gender][metric]`** 뿐, **age 없음**.
- → 30대 14명에서 뽑은 보정이 **전 연령 동아 여성**에 동일 적용됨 (30대 한정 아님).
- 연령은 하위(`deriveAttributeScores` 의 `ageGroup`)에서만 조정.

### 1.3 5.0~10.0 floor 는 UX 설계 (측정 필연 아님)
`attribute_normalize.dart` `score = 5.0 + blended·5.0`, `blended = 0.35·rank + 0.65·global`.
- 하한 5.0 = 심리적 방어선 (낙제선 회피·백래시 방어). 문서엔 근거 미기재 — 설계 추론.
- 35% rank 성분은 **자기 10속성 강제 순위 대비** → 실제 우열과 무관하게 대비 제조.
- docstring 의 "top≥8 / bottom≤7 / spread≥3.0" 은 **엄밀 보장 아님** (전형값; rank 단독 스프레드는 1.75).

---

## 2. 데이터로 개선되는 것 / 안 되는 것

**개선 가능 (calibration)**: per-cell mean/std 정밀화, 연령 차원 추가, MC 합성 sampler 를
실측 공분산/분포로 대체(또는 실측 raw 점수에서 직접 quantile), faceShape 분류기 검증.

**개선 불가 (validation)**: 관상 규칙(넓은 이마→재물운 등)의 참/거짓. **outcome 라벨이
없으므로** 데이터는 "모집단 내 위치"만 개선하고 규칙 자체는 검증 못 한다. 엔진은 *더 잘
보정된* 관상이 될 뿐 *검증된* 관상이 되지 않는다. 이 경계는 마케팅에서도 정직하게 유지.

---

## 3. 한국인 기준 전략

### 3.1 층화: gender × ageGroup (~10셀), 인종 제거
- 인종 차원 제거 → 셀 = 2 성별 × ~5 연령 = **약 10셀**. 셀당 목표 채우기 현실적.
- ethnicity 추론(DeepFace)은 **층화 축이 아니라 corpus 포함 필터**로 사용: `eastAsian 만 누적`.
  - ⚠️ DeepFace 는 "eastAsian"까지만 구분, 한·중·일 못 가림 → corpus 는 **한국인 근사(proxy)**.

### 3.2 셀당 표본 목표
| 수준 | N/셀 | 비고 |
|---|---|---|
| 최소 가용 | ~300–500 | 중심·중앙 quantile |
| **졸업 임계** | **~1,000** | p5/p95 안정 |
| 천장 | ~5,000 | 극단 꼬리, 이상은 수확체감 |

- 총 1~5만이면 충분. **크기보다 대표성**(한국 안에서도 sharer·20대 여성 과대표 주의).
- p0/p100(표본 min/max)은 N 무관 불안정 → **p1/p99 또는 winsorize 로 교체** (코드 픽스).

### 3.3 ⭐ 최우선 구조 변경: reference 를 `[gender][ageGroup]` 로 재편
한국 한정이라 인종이 빠지면 주 층화축이 age 인데 reference 에 age 가 없다.
→ `face_reference_data.dart` 의 `referenceData` 를 연령 차원 포함하도록 재편하는 것이
정확도에 가장 크게 기여하는 변경.

### 3.4 수집·갱신 아키텍처 (프라이버시 양립)
- 원본 행/얼굴 **저장·90일 삭제 해제 금지**. 대신 셀별 **streaming 집계**:
  `count, Σx, Σx²` (+공분산용 `Σxᵢxⱼ`), 꼬리는 **t-digest** quantile sketch.
  - → mean/std/covariance/quantile 전부 산출, 원본 즉시 폐기 가능 → /contact 의 90일
    자동삭제 약속·Play 데이터안전성 선언과 충돌 없음. 모델 개선 목적 **동의 한 줄**은 필요.
- 갱신은 **누적 전체** 기준 (최근 N개 슬라이딩 윈도우 ✗ — 얼굴 분포는 정상성이라 윈도우는
  점수 불안정 + recency 편향 + 데이터 낭비만 부름).
- **수렴 시 freeze** (N≈5000 이면 1/√N 로 거의 안 움직임). 재생성 트리거는
  (a) 셀 N 임계 도달, (b) 측정 파이프라인/metric 변경, (c) 정기 큰 주기 — **상시 슬라이딩 ✗**.
- 셀 N<1000 은 **shrinkage** (가중치 `N/(N+k)`, k≈300) 로 부모(연령 합친) 분포에서 차용.
- 배포는 **버전 단 static 스냅샷** (지금 calibration_test → 상수 박는 방식 유지).

---

## 4. 구현 순서 (제안)

1. `referenceData` 를 `[gender][ageGroup]` 구조로 재편 (`face_reference_data.dart`).
2. Supabase 셀별 집계 테이블 + 누적 RPC + t-digest (`react/db/migrations/0001_baseline.sql` 직접 수정).
3. eastAsian 필터 + ageGroup 버킷팅을 집계 경로에 적용.
4. N 임계 졸업 + shrinkage 로직 → reference 재생성 하니스.
5. `attribute_normalize` p0/p100 → p1/p99 픽스.
6. (선택) MC sampler 의 손튜닝 로딩을 실측 공분산으로 교체, 또는 실측 raw 점수 직접 quantile.

각 단계는 독립 PR 가능. 1·5 는 데이터 없이 지금 착수 가능, 2~4 는 출시 후 데이터 누적과 병행.

---

## 5. 정직성 체크리스트 (마케팅·고지)

- "Monte Carlo 재보정" = attribute 점수 분포 **사전 보정**(offline→상수). 실시간 아님.
- "성별·연령·인종별 보정" = 실측 뒷받침 셀은 현재 동아 여성 30대 1칸뿐. 그 외는 학술 reference.
- 점수는 절대 평가 아님 = "보기 좋게 정규화된 상대 점수" (5.0 floor + 35% rank 대비).
- 데이터가 늘어도 관상 규칙 자체는 검증되지 않음 (calibration ≠ validation).
