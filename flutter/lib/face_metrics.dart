import 'dart:math';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

// MediaPipe Face Mesh landmark indices
abstract class LandmarkIndex {
  static const foreheadTop = 10;
  static const nasion = 168;
  static const noseTip = 1;
  static const subnasale = 94;
  static const rightAla = 98;
  static const leftAla = 327;
  static const rightEndocanthion = 133;
  static const leftEndocanthion = 362;
  static const rightExocanthion = 33;
  static const leftExocanthion = 263;
  static const rightCheilion = 61;
  static const leftCheilion = 291;
  static const upperLipTop = 0;
  static const lowerLipBottom = 17;
  static const upperLipInner = 13;
  static const lowerLipInner = 14;
  static const chin = 152;
  static const rightFaceEdge = 234;
  static const leftFaceEdge = 454;
  static const rightEyeTop = 159;
  static const rightEyeBottom = 145;
  static const leftEyeTop = 386;
  static const leftEyeBottom = 374;
}

class FaceMetrics {
  final List<FaceMeshLandmark> landmarks;

  FaceMetrics(this.landmarks);

  FaceMeshLandmark _lm(int index) => landmarks[index];

  double _dist(int a, int b) {
    final la = _lm(a);
    final lb = _lm(b);
    final dx = la.x - lb.x;
    final dy = la.y - lb.y;
    return sqrt(dx * dx + dy * dy);
  }

  double get faceHeight => _dist(LandmarkIndex.foreheadTop, LandmarkIndex.chin);
  double get faceWidth => _dist(LandmarkIndex.rightFaceEdge, LandmarkIndex.leftFaceEdge);

  // 1. Face aspect ratio
  double get faceAspectRatio => faceHeight / faceWidth;

  // 2. Upper face ratio (forehead to nasion / face height)
  double get upperFaceRatio => _dist(LandmarkIndex.foreheadTop, LandmarkIndex.nasion) / faceHeight;

  // 3. Mid face ratio (nasion to subnasale / face height)
  double get midFaceRatio => _dist(LandmarkIndex.nasion, LandmarkIndex.subnasale) / faceHeight;

  // 4. Lower face ratio (subnasale to chin / face height)
  double get lowerFaceRatio => _dist(LandmarkIndex.subnasale, LandmarkIndex.chin) / faceHeight;

  // 5. Intercanthal ratio (inner eye distance / face width)
  double get intercanthalRatio =>
      _dist(LandmarkIndex.rightEndocanthion, LandmarkIndex.leftEndocanthion) / faceWidth;

  // 6. Eye fissure ratio (average eye length / face width)
  double get eyeFissureRatio {
    final rightEye = _dist(LandmarkIndex.rightExocanthion, LandmarkIndex.rightEndocanthion);
    final leftEye = _dist(LandmarkIndex.leftExocanthion, LandmarkIndex.leftEndocanthion);
    return ((rightEye + leftEye) / 2.0) / faceWidth;
  }

  // 7. Eye openness (average eye height / average eye length)
  double get eyeOpenness {
    final rightEyeH = _dist(LandmarkIndex.rightEyeTop, LandmarkIndex.rightEyeBottom);
    final leftEyeH = _dist(LandmarkIndex.leftEyeTop, LandmarkIndex.leftEyeBottom);
    final rightEyeW = _dist(LandmarkIndex.rightExocanthion, LandmarkIndex.rightEndocanthion);
    final leftEyeW = _dist(LandmarkIndex.leftExocanthion, LandmarkIndex.leftEndocanthion);
    return ((rightEyeH + leftEyeH) / 2.0) / ((rightEyeW + leftEyeW) / 2.0);
  }

  // 8. Nasal width ratio (nose width / intercanthal distance)
  double get nasalWidthRatio {
    final nasalWidth = _dist(LandmarkIndex.rightAla, LandmarkIndex.leftAla);
    final icd = _dist(LandmarkIndex.rightEndocanthion, LandmarkIndex.leftEndocanthion);
    return nasalWidth / icd;
  }

  // 9. Nasal height ratio (nose height / face height)
  double get nasalHeightRatio => _dist(LandmarkIndex.nasion, LandmarkIndex.subnasale) / faceHeight;

  // 10. Mouth width ratio (mouth width / face width)
  double get mouthWidthRatio =>
      _dist(LandmarkIndex.rightCheilion, LandmarkIndex.leftCheilion) / faceWidth;

  // 11. Lip fullness ratio (lip height / face height)
  double get lipFullnessRatio =>
      _dist(LandmarkIndex.upperLipTop, LandmarkIndex.lowerLipBottom) / faceHeight;

  // 12. Mouth corner angle (degrees, positive = upturned)
  double get mouthCornerAngle {
    final midLipY = (_lm(LandmarkIndex.upperLipInner).y + _lm(LandmarkIndex.lowerLipInner).y) / 2.0;
    final midLipX = (_lm(LandmarkIndex.upperLipInner).x + _lm(LandmarkIndex.lowerLipInner).x) / 2.0;

    final rightCorner = _lm(LandmarkIndex.rightCheilion);
    final leftCorner = _lm(LandmarkIndex.leftCheilion);

    // Average angle of both corners relative to center
    // Negative dy = corner is higher = upturned (but y is inverted in image coords)
    final rightAngle = atan2(-(rightCorner.y - midLipY), (rightCorner.x - midLipX).abs());
    final leftAngle = atan2(-(leftCorner.y - midLipY), (leftCorner.x - midLipX).abs());

    return ((rightAngle + leftAngle) / 2.0) * (180.0 / pi);
  }

  Map<String, double> computeAll() {
    return {
      'faceAspectRatio': faceAspectRatio,
      'upperFaceRatio': upperFaceRatio,
      'midFaceRatio': midFaceRatio,
      'lowerFaceRatio': lowerFaceRatio,
      'intercanthalRatio': intercanthalRatio,
      'eyeFissureRatio': eyeFissureRatio,
      'eyeOpenness': eyeOpenness,
      'nasalWidthRatio': nasalWidthRatio,
      'nasalHeightRatio': nasalHeightRatio,
      'mouthWidthRatio': mouthWidthRatio,
      'lipFullnessRatio': lipFullnessRatio,
      'mouthCornerAngle': mouthCornerAngle,
    };
  }
}
