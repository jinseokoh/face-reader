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
// Real faces have STRONG metric correlations. Independent N(μ,σ) sampling
// understates how often two users simultaneously score high on stability /
// trustworthiness / leadership. Templates encode archetypal metric clusters
// (leader / sage / sociable / sensual / stable / merchant); remaining metrics
// draw from tighter N(0.2, 0.6) noise.
const _faceTemplates = <Map<String, double>>[
  {
    'browEyeDistance': 1.4,
    'eyebrowThickness': 1.6,
    'gonialAngle': 1.3,
    'eyeCanthalTilt': 1.0,
    'faceTaperRatio': -0.4,
  },
  {
    'browEyeDistance': 1.0,
    'eyeFissureRatio': 1.4,
    'mouthCornerAngle': 0.9,
    'eyebrowThickness': 0.7,
  },
  {
    'mouthWidthRatio': 1.4,
    'mouthCornerAngle': 1.4,
    'lipFullnessRatio': 1.1,
    'eyeFissureRatio': 0.9,
  },
  {
    'lipFullnessRatio': 1.6,
    'eyeCanthalTilt': 1.4,
    'philtrumLength': -0.9,
    'mouthCornerAngle': 0.9,
  },
  {
    'browEyeDistance': 1.8,
    'eyebrowThickness': 1.8,
    'gonialAngle': 1.3,
    'faceAspectRatio': 0.0,
  },
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
  final template = _faceTemplates[rng.nextInt(_faceTemplates.length)];
  final zMap = <String, double>{};
  final intScores = <String, int>{};
  for (final info in metricInfoList) {
    final bias = template[info.id] ?? _baseBias;
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
