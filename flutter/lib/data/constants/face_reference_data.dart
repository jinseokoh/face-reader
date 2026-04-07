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
    Gender.male: {
      'faceAspectRatio': MetricReference(1.40, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.85, 0.05),
      'gonialAngle': MetricReference(118.0, 7.0),
      'intercanthalRatio': MetricReference(0.27, 0.02),
      'eyeFissureRatio': MetricReference(0.23, 0.02),
      'eyeCanthalTilt': MetricReference(3.5, 3.0),
      'eyebrowThickness': MetricReference(0.017, 0.004),
      'browEyeDistance': MetricReference(0.058, 0.014),
      'nasalWidthRatio': MetricReference(1.08, 0.10),


      'nasalHeightRatio': MetricReference(0.30, 0.02),
      'mouthWidthRatio': MetricReference(0.39, 0.03),
      'mouthCornerAngle': MetricReference(-0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.09, 0.02),
      'philtrumLength': MetricReference(0.085, 0.015),
    },
    Gender.female: {
      'faceAspectRatio': MetricReference(1.36, 0.07),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.33, 0.02),
      'lowerFaceRatio': MetricReference(0.34, 0.03),
      'faceTaperRatio': MetricReference(0.79, 0.05),
      'gonialAngle': MetricReference(122.0, 8.0),
      'intercanthalRatio': MetricReference(0.27, 0.02),
      'eyeFissureRatio': MetricReference(0.25, 0.02),
      'eyeCanthalTilt': MetricReference(4.5, 3.0),
      'eyebrowThickness': MetricReference(0.013, 0.003),
      'browEyeDistance': MetricReference(0.062, 0.015),
      'nasalWidthRatio': MetricReference(1.02, 0.09),


      'nasalHeightRatio': MetricReference(0.30, 0.02),
      'mouthWidthRatio': MetricReference(0.37, 0.03),
      'mouthCornerAngle': MetricReference(0.5, 3.0),
      'lipFullnessRatio': MetricReference(0.11, 0.02),
      'philtrumLength': MetricReference(0.075, 0.013),
    },
  },
  Ethnicity.caucasian: {
    Gender.male: {
      'faceAspectRatio': MetricReference(1.37, 0.08),
      'upperFaceRatio': MetricReference(0.33, 0.03),
      'midFaceRatio': MetricReference(0.34, 0.02),
      'lowerFaceRatio': MetricReference(0.33, 0.03),
      'faceTaperRatio': MetricReference(0.83, 0.05),
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
      'faceTaperRatio': MetricReference(0.80, 0.05),
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
