import 'dart:math';
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

  // Stability (5)
  _InteractionRule('ST-R2', (s) => s['eyebrowThickness']! >= 1 && s['gonialAngle']! >= 1,
      {Attribute.stability: 2.0}),
  _InteractionRule('ST-R3', (s) => s['faceAspectRatio']!.abs() <= 1 && s['faceTaperRatio']!.abs() <= 1,
      {Attribute.stability: 1.5}),
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

// ─── Score Normalization (§8) ───

/// sigmoid: 10 / (1 + exp(-0.5 * raw))
double normalizeScore(double raw) {
  final normalized = 10.0 / (1.0 + exp(-0.5 * raw));
  return (normalized * 10).round() / 10.0; // 소수 첫째자리
}
