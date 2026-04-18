/// Monte Carlo calibration for the compatibility engine.
///
/// Generates N correlated face pairs via face templates, runs them through
/// the hierarchical attribute engine + `evaluateCompatibility`, and returns
/// the sorted distribution + percentile thresholds. Output drives the
/// compat_label tier buckets.
library;

import 'dart:math';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/compatibility_engine.dart';
import 'package:face_reader/domain/services/metric_score.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

// ─── Template-based correlated face generator ───
//
// Real faces have STRONG metric correlations (thick brow ↔ strong jaw, etc.).
// Independent Gaussian sampling understates how often two users simultaneously
// exhibit rule-triggering metric patterns. Each template biases the metric
// pathway the hierarchical engine uses for a specific attribute cluster:
//
//   leader   → forehead/cheekbone/chin strong + Z-07 (all zones hot)
//   scholar  → forehead + eye + eyebrow, Z-02/P-02 (upper zone dominant)
//   merchant → nose + mouth + eye, O-NM1/P-01 (middle zone dominant)
//   charmer  → cheekbone + mouth + eye, O-EM
//   sensual  → lip full + eye tilt + short philtrum, O-PH1/Z-04/P-06
//   anchor   → chin + long philtrum + moderate forehead/nose, O-CH/O-PH2
//
// See `lib/domain/services/attribute_derivation.dart` for the weight matrix
// and rule conditions these biases exploit.
const faceTemplates = <FaceTemplate>[
  FaceTemplate('leader', {
    'upperFaceRatio': 1.4,
    'foreheadWidth': 1.3,
    'cheekboneWidth': 1.3,
    'gonialAngle': 1.2,
    'lowerFaceFullness': 1.0,
    'chinAngle': 1.1,
    'nasalHeightRatio': 0.8,
    'noseTipProjection': 0.8,
  }),
  FaceTemplate('scholar', {
    'upperFaceRatio': 1.3,
    'foreheadWidth': 1.2,
    'eyebrowThickness': 1.1,
    'browEyeDistance': 1.0,
    'eyeFissureRatio': 1.3,
    'eyeAspect': 1.1,
    'nasalWidthRatio': -0.3,
    'gonialAngle': -0.3,
    'lowerFaceFullness': -0.3,
    'mouthWidthRatio': -0.2,
  }),
  FaceTemplate('merchant', {
    'nasalWidthRatio': 1.3,
    'nasalHeightRatio': 1.5,
    'nasofrontalAngle': 1.1,
    'noseTipProjection': 1.3,
    'mouthWidthRatio': 1.2,
    'mouthCornerAngle': 1.0,
    'cheekboneWidth': 1.1,
    'eyeFissureRatio': 1.1,
    'upperFaceRatio': -0.3,
    'foreheadWidth': -0.3,
    'philtrumLength': -0.3,
    'lowerFaceFullness': -0.2,
  }),
  FaceTemplate('charmer', {
    'cheekboneWidth': 1.5,
    'mouthWidthRatio': 1.5,
    'mouthCornerAngle': 1.4,
    'lipFullnessRatio': 1.0,
    'lowerFaceFullness': 0.9,
    'chinAngle': 0.8,
    'eyeFissureRatio': 1.1,
    'eyeAspect': 0.9,
    'nasalHeightRatio': 0.2,
  }),
  FaceTemplate('sensual', {
    'eyeCanthalTilt': 1.5,
    'eyeAspect': 1.1,
    'lipFullnessRatio': 1.6,
    'upperVsLowerLipRatio': 1.0,
    'mouthCornerAngle': 0.9,
    'philtrumLength': -1.2,
    'lowerFaceFullness': 0.9,
    'chinAngle': 0.7,
    'upperFaceRatio': -0.3,
    'foreheadWidth': -0.3,
    'nasalWidthRatio': -0.2,
    'eyebrowThickness': -0.2,
  }),
  FaceTemplate('anchor', {
    'gonialAngle': 1.2,
    'lowerFaceRatio': 0.8,
    'lowerFaceFullness': 1.1,
    'chinAngle': 1.3,
    'philtrumLength': 1.3,
    'upperFaceRatio': 0.8,
    'foreheadWidth': 0.7,
    'eyebrowThickness': 1.0,
    'browEyeDistance': 0.8,
    'nasalHeightRatio': 0.6,
    'nasalWidthRatio': 0.4,
    'eyeFissureRatio': 0.4,
    'mouthWidthRatio': 0.0,
    'lipFullnessRatio': -0.3,
    'mouthCornerAngle': -0.3,
  }),
];

class FaceTemplate {
  final String label;
  final Map<String, double> bias;
  const FaceTemplate(this.label, this.bias);
}

const double _noiseStd = 0.6;
const double _baseBias = 0.2;

FaceReadingReport _syntheticReport(Random rng, Gender gender) {
  final template = faceTemplates[rng.nextInt(faceTemplates.length)];
  final zMap = <String, double>{};
  final intScores = <String, int>{};
  for (final info in metricInfoList) {
    final bias = template.bias[info.id] ?? _baseBias;
    final z = (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5);
    zMap[info.id] = z;
    intScores[info.id] = convertToScore(z, info.type);
  }

  // Stage 0 preset 을 compat 분포에 반영 — 프로덕션과 동일한 shape-aware 산출.
  final shape = drawShape(rng);
  final confidence = shape == FaceShape.unknown ? 0.0 : 0.8;

  final tree = scoreTree(zMap);
  final breakdown = deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: false,
    hasLateral: false,
    faceShape: shape,
    shapeConfidence: confidence,
  );
  final normalized = normalizeAllScores(breakdown.total, gender);
  final archetype = classifyArchetype(normalized, shape: shape);

  final metricResults = <String, MetricResult>{};
  for (final info in metricInfoList) {
    metricResults[info.id] = MetricResult(
      id: info.id,
      rawValue: 0,
      zScore: zMap[info.id]!,
      zAdjusted: zMap[info.id]!,
      metricScore: intScores[info.id]!,
    );
  }

  // Build rich evidence — nodeScores, attributes, rules
  final nodeScores = _collectNodeScores(tree);
  final attributes = _buildAttributeEvidence(breakdown, normalized);
  final rules = _buildRuleEvidence(breakdown);

  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: AgeGroup.thirties,
    timestamp: DateTime.now(),
    source: AnalysisSource.album,
    metrics: metricResults,
    nodeScores: nodeScores,
    attributes: attributes,
    rules: rules,
    archetype: archetype,
    faceShape: shape,
  );
}

/// Walk the 14-node tree and collect NodeEvidence for every node.
Map<String, NodeEvidence> _collectNodeScores(NodeScore root) {
  final out = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    out[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final child in node.children) {
      walk(child);
    }
  }
  walk(root);
  return out;
}

/// Build AttributeEvidence for each attribute from the breakdown.
Map<Attribute, AttributeEvidence> _buildAttributeEvidence(
  AttributeBreakdown breakdown,
  Map<Attribute, double> normalizedScores,
) {
  final out = <Attribute, AttributeEvidence>{};
  for (final attr in Attribute.values) {
    final base = breakdown.basePerNode[attr] ?? const <String, double>{};
    final dist = breakdown.distinctiveness[attr] ?? 0.0;
    final raw = breakdown.total[attr] ?? 0.0;
    final norm = normalizedScores[attr] ?? 5.0;

    final bag = <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
    final sh = breakdown.shapePreset[attr] ?? 0.0;
    if (sh.abs() > 0.05) bag['shape'] = sh;
    if (dist.abs() > 0.05) bag['distinctiveness'] = dist;
    for (final r in breakdown.zoneRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.organRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.palaceRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.ageRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.lateralRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }

    final sorted = bag.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final contributors = sorted
        .map((e) => Contributor(id: e.key, value: e.value))
        .toList();

    out[attr] = AttributeEvidence(
      rawTotal: raw,
      normalizedScore: norm,
      basePerNode: Map<String, double>.from(base),
      distinctiveness: dist,
      contributors: contributors,
    );
  }
  return out;
}

/// Flatten the 5 rule lists into List<RuleEvidence> with stage tags.
List<RuleEvidence> _buildRuleEvidence(AttributeBreakdown breakdown) {
  final out = <RuleEvidence>[];
  for (final r in breakdown.zoneRules) {
    out.add(RuleEvidence(id: r.id, stage: 'zone', effects: r.effects));
  }
  for (final r in breakdown.organRules) {
    out.add(RuleEvidence(id: r.id, stage: 'organ', effects: r.effects));
  }
  for (final r in breakdown.palaceRules) {
    out.add(RuleEvidence(id: r.id, stage: 'palace', effects: r.effects));
  }
  for (final r in breakdown.ageRules) {
    out.add(RuleEvidence(id: r.id, stage: 'age', effects: r.effects));
  }
  for (final r in breakdown.lateralRules) {
    out.add(RuleEvidence(id: r.id, stage: 'lateral', effects: r.effects));
  }
  return out;
}

class CompatPercentiles {
  final List<double> sorted;
  CompatPercentiles(this.sorted);

  double percentile(double p) {
    final idx = (sorted.length * p).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  double get p1 => percentile(0.01);
  double get p5 => percentile(0.05);
  double get p10 => percentile(0.10);
  double get p15 => percentile(0.15);
  double get p20 => percentile(0.20);
  double get p30 => percentile(0.30);
  double get p40 => percentile(0.40);
  double get p50 => percentile(0.50);
  double get p60 => percentile(0.60);
  double get p70 => percentile(0.70);
  double get p80 => percentile(0.80);
  double get p85 => percentile(0.85);
  double get p90 => percentile(0.90);
  double get p95 => percentile(0.95);
  double get p99 => percentile(0.99);
  double get min => sorted.first;
  double get max => sorted.last;
  double get mean => sorted.reduce((a, b) => a + b) / sorted.length;

  int countWhere(bool Function(double) f) => sorted.where(f).length;
}

CompatPercentiles calibrateCompatibility({
  int samples = 10000,
  int seed = 42,
}) {
  final rng = Random(seed);
  final scores = <double>[];
  for (int i = 0; i < samples; i++) {
    final my = _syntheticReport(rng, Gender.male);
    final album = _syntheticReport(rng, Gender.female);
    final result = evaluateCompatibility(my, album);
    scores.add(result.score);
  }
  scores.sort();
  return CompatPercentiles(scores);
}
