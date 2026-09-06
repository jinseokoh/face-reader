// 얼굴 지도(§55) — 평균 얼굴 상수와 계측 측정선 표의 정합성.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/average_face.dart';
import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:facely/presentation/widgets/metric_landmark_paths.dart';

void main() {
  test('평균 얼굴 — 성별 2개, 468점, 무게중심 0·RMS 1·눈꼬리 수평', () {
    for (final g in Gender.values) {
      final f = kAverageFace[g]!;
      expect(f.length, 468, reason: g.name);
      var cx = 0.0, cy = 0.0, ss = 0.0;
      for (final p in f) {
        cx += p[0];
        cy += p[1];
        ss += p[0] * p[0] + p[1] * p[1];
      }
      expect(cx / 468, closeTo(0, 1e-3));
      expect(cy / 468, closeTo(0, 1e-3));
      expect(sqrt(ss / 468), closeTo(1, 1e-3));
      expect(f[263][1] - f[33][1], closeTo(0, 1e-3));
    }
  });

  test('측정선 표 — referenceData 계측 전부, 인덱스는 468 안', () {
    final ids = metricInfoList.map((m) => m.id).toSet();
    expect(metricLandmarkPaths.keys.toSet(), ids);
    for (final e in metricLandmarkPaths.entries) {
      for (final line in e.value) {
        expect(line.length, greaterThanOrEqualTo(2), reason: e.key);
        for (final i in line) {
          expect(i, inInclusiveRange(0, 467), reason: e.key);
        }
      }
    }
  });
}
