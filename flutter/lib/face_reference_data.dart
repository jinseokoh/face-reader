enum Ethnicity {
  eastAsian,
  caucasian,
  african,
  southeastAsian,
  hispanic,
  middleEastern,
}

extension EthnicityLabel on Ethnicity {
  String get labelKo => switch (this) {
        Ethnicity.eastAsian => '동아시아인',
        Ethnicity.caucasian => '백인',
        Ethnicity.african => '아프리카인',
        Ethnicity.southeastAsian => '동남아시아인',
        Ethnicity.hispanic => '히스패닉',
        Ethnicity.middleEastern => '중동인',
      };
}

class MetricReference {
  final double mean;
  final double sd;

  const MetricReference(this.mean, this.sd);
}

class MetricInfo {
  final String id;
  final String nameKo;
  final String nameEn;
  final String category; // 'face', 'eyes', 'nose', 'mouth'
  final String higherLabel; // e.g. "넓음", "큼"
  final String lowerLabel; // e.g. "좁음", "작음"

  const MetricInfo({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.category,
    required this.higherLabel,
    required this.lowerLabel,
  });
}

const metricInfoList = [
  MetricInfo(
    id: 'faceAspectRatio',
    nameKo: '얼굴 종횡비',
    nameEn: 'Face Aspect Ratio',
    category: 'face',
    higherLabel: '세로로 긴 얼굴',
    lowerLabel: '가로로 넓은 얼굴',
  ),
  MetricInfo(
    id: 'upperFaceRatio',
    nameKo: '상안면 비율',
    nameEn: 'Upper Face Ratio',
    category: 'face',
    higherLabel: '이마가 넓음',
    lowerLabel: '이마가 좁음',
  ),
  MetricInfo(
    id: 'midFaceRatio',
    nameKo: '중안면 비율',
    nameEn: 'Mid Face Ratio',
    category: 'face',
    higherLabel: '중안면이 긺',
    lowerLabel: '중안면이 짧음',
  ),
  MetricInfo(
    id: 'lowerFaceRatio',
    nameKo: '하안면 비율',
    nameEn: 'Lower Face Ratio',
    category: 'face',
    higherLabel: '턱이 긺',
    lowerLabel: '턱이 짧음',
  ),
  MetricInfo(
    id: 'intercanthalRatio',
    nameKo: '눈 사이 거리',
    nameEn: 'Intercanthal Distance',
    category: 'eyes',
    higherLabel: '눈 사이가 넓음',
    lowerLabel: '눈 사이가 좁음',
  ),
  MetricInfo(
    id: 'eyeFissureRatio',
    nameKo: '눈 길이',
    nameEn: 'Eye Fissure Length',
    category: 'eyes',
    higherLabel: '눈이 긺',
    lowerLabel: '눈이 짧음',
  ),
  MetricInfo(
    id: 'eyeOpenness',
    nameKo: '눈 크기',
    nameEn: 'Eye Openness',
    category: 'eyes',
    higherLabel: '눈이 큼',
    lowerLabel: '눈이 작음',
  ),
  MetricInfo(
    id: 'nasalWidthRatio',
    nameKo: '코 너비',
    nameEn: 'Nasal Width',
    category: 'nose',
    higherLabel: '코가 넓음',
    lowerLabel: '코가 좁음',
  ),
  MetricInfo(
    id: 'nasalHeightRatio',
    nameKo: '코 길이',
    nameEn: 'Nasal Height',
    category: 'nose',
    higherLabel: '코가 긺',
    lowerLabel: '코가 짧음',
  ),
  MetricInfo(
    id: 'mouthWidthRatio',
    nameKo: '입 너비',
    nameEn: 'Mouth Width',
    category: 'mouth',
    higherLabel: '입이 넓음',
    lowerLabel: '입이 좁음',
  ),
  MetricInfo(
    id: 'lipFullnessRatio',
    nameKo: '입술 두께',
    nameEn: 'Lip Fullness',
    category: 'mouth',
    higherLabel: '입술이 두꺼움',
    lowerLabel: '입술이 얇음',
  ),
  MetricInfo(
    id: 'mouthCornerAngle',
    nameKo: '입꼬리 각도',
    nameEn: 'Mouth Corner Angle',
    category: 'mouth',
    higherLabel: '입꼬리가 올라감',
    lowerLabel: '입꼬리가 내려감',
  ),
];

// Population reference data by ethnicity
// Sources: Farkas anthropometric studies, ICD meta-analysis (PMC9029890), NIOSH dataset
const Map<Ethnicity, Map<String, MetricReference>> referenceData = {
  Ethnicity.eastAsian: {
    'faceAspectRatio': MetricReference(1.38, 0.08),
    'upperFaceRatio': MetricReference(0.33, 0.03),
    'midFaceRatio': MetricReference(0.33, 0.02),
    'lowerFaceRatio': MetricReference(0.34, 0.03),
    'intercanthalRatio': MetricReference(0.27, 0.02),
    'eyeFissureRatio': MetricReference(0.24, 0.02),
    'eyeOpenness': MetricReference(0.35, 0.05),
    'nasalWidthRatio': MetricReference(1.05, 0.10),
    'nasalHeightRatio': MetricReference(0.30, 0.02),
    'mouthWidthRatio': MetricReference(0.38, 0.03),
    'lipFullnessRatio': MetricReference(0.10, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
  Ethnicity.caucasian: {
    'faceAspectRatio': MetricReference(1.35, 0.08),
    'upperFaceRatio': MetricReference(0.33, 0.03),
    'midFaceRatio': MetricReference(0.33, 0.02),
    'lowerFaceRatio': MetricReference(0.34, 0.03),
    'intercanthalRatio': MetricReference(0.23, 0.02),
    'eyeFissureRatio': MetricReference(0.23, 0.02),
    'eyeOpenness': MetricReference(0.38, 0.05),
    'nasalWidthRatio': MetricReference(0.95, 0.10),
    'nasalHeightRatio': MetricReference(0.31, 0.02),
    'mouthWidthRatio': MetricReference(0.37, 0.03),
    'lipFullnessRatio': MetricReference(0.09, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
  Ethnicity.african: {
    'faceAspectRatio': MetricReference(1.32, 0.08),
    'upperFaceRatio': MetricReference(0.32, 0.03),
    'midFaceRatio': MetricReference(0.32, 0.02),
    'lowerFaceRatio': MetricReference(0.36, 0.03),
    'intercanthalRatio': MetricReference(0.29, 0.02),
    'eyeFissureRatio': MetricReference(0.24, 0.02),
    'eyeOpenness': MetricReference(0.37, 0.05),
    'nasalWidthRatio': MetricReference(1.20, 0.12),
    'nasalHeightRatio': MetricReference(0.28, 0.02),
    'mouthWidthRatio': MetricReference(0.40, 0.03),
    'lipFullnessRatio': MetricReference(0.12, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
  Ethnicity.southeastAsian: {
    'faceAspectRatio': MetricReference(1.36, 0.08),
    'upperFaceRatio': MetricReference(0.33, 0.03),
    'midFaceRatio': MetricReference(0.33, 0.02),
    'lowerFaceRatio': MetricReference(0.34, 0.03),
    'intercanthalRatio': MetricReference(0.25, 0.02),
    'eyeFissureRatio': MetricReference(0.24, 0.02),
    'eyeOpenness': MetricReference(0.36, 0.05),
    'nasalWidthRatio': MetricReference(1.10, 0.10),
    'nasalHeightRatio': MetricReference(0.29, 0.02),
    'mouthWidthRatio': MetricReference(0.39, 0.03),
    'lipFullnessRatio': MetricReference(0.11, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
  Ethnicity.hispanic: {
    'faceAspectRatio': MetricReference(1.35, 0.08),
    'upperFaceRatio': MetricReference(0.33, 0.03),
    'midFaceRatio': MetricReference(0.33, 0.02),
    'lowerFaceRatio': MetricReference(0.34, 0.03),
    'intercanthalRatio': MetricReference(0.24, 0.02),
    'eyeFissureRatio': MetricReference(0.23, 0.02),
    'eyeOpenness': MetricReference(0.37, 0.05),
    'nasalWidthRatio': MetricReference(1.00, 0.10),
    'nasalHeightRatio': MetricReference(0.30, 0.02),
    'mouthWidthRatio': MetricReference(0.38, 0.03),
    'lipFullnessRatio': MetricReference(0.10, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
  Ethnicity.middleEastern: {
    'faceAspectRatio': MetricReference(1.36, 0.08),
    'upperFaceRatio': MetricReference(0.33, 0.03),
    'midFaceRatio': MetricReference(0.33, 0.02),
    'lowerFaceRatio': MetricReference(0.34, 0.03),
    'intercanthalRatio': MetricReference(0.23, 0.02),
    'eyeFissureRatio': MetricReference(0.24, 0.02),
    'eyeOpenness': MetricReference(0.38, 0.05),
    'nasalWidthRatio': MetricReference(1.00, 0.10),
    'nasalHeightRatio': MetricReference(0.31, 0.02),
    'mouthWidthRatio': MetricReference(0.37, 0.03),
    'lipFullnessRatio': MetricReference(0.09, 0.02),
    'mouthCornerAngle': MetricReference(0.0, 3.0),
  },
};
