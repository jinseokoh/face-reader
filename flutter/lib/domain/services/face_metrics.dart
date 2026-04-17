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

  // Temples (upper forehead sides, for 天庭/foreheadWidth)
  static const rightTemple = 54;
  static const leftTemple = 284;

  // Cheekbones (for 顴骨/cheekboneWidth)
  static const rightCheekbone = 116;
  static const leftCheekbone = 345;

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
  // Lower eyelid midpoints (for eyeAspect: 세로/가로)
  static const rightEyeBottom = 145;
  static const leftEyeBottom = 374;

  // Eyebrow (right) — upper arc, lateral(tail) → medial(head)
  static const rightBrowUpper1 = 46; // outer tail
  static const rightBrowLower1 = 70;
  static const rightBrowUpper2 = 53;
  static const rightBrowLower2 = 63;
  static const rightBrowUpper3 = 52;
  static const rightBrowLower3 = 105;
  static const rightBrowInner = 55; // inner head (toward nose, 眉頭)

  // Eyebrow (left)
  static const leftBrowUpper1 = 276; // outer tail
  static const leftBrowLower1 = 300;
  static const leftBrowUpper2 = 283;
  static const leftBrowLower2 = 293;
  static const leftBrowUpper3 = 282;
  static const leftBrowLower3 = 334;
  static const leftBrowInner = 285; // inner head

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

  // ─── Lower-face width samples (inputs to lowerFaceFullness) ───
  /// 양쪽 하악각(gonion) 사이 폭.
  double get jawWidth =>
      _dist(LandmarkIndex.rightGonion, LandmarkIndex.leftGonion);

  /// 하악 중단(150–379) 폭.
  double get jawLowerWidth =>
      _dist(LandmarkIndex.rightJawLower, LandmarkIndex.leftJawLower);

  /// 턱 측면(148–377) 폭.
  double get chinSideWidth =>
      _dist(LandmarkIndex.rightChinSide, LandmarkIndex.leftChinSide);

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
  double get lowerFaceFullness =>
      (jawWidth + jawLowerWidth + chinSideWidth) / (3.0 * faceWidth);


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

  /// #13 코 길이 (얼굴 높이 대비) — 콧대 길이 (nasion→noseTip)
  ///
  /// 2026-04-17 버그 수정: 이전에는 `dist(nasion, subnasale) / faceHeight` 였으나
  /// `midFaceRatio` 와 수식이 완전히 동일해 Pearson r=1.000 중복이었음
  /// (feature_audit 5000 샘플 기준). 이제 콧대 끝(noseTip=1)까지의 거리로 측정하여
  /// 실제 "코 길이"를 반영한다.
  double get nasalHeightRatio =>
      _dist(LandmarkIndex.nasion, LandmarkIndex.noseTip) / faceHeight;

  // ─── MOUTH (4) ───

  /// #12 입 너비
  double get mouthWidthRatio =>
      _dist(LandmarkIndex.rightCheilion, LandmarkIndex.leftCheilion) /
      faceWidth;

  /// #13 입꼬리 각도 (부호 보존: + 仰月口, - 俯月口)
  ///
  /// 2026-04-17 버그 수정: 이전 구현은 `midLipY`를 x-좌표 기준으로 잘못 사용하여
  /// 각도 크기가 왜곡되었다. 정상화된 midLipX 기준으로 계산.
  double get mouthCornerAngle {
    final midLipX = (_lm(LandmarkIndex.upperLipInner).x +
            _lm(LandmarkIndex.lowerLipInner).x) /
        2.0;
    final midLipY = (_lm(LandmarkIndex.upperLipInner).y +
            _lm(LandmarkIndex.lowerLipInner).y) /
        2.0;
    final rightCorner = _lm(LandmarkIndex.rightCheilion);
    final leftCorner = _lm(LandmarkIndex.leftCheilion);

    final rightAngle =
        atan2(-(rightCorner.y - midLipY), (rightCorner.x - midLipX).abs());
    final leftAngle =
        atan2(-(leftCorner.y - midLipY), (leftCorner.x - midLipX).abs());

    return ((rightAngle + leftAngle) / 2.0) * (180.0 / pi);
  }

  /// #14 입술 두께
  double get lipFullnessRatio =>
      _dist(LandmarkIndex.upperLipTop, LandmarkIndex.lowerLipBottom) /
      faceHeight;

  /// #15 인중 길이
  double get philtrumLength =>
      _dist(LandmarkIndex.subnasale, LandmarkIndex.upperLipTop) / faceHeight;

  // ─── PHASE 1 — 관상학 추가 attribute (2026-04-17) ───

  /// #P1 눈썹 길이 (눈 길이 대비) — 兄弟宮 (眉長過目 = 형제 多)
  double get eyebrowLength {
    final rightBrow = _dist(
        LandmarkIndex.rightBrowUpper1, LandmarkIndex.rightBrowInner);
    final leftBrow = _dist(
        LandmarkIndex.leftBrowUpper1, LandmarkIndex.leftBrowInner);
    final rightEye = _dist(
        LandmarkIndex.rightExocanthion, LandmarkIndex.rightEndocanthion);
    final leftEye = _dist(
        LandmarkIndex.leftExocanthion, LandmarkIndex.leftEndocanthion);
    final eyeAvg = (rightEye + leftEye) / 2.0;
    if (eyeAvg == 0) return 0.0;
    return ((rightBrow + leftBrow) / 2.0) / eyeAvg;
  }

  /// #P2 눈썹 기울기 (부호 보존) — 劍眉(+, 위로 치켜) / 八字眉(-, 내려감)
  ///
  /// outer.y < inner.y (outer가 위) → 양수. faceHeight로 정규화.
  /// 이미지 좌표계(y 아래 증가) 기준: `inner.y - outer.y` 가 양수면 outer 위.
  double get eyebrowTiltDirection {
    final rInner = _lm(LandmarkIndex.rightBrowInner);
    final rOuter = _lm(LandmarkIndex.rightBrowUpper1);
    final lInner = _lm(LandmarkIndex.leftBrowInner);
    final lOuter = _lm(LandmarkIndex.leftBrowUpper1);
    final rTilt = (rInner.y - rOuter.y); // + if outer higher
    final lTilt = (lInner.y - lOuter.y);
    if (faceHeight == 0) return 0.0;
    return ((rTilt + lTilt) / 2.0) / faceHeight;
  }

  /// #P3 눈썹 곡률 (아치 정도) — 直眉(~0) / 彎眉(+) / 八字(-, 중앙 쳐짐)
  ///
  /// 중간점의 아래로 향한 처짐을 측정: middle의 y가 inner/outer의 선형보간값보다
  /// 작으면(이미지 y기준 위) 양수 → 아치. 큰 값이면 처짐(음수).
  double get eyebrowCurvature {
    double curve(int inner, int middle, int outer) {
      final pi_ = _lm(inner);
      final pm = _lm(middle);
      final po = _lm(outer);
      // middle에 대응하는 inner-outer 직선상의 y
      final yLine = (pi_.y + po.y) / 2.0; // 단순 중점 근사
      return yLine - pm.y; // + if middle is above the chord (arched)
    }
    final rCurve = curve(LandmarkIndex.rightBrowInner,
        LandmarkIndex.rightBrowUpper3, LandmarkIndex.rightBrowUpper1);
    final lCurve = curve(LandmarkIndex.leftBrowInner,
        LandmarkIndex.leftBrowUpper3, LandmarkIndex.leftBrowUpper1);
    if (faceHeight == 0) return 0.0;
    return ((rCurve + lCurve) / 2.0) / faceHeight;
  }

  /// #P4 미간 거리 (印堂) — 넓으면 관대, 좁으면 속좁음
  double get browSpacing =>
      _dist(LandmarkIndex.rightBrowInner, LandmarkIndex.leftBrowInner) /
      faceWidth;

  /// #P5 눈 세로/가로 비율 — 鳳眼(작음, 가로긴) / 圓眼(큼, 세로긴)
  double get eyeAspect {
    final rH = _dist(LandmarkIndex.rightEyeTop, LandmarkIndex.rightEyeBottom);
    final lH = _dist(LandmarkIndex.leftEyeTop, LandmarkIndex.leftEyeBottom);
    final rW = _dist(
        LandmarkIndex.rightExocanthion, LandmarkIndex.rightEndocanthion);
    final lW = _dist(
        LandmarkIndex.leftExocanthion, LandmarkIndex.leftEndocanthion);
    final rAsp = rW > 0 ? rH / rW : 0.0;
    final lAsp = lW > 0 ? lH / lW : 0.0;
    return (rAsp + lAsp) / 2.0;
  }

  /// #P6 윗입술/아랫입술 두께 비율 — >1: 윗입술 두껍(情 多) / <1: 아랫입술 두껍
  double get upperVsLowerLipRatio {
    final upper = _dist(LandmarkIndex.upperLipTop, LandmarkIndex.upperLipInner);
    final lower = _dist(LandmarkIndex.lowerLipInner, LandmarkIndex.lowerLipBottom);
    if (lower == 0) return 0.0;
    return upper / lower;
  }

  /// #P7 턱 각도 (chinAngle) — 方頤(~180°, 둥글) / 尖頤(작음, 뾰족)
  ///
  /// 양 턱측면(148, 377)과 턱끝(152)이 만드는 각.
  double get chinAngle => _angle(LandmarkIndex.rightChinSide,
      LandmarkIndex.chin, LandmarkIndex.leftChinSide);

  /// #P8 이마 폭 (天庭) — 관상학적 사회운/관록 지표
  double get foreheadWidth =>
      _dist(LandmarkIndex.rightTemple, LandmarkIndex.leftTemple) / faceWidth;

  /// #P9 광대 폭 (顴骨) — 권력/자아 지표
  double get cheekboneWidth =>
      _dist(LandmarkIndex.rightCheekbone, LandmarkIndex.leftCheekbone) /
      faceWidth;

  /// #P10 콧대-코끝 수직 거리 / nasion-subnasale (콧대 돌출 간접 지표)
  ///
  /// 새 `nasalHeightRatio` 가 콧대 bridge(168→1) 거리이므로, subnasale까지의
  /// 거리와의 비율을 보면 콧대 돌출(앞→아래) 경사 정보를 포착할 수 있다.
  double get noseBridgeRatio {
    final bridge = _dist(LandmarkIndex.nasion, LandmarkIndex.noseTip);
    final full = _dist(LandmarkIndex.nasion, LandmarkIndex.subnasale);
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
      // Phase 1 additions (2026-04-17)
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
