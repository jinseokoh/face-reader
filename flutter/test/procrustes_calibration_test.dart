// 닮은 정도(Procrustes)·케미 등급 경계를 **AAF 11,800장 실측 좌표**로 생성한다.
//
// 출력 1 → shared/lib/data/constants/procrustes_reference.dart
//   kProcrustesDistanceMedian : 무작위 쌍 RMS 거리 중앙값 (overall + 영역 6)
//   kRegionSimilarityQuartiles: 닮은 정도 [p75, p50, p25]
// 출력 2 → shared/lib/domain/services/compat/team.dart
//   kFirstImpressionBandCuts  : 케미 합(조화도+보완도+닮은 정도) [p75, p50, p25]
//   kTeamBlockCapFirstImpression: p25 바로 아래 (0.1 내림)
// 계측·대칭·첫인상은 전부 좌표에서 앱과 같은 식으로 다시 만든다 (§59).
//
// 실행: flutter test test/procrustes_calibration_test.dart --plain-name generate

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/landmark_normalize.dart';
import 'package:face_engine/domain/services/symmetry_metrics.dart';
import 'package:facely/domain/services/face_metrics.dart';

import 'support/aaf_landmarks.dart';

double _q(List<double> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

void main() {
  test('generate procrustes reference + chemistry band cuts', () {
    final faces = loadAafLandmarks();
    final ids = metricInfoList.map((m) => m.id).toList();
    final rng = Random(11);
    const n = 20000;

    // 1) 거리 중앙값 — 정렬 한 번에 overall + 영역.
    final dist = <String, List<double>>{
      'overall': [],
      for (final r in landmarkRegions.keys) r: [],
    };
    final pairs = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final a = rng.nextInt(faces.length);
      var b = rng.nextInt(faces.length);
      while (b == a) {
        b = rng.nextInt(faces.length);
      }
      pairs.add((a, b));
      final al = alignFaces(faces[a].points, faces[b].points);
      dist['overall']!.add(al.distance);
      for (final r in landmarkRegions.keys) {
        dist[r]!.add(al.regionDistance(r));
      }
    }
    final median = <String, double>{};
    final buf = StringBuffer();
    buf.writeln('// ── procrustes_reference.dart ──');
    buf.writeln('const Map<String, double> kProcrustesDistanceMedian = {');
    for (final e in dist.entries) {
      final s = [...e.value]..sort();
      median[e.key] = _q(s, 0.5);
      buf.writeln("  '${e.key}': ${median[e.key]!.toStringAsFixed(5)},");
    }
    buf.writeln('};');

    // 2) 닮은 정도 사분위 — 위 중앙값으로 환산.
    double sim(double d, String r) => 100 * exp(-ln2 * d / median[r]!);
    buf.writeln('const Map<String, List<double>> kRegionSimilarityQuartiles = {');
    for (final e in dist.entries) {
      final s = [for (final d in e.value) sim(d, e.key)]..sort();
      buf.writeln("  '${e.key}': [${_q(s, 0.75).toStringAsFixed(1)}, "
          "${_q(s, 0.5).toStringAsFixed(1)}, ${_q(s, 0.25).toStringAsFixed(1)}],");
    }
    buf.writeln('};');

    // 3) 케미 합 — 같은 쌍. 첫인상 프로필은 좌표 → 계측 → z → 축.
    final profiles = <int, FirstImpressionProfile>{};
    FirstImpressionProfile profileOf(int i) => profiles.putIfAbsent(i, () {
          final f = faces[i];
          final lms = [
            for (final p in f.points) FaceMeshLandmark(x: p[0], y: p[1], z: 0)
          ];
          final raw = FaceMetrics(lms).computeAll();
          final refs = referenceData[Ethnicity.eastAsian]![f.gender]!;
          final z = <String, double>{
            for (final id in ids)
              id: (raw[id]! - refs[id]!.mean) / refs[id]!.sd,
          };
          return computeFirstImpression(z,
              gender: f.gender,
              referenceMetricIds: ids,
              symmetryZ:
                  symmetryOverallZ(computeSymmetry(f.points), f.gender));
        });
    final chem = <double>[];
    for (var i = 0; i < pairs.length; i++) {
      final (a, b) = pairs[i];
      chem.add(harmony(profileOf(a), profileOf(b)) +
          complementarity(profileOf(a), profileOf(b)) +
          sim(dist['overall']![i], 'overall'));
    }
    chem.sort();
    final p25 = _q(chem, 0.25);
    buf.writeln('// ── team.dart ──');
    buf.writeln('const List<double> kFirstImpressionBandCuts = '
        '[${_q(chem, 0.75).toStringAsFixed(1)}, ${_q(chem, 0.5).toStringAsFixed(1)}, ${p25.toStringAsFixed(1)}];');
    buf.writeln('const double kTeamBlockCapFirstImpression = '
        '${((p25 * 10).floor() / 10 - 0.1).toStringAsFixed(1)};');
    // ignore: avoid_print
    print(buf.toString());
  });
}
