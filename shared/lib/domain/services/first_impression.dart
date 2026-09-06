/// 3층 — 제품 지표.
///
/// 2층 feature 에 1층의 부호·비중을 곱해 축 원점수를 만들고, AAF 11,800장에
/// 같은 식을 돌려 얻은 분위표(`impression_quantiles.dart`)로 백분위(0~100)를
/// 만든다. 축의 정의는 문헌, 백분위는 실측이다 (APPLE.md §81.2).
///
/// 두 얼굴 지표(§81.3): 닮은 정도 · 첫인상 유사도 · 조화도 · 보완도, 그리고
/// 케미 점수(세 성분의 합, §81.4). 매력 축은 두 얼굴·케미 어디에도 쓰지 않는다.
///
/// 이 점수는 실제 성격·능력이 아니라 "얼굴이 그 인상을 형성하는 방향으로
/// 얼마나 나타나는지" 의 모델상 상대 위치다. 정확도·한국인 일치율을 주장하지
/// 않는다.
library;

import 'dart:math';

import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/constants/impression_quantiles.dart';
import 'package:face_engine/data/constants/symmetry_reference.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/impression_features.dart';

const double _kPrimaryWeight = 1.0;
const double _kSecondaryWeight = 0.5;

/// 두 얼굴 지표에 쓰는 축 — 매력 제외.
const List<ImpressionAxis> pairAxes = [
  ImpressionAxis.trust,
  ImpressionAxis.approach,
  ImpressionAxis.dominance,
];

/// 축 원점수 — Σ(부호 × 비중 × feature z). feature 가 없으면 그 항은 건너뛴다.
Map<ImpressionAxis, double> computeImpressionRaw(Map<String, double> features) {
  final out = <ImpressionAxis, double>{
    for (final a in ImpressionAxis.values) a: 0.0,
  };
  for (final link in impressionEvidence) {
    final f = features[link.feature];
    if (f == null) continue;
    final w = link.tier == EvidenceTier.primary
        ? _kPrimaryWeight
        : _kSecondaryWeight;
    out[link.axis] = out[link.axis]! + link.sign * w * f;
  }
  return out;
}

/// 21-point 분위표(p0, p5, …, p100)로 원점수 → 백분위 0~100. 선형 보간.
double percentileFromQuantiles(double raw, List<double> q) {
  if (raw <= q.first) return 0;
  if (raw >= q.last) return 100;
  for (var i = 1; i < q.length; i++) {
    if (raw <= q[i]) {
      final lo = q[i - 1];
      final hi = q[i];
      final t = hi == lo ? 0.0 : (raw - lo) / (hi - lo);
      return ((i - 1) + t) * (100 / (q.length - 1));
    }
  }
  return 100;
}

/// 첫인상 프로필 — 축별 0~100 백분위.
class FirstImpressionProfile {
  final Map<ImpressionAxis, double> percentile;
  final Map<ImpressionAxis, double> raw;

  const FirstImpressionProfile({required this.percentile, required this.raw});

  double operator [](ImpressionAxis a) => percentile[a]!;
}

/// 얼굴 전체 비대칭도(symOverall raw) → 성별 reference 로 z. 대칭 계측이 없으면 null.
double? symmetryOverallZ(Map<String, double>? symmetry, Gender gender) {
  final raw = symmetry?['symOverall'];
  if (raw == null) return null;
  final ref = symmetryReference[gender]!['symOverall']!;
  return (raw - ref.mean) / ref.sd;
}

/// metric z-map → 첫인상 프로필. [symmetryZ] 는 [symmetryOverallZ] 값(없으면 생략).
FirstImpressionProfile computeFirstImpression(
  Map<String, double> zByMetric, {
  required Gender gender,
  required Iterable<String> referenceMetricIds,
  double? symmetryZ,
}) {
  final features = buildImpressionFeatures(zByMetric,
      referenceMetricIds: referenceMetricIds, symmetryZ: symmetryZ);
  final raw = computeImpressionRaw(features);
  final table = impressionQuantiles[gender]!;
  final pct = <ImpressionAxis, double>{
    for (final a in ImpressionAxis.values)
      a: percentileFromQuantiles(raw[a]!, table[a]!),
  };
  return FirstImpressionProfile(percentile: pct, raw: raw);
}

// ─────────────────────────── 두 얼굴 ───────────────────────────

/// 닮은 정도의 영역 분할 — 계측 id 그룹. 부분 점수와 전체 점수가 같은 식.
const Map<String, List<String>> geometryRegions = {
  'outline': [
    'faceAspectRatio',
    'faceTaperRatio',
    'lowerFaceFullness',
    'foreheadWidth',
    'cheekboneWidth',
  ],
  'eyes': [
    'intercanthalRatio',
    'eyeFissureRatio',
    'eyeCanthalTilt',
    'eyeAspect',
    'browSpacing',
  ],
  'brows': [
    'eyebrowThickness',
    'browEyeDistance',
    'eyebrowTiltDirection',
    'eyebrowCurvature',
  ],
  'nose': ['nasalWidthRatio', 'nasalHeightRatio', 'midFaceRatio'],
  'mouth': [
    'mouthWidthRatio',
    'mouthCornerAngle',
    'lipFullnessRatio',
    'philtrumLength',
    'upperVsLowerLipRatio',
  ],
  'jaw': ['gonialAngle', 'chinAngle', 'lowerFaceRatio', 'upperFaceRatio'],
};

/// z 벡터의 RMS 거리. 두 얼굴에 모두 있는 계측만 센다.
double geometryDistance(
  Map<String, double> zA,
  Map<String, double> zB,
  Iterable<String> ids,
) {
  var sum = 0.0;
  var n = 0;
  for (final id in ids) {
    final a = zA[id];
    final b = zB[id];
    if (a == null || b == null) continue;
    final d = a - b;
    sum += d * d;
    n++;
  }
  if (n == 0) return 0;
  return sqrt(sum / n);
}

/// 거리 → 0~100 닮은 정도. AAF 무작위 쌍의 중앙 거리가 50점이 되도록
/// 지수 감쇠(`kGeometryDistanceMedian`, 실측 상수).
double similarityFromDistance(double d) =>
    100 * exp(-ln2 * d / kGeometryDistanceMedian);

/// 닮은 정도 — 전체와 영역별.
class GeometrySimilarity {
  final double overall;
  final Map<String, double> byRegion;

  const GeometrySimilarity({required this.overall, required this.byRegion});
}

GeometrySimilarity computeGeometrySimilarity(
  Map<String, double> zA,
  Map<String, double> zB,
  Iterable<String> referenceMetricIds,
) {
  final overall =
      similarityFromDistance(geometryDistance(zA, zB, referenceMetricIds));
  final byRegion = <String, double>{
    for (final e in geometryRegions.entries)
      e.key: similarityFromDistance(geometryDistance(zA, zB, e.value)),
  };
  return GeometrySimilarity(overall: overall, byRegion: byRegion);
}

/// 첫인상 유사도 — 매력 제외 3축 백분위 차이의 평균을 100 에서 뺀 값.
double impressionSimilarity(
    FirstImpressionProfile a, FirstImpressionProfile b) {
  var sum = 0.0;
  for (final ax in pairAxes) {
    sum += (a[ax] - b[ax]).abs();
  }
  return 100 - sum / pairAxes.length;
}

/// 조화도 — 축마다 두 사람 중 높은 쪽을 취해 평균. "둘이 함께 있으면 인상
/// 축이 다 채워지는가". 제품 정의이며 문헌 검증 없음 → UI 는 가설 지표 표기.
double harmony(FirstImpressionProfile a, FirstImpressionProfile b) {
  var sum = 0.0;
  for (final ax in pairAxes) {
    sum += max(a[ax], b[ax]);
  }
  return sum / pairAxes.length;
}

/// 보완도 — 축마다 |A−B| 의 평균. 두 프로필이 서로 다른 방향을 보이는 정도.
/// 실제 성격의 보완이 아니다.
double complementarity(FirstImpressionProfile a, FirstImpressionProfile b) {
  var sum = 0.0;
  for (final ax in pairAxes) {
    sum += (a[ax] - b[ax]).abs();
  }
  return sum / pairAxes.length;
}

/// 두 얼굴 결과 묶음.
class PairAnalysis {
  final GeometrySimilarity similarity;
  final double impressionSimilarity;
  final double harmony;
  final double complementarity;

  const PairAnalysis({
    required this.similarity,
    required this.impressionSimilarity,
    required this.harmony,
    required this.complementarity,
  });

  /// 케미 점수 — 조화도 + 보완도 + 닮은 정도 (0~300). 첫인상 케미 방의
  /// 매트릭스 값이자 베스트 쌍 기준. "궁합" 이라는 말은 쓰지 않는다.
  double get chemistry => harmony + complementarity + similarity.overall;
}

PairAnalysis analyzePair({
  required Map<String, double> zA,
  required FirstImpressionProfile profileA,
  required Map<String, double> zB,
  required FirstImpressionProfile profileB,
  required Iterable<String> referenceMetricIds,
}) {
  return PairAnalysis(
    similarity: computeGeometrySimilarity(zA, zB, referenceMetricIds),
    impressionSimilarity: impressionSimilarity(profileA, profileB),
    harmony: harmony(profileA, profileB),
    complementarity: complementarity(profileA, profileB),
  );
}
