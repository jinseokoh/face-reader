// Verifies that, with z-normalization in normalizeScore, no archetype
// is statistically favored over another.
//
// Run via: flutter test test/archetype_fairness_test.dart
//
// Expected: each of 10 archetypes is selected as primary roughly 10% of
// the time (1 in 10) over a large random sample.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';
import 'package:face_reader/domain/services/metric_score.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

// Realistic input distribution: matches what calibration uses (N(0.2, 0.85))
const double _inputMean = 0.2;
const double _inputStd = 0.85;
double _realisticZ(Random rng) =>
    (_normal(rng) * _inputStd + _inputMean).clamp(-3.5, 3.5);

void main() {
  test('archetype primary distribution is fair (within ±5%)', () {
    const samples = 20000;
    const seed = 1234;
    final rng = Random(seed);
    final counts = {for (final a in Attribute.values) a: 0};

    for (int i = 0; i < samples; i++) {
      final gender = i.isEven ? Gender.male : Gender.female;
      final continuousScores = <String, double>{};
      final intScores = <String, int>{};
      for (final info in metricInfoList) {
        final z = _realisticZ(rng);
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
      counts[archetype.primary] = counts[archetype.primary]! + 1;
    }

    // ignore: avoid_print
    print('\n========== Archetype Fairness ($samples samples) ==========');
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      final pct = (e.value / samples * 100).toStringAsFixed(2);
      // ignore: avoid_print
      print('${e.key.name.padRight(16)} ${e.value.toString().padLeft(5)}  ($pct%)');
    }

    // 각 attribute가 5%~15% 사이에 있어야 fair (이상값 10%, ±5% 허용)
    // 이론적으론 정확히 10%여야 하지만 attribute 간 correlation 때문에 약간 벗어남.
    // ±5% 안이면 leadership 쏠림 같은 심각한 편향은 사라진 것으로 간주.
    for (final entry in counts.entries) {
      final pct = entry.value / samples;
      expect(pct, greaterThan(0.05),
          reason: '${entry.key.name} too rare: ${(pct * 100).toStringAsFixed(2)}%');
      expect(pct, lessThan(0.15),
          reason: '${entry.key.name} too common: ${(pct * 100).toStringAsFixed(2)}%');
    }
  });
}
