import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/enums/metric_type.dart';

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
];

/// Reference data: [Ethnicity][Gender][metricId] → MetricReference(mean, sd)
const Map<Ethnicity, Map<Gender, Map<String, MetricReference>>> referenceData = {
  Ethnicity.eastAsian: {
    // ─── MediaPipe-calibrated reference (2026-04-12) ───
    // Original Farkas anthropometric data was incompatible with MediaPipe Face
    // Mesh landmark conventions, causing real Korean adult faces to systematically
    // produce z=±6~7 (clamped at ±3.5) on eyebrowThickness, browEyeDistance,
    // faceAspectRatio, and gonialAngle. After clamping, distinguishing info
    // between faces was lost → stability/trustworthiness/leadership saturated
    // for all Korean adults.
    //
    // Corrected means estimated from MediaPipe Face Mesh outputs on real photos.
    // SDs widened conservatively so typical real-face variation produces z in
    // [-2, +2], preserving distinguishing information across faces.
    Gender.male: {
      // PHYSICAL pixel space ratio. Calibrated from Flutter measurements,
      // male slightly more elongated than female (Korean adult).
      'faceAspectRatio': MetricReference(1.32, 0.07),
      'upperFaceRatio': MetricReference(0.32, 0.04),
      'midFaceRatio': MetricReference(0.31, 0.03),
      'lowerFaceRatio': MetricReference(0.38, 0.05),
      'faceTaperRatio': MetricReference(0.85, 0.05),
      'lowerFaceFullness': MetricReference(0.72, 0.05),
      'gonialAngle': MetricReference(137.0, 6.0),
      'intercanthalRatio': MetricReference(0.26, 0.02),
      'eyeFissureRatio': MetricReference(0.21, 0.025),
      'eyeCanthalTilt': MetricReference(4.0, 4.0),
      'eyebrowThickness': MetricReference(0.038, 0.006),
      'browEyeDistance': MetricReference(0.146, 0.022),
      'nasalWidthRatio': MetricReference(0.93, 0.10),
      'nasalHeightRatio': MetricReference(0.31, 0.03),
      'mouthWidthRatio': MetricReference(0.40, 0.05),
      'mouthCornerAngle': MetricReference(2.0, 5.0),
      'lipFullnessRatio': MetricReference(0.10, 0.025),
      'philtrumLength': MetricReference(0.094, 0.020),
    },
    Gender.female: {
      // PHYSICAL pixel space ratio (post imageHeight/imageWidth correction).
      // Re-calibrated 2026-04 on expanded sample set:
      //   이수지=1.264 (가로로 넓은)
      //   표준 band=1.321 / 1.336 / 1.363 / 1.396 (모두 표준)
      // mean=1.35, sd=0.07 →
      //   이수지 z=-1.23 (가로로 넓은)
      //   표준 band z ∈ [-0.41, +0.65] (|z|≤1, 표준)
      //   raw ≥ ~1.42 부터 z>1 → 세로로 긴
      // (이전 mean=1.29 는 raw 1.36~1.40 평범 얼굴을 "세로로 긴"으로 오분류했음)
      'faceAspectRatio': MetricReference(1.35, 0.07),
      'upperFaceRatio': MetricReference(0.31, 0.04),
      'midFaceRatio': MetricReference(0.30, 0.03),
      'lowerFaceRatio': MetricReference(0.39, 0.05),
      'faceTaperRatio': MetricReference(0.79, 0.05),
      'lowerFaceFullness': MetricReference(0.66, 0.05),
      'gonialAngle': MetricReference(141.0, 6.0),
      'intercanthalRatio': MetricReference(0.26, 0.02),
      'eyeFissureRatio': MetricReference(0.20, 0.025),
      'eyeCanthalTilt': MetricReference(5.0, 4.0),
      'eyebrowThickness': MetricReference(0.034, 0.005),
      'browEyeDistance': MetricReference(0.150, 0.020),
      'nasalWidthRatio': MetricReference(0.89, 0.10),
      'nasalHeightRatio': MetricReference(0.30, 0.03),
      'mouthWidthRatio': MetricReference(0.39, 0.05),
      'mouthCornerAngle': MetricReference(3.0, 5.0),
      'lipFullnessRatio': MetricReference(0.12, 0.025),
      'philtrumLength': MetricReference(0.090, 0.020),
    },
  },
  Ethnicity.caucasian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.37, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.83, 0.05),
      'lowerFaceFullness': MetricReference(0.7, 0.05),
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
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.33, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.77, 0.05),
      'lowerFaceFullness': MetricReference(0.64, 0.05),
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
    },
  },
  Ethnicity.african: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.34, 0.08),
      'upperFaceRatio': MetricReference(0.32, 0.03),
      'midFaceRatio': MetricReference(0.32, 0.02),
      'lowerFaceRatio': MetricReference(0.36, 0.03),
      'faceTaperRatio': MetricReference(0.86, 0.05),
      'lowerFaceFullness': MetricReference(0.73, 0.05),
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
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.30, 0.07),
      'upperFaceRatio': MetricReference(0.32, 0.03),
      'midFaceRatio': MetricReference(0.32, 0.02),
      'lowerFaceRatio': MetricReference(0.36, 0.03),
      'faceTaperRatio': MetricReference(0.8, 0.05),
      'lowerFaceFullness': MetricReference(0.67, 0.05),
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
    },
  },
  Ethnicity.southeastAsian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.38, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.71, 0.05),
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
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.34, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.65, 0.05),
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
    },
  },
  Ethnicity.hispanic: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.37, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.71, 0.05),
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
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.33, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.65, 0.05),
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
    },
  },
  Ethnicity.middleEastern: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.38, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.84, 0.05),
      'lowerFaceFullness': MetricReference(0.71, 0.05),
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
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.34, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.78, 0.05),
      'lowerFaceFullness': MetricReference(0.65, 0.05),
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
const Map<Ethnicity, Map<Gender, Map<String, MetricReference>>>
    lateralReferenceData = {
  Ethnicity.eastAsian: _eastAsianLateral,
  Ethnicity.caucasian: _eastAsianLateral,
  Ethnicity.african: _eastAsianLateral,
  Ethnicity.southeastAsian: _eastAsianLateral,
  Ethnicity.hispanic: _eastAsianLateral,
  Ethnicity.middleEastern: _eastAsianLateral,
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
