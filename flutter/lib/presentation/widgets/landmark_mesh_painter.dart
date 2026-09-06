import 'package:face_engine/domain/services/landmark_normalize.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 정규화된 얼굴(§5)을 윤곽선으로 그린다 — 한 얼굴(§55 얼굴 지도) 또는 두 얼굴
/// 겹치기(§24). 입력은 `normalizeLandmarks`/`alignFaces` 결과(무게중심 0,
/// RMS 1). [highlight] 영역은 굵게, 나머지는 얇게.
class LandmarkMeshPainter extends CustomPainter {
  final List<List<double>> a;
  final List<List<double>>? b;
  final Set<String> highlight;
  final Color colorA;
  final Color colorB;

  const LandmarkMeshPainter({
    required this.a,
    this.b,
    this.highlight = const {},
    this.colorA = AppColors.gold,
    this.colorB = AppColors.info,
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

  @override
  void paint(Canvas canvas, Size size) {
    _drawFace(canvas, size, a, colorA);
    final other = b;
    if (other != null) _drawFace(canvas, size, other, colorB);
  }

  @override
  bool shouldRepaint(LandmarkMeshPainter old) =>
      old.a != a || old.b != b || old.highlight != highlight;
}
