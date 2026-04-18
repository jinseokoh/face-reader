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
import 'package:face_reader/data/enums/ethnicity.dart';
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

  final tree = scoreTree(zMap);
  final breakdown = deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: false,
    hasLateral: false,
  );
  final normalized = normalizeAllScores(breakdown.total, gender);
  final archetype = classifyArchetype(normalized);
  final triggered = <TriggeredRule>[
    ...breakdown.zoneRules,
    ...breakdown.organRules,
    ...breakdown.palaceRules,
    ...breakdown.ageRules,
    ...breakdown.lateralRules,
  ];

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

  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: AgeGroup.thirties,
    timestamp: DateTime.now(),
    source: AnalysisSource.album,
    metrics: metricResults,
    attributeScores: normalized,
    archetype: archetype,
    triggeredRules: triggered,
  );
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
