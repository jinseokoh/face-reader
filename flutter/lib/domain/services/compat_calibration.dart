// Monte Carlo calibration for the compatibility engine.
//
// Generates N random face pairs, runs them through evaluateCompatibility(),
// returns the sorted score distribution + percentile thresholds.
//
// Run via test/compat_calibration_test.dart and copy the percentile values
// into compat_label.dart.

import 'dart:math';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';
import 'package:face_reader/domain/services/compatibility_engine.dart';
import 'package:face_reader/domain/services/metric_score.dart';

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
// Real Korean adult faces have STRONG metric correlations: a strong jawline
// face also tends to have thick eyebrows, deep-set eyes, etc. Pure independent
// N(μ,σ) sampling underestimates how often two real users will both score high
// on stability/trust/leadership simultaneously, which makes Monte Carlo
// compatibility scores systematically LOWER than what real users see.
//
// Templates encode common Korean adult face archetypes. Each template biases
// a subset of metrics toward a strong z-score; remaining metrics + per-face
// noise come from a tighter N(0.2, 0.6) so the face stays inside the template.
const _faceTemplates = <Map<String, double>>[
  // Leader: strong jaw, thick brow, deep eyes, sharp tilt
  {
    'browEyeDistance': 1.4,
    'eyebrowThickness': 1.6,
    'gonialAngle': 1.3,
    'eyeCanthalTilt': 1.0,
    'faceTaperRatio': -0.4,
  },
  // Wisdom/gentle: wide eyes, soft features, balanced
  {
    'browEyeDistance': 1.0,
    'eyeFissureRatio': 1.4,
    'mouthCornerAngle': 0.9,
    'eyebrowThickness': 0.7,
  },
  // Sociable: wide mouth, smile, full lips
  {
    'mouthWidthRatio': 1.4,
    'mouthCornerAngle': 1.4,
    'lipFullnessRatio': 1.1,
    'eyeFissureRatio': 0.9,
  },
  // Sensual: full lips, tilted eyes, short philtrum
  {
    'lipFullnessRatio': 1.6,
    'eyeCanthalTilt': 1.4,
    'philtrumLength': -0.9,
    'mouthCornerAngle': 0.9,
  },
  // Stable/traditional: wide brow gap, thick brow, strong jaw
  {
    'browEyeDistance': 1.8,
    'eyebrowThickness': 1.8,
    'gonialAngle': 1.3,
    'faceAspectRatio': 0.0,
  },
  // Wealth/merchant: wide nose, broad mouth, balanced
  {
    'nasalWidthRatio': 1.5,
    'nasalHeightRatio': 1.0,
    'mouthWidthRatio': 1.0,
    'gonialAngle': 0.6,
  },
];

const double _noiseStd = 0.6;
const double _baseBias = 0.2;

FaceReadingReport _syntheticReport(Random rng, Gender gender) {
  // Pick a template per face — drives metric correlation
  final template = _faceTemplates[rng.nextInt(_faceTemplates.length)];
  final continuousScores = <String, double>{};
  final intScores = <String, int>{};
  for (final info in metricInfoList) {
    final bias = template[info.id] ?? _baseBias;
    final z = (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5);
    continuousScores[info.id] = z;
    intScores[info.id] = convertToScore(z, info.type);
  }

  final base = computeBaseScoresContinuous(continuousScores, gender);
  final triggered = evaluateRules(
    scores: intScores,
    adjustedScores: intScores,
    gender: gender,
    isOver50: false,
  );
  final raws = Map<Attribute, double>.from(base);
  for (final r in triggered) {
    for (final e in r.effects.entries) {
      raws[e.key] = (raws[e.key] ?? 0) + e.value;
    }
  }
  final normalized = normalizeAllScores(raws, gender);
  final archetype = classifyArchetype(normalized);

  final metricResults = <String, MetricResult>{};
  for (final info in metricInfoList) {
    metricResults[info.id] = MetricResult(
      id: info.id,
      rawValue: 0,
      zScore: continuousScores[info.id]!,
      zAdjusted: continuousScores[info.id]!,
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
  final List<double> sorted; // ascending
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
  double get mean =>
      sorted.reduce((a, b) => a + b) / sorted.length;

  /// Returns the count of scores satisfying the predicate.
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
