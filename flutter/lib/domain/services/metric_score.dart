import 'package:face_reader/data/enums/metric_type.dart';

/// z-score → Metric Score (S) 변환 (정수, rule trigger 용도)
/// ratio: 7단계 (-3 ~ +3), angle: 5단계 (-2 ~ +2), shape: 3단계 (-2 ~ +2)
int convertToScore(double z, MetricType type) {
  return switch (type) {
    MetricType.ratio => _ratioScore(z),
    MetricType.angle => _angleScore(z),
    MetricType.shape => _shapeScore(z),
  };
}

/// z-score → Continuous Metric Score (attribute 가중합 용도)
/// 양자화 없이 연속값을 보존하여 미세한 차이가 결과에 반영되도록 함.
/// 극단값은 ±3.5로 hard clip (랜드마크 노이즈로 인한 outlier 방어)
double convertToContinuousScore(double z, MetricType type) {
  return z.clamp(-3.5, 3.5);
}

/// Ratio 계열 — 7단계
int _ratioScore(double z) {
  if (z >= 2.0) return 3;
  if (z >= 1.0) return 2;
  if (z >= 0.5) return 1;
  if (z > -0.5) return 0;
  if (z > -1.0) return -1;
  if (z > -2.0) return -2;
  return -3;
}

/// Angle 계열 — 5단계
int _angleScore(double z) {
  if (z >= 1.5) return 2;
  if (z >= 0.5) return 1;
  if (z > -0.5) return 0;
  if (z > -1.5) return -1;
  return -2;
}

/// Shape 계열 — 3단계 (발달/보통/미발달)
int _shapeScore(double z) {
  final abs = z.abs();
  if (abs < 0.3) return 0;
  final sign = z > 0 ? 1 : -1;
  if (abs < 1.0) return sign * 1;
  return sign * 2;
}
