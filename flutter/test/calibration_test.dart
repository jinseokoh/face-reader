// Run with: flutter test test/calibration_test.dart
// One-shot tool:
//   1) agnostic quantile arrays per attribute (male/female) — drop-in for
//      attribute_normalize.dart `_attrQuantilesMale / _attrQuantilesFemale`.
//   2) per-shape quantile tables (5 known shapes × gender × attr × 21 pt) —
//      drop-in for `_attrQuantilesByShape`. Shape-conditional bias 근본 제거.

import 'package:flutter_test/flutter_test.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/score_calibration.dart';

void main() {
  test('attribute calibration (Monte Carlo)', () {
    const samples = 20000;

    final maleQ =
        calibrateQuantiles(samples: samples, gender: Gender.male, seed: 42);
    final femaleQ =
        calibrateQuantiles(samples: samples, gender: Gender.female, seed: 42);
    final maleMS =
        calibrateMeanStd(samples: samples, gender: Gender.male, seed: 42);
    final femaleMS =
        calibrateMeanStd(samples: samples, gender: Gender.female, seed: 42);

    // ignore: avoid_print
    print('\n========== Mean/Std Calibration ($samples samples) ==========');
    // ignore: avoid_print
    print(formatMeanStd(maleMS, femaleMS));
    // ignore: avoid_print
    print('\n========== Quantile Calibration ($samples samples) ==========');
    // ignore: avoid_print
    print(formatQuantiles(maleQ, femaleQ));
  });

  test('per-shape quantile tables (Opt-D)', () {
    const samples = 20000;

    final maleByShape = calibrateQuantilesByShape(
        samples: samples, gender: Gender.male, seed: 42);
    final femaleByShape = calibrateQuantilesByShape(
        samples: samples, gender: Gender.female, seed: 1042);

    // ignore: avoid_print
    print('\n========== Per-Shape Quantile Calibration '
        '($samples × 5 shapes × 2 genders) ==========');
    // ignore: avoid_print
    print(formatQuantilesByShape(maleByShape, femaleByShape));
  });
}
