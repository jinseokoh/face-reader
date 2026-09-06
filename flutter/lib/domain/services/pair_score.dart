import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/impression_features.dart';

/// 두 리포트 → 첫인상 쌍 분석 (닮은 정도·첫인상 유사도·조화도·보완도·케미 합).
///
/// measure 에디션의 비교 탭·상세·해제 기록·케미 셀이 전부 이 한 함수를 쓴다.
/// 첫인상은 계측 z, 닮은 정도는 저장 좌표(Procrustes) 에서 온다 (APPLE.md §81.3).
final List<String> _referenceIds = [for (final m in metricInfoList) m.id];

Map<String, double> zMapOf(FaceReadingReport r) =>
    {for (final e in r.metrics.entries) e.key: e.value.zScore};

FirstImpressionProfile impressionOf(FaceReadingReport r) =>
    computeFirstImpression(zMapOf(r),
        gender: r.gender,
        referenceMetricIds: _referenceIds,
        symmetryZ: symmetryOverallZ(r.symmetry, r.gender));

PairAnalysis analyzePairReports(FaceReadingReport a, FaceReadingReport b) =>
    analyzePair(
      landmarksA: a.landmarks,
      profileA: impressionOf(a),
      landmarksB: b.landmarks,
      profileB: impressionOf(b),
    );

/// 두 얼굴에서 계측 차이(|Δz|)가 가장 작은/큰 계측 id 순.
List<String> rankMetricsByDifference(
  FaceReadingReport a,
  FaceReadingReport b, {
  required bool mostSimilar,
}) {
  final zA = zMapOf(a);
  final zB = zMapOf(b);
  final ids = [
    for (final id in _referenceIds)
      if (zA[id] != null && zB[id] != null) id,
  ];
  double d(String id) => (zA[id]! - zB[id]!).abs();
  ids.sort((x, y) => mostSimilar ? d(x).compareTo(d(y)) : d(y).compareTo(d(x)));
  return ids;
}

/// 두 사람이 평균에서 같은 방향으로 먼 계측(|z| ≥ 1 둘 다) — 둘 다 작은 |z| 순.
/// [sameDirection] false 면 반대 방향(한쪽 +, 한쪽 −)인 계측.
List<String> sharedDeviations(
  FaceReadingReport a,
  FaceReadingReport b, {
  required bool sameDirection,
  double threshold = 1.0,
}) {
  final zA = zMapOf(a);
  final zB = zMapOf(b);
  final ids = [
    for (final id in _referenceIds)
      if (zA[id] != null &&
          zB[id] != null &&
          zA[id]!.abs() >= threshold &&
          zB[id]!.abs() >= threshold &&
          ((zA[id]! > 0) == (zB[id]! > 0)) == sameDirection)
        id,
  ];
  double strength(String id) =>
      zA[id]!.abs() < zB[id]!.abs() ? zA[id]!.abs() : zB[id]!.abs();
  ids.sort((x, y) => strength(y).compareTo(strength(x)));
  return ids;
}

/// 리포트의 축별 feature 기여 (부호 × 비중 × feature z).
Map<ImpressionAxis, Map<String, double>> axisContributionsOf(
        FaceReadingReport r) =>
    axisContributions(buildImpressionFeatures(zMapOf(r),
        referenceMetricIds: _referenceIds,
        symmetryZ: symmetryOverallZ(r.symmetry, r.gender)));

/// feature id → 화면 이름 (계측 이름 · 얼굴 대칭 · 평균과의 거리).
String featureNameKo(String feature) {
  for (final s in impressionFeatureSpecs) {
    if (s.id == feature) {
      return metricInfoList.firstWhere((m) => m.id == s.metric).nameKo;
    }
  }
  if (feature == symmetryFeatureId) return '얼굴 대칭';
  return '평균과의 거리';
}
