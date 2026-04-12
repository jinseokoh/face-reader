// Monte Carlo distribution + tier histogram for the compatibility engine.
//
// Run via: flutter test test/compat_calibration_test.dart
//
// Use the printed p30 / p60 / p90 to update _resolveLabel thresholds in
// lib/presentation/screens/compatibility/compatibility_report_page.dart so
// that real users see roughly:
//   30% 어려운 궁합
//   30% 보통
//   30% 좋은 궁합
//   10% 천생연분

import 'package:flutter_test/flutter_test.dart';
import 'package:face_reader/domain/services/compat_calibration.dart';

void main() {
  test('compatibility score Monte Carlo distribution + tier histogram', () {
    const samples = 20000;
    final p = calibrateCompatibility(samples: samples);

    // ignore: avoid_print
    print('\n========== Compatibility Score Distribution ($samples pairs) ==========');
    final marks = [
      ('min   ', p.min),
      ('p1    ', p.p1),
      ('p5    ', p.p5),
      ('p10   ', p.p10),
      ('p20   ', p.p20),
      ('p30   ', p.p30), // ← 어려운 / 보통 boundary target
      ('p40   ', p.p40),
      ('p50   ', p.p50),
      ('p60   ', p.p60), // ← 보통 / 좋은 boundary target
      ('p70   ', p.p70),
      ('p80   ', p.p80),
      ('p90   ', p.p90), // ← 좋은 / 천생연분 boundary target
      ('p95   ', p.p95),
      ('p99   ', p.p99),
      ('max   ', p.max),
      ('mean  ', p.mean),
    ];
    for (final m in marks) {
      // ignore: avoid_print
      print('${m.$1} ${m.$2.toStringAsFixed(2)}');
    }

    // ─── Tier histogram using TARGET thresholds (p30, p60, p90) ───
    final t30 = p.p30;
    final t60 = p.p60;
    final t90 = p.p90;
    final hard = p.countWhere((s) => s < t30);
    final mid = p.countWhere((s) => s >= t30 && s < t60);
    final good = p.countWhere((s) => s >= t60 && s < t90);
    final perfect = p.countWhere((s) => s >= t90);

    // ignore: avoid_print
    print('\n========== Tier Histogram (using empirical p30/p60/p90) ==========');
    // ignore: avoid_print
    print('어려운 궁합 (< ${t30.toStringAsFixed(0)}): $hard  (${(hard / samples * 100).toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('보통       ($t30..${t60.toStringAsFixed(0)}): $mid  (${(mid / samples * 100).toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('좋은 궁합  ($t60..${t90.toStringAsFixed(0)}): $good  (${(good / samples * 100).toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('천생연분   (≥ ${t90.toStringAsFixed(0)}): $perfect  (${(perfect / samples * 100).toStringAsFixed(1)}%)');

    // ─── Recommended Dart constants snippet ───
    // ignore: avoid_print
    print('\n========== Suggested _resolveLabel thresholds ==========');
    // ignore: avoid_print
    print('  if (score >= ${t90.round()}) return \'천생연분\';   // top 10%');
    // ignore: avoid_print
    print('  if (score >= ${t60.round()}) return \'좋은 궁합\'; // 60-90%');
    // ignore: avoid_print
    print('  if (score >= ${t30.round()}) return \'보통\';      // 30-60%');
    // ignore: avoid_print
    print('  return \'어려운 궁합\';                            // bottom 30%');
  });
}
