/// 음양(陰陽) 쏠림 측정 — 관상학 전통의 양기(陽氣) · 음기(陰氣) 축.
///
/// 각 metric 이 "양 방향" 인지 "음 방향" 인지 고전 관상학 기준으로 부호 태깅한
/// 뒤 z-score 가중합. 결과 skew:
///   +  = 양기 우세 (강건·각진 선·돌출·외향·적극성)
///   −  = 음기 우세 (부드러움·수분감·풍성·내향·수용성)
///   ≈0 = 음양 조화 (중용의 상)
///
/// 한국 관상학 음양 전통 — 남성은 양(陽) baseline, 여성은 음(陰) baseline.
/// raw skew 에서 gender baseline 을 빼서 "예상 baseline 대비 얼마나 벗어
/// 났는가" 를 표시한다. 평균 남성 → skew ≈ 0 (양 baseline 정상), 평균
/// 여성 → skew ≈ 0 (음 baseline 정상). 양·음 쏠림 신호는 사용자가
/// *자기 gender 기준* 에서 벗어났을 때만 부각.
///
/// 근거:
/// - 양기 증강: 이마 넓음·턱 각도·광대 돌출·눈썹 두꺼움·코 높이·콧대 돌출.
/// - 음기 증강: 도톰한 입술·하정 풍성·큰 눈(수기)·긴 인중·부드러운 입꼬리.
/// - gender baseline: 한국 관상 전통의 음양 분류 — 남성=양, 여성=음 의
///   "정상 baseline" 위에서 deviation 측정.
///
/// 출처: 한국 관상학 전통의 음양 해석 + 현대 관상 교재 통용 기준. 수치
/// weight 는 관상 전통 상대 중요도 + 현실 얼굴 분산 고려.
library;

import 'package:face_engine/data/enums/gender.dart';

enum YinYangTone {
  strongYang,   // skew ≥ +1.0
  leaningYang,  // skew ≥ +0.3
  harmony,      // |skew| < 0.3
  leaningYin,   // skew ≤ -0.3
  strongYin,    // skew ≤ -1.0
}

class YinYangBalance {
  /// 양기(+) — 음기(−) 축 위의 쏠림 정도, gender baseline 제거 후.
  /// 보통 [-2.5, +2.5] 범위. 평균 남성·평균 여성 모두 ≈ 0.
  final double skew;

  /// 음양 둘 다 더한 총 "강도" — 존재감의 크기. 얼굴이 얼마나 특징적인지.
  /// gender baseline 영향 없음 (절대 magnitude).
  final double magnitude;

  const YinYangBalance({required this.skew, required this.magnitude});

  YinYangTone get tone {
    if (skew >= 1.0) return YinYangTone.strongYang;
    if (skew >= 0.3) return YinYangTone.leaningYang;
    if (skew <= -1.0) return YinYangTone.strongYin;
    if (skew <= -0.3) return YinYangTone.leaningYin;
    return YinYangTone.harmony;
  }

  String get label {
    switch (tone) {
      case YinYangTone.strongYang:
        return '양기(陽氣) 우세';
      case YinYangTone.leaningYang:
        return '양기 경향';
      case YinYangTone.strongYin:
        return '음기(陰氣) 우세';
      case YinYangTone.leaningYin:
        return '음기 경향';
      case YinYangTone.harmony:
        return '음양 조화';
    }
  }
}

/// 각 metric 의 z-score 앞에 붙는 축 가중치.
/// positive → 양 방향 증강, negative → 음 방향 증강.
const Map<String, double> _yyWeights = {
  // 양기 증강 (+)
  'foreheadWidth': 0.15,
  'gonialAngle': 0.15,         // 각진 턱 (크면 각짐)
  'cheekboneWidth': 0.15,
  'eyebrowThickness': 0.15,
  'nasalHeightRatio': 0.10,
  'nasalWidthRatio': 0.08,
  'noseTipProjection': 0.08,   // lateral
  'dorsalConvexity': 0.08,     // lateral
  'facialConvexity': 0.05,     // lateral

  // 음기 증강 (−)
  'lipFullnessRatio': -0.20,
  'lowerFaceFullness': -0.15,
  'eyeFissureRatio': -0.10,    // 큰 눈 = 수기·달
  'mouthCornerAngle': -0.10,
  'philtrumLength': -0.10,
  'upperLipEline': -0.05,      // lateral
  'lowerLipEline': -0.05,      // lateral
};

/// Gender baseline — raw skew 에서 빼는 값. 남=+양 / 여=−음 의 canonical
/// expectation. 평균 남성 raw skew ≈ +0.3 → adjusted skew ≈ 0 (정상). 평균
/// 여성 raw skew ≈ −0.3 → adjusted skew ≈ 0 (정상). 평균에서 벗어날 때만
/// strongYang/leaningYin 등 tone 이 활성.
const Map<Gender, double> _yyGenderBaseline = {
  Gender.male: 0.30,
  Gender.female: -0.30,
};

/// z-map(metric id → z-score) + gender 으로 음양 balance 계산.
/// frontal 17 + lateral 8 모두 혼재 가능. 없는 metric 은 0 으로 간주.
/// gender baseline 을 빼서 "성별 expectation 대비 deviation" 을 표시한다.
YinYangBalance computeYinYang(Map<String, double> zMap, Gender gender) {
  double rawSkew = 0;
  double mag = 0;
  _yyWeights.forEach((metricId, weight) {
    final z = zMap[metricId] ?? 0.0;
    final contrib = weight * z;
    rawSkew += contrib;
    mag += contrib.abs();
  });
  final baseline = _yyGenderBaseline[gender] ?? 0.0;
  return YinYangBalance(skew: rawSkew - baseline, magnitude: mag);
}
