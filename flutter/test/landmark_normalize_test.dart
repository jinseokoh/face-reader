// §5 정규화 · Procrustes (§75 단위 테스트) — 실제 AAF 랜드마크 픽스처.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/landmark_normalize.dart';

import 'support/demo_landmarks.dart';

List<List<double>> _transform(List<List<double>> pts,
    {double dx = 0, double dy = 0, double scale = 1, double theta = 0}) {
  final c = cos(theta), s = sin(theta);
  return [
    for (final p in pts)
      [
        (p[0] * c - p[1] * s) * scale + dx,
        (p[0] * s + p[1] * c) * scale + dy,
      ],
  ];
}

double _maxDiff(List<List<double>> a, List<List<double>> b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = max(m, max((a[i][0] - b[i][0]).abs(), (a[i][1] - b[i][1]).abs()));
  }
  return m;
}

void main() {
  final face = demoLandmarks(Gender.male);

  test('정규화 결과 — 무게중심 0, RMS 1, 눈꼬리 수평', () {
    final n = normalizeLandmarks(face);
    var cx = 0.0, cy = 0.0, ss = 0.0;
    for (final p in n) {
      cx += p[0];
      cy += p[1];
      ss += p[0] * p[0] + p[1] * p[1];
    }
    expect(cx / n.length, closeTo(0, 1e-9));
    expect(cy / n.length, closeTo(0, 1e-9));
    expect(sqrt(ss / n.length), closeTo(1, 1e-9));
    expect(n[263][1] - n[33][1], closeTo(0, 1e-9));
  });

  test('이동·크기·회전을 바꿔도 정규화 결과가 같다', () {
    final base = normalizeLandmarks(face);
    final moved = normalizeLandmarks(
        _transform(face, dx: 0.3, dy: -0.2, scale: 2.5, theta: 0.4));
    expect(_maxDiff(base, moved), lessThan(1e-9));
  });

  test('Procrustes — 같은 얼굴을 돌려 넣으면 거리 0, 다른 얼굴은 0 보다 크다', () {
    final same = alignFaces(face, _transform(face, theta: -0.7, scale: 0.5));
    expect(same.distance, closeTo(0, 1e-9));
    final other = alignFaces(face, demoLandmarks(Gender.female));
    expect(other.distance, greaterThan(0.01));
    for (final r in landmarkRegions.keys) {
      expect(other.regionDistance(r), greaterThan(0));
    }
  });

  test('영역 인덱스는 전부 468 안이고 윤곽 인덱스는 영역 안에 있다', () {
    for (final e in landmarkRegions.entries) {
      for (final i in e.value) {
        expect(i, inInclusiveRange(0, 467), reason: e.key);
      }
    }
    for (final e in landmarkContours.entries) {
      final region = landmarkRegions[e.key]!.toSet();
      for (final line in e.value) {
        for (final i in line) {
          expect(region, contains(i), reason: '${e.key} $i');
        }
      }
    }
  });
}
