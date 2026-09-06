// 좌우 대칭 계측 — 완전 대칭 얼굴은 0, 한쪽만 흔들면 그 영역만 커진다.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/domain/services/symmetry_metrics.dart';

/// 468점을 midline(x=0.5, 세로) 기준 좌우 대칭으로 만든 가짜 얼굴.
List<List<double>> _mirrorFace() {
  final pts = List.generate(468, (i) => [0.5, 0.5 + (i % 40) * 0.01]);
  pts[168] = [0.5, 0.3]; // nasion
  pts[152] = [0.5, 0.9]; // chin
  pts[234] = [0.2, 0.55]; // 얼굴 가장자리 (폭 0.6)
  pts[454] = [0.8, 0.55];
  var k = 0;
  for (final pairs in symmetryPairs.values) {
    for (final p in pairs) {
      final dx = 0.05 + 0.02 * (k % 7);
      final y = 0.35 + 0.05 * (k % 9);
      pts[p[0]] = [0.5 - dx, y];
      pts[p[1]] = [0.5 + dx, y];
      k++;
    }
  }
  return pts;
}

void main() {
  test('완전 대칭 얼굴은 전 영역 0', () {
    final s = computeSymmetry(_mirrorFace());
    expect(s.keys.toSet(), symmetryIds.toSet());
    for (final id in symmetryIds) {
      expect(s[id], closeTo(0, 1e-9), reason: id);
    }
  });

  test('입꼬리 한쪽만 벌리면 입 영역만 커지고 overall 은 그 1/5', () {
    final pts = _mirrorFace();
    final fw = pts[454][0] - pts[234][0]; // 윤곽 쌍(234,454)이 폭을 정한다
    pts[291] = [pts[291][0] + 0.06, pts[291][1]];
    final s = computeSymmetry(pts);
    expect(s['symEyes'], closeTo(0, 1e-9));
    expect(s['symMouth'], closeTo(0.06 / fw / 4, 1e-9)); // 쌍 4개 평균
    expect(s['symOverall'], closeTo(s['symMouth']! / 5, 1e-9));
  });

  test('전체 이동·회전·확대에 불변', () {
    final base = computeSymmetry(_mirrorFace());
    final moved = [
      for (final p in _mirrorFace()) [p[0] * 2 + 0.1, p[1] * 2 - 0.2],
    ];
    final s = computeSymmetry(moved);
    for (final id in symmetryIds) {
      expect(s[id], closeTo(base[id]!, 1e-9), reason: id);
    }
  });

  test('aspect 보정은 y 만 늘린다 — 세로 어긋남이 aspect 배로 커진다', () {
    final pts = _mirrorFace();
    pts[263] = [pts[263][0], pts[263][1] + 0.01];
    final a1 = computeSymmetry(pts)['symEyes']!;
    final a2 = computeSymmetry(pts, aspect: 2.0)['symEyes']!;
    expect(a2 / a1, closeTo(2.0, 1e-6));
  });
}
