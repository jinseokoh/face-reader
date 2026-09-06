// 대칭 계측의 성별 reference(평균·표준편차)와 21-point 분위표를 AAF 실측으로 생성한다.
//
// 입력: tools/face_shape_ml/out/aaf_per_face_sym.csv
//   생성 = tools/face_shape_ml/extract_aaf_symmetry.py (28 계측 + 대칭 6)
// 실행:
//   flutter test test/symmetry_calibration_test.dart --plain-name 'generate'
// 출력 블록을 shared/lib/data/constants/symmetry_reference.dart 에 붙여넣는다.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/domain/services/symmetry_metrics.dart';

const aafSymCsvPath =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_per_face_sym.csv';

List<double> _quantiles21(List<double> sorted) {
  final n = sorted.length;
  return [
    for (var k = 0; k <= 20; k++)
      sorted[((n - 1) * k / 20).round().clamp(0, n - 1)],
  ];
}

String _fmt(List<double> q) =>
    '[${q.map((v) => v.toStringAsFixed(5)).join(', ')}]';

void main() {
  test('generate symmetry reference', () {
    final lines = File(aafSymCsvPath).readAsLinesSync();
    final header = lines.first.split(',');
    final gi = header.indexOf('gender');
    final cols = {for (final id in symmetryIds) id: header.indexOf(id)};

    final buf = StringBuffer();
    buf.writeln('// 생성: flutter test test/symmetry_calibration_test.dart');
    for (final gender in ['male', 'female']) {
      final byId = {for (final id in symmetryIds) id: <double>[]};
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;
        final c = line.split(',');
        if (c[gi] != gender) continue;
        for (final id in symmetryIds) {
          byId[id]!.add(double.parse(c[cols[id]!]));
        }
      }
      buf.writeln('  Gender.$gender: {  // n=${byId[symmetryIds.first]!.length}');
      for (final id in symmetryIds) {
        final xs = byId[id]!..sort();
        final mean = xs.reduce((a, b) => a + b) / xs.length;
        var ss = 0.0;
        for (final v in xs) {
          ss += (v - mean) * (v - mean);
        }
        final sd = sqrt(ss / xs.length); // population sd (ddof=0), face_reference_data 와 동일
        buf.writeln(
            "    '$id': SymmetryReference(${mean.toStringAsFixed(6)}, ${sd.toStringAsFixed(6)}, ${_fmt(_quantiles21(xs))}),");
      }
      buf.writeln('  },');
    }
    // ignore: avoid_print
    print(buf.toString());
  });
}
