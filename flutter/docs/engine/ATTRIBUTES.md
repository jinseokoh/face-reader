# 10 속성 → Tree Node 재도출 설계서

**버전**: v2.9 (engine v2, face/ear 제외, Stage 0 preset 철수, dominant decorrelation, 실사용자 ref re-centering, 美人相 rule 7 개 도입)
**마지막 업데이트**: 2026-04-20
**기반 문서**:
- `docs/engine/TAXONOMY.md` v2.0 (14-node tree SSOT + 노드별 metric/rule 매칭)
- `lib/domain/services/physiognomy_scoring.dart` (NodeScore tree)
- `lib/domain/services/attribute_derivation.dart` (5-stage pipeline)
- **관상 전통 research** (v0.2 반영) — §12 참조

**역할**: 9-node × 10-attribute weight matrix (face/ear 제외) 설계 + 5-stage derivation pipeline 규칙 명세.

**v0.3 → v2.9 변경 스택 (2026-04-18 → 2026-04-20)**:

v2.0 (2026-04-18):
- face(root)·ear 제외한 9-노드 매트릭스 재설계.
- Stage 0 face-shape preset 신설 (이후 v2.2 에서 철수).
- Stage 1b 매력도 symmetric bell 도입 (이후 v2.2 에서 철수).
- Rule 튜닝: O-EM 1.0→0.5, P-03 0.8→0.3.

v2.2 (2026-04-18):
- **Stage 0 preset 완전 철수** — 얼굴형이 raw score 에 1도 관여 안 함.
  FaceShape 는 archetype overlay + narrative Layer B 에만 존속.
- **매력도 distinctiveness bell 철수** — attr 는 node weight + rule 로만.

v2.3 (2026-04-18):
- 공통 rule magnitude 축소 (shape-bound stab/trust 쏠림 해소):
  Z-01 stab 1.5→0.3, O-CH stab 1.0→0.3, O-EB1 trust 1.0→0.3,
  P-01 stab 1.0→0.3, P-04 trust 1.0→0.3.

v2.5 (2026-04-19):
- intelligence weight matrix 재설계: 상정 집중 90% → 38% (forehead
  0.25→0.15, eyebrow 0.25→0.18, eye 0.30→0.25, nose 0.05→0.17,
  mouth→0.10, chin 0.05→0.10).
- stability weight matrix 재설계: forehead+chin 집중 55% → 35%
  (forehead 0.20→0.15, chin 0.35→0.20, eye 0.05→0.15, nose 0.15→0.17).
- Z-01 재축소: stab 0.3→0.1, trust 0.2→0.05, attr 0.2→0.1.
- Z-12 mag 축소: stab 0.5→0.2, trust 0.3→0.1.
- P-09 stab 0.5→0.2.
- **증명**: `test/shape_archetype_bias_test.dart` — 5 shape × 2000 샘플의
  top-1 attr 분포 max concentration 29.8% → 25.4% (assertion < 27%).
  oblong intel 23.8% → 11.0% (2배 감소).

v2.6 (2026-04-19):
- 모든 rule magnitude cap |Δ| ≤ 0.5. step-function dominance 차단.
- per-metric 영향력 ∈ [0.15, 1.20], max/min ≤ 6.5×.
- compat threshold 84/73/65 재보정.

v2.7 (2026-04-19):
- **dominant node decorrelation** — 10 attribute 가 각기 다른 1 개 노드를
  top weight(≥0.17)로 가지도록 row 재설계. row cosine similarity < 0.92.
- charm cluster (sociability·emotionality·sensuality·attractiveness·libido)
  가 eye+eyebrow+mouth 3 노드에 공통 dominant 로 쏠리던 편향(외교형/
  예술가형/미인형 cluster top-2 고정)의 구조적 원인 제거.
- attractiveness: eye·mouth tied (각 0.17), chin 0.09 로 분산.

v2.8 (2026-04-19):
- N=14 eastAsian female 30s 실사용자 empirical z 가 N(0,1) 에 수렴하도록
  reference mean 19 metric 재조정 + MC sampler bias=0.0, std=1.0.
- max archetype concentration 28.6% (4/14).

v2.9 (2026-04-20, 현행):
- **美人相 rule 7 개 도입** — 麻衣相法·神相全編 美貌 명제 grounded:
  - Z-NG 五官端正 (균형형 美), O-MM 桃花眼, O-EM2 眉目清秀, O-RL 朱唇小口,
    O-CKE 顴骨突過 (-), O-EZ 目偏不正 (-), P-MJ 印堂明潤.
- **기존 lax/stacking 매력 신호 narrowing**:
  - O-EM 임계 0.5→1.0, attractiveness 제거 (sociability 0.33 만).
  - Z-07 attractiveness 제거 (권위 명제로 정확화). Z-09 attractiveness 음수 제거.
  - P-03 attractiveness 제거 (trust 0.17 전용). Z-LFR attractiveness 제거.
- **compat threshold 재보정**: 83/73/65 → **85/72/64** (MC p90/p60/p30).
- **evidence snapshot 갱신**: rules 13→16, attractiveness 9.4→8.6 (lax stacking 제거 효과).

---

## 0. 전제

- 입력은 `NodeScore` tree (`physiognomy_scoring.dart::scoreTree()` — own-stats + roll-up stats 이중 축 제공).
- 출력은 `Map<Attribute, double>` 10 속성 raw score. 최종 UI 매핑(5.0~10.0)은 v9 normalize 경로로 변환.
- 조합 풍성화를 적극 추구하되 stage 간 dead-weight 없이 모든 layer 가 의미 있게 기여하도록 설계.

---

## 1. 설계 목표

### 1.1 트리 엔진이 활용하는 구조적 자원

| 자원 | 역할 |
|---|---|
| **Zone 집계** (삼정 roll-up) | 상/중/하 조화·불균형 규칙 |
| **Organ 태그** (오관) | 눈-눈썹, 코-입 등 쌍 규칙 |
| **Palace overlay** (십이궁) | 재백궁·관록궁 복합 시너지 |
| **Signed vs AbsZ 이중 축** | 방향 점수 + 편차 강도(distinctiveness) 분리 |
| **Root metrics** | root 노드 own-z 로 얼굴 전체 프로포션 명시 |
| **ownZ vs rollUpZ 구분** | leaf 자체 특성 vs zone 지배력 구분 |

### 1.2 설계 원칙

1. **Node 중심**: 규칙·가중치 모두 노드 id 참조. metric id 는 node 내부에 흡수.
2. **다층 조합**: base linear → zone → organ → palace → gender/age/lateral 의 **5 stage pipeline**.
3. **Polar 과 Magnitude 분리**: signed ownMeanZ (부호 있는 강세) + ownMeanAbsZ (편차 강도) 를 둘 다 활용.
4. **미지원 노드 견고성**: ear(unsupported), glabella(metric 공백) 는 자연스럽게 기여 0 으로 흐름.
5. **Lateral 흡수**: 측면 metric 은 이미 node 소속. `hasLateral` flag 로 규칙 적용 분기만.

---

## 2. Node → Attribute 가중치 매트릭스 (base linear 단계)

### 2.1 기본 공식

```
base[attr] = Σ_node ( W[attr][node] × signedScore(node) )
signedScore(node) = node.ownMeanZ          (leaf 노드)
                  = node.rollUpMeanZ       (zone 노드, rule 에서만 사용)
missing  → 0 기여
```

- 각 attribute 행의 **가중치 합 = 1.00** 으로 정규화.
- polarity (-1) 은 해당 셀에 음수 표기.
- face(root)/ear(unsupported) 노드는 weight matrix 에서 제외. face 는 Stage 0 shape preset + Stage 1b distinctiveness + Z-11 zone rule 을 통해 간접 소비.

### 2.2 매트릭스 (engine v2, 9-노드)

9 개 노드 = 이마·미간·눈썹·눈·코·광대·인중·입·턱 (face·ear 제외).

모든 가중치는 §12 research + 2026-04-18 엔진 재조정에서 도출. **합 = 1.00** (각 행). libido 의 philtrum 만 polarity `-1`.

**v2.7 매트릭스** (현행, 2026-04-19, code SSOT = `attribute_derivation.dart::_weightMatrix`):

| Attribute \\ Node | 이마 | 미간 | 눈썹 | 눈 | 코 | 광대 | 인중 | 입 | 턱 |
|---|---|---|---|---|---|---|---|---|---|
| **wealth** 재물운 | 0.12 | 0.10 | 0.08 | 0.08 | **0.20** | 0.10 | 0.07 | 0.10 | 0.15 |
| **leadership** 리더십 | 0.13 | 0.08 | 0.15 | 0.10 | 0.15 | 0.10 | 0.03 | 0.08 | **0.18** |
| **intelligence** 통찰력 | **0.18** | 0.10 | 0.10 | 0.15 | 0.10 | 0.08 | 0.09 | 0.10 | 0.10 |
| **sociability** 사회성 | 0.08 | 0.10 | 0.10 | 0.12 | 0.08 | 0.12 | 0.07 | **0.20** | 0.13 |
| **emotionality** 감정성 | 0.06 | 0.13 | 0.12 | **0.20** | 0.08 | 0.08 | 0.10 | 0.13 | 0.10 |
| **stability** 안정성 | 0.12 | 0.15 | 0.08 | 0.08 | 0.13 | 0.10 | 0.08 | 0.08 | **0.18** |
| **sensuality** 바람기 | 0.05 | 0.08 | 0.13 | **0.17** | 0.10 | 0.08 | 0.15 | **0.17** | 0.07 |
| **trustworthiness** 신뢰성 | **0.15** | 0.12 | 0.06 | **0.15** | 0.13 | 0.07 | 0.07 | 0.10 | **0.15** |
| **attractiveness** 매력도 | 0.07 | 0.07 | 0.13 | **0.17** | 0.10 | 0.13 | 0.07 | **0.17** | 0.09 |
| **libido** 관능도 | 0.05 | 0.08 | **0.17** | 0.13 | 0.10 | 0.10 | 0.15(−) | 0.12 | 0.10 |

각 행 합 = 1.00. zone 노드(상/중/하) 자체는 base 에 투입하지 않고 **zone 규칙**(§4.1) 에서 사용. libido 의 philtrum 만 polarity `-1`.

v2.7 핵심: 10 attribute 가 각기 다른 1 개 노드를 top weight(≥0.17) 로 가지도록 **dominant node decorrelation** — wealth=nose / leadership=chin / intelligence=forehead / sociability=mouth / emotionality=eye / stability=chin+glabella / sensuality=eye·mouth tied / trustworthiness=forehead·eye·chin balanced / **attractiveness=eye·mouth tied** / libido=eyebrow. charm cluster (sociability·emotionality·sensuality·attractiveness·libido) 가 eye+eyebrow+mouth 3 노드에 공통 dominant 로 쏠려 외교형/예술가형/미인형 cluster 로 top-2 가 고정되던 편향 해소. row cosine similarity < 0.92 강제.

**v0.3 재조정 핵심 (2026-04-18)**:
- cheekbone 의 총 영향력 1.13 → 0.75 로 완화 (단일 metric 과적재 해소).
- glabella(미간·browSpacing) base 기여 0 → 0.45 (고아 해제, 6 속성에 0.05~0.10 분산).
- 의미론 구멍 메움: eye→sociability/trustworthiness, chin→attractiveness, 하정 3노드→sensuality.
- nose 최고 weight 0.50→0.35 (lateral 의존성 완화), trust nose 0.35→0.20.
- philtrum libido 0.40(−)→0.20(−) (단일 metric 과적재 완화).

### 2.3 Stage 0 — Face Shape Preset (RETIRED v2.2)

v2.0 에 도입되었으나 v2.2 (2026-04-18) 에서 철수. 얼굴형이 raw score 에 주는 영향 = 0.
FaceShape 는 `classifyArchetype` 의 shape-gated overlay 와 narrative Layer B 에만 영향.

철수 이유: halve+gate 로도 calibration ↔ production 편향 제거 불충분. 얼굴형 →
archetype 간접 경로 (metric 상관 + 낮은 quantile p50) 가 근본 원인.

### 2.4 Stage 1b — Distinctiveness 가산 (magnitude 축)

v2.2 (2026-04-18) 에서 매력도 distinctiveness 완전 철수. 현행:

| Attribute | 소스 | 공식 | 이유 |
|---|---|---|---|
| intelligence | upper.rollUpMeanAbsZ | `+0.2 × clamp(abs−0.5, 0, 1.5)` | 상정 차별화 시 지적 인상 강화 |
| emotionality | lower.rollUpMeanAbsZ | `+0.3 × clamp(abs−0.5, 0, 1.5)` | 하정 강한 표정 → 감정 풍부 |

매력도는 node weight + rule 로만 결정 (bell 이 calibration p50 을 부풀려
production 얼굴이 체계적으로 낮은 percentile 을 받는 오염 제거).

---

## 3. 신규 규칙 세트 — 5 Stage Pipeline

```
base (linear)
  ├─ Stage 1: 노드 가중 합 (§2)
  ├─ Stage 2: Zone rules   (§4.1, 10 개 내외)
  ├─ Stage 3: Organ rules  (§4.2, 14 개 내외)
  ├─ Stage 4: Palace rules (§4.3, 8 개 내외)
  ├─ Stage 5: Gender delta + Age + Lateral flag (§5, 10 + 5 + 3 개)
  └─ distinctiveness 가산 (§2.3)
     → raw_attr_score
```

목표 총 규칙 수: 40–50 개. 한 규칙 한 가지 "얼굴 조합" 을 대표하도록 설계 — metric-pair 임계값 중복 없이 node 조합으로 풍성도 확보.

---

## 4. 조합 규칙 설계

### 4.1 Zone Rules (삼정 조화·불균형)

입력: `upper.rollUp*`, `middle.rollUp*`, `lower.rollUp*`. v2.6 cap: 단일 effect \|Δ\| ≤ 0.5.

| ID | 조건 | 효과 | 근거 |
|---|---|---|---|
| Z-01 삼정 균형 | 세 zone 모두 \|signedZ\| < 0.5 | stability +0.1, trust +0.05, attractiveness +0.05 | 三停均等, 福壽綿長 (麻衣相法) |
| Z-02 상정 우세 | upper signedZ ≥ 1 & 나머지 ≤ 0.5 | intelligence +0.5, leadership +0.13 | |
| Z-03 중정 우세 | middle signedZ ≥ 1 & 나머지 ≤ 0.5 | wealth +0.5, libido +0.33 | |
| Z-04 하정 우세 | lower signedZ ≥ 1 & 나머지 ≤ 0.5 | sensuality +0.5, libido +0.5, stability -0.17 | |
| Z-05 상-하 대립 | upper ≥ 1 & lower ≤ -1 | intelligence +0.5, emotionality -0.5 | |
| Z-06 하-상 대립 | lower ≥ 1 & upper ≤ -1 | emotionality +0.5, trust -0.17 | |
| Z-07 전면 강세 | 세 zone 모두 signedZ ≥ 1 | leadership +0.5 | 三停俱足者 富貴雙全 (麻衣) — 권위 명제. 美 부분은 Z-NG 로 분리 (v2.9) |
| Z-08 전면 약세 | 세 zone 모두 signedZ ≤ -1 | 7 positive attr -0.5 | |
| Z-09 상정 distinctive | upper absZ ≥ 1.5 | intelligence +0.5 | 매력 음수는 O-EZ 로 정확화 (v2.9) |
| Z-10 하정 distinctive | lower absZ ≥ 1.5 | sensuality +0.5, emotionality +0.25 | |
| Z-11 중정 비율 큼 | root `midFaceRatio` z ≥ 1.0 | wealth +0.5, sociability +0.3 | 中停隆滿者 富 |
| Z-12 하정 비율 큼 | chin `lowerFaceRatio` z ≥ 1.0 | stability +0.2, trust +0.1 | |
| Z-13 하정 비율 작음 | chin `lowerFaceRatio` z ≤ -1.0 | emotionality +0.3, stability -0.3 | |
| Z-FH 이마 강세 | forehead leafZ ≥ 0.7 | intelligence +0.20, trust +0.10 | v2.9 신규 — 학자형 신호 분산 |
| Z-IC 눈 사이 넓음 | eye `intercanthalRatio` z ≥ 0.5 | leadership +0.20, wealth +0.08 | v2.9 신규 — open-set 인상 |
| Z-LFR 풍만한 입술 | mouth `lipFullnessRatio` z ≥ 0.8 & `mouthWidthRatio` z < 1.5 | sociability +0.25 | 美 부분은 O-RL 로 narrowing (v2.9) |
| Z-FAR 세로로 긴 얼굴 | root `faceAspectRatio` z ≥ 1.2 | wealth +0.25, leadership +0.10 | v2.9 — oblong 형 wealth 분류 |
| Z-EBT 처진 눈썹 | eyebrow `eyebrowTiltDirection` z ≤ -1.0 | sensuality +0.20, emotionality +0.10 | 八字眉 — 관능·감성형 (한국 관상) |
| **Z-NG 五官端正** | 三停 모두 absZ < 0.7 & root rollUpMeanZ ≥ 0.3 | attractiveness +0.3 | 神相全編 "五官端正, 必爲美相" — 균형형 美 (v2.9) |

### 4.2 Organ Rules (오관 쌍·조합)

입력: 개별 leaf node 의 ownMeanZ / ownMeanAbsZ. v2.6 cap: \|Δ\| ≤ 0.5. 임계 통일: ≥ 1.0 / ≤ -1.0.

| ID | 조건 | 효과 | 전통 근거 |
|---|---|---|---|
| O-EB1 눈-눈썹 동조 강 | eye & eyebrow 둘 다 leafZ ≥ 1 | leadership +0.5, trust +0.1 | 감찰관+보수관 연합 |
| O-EB2 눈 강·눈썹 약 | eye ≥ 1 & eyebrow ≤ -1 | intelligence +0.5, emotionality +0.5 | 눈빛 있으나 의지 부족 |
| O-EB3 눈썹 강·눈 약 | eyebrow ≥ 1 & eye ≤ -1 | leadership +0.5, trust -0.5 | 고집형 |
| O-NM1 코-입 동조 | nose & mouth 둘 다 leafZ ≥ 1 | wealth +0.5, sociability +0.25 | 심변관+출납관 (재·식 동시) |
| O-NM2 코 강·입 약 | nose ≥ 1 & mouth ≤ -1 | wealth +0.25, sociability -0.5 | 축재형 폐쇄 |
| O-NM3 코 약·입 강 | nose ≤ -1 & mouth ≥ 1 | sociability +0.5, wealth -0.17 | 소비형 외향 |
| O-NC 코-턱 결합 | nose ≥ 1 & chin ≥ 1 | wealth +0.5, leadership +0.5, stability +0.25 | 숭산+항산 |
| O-EM 눈-입 결합 | eye ≥ 1 & mouth ≥ 1 | sociability +0.33 | 감찰관+출납관 — sociability 전용 축소 (v2.9). 美 부분은 O-MM/O-EM2 로 분리 |
| O-FB 이마-눈썹 결합 | forehead ≥ 1 & eyebrow ≥ 1 | leadership +0.5, intelligence +0.25 | 상정 기세 |
| O-CK 광대 강 | cheekbone leafZ ≥ 1 | leadership +0.5, wealth +0.19 | 태·화산 권위 |
| O-CB 광대 약 | cheekbone leafZ ≤ -1 | leadership -0.5, sociability +0.3, attractiveness +0.3 | 부드러운 인상 |
| O-CKN 광대+코 동반 강 | cheekbone & nose 둘 다 ≥ 1 | wealth +0.5, leadership +0.31 | |
| O-CKC 광대+턱 동반 강 | cheekbone & chin 둘 다 ≥ 1 | leadership +0.5, stability +0.31 | |
| O-CKF 광대+이마 동반 강 | cheekbone & forehead 둘 다 ≥ 1 | leadership +0.5, intelligence +0.5 | |
| O-PH1 인중 짧음 | philtrum leafZ ≤ -1 | libido +0.5, sensuality +0.33 (age≥50 추가 감점 별도) | 생식궁 |
| O-PH2 인중 긺 | philtrum leafZ ≥ 1 | stability +0.25, trust +0.5 | 신중 |
| O-CH 턱 강 | chin leafZ ≥ 1 | leadership +0.5, stability +0.15 | 항산 |
| O-DC1 매부리코 살짝 | nose `dorsalConvexity` z ∈ [1.5, 3) | leadership +0.5, wealth +0.21 | |
| O-DC2 코 등선 살짝 오목 | nose `dorsalConvexity` z ∈ (-3, -1.5] | sensuality +0.5, emotionality +0.3 | |
| O-NF1 비전두각 큼 | nose `nasofrontalAngle` z ≥ 1.5 | intelligence +0.5, trust +0.5 | |
| O-NF2 비전두각 작음 | nose `nasofrontalAngle` z ≤ -1.5 | leadership +0.5, stability -0.3 | |
| **O-MM 美目流盼** | eye leafZ ≥ 1 & `eyeCanthalTilt` z ∈ [0.3, 2.0] | attractiveness +0.4 | 麻衣相法 "目如秋水, 媚生於目" — 桃花眼 (v2.9) |
| **O-EM2 眉目清秀** | eye ≥ 1 & eyebrow ≥ 0.5 & `eyebrowTiltDirection` z ≥ -0.5 | attractiveness +0.3 | 神相全編 "眉清目秀, 萬人之上" (v2.9) |
| **O-RL 朱唇小口** | mouth `lipFullnessRatio` z ≥ 0.8 & `mouthWidthRatio` z ∈ [-1.0, 0.3] | attractiveness +0.3 | 麻衣相法 "唇如塗朱, 口如櫻桃" (v2.9) |
| **O-CKE 顴骨突過** | cheekbone leafZ ≥ 1.5 | attractiveness -0.3 | 麻衣相法 "顴骨高聳露骨, 神色不和" (v2.9) |
| **O-EZ 目偏不正** | eye absZ ≥ 1.5 & signed leafZ ≤ -0.5 | attractiveness -0.3 | 神相全編 "目陷偏者, 形不和, 神不全" (v2.9) |

### 4.3 Palace Overlay Rules (십이궁 시너지)

십이궁은 `PhysiognomyNode.palaces` 태그로 노드에 부여되어 있음. 여러 노드에 같은 궁이 걸리면 **복합 시너지**.

| ID | 궁 조합 | 조건 | 효과 |
|---|---|---|---|
| P-01 재백+전택 | 재백(코)+전택(눈) | nose & eye 둘 다 leafZ ≥ 1 | wealth +0.5, stability +0.15 |
| P-02 관록+천이 | 관록+천이 (둘 다 이마) | forehead leafZ ≥ 1.5 | leadership +0.5, intelligence +0.33 |
| P-03 복덕 cross | 전체 rollUp + 세 zone 모두 비음수 | root rollUpMeanZ ≥ 0.3 & 세 zone signedZ ≥ 0 | trust +0.17 (v2.9: trust 전용. 美 부분은 P-MJ 로 narrowing) |
| P-04 형제궁 | 형제(눈썹) | eyebrow leafZ ≥ 1 & leafAbsZ ≥ 1.5 | sociability +0.5, trust +0.3 |
| P-05 남녀궁 | 남녀(눈 아래) | eye leafZ ≥ 1 & lower zone signedZ ≥ 0 | libido +0.5, emotionality +0.25, sociability +0.15 |
| P-06 처첩궁 | 처첩(눈꼬리) | eye absZ ≥ 1 & `eyeCanthalTilt` z ≥ 1 | sensuality +0.5, attractiveness +0.25, emotionality +0.15 |
| P-07 질액궁 | 질액(산근=코뿌리) | nose absZ ≥ 1.5 | stability -0.5 (체질 부조화) |
| P-08 천이궁 | 천이(이마 양옆) | forehead leafZ ≥ 1 & root rollUpMeanAbsZ ≥ 0.5 | leadership +0.5, stability +0.2, intelligence +0.5 |
| P-09 명궁 넓음 | glabella | glabella leafZ ≥ 1 | wealth +0.5, stability +0.2, leadership +0.3 |
| P-09B 명궁 좁음 | glabella | glabella leafZ ≤ -1 | emotionality +0.5, intelligence +0.3, stability -0.3 |
| **P-MJ 印堂明潤** | 명궁(glabella) | glabella leafZ ≥ 0.7 | attractiveness +0.3 — 印堂은 一身之主, 명윤하면 神氣 발현 (v2.9) |

### 4.4 Signed vs AbsZ 사용 규칙 — 요약

| 축 | 용도 | 예시 |
|---|---|---|
| ownMeanZ | 방향 (플러스면 큼/강함) | 눈이 ownMeanZ ≥ 1 → sociability + |
| ownMeanAbsZ | 편차 강도 (얼마나 특이한가) | 눈 abs ≥ 1.5 → distinctiveness 효과 |
| rollUpMeanZ | zone/root 통합 방향 | 상정 우세 판정 |
| rollUpMeanAbsZ | zone 통합 강도 | 하정 distinctive 감정 |

---

## 5. Gender / Age / Lateral 축

### 5.1 Gender Delta (node 레벨)

Node 단위 delta 적용:

| Attribute | Node | Male Δ | Female Δ | 비고 |
|---|---|---|---|---|
| wealth | nose | +0.05 | -0.05 | 남=코 가중 ↑ |
| wealth | mouth | -0.05 | +0.05 | 여=입 가중 ↑ |
| leadership | chin | +0.05 | -0.05 | |
| leadership | eye (canthalTilt 강) | -0.05 | +0.05 | |
| sensuality | mouth | -0.05 | +0.05 | |
| sensuality | eye | +0.05 | -0.05 | |
| libido | nose | +0.05 | -0.05 | |
| libido | mouth | -0.05 | +0.05 | |
| attractiveness | face (taper) | -0.05 | +0.05 | 여 V라인 선호 |
| attractiveness | chin | +0.05 | 0 | 남 턱선 |

Delta 는 §2.2 base 가중치에 합산 후 row 재정규화.

### 5.2 Age Rules (50+)

50+ 전용 규칙 4 개:

| ID | 조건 (50+ 전용) | 효과 |
|---|---|---|
| A-01 하정 약화 보정 | lower.rollUpMeanZ ≤ -1 | libido -1.0, sensuality -0.5 (노화 normal) |
| A-02 상정 유지 우수 | upper.rollUpMeanZ ≥ 0.5 | intelligence +1.0, stability +0.5 |
| A-03 입꼬리 유지 | mouth.ownMeanZ ≥ 0.5 (age-adjusted) | attractiveness +1.5, stability +1.0 |
| A-04 전반 이완 | face.rollUpMeanZ ≤ -1 | emotionality +0.5 (원숙), attractiveness -1.0 |

### 5.3 Lateral Flag Rules (3 개)

측면 metric 은 이미 node 에 흡수되므로 별도 rule 불필요. **flag 기반만** 유지:

| ID | 조건 | 효과 |
|---|---|---|
| L-AQ 매부리 | aquilineNose flag | leadership +1.5, wealth +0.5, stability -0.3 |
| L-SN 들창 | snubNose flag | sociability +1.0, attractiveness +0.5 (youthful) |
| L-EL E-line 전돌 | upperLipEline ≥ 1 & lowerLipEline ≥ 1 (이미 mouth.ownZ 에 반영되므로 추가 +0.5 만) | sensuality +0.5, libido +0.5 |

※ L-EL 은 이중계상 위험 있어 **effect 크기를 최소화** (mouth.ownZ 에 이미 반영된 부분과 중복 방지).

---

## 6. Normalize 재보정

### 6.1 영향 평가

v9 (rank-aware + global percentile blend 60/40) 의 핵심 자산:
- `_attrQuantilesMale` / `_attrQuantilesFemale` — 21-point CDF per attribute
- blend 공식
- 5~10 mapping

**재보정 필요한 것**: quantile table 만. 이유: raw_attr_score 의 분포가 바뀐다 (규칙 개수·강도가 달라졌으므로).

**유지 가능한 것**: blend 공식(60 rank + 40 global), 5~10 mapping.

### 6.2 재보정 절차 (3D 에서 실행)

1. 기존 Monte Carlo harness (`test/calibration_test.dart`) 를 신규 `attribute_derivation.dart` 에 연결.
2. 10,000 회 synthetic sample (기존 방식 동일) → 신규 raw_attr_score 분포 수집.
3. gender 별 21-point quantile 재계산.
4. 기존 테이블과 diff — 속성별 mean/median shift 기록.
5. blend ratio 검증: within-face spread 최소 3.0 유지 보장되면 60/40 유지, 아니면 튜닝.

---

## 7. 신규 파일 스켈레톤

### 7.1 파일 구성

```
lib/domain/services/
  attribute_derivation.dart     # 5-stage pipeline 구현 (weight matrix + rules)
  physiognomy_scoring.dart      # NodeScore tree 입력 제공
```

### 7.2 공개 API 시그니처

```dart
/// Stage 1-5 pipeline 전체를 수행. 출력은 raw attribute score (미정규화).
Map<Attribute, double> deriveAttributeScores({
  required NodeScore tree,           // Phase 2 scoreTree() 결과
  required Gender gender,
  required bool isOver50,
  required bool hasLateral,
  Map<String, bool> lateralFlags = const {},
});

/// 디버깅/리포트용 — 각 stage 의 기여도 분해.
class AttributeBreakdown {
  final Map<Attribute, double> base;          // §2 linear
  final List<TriggeredRule> zoneRules;        // §4.1
  final List<TriggeredRule> organRules;       // §4.2
  final List<TriggeredRule> palaceRules;      // §4.3
  final List<TriggeredRule> ageRules;         // §5.2
  final List<TriggeredRule> lateralRules;     // §5.3
  final Map<Attribute, double> distinctiveness; // §2.3
  final Map<Attribute, double> total;
}

AttributeBreakdown deriveAttributeScoresDetailed({...});
```

`TriggeredRule` 타입은 `attribute_derivation.dart` 에 정의.

### 7.3 내부 구조 (섹션 분할)

1. Types (`_NodeWeight`, `_ZoneRule`, `_OrganRule`, `_PalaceRule`, `_AgeRule`, `_LateralFlagRule`, `AttributeBreakdown`)
2. `_weightMatrix` (§2.2, const)
3. `_genderDelta` (§5.1, const)
4. `_distinctivenessRules` (§2.3)
5. `_zoneRules` / `_organRules` / `_palaceRules` / `_ageRules` / `_lateralFlagRules`
6. Stage 함수 × 5 + `deriveAttributeScores` orchestrator
7. (선택) AttributeBreakdown 생성 헬퍼

예상 LOC: 650–750.

---

## 8. Caller 연결

`deriveAttributeScores()` 를 호출하는 파일:

| 파일 | 호출 방식 |
|---|---|
| `domain/models/face_analysis.dart` | `deriveAttributeScores(tree, ...)` → `normalizeAllScores` |
| `domain/services/score_calibration.dart` (×2) | Monte Carlo quantile 생성 시 동일 경로 |

`normalizeAllScores` / `normalizeScore` 시그니처는 고정. quantile 테이블 재생성만으로 분포 변경 흡수.

---

## 9. 실행 단계

### Phase A — 구현 (단일 PR 권장)
1. `attribute_derivation.dart` 작성 (§2–§5 구현)
2. `test/attribute_derivation_test.dart` — 각 stage 독립 테스트 + 통합 테스트
3. Breakdown 디버그 경로 테스트

### Phase B — caller 연결 + quantile 재보정
1. `face_analysis.dart` 호출 연결
2. `score_calibration.dart` ×2 호출 연결
3. `calibration_test.dart` 실행 → `_attrQuantilesMale/Female` 테이블 재생성
4. Report UI 연결 확인

### Phase C — 자체 품질 검증 & 문서 정리

검증 대상은 **엔진 자체 품질**. 자체 기준(§3D)으로만 평가.

1. **분포 건전성**: Monte Carlo 10,000 sample 로 속성별 분포 확인
   - within-face spread ≥ 3.0 점 (강-약 최소 간격) 유지
   - 상위/하위 saturation (95%↑가 10점 or 5%↓가 5점) 없음
   - gender 별 평균·표준편차 reasonable range
2. **Stage 기여 균형**: AttributeBreakdown 으로 base/zone/organ/palace/distinctiveness 각 stage 가 **dead 하지 않음** 확인 (한 stage 가 무시할 만하면 규칙 재설계)
3. **Edge case**: empty metric, lateral 없음, age over50, unsupported ear 노드 등 정상 flow 확인
4. **관상 정합성 sanity**: 10 개 "프로토타입 얼굴" (예: "이상적 재물운 상" = 코 z=2 / 광대 z=1.5 / 턱 z=1) 입력 시 해당 속성이 실제 상위에 오는지 내부 일관성 점검
5. `docs/engine/TAXONOMY.md` §3 노드별 metric/rule snapshot 갱신
6. CLAUDE.md attribute engine 섹션 현행화

---

## 10. 오픈 이슈 (대부님 확답 필요)

관상 전통·부위 가중치·십이궁 해석은 §12 research 로 확정했으므로 제거. 남은 이슈는 **구현 전략·UI 노출 여부** 만.

| # | 질문 | 대부님 확정 (2026-04-18) |
|---|---|---|
| Q1 | `AttributeBreakdown` 디버그 API 를 UI 리포트에 노출? | **부분 노출**. 리포트 상세에 속성별 "상세보기" 토글 → top-3 기여 요인 표시. |
| Q2 | `_attrQuantilesMale/Female` 재생성 필요? | **예**. 트리 엔진 분포 기준으로 재생성. |
| Q3 | 3B 구현을 단일 PR vs 분할 PR? | **단일 PR**. |
| Q4 | 회귀 검증 기준? | 엔진 자체 품질 기준(§Phase C)으로만 평가. |

---

## 11. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 신규 분포의 within-face spread 부족 (≥ 3.0 점 미달) | Monte Carlo 결과 보고 blend ratio(60/40) 조정 또는 §2.3 distinctiveness 가산 강도 튜닝 |
| 특정 stage 가 사실상 dead (기여 ≈ 0) | AttributeBreakdown 관측 → 규칙 임계값 낮추거나 해당 stage 규칙 재설계 |
| glabella metric 부재로 palace overlay 명궁 규칙 불가 | v1 에서 skip, Phase 4 에서 `glabellaWidth` 신규 metric 도입 시 활성화 |
| caller 연결 중 빌드 깨짐 | Phase B 는 단일 커밋 범위 내에서 `deriveAttributeScores` 도입 → caller 전환 순으로 진행. 중간 상태 커밋 금지. |

---

## 12. Research 근거 (v0.2 가중치 확정 자료)

§2.2 매트릭스와 §4.3 Palace overlay 의 모든 숫자는 아래 자료 교차검증으로 도출.

### 12.1 전통 관상 고전
- **麻衣相法(마의상법)** — 북송 陳摶 저. 재백궁(코)·감찰관(눈)·출납관(입) 체계 원형.
- **柳莊相法(유장상법)** — 명 袁珙 저. 십이궁 체계 확립.
- **神相全編(신상전편)** — 청대 집성본. 오악·사독 해설.

### 12.2 한국·중국 현대 해설 (교차검증용)

부위별 핵심 근거:

| 부위·개념 | URL | 요지 |
|---|---|---|
| 재백궁=코 | https://www.siminsori.com/news/articleView.html?idxno=76603 | 코 모양별 재물운 전통 해석 |
| 코 관상 종합 | https://www.dkilbo.com/news/articleView.html?idxno=453095 | 코의 재물·신뢰 격언 상세 |
| 십이궁 개요 | http://www.skkuw.com/news/articleView.html?idxno=10698 | 12궁 위치·의미 도표 |
| 관상 기본 | https://www.igimpo.com/news/articleView.html?idxno=63205 | 마의상법 기반 12궁 요약 |
| 관록궁=이마 | https://www.usjournal.kr/news/newsview.php?ncode=1065570289518611 | 이마=리더십·책임감 |
| 광대=사회성 | https://www.dkilbo.com/news/articleView.html?idxno=422626 | "관골은 주로 사회성을 보는 부위" |
| 노복궁=턱 | https://tgkim.net/15 | 턱=부하 덕·말년 권위 |
| 명궁=미간 | https://www.asiatoday.co.kr/kn/view.php?key=20260114010006805 | 인당=지혜·총명 판별 |
| 눈=지성/감정 | https://encykorea.aks.ac.kr/Article/E0004873 | 한국 관상학의 눈 5할 비중 |
| 눈=9할 | http://www.gimhaenews.co.kr/news/articleView.html?idxno=1005 | "얼굴이 천 냥이면 눈이 구백 냥" |
| 입 출납관 | https://www.kyeongin.com/article/1619154 | 입=소통·정화장치·구덕 |
| 인중 | https://www.igimpo.com/news/articleView.html?idxno=66626 | 인중=자녀·정력·부하 덕 |
| 색욕 관상 | https://m.joongdo.co.kr/view.php?key=20180513010004843 | 눈·입술·뺨과 색욕 |
| 마의상법 인용 | https://www.threads.com/@bro.analyzer/post/DJ3m0bNBGYR/ | 입술·눈매 색욕 원문 |
| 신뢰 코 해석 | https://www.siminsori.com/news/articleView.html?idxno=75708 | 마의상법 "코 바름=사람됨" |
| 입술 신용 | https://www.dkilbo.com/news/articleView.html?idxno=353957 | 뚜렷한 입술선=정직·신용 |
| 12궁 상세 | https://m.cafe.daum.net/readandchange/an0E/91 | Humanitas 십이궁 도표 |
| 오악 해설 | https://www.usjournal.kr/news/newsview.php?ncode=1065606818621067 | 형산·태산·화산·숭산·항산 |
| 오관 해설 | https://www.sajuforum.com/01forum/sang_face/04_sang_face.php | 보수·감찰·심변·출납·채청관 |
| 사독 해설 | https://www.kyeongin.com/view.php?key=20180719010006960 | 강·하·회·제 유통 평가 |

### 12.3 현대 학술 연구 (매력·대칭성 교차검증)
- **Pallett, Link, Lee (2010)** — "New 'Golden' Ratios for Facial Beauty." _Vision Research._
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC2814183/
  - 최적 매력 비율: 눈-입 수직 거리 = 얼굴 길이의 36%, 동공 간 거리 = 얼굴 폭의 46%.
  - 전통 삼정 균형(1:1:1) 원리와 정량적으로 수렴 — `attractiveness` 가중치에서 root(0.25 P) + eye(0.35) 조합의 근거.

### 12.4 Research 수행 기록
- 일자: 2026-04-18
- 수행: `document-specialist` 3 병렬 (10 attribute × 5 + 5 / 십이궁·오관·오악·사독)
- 내부 방법론: "(전통 문헌 권위도) × (해당 속성 결정력)" 직관 산정 후 교차검증.
- 출처 불명 해석(예: 귀와 정력 관련 단편 주장) 은 가중치에서 제외.

---

## 연관 문서

- [OVERVIEW.md](../architecture/OVERVIEW.md) — 상위 트리 엔진 설계 (§2)
- [TAXONOMY.md](TAXONOMY.md) — 14-node tree SSOT + 노드별 metric/rule 매칭
- [NORMALIZATION.md](NORMALIZATION.md) — raw → 5~10 정규화 파이프라인
