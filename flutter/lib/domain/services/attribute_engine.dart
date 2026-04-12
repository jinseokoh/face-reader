import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';

// ─── Types ───

class _MetricWeight {
  final String metricId;
  final double weight;
  final int polarity; // +1 or -1
  final bool useProximity;

  const _MetricWeight(this.metricId, this.weight, this.polarity,
      {this.useProximity = false});
}

class _GenderDelta {
  final double male;
  final double female;
  const _GenderDelta(this.male, this.female);
}

class TriggeredRule {
  final String id;
  final Map<Attribute, double> effects;
  const TriggeredRule(this.id, this.effects);
}

typedef _Condition = bool Function(Map<String, int> s);
typedef _AdjCondition = bool Function(Map<String, int> s, Map<String, int> sAdj);

class _InteractionRule {
  final String id;
  final _Condition condition;
  final Map<Attribute, double> effects;
  const _InteractionRule(this.id, this.condition, this.effects);
}

class _GenderRule {
  final String id;
  final Gender gender;
  final _Condition condition;
  final Map<Attribute, double> effects;
  const _GenderRule(this.id, this.gender, this.condition, this.effects);
}

class _AgeRule {
  final String id;
  final _AdjCondition condition;
  final Map<Attribute, double> effects;
  const _AgeRule(this.id, this.condition, this.effects);
}

// ─── Proximity function ───

/// proximity(S) = 2 - |S|  (S=0→2, |S|=3→-1)
double _proximity(int s) => 2.0 - s.abs();

/// Continuous proximity for double scores
double _proximityCont(double s) => 2.0 - s.abs();

// ─── Base Weight Tables (§6) ───

const _baseWeights = <Attribute, List<_MetricWeight>>{
  Attribute.wealth: [
    _MetricWeight('nasalWidthRatio', 0.45, 1),
    _MetricWeight('nasalHeightRatio', 0.25, 1),
    _MetricWeight('mouthWidthRatio', 0.20, 1),
    _MetricWeight('gonialAngle', 0.10, 1),
  ],
  Attribute.leadership: [
    _MetricWeight('gonialAngle', 0.30, 1),
    _MetricWeight('eyeCanthalTilt', 0.25, 1),
    _MetricWeight('eyebrowThickness', 0.15, 1),
    _MetricWeight('faceTaperRatio', 0.15, 1),
    _MetricWeight('browEyeDistance', 0.15, 1),
  ],
  Attribute.intelligence: [
    _MetricWeight('eyeFissureRatio', 0.35, 1),
    _MetricWeight('browEyeDistance', 0.30, 1),
    _MetricWeight('intercanthalRatio', 0.20, -1),
    _MetricWeight('faceAspectRatio', 0.15, 1),
  ],
  Attribute.sociability: [
    _MetricWeight('mouthWidthRatio', 0.30, 1),
    _MetricWeight('mouthCornerAngle', 0.30, 1),
    _MetricWeight('intercanthalRatio', 0.15, 1),
    _MetricWeight('lipFullnessRatio', 0.15, 1),
    _MetricWeight('eyeFissureRatio', 0.10, 1),
  ],
  Attribute.emotionality: [
    _MetricWeight('lipFullnessRatio', 0.30, 1),
    _MetricWeight('eyebrowThickness', 0.20, -1),
    _MetricWeight('mouthCornerAngle', 0.20, 1),
    _MetricWeight('browEyeDistance', 0.15, -1),
    _MetricWeight('philtrumLength', 0.15, 1),
  ],
  Attribute.stability: [
    _MetricWeight('browEyeDistance', 0.35, 1),
    _MetricWeight('eyebrowThickness', 0.25, 1),
    _MetricWeight('faceAspectRatio', 0.20, 1, useProximity: true),
    _MetricWeight('gonialAngle', 0.20, 1),
  ],
  Attribute.sensuality: [
    _MetricWeight('lipFullnessRatio', 0.25, 1),
    _MetricWeight('eyeCanthalTilt', 0.25, 1),
    _MetricWeight('mouthCornerAngle', 0.20, 1),
    _MetricWeight('philtrumLength', 0.15, -1),
    _MetricWeight('eyeFissureRatio', 0.15, 1),
  ],
  Attribute.trustworthiness: [
    _MetricWeight('browEyeDistance', 0.35, 1),
    _MetricWeight('mouthCornerAngle', 0.25, 1),
    _MetricWeight('eyebrowThickness', 0.20, 1),
    _MetricWeight('intercanthalRatio', 0.20, 1, useProximity: true),
  ],
  Attribute.attractiveness: [
    _MetricWeight('mouthCornerAngle', 0.20, 1),
    _MetricWeight('eyeCanthalTilt', 0.20, 1),
    _MetricWeight('faceAspectRatio', 0.15, 1, useProximity: true),
    _MetricWeight('lipFullnessRatio', 0.15, 1),
    _MetricWeight('faceTaperRatio', 0.15, 1),
    _MetricWeight('eyeFissureRatio', 0.15, 1),
  ],
  Attribute.libido: [
    _MetricWeight('philtrumLength', 0.25, -1),
    _MetricWeight('lipFullnessRatio', 0.20, 1),
    _MetricWeight('nasalWidthRatio', 0.20, 1),
    _MetricWeight('nasalHeightRatio', 0.25, 1),
    _MetricWeight('eyeCanthalTilt', 0.10, 1),
  ],
};

// ─── Gender Weight Deltas (§3.5) ───

const _genderDeltas = <Attribute, Map<String, _GenderDelta>>{
  Attribute.wealth: {
    'nasalWidthRatio': _GenderDelta(0.05, -0.05),
    'mouthWidthRatio': _GenderDelta(-0.05, 0.05),
  },
  Attribute.leadership: {
    'gonialAngle': _GenderDelta(0.05, -0.05),
    'eyeCanthalTilt': _GenderDelta(-0.05, 0.05),
  },
  Attribute.sensuality: {
    'lipFullnessRatio': _GenderDelta(-0.05, 0.05),
    'eyeCanthalTilt': _GenderDelta(0.05, -0.05),
  },
  Attribute.libido: {
    'nasalWidthRatio': _GenderDelta(0.05, -0.05),
    'lipFullnessRatio': _GenderDelta(-0.05, 0.05),
  },
  Attribute.attractiveness: {
    'faceTaperRatio': _GenderDelta(-0.05, 0.05),
    'gonialAngle': _GenderDelta(0.05, 0.0),
  },
};

double _getWeight(Attribute attr, String metricId, Gender gender) {
  final weights = _baseWeights[attr]!;
  double base = 0;
  for (final w in weights) {
    if (w.metricId == metricId) {
      base = w.weight;
      break;
    }
  }
  final delta = _genderDeltas[attr]?[metricId];
  if (delta == null) return base;
  return base + (gender == Gender.male ? delta.male : delta.female);
}

// ─── Base Score Computation ───

Map<Attribute, double> computeBaseScores(
    Map<String, int> scores, Gender gender) {
  final result = <Attribute, double>{};

  for (final attr in Attribute.values) {
    double sum = 0;
    for (final mw in _baseWeights[attr]!) {
      final s = scores[mw.metricId] ?? 0;
      final w = _getWeight(attr, mw.metricId, gender);
      if (mw.useProximity) {
        sum += w * _proximity(s) * s;
      } else {
        sum += w * mw.polarity * s;
      }
    }
    result[attr] = sum;
  }

  return result;
}

/// Continuous version — uses double scores directly without quantization.
/// This preserves the natural variation in z-scores and prevents the
/// "everyone converges to the middle" problem.
Map<Attribute, double> computeBaseScoresContinuous(
    Map<String, double> scores, Gender gender) {
  final result = <Attribute, double>{};

  for (final attr in Attribute.values) {
    double sum = 0;
    for (final mw in _baseWeights[attr]!) {
      final s = scores[mw.metricId] ?? 0.0;
      final w = _getWeight(attr, mw.metricId, gender);
      if (mw.useProximity) {
        sum += w * _proximityCont(s) * s;
      } else {
        sum += w * mw.polarity * s;
      }
    }
    result[attr] = sum;
  }

  return result;
}

// ─── Common Interaction Rules (50) ───

final _commonRules = <_InteractionRule>[
  // Wealth (5)
  _InteractionRule('W-R5', (s) => s['mouthWidthRatio']! >= 1 && s['nasalWidthRatio']! >= 1,
      {Attribute.wealth: 1.0}),

  // Leadership (5)
  _InteractionRule('L-R1', (s) => s['gonialAngle']! >= 1 && s['eyeCanthalTilt']! >= 1,
      {Attribute.leadership: 3.0}),
  _InteractionRule('L-R2', (s) => s['gonialAngle']! >= 1 && s['eyebrowThickness']! >= 1,
      {Attribute.leadership: 2.0}),
  _InteractionRule('L-R3', (s) => s['browEyeDistance']! >= 1 && s['gonialAngle']! >= 0,
      {Attribute.leadership: 1.5}),
  _InteractionRule('L-R4', (s) => s['eyeCanthalTilt']! <= -1 && s['gonialAngle']! <= -1,
      {Attribute.leadership: -2.0}),
  _InteractionRule('L-R5', (s) => s['faceTaperRatio']! <= -1 && s['eyeCanthalTilt']! >= 1,
      {Attribute.leadership: 1.5}),

  // Intelligence (5)
  _InteractionRule('I-R1', (s) => s['eyeFissureRatio']! >= 1 && s['browEyeDistance']! >= 1,
      {Attribute.intelligence: 3.0}),
  _InteractionRule('I-R2', (s) => s['intercanthalRatio']! <= -1 && s['eyeFissureRatio']! >= 1,
      {Attribute.intelligence: 2.0}),
  _InteractionRule('I-R4', (s) => s['eyeFissureRatio']! <= -1 && s['browEyeDistance']! <= -1,
      {Attribute.intelligence: -1.5}),
  _InteractionRule('I-R5', (s) => s['faceAspectRatio']! >= 1 && s['browEyeDistance']! >= 1,
      {Attribute.intelligence: 1.0}),

  // Sociability (5)
  _InteractionRule('S-R1', (s) => s['mouthWidthRatio']! >= 1 && s['mouthCornerAngle']! >= 1,
      {Attribute.sociability: 3.0}),
  _InteractionRule('S-R2', (s) => s['mouthCornerAngle']! >= 1 && s['lipFullnessRatio']! >= 1,
      {Attribute.sociability: 2.0}),
  _InteractionRule('S-R3', (s) => s['intercanthalRatio']! >= 1 && s['mouthWidthRatio']! >= 1,
      {Attribute.sociability: 1.5}),
  _InteractionRule('S-R4', (s) => s['mouthCornerAngle']! <= -1 && s['mouthWidthRatio']! <= -1,
      {Attribute.sociability: -2.0}),
  _InteractionRule('S-R5', (s) => s['mouthCornerAngle']! >= 1 && s['eyeFissureRatio']! >= 1,
      {Attribute.sociability: 1.0}),

  // Emotionality (5)
  _InteractionRule('E-R1', (s) => s['lipFullnessRatio']! >= 1 && s['eyebrowThickness']! <= -1,
      {Attribute.emotionality: 3.0}),
  _InteractionRule('E-R2', (s) => s['lipFullnessRatio']! >= 1 && s['mouthCornerAngle']! >= 1,
      {Attribute.emotionality: 2.0}),
  _InteractionRule('E-R3', (s) => s['browEyeDistance']! <= -1 && s['lipFullnessRatio']! >= 1,
      {Attribute.emotionality: 2.0}),
  _InteractionRule('E-R4', (s) => s['eyebrowThickness']! >= 2 && s['browEyeDistance']! >= 1,
      {Attribute.emotionality: -2.0}),
  _InteractionRule('E-R5', (s) => s['philtrumLength']! >= 1 && s['lipFullnessRatio']! >= 0,
      {Attribute.emotionality: 1.0}),

  // Stability (5) — magnitudes reduced to balance with other attributes
  _InteractionRule('ST-R2', (s) => s['eyebrowThickness']! >= 1 && s['gonialAngle']! >= 1,
      {Attribute.stability: 1.0}),
  _InteractionRule('ST-R3', (s) => s['faceAspectRatio']!.abs() <= 1 && s['faceTaperRatio']!.abs() <= 1,
      {Attribute.stability: 0.5}),
  _InteractionRule('ST-R4', (s) => s['eyeCanthalTilt']! <= -1 && s['mouthCornerAngle']! <= -1,
      {Attribute.stability: -2.0}),

  // Sensuality (5)
  _InteractionRule('SN-R1', (s) => s['eyeCanthalTilt']! >= 1 && s['lipFullnessRatio']! >= 1,
      {Attribute.sensuality: 3.0}),
  _InteractionRule('SN-R2', (s) => s['eyeCanthalTilt']! >= 1 && s['eyeFissureRatio']! >= 1,
      {Attribute.sensuality: 2.0}),
  _InteractionRule('SN-R3', (s) => s['mouthCornerAngle']! >= 1 && s['lipFullnessRatio']! >= 1,
      {Attribute.sensuality: 2.0}),
  _InteractionRule('SN-R4', (s) => s['philtrumLength']! <= -1 && s['lipFullnessRatio']! >= 1,
      {Attribute.sensuality: 2.0}),
  _InteractionRule('SN-R5', (s) => s['eyeCanthalTilt']! <= -1 && s['lipFullnessRatio']! <= -1,
      {Attribute.sensuality: -2.0}),

  // Trustworthiness (5)
  _InteractionRule('T-R2', (s) => s['browEyeDistance']! >= 1 && s['eyebrowThickness']! >= 1,
      {Attribute.trustworthiness: 2.0}),
  _InteractionRule('T-R4', (s) => s['intercanthalRatio']! >= 2 && s['browEyeDistance']! <= -1,
      {Attribute.trustworthiness: -2.0}),

  // Attractiveness (5)
  _InteractionRule('AT-R1',
      (s) => s['mouthCornerAngle']! >= 1 && s['eyeCanthalTilt']! >= 1 && s['lipFullnessRatio']! >= 0,
      {Attribute.attractiveness: 3.0}),
  _InteractionRule('AT-R2', (s) => s['faceAspectRatio']!.abs() <= 1 && s['faceTaperRatio']! <= 0,
      {Attribute.attractiveness: 2.0}),
  _InteractionRule('AT-R3', (s) => s['eyeFissureRatio']! >= 1 && s['eyeCanthalTilt']! >= 0,
      {Attribute.attractiveness: 1.5}),
  _InteractionRule('AT-R4', (s) => s['mouthCornerAngle']! <= -1 && s['eyeCanthalTilt']! <= -1,
      {Attribute.attractiveness: -2.0}),

  // Libido (5)
  _InteractionRule('LB-R1', (s) => s['philtrumLength']! <= -1 && s['lipFullnessRatio']! >= 1,
      {Attribute.libido: 3.0}),
  _InteractionRule('LB-R3', (s) => s['philtrumLength']! <= -1 && s['nasalWidthRatio']! >= 1,
      {Attribute.libido: 2.0}),
  _InteractionRule('LB-R4', (s) => s['philtrumLength']! >= 2 && s['lipFullnessRatio']! <= -1,
      {Attribute.libido: -2.0}),
  _InteractionRule('LB-R5', (s) => s['eyeCanthalTilt']! >= 1 && s['lipFullnessRatio']! >= 1,
      {Attribute.libido: 1.5}),
];

// ─── Gender Rules (10) ───

final _genderRules = <_GenderRule>[
  // Male (5)
  _GenderRule('GM-R1', Gender.male,
      (s) => s['gonialAngle']! >= 2 && s['eyebrowThickness']! >= 1,
      {Attribute.leadership: 2.0, Attribute.attractiveness: 1.0}),
  _GenderRule('GM-R2', Gender.male,
      (s) => s['nasalWidthRatio']! >= 1 && s['gonialAngle']! >= 1,
      {Attribute.wealth: 1.5}),
  _GenderRule('GM-R3', Gender.male,
      (s) => s['philtrumLength']! <= -1 && s['nasalWidthRatio']! >= 1,
      {Attribute.libido: 2.0}),
  _GenderRule('GM-R4', Gender.male,
      (s) => s['lipFullnessRatio']! >= 2,
      {Attribute.sensuality: 2.0, Attribute.emotionality: 1.0}),
  _GenderRule('GM-R5', Gender.male,
      (s) => s['eyeCanthalTilt']! <= -1 && s['browEyeDistance']! >= 1,
      {Attribute.trustworthiness: 1.5}),

  // Female (5)
  _GenderRule('GF-R1', Gender.female,
      (s) => s['eyeCanthalTilt']! >= 1 && s['lipFullnessRatio']! >= 1,
      {Attribute.sensuality: 2.0, Attribute.attractiveness: 1.5}),
  _GenderRule('GF-R2', Gender.female,
      (s) => s['faceTaperRatio']! <= -1 && s['lipFullnessRatio']! >= 1,
      {Attribute.attractiveness: 2.0}),
  _GenderRule('GF-R3', Gender.female,
      (s) => s['philtrumLength']! <= -1 && s['lipFullnessRatio']! >= 0,
      {Attribute.libido: 1.5, Attribute.sensuality: 1.0}),
  _GenderRule('GF-R4', Gender.female,
      (s) => s['eyebrowThickness']! >= 1 && s['gonialAngle']! >= 1,
      {Attribute.leadership: 2.5}),
  _GenderRule('GF-R5', Gender.female,
      (s) => s['mouthCornerAngle']! >= 1 && s['eyeFissureRatio']! >= 1,
      {Attribute.sociability: 2.0, Attribute.attractiveness: 1.0}),
];

// ─── Age Rules (5, over50 only) ───

final _ageRules = <_AgeRule>[
  _AgeRule('AG-R1', (s, sAdj) => sAdj['mouthCornerAngle']! >= 1,
      {Attribute.stability: 2.0, Attribute.attractiveness: 1.5}),
  _AgeRule('AG-R2', (s, sAdj) => sAdj['browEyeDistance']! >= 1 && sAdj['lipFullnessRatio']! >= 0,
      {Attribute.attractiveness: 1.5}),
  _AgeRule('AG-R3', (s, sAdj) => sAdj['philtrumLength']! <= -1,
      {Attribute.libido: 1.5, Attribute.sensuality: 1.0}),
  _AgeRule('AG-R4', (s, sAdj) => sAdj['lipFullnessRatio']! >= 1,
      {Attribute.emotionality: 1.5, Attribute.sensuality: 1.0}),
  _AgeRule('AG-R5', (s, sAdj) => sAdj['mouthCornerAngle']! <= -1 && sAdj['browEyeDistance']! <= -1,
      {Attribute.stability: -1.5}),
];

// ─── Rule Evaluation ───

List<TriggeredRule> evaluateRules({
  required Map<String, int> scores,
  required Map<String, int> adjustedScores,
  required Gender gender,
  required bool isOver50,
}) {
  final triggered = <TriggeredRule>[];

  // Common rules
  for (final rule in _commonRules) {
    if (rule.condition(scores)) {
      triggered.add(TriggeredRule(rule.id, rule.effects));
    }
  }

  // Gender rules
  for (final rule in _genderRules) {
    if (rule.gender == gender && rule.condition(scores)) {
      triggered.add(TriggeredRule(rule.id, rule.effects));
    }
  }

  // Age rules (over50 only, using adjusted scores)
  if (isOver50) {
    for (final rule in _ageRules) {
      if (rule.condition(scores, adjustedScores)) {
        triggered.add(TriggeredRule(rule.id, rule.effects));
      }
    }
  }

  return triggered;
}

// ─── Score Normalization (§8 v9) — Rank-Aware Per-Face Mapping ───
//
// Why this exists:
//   v8 (pure quantile mapping) used INDEPENDENT Monte Carlo calibration, but
//   real face metrics are STRONGLY CORRELATED. 한 얼굴이 굵은 눈썹 + 강한 턱선 +
//   깊은 눈을 가지면 stability/trustworthiness/leadership 세 attribute가
//   모두 동일한 메트릭(browEyeDistance, eyebrowThickness, gonialAngle)을
//   공유하기 때문에 한꺼번에 saturate. 결과: 모든 사용자의 top 3가 항상 동일.
//
// v9 strategy:
//   1. global percentile per attribute (calibration CDF에서 raw → 0~1)
//      — 절대적 수준 보존 (cross-user comparability)
//   2. within-face rank (각 얼굴 안에서 10개 attribute를 점수순 정렬)
//      — 상관관계와 무관하게 항상 5~10 spread를 강제
//   3. blend (60% rank + 40% global) → 5~10 매핑
//
// Guarantees:
//   - 모든 얼굴은 항상 최소 3.0 score points 이상의 within-face spread
//   - 한 얼굴의 가장 강한 attribute는 항상 8.0 이상
//   - 한 얼굴의 가장 약한 attribute는 항상 7.0 이하
//   - 두 얼굴이 같은 attribute에서 강해도 절대적 수준은 다르게 나옴
//   - "모든 사람의 top 3가 똑같은 saturate" 문제가 수학적으로 불가능
//
// Re-run calibration via: flutter test test/calibration_test.dart

const _attrQuantilesMale = <Attribute, List<double>>{
  Attribute.wealth: [-1.920, -0.621, -0.446, -0.315, -0.220, -0.132, -0.057, 0.011, 0.082, 0.148, 0.218, 0.289, 0.369, 0.465, 0.593, 0.821, 1.504, 1.839, 2.138, 2.829, 4.875],
  Attribute.leadership: [-3.673, -0.646, -0.331, -0.198, -0.092, -0.000, 0.089, 0.185, 0.301, 0.472, 1.298, 1.553, 1.718, 1.861, 2.030, 2.283, 3.205, 3.973, 5.047, 6.278, 11.389],
  Attribute.intelligence: [-3.210, -1.775, -0.515, -0.348, -0.247, -0.168, -0.097, -0.030, 0.037, 0.102, 0.176, 0.253, 0.348, 0.479, 0.852, 1.320, 1.986, 3.173, 3.623, 4.774, 7.868],
  Attribute.sociability: [-3.445, -0.704, -0.365, -0.235, -0.146, -0.071, -0.006, 0.060, 0.128, 0.193, 0.268, 0.353, 0.469, 0.783, 1.500, 1.941, 2.297, 3.245, 3.897, 5.699, 9.207],
  Attribute.emotionality: [-3.324, -1.309, -0.586, -0.415, -0.305, -0.215, -0.134, -0.057, 0.026, 0.121, 0.249, 0.608, 1.002, 1.168, 1.346, 1.925, 2.583, 3.452, 4.502, 5.721, 10.451],
  Attribute.stability: [-3.045, -0.638, -0.296, -0.134, -0.018, 0.086, 0.176, 0.255, 0.331, 0.405, 0.483, 0.564, 0.647, 0.737, 0.836, 0.958, 1.111, 1.358, 1.685, 2.036, 3.322],
  Attribute.sensuality: [-3.299, -0.679, -0.400, -0.275, -0.182, -0.106, -0.034, 0.035, 0.102, 0.180, 0.268, 0.387, 0.621, 2.001, 2.228, 2.440, 2.853, 4.323, 5.394, 7.486, 12.556],
  Attribute.trustworthiness: [-3.338, -1.165, -0.502, -0.343, -0.231, -0.138, -0.062, 0.007, 0.074, 0.143, 0.217, 0.295, 0.380, 0.480, 0.631, 1.301, 2.119, 2.439, 2.697, 3.115, 5.167],
  Attribute.attractiveness: [-2.972, -0.321, -0.108, 0.031, 0.148, 0.266, 0.399, 0.792, 1.618, 1.764, 1.865, 1.955, 2.042, 2.132, 2.245, 2.446, 3.433, 3.703, 3.958, 5.286, 8.280],
  Attribute.libido: [-3.383, -0.730, -0.461, -0.328, -0.237, -0.164, -0.096, -0.031, 0.030, 0.094, 0.154, 0.222, 0.288, 0.375, 0.490, 0.690, 1.530, 1.967, 3.480, 4.759, 10.099],
};

const _attrQuantilesFemale = <Attribute, List<double>>{
  Attribute.wealth: [-1.841, -0.560, -0.390, -0.279, -0.188, -0.110, -0.042, 0.023, 0.087, 0.150, 0.208, 0.266, 0.331, 0.402, 0.480, 0.571, 0.698, 0.965, 1.570, 1.859, 3.265],
  Attribute.leadership: [-3.719, -0.611, -0.312, -0.171, -0.071, 0.023, 0.121, 0.222, 0.340, 0.538, 1.299, 1.540, 1.701, 1.859, 2.056, 3.238, 4.533, 5.027, 6.330, 8.147, 12.064],
  Attribute.intelligence: [-3.210, -1.775, -0.515, -0.348, -0.247, -0.168, -0.097, -0.030, 0.037, 0.102, 0.176, 0.253, 0.348, 0.479, 0.852, 1.320, 1.986, 3.173, 3.623, 4.774, 7.868],
  Attribute.sociability: [-3.445, -0.704, -0.365, -0.235, -0.146, -0.071, -0.006, 0.060, 0.128, 0.193, 0.268, 0.353, 0.469, 0.816, 1.961, 2.320, 3.088, 3.534, 5.400, 6.579, 11.207],
  Attribute.emotionality: [-3.324, -1.875, -0.600, -0.422, -0.311, -0.221, -0.143, -0.069, 0.009, 0.093, 0.191, 0.347, 0.835, 1.100, 1.284, 1.535, 2.256, 3.210, 3.825, 5.450, 9.451],
  Attribute.stability: [-3.045, -0.638, -0.296, -0.134, -0.018, 0.086, 0.176, 0.255, 0.331, 0.405, 0.483, 0.564, 0.647, 0.737, 0.836, 0.958, 1.111, 1.358, 1.685, 2.036, 3.322],
  Attribute.sensuality: [-3.293, -0.696, -0.408, -0.284, -0.191, -0.112, -0.040, 0.030, 0.098, 0.173, 0.260, 0.386, 0.787, 1.363, 2.121, 2.393, 2.786, 3.995, 5.709, 7.778, 13.601],
  Attribute.trustworthiness: [-3.338, -1.165, -0.502, -0.344, -0.235, -0.144, -0.071, -0.004, 0.059, 0.125, 0.189, 0.259, 0.333, 0.416, 0.512, 0.658, 1.872, 2.374, 2.584, 2.807, 3.879],
  Attribute.attractiveness: [-3.090, -0.303, -0.049, 0.114, 0.253, 0.408, 0.702, 1.567, 1.738, 1.851, 1.960, 2.062, 2.191, 2.437, 3.231, 3.560, 3.798, 4.330, 5.299, 6.545, 11.944],
  Attribute.libido: [-3.413, -0.703, -0.448, -0.323, -0.236, -0.163, -0.095, -0.029, 0.035, 0.094, 0.162, 0.235, 0.323, 0.445, 0.661, 1.565, 1.826, 2.062, 3.754, 5.195, 9.475],
};

/// Computes raw → empirical percentile (0..1) using calibration CDF.
/// Used as one component of the blended normalization.
double _rawToPercentile(double raw, Attribute attr, Gender gender) {
  final q = gender == Gender.male
      ? _attrQuantilesMale[attr]!
      : _attrQuantilesFemale[attr]!;
  if (raw <= q[0]) return 0.0;
  if (raw >= q[20]) return 1.0;
  for (int i = 0; i < 20; i++) {
    final lo = q[i];
    final hi = q[i + 1];
    if (raw <= hi) {
      final span = hi - lo;
      final t = span > 0 ? (raw - lo) / span : 0.0;
      return (i + t) / 20.0;
    }
  }
  return 1.0;
}

/// Blend ratio for normalize: 60% within-face rank, 40% global percentile.
/// Higher rank weight → larger guaranteed within-face spread.
const double _rankWeight = 0.60;
const double _globalWeight = 0.40;

/// Normalizes all 10 attribute raw scores at once into 5~10 with per-face
/// rank-aware spread. See §8 v9 header above for rationale.
Map<Attribute, double> normalizeAllScores(
    Map<Attribute, double> rawScores, Gender gender) {
  // 1. Global percentile per attribute (calibration CDF → 0..1)
  final globalPct = <Attribute, double>{};
  for (final entry in rawScores.entries) {
    globalPct[entry.key] = _rawToPercentile(entry.value, entry.key, gender);
  }

  // 2. Within-face rank by GLOBAL PERCENTILE (so all attributes are on the
  //    same 0..1 scale — ranking by raw would unfairly favor attributes whose
  //    raw scores have larger natural spreads like leadership).
  //    0 = strongest (highest percentile), n-1 = weakest.
  final sorted = globalPct.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final ranks = <Attribute, int>{};
  for (int i = 0; i < sorted.length; i++) {
    ranks[sorted[i].key] = i;
  }
  final n = sorted.length;
  final denom = (n - 1).toDouble();

  // 3. Blend rank (within-face spread) and global percentile (cross-user)
  final result = <Attribute, double>{};
  for (final attr in Attribute.values) {
    final rankPct = (denom - ranks[attr]!) / denom; // 0..1
    final gPct = globalPct[attr]!;
    final blended = _rankWeight * rankPct + _globalWeight * gPct;
    final score = 5.0 + blended * 5.0; // 5..10
    result[attr] = (score * 10).round() / 10.0;
  }
  return result;
}

/// Legacy single-attribute normalization, kept for callers that don't have
/// the full 10-attribute map (e.g. compat engine partial flows). Uses pure
/// global percentile mapping (no rank component since rank requires the full
/// set). Prefer [normalizeAllScores] for primary face analysis.
double normalizeScore(double raw, Attribute attr, Gender gender) {
  final pct = _rawToPercentile(raw, attr, gender);
  final score = 5.0 + pct * 5.0;
  return (score * 10).round() / 10.0;
}
