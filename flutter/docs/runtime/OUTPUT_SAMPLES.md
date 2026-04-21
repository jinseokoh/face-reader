# 얼굴 분석 파이프라인 출력 예시

**마지막 업데이트**: 2026-04-18

본 문서는 `analyzeFaceReading()` 파이프라인의 출력 형태를 샘플 데이터와 함께 설명한다.

---

## 1. 분석 파이프라인 개요

```
카메라/앨범 캡처 (정면 5프레임 평균 + 3/4 측면 5프레임 평균)
  ↓
MediaPipe Face Mesh 468 랜드마크
  ↓
FaceMetrics.computeAll()          → frontal 17 raw metrics
LateralFaceMetrics.computeAll()   → lateral 8 raw metrics (옵션)
  ↓
Z-score vs (ethnicity x gender) reference
  ↓
scoreTree(zMap)                   → 14-node NodeScore tree
  ↓
deriveAttributeScores(tree, ...)  → 10 attribute raw scores (5-stage pipeline)
  ↓
normalizeAllScores()              → 5.0~10.0 정규화 점수
  ↓
classifyArchetype()               → primary/secondary archetype + special
  ↓
FaceReadingReport
```

구현: `lib/domain/models/face_analysis.dart` (see `docs/architecture/OVERVIEW.md` §4)

---

## 2. Metric 출력 예시 (동아시아 여성 기준)

17개 frontal metric + 8개 lateral metric. Reference 데이터 진본: `lib/data/constants/face_reference_data.dart`.

| Category | Metric | 측정값 | Mean | SD | Z-score | 판정 |
|---|---|---|---|---|---|---|
| face | faceAspectRatio | 1.28 | 1.29 | 0.07 | -0.14 | 평균 |
| face | faceTaperRatio | 0.81 | 0.79 | 0.05 | 0.40 | 평균 |
| face | upperFaceRatio | 0.32 | 0.31 | 0.04 | 0.25 | 평균 |
| face | midFaceRatio | 0.29 | 0.30 | 0.03 | -0.33 | 평균 |
| face | lowerFaceRatio | 0.39 | 0.39 | 0.05 | 0.00 | 평균 |
| face | gonialAngle | 145.0 | 141.0 | 6.0 | 0.67 | 약간 넓은 턱각 |
| eyes | intercanthalRatio | 0.27 | 0.26 | 0.02 | 0.50 | 약간 넓음 |
| eyes | eyeFissureRatio | 0.21 | 0.20 | 0.025 | 0.40 | 평균 |
| eyes | eyeCanthalTilt | 7.0 | 5.0 | 4.0 | 0.50 | 약간 올라감 |
| eyes | eyebrowThickness | 0.036 | 0.034 | 0.005 | 0.40 | 평균 |
| eyes | browEyeDistance | 0.155 | 0.150 | 0.020 | 0.25 | 평균 |
| nose | nasalWidthRatio | 0.88 | 0.89 | 0.10 | -0.10 | 평균 |
| nose | nasalHeightRatio | 0.31 | 0.30 | 0.03 | 0.33 | 평균 |
| mouth | mouthWidthRatio | 0.40 | 0.39 | 0.05 | 0.20 | 평균 |
| mouth | mouthCornerAngle | 4.5 | 3.0 | 5.0 | 0.30 | 평균 |
| mouth | lipFullnessRatio | 0.13 | 0.12 | 0.025 | 0.40 | 평균 |
| mouth | philtrumLength | 0.085 | 0.090 | 0.020 | -0.25 | 평균 |

### Z-score 판정 체계

| |z| 범위 | 판정 |
|---|---|
| < 0.5 | 평균 |
| 0.5 ~ 1.0 | 약간 큼/작음 |
| 1.0 ~ 2.0 | 큼/작음 |
| >= 2.0 | 매우 큼/작음 |

---

## 3. FaceReadingReport 주요 필드

```dart
class FaceReadingReport {
  // v3 (2026-04-18): Hive 에 capture 만 저장. 해석(nodeScores/attributes/
  // rules/archetype) 은 load 시 현재 엔진으로 재계산. 엔진 버전 업그레이드
  // 가 스토리지에 영향 없음.
  static const int kReportSchemaVersion = 1;
  final int schemaVersion;

  // ─── Persistent (Hive 에 저장) ───
  // Track 1 — 얼굴형
  FaceShape faceShape;             // oval/oblong/round/square/heart/unknown
  String? faceShapeLabel;          // ML 분류기 English 원본
  double? faceShapeConfidence;

  // Metric 원본
  Map<String, MetricResult> metrics;             // 17 frontal
  Map<String, MetricResult>? lateralMetrics;     // 8 lateral (옵션)
  Map<String, bool>? lateralFlags;

  // ─── Derived (load 시 재계산) ───
  Map<Attribute, AttributeEvidence> attributes;  // 10개 속성 상세
  List<RuleEvidence> rules;                      // 발동 rule (v2.5 기준)
  Map<String, NodeEvidence> nodeScores;          // 14-node tree scores
  ArchetypeResult archetype;                     // primary/secondary/special

  // convenience getter
  Map<Attribute, double> get attributeScores;    // normalized 5.0~10.0

  // Track 3 — 측면
  Map<String, double>? lateralMetrics;
  Map<String, bool>? lateralFlags;               // aquilineNose, snubNose 등

  // Archetype
  ArchetypeResult archetype;                     // primary, secondary, special

  // Demographics
  Gender gender;
  Ethnicity ethnicity;
  AgeGroup ageGroup;
}
```

---

## 4. Attribute 점수 출력 예시

정규화 후 5.0~10.0 범위 (engine v2, 40% within-face rank + 60% global quantile blend).

| Attribute | Korean | 점수 |
|---|---|---|
| wealth | 재물운 | 7.8 |
| leadership | 리더십 | 6.9 |
| intelligence | 통찰력 | 8.2 |
| sociability | 사회성 | 7.1 |
| emotionality | 감정성 | 6.5 |
| stability | 안정성 | 8.5 |
| sensuality | 바람기 | 5.8 |
| trustworthiness | 신뢰성 | 7.4 |
| attractiveness | 매력도 | 7.6 |
| libido | 관능도 | 5.3 |

**기대 통계** (상관 Monte Carlo 20,000 샘플, seed=42, bone/mid latent + 얼굴형 prior):
- top-bottom spread >= 2.0 (rank-minimum 보장)
- 평균 ~ 7.0, 표준편차 ~ 1.2
- 상위 속성 >= 7.0, 상위 saturation(모두 >=9.5) < 5%

---

## 5. Supabase 저장 형태

```json
{
  "id": "uuid",
  "metrics_json": "{...FaceReadingReport JSON...}",
  "source": "camera",
  "ethnicity": "eastAsian",
  "gender": "female",
  "age_group": "twenties",
  "expires_at": "2026-07-18T00:00:00Z",
  "created_at": "2026-04-18T10:01:00Z"
}
```

---

## 연관 문서

- [OVERVIEW.md](../architecture/OVERVIEW.md) — 전체 파이프라인 설계 (§4 Runtime Pipeline)
- [HIVE_SCHEMA.md](HIVE_SCHEMA.md) — Hive 저장 포맷 SSOT (v3 capture-only · 17 frontal + 8 lateral key 완전 목록 · 확장 체크리스트)
- [NORMALIZATION.md](../engine/NORMALIZATION.md) — raw → 5~10 정규화 상세
- [PLAN.md](../supabase/PLAN.md) — Supabase 연동 계획
