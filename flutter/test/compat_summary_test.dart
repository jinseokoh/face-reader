// Verifies the V5 compatibility summary changes:
//
//  1. Variable verbosity by importance: top 2 attributes (major) get a 비범한
//     관상가 implication appended; minor attributes are shortened to one
//     sentence.
//  2. Sexual harmony section appears ONLY when both partners are 30~50대.
//
// Run via: flutter test test/compat_summary_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

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

FaceReadingReport _synthetic(Random rng, Gender gender, AgeGroup age) {
  final continuousScores = <String, double>{};
  final intScores = <String, int>{};
  for (final info in metricInfoList) {
    final z = (_normal(rng) * 0.85 + 0.2).clamp(-3.5, 3.5);
    continuousScores[info.id] = z;
    intScores[info.id] = convertToScore(z, info.type);
  }
  final base = computeBaseScoresContinuous(continuousScores, gender);
  final triggered = evaluateRules(
    scores: intScores,
    adjustedScores: intScores,
    gender: gender,
    isOver50: age.isOver50,
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
    ageGroup: age,
    timestamp: DateTime.now(),
    source: AnalysisSource.album,
    metrics: metricResults,
    attributeScores: normalized,
    archetype: archetype,
    triggeredRules: triggered,
  );
}

void main() {
  test('침실 궁합 section appears only for 30~50대', () {
    final rng = Random(42);

    final eligibleAges = [
      AgeGroup.thirties,
      AgeGroup.forties,
      AgeGroup.fifties,
    ];
    final ineligibleAges = [
      AgeGroup.teens,
      AgeGroup.twenties,
      AgeGroup.sixties,
      AgeGroup.seventies,
    ];

    // ─── Eligible: BOTH 30~50대 → must have section ───
    int eligibleHits = 0;
    int eligibleTotal = 0;
    for (final ageA in eligibleAges) {
      for (final ageB in eligibleAges) {
        for (var i = 0; i < 5; i++) {
          final my = _synthetic(rng, Gender.male, ageA);
          final album = _synthetic(rng, Gender.female, ageB);
          final result = evaluateCompatibility(my, album);
          eligibleTotal++;
          if (result.summary.contains('## 침실 궁합')) eligibleHits++;
        }
      }
    }
    expect(eligibleHits, equals(eligibleTotal),
        reason:
            '30~50대 페어 $eligibleTotal중 $eligibleHits 개만 침실 궁합 섹션 포함됨 (전체 포함되어야 함)');

    // ─── Ineligible: at least one outside 30~50대 → must NOT have section ───
    int ineligibleLeaks = 0;
    int ineligibleTotal = 0;
    for (final ageA in ineligibleAges) {
      for (final ageB in [...eligibleAges, ...ineligibleAges]) {
        final my = _synthetic(rng, Gender.male, ageA);
        final album = _synthetic(rng, Gender.female, ageB);
        final result = evaluateCompatibility(my, album);
        ineligibleTotal++;
        if (result.summary.contains('## 침실 궁합')) ineligibleLeaks++;
      }
    }
    expect(ineligibleLeaks, equals(0),
        reason:
            '30~50대가 아닌 페어 $ineligibleTotal 중 $ineligibleLeaks 개에 침실 궁합 섹션이 잘못 포함됨');

    // ignore: avoid_print
    print('\n========== 침실 궁합 Section Gating ==========');
    // ignore: avoid_print
    print('30~50대 페어 (포함되어야 함): $eligibleHits/$eligibleTotal');
    // ignore: avoid_print
    print('비-30~50대 페어 (제외되어야 함): leaks=$ineligibleLeaks/$ineligibleTotal');
  });

  test('major attributes get longer text than minor attributes', () {
    final rng = Random(7);
    int majorLongerCount = 0;
    int sampled = 0;

    for (var i = 0; i < 50; i++) {
      final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
      final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
      final result = evaluateCompatibility(my, album);

      // Find one major-marked line and one minor-marked line in summary
      final lines = result.summary.split('\n');
      String? majorLine;
      String? minorLine;
      for (final l in lines) {
        if (majorLine == null && l.startsWith('◆ ')) majorLine = l;
        if (minorLine == null && l.startsWith('· ')) minorLine = l;
        if (majorLine != null && minorLine != null) break;
      }
      if (majorLine != null && minorLine != null) {
        sampled++;
        if (majorLine.length > minorLine.length) majorLongerCount++;
      }
    }

    expect(sampled, greaterThan(20),
        reason: 'not enough samples produced both major and minor lines');
    // Major lines should be longer than minor lines in the vast majority of cases
    expect(majorLongerCount / sampled, greaterThan(0.85),
        reason:
            'major lines were longer in only ${majorLongerCount}/$sampled cases');

    // ignore: avoid_print
    print('\n========== Major vs Minor Length ==========');
    // ignore: avoid_print
    print('Sampled: $sampled, major-longer: $majorLongerCount '
        '(${(majorLongerCount / sampled * 100).toStringAsFixed(1)}%)');
  });

  test('침실 궁합 V6: high variety across many pairs', () {
    final rng = Random(2026);
    final summaries = <String>{};
    const samples = 200;

    for (var i = 0; i < samples; i++) {
      final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
      final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
      final result = evaluateCompatibility(my, album);
      // Extract just the 침실 궁합 section content
      final lines = result.summary.split('\n');
      final idx = lines.indexOf('## 침실 궁합');
      if (idx >= 0 && idx + 1 < lines.length) {
        summaries.add(lines[idx + 1]);
      }
    }

    // ignore: avoid_print
    print('\n========== 침실 궁합 Variety ==========');
    // ignore: avoid_print
    print('Samples: $samples, unique outputs: ${summaries.length}');

    // Compositional pools should produce ≥100 unique outputs in 200 samples
    expect(summaries.length, greaterThanOrEqualTo(100),
        reason: 'only ${summaries.length} unique outputs in $samples pairs '
            '— pools too repetitive');
  });

  test('침실 궁합 V6: tiny score perturbations shift output', () {
    // Build two reports differing by one attribute by 0.1
    final rng = Random(31);
    final myA = _synthetic(rng, Gender.male, AgeGroup.thirties);
    final albumA = _synthetic(rng, Gender.female, AgeGroup.thirties);

    int shifts = 0;
    int trials = 0;
    for (final attr in Attribute.values) {
      final base = albumA.attributeScores[attr] ?? 5.0;
      // Skip attributes already at boundary
      if (base >= 9.9 || base <= 5.1) continue;
      // Mutate album by +0.2 on this attribute
      final mutated = Map<Attribute, double>.from(albumA.attributeScores);
      mutated[attr] = (base + 0.2).clamp(5.0, 10.0);
      final albumB = FaceReadingReport(
        ethnicity: albumA.ethnicity,
        gender: albumA.gender,
        ageGroup: albumA.ageGroup,
        timestamp: albumA.timestamp,
        source: albumA.source,
        metrics: albumA.metrics,
        attributeScores: mutated,
        archetype: albumA.archetype,
        triggeredRules: albumA.triggeredRules,
      );
      final resA = evaluateCompatibility(myA, albumA);
      final resB = evaluateCompatibility(myA, albumB);
      final lA = resA.summary.split('\n');
      final lB = resB.summary.split('\n');
      final iA = lA.indexOf('## 침실 궁합');
      final iB = lB.indexOf('## 침실 궁합');
      if (iA >= 0 && iB >= 0) {
        trials++;
        if (lA[iA + 1] != lB[iB + 1]) shifts++;
      }
    }

    // ignore: avoid_print
    print('\n========== 침실 궁합 Sensitivity ==========');
    // ignore: avoid_print
    print('Trials: $trials, output-shifted: $shifts '
        '(${(shifts / trials * 100).toStringAsFixed(0)}%)');

    // At least half the perturbations should change the output
    expect(shifts / trials, greaterThan(0.4),
        reason: 'only $shifts/$trials perturbations changed the output');
  });

  test('sample summary print (30대 vs 30대)', () {
    final rng = Random(2026);
    final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
    final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
    final result = evaluateCompatibility(my, album);
    // ignore: avoid_print
    print('\n========== Sample Summary (30대 vs 30대) ==========');
    // ignore: avoid_print
    print('Score: ${result.score}');
    // ignore: avoid_print
    print(result.summary);
  });
}
