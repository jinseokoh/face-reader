# 관상 체계 ↔ 현 구현 매칭 도표

**버전**: 1.0
**마지막 업데이트**: 2026-04-18
**기반 문서**: `docs/PHYSIOGNOMY_TAXONOMY.md` v1.0
**역할**: α 옵션(삼정 우선 tree)의 각 노드에 대해 **현재 코드베이스의 metric/attribute/
rule/UI 자원이 얼마나 준비되어 있는지** 매핑하고 갭을 드러낸다. 리팩터 우선순위의 근거 자료.

---

## 0. 범례

| 표기 | 의미 |
|---|---|
| ✓ | 측정·reference·규칙·UI 모두 구비 |
| ⚠️ | 일부 준비 (통상 "측정·reference 있으나 규칙 없음") |
| ✗ | 공백 (metric 없음 or Tree 노드 대응 없음) |
| orphan | `computeAll()` 은 계산하나 `metricInfoList` 에 없어 z-score 이후 단계로 흐르지 않음 |

**자원 4축**
1. **Metric**: `face_metrics.dart::computeAll()` 결과 키
2. **Reference**: `face_reference_data.dart::metricInfoList` 의 mu/sd 엔트리
3. **Rule**: `attribute_derivation.dart` 의 규칙에서 참조
4. **UI**: 리포트 화면에 노출

---

## 1. 밸런스 진단

### 1.1 노드별 metric 수 집계

| Zone | 노드 | 기존(infoList) | 신규(orphan) | Lateral | 합 | 밸런스 |
|---|---|---|---|---|---|---|
| 상정 | 이마 | 1 (upperFaceRatio) | 1 (foreheadWidth) | 0 | **2** | 부족 |
| 상정 | 미간 | 0 | 0 | 0 | **0** | 공백 |
| 상정 | 눈썹 | 2 (thickness, browEyeDist) | 4 (length/tilt/curve/spacing) | 0 | **6** | 과집중 |
| 중정 | 눈 | 3 (intercanthal, fissure, canthalTilt) | 1 (eyeAspect) | 0 | **4** | OK |
| 중정 | 코 | 2 (nasalWidth, nasalHeight) | 1 (bridge) | 4 | **7** | OK (측면 포함) |
| 중정 | 광대 | 0 | 1 (cheekboneWidth) | 0 | **1** | 부족 |
| 중정 | 귀 | 0 | 0 | 0 | **0** | 공백 (기술 제약) |
| 하정 | 인중 | 1 (philtrumLength) | 0 | 0 | **1** | 부족 |
| 하정 | 입 | 3 (width, corner, fullness) | 1 (upperVsLower) | 3 | **7** | OK |
| 하정 | 턱 | 3 (gonial, lowerRatio, fullness) | 1 (chinAngle) | 1 (facialConvexity) | **5** | OK |
| root | 얼굴전체 | 3 (aspect, taper, midRatio) | 0 | 0 | **3** | OK |

### 1.2 밸런스 결론

- **과집중**: 눈썹(6) — 신규 4개 한 번에 투입됨
- **공백**: 미간(0), 귀(0)
- **부족**: 이마(2), 광대(1), 인중(1)

대부님이 우려한 "부위 쏠림" 실증: 눈썹에 신규 4개 몰렸음. 코는 7개지만 정면 3 + 측면 4 로 축이 분리되어 과집중 아님.

---

## 2. 노드별 상세 매칭

### 2.1 상정 · 이마 (forehead)

| 자원 | 현황 | 상태 |
|---|---|---|
| Metric `upperFaceRatio` | 계산 ✓ / info ✓ / 규칙 0 / UI ✓ | ⚠️ 해석 없음 |
| Metric `foreheadWidth` | 계산 ✓ / info ✗ / 규칙 ✗ / UI ✗ | orphan |
| 이마 관련 규칙 | 없음 | ✗ |

**갭**: 관록궁·천이궁·형산이 걸린 관상학 상위 개념인데 **규칙 0개**. 지성·초년운·사회적 성취 해석 부재.

---

### 2.2 상정 · 미간 (glabella)

| 자원 | 현황 | 상태 |
|---|---|---|
| Metric | 없음 (`browSpacing` 이 간접 지표 후보지만 orphan) | ✗ |

**갭**: **명궁(운명 핵심)**이 측정 공백. `glabellaWidth` 신규 metric 후보. MediaPipe 정면 mesh 에서 측정 타당성 검토 필요 (landmark 9 주변 폭·매끈함).

---

### 2.3 상정 · 눈썹 (eyebrow)

| 자원 | 현황 | 상태 |
|---|---|---|
| `eyebrowThickness` | 계산 ✓ / info ✓ / 규칙 ~10 / UI ✓ | ✓ |
| `browEyeDistance` | 계산 ✓ / info ✓ / 규칙 ~11 / UI ✓ | ✓ |
| `eyebrowLength` | orphan | ✗ |
| `eyebrowTiltDirection` | orphan | ✗ |
| `eyebrowCurvature` | orphan | ✗ |
| `browSpacing` | orphan | ✗ |

**갭**: 기존 2개만 해도 규칙 **21개** 집중. 신규 4개 모두 정규화하면 30+ → tree 밸런스 붕괴. 2개만 선별 권장.

---

### 2.4 중정 · 눈 (eye)

| 자원 | 현황 | 상태 |
|---|---|---|
| `intercanthalRatio` | 계산 ✓ / info ✓ / 규칙 ~5 / UI ✓ | ✓ |
| `eyeFissureRatio` | 계산 ✓ / info ✓ / 규칙 ~10 / UI ✓ | ✓ |
| `eyeCanthalTilt` | 계산 ✓ / info ✓ / 규칙 ~11 / UI ✓ | ✓ |
| `eyeAspect` | orphan | ✗ |

**갭**: 해석 밀도 양호. `eyeAspect` 가 쌍꺼풀·눈매 암시하면 감찰관·전택궁 해석 보강 기회.

---

### 2.5 중정 · 코 (nose)

| 자원 | 현황 | 상태 |
|---|---|---|
| Frontal `nasalWidthRatio` | 계산 ✓ / info ✓ / 규칙 ~8 / UI ✓ | ✓ |
| Frontal `nasalHeightRatio` | 계산 ✓ / info ✓ / 규칙 ~8 / UI ✓ | ✓ |
| Frontal `noseBridgeRatio` | orphan | ✗ |
| Lateral `nasofrontalAngle` | 계산 ✓ / lateralInfo ✓ / 규칙 **1** / UI ✓ | ⚠️ 저활용 |
| Lateral `nasolabialAngle` | 계산 ✓ / lateralInfo ✓ / 규칙 3 / UI ✓ | ✓ |
| Lateral `noseTipProjection` | 계산 ✓ / lateralInfo ✓ / 규칙 1 / UI ✓ | ⚠️ |
| Lateral `dorsalConvexity` | 계산 ✓ / lateralInfo ✓ / **연속규칙 0** / UI flag | ⚠️ **dark metric** |
| Flag `aquilineNose` | ✓ / 규칙 4 (LAT-AQ1~R4) / UI ✓ | ✓ |
| Flag `snubNose`/`saddleNose`/`flatNose` | flag ✓ / 규칙 일부 | ⚠️ |

**갭**:
- `dorsalConvexity` z ∈ [1, 3) 구간 규칙 없음 — **가장 시급한 dark metric**
- `nasofrontalAngle` 규칙 1개뿐 — 산근(질액궁) 해석 여지 큼
- `noseBridgeRatio` 고아 — `nasalHeightRatio` 와 중복 여부 검증 필요

---

### 2.6 중정 · 광대 (cheekbone)

| 자원 | 현황 | 상태 |
|---|---|---|
| `cheekboneWidth` | orphan | ✗ |
| `faceTaperRatio` (간접) | 계산 ✓ / info ✓ / 규칙 ~4 / UI ✓ | ⚠️ (광대 전용 아님) |

**갭**: 오악 태산·화산(좌우 광대) 독립 노드인데 정식 metric 없음. `cheekboneWidth` 정규화 + 좌우 비대칭 metric 후보.

---

### 2.7 중정 · 귀 (ear)

| 자원 | 현황 | 상태 |
|---|---|---|
| Metric | 없음 (MediaPipe 정면 mesh 제약) | ✗ |

**권장**: v1.0 에서 **명시적 미지원 선언**. PHYSIOGNOMY_TAXONOMY.md 에 기록.

---

### 2.8 하정 · 인중 (philtrum)

| 자원 | 현황 | 상태 |
|---|---|---|
| `philtrumLength` | 계산 ✓ / info ✓ / 규칙 ~8 / UI ✓ | ✓ |

**갭**: 단일 metric 으로 자녀·생식·수명 해석은 빈약. 깊이·명확도 측정은 정면 mesh 로 불가.

---

### 2.9 하정 · 입 (mouth)

| 자원 | 현황 | 상태 |
|---|---|---|
| Frontal `mouthWidthRatio` | 계산 ✓ / info ✓ / 규칙 ~6 / UI ✓ | ✓ |
| Frontal `mouthCornerAngle` | 계산 ✓ / info ✓ / 규칙 **~20** / UI ✓ | ✓ 과집중 |
| Frontal `lipFullnessRatio` | 계산 ✓ / info ✓ / 규칙 **~20+** / UI ✓ | ✓ 과집중 |
| Frontal `upperVsLowerLipRatio` | orphan | ✗ |
| Lateral `upperLipEline` | 계산 ✓ / lateralInfo ✓ / 규칙 3 / UI ✓ | ✓ |
| Lateral `lowerLipEline` | 계산 ✓ / lateralInfo ✓ / 규칙 3 / UI ✓ | ✓ |
| Lateral `mentolabialAngle` | 계산 ✓ / lateralInfo ✓ / 규칙 2 / UI ✓ | ✓ |

**갭**:
- `mouthCornerAngle`, `lipFullnessRatio` 규칙 과집중 — tree 스코프로 분산 필요
- `upperVsLowerLipRatio` 고아 — 상하순 균형 관상학 개념 존재

---

### 2.10 하정 · 턱 (chin/jaw)

| 자원 | 현황 | 상태 |
|---|---|---|
| `gonialAngle` | 계산 ✓ / info ✓ / 규칙 ~10 / UI ✓ | ✓ |
| `lowerFaceRatio` | 계산 ✓ / info ✓ / **규칙 0** / UI ✓ | ⚠️ |
| `lowerFaceFullness` | 계산 ✓ / info ✓ / **규칙 0** / UI ✓ | ⚠️ |
| `chinAngle` | orphan | ✗ |
| Lateral `facialConvexity` | 계산 ✓ / lateralInfo ✓ / 규칙 2 / UI ✓ | ✓ |
| `faceTaperRatio` (간접) | 계산 ✓ / info ✓ / 규칙 ~4 / UI ✓ | ✓ |

**갭**: `chinAngle` 정규화 시 말년운(항산·노복궁) 해석 강화. `lowerFaceRatio` 도 규칙 0개.

---

### 2.11 root · 얼굴 전체

| 자원 | 현황 | 상태 |
|---|---|---|
| `faceAspectRatio` | 계산 ✓ / info ✓ / 규칙 ~3 / UI ✓ | ✓ |
| `faceTaperRatio` | 계산 ✓ / info ✓ / 규칙 ~4 / UI ✓ | ✓ |
| `midFaceRatio` | 계산 ✓ / info ✓ / **규칙 0** / UI ✓ | ⚠️ |
| Face shape (Track 1 classifier) | ✓ 완료 | ✓ |

---

## 3. 🔥 가장 큰 공백 — 삼정 비율 규칙 부재

`upperFaceRatio` / `midFaceRatio` / `lowerFaceRatio` **세 metric 모두 규칙 0개**.

관상학 고전 3권 공통 좌표계의 핵심인 **삼정 해석이 완전 부재**. 이것이 "flat 구조가 관상학 백그라운드와 어긋나 있다"는 대부님 직관의 정량적 증거.

**우선순위 P0**: 삼정 균형 규칙 추가.

예시:
- 상정 길면 지성·초년운·관록 +
- 중정 길면 중년 활동력·재물(재백) +
- 하정 길면 말년 안정·인내 +
- 삼정 1:1:1 균형이면 "조화" 보너스

---

## 4. 고아 10개 처분 권장

| Metric | 노드 | 관상학 중요도 | 판별력 | 처분 |
|---|---|---|---|---|
| eyebrowLength | 눈썹 | 중 | 미검증 | 보류 (검증 후) |
| eyebrowTiltDirection | 눈썹 | 상 | 미검증 | ⭐ 정규화 후보 |
| eyebrowCurvature | 눈썹 | 상 | 미검증 | ⭐ 정규화 후보 |
| browSpacing | 미간 | 중 (명궁 간접) | 미검증 | 보류 (검증 후) |
| eyeAspect | 눈 | 상 (쌍꺼풀 암시) | 미검증 | ⭐ 정규화 후보 |
| upperVsLowerLipRatio | 입 | 중 | 미검증 | ⭐ 정규화 후보 |
| chinAngle | 턱 | 상 (말년·결단력) | 미검증 | ⭐ 최우선 정규화 |
| foreheadWidth | 이마 | 상 (지성) | 미검증 | ⭐ 정규화 후보 |
| cheekboneWidth | 광대 | 상 (권위) | 미검증 | ⭐ 정규화 후보 |
| noseBridgeRatio | 코 | 중 | nasalHeight 중복 의심 | 보류 (중복 검증) |

**정규화 = `metricInfoList` 추가 + 6 ethnicity × 2 gender mu/sd + 규칙 1~3개 연결.**

**추천 7개 정규화 (⭐):** chinAngle · foreheadWidth · cheekboneWidth · eyeAspect · eyebrowCurvature · eyebrowTiltDirection · upperVsLowerLipRatio.

**보류 3개:** eyebrowLength · browSpacing · noseBridgeRatio.

### 4.1 Phase 1B 결정 (2026-04-18)

- ⭐ 7개 **정규화 완료**: `metricInfoList` 추가 + 6 인종 × 2 성별 reference 엔트리 84건 추가.
  East Asian MediaPipe-추정값을 6 인종에 동일 fallback (lateral 패턴).
- 보류 3개는 **tree 밖 classifier 전용 feature** 로 재분류.
  사유: Track 1 TFLite classifier (`face_shape_classifier.dart`) 가 28-feature
  입력으로 이 3개를 사용 중 — 제거 시 Track 1 재학습 필요 (세션 범위 초과).
  `computeAll()` 는 이 3개를 계속 계산하되 tree·rule·UI 에는 노출하지 않음.
- 검증: `flutter/test/physiognomy_tree_sanity_test.dart` 11 test 모두 통과.

---

## 5. 리팩터 우선순위 로드맵

| # | 액션 | 노드 | 효과 | 난이도 |
|---|---|---|---|---|
| **P0** | 삼정 규칙 도입 (upper/mid/lowerFaceRatio) | root·삼정 | 최대 공백 해소 | 중 |
| **P1** | Tree 자료구조 + 노드 스코프 규칙 시스템 | 엔진 전반 | 과집중 구조 해소 | 상 |
| P2 | `chinAngle` 정규화 + 턱 규칙 | 턱 | 말년 해석 확립 | 하 |
| P3 | `foreheadWidth` + 이마 규칙 3~4개 | 이마 | 지성·관록궁 해석 | 중 |
| P4 | `cheekboneWidth` + 광대 규칙 | 광대 | 오악 완성 | 하 |
| P5 | `dorsalConvexity` 연속 규칙 | 코 | dark metric 제거 | 하 |
| P6 | `eyeAspect` + `upperVsLowerLipRatio` 정규화 | 눈·입 | 해석 풍부화 | 하 |
| P7 | 눈썹 orphan 4개 중 2개 선별 정규화 | 눈썹 | 밸런스 유지 확장 | 중 |
| P8 | 미간 측정 타당성 검토 + 신규 metric | 미간 | 명궁 해석 착수 | 중 |
| P9 | 귀 노드 v1.0 미지원 문서화 | 귀 | 투명성 | 하 |
| P10 | 오관·오악·사독·십이궁 tag enum 도입 | 전반 | 해석 풍부화 | 중 |

---

## 6. 대부님 결정 (2026-04-18 확정)

1. **고아 7 정규화**: 7개 정식화 + 3개(eyebrowLength·browSpacing·noseBridgeRatio)는
   tree 밖 classifier 전용으로 재분류. **Phase 1B 완료**.
2. **귀 노드**: v1.0 미지원 선언 확정. `unsupported: true` 태그 + `metricIds: []`.
3. **규칙 시스템**: `attribute_derivation.dart` — node-scoped 5-stage pipeline 체계.
4. **10 attribute 체계**: **(b) 완전 재설계** — 10 attribute 를 tree node score 의
   파생 지표로 재정의. Phase 3 에서 실행.

---

## 7. 차후 갱신 규칙

- 새 노드/metric 추가 시 1.1 밸런스 표 먼저 업데이트 → 그 다음 코드
- 정규화 완료 시 해당 metric 의 orphan → ✓ 전환을 표에 반영
- 규칙 밀도(과집중) 갱신은 `attribute_derivation.dart` 변경 커밋에서 동시 진행

---

## 연관 문서

- [PHYSIOGNOMY_TAXONOMY.md](PHYSIOGNOMY_TAXONOMY.md) — 14-node tree SSOT
- [ATTRIBUTE_NODE_MAPPING.md](ATTRIBUTE_NODE_MAPPING.md) — weight matrix + rule 명세
- [ARCHITECTURE.md](ARCHITECTURE.md) — 상위 아키텍처
- [NORMALIZATION.md](NORMALIZATION.md) — 정규화 파이프라인
