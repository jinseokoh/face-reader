// 첫인상 4축 분위표·계측 분위표·닮은 정도 거리 상수를 **AAF 11,800장 실측**으로 생성한다.
// 입력: test/support/aaf_faces.dart (26 계측 z + 대칭 symOverall z).
//
// 축의 정의(어떤 계측이 어느 부호·비중으로 들어가는가)는 문헌
// (`impression_evidence.dart`)에서 오고, 백분위는 이 실측 분포에서 온다.
//
// 실행:
//   flutter test test/impression_calibration_test.dart --plain-name 'generate'
// 출력 블록을 shared/lib/data/constants/impression_quantiles.dart 에 붙여넣는다.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/impression_features.dart';

import 'support/aaf_faces.dart';

List<double> _quantiles21(List<double> sorted) {
  final n = sorted.length;
  return [
    for (var k = 0; k <= 20; k++)
      sorted[((n - 1) * k / 20).round().clamp(0, n - 1)],
  ];
}

String _fmt(List<double> q) =>
    '[${q.map((v) => v.toStringAsFixed(3)).join(', ')}]';

void main() {
  test('generate impression quantiles + geometry distance median', () {
    final faces = loadAafFaces();
    final ids = metricInfoList.map((m) => m.id).toList();

    final buf = StringBuffer();
    buf.writeln('// 생성: flutter test test/impression_calibration_test.dart');
    buf.writeln('// AAF 11,800장 (male 5361 / female 6439) 실측.');
    for (final gender in Gender.values) {
      final byAxis = <ImpressionAxis, List<double>>{
        for (final a in ImpressionAxis.values) a: <double>[],
      };
      var n = 0;
      for (final f in faces) {
        if (f.gender != gender) continue;
        n++;
        final feats = buildImpressionFeatures(f.z,
            referenceMetricIds: ids, symmetryZ: f.symZ);
        final raw = computeImpressionRaw(feats);
        for (final a in ImpressionAxis.values) {
          byAxis[a]!.add(raw[a]!);
        }
      }
      buf.writeln('  Gender.${gender.name}: {  // n=$n');
      for (final a in ImpressionAxis.values) {
        final s = byAxis[a]!..sort();
        buf.writeln('    ImpressionAxis.${a.name}: ${_fmt(_quantiles21(s))},');
      }
      buf.writeln('  },');
    }

    // 계측 26개의 성별 21-point 분위 — 리포트의 "한국인 상위 N%" 표기용.
    buf.writeln('// ── metric quantiles (metric_quantiles.dart) ──');
    for (final gender in Gender.values) {
      final byId = <String, List<double>>{for (final id in ids) id: <double>[]};
      for (final f in faces) {
        if (f.gender != gender) continue;
        for (final id in ids) {
          byId[id]!.add(f.z[id]!);
        }
      }
      buf.writeln('  Gender.${gender.name}: {');
      for (final id in ids) {
        final s = byId[id]!..sort();
        buf.writeln("    '$id': ${_fmt(_quantiles21(s))},");
      }
      buf.writeln('  },');
    }

    // 닮은 정도 — 성별 안 무작위 쌍 20,000개의 거리 중앙값.
    final rng = Random(7);
    final dists = <double>[];
    for (var i = 0; i < 20000; i++) {
      final a = faces[rng.nextInt(faces.length)];
      var b = faces[rng.nextInt(faces.length)];
      while (identical(a, b)) {
        b = faces[rng.nextInt(faces.length)];
      }
      dists.add(geometryDistance(a.z, b.z, ids));
    }
    dists.sort();
    final median = dists[dists.length ~/ 2];
    buf.writeln('// geometry distance median (random pairs, n=20000): '
        '${median.toStringAsFixed(4)}');

    // ignore: avoid_print
    print(buf.toString());
  }, skip: false);
}
