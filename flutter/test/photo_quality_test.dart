// 앨범 사진 품질 검사(§60) — 얼굴 크기·밝기·자르기 영역.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:facely/domain/services/photo_quality.dart';

Uint8List _solid(int w, int h, int v) =>
    Uint8List.fromList(List.filled(w * h * 4, v));

void main() {
  test('작은 얼굴은 거른다 — 짧은 변 12% 미만', () {
    expect(
      photoQualityIssue(
          face: const Rect.fromLTWH(0, 0, 100, 100),
          imageW: 1000,
          imageH: 1000,
          meanLuma: 120),
      contains('너무 작게'),
    );
    expect(
      photoQualityIssue(
          face: const Rect.fromLTWH(0, 0, 130, 130),
          imageW: 1000,
          imageH: 1000,
          meanLuma: 120),
      isNull,
    );
  });

  test('어두운 얼굴은 거른다 — 평균 밝기 40 미만', () {
    expect(
      photoQualityIssue(
          face: const Rect.fromLTWH(0, 0, 300, 300),
          imageW: 1000,
          imageH: 1000,
          meanLuma: 30),
      contains('너무 어둡'),
    );
  });

  test('평균 밝기 — 단색 버퍼에서 그 값이 나온다', () {
    final rgba = _solid(64, 64, 200);
    expect(
      meanLumaInRect(rgba, 64, 64, const Rect.fromLTWH(8, 8, 40, 40)),
      closeTo(200, 1e-6),
    );
  });

  test('자르기 영역 — 1.6배 확장 후 사진 안으로 클램프', () {
    final r = expandedCropRect(const Rect.fromLTWH(900, 0, 100, 100), 1000, 1000);
    expect(r.left, closeTo(870, 1e-9));
    expect(r.top, 0);
    expect(r.right, 1000);
    expect(r.bottom, closeTo(130, 1e-9));
  });
}
