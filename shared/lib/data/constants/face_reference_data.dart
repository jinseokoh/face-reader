import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/data/enums/metric_type.dart';

const metricInfoList = [
  // FACE (3)
  MetricInfo(
    id: 'faceAspectRatio',
    nameKo: '얼굴 종횡비',
    nameEn: 'Face Aspect Ratio',
    category: 'face',
    higherLabel: '세로로 긴 얼굴',
    lowerLabel: '가로로 넓은 얼굴',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'faceTaperRatio',
    nameKo: '얼굴 테이퍼 (황금비)',
    nameEn: 'Face Taper Ratio',
    category: 'face',
    higherLabel: '넓은 턱',
    lowerLabel: '좁은 턱 (V라인)',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'lowerFaceFullness',
    nameKo: '하단얼굴 풍만도',
    nameEn: 'Lower Face Fullness',
    category: 'face',
    higherLabel: '볼살/턱살 풍만 (둥근 얼굴)',
    lowerLabel: '갸름한 하단 (V-line)',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'upperFaceRatio',
    nameKo: '상안면 비율',
    nameEn: 'Upper Face Ratio',
    category: 'face',
    higherLabel: '이마가 넓음',
    lowerLabel: '이마가 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'midFaceRatio',
    nameKo: '중안면 비율',
    nameEn: 'Mid Face Ratio',
    category: 'face',
    higherLabel: '중안면이 긺',
    lowerLabel: '중안면이 짧음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'lowerFaceRatio',
    nameKo: '하안면 비율',
    nameEn: 'Lower Face Ratio',
    category: 'face',
    higherLabel: '턱이 긺',
    lowerLabel: '턱이 짧음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'gonialAngle',
    nameKo: '하악각',
    nameEn: 'Gonial Angle',
    category: 'face',
    higherLabel: '각진 턱',
    lowerLabel: '둥근 턱',
    type: MetricType.angle,
  ),
  // EYES (4)
  MetricInfo(
    id: 'intercanthalRatio',
    nameKo: '눈 사이 거리',
    nameEn: 'Intercanthal Distance',
    category: 'eyes',
    higherLabel: '눈 사이가 넓음',
    lowerLabel: '눈 사이가 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'eyeFissureRatio',
    nameKo: '눈 길이',
    nameEn: 'Eye Fissure Length',
    category: 'eyes',
    higherLabel: '눈이 긺',
    lowerLabel: '눈이 짧음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'eyeCanthalTilt',
    nameKo: '눈꼬리 각도',
    nameEn: 'Eye Canthal Tilt',
    category: 'eyes',
    higherLabel: '눈꼬리가 올라감',
    lowerLabel: '눈꼬리가 내려감',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'eyebrowThickness',
    nameKo: '눈썹 두께',
    nameEn: 'Eyebrow Thickness',
    category: 'eyes',
    higherLabel: '눈썹이 두꺼움',
    lowerLabel: '눈썹이 얇음',
    type: MetricType.shape,
  ),
  // EYES-BROW (1)
  MetricInfo(
    id: 'browEyeDistance',
    nameKo: '눈썹-눈 거리',
    nameEn: 'Brow-Eye Distance',
    category: 'eyes',
    higherLabel: '전택이 넓음',
    lowerLabel: '전택이 좁음',
    type: MetricType.shape,
  ),
  // NOSE (3)
  MetricInfo(
    id: 'nasalWidthRatio',
    nameKo: '코 너비',
    nameEn: 'Nasal Width',
    category: 'nose',
    higherLabel: '코가 넓음',
    lowerLabel: '코가 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'nasalHeightRatio',
    nameKo: '코 길이',
    nameEn: 'Nasal Height',
    category: 'nose',
    higherLabel: '코가 긺',
    lowerLabel: '코가 짧음',
    type: MetricType.ratio,
  ),
  // MOUTH (4)
  MetricInfo(
    id: 'mouthWidthRatio',
    nameKo: '입 너비',
    nameEn: 'Mouth Width',
    category: 'mouth',
    higherLabel: '입이 넓음',
    lowerLabel: '입이 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'mouthCornerAngle',
    nameKo: '입꼬리 각도',
    nameEn: 'Mouth Corner Angle',
    category: 'mouth',
    higherLabel: '입꼬리가 올라감',
    lowerLabel: '입꼬리가 내려감',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'lipFullnessRatio',
    nameKo: '입술 두께',
    nameEn: 'Lip Fullness',
    category: 'mouth',
    higherLabel: '입술이 두꺼움',
    lowerLabel: '입술이 얇음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'philtrumLength',
    nameKo: '인중 길이',
    nameEn: 'Philtrum Length',
    category: 'mouth',
    higherLabel: '인중이 긺',
    lowerLabel: '인중이 짧음',
    type: MetricType.ratio,
  ),
  // ─── Phase 1B additions (2026-04-18) ───
  // See docs/engine/TAXONOMY.md v1.0 — orphan 7개 정규화.
  // 보류된 2개(eyebrowLength·noseBridgeRatio)는 tree 밖 classifier 전용.
  // browSpacing 은 Phase 2 (2026-04-18) 에서 glabella·명궁으로 편입.
  MetricInfo(
    id: 'foreheadWidth',
    nameKo: '이마 너비',
    nameEn: 'Forehead Width',
    category: 'face',
    higherLabel: '이마가 넓음',
    lowerLabel: '이마가 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'cheekboneWidth',
    nameKo: '광대 너비',
    nameEn: 'Cheekbone Width',
    category: 'face',
    higherLabel: '광대가 넓음',
    lowerLabel: '광대가 좁음',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'chinAngle',
    nameKo: '턱 각도',
    nameEn: 'Chin Angle',
    category: 'face',
    higherLabel: '턱이 둥글고 넓음',
    lowerLabel: '턱이 뾰족함',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'eyeAspect',
    nameKo: '눈 세로/가로 비율',
    nameEn: 'Eye Aspect Ratio',
    category: 'eyes',
    higherLabel: '눈이 둥글고 큼 (圓眼)',
    lowerLabel: '눈이 가늘고 긺 (鳳眼)',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'eyebrowCurvature',
    nameKo: '눈썹 곡률',
    nameEn: 'Eyebrow Curvature',
    category: 'eyes',
    higherLabel: '눈썹이 아치형',
    lowerLabel: '눈썹이 직선/처짐',
    type: MetricType.shape,
  ),
  MetricInfo(
    id: 'eyebrowTiltDirection',
    nameKo: '눈썹 기울기',
    nameEn: 'Eyebrow Tilt Direction',
    category: 'eyes',
    higherLabel: '눈썹 꼬리가 올라감 (劍眉)',
    lowerLabel: '눈썹 꼬리가 내려감 (八字眉)',
    type: MetricType.shape,
  ),
  MetricInfo(
    id: 'upperVsLowerLipRatio',
    nameKo: '윗입술/아랫입술 비율',
    nameEn: 'Upper vs Lower Lip Ratio',
    category: 'mouth',
    higherLabel: '윗입술이 두꺼움',
    lowerLabel: '아랫입술이 두꺼움',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'browSpacing',
    nameKo: '미간 너비 (印堂)',
    nameEn: 'Brow Spacing',
    category: 'eyes',
    higherLabel: '미간이 넓음',
    lowerLabel: '미간이 좁음',
    type: MetricType.ratio,
  ),
];

/// Reference data: [Ethnicity][Gender][metricId] → MetricReference(mean, sd)
const Map<Ethnicity, Map<Gender, Map<String, MetricReference>>> referenceData = {
  Ethnicity.eastAsian: {
    // ─── AAF-recalibrated reference (2026-06-01) ───
    // All-Age-Faces (AAF) 실사진 11,800장(정면 yaw<18°, male=5361 female=6439)을
    // 앱과 동일 파이프라인(MediaPipe 468 → face_metrics.dart::computeAll(), 정규화
    // 좌표·faceAspectRatio 만 (imgH/imgW)·1.05 보정)으로 측정한 metric별 empirical
    // mean/std (population, ddof=0). 추출·집계: tools/face_shape_ml/extract_aaf.py.
    // 추정치 기반 reference 가 production z 를 체계적으로 +로 띄워 전 속성이 CDF
    // 상단에 saturate 되던 문제(docs/DIAGNOSIS-score-saturation.md)의 근본 교정.
    // 측면 8 metric(lateralReferenceData)은 정면 표본으로 측정 불가 → 미변경.
    Gender.male: {
      'faceAspectRatio': MetricReference(1.221, 0.06563),
      'faceTaperRatio': MetricReference(0.801, 0.02482),
      'lowerFaceFullness': MetricReference(0.5151, 0.01937),
      'upperFaceRatio': MetricReference(0.2965, 0.01789),
      'midFaceRatio': MetricReference(0.2954, 0.01756),
      'lowerFaceRatio': MetricReference(0.4087, 0.0308),
      'gonialAngle': MetricReference(139.7, 4.509),
      'intercanthalRatio': MetricReference(0.252, 0.01507),
      'eyeFissureRatio': MetricReference(0.1828, 0.01017),
      'eyeCanthalTilt': MetricReference(3.778, 2.329),
      'eyebrowThickness': MetricReference(0.03412, 0.00256),
      'browEyeDistance': MetricReference(0.1424, 0.01737),
      'nasalWidthRatio': MetricReference(0.9643, 0.08373),
      'nasalHeightRatio': MetricReference(0.2648, 0.02175),
      'mouthWidthRatio': MetricReference(0.3664, 0.04232),
      'mouthCornerAngle': MetricReference(2.623, 5.324),
      'lipFullnessRatio': MetricReference(0.1177, 0.03088),
      'philtrumLength': MetricReference(0.0994, 0.01616),
      'foreheadWidth': MetricReference(0.8516, 0.02643),
      'cheekboneWidth': MetricReference(0.9043, 0.0123),
      'chinAngle': MetricReference(171.5, 2.5),
      'eyeAspect': MetricReference(0.2561, 0.07213),
      'eyebrowCurvature': MetricReference(0.03748, 0.003897),
      'eyebrowTiltDirection': MetricReference(-0.007304, 0.01407),
      'upperVsLowerLipRatio': MetricReference(0.6243, 0.1162),
      'browSpacing': MetricReference(0.1866, 0.01272),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.223, 0.06561),
      'faceTaperRatio': MetricReference(0.7931, 0.0251),
      'lowerFaceFullness': MetricReference(0.5067, 0.02026),
      'upperFaceRatio': MetricReference(0.3063, 0.01944),
      'midFaceRatio': MetricReference(0.3013, 0.0195),
      'lowerFaceRatio': MetricReference(0.3936, 0.03463),
      'gonialAngle': MetricReference(141.7, 4.383),
      'intercanthalRatio': MetricReference(0.2569, 0.01549),
      'eyeFissureRatio': MetricReference(0.1888, 0.01135),
      'eyeCanthalTilt': MetricReference(5.935, 2.579),
      'eyebrowThickness': MetricReference(0.03371, 0.00264),
      'browEyeDistance': MetricReference(0.1412, 0.01572),
      'nasalWidthRatio': MetricReference(0.947, 0.07906),
      'nasalHeightRatio': MetricReference(0.274, 0.02376),
      'mouthWidthRatio': MetricReference(0.3864, 0.04726),
      'mouthCornerAngle': MetricReference(6.739, 6.011),
      'lipFullnessRatio': MetricReference(0.1286, 0.03176),
      'philtrumLength': MetricReference(0.08641, 0.01676),
      'foreheadWidth': MetricReference(0.8484, 0.0315),
      'cheekboneWidth': MetricReference(0.9107, 0.01399),
      'chinAngle': MetricReference(169.5, 2.5),
      'eyeAspect': MetricReference(0.2963, 0.07239),
      'eyebrowCurvature': MetricReference(0.03933, 0.003766),
      'eyebrowTiltDirection': MetricReference(0.001593, 0.01409),
      'upperVsLowerLipRatio': MetricReference(0.5966, 0.1103),
      'browSpacing': MetricReference(0.1928, 0.01235),
    },
  },
  Ethnicity.caucasian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.37, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.83, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(120.0, 7.0),
      'intercanthalRatio': MetricReference(0.23, 0.02),
      'eyeFissureRatio': MetricReference(0.22, 0.02),
      'eyeCanthalTilt': MetricReference(4.0, 3.0),
      'eyebrowThickness': MetricReference(0.018, 0.004),
      'browEyeDistance': MetricReference(0.060, 0.014),
      'nasalWidthRatio': MetricReference(0.98, 0.10),


      'nasalHeightRatio': MetricReference(0.31, 0.02),
      'mouthWidthRatio': MetricReference(0.38, 0.03),
      'mouthCornerAngle': MetricReference(0.0, 3.0),
      'lipFullnessRatio': MetricReference(0.08, 0.02),
      'philtrumLength': MetricReference(0.082, 0.015),
      'foreheadWidth': MetricReference(0.88, 0.04),
      'cheekboneWidth': MetricReference(0.91, 0.04),
      'chinAngle': MetricReference(168.0, 5.0),
      'eyeAspect': MetricReference(0.32, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.19, 0.03),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.33, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.77, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(124.0, 8.0),
      'intercanthalRatio': MetricReference(0.23, 0.02),
      'eyeFissureRatio': MetricReference(0.24, 0.02),
      'eyeCanthalTilt': MetricReference(5.0, 3.0),
      'eyebrowThickness': MetricReference(0.014, 0.003),
      'browEyeDistance': MetricReference(0.064, 0.015),
      'nasalWidthRatio': MetricReference(0.92, 0.09),


      'nasalHeightRatio': MetricReference(0.31, 0.02),
      'mouthWidthRatio': MetricReference(0.36, 0.03),
      'mouthCornerAngle': MetricReference(1.0, 3.0),
      'lipFullnessRatio': MetricReference(0.10, 0.02),
      'philtrumLength': MetricReference(0.072, 0.013),
      'foreheadWidth': MetricReference(0.86, 0.04),
      'cheekboneWidth': MetricReference(0.90, 0.04),
      'chinAngle': MetricReference(170.0, 5.0),
      'eyeAspect': MetricReference(0.35, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.20, 0.03),
    },
  },
  Ethnicity.african: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.34, 0.08),
      'upperFaceRatio': MetricReference(0.32, 0.03),
      'midFaceRatio': MetricReference(0.32, 0.02),
      'lowerFaceRatio': MetricReference(0.36, 0.03),
      'faceTaperRatio': MetricReference(0.86, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(116.0, 7.0),
      'intercanthalRatio': MetricReference(0.29, 0.02),
      'eyeFissureRatio': MetricReference(0.23, 0.02),
      'eyeCanthalTilt': MetricReference(3.0, 3.0),
      'eyebrowThickness': MetricReference(0.016, 0.004),
      'browEyeDistance': MetricReference(0.056, 0.014),
      'nasalWidthRatio': MetricReference(1.24, 0.12),


      'nasalHeightRatio': MetricReference(0.28, 0.02),
      'mouthWidthRatio': MetricReference(0.41, 0.03),
      'mouthCornerAngle': MetricReference(-0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.11, 0.02),
      'philtrumLength': MetricReference(0.088, 0.015),
      'foreheadWidth': MetricReference(0.88, 0.04),
      'cheekboneWidth': MetricReference(0.91, 0.04),
      'chinAngle': MetricReference(168.0, 5.0),
      'eyeAspect': MetricReference(0.32, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.19, 0.03),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.30, 0.07),
      'upperFaceRatio': MetricReference(0.32, 0.03),
      'midFaceRatio': MetricReference(0.32, 0.02),
      'lowerFaceRatio': MetricReference(0.36, 0.03),
      'faceTaperRatio': MetricReference(0.8, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(120.0, 8.0),
      'intercanthalRatio': MetricReference(0.29, 0.02),
      'eyeFissureRatio': MetricReference(0.25, 0.02),
      'eyeCanthalTilt': MetricReference(4.0, 3.0),
      'eyebrowThickness': MetricReference(0.012, 0.003),
      'browEyeDistance': MetricReference(0.060, 0.015),
      'nasalWidthRatio': MetricReference(1.16, 0.11),


      'nasalHeightRatio': MetricReference(0.28, 0.02),
      'mouthWidthRatio': MetricReference(0.39, 0.03),
      'mouthCornerAngle': MetricReference(0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.13, 0.02),
      'philtrumLength': MetricReference(0.078, 0.013),
      'foreheadWidth': MetricReference(0.86, 0.04),
      'cheekboneWidth': MetricReference(0.90, 0.04),
      'chinAngle': MetricReference(170.0, 5.0),
      'eyeAspect': MetricReference(0.35, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.20, 0.03),
    },
  },
  Ethnicity.southeastAsian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.38, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(119.0, 7.0),
      'intercanthalRatio': MetricReference(0.25, 0.02),
      'eyeFissureRatio': MetricReference(0.23, 0.02),
      'eyeCanthalTilt': MetricReference(3.5, 3.0),
      'eyebrowThickness': MetricReference(0.016, 0.004),
      'browEyeDistance': MetricReference(0.057, 0.014),
      'nasalWidthRatio': MetricReference(1.13, 0.10),


      'nasalHeightRatio': MetricReference(0.29, 0.02),
      'mouthWidthRatio': MetricReference(0.40, 0.03),
      'mouthCornerAngle': MetricReference(-0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.10, 0.02),
      'philtrumLength': MetricReference(0.086, 0.015),
      'foreheadWidth': MetricReference(0.88, 0.04),
      'cheekboneWidth': MetricReference(0.91, 0.04),
      'chinAngle': MetricReference(168.0, 5.0),
      'eyeAspect': MetricReference(0.32, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.19, 0.03),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.34, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(123.0, 8.0),
      'intercanthalRatio': MetricReference(0.25, 0.02),
      'eyeFissureRatio': MetricReference(0.25, 0.02),
      'eyeCanthalTilt': MetricReference(4.5, 3.0),
      'eyebrowThickness': MetricReference(0.012, 0.003),
      'browEyeDistance': MetricReference(0.061, 0.015),
      'nasalWidthRatio': MetricReference(1.07, 0.09),


      'nasalHeightRatio': MetricReference(0.29, 0.02),
      'mouthWidthRatio': MetricReference(0.38, 0.03),
      'mouthCornerAngle': MetricReference(0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.12, 0.02),
      'philtrumLength': MetricReference(0.076, 0.013),
      'foreheadWidth': MetricReference(0.86, 0.04),
      'cheekboneWidth': MetricReference(0.90, 0.04),
      'chinAngle': MetricReference(170.0, 5.0),
      'eyeAspect': MetricReference(0.35, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.20, 0.03),
    },
  },
  Ethnicity.hispanic: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.37, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(119.0, 7.0),
      'intercanthalRatio': MetricReference(0.24, 0.02),
      'eyeFissureRatio': MetricReference(0.22, 0.02),
      'eyeCanthalTilt': MetricReference(3.5, 3.0),
      'eyebrowThickness': MetricReference(0.017, 0.004),
      'browEyeDistance': MetricReference(0.059, 0.014),
      'nasalWidthRatio': MetricReference(1.03, 0.10),


      'nasalHeightRatio': MetricReference(0.30, 0.02),
      'mouthWidthRatio': MetricReference(0.39, 0.03),
      'mouthCornerAngle': MetricReference(0.0, 3.0),
      'lipFullnessRatio': MetricReference(0.09, 0.02),
      'philtrumLength': MetricReference(0.084, 0.015),
      'foreheadWidth': MetricReference(0.88, 0.04),
      'cheekboneWidth': MetricReference(0.91, 0.04),
      'chinAngle': MetricReference(168.0, 5.0),
      'eyeAspect': MetricReference(0.32, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.19, 0.03),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.33, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(123.0, 8.0),
      'intercanthalRatio': MetricReference(0.24, 0.02),
      'eyeFissureRatio': MetricReference(0.24, 0.02),
      'eyeCanthalTilt': MetricReference(4.5, 3.0),
      'eyebrowThickness': MetricReference(0.013, 0.003),
      'browEyeDistance': MetricReference(0.063, 0.015),
      'nasalWidthRatio': MetricReference(0.97, 0.09),


      'nasalHeightRatio': MetricReference(0.30, 0.02),
      'mouthWidthRatio': MetricReference(0.37, 0.03),
      'mouthCornerAngle': MetricReference(0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.11, 0.02),
      'philtrumLength': MetricReference(0.074, 0.013),
      'foreheadWidth': MetricReference(0.86, 0.04),
      'cheekboneWidth': MetricReference(0.90, 0.04),
      'chinAngle': MetricReference(170.0, 5.0),
      'eyeAspect': MetricReference(0.35, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.20, 0.03),
    },
  },
  Ethnicity.middleEastern: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.38, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(117.0, 7.0),
      'intercanthalRatio': MetricReference(0.23, 0.02),
      'eyeFissureRatio': MetricReference(0.23, 0.02),
      'eyeCanthalTilt': MetricReference(3.5, 3.0),
      'eyebrowThickness': MetricReference(0.019, 0.004),
      'browEyeDistance': MetricReference(0.059, 0.014),
      'nasalWidthRatio': MetricReference(1.03, 0.10),


      'nasalHeightRatio': MetricReference(0.31, 0.02),
      'mouthWidthRatio': MetricReference(0.38, 0.03),
      'mouthCornerAngle': MetricReference(0.0, 3.0),
      'lipFullnessRatio': MetricReference(0.08, 0.02),
      'philtrumLength': MetricReference(0.083, 0.015),
      'foreheadWidth': MetricReference(0.88, 0.04),
      'cheekboneWidth': MetricReference(0.91, 0.04),
      'chinAngle': MetricReference(168.0, 5.0),
      'eyeAspect': MetricReference(0.32, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.19, 0.03),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.34, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.50, 0.05),
      'gonialAngle': MetricReference(121.0, 8.0),
      'intercanthalRatio': MetricReference(0.23, 0.02),
      'eyeFissureRatio': MetricReference(0.25, 0.02),
      'eyeCanthalTilt': MetricReference(4.5, 3.0),
      'eyebrowThickness': MetricReference(0.015, 0.003),
      'browEyeDistance': MetricReference(0.063, 0.015),
      'nasalWidthRatio': MetricReference(0.97, 0.09),


      'nasalHeightRatio': MetricReference(0.31, 0.02),
      'mouthWidthRatio': MetricReference(0.36, 0.03),
      'mouthCornerAngle': MetricReference(0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.10, 0.02),
      'philtrumLength': MetricReference(0.073, 0.013),
      'foreheadWidth': MetricReference(0.86, 0.04),
      'cheekboneWidth': MetricReference(0.90, 0.04),
      'chinAngle': MetricReference(170.0, 5.0),
      'eyeAspect': MetricReference(0.35, 0.06),
      'eyebrowCurvature': MetricReference(0.038, 0.005),
      'eyebrowTiltDirection': MetricReference(0.000, 0.012),
      'upperVsLowerLipRatio': MetricReference(0.65, 0.10),
      'browSpacing': MetricReference(0.20, 0.03),
    },
  },
};

class MetricInfo {
  final String id;
  final String nameKo;
  final String nameEn;
  final String category;
  final String higherLabel;
  final String lowerLabel;
  final MetricType type;

  const MetricInfo({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.category,
    required this.higherLabel,
    required this.lowerLabel,
    required this.type,
  });
}

class MetricReference {
  final double mean;
  final double sd;

  const MetricReference(this.mean, this.sd);
}

// ─────────────────────────────────────────────────────────────────────────
// LATERAL METRICS (3/4-view capture)
//
// Computed from a separately-captured ~30-45 deg yaw photo. Reference values
// from East Asian cephalometric literature (Korean/Han Chinese adults).
// Other ethnicities currently fall back to East Asian baselines until
// per-ethnicity literature is integrated.
// ─────────────────────────────────────────────────────────────────────────

const lateralMetricInfoList = [
  MetricInfo(
    id: 'nasofrontalAngle',
    nameKo: '비전두각',
    nameEn: 'Nasofrontal Angle',
    category: 'lateral',
    higherLabel: '이마-코 경사가 완만함',
    lowerLabel: '이마-코 경사가 급함',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'nasolabialAngle',
    nameKo: '비순각',
    nameEn: 'Nasolabial Angle',
    category: 'lateral',
    higherLabel: '코끝이 들림',
    lowerLabel: '코끝이 처짐',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'facialConvexity',
    nameKo: '안면 돌출각',
    nameEn: 'Facial Convexity (G-Sn-Pog)',
    category: 'lateral',
    higherLabel: '얼굴이 볼록함',
    lowerLabel: '얼굴이 평평함',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'upperLipEline',
    nameKo: '상순 E-line 거리',
    nameEn: 'Upper Lip to E-line',
    category: 'lateral',
    higherLabel: '상순이 앞으로 나옴',
    lowerLabel: '상순이 뒤로 들어감',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'lowerLipEline',
    nameKo: '하순 E-line 거리',
    nameEn: 'Lower Lip to E-line',
    category: 'lateral',
    higherLabel: '하순이 앞으로 나옴',
    lowerLabel: '하순이 뒤로 들어감',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'mentolabialAngle',
    nameKo: '순이각',
    nameEn: 'Mentolabial Angle',
    category: 'lateral',
    higherLabel: '입술-턱 경계가 평평함',
    lowerLabel: '입술-턱 경계가 깊음',
    type: MetricType.angle,
  ),
  MetricInfo(
    id: 'noseTipProjection',
    nameKo: '코끝 돌출',
    nameEn: 'Nose Tip Projection',
    category: 'lateral',
    higherLabel: '코끝이 길게 나옴',
    lowerLabel: '코끝이 짧게 들어감',
    type: MetricType.ratio,
  ),
  MetricInfo(
    id: 'dorsalConvexity',
    nameKo: '코 등선 돌출도',
    nameEn: 'Nasal Dorsum Convexity',
    category: 'lateral',
    higherLabel: '매부리 돌출이 뚜렷함',
    lowerLabel: '코 등선이 평평/오목함',
    type: MetricType.ratio,
  ),
];

/// Lateral binary-flag IDs (no z-score, just yes/no).
const lateralFlagIds = [
  'aquilineNose', // 매부리코
  'snubNose',     // 들창코
];

/// Lateral reference data: [Ethnicity][Gender][metricId] → MetricReference.
/// Currently only East Asian has empirical values; other ethnicities reuse
/// the same baselines.
/// Lateral reference data per (Ethnicity × Gender) — 8 metric.
///
/// ─── Calibration philosophy ───────────────────────────────────────────────
/// EastAsian baseline 은 우리 2D MediaPipe proxy 측정 frame 에서 empirical
/// 재보정된 값 (2026-04-14). 타 5 인종 mean 은 clinical anthropometry 의
/// "EA 대비 delta" 를 proxy frame 에 보수적으로 적용했다. sd 는 empirical N
/// 누적 전까지 동아시아 baseline 그대로 — 일률 widening 보다는 conservative
/// 유지가 안전.
///
/// References (인종간 delta 출처):
///   - Farkas LG et al. (2005) *International Anthropometric Study of Facial
///     Morphology* J Craniofac Surg 16(4):615-646 — nasofrontal/nasolabial
///     angles per population.
///   - Sforza C et al. (2009) *Soft-tissue facial planes and masculine-feminine
///     differences* — gender × ancestry dimorphism in lateral profile.
///   - Mommaerts MY et al. (2014) facial harmony references — lip projection
///     (E-line), mentolabial angle population variation.
///   - Naini FB et al. (2017) PMC5292106 — mentolabial angle ethnic subgroups.
///
/// ─── 영향 ────────────────────────────────────────────────────────────────
/// 이 표 도입 전 모든 인종이 동아 baseline 으로 z-score → caucasian male 의
/// dorsalConvexity 가 거의 항상 z≥3 → spurious `aquilineNose` flag → L-AQ rule
/// 로 leadership +1.5 시스템 편향. 표 도입 후 인종별 baseline 대비 *진짜로*
/// aquiline 한 사람만 flag 발동.
const Map<Ethnicity, Map<Gender, Map<String, MetricReference>>>
    lateralReferenceData = {
  Ethnicity.eastAsian: _eastAsianLateral,
  Ethnicity.caucasian: _caucasianLateral,
  Ethnicity.african: _africanLateral,
  Ethnicity.southeastAsian: _southeastAsianLateral,
  Ethnicity.hispanic: _hispanicLateral,
  Ethnicity.middleEastern: _middleEasternLateral,
};

// ─── Caucasian — strong dorsal convexity (aquiline tendency), retrusive lips,
//     more projected tip, more acute nasofrontal/mentolabial angles ────────
const Map<Gender, Map<String, MetricReference>> _caucasianLateral = {
  Gender.male: {
    'nasofrontalAngle': MetricReference(121.0, 9.0),
    'nasolabialAngle': MetricReference(128.0, 12.0),
    'facialConvexity': MetricReference(4.5, 3.9),
    'upperLipEline': MetricReference(-0.010, 0.007),
    'lowerLipEline': MetricReference(-0.005, 0.007),
    'mentolabialAngle': MetricReference(124.0, 3.8),
    'noseTipProjection': MetricReference(0.35, 0.04),
    'dorsalConvexity': MetricReference(0.020, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(131.0, 10.0),
    'nasolabialAngle': MetricReference(130.0, 12.0),
    'facialConvexity': MetricReference(5.0, 3.9),
    'upperLipEline': MetricReference(-0.010, 0.007),
    'lowerLipEline': MetricReference(-0.003, 0.007),
    'mentolabialAngle': MetricReference(124.0, 3.3),
    'noseTipProjection': MetricReference(0.34, 0.04),
    'dorsalConvexity': MetricReference(0.015, 0.008),
  },
};

// ─── African — prognathic profile, protrusive lips, flatter (less projected)
//     nose tip, wider nasofrontal, no aquiline tendency ────────────────────
const Map<Gender, Map<String, MetricReference>> _africanLateral = {
  Gender.male: {
    'nasofrontalAngle': MetricReference(137.0, 9.0),
    'nasolabialAngle': MetricReference(132.0, 12.0),
    'facialConvexity': MetricReference(11.0, 3.9),
    'upperLipEline': MetricReference(0.005, 0.007),
    'lowerLipEline': MetricReference(0.008, 0.007),
    'mentolabialAngle': MetricReference(130.0, 3.8),
    'noseTipProjection': MetricReference(0.25, 0.04),
    'dorsalConvexity': MetricReference(0.000, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(144.0, 10.0),
    'nasolabialAngle': MetricReference(134.0, 12.0),
    'facialConvexity': MetricReference(11.5, 3.9),
    'upperLipEline': MetricReference(0.005, 0.007),
    'lowerLipEline': MetricReference(0.008, 0.007),
    'mentolabialAngle': MetricReference(130.0, 3.3),
    'noseTipProjection': MetricReference(0.25, 0.04),
    'dorsalConvexity': MetricReference(0.000, 0.008),
  },
};

// ─── Southeast Asian — close to East Asian; slightly fuller lips, slightly
//     less projected tip, marginally more facial convexity ─────────────────
const Map<Gender, Map<String, MetricReference>> _southeastAsianLateral = {
  Gender.male: {
    'nasofrontalAngle': MetricReference(130.0, 9.0),
    'nasolabialAngle': MetricReference(132.0, 12.0),
    'facialConvexity': MetricReference(9.0, 3.9),
    'upperLipEline': MetricReference(-0.001, 0.007),
    'lowerLipEline': MetricReference(0.005, 0.007),
    'mentolabialAngle': MetricReference(132.0, 3.8),
    'noseTipProjection': MetricReference(0.28, 0.04),
    'dorsalConvexity': MetricReference(0.005, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(138.0, 10.0),
    'nasolabialAngle': MetricReference(132.0, 12.0),
    'facialConvexity': MetricReference(9.0, 3.9),
    'upperLipEline': MetricReference(-0.001, 0.007),
    'lowerLipEline': MetricReference(0.005, 0.007),
    'mentolabialAngle': MetricReference(130.0, 3.3),
    'noseTipProjection': MetricReference(0.27, 0.04),
    'dorsalConvexity': MetricReference(0.005, 0.008),
  },
};

// ─── Hispanic — intermediate between Caucasian and Southeast Asian ───────
const Map<Gender, Map<String, MetricReference>> _hispanicLateral = {
  Gender.male: {
    'nasofrontalAngle': MetricReference(125.0, 9.0),
    'nasolabialAngle': MetricReference(130.0, 12.0),
    'facialConvexity': MetricReference(6.0, 3.9),
    'upperLipEline': MetricReference(-0.005, 0.007),
    'lowerLipEline': MetricReference(0.000, 0.007),
    'mentolabialAngle': MetricReference(126.0, 3.8),
    'noseTipProjection': MetricReference(0.32, 0.04),
    'dorsalConvexity': MetricReference(0.012, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(132.0, 10.0),
    'nasolabialAngle': MetricReference(130.0, 12.0),
    'facialConvexity': MetricReference(6.5, 3.9),
    'upperLipEline': MetricReference(-0.005, 0.007),
    'lowerLipEline': MetricReference(0.000, 0.007),
    'mentolabialAngle': MetricReference(126.0, 3.3),
    'noseTipProjection': MetricReference(0.31, 0.04),
    'dorsalConvexity': MetricReference(0.010, 0.008),
  },
};

// ─── Middle Eastern — strongest aquiline + high projection + retrusive lips
//     + acute mentolabial. Persian/Arab/Turkish aggregated. ───────────────
const Map<Gender, Map<String, MetricReference>> _middleEasternLateral = {
  Gender.male: {
    'nasofrontalAngle': MetricReference(122.0, 9.0),
    'nasolabialAngle': MetricReference(127.0, 12.0),
    'facialConvexity': MetricReference(5.0, 3.9),
    'upperLipEline': MetricReference(-0.010, 0.007),
    'lowerLipEline': MetricReference(-0.003, 0.007),
    'mentolabialAngle': MetricReference(124.0, 3.8),
    'noseTipProjection': MetricReference(0.34, 0.04),
    'dorsalConvexity': MetricReference(0.022, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(130.0, 10.0),
    'nasolabialAngle': MetricReference(128.0, 12.0),
    'facialConvexity': MetricReference(5.5, 3.9),
    'upperLipEline': MetricReference(-0.010, 0.007),
    'lowerLipEline': MetricReference(-0.003, 0.007),
    'mentolabialAngle': MetricReference(124.0, 3.3),
    'noseTipProjection': MetricReference(0.33, 0.04),
    'dorsalConvexity': MetricReference(0.018, 0.008),
  },
};

const Map<Gender, Map<String, MetricReference>> _eastAsianLateral = {
  Gender.male: {
    // Moon et al. 2013 (PMC3785598), n=50 Korean M, CT scan.
    'nasofrontalAngle': MetricReference(131.0, 9.0),
    // Calibrated to our 2D-proxy measurement (NOT clinical NLA). See
    // nasolabialAngle doc comment for details. Mean ~135° with normal noses
    // reading 125-145°, drooping 100-120°, genuine snub 155-175°.
    'nasolabialAngle': MetricReference(135.0, 12.0),
    // Kim & Kim 2001 Korean J Orthod (combined sex, used here for both).
    'facialConvexity': MetricReference(7.7, 3.9),
    // Triangulated Korean/Chinese norms — normalized by faceHeight.
    // Raw mm value ~ -1mm; on a faceHeight ≈ 0.5 (normalized) it scales to
    // approximately -0.0033. SD scaled equivalently.
    'upperLipEline': MetricReference(-0.003, 0.007),
    'lowerLipEline': MetricReference(0.002, 0.007),
    // Naini et al. 2017 PMC5292106, Asian Far Eastern subsample, n=185 M.
    'mentolabialAngle': MetricReference(134.8, 3.8),
    // No published ratio mean; estimated from Goode-style normalization on
    // Korean face proportions.
    'noseTipProjection': MetricReference(0.30, 0.04),
    // No published continuous norm (PubMed 20591758 reports types, not a
    // continuous distribution). Empirical re-calibration 2026-04-14: at
    // 50-60 deg yaw capture, typical (non-aquiline) faces produce
    // dorsalConvexity in 0.005-0.018 range due to natural bridge curvature +
    // mesh noise + projection geometry. Pronounced 매부리 reaches 0.030+.
    // Tune further as real-device data accumulates.
    'dorsalConvexity': MetricReference(0.010, 0.008),
  },
  Gender.female: {
    'nasofrontalAngle': MetricReference(141.0, 10.0),
    'nasolabialAngle': MetricReference(135.0, 12.0),
    'facialConvexity': MetricReference(7.7, 3.9),
    'upperLipEline': MetricReference(-0.003, 0.007),
    'lowerLipEline': MetricReference(0.002, 0.007),
    'mentolabialAngle': MetricReference(133.4, 3.3),
    'noseTipProjection': MetricReference(0.30, 0.04),
    'dorsalConvexity': MetricReference(0.010, 0.008),
  },
};
