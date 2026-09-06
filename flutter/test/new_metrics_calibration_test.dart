// §6 추가 계측 4개(faceArea·outlineCurvature·eyeSizeBalance·noseAxisTilt)의 AAF
// 11,800장 성별 mean/sd 를 생성한다 → face_reference_data.dart 의 eastAsian 블록.
// (다른 인종 블록은 지금 규칙대로 eastAsian 값을 복사한다 — AAF-only reference.)
// 실행: flutter test test/new_metrics_calibration_test.dart --plain-name generate

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_engine/data/enums/gender.dart';
import 'package:facely/domain/services/face_metrics.dart';

import 'support/aaf_landmarks.dart';

const _ids = ['faceArea', 'outlineCurvature', 'eyeSizeBalance', 'noseAxisTilt'];

void main() {
  test('generate new metric reference', () {
    final faces = loadAafLandmarks();
    final buf = StringBuffer();
    for (final g in Gender.values) {
      final vals = {for (final id in _ids) id: <double>[]};
      for (final f in faces.where((f) => f.gender == g)) {
        final m = FaceMetrics(
                [for (final p in f.points) FaceMeshLandmark(x: p[0], y: p[1], z: 0)])
            .computeAll();
        for (final id in _ids) {
          vals[id]!.add(m[id]!);
        }
      }
      buf.writeln('  Gender.${g.name}: // n=${vals[_ids[0]]!.length}');
      for (final id in _ids) {
        final v = vals[id]!;
        final mean = v.reduce((a, b) => a + b) / v.length;
        final sd = sqrt(v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length);
        buf.writeln("      '$id': MetricReference(${mean.toStringAsFixed(5)}, ${sd.toStringAsFixed(5)}),");
      }
    }
    // ignore: avoid_print
    print(buf.toString());
  });
}
