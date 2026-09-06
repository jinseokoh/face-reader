/// measure 카드의 웹 공유 출력 (APPLE.md §81.9 — 관상과 섞지 않는다).
///
/// 앱의 MeasureReportBody / MeasurePairBody 와 같은 식·같은 상수로 숫자만 만든다.
/// 문구는 웹(ShareCard)이 붙인다. 서술·등급·오행은 없다.
library;

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/constants/metric_quantiles.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/analysis_confidence.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/geometry_profile.dart';
import 'package:face_engine/domain/services/symmetry_metrics.dart';

final List<String> _ids = [for (final m in metricInfoList) m.id];

Map<String, double> _zOf(FaceReadingReport r) =>
    {for (final e in r.metrics.entries) e.key: e.value.zScore};

FirstImpressionProfile _profileOf(FaceReadingReport r) => computeFirstImpression(
      _zOf(r),
      gender: r.gender,
      referenceMetricIds: _ids,
      symmetryZ: symmetryOverallZ(r.symmetry, r.gender),
    );

int _top(double percentile) => (100 - percentile).round().clamp(1, 99);

Map<String, dynamic> composeMeasureOutput(FaceReadingReport r) {
  final z = _zOf(r);
  final profile = _profileOf(r);
  final quant = metricQuantiles[r.gender]!;
  final geo = computeGeometryProfile(
      zByMetric: z, gender: r.gender, symmetry: r.symmetry);
  final distinct = [for (final id in _ids) if (z[id] != null) id]
    ..sort((a, b) => z[b]!.abs().compareTo(z[a]!.abs()));
  return {
    'genderKo': r.gender.labelKo,
    'ageGroupKo': r.ageGroup.labelKo,
    'faceShapeKo': r.faceShape.korean,
    'axes': [
      for (final a in ImpressionAxis.values)
        {'key': a.name, 'labelKo': a.labelKo, 'top': _top(profile[a])},
    ],
    // 공유 카드(§55) — 매력 제외 3축 5칸.
    'cardAxes': [
      for (final a in pairAxes)
        {
          'labelKo': a.labelKo,
          'level': (profile[a] / 20).ceil().clamp(1, 5),
        },
    ],
    'profile': [
      for (final id in geometryProfileIds)
        if (geo[id] != null)
          {'labelKo': geometryProfileNameKo[id], 'score': geo[id]!.round()},
    ],
    'distinct': [
      for (final id in distinct.take(3))
        {
          'labelKo': metricInfoList.firstWhere((m) => m.id == id).nameKo,
          'top': _top(percentileFromQuantiles(z[id]!, quant[id]!)),
        },
    ],
    'symmetry': [
      if (r.symmetry != null)
        for (final id in symmetryIds)
          if (r.symmetry![id] != null)
            {
              'labelKo': symmetryNameKo[id],
              'value': r.symmetry![id]!,
            },
    ],
    'confidenceKo': analysisConfidence(
            landmarks: r.landmarks, gender: r.gender, symmetry: r.symmetry)
        .labelKo,
  };
}

Map<String, dynamic> composeMeasurePairOutput(
    FaceReadingReport a, FaceReadingReport b) {
  final pa = _profileOf(a);
  final pb = _profileOf(b);
  final pair = analyzePair(
    landmarksA: a.landmarks,
    profileA: pa,
    landmarksB: b.landmarks,
    profileB: pb,
  );
  return {
    'chemistry': pair.chemistry.round(),
    'chemistryTop': _top(chemistryPercentile(pair.chemistry)),
    'harmony': pair.harmony.round(),
    'complementarity': pair.complementarity.round(),
    'similarity': pair.similarity.overall.round(),
    'similarityTop': _top(pairSimilarityPercentile(pair.similarity.overall)),
    'impressionSimilarity': pair.impressionSimilarity.round(),
    'regions': [
      for (final e in pair.similarity.byRegion.entries)
        {
          'key': e.key,
          'labelKo': _regionKo[e.key] ?? e.key,
          'value': e.value.round(),
          'bandKo': similarityBandOf(e.key, e.value).labelKo,
          'similar': similarityBandOf(e.key, e.value).isSimilar,
        },
    ],
    'axes': [
      for (final ax in pairAxes)
        {'labelKo': ax.labelKo, 'aTop': _top(pa[ax]), 'bTop': _top(pb[ax])},
    ],
    'a': _person(a),
    'b': _person(b),
  };
}

Map<String, dynamic> _person(FaceReadingReport r) => {
      'genderKo': r.gender.labelKo,
      'ageGroupKo': r.ageGroup.labelKo,
      'faceShapeKo': r.faceShape.korean,
    };

const Map<String, String> _regionKo = {
  'outline': '윤곽',
  'eyes': '눈',
  'brows': '눈썹',
  'nose': '코',
  'mouth': '입',
  'jaw': '턱선',
};
