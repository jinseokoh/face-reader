// Monte Carlo simulation for per-attribute (mean, std) calibration.
//
// Run via test or one-shot script. Output → hardcode into _attrCalibration
// in attribute_engine.dart.
//
// To re-run when weights/rules change:
//   dart test test/calibration_test.dart
//
// Or invoke from any test/main:
//   final result = calibrate(samples: 10000, gender: Gender.male);
//   result.forEach((k, v) => print('$k: μ=${v.mean.toStringAsFixed(3)} σ=${v.std.toStringAsFixed(3)}'));

import 'dart:math';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';
import 'package:face_reader/domain/services/metric_score.dart';

/// Generates [samples] random faces, runs them through the attribute engine,
/// and returns the per-attribute quantile array (21 points: p0, p5, ..., p100).
Map<Attribute, List<double>> calibrateQuantiles({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final rng = Random(seed);
  final raws = {for (final a in Attribute.values) a: <double>[]};

  // Box–Muller standard normal sampler
  double normal() {
    double u1, u2;
    do {
      u1 = rng.nextDouble();
    } while (u1 == 0.0);
    u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  for (int i = 0; i < samples; i++) {
    final continuousScores = <String, double>{};
    final intScores = <String, int>{};
    for (final info in metricInfoList) {
      final z = (normal() * _inputStd + _inputMean).clamp(-3.5, 3.5);
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
    final rawScores = Map<Attribute, double>.from(base);
    for (final rule in triggered) {
      for (final eff in rule.effects.entries) {
        rawScores[eff.key] = (rawScores[eff.key] ?? 0) + eff.value;
      }
    }

    for (final attr in Attribute.values) {
      raws[attr]!.add(rawScores[attr] ?? 0);
    }
  }

  // Sort and extract 21 quantiles (every 5%)
  final result = <Attribute, List<double>>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!..sort();
    final quantiles = List<double>.generate(21, (i) {
      final idx = ((list.length - 1) * (i / 20)).round();
      return list[idx];
    });
    result[attr] = quantiles;
  }
  return result;
}

/// Format quantile arrays as a Dart const snippet for attribute_engine.dart.
String formatQuantiles(
    Map<Attribute, List<double>> male,
    Map<Attribute, List<double>> female) {
  String fmtArr(List<double> q) =>
      '[${q.map((v) => v.toStringAsFixed(3)).join(', ')}]';

  final buf = StringBuffer();
  buf.writeln('const _attrQuantilesMale = <Attribute, List<double>>{');
  for (final attr in Attribute.values) {
    buf.writeln('  Attribute.${attr.name}: ${fmtArr(male[attr]!)},');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln('const _attrQuantilesFemale = <Attribute, List<double>>{');
  for (final attr in Attribute.values) {
    buf.writeln('  Attribute.${attr.name}: ${fmtArr(female[attr]!)},');
  }
  buf.writeln('};');
  return buf.toString();
}

/// Realistic z-score input distribution for actual app users.
/// Real Korean adult faces have:
///  - Slightly positive bias (mean ~+0.2): selection bias + reference data offset
///  - Tighter spread (std ~0.85): real population variance is narrower than reference
///
/// Using N(0, 1) (pure standard normal) underestimates rule firing rates and
/// produces a μ/σ that doesn't reflect real users → score saturation in stability,
/// trustworthiness, etc. N(0.2, 0.85) is a closer approximation.
const double _inputMean = 0.2;
const double _inputStd = 0.85;

/// Generates [samples] random faces using N(_inputMean, _inputStd) for each
/// metric z-score, runs them through the attribute engine, and returns
/// the per-attribute (mean, std) of the raw scores.
Map<Attribute, ({double mean, double std})> calibrateMeanStd({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final rng = Random(seed);
  final raws = {for (final a in Attribute.values) a: <double>[]};

  double normal() {
    double u1, u2;
    do {
      u1 = rng.nextDouble();
    } while (u1 == 0.0);
    u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  for (int i = 0; i < samples; i++) {
    final continuousScores = <String, double>{};
    final intScores = <String, int>{};
    for (final info in metricInfoList) {
      final z = (normal() * _inputStd + _inputMean).clamp(-3.5, 3.5);
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
    final rawScores = Map<Attribute, double>.from(base);
    for (final rule in triggered) {
      for (final eff in rule.effects.entries) {
        rawScores[eff.key] = (rawScores[eff.key] ?? 0) + eff.value;
      }
    }
    for (final attr in Attribute.values) {
      raws[attr]!.add(rawScores[attr] ?? 0);
    }
  }

  final result = <Attribute, ({double mean, double std})>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!;
    final mean = list.reduce((a, b) => a + b) / list.length;
    final variance = list.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / list.length;
    result[attr] = (mean: mean, std: sqrt(variance));
  }
  return result;
}

String formatMeanStd(
    Map<Attribute, ({double mean, double std})> male,
    Map<Attribute, ({double mean, double std})> female) {
  final buf = StringBuffer();
  buf.writeln('const _attrCalibrationMale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = male[attr]!;
    buf.writeln('  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln('const _attrCalibrationFemale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = female[attr]!;
    buf.writeln('  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  return buf.toString();
}
