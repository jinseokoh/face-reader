import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/first_impression.dart';

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
