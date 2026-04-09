import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/age_adjustment.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';
import 'package:face_reader/domain/services/face_metrics.dart';
import 'package:face_reader/domain/services/metric_score.dart';

/// Full face-reading pipeline (FORMULA.md §3.8)
FaceReadingReport analyzeFaceReading({
  required List<FaceMeshLandmark> landmarks,
  required Ethnicity ethnicity,
  required Gender gender,
  required AgeGroup ageGroup,
  required AnalysisSource source,
}) {
  final isOver50 = ageGroup.isOver50;

  // Step 1: Compute 15 raw metrics
  final faceMetrics = FaceMetrics(landmarks);
  final measured = faceMetrics.computeAll();

  // Step 2: Z-score with gender-specific reference
  final refs = referenceData[ethnicity]![gender]!;
  final zScores = <String, double>{};
  for (final entry in measured.entries) {
    final ref = refs[entry.key]!;
    zScores[entry.key] = (entry.value - ref.mean) / ref.sd;
  }

  // Step 3: Age adjustment (over50 only)
  final zAdjusted = <String, double>{};
  for (final entry in zScores.entries) {
    zAdjusted[entry.key] =
        adjustForAge(entry.key, entry.value, gender, isOver50);
  }

  // Step 4: Z-adjusted → Metric Score (S)
  final metricScores = <String, int>{};
  final adjustedMetricScores = <String, int>{};
  for (final info in metricInfoList) {
    metricScores[info.id] = convertToScore(zScores[info.id]!, info.type);
    adjustedMetricScores[info.id] =
        convertToScore(zAdjusted[info.id]!, info.type);
  }

  // Step 5: Attribute base scores (gender-weighted)
  final baseScores = computeBaseScores(adjustedMetricScores, gender);

  // Step 6: Interaction rules
  final triggered = evaluateRules(
    scores: metricScores,
    adjustedScores: adjustedMetricScores,
    gender: gender,
    isOver50: isOver50,
  );

  // Apply bonuses to base scores
  final rawScores = Map<Attribute, double>.from(baseScores);
  for (final rule in triggered) {
    for (final effect in rule.effects.entries) {
      rawScores[effect.key] = (rawScores[effect.key] ?? 0) + effect.value;
    }
  }

  // Step 7: Normalize (0~10)
  final normalizedScores = <Attribute, double>{};
  for (final entry in rawScores.entries) {
    normalizedScores[entry.key] = normalizeScore(entry.value);
  }

  // Step 8: Archetype classification
  final archetype = classifyArchetype(normalizedScores);

  // Build metric results
  final metricResults = <String, MetricResult>{};
  for (final info in metricInfoList) {
    metricResults[info.id] = MetricResult(
      id: info.id,
      rawValue: measured[info.id]!,
      zScore: zScores[info.id]!,
      zAdjusted: zAdjusted[info.id]!,
      metricScore: adjustedMetricScores[info.id]!,
    );
  }

  return FaceReadingReport(
    ethnicity: ethnicity,
    gender: gender,
    ageGroup: ageGroup,
    timestamp: DateTime.now(),
    source: source,
    metrics: metricResults,
    attributeScores: normalizedScores,
    archetype: archetype,
    triggeredRules: triggered,
  );
}

/// Average multiple landmark frames to reduce noise
List<FaceMeshLandmark> averageLandmarks(List<List<FaceMeshLandmark>> samples) {
  if (samples.length == 1) return samples.first;

  final count = samples.first.length;
  final n = samples.length.toDouble();

  return List.generate(count, (i) {
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final sample in samples) {
      sumX += sample[i].x;
      sumY += sample[i].y;
      sumZ += sample[i].z;
    }
    return FaceMeshLandmark(x: sumX / n, y: sumY / n, z: sumZ / n);
  });
}
