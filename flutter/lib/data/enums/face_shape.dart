/// 얼굴형 분류 — ML 분류기(FaceShapeClass) 출력을 도메인 enum 으로 승격.
///
/// 관상학적 해석 체계에서 얼굴형은 삼정·오관 해석보다 먼저 오는 "첫 관문".
/// Stage 0 preset delta (attribute_derivation.dart) 와 archetype overlay,
/// 서술 엔진 variation 의 key 로 사용된다.
library;

import 'dart:math';

enum FaceShape {
  /// 계란형 (oval) — 균형·조화·복덕
  oval,

  /// 세로로 긴 얼굴형 (oblong) — 이지·예술·감성
  oblong,

  /// 둥근 얼굴형 (round) — 식복·원만·낙천
  round,

  /// 각진 얼굴형 (square) — 우직·실행·의지
  square,

  /// 하트형 (heart) — 총명·민감·예술
  heart,

  /// 분류 실패 / 신뢰도 낮음 → preset delta 0 (중립)
  unknown,
}

extension FaceShapeLabel on FaceShape {
  String get korean {
    switch (this) {
      case FaceShape.oval:
        return '계란형';
      case FaceShape.oblong:
        return '세로로 긴 얼굴형';
      case FaceShape.round:
        return '둥근 얼굴형';
      case FaceShape.square:
        return '각진 얼굴형';
      case FaceShape.heart:
        return '하트형';
      case FaceShape.unknown:
        return '일반형';
    }
  }

  String get english {
    switch (this) {
      case FaceShape.oval:
        return 'Oval';
      case FaceShape.oblong:
        return 'Oblong';
      case FaceShape.round:
        return 'Round';
      case FaceShape.square:
        return 'Square';
      case FaceShape.heart:
        return 'Heart';
      case FaceShape.unknown:
        return 'Unknown';
    }
  }

  /// 분류기 영어 라벨('Heart'|'Oblong'|'Oval'|'Round'|'Square') → enum.
  static FaceShape fromEnglish(String? label) {
    switch (label) {
      case 'Heart':
        return FaceShape.heart;
      case 'Oblong':
        return FaceShape.oblong;
      case 'Oval':
        return FaceShape.oval;
      case 'Round':
        return FaceShape.round;
      case 'Square':
        return FaceShape.square;
      default:
        return FaceShape.unknown;
    }
  }
}

/// 한국 성인 얼굴형 분포 — MC calibration (score_calibration).
/// 합 = 1.00. 실사용자 데이터 확보 후 재보정 대상.
const Map<FaceShape, double> koreanShapeDistribution = {
  FaceShape.oval: 0.35,
  FaceShape.oblong: 0.18,
  FaceShape.round: 0.15,
  FaceShape.square: 0.12,
  FaceShape.heart: 0.10,
  FaceShape.unknown: 0.10,
};

/// koreanShapeDistribution 에서 샘플 1개 드로우. calibration MC 공용.
FaceShape drawShape(Random rng) {
  final u = rng.nextDouble();
  double acc = 0;
  for (final entry in koreanShapeDistribution.entries) {
    acc += entry.value;
    if (u <= acc) return entry.key;
  }
  return FaceShape.unknown;
}

/// 3-metric fallback classifier — ML 확신도 낮을 때 결정적 규칙으로 대체.
/// input: ref 대비 z-score. 모든 입력은 성별·인종 보정 완료된 값.
///
/// 모든 축이 중립(|z|<0.3, midFace<0.5) 이면 FaceShape.unknown 반환.
/// "애매하면 oval" 로 자동 귀속시키면 매력도 preset(+0.30) 이 과도하게 적용됨.
FaceShape classifyShapeByMetrics({
  required double aspectZ,
  required double taperZ,
  required double midFaceZ,
}) {
  if (aspectZ >= 1.2) return FaceShape.oblong;
  if (aspectZ <= -1.2) return FaceShape.round;
  if (taperZ >= 0.8) return FaceShape.heart;
  if (taperZ <= -0.8) return FaceShape.round; // 배형도 둥근 쪽으로 귀속(5-class 한계)
  if (midFaceZ >= 1.0) return FaceShape.square;
  if (aspectZ >= 0.3 && taperZ.abs() < 0.4) return FaceShape.oval;
  // 3 축 모두 중립 — 뚜렷한 얼굴형 신호 없음. preset 중립.
  return FaceShape.unknown;
}
