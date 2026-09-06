import 'package:face_engine/domain/services/landmark_normalize.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 정규화된 얼굴(§5)을 윤곽선으로 그린다 — 한 얼굴(§55 얼굴 지도) 또는 두 얼굴
/// 겹치기(§24). 입력은 `normalizeLandmarks`/`alignFaces` 결과(무게중심 0,
/// RMS 1). [highlight] 영역은 굵게, 나머지는 얇게.
///
/// 얼굴 지도: [background] 에 기준 집단 평균 얼굴을 회색으로 먼저 깔고,
/// [metricPaths] 의 측정선을 평균 얼굴과 [a] 양쪽에 굵게 그어 차이를 보인다.
class LandmarkMeshPainter extends CustomPainter {
  final List<List<double>> a;
  final List<List<double>>? b;
  final List<List<double>>? background;
  final Set<String> highlight;
  final List<List<int>> metricPaths;
  final Color colorA;
  final Color colorB;
  final Color colorBackground;

  const LandmarkMeshPainter({
    required this.a,
    this.b,
    this.background,
    this.highlight = const {},
    this.metricPaths = const [],
    this.colorA = AppColors.gold,
    this.colorB = AppColors.info,
    this.colorBackground = AppColors.textPrimary,
  });

  /// 정규화 좌표는 대략 ±2.2 안에 든다 — 그 범위를 상자에 맞춘다.
  static const double _extent = 2.3;

  Offset _map(List<double> p, Size size) {
    final s = size.shortestSide / (2 * _extent);
    return Offset(size.width / 2 + p[0] * s, size.height / 2 + p[1] * s);
  }

  void _drawFace(Canvas canvas, Size size, List<List<double>> pts, Color color) {
    for (final e in landmarkContours.entries) {
      final strong = highlight.contains(e.key);
      final paint = Paint()
        ..color = strong ? color : color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strong ? 2.2 : 1.0
        ..strokeCap = StrokeCap.round;
      for (final line in e.value) {
        final path = Path();
        for (var i = 0; i < line.length; i++) {
          final o = _map(pts[line[i]], size);
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawMetricPaths(
      Canvas canvas, Size size, List<List<double>> pts, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    for (final line in metricPaths) {
      final path = Path();
      for (var i = 0; i < line.length; i++) {
        final o = _map(pts[line[i]], size);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawCircle(o, 2.6, dot);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = background;
    if (bg != null) {
      _drawFace(canvas, size, bg, colorBackground);
      _drawMetricPaths(canvas, size, bg, colorBackground);
    }
    _drawFace(canvas, size, a, colorA);
    _drawMetricPaths(canvas, size, a, colorA);
    final other = b;
    if (other != null) _drawFace(canvas, size, other, colorB);
  }

  @override
  bool shouldRepaint(LandmarkMeshPainter old) =>
      old.a != a ||
      old.b != b ||
      old.background != background ||
      old.highlight != highlight ||
      old.metricPaths != metricPaths;
}
