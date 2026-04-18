import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/physiognomy_tree.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tree has exactly 14 nodes (root + 3 zones + 10 leaves)', () {
    expect(allNodes.length, 14);
  });

  test('root + zone ids present', () {
    for (final id in ['face', 'upper', 'middle', 'lower']) {
      expect(nodeById[id], isNotNull, reason: 'missing $id');
    }
  });

  test('all 10 leaf ids present', () {
    const leaves = [
      'forehead', 'glabella', 'eyebrow',
      'eye', 'nose', 'cheekbone', 'ear',
      'philtrum', 'mouth', 'chin',
    ];
    expect(leaves.length, 10);
    for (final id in leaves) {
      expect(nodeById[id], isNotNull, reason: 'missing $id');
    }
  });

  test('ear node is unsupported', () {
    expect(nodeById['ear']!.unsupported, true);
    expect(nodeById['ear']!.metricIds, isEmpty);
  });

  test('glabella 는 browSpacing 하나로 명궁 감지', () {
    expect(nodeById['glabella']!.metricIds, ['browSpacing']);
  });

  test('metric → node mapping covers expected frontal + lateral metrics', () {
    // Expected set = 현재 computeAll 산출물 - 고아 2개 (classifier 전용).
    const expected = {
      // root
      'faceAspectRatio', 'faceTaperRatio', 'midFaceRatio',
      // forehead
      'upperFaceRatio', 'foreheadWidth',
      // glabella
      'browSpacing',
      // eyebrow
      'eyebrowThickness', 'browEyeDistance',
      'eyebrowTiltDirection', 'eyebrowCurvature',
      // eye
      'intercanthalRatio', 'eyeFissureRatio', 'eyeCanthalTilt', 'eyeAspect',
      // nose
      'nasalWidthRatio', 'nasalHeightRatio',
      'nasofrontalAngle', 'nasolabialAngle',
      'noseTipProjection', 'dorsalConvexity',
      // cheekbone
      'cheekboneWidth',
      // philtrum
      'philtrumLength',
      // mouth
      'mouthWidthRatio', 'mouthCornerAngle', 'lipFullnessRatio',
      'upperVsLowerLipRatio',
      'upperLipEline', 'lowerLipEline', 'mentolabialAngle',
      // chin
      'gonialAngle', 'lowerFaceRatio', 'lowerFaceFullness',
      'chinAngle', 'facialConvexity',
    };
    expect(nodeByMetricId.keys.toSet(), expected);
  });

  test('retired orphans are NOT in tree', () {
    for (final m in ['eyebrowLength', 'noseBridgeRatio']) {
      expect(nodeByMetricId[m], isNull, reason: '$m should be retired');
    }
  });

  test('each leaf belongs to a zone', () {
    for (final n in allNodes) {
      if (n.children.isEmpty && n.id != 'face') {
        expect(n.zone, isNotNull, reason: 'leaf ${n.id} has no zone');
      }
    }
  });

  // ─── Phase 1B coverage: every tree metric has info + reference data ───

  /// metric id → source split. Lateral metrics live in separate map.
  const lateralSet = {
    'nasofrontalAngle',
    'nasolabialAngle',
    'noseTipProjection',
    'dorsalConvexity',
    'upperLipEline',
    'lowerLipEline',
    'mentolabialAngle',
    'facialConvexity',
  };

  test('every tree metric has a MetricInfo (frontal or lateral)', () {
    final infoIds = {
      for (final m in metricInfoList) m.id,
      for (final m in lateralMetricInfoList) m.id,
    };
    for (final m in nodeByMetricId.keys) {
      expect(infoIds.contains(m), true,
          reason: 'metricInfoList/lateralMetricInfoList missing $m');
    }
  });

  test('every frontal tree metric has reference entry for all ethnicity × gender',
      () {
    for (final m in nodeByMetricId.keys) {
      if (lateralSet.contains(m)) continue;
      for (final eth in Ethnicity.values) {
        for (final g in Gender.values) {
          final ref = referenceData[eth]?[g]?[m];
          expect(ref, isNotNull,
              reason: 'referenceData[$eth][$g] missing $m');
        }
      }
    }
  });

  test('every lateral tree metric has reference entry for all ethnicity × gender',
      () {
    for (final m in nodeByMetricId.keys) {
      if (!lateralSet.contains(m)) continue;
      for (final eth in Ethnicity.values) {
        for (final g in Gender.values) {
          final ref = lateralReferenceData[eth]?[g]?[m];
          expect(ref, isNotNull,
              reason: 'lateralReferenceData[$eth][$g] missing $m');
        }
      }
    }
  });

  // ─── Weight-matrix sanity (face/ear 제외 9-노드) ───

  test('모든 attribute row sum = 1.00 (±0.01)', () {
    final sums = attributeRowSums();
    for (final attr in Attribute.values) {
      final s = sums[attr]!;
      expect(s, closeTo(1.0, 0.01),
          reason: '${attr.name} row sum = $s (expected 1.00)');
    }
  });

  test('weight matrix 는 face(root) / ear 를 참조하지 않는다', () {
    for (final attr in Attribute.values) {
      final ids = weightedNodeIds(attr);
      expect(ids, isNot(contains('face')),
          reason: '${attr.name} still references face root');
      expect(ids, isNot(contains('ear')),
          reason: '${attr.name} still references ear (unsupported)');
    }
  });

  test('per-metric 영향력 ∈ [0.10, 0.80] — 과적재/고아 회귀 차단', () {
    // face(root) metric 은 Stage 1b distinctiveness · Z-11 zone rule 로 소비되므로
    // weight matrix 영향력 0 이 정상. 이 테스트는 leaf 노드 metric 만 검사한다.
    const rootMetrics = {'faceAspectRatio', 'faceTaperRatio', 'midFaceRatio'};
    final inf = perMetricInfluence();
    final supportedLeafIds = nodeByMetricId.keys
        .where((m) => !lateralSet.contains(m) && !rootMetrics.contains(m))
        .toSet();
    for (final m in supportedLeafIds) {
      final v = inf[m];
      expect(v, isNotNull, reason: 'supported leaf metric $m 에 weight 기여 0');
      expect(v!, greaterThanOrEqualTo(0.10),
          reason: 'metric $m influence too low ($v) — 고아 의심');
      expect(v, lessThanOrEqualTo(0.80),
          reason: 'metric $m influence too high ($v) — 과적재 의심');
    }
  });

  test('face root metric 은 weight matrix 영향력 0 (design)', () {
    final inf = perMetricInfluence();
    for (final m in ['faceAspectRatio', 'faceTaperRatio', 'midFaceRatio']) {
      expect(inf[m] ?? 0.0, 0.0,
          reason: 'root metric $m should be Stage 1b/Z-11 only');
    }
  });

  test('각 attribute 는 최소 2개 zone 에 non-zero weight', () {
    final cov = attributeZoneCoverage();
    for (final attr in Attribute.values) {
      final zones = cov[attr]!;
      expect(zones.length, greaterThanOrEqualTo(2),
          reason: '${attr.name} zone coverage = $zones (<2)');
    }
  });
}
