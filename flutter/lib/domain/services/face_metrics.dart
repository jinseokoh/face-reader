import 'dart:math';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

abstract class LandmarkIndex {
  // Face outline
  static const foreheadTop = 10;
  static const chin = 152;
  static const rightFaceEdge = 234;
  static const leftFaceEdge = 454;

  // Jaw / gonion
  static const rightGonion = 172;
  static const leftGonion = 397;
  static const rightEar = 132;
  static const leftEar = 361;

  // 하악선 중간~턱 바로 위의 외곽선 랜드마크
  // (골격이 아닌 피부 외곽선 — 볼살·턱살이 있으면 넓게 측정됨)
  // MediaPipe face-oval 순서: ...172(rightGonion)→136→150→149→176→148→152(chin)
  static const rightJawLower = 150; // rightGonion 과 chin 사이 하단 1/3 지점
  static const leftJawLower = 379; // leftGonion 과 chin 사이 하단 1/3 지점
  static const rightChinSide = 148; // chin 바로 오른쪽 (턱 측면)
  static const leftChinSide = 377; // chin 바로 왼쪽 (턱 측면)

  // Nose
  static const nasion = 168;
  static const noseTip = 1;
  static const subnasale = 94;
  static const rightAla = 98;
  static const leftAla = 327;
  // Eyes
  static const rightEndocanthion = 133;
  static const leftEndocanthion = 362;
  static const rightExocanthion = 33;
  static const leftExocanthion = 263;
  static const rightEyeTop = 159;
  static const leftEyeTop = 386;

  // Eyebrow (right)
  static const rightBrowUpper1 = 46;
  static const rightBrowLower1 = 70;
  static const rightBrowUpper2 = 53;
  static const rightBrowLower2 = 63;
  static const rightBrowUpper3 = 52;
  static const rightBrowLower3 = 105;

  // Eyebrow (left)
  static const leftBrowUpper1 = 276;
  static const leftBrowLower1 = 300;
  static const leftBrowUpper2 = 283;
  static const leftBrowLower2 = 293;
  static const leftBrowUpper3 = 282;
  static const leftBrowLower3 = 334;

  // Mouth
  static const rightCheilion = 61;
  static const leftCheilion = 291;
  static const upperLipTop = 0;
  static const lowerLipBottom = 17;
  static const upperLipInner = 13;
  static const lowerLipInner = 14;
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

  double _angle(int a, int vertex, int b) {
    final pa = _lm(a);
    final pv = _lm(vertex);
    final pb = _lm(b);
    final ax = pa.x - pv.x;
    final ay = pa.y - pv.y;
    final bx = pb.x - pv.x;
    final by = pb.y - pv.y;
    final dot = ax * bx + ay * by;
    final cross = ax * by - ay * bx;
    return atan2(cross.abs(), dot) * (180.0 / pi);
  }

  // ─── Base dimensions ───
  double get faceHeight =>
      _dist(LandmarkIndex.foreheadTop, LandmarkIndex.chin);
  double get faceWidth =>
      _dist(LandmarkIndex.rightFaceEdge, LandmarkIndex.leftFaceEdge);

  // ─── FACE (3) ───

  /// #1 얼굴 종횡비
  double get faceAspectRatio => faceHeight / faceWidth;

  /// 상안면 비율 (이마~미간 / 얼굴높이)
  double get upperFaceRatio =>
      _dist(LandmarkIndex.foreheadTop, LandmarkIndex.nasion) / faceHeight;

  /// 중안면 비율 (미간~코밑 / 얼굴높이)
  double get midFaceRatio =>
      _dist(LandmarkIndex.nasion, LandmarkIndex.subnasale) / faceHeight;

  /// 하안면 비율 (코밑~턱 / 얼굴높이)
  double get lowerFaceRatio =>
      _dist(LandmarkIndex.subnasale, LandmarkIndex.chin) / faceHeight;

  /// #2 얼굴 테이퍼 (jawWidth / faceWidth)
  double get faceTaperRatio =>
      _dist(LandmarkIndex.rightGonion, LandmarkIndex.leftGonion) / faceWidth;

  /// #2b 하단얼굴 풍만도 (lowerFaceFullness)
  /// 얼굴 하단 3개 레벨(gonion·jawLower·chinSide)의 평균 폭 / 최대 얼굴폭.
  ///
  /// 골격이 아닌 피부 외곽선 기준이므로 볼살·턱살·jowl이 있으면 높아진다.
  /// - 둥근 얼굴/사각 얼굴(예: 이수지): 하단까지 넓게 채워져 0.72~0.82
  /// - V-line / 갸름한 얼굴(예: IU): 턱으로 갈수록 급격히 좁아져 0.55~0.65
  ///
  /// 핵심 signal: faceTaperRatio (gonion 1레벨) 단독으론 못 잡는
  /// 중간·하단 볼륨을 포착.
  double get lowerFaceFullness {
    final jaw =
        _dist(LandmarkIndex.rightGonion, LandmarkIndex.leftGonion);
    final jawLower =
        _dist(LandmarkIndex.rightJawLower, LandmarkIndex.leftJawLower);
    final chinSide =
        _dist(LandmarkIndex.rightChinSide, LandmarkIndex.leftChinSide);
    return (jaw + jawLower + chinSide) / (3.0 * faceWidth);
  }

  /// #3 하악각 (양측 평균)
  double get gonialAngle {
    final right =
        _angle(LandmarkIndex.rightEar, LandmarkIndex.rightGonion, LandmarkIndex.chin);
    final left =
        _angle(LandmarkIndex.leftEar, LandmarkIndex.leftGonion, LandmarkIndex.chin);
    return (right + left) / 2.0;
  }

  // ─── EYES (4) ───

  /// #4 눈 사이 거리
  double get intercanthalRatio =>
      _dist(LandmarkIndex.rightEndocanthion, LandmarkIndex.leftEndocanthion) /
      faceWidth;

  /// #5 눈 길이
  double get eyeFissureRatio {
    final rightEye = _dist(
        LandmarkIndex.rightExocanthion, LandmarkIndex.rightEndocanthion);
    final leftEye = _dist(
        LandmarkIndex.leftExocanthion, LandmarkIndex.leftEndocanthion);
    return ((rightEye + leftEye) / 2.0) / faceWidth;
  }

  /// #6 눈꼬리 각도 (양측 평균, degrees)
  double get eyeCanthalTilt {
    final rExo = _lm(LandmarkIndex.rightExocanthion);
    final rEndo = _lm(LandmarkIndex.rightEndocanthion);
    final lExo = _lm(LandmarkIndex.leftExocanthion);
    final lEndo = _lm(LandmarkIndex.leftEndocanthion);

    final rightAngle =
        atan2(-(rExo.y - rEndo.y), (rExo.x - rEndo.x).abs()) * (180.0 / pi);
    final leftAngle =
        atan2(-(lExo.y - lEndo.y), (lExo.x - lEndo.x).abs()) * (180.0 / pi);
    return (rightAngle + leftAngle) / 2.0;
  }

  /// #7 눈썹 두께
  double get eyebrowThickness {
    final rightThickness = (
      _dist(LandmarkIndex.rightBrowUpper1, LandmarkIndex.rightBrowLower1) +
      _dist(LandmarkIndex.rightBrowUpper2, LandmarkIndex.rightBrowLower2) +
      _dist(LandmarkIndex.rightBrowUpper3, LandmarkIndex.rightBrowLower3)
    ) / 3.0;
    final leftThickness = (
      _dist(LandmarkIndex.leftBrowUpper1, LandmarkIndex.leftBrowLower1) +
      _dist(LandmarkIndex.leftBrowUpper2, LandmarkIndex.leftBrowLower2) +
      _dist(LandmarkIndex.leftBrowUpper3, LandmarkIndex.leftBrowLower3)
    ) / 3.0;
    return ((rightThickness + leftThickness) / 2.0) / faceHeight;
  }

  // ─── EYES-BROW (1) ───

  /// #8 눈썹-눈 거리
  double get browEyeDistance {
    final right =
        _dist(LandmarkIndex.rightBrowLower3, LandmarkIndex.rightEyeTop);
    final left =
        _dist(LandmarkIndex.leftBrowLower3, LandmarkIndex.leftEyeTop);
    return ((right + left) / 2.0) / faceHeight;
  }

  // ─── NOSE (2) ───

  /// #12 코 너비
  double get nasalWidthRatio {
    final nasalWidth = _dist(LandmarkIndex.rightAla, LandmarkIndex.leftAla);
    final icd = _dist(
        LandmarkIndex.rightEndocanthion, LandmarkIndex.leftEndocanthion);
    final ratio = nasalWidth / icd;
    // ignore: avoid_print
    print('[NasalWidthDebug] alaWidth=${nasalWidth.toStringAsFixed(5)} '
        'icd=${icd.toStringAsFixed(5)} ratio=${ratio.toStringAsFixed(4)} '
        '(landmarks: rAla=98 lAla=327 rEndo=133 lEndo=362)');
    return ratio;
  }

  /// #13 코 길이 (얼굴 높이 대비)
  double get nasalHeightRatio =>
      _dist(LandmarkIndex.nasion, LandmarkIndex.subnasale) / faceHeight;

  // ─── MOUTH (4) ───

  /// #12 입 너비
  double get mouthWidthRatio =>
      _dist(LandmarkIndex.rightCheilion, LandmarkIndex.leftCheilion) /
      faceWidth;

  /// #13 입꼬리 각도
  double get mouthCornerAngle {
    final midLipY = (_lm(LandmarkIndex.upperLipInner).y +
            _lm(LandmarkIndex.lowerLipInner).y) /
        2.0;
    final rightCorner = _lm(LandmarkIndex.rightCheilion);
    final leftCorner = _lm(LandmarkIndex.leftCheilion);

    final rightAngle =
        atan2(-(rightCorner.y - midLipY), (rightCorner.x - midLipY).abs());
    final leftAngle =
        atan2(-(leftCorner.y - midLipY), (leftCorner.x - midLipY).abs());

    return ((rightAngle + leftAngle) / 2.0) * (180.0 / pi);
  }

  /// #14 입술 두께
  double get lipFullnessRatio =>
      _dist(LandmarkIndex.upperLipTop, LandmarkIndex.lowerLipBottom) /
      faceHeight;

  /// #15 인중 길이
  double get philtrumLength =>
      _dist(LandmarkIndex.subnasale, LandmarkIndex.upperLipTop) / faceHeight;

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
    };
  }
}
