import 'dart:math';

/// Web/headless port of the Flutter `FaceMetrics` (flutter/lib/domain/services/
/// face_metrics.dart). 좌표 입력만 `FaceMeshLandmark` → `List<List<double>>`
/// ([x, y] 또는 [x, y, z], 정규화 0..1 무관 — 전부 비율/각도라 scale-invariant)
/// 로 바꾼 verbatim 포팅. **수식은 Flutter 원본과 1:1 동일해야 한다** (z-score
/// reference 가 이 raw 스케일에 맞춰져 있으므로). 측면 8개는 웹 미수집.
///
/// face_engine.dart 의 `runMetrics(landmarksJson)` 진입점이 사용한다.
class WebFaceMetrics {
  /// 468 MediaPipe Face Mesh landmarks — each point = [x, y, (z)].
  final List<List<double>> landmarks;

  WebFaceMetrics(this.landmarks);

  double _x(int i) => landmarks[i][0];
  double _y(int i) => landmarks[i][1];

  double _dist(int a, int b) {
    final dx = _x(a) - _x(b);
    final dy = _y(a) - _y(b);
    return sqrt(dx * dx + dy * dy);
  }

  double _angle(int a, int vertex, int b) {
    final ax = _x(a) - _x(vertex);
    final ay = _y(a) - _y(vertex);
    final bx = _x(b) - _x(vertex);
    final by = _y(b) - _y(vertex);
    final dot = ax * bx + ay * by;
    final cross = ax * by - ay * bx;
    return atan2(cross.abs(), dot) * (180.0 / pi);
  }

  // ─── Base dimensions ───
  double get faceHeight => _dist(_L.foreheadTop, _L.chin);
  double get faceWidth => _dist(_L.rightFaceEdge, _L.leftFaceEdge);

  double get jawWidth => _dist(_L.rightGonion, _L.leftGonion);
  double get jawLowerWidth => _dist(_L.rightJawLower, _L.leftJawLower);
  double get chinSideWidth => _dist(_L.rightChinSide, _L.leftChinSide);

  // ─── FACE ───
  double get faceAspectRatio => faceHeight / faceWidth;
  double get upperFaceRatio => _dist(_L.foreheadTop, _L.nasion) / faceHeight;
  double get midFaceRatio => _dist(_L.nasion, _L.subnasale) / faceHeight;
  double get lowerFaceRatio => _dist(_L.subnasale, _L.chin) / faceHeight;
  double get faceTaperRatio =>
      _dist(_L.rightGonion, _L.leftGonion) / faceWidth;
  double get lowerFaceFullness =>
      (jawWidth + jawLowerWidth + chinSideWidth) / (3.0 * faceWidth);

  double get gonialAngle {
    final right = _angle(_L.rightEar, _L.rightGonion, _L.chin);
    final left = _angle(_L.leftEar, _L.leftGonion, _L.chin);
    return (right + left) / 2.0;
  }

  // ─── EYES ───
  double get intercanthalRatio =>
      _dist(_L.rightEndocanthion, _L.leftEndocanthion) / faceWidth;

  double get eyeFissureRatio {
    final rightEye = _dist(_L.rightExocanthion, _L.rightEndocanthion);
    final leftEye = _dist(_L.leftExocanthion, _L.leftEndocanthion);
    return ((rightEye + leftEye) / 2.0) / faceWidth;
  }

  double get eyeCanthalTilt {
    final rightAngle = atan2(
            -(_y(_L.rightExocanthion) - _y(_L.rightEndocanthion)),
            (_x(_L.rightExocanthion) - _x(_L.rightEndocanthion)).abs()) *
        (180.0 / pi);
    final leftAngle = atan2(
            -(_y(_L.leftExocanthion) - _y(_L.leftEndocanthion)),
            (_x(_L.leftExocanthion) - _x(_L.leftEndocanthion)).abs()) *
        (180.0 / pi);
    return (rightAngle + leftAngle) / 2.0;
  }

  double get eyebrowThickness {
    final rightThickness = (_dist(_L.rightBrowUpper1, _L.rightBrowLower1) +
            _dist(_L.rightBrowUpper2, _L.rightBrowLower2) +
            _dist(_L.rightBrowUpper3, _L.rightBrowLower3)) /
        3.0;
    final leftThickness = (_dist(_L.leftBrowUpper1, _L.leftBrowLower1) +
            _dist(_L.leftBrowUpper2, _L.leftBrowLower2) +
            _dist(_L.leftBrowUpper3, _L.leftBrowLower3)) /
        3.0;
    return ((rightThickness + leftThickness) / 2.0) / faceHeight;
  }

  double get browEyeDistance {
    final right = _dist(_L.rightBrowLower3, _L.rightEyeTop);
    final left = _dist(_L.leftBrowLower3, _L.leftEyeTop);
    return ((right + left) / 2.0) / faceHeight;
  }

  // ─── NOSE ───
  double get nasalWidthRatio {
    final nasalWidth = _dist(_L.rightAla, _L.leftAla);
    final icd = _dist(_L.rightEndocanthion, _L.leftEndocanthion);
    return nasalWidth / icd;
  }

  double get nasalHeightRatio => _dist(_L.nasion, _L.noseTip) / faceHeight;

  // ─── MOUTH ───
  double get mouthWidthRatio =>
      _dist(_L.rightCheilion, _L.leftCheilion) / faceWidth;

  double get mouthCornerAngle {
    final midLipX = (_x(_L.upperLipInner) + _x(_L.lowerLipInner)) / 2.0;
    final midLipY = (_y(_L.upperLipInner) + _y(_L.lowerLipInner)) / 2.0;
    final rightAngle = atan2(
        -(_y(_L.rightCheilion) - midLipY), (_x(_L.rightCheilion) - midLipX).abs());
    final leftAngle = atan2(
        -(_y(_L.leftCheilion) - midLipY), (_x(_L.leftCheilion) - midLipX).abs());
    return ((rightAngle + leftAngle) / 2.0) * (180.0 / pi);
  }

  double get lipFullnessRatio =>
      _dist(_L.upperLipTop, _L.lowerLipBottom) / faceHeight;

  double get philtrumLength =>
      _dist(_L.subnasale, _L.upperLipTop) / faceHeight;

  // ─── PHASE 1 additions ───
  double get eyebrowLength {
    final rightBrow = _dist(_L.rightBrowUpper1, _L.rightBrowInner);
    final leftBrow = _dist(_L.leftBrowUpper1, _L.leftBrowInner);
    final rightEye = _dist(_L.rightExocanthion, _L.rightEndocanthion);
    final leftEye = _dist(_L.leftExocanthion, _L.leftEndocanthion);
    final eyeAvg = (rightEye + leftEye) / 2.0;
    if (eyeAvg == 0) return 0.0;
    return ((rightBrow + leftBrow) / 2.0) / eyeAvg;
  }

  double get eyebrowTiltDirection {
    final rTilt = _y(_L.rightBrowInner) - _y(_L.rightBrowUpper1);
    final lTilt = _y(_L.leftBrowInner) - _y(_L.leftBrowUpper1);
    if (faceHeight == 0) return 0.0;
    return ((rTilt + lTilt) / 2.0) / faceHeight;
  }

  double get eyebrowCurvature {
    double curve(int inner, int middle, int outer) {
      final yLine = (_y(inner) + _y(outer)) / 2.0;
      return yLine - _y(middle);
    }

    final rCurve =
        curve(_L.rightBrowInner, _L.rightBrowUpper3, _L.rightBrowUpper1);
    final lCurve =
        curve(_L.leftBrowInner, _L.leftBrowUpper3, _L.leftBrowUpper1);
    if (faceHeight == 0) return 0.0;
    return ((rCurve + lCurve) / 2.0) / faceHeight;
  }

  double get browSpacing =>
      _dist(_L.rightBrowInner, _L.leftBrowInner) / faceWidth;

  double get eyeAspect {
    final rH = _dist(_L.rightEyeTop, _L.rightEyeBottom);
    final lH = _dist(_L.leftEyeTop, _L.leftEyeBottom);
    final rW = _dist(_L.rightExocanthion, _L.rightEndocanthion);
    final lW = _dist(_L.leftExocanthion, _L.leftEndocanthion);
    final rAsp = rW > 0 ? rH / rW : 0.0;
    final lAsp = lW > 0 ? lH / lW : 0.0;
    return (rAsp + lAsp) / 2.0;
  }

  double get upperVsLowerLipRatio {
    final upper = _dist(_L.upperLipTop, _L.upperLipInner);
    final lower = _dist(_L.lowerLipInner, _L.lowerLipBottom);
    if (lower == 0) return 0.0;
    return upper / lower;
  }

  double get chinAngle =>
      _angle(_L.rightChinSide, _L.chin, _L.leftChinSide);

  double get foreheadWidth =>
      _dist(_L.rightTemple, _L.leftTemple) / faceWidth;

  double get cheekboneWidth =>
      _dist(_L.rightCheekbone, _L.leftCheekbone) / faceWidth;

  double get noseBridgeRatio {
    final bridge = _dist(_L.nasion, _L.noseTip);
    final full = _dist(_L.nasion, _L.subnasale);
    if (full == 0) return 0.0;
    return bridge / full;
  }

  Map<String, double> computeAll() {
    return {
      'faceAspectRatio': faceAspectRatio,
      'upperFaceRatio': upperFaceRatio,
      'midFaceRatio': midFaceRatio,
      'lowerFaceRatio': lowerFaceRatio,
      'faceTaperRatio': faceTaperRatio,
      'lowerFaceFullness': lowerFaceFullness,
      'gonialAngle': gonialAngle,
      'intercanthalRatio': intercanthalRatio,
      'eyeFissureRatio': eyeFissureRatio,
      'eyeCanthalTilt': eyeCanthalTilt,
      'eyebrowThickness': eyebrowThickness,
      'browEyeDistance': browEyeDistance,
      'nasalWidthRatio': nasalWidthRatio,
      'nasalHeightRatio': nasalHeightRatio,
      'mouthWidthRatio': mouthWidthRatio,
      'mouthCornerAngle': mouthCornerAngle,
      'lipFullnessRatio': lipFullnessRatio,
      'philtrumLength': philtrumLength,
      'eyebrowLength': eyebrowLength,
      'eyebrowTiltDirection': eyebrowTiltDirection,
      'eyebrowCurvature': eyebrowCurvature,
      'browSpacing': browSpacing,
      'eyeAspect': eyeAspect,
      'upperVsLowerLipRatio': upperVsLowerLipRatio,
      'chinAngle': chinAngle,
      'foreheadWidth': foreheadWidth,
      'cheekboneWidth': cheekboneWidth,
      'noseBridgeRatio': noseBridgeRatio,
    };
  }
}

/// MediaPipe Face Mesh landmark indices — Flutter `LandmarkIndex` verbatim copy.
abstract class _L {
  static const foreheadTop = 10;
  static const chin = 152;
  static const rightFaceEdge = 234;
  static const leftFaceEdge = 454;

  static const rightGonion = 172;
  static const leftGonion = 397;
  static const rightEar = 132;
  static const leftEar = 361;

  static const rightJawLower = 150;
  static const leftJawLower = 379;
  static const rightChinSide = 148;
  static const leftChinSide = 377;

  static const rightTemple = 54;
  static const leftTemple = 284;

  static const rightCheekbone = 116;
  static const leftCheekbone = 345;

  static const nasion = 168;
  static const noseTip = 1;
  static const subnasale = 94;
  static const rightAla = 98;
  static const leftAla = 327;

  static const rightEndocanthion = 133;
  static const leftEndocanthion = 362;
  static const rightExocanthion = 33;
  static const leftExocanthion = 263;
  static const rightEyeTop = 159;
  static const leftEyeTop = 386;
  static const rightEyeBottom = 145;
  static const leftEyeBottom = 374;

  static const rightBrowUpper1 = 46;
  static const rightBrowLower1 = 70;
  static const rightBrowUpper2 = 53;
  static const rightBrowLower2 = 63;
  static const rightBrowUpper3 = 52;
  static const rightBrowLower3 = 105;
  static const rightBrowInner = 55;

  static const leftBrowUpper1 = 276;
  static const leftBrowLower1 = 300;
  static const leftBrowUpper2 = 283;
  static const leftBrowLower2 = 293;
  static const leftBrowUpper3 = 282;
  static const leftBrowLower3 = 334;
  static const leftBrowInner = 285;

  static const rightCheilion = 61;
  static const leftCheilion = 291;
  static const upperLipTop = 0;
  static const lowerLipBottom = 17;
  static const upperLipInner = 13;
  static const lowerLipInner = 14;
}
