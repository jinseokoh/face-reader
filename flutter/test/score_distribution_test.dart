// Verifies that normalized attribute scores are spread evenly in [5, 10]
// for the realistic input distribution N(0.2, 0.85).
//
// Run via: flutter test test/score_distribution_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
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

const double _inputMean = 0.2;
const double _inputStd = 0.85;
double _realisticZ(Random rng) =>
    (_normal(rng) * _inputStd + _inputMean).clamp(-3.5, 3.5);

void main() {
  test('normalized score distribution per attribute', () {
    const samples = 20000;
    const seed = 1234;
    final rng = Random(seed);
    final scores = {for (final a in Attribute.values) a: <double>[]};

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
      for (final attr in Attribute.values) {
        scores[attr]!.add(normalized[attr]!);
      }
    }

    // ignore: avoid_print
    print('\n========== Score Distribution per Attribute ==========');
    // ignore: avoid_print
    print('Attribute         min    p25    p50    p75    p95    p99   max   mean   <6%   >9.5%');
    for (final attr in Attribute.values) {
      final list = scores[attr]!..sort();
      final mean = list.reduce((a, b) => a + b) / list.length;
      final p = (double pct) => list[((list.length - 1) * pct).round()];
      final under6 = list.where((s) => s < 6.0).length / list.length;
      final over95 = list.where((s) => s > 9.5).length / list.length;
      // ignore: avoid_print
      print(
          '${attr.name.padRight(16)} '
          '${list.first.toStringAsFixed(2).padLeft(5)}  '
          '${p(0.25).toStringAsFixed(2).padLeft(5)}  '
          '${p(0.50).toStringAsFixed(2).padLeft(5)}  '
          '${p(0.75).toStringAsFixed(2).padLeft(5)}  '
          '${p(0.95).toStringAsFixed(2).padLeft(5)}  '
          '${p(0.99).toStringAsFixed(2).padLeft(5)}  '
          '${list.last.toStringAsFixed(2).padLeft(5)}  '
          '${mean.toStringAsFixed(2).padLeft(5)}  '
          '${(under6 * 100).toStringAsFixed(1).padLeft(5)}% '
          '${(over95 * 100).toStringAsFixed(1).padLeft(5)}%');
    }

    // 검증: 모든 attribute에서
    //  - median은 7.0~8.0 근처 (5~10 균등이면 7.5)
    //  - max에 saturate되는 비율(>9.5)이 30% 이하
    for (final attr in Attribute.values) {
      final list = scores[attr]!;
      final p50 = list[(list.length / 2).round()];
      final over95 = list.where((s) => s > 9.5).length / list.length;
      expect(p50, greaterThan(6.5),
          reason: '${attr.name} median too low: $p50');
      expect(p50, lessThan(8.5),
          reason: '${attr.name} median too high: $p50');
      expect(over95, lessThan(0.30),
          reason:
              '${attr.name} too saturated above 9.5: ${(over95 * 100).toStringAsFixed(1)}%');
    }
  });

  // ─── Correlated-metrics simulation: mimics real Korean adult faces where
  // browEyeDistance + eyebrowThickness + gonialAngle move TOGETHER. v8 (pure
  // quantile mapping) saturated stability/trust/leadership at 9.9~10 for these.
  // v9 (rank-aware) must show within-face spread regardless.
  test('correlated real-face simulation: top 3 must not all saturate', () {
    const samples = 1000;
    final rng = Random(99);

    // 5 face templates representing common Korean adult patterns.
    // Each template: a base z bias for each metric (drives correlation).
    final templates = <Map<String, double>>[
      // Template A: strong leadership face — thick brow, strong jaw, deep eyes
      {
        'browEyeDistance': 1.5,
        'eyebrowThickness': 1.8,
        'gonialAngle': 1.5,
        'eyeCanthalTilt': 1.0,
        'faceTaperRatio': -0.5,
      },
      // Template B: gentle "wisdom" face — wide eyes, soft features
      {
        'browEyeDistance': 1.2,
        'eyeFissureRatio': 1.5,
        'mouthCornerAngle': 1.0,
        'eyebrowThickness': 0.8,
      },
      // Template C: sociable face
      {
        'mouthWidthRatio': 1.5,
        'mouthCornerAngle': 1.5,
        'lipFullnessRatio': 1.2,
        'eyeFissureRatio': 1.0,
      },
      // Template D: sensual face
      {
        'lipFullnessRatio': 1.8,
        'eyeCanthalTilt': 1.5,
        'philtrumLength': -1.0,
        'mouthCornerAngle': 1.0,
      },
      // Template E: stable/trust archetype — the problematic one
      {
        'browEyeDistance': 2.0,
        'eyebrowThickness': 2.0,
        'gonialAngle': 1.5,
        'faceAspectRatio': 0.0,
        'intercanthalRatio': 0.0,
      },
    ];

    int allTop3Saturated = 0;
    int spreadFailures = 0;
    final templateExamples = <int, Map<Attribute, double>>{};

    for (int i = 0; i < samples; i++) {
      final templateIdx = i % templates.length;
      final template = templates[templateIdx];
      final gender = i.isEven ? Gender.male : Gender.female;

      final continuousScores = <String, double>{};
      final intScores = <String, int>{};
      for (final info in metricInfoList) {
        // Template bias + small random noise (correlated structure)
        final bias = template[info.id] ?? 0.0;
        final noise = _normal(rng) * 0.4;
        final z = (bias + noise).clamp(-3.5, 3.5);
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

      // Capture one example per template for visual inspection
      templateExamples.putIfAbsent(templateIdx, () => normalized);

      final values = normalized.values.toList()..sort((a, b) => b.compareTo(a));
      // Top 3 all >= 9.5 → saturation pattern (the bug)
      if (values[0] >= 9.5 && values[1] >= 9.5 && values[2] >= 9.5) {
        allTop3Saturated++;
      }
      // Within-face spread must be at least 3.0 points (rank guarantee)
      final spread = values.first - values.last;
      if (spread < 3.0) spreadFailures++;
    }

    // ignore: avoid_print
    print('\n========== Correlated Face Simulation ==========');
    // ignore: avoid_print
    print('Samples: $samples');
    // ignore: avoid_print
    print('Top-3 all ≥9.5 saturation count: $allTop3Saturated');
    // ignore: avoid_print
    print('Within-face spread <3.0 count: $spreadFailures');
    // ignore: avoid_print
    print('\n--- Example score patterns per template ---');
    final templateLabels = ['leader', 'wisdom', 'social', 'sensual', 'stable'];
    for (int i = 0; i < templates.length; i++) {
      final ex = templateExamples[i];
      if (ex == null) continue;
      final sorted = ex.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('Template ${templateLabels[i]}:');
      for (final e in sorted) {
        // ignore: avoid_print
        print('  ${e.key.name.padRight(16)} ${e.value.toStringAsFixed(1)}');
      }
    }

    // 검증: 상관 얼굴에서도 spread는 항상 보장됨, top-3 saturation은 거의 없음
    expect(spreadFailures, equals(0),
        reason: 'every face should have ≥3.0 score spread by rank guarantee');
    // top-3 all 9.5+ should be very rare even for the "stable" template
    // (the user-reported bug had this happen for ~100% of faces)
    expect(allTop3Saturated / samples, lessThan(0.05),
        reason:
            'top-3 saturation should be <5% of faces, was ${(allTop3Saturated / samples * 100).toStringAsFixed(1)}%');
  });
}
