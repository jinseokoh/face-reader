// Run with: flutter test test/calibration_test.dart
// One-shot tool: outputs 21-point quantile arrays per attribute that should be
// copy-pasted into attribute_engine.dart's _attrQuantilesMale/Female maps.

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
}
