/// 분석 확신도 (APPLE.md §14·§29) — 촬영 조건 기반 3단.
///
/// "이 사진이 분석에 적합했는가" 를 저장 좌표에서만 판정한다 (재현 가능, §59).
/// 세 신호를 보고 가장 나쁜 쪽을 따른다.
///   yaw   : 코끝이 얼굴 좌우 가장자리 사이 어디에 있는가, |(l−r)/(l+r)|. 0 = 정면.
///           AAF 기준 집단(자세 필터 ≤ 18°)의 p95 ≈ 0.45 → 그 안이면 기준 집단과
///           같은 조건. 0.70 은 촬영 흐름의 정면 판정 한계(classifyYaw).
///   폭    : 얼굴 폭 / 사진 폭. 0.12 미만은 촬영 단계에서 이미 거른다(§60).
///   대칭  : 전체 비대칭도 z. 기울인 사진은 대칭이 크게 깨진다.
/// 수치가 사람의 특성이 아니라 사진 상태를 말한다는 점을 화면 문구가 밝힌다.
library;

import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/first_impression.dart';

enum AnalysisConfidence {
  high('높음'),
  medium('보통'),
  low('낮음');

  const AnalysisConfidence(this.labelKo);
  final String labelKo;
}

const double kConfidenceYawHigh = 0.45;
const double kConfidenceYawMedium = 0.70;
const double kConfidenceWidthHigh = 0.20;
const double kConfidenceSymZMedium = 2.0;
const double kConfidenceSymZLow = 3.0;

/// 좌표에서 본 yaw — face_metrics_lateral.estimateYaw 와 같은 식 (x 만 쓴다).
double landmarkYaw(List<List<double>> pts) {
  final nose = pts[1][0];
  final r = (nose - pts[234][0]).abs();
  final l = (pts[454][0] - nose).abs();
  final total = r + l;
  return total == 0 ? 0 : (l - r) / total;
}

/// 얼굴 폭 / 사진 폭 (x 는 폭 기준 정규화 좌표).
double faceWidthFraction(List<List<double>> pts) =>
    (pts[454][0] - pts[234][0]).abs();

AnalysisConfidence analysisConfidence({
  required List<List<double>> landmarks,
  required Gender gender,
  Map<String, double>? symmetry,
}) {
  final yaw = landmarkYaw(landmarks).abs();
  final width = faceWidthFraction(landmarks);
  final symZ = symmetryOverallZ(symmetry, gender) ?? 0;
  if (yaw > kConfidenceYawMedium || symZ >= kConfidenceSymZLow) {
    return AnalysisConfidence.low;
  }
  if (yaw > kConfidenceYawHigh ||
      width < kConfidenceWidthHigh ||
      symZ >= kConfidenceSymZMedium) {
    return AnalysisConfidence.medium;
  }
  return AnalysisConfidence.high;
}
