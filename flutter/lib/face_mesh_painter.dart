import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

class FaceMeshPainter extends CustomPainter {
  final FaceMeshResult result;
  final bool isFrontCamera;
  final Color overlayColor;

  FaceMeshPainter({
    required this.result,
    required this.isFrontCamera,
    this.overlayColor = Colors.redAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trianglePaint = Paint()
      ..color = overlayColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Draw mesh triangles
    for (final triangle in result.triangles) {
      final points = triangle.points;
      if (points.length == 3) {
        final path = Path();
        final p0 = _toOffset(points[0], size);
        final p1 = _toOffset(points[1], size);
        final p2 = _toOffset(points[2], size);
        path.moveTo(p0.dx, p0.dy);
        path.lineTo(p1.dx, p1.dy);
        path.lineTo(p2.dx, p2.dy);
        path.close();
        canvas.drawPath(path, trianglePaint);
      }
    }

    // Draw landmark points
    final pointPaint = Paint()
      ..color = overlayColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;

    for (final lm in result.landmarks) {
      final offset = _toOffset(lm, size);
      canvas.drawCircle(offset, 1.5, pointPaint);
    }
  }

  Offset _toOffset(FaceMeshLandmark lm, Size size) {
    final x = lm.x.clamp(0.0, 1.0);
    final y = lm.y.clamp(0.0, 1.0);
    if (isFrontCamera) {
      return Offset((1.0 - x) * size.width, y * size.height);
    }
    return Offset(x * size.width, y * size.height);
  }

  @override
  bool shouldRepaint(FaceMeshPainter oldDelegate) => true;
}
