import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

/// Renders face mesh landmarks over a CameraPreview.
///
/// Follows the official mediapipe_face_mesh camera demo approach:
/// - Landmarks are returned in raw camera-frame coordinates by the C layer
/// - Painter applies rotation compensation to map to screen-upright space
/// - Android front camera: OS mirrors the preview, so flip x to match
/// - iOS front camera: CameraPreview does NOT mirror, so no flip needed
class FaceMeshPainter extends CustomPainter {
  final FaceMeshResult result;
  final int rotationCompensation;
  final CameraLensDirection lensDirection;
  final Color overlayColor;

  FaceMeshPainter({
    required this.result,
    required this.rotationCompensation,
    required this.lensDirection,
    this.overlayColor = Colors.redAccent,
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

    final pointRadius = size.shortestSide * 0.006;

    for (final lm in result.landmarks) {
      final offset = _toOffset(lm, size);
      canvas.drawCircle(offset, pointRadius, pointPaint);
    }
  }

  Offset _toOffset(FaceMeshLandmark lm, Size size) {
    double xOut = lm.x.clamp(0.0, 1.0);
    double yOut = lm.y.clamp(0.0, 1.0);

    // Landmarks are in raw camera-frame coordinates.
    // Apply rotation compensation to map into screen-upright space.
    switch (rotationCompensation) {
      case 90:
        final ox = xOut;
        xOut = 1.0 - yOut;
        yOut = ox;
        break;
      case 180:
        xOut = 1.0 - xOut;
        yOut = 1.0 - yOut;
        break;
      case 270:
        final ox = xOut;
        xOut = yOut;
        yOut = 1.0 - ox;
        break;
      default:
        break;
    }

    // Android front camera preview is mirrored by the OS → flip x.
    // iOS front camera preview is NOT mirrored → no flip.
    if (!Platform.isIOS && lensDirection == CameraLensDirection.front) {
      xOut = 1.0 - xOut;
    }

    return Offset(
      xOut.clamp(0.0, 1.0) * size.width,
      yOut.clamp(0.0, 1.0) * size.height,
    );
  }

  @override
  bool shouldRepaint(FaceMeshPainter oldDelegate) => true;
}
