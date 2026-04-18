import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/physiognomy_tree.dart';
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

  test('glabella currently has no metrics (v1.0 gap, documented)', () {
    expect(nodeById['glabella']!.metricIds, isEmpty);
  });

  test('metric → node mapping covers expected frontal + lateral metrics', () {
    // Expected set = 현재 computeAll 산출물 - 고아 3개 (Phase 1B 에서 제거 대상)
    const expected = {
      // root
      'faceAspectRatio', 'faceTaperRatio', 'midFaceRatio',
      // forehead
      'upperFaceRatio', 'foreheadWidth',
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
    for (final m in ['eyebrowLength', 'browSpacing', 'noseBridgeRatio']) {
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
}
