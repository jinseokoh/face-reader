import 'package:face_engine/data/constants/ethnicity_factors.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';

class _AgeOffset {
  final double male;
  final double female;
  const _AgeOffset(this.male, this.female);
}

const _ageOffsets = <String, _AgeOffset>{
  'lipFullnessRatio': _AgeOffset(-0.5, -0.7),
  'mouthCornerAngle': _AgeOffset(-0.6, -0.8),
  'browEyeDistance': _AgeOffset(-0.4, -0.5),
  'philtrumLength': _AgeOffset(0.5, 0.6),
  'eyebrowThickness': _AgeOffset(0.3, -0.3),
};

/// 50대 이상일 때 노화에 의한 체계적 편향을 제거한다.
///
///   z_adjusted = z_raw − (gender_offset × ethnicityScale)
///
/// [ethnicity] 는 노화 trajectory 가 인종별로 다르다는 dermatology robust
/// 발견 ([agingTrajectoryScale]) 을 반영하는 multiplier. Asian/African 은
/// Caucasian 대비 wrinkle/sagging 발현이 5~10년 지연되므로 같은 50+ 라도
/// metric 변화량을 축소 적용해야 한다.
double adjustForAge(
  String metricId,
  double zRaw,
  Gender gender,
  Ethnicity ethnicity,
  bool isOver50,
) {
  if (!isOver50) return zRaw;

  final offsets = _ageOffsets[metricId];
  if (offsets == null) return zRaw;

  final base = gender == Gender.male ? offsets.male : offsets.female;
  final scale = agingTrajectoryScale[ethnicity] ?? 1.0;
  return zRaw - base * scale;
}
