import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

class FaceMeshPainter extends CustomPainter {
  final FaceMeshResult result;
  final bool isFrontCamera;
  final Color overlayColor;
  final int sensorOrientation;
  final bool unrotateForDisplay;

  FaceMeshPainter({
    required this.result,
    required this.isFrontCamera,
    this.overlayColor = Colors.redAccent,
    this.sensorOrientation = 0,
    this.unrotateForDisplay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trianglePaint = Paint()
      ..color = overlayColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

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
    double x = lm.x.clamp(0.0, 1.0);
    double y = lm.y.clamp(0.0, 1.0);

    // On iOS the CameraPreview shows the raw landscape texture while
    // landmarks are in the rotated portrait space. Un-rotate them so
    // they match the displayed texture.
    if (unrotateForDisplay) {
      final ox = x;
      final oy = y;
      if (sensorOrientation == 90) {
        // portrait(x,y) → landscape(y, 1-x)
        x = oy;
        y = 1.0 - ox;
      } else if (sensorOrientation == 270) {
        // portrait(x,y) → landscape(1-y, x)
        x = 1.0 - oy;
        y = ox;
      }
    }

    if (isFrontCamera) {
      return Offset((1.0 - x) * size.width, y * size.height);
    }
    return Offset(x * size.width, y * size.height);
  }

  @override
  bool shouldRepaint(FaceMeshPainter oldDelegate) => true;
}
