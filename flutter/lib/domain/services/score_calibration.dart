/// Monte Carlo calibration for attribute raw-score distributions.
///
/// Run `flutter test test/calibration_test.dart` to regenerate the 21-point
/// quantile tables in `attribute_normalize.dart`.
///
/// Realistic z-score input: N(0.2, 0.85) per metric — slight positive bias +
/// tighter spread than standard normal better matches observed Korean adult
/// faces (see `_inputMean` / `_inputStd` below).
library;

import 'dart:math';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

/// 21-point quantile array per attribute (p0, p5, …, p100).
Map<Attribute, List<double>> calibrateQuantiles({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final raws = _simulateRaws(samples: samples, seed: seed, gender: gender);
  final result = <Attribute, List<double>>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!..sort();
    result[attr] = List<double>.generate(21, (i) {
      final idx = ((list.length - 1) * (i / 20)).round();
      return list[idx];
    });
  }
  return result;
}

/// Per-attribute (mean, std) of raw scores — for distribution-health checks.
Map<Attribute, ({double mean, double std})> calibrateMeanStd({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final raws = _simulateRaws(samples: samples, seed: seed, gender: gender);
  final result = <Attribute, ({double mean, double std})>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!;
    final mean = list.reduce((a, b) => a + b) / list.length;
    final variance =
        list.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            list.length;
    result[attr] = (mean: mean, std: sqrt(variance));
  }
  return result;
}

Map<Attribute, List<double>> _simulateRaws({
  required int samples,
  required int seed,
  required Gender gender,
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
    final z = <String, double>{};
    for (final info in metricInfoList) {
      z[info.id] = (normal() * _inputStd + _inputMean).clamp(-3.5, 3.5);
    }
    final tree = scoreTree(z);
    final scores = deriveAttributeScores(
      tree: tree,
      gender: gender,
      isOver50: false,
      hasLateral: false,
    );
    for (final attr in Attribute.values) {
      raws[attr]!.add(scores[attr] ?? 0.0);
    }
  }
  return raws;
}

/// Format quantiles as a drop-in Dart const block for attribute_normalize.dart.
String formatQuantiles(
    Map<Attribute, List<double>> male, Map<Attribute, List<double>> female) {
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

String formatMeanStd(Map<Attribute, ({double mean, double std})> male,
    Map<Attribute, ({double mean, double std})> female) {
  final buf = StringBuffer();
  buf.writeln(
      'const _attrCalibrationMale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = male[attr]!;
    buf.writeln(
        '  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln(
      'const _attrCalibrationFemale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = female[attr]!;
    buf.writeln(
        '  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  return buf.toString();
}

const double _inputMean = 0.2;
const double _inputStd = 0.85;
