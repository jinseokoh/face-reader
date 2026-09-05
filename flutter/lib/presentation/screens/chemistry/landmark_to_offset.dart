import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

/// MediaPipe raw landmark → 화면 픽셀 좌표. 카메라 회전 보정과 Android 전면
/// 카메라 미러링을 적용한다. 메시·계측 오버레이 두 painter 가 같은 변환을 쓴다.
Offset landmarkToOffset(
  FaceMeshLandmark lm,
  Size size,
  int rotationCompensation,
  CameraLensDirection lensDirection,
) {
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
