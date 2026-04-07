import 'package:face_reader/data/enums/gender.dart';

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
/// z_adjusted = z_raw - age_offset
double adjustForAge(String metricId, double zRaw, Gender gender, bool isOver50) {
  if (!isOver50) return zRaw;

  final offsets = _ageOffsets[metricId];
  if (offsets == null) return zRaw;

  final offset = gender == Gender.male ? offsets.male : offsets.female;
  return zRaw - offset;
}
