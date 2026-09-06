/// 계측 id → 측정선(랜드마크 인덱스 경로). 얼굴 지도(§55)가 내 얼굴과 평균 얼굴
/// 양쪽에 같은 선을 그어 차이를 보인다. 선의 정의는 카메라 오버레이
/// (`face_metric_overlay_painter.dart`)와 같은 점을 쓴다 — 계산된 중점만
/// 가장 가까운 랜드마크(입 안쪽 13)로 대신한다.
library;

const Map<String, List<List<int>>> metricLandmarkPaths = {
  'faceAspectRatio': [[10, 152], [234, 454]],
  'upperFaceRatio': [[10, 168]],
  'midFaceRatio': [[168, 94]],
  'lowerFaceRatio': [[94, 152]],
  'faceTaperRatio': [[172, 397]],
  'lowerFaceFullness': [[150, 379], [148, 377]],
  'gonialAngle': [[132, 172, 152], [361, 397, 152]],
  'intercanthalRatio': [[133, 362]],
  'eyeFissureRatio': [[33, 133], [362, 263]],
  'eyeCanthalTilt': [[133, 33], [362, 263]],
  'eyebrowThickness': [[46, 70], [53, 63], [52, 105], [276, 300], [283, 293], [282, 334]],
  'browEyeDistance': [[105, 159], [334, 386]],
  'nasalWidthRatio': [[98, 327]],
  'nasalHeightRatio': [[168, 1]],
  'mouthWidthRatio': [[61, 291]],
  'mouthCornerAngle': [[61, 13, 291]],
  'lipFullnessRatio': [[0, 17]],
  'philtrumLength': [[94, 0]],
  'eyebrowTiltDirection': [[46, 55], [276, 285]],
  'eyebrowCurvature': [[55, 52, 46], [285, 282, 276]],
  'browSpacing': [[55, 285]],
  'eyeAspect': [[159, 145], [386, 374]],
  'upperVsLowerLipRatio': [[0, 13], [14, 17]],
  'chinAngle': [[148, 152, 377]],
  'foreheadWidth': [[54, 284]],
  'cheekboneWidth': [[116, 345]],
};
