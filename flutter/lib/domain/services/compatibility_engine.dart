import 'dart:math';

import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/compatibility_result.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';

import 'package:face_reader/data/constants/compatibility_text_blocks.dart'
    as text_blocks;

// ═══════════════════════════════════════════════════════════════
//  Synergy scores when both ≥ 7.0
// ═══════════════════════════════════════════════════════════════

const _synergyScores = <Attribute, double>{
  Attribute.wealth: 78,
  Attribute.leadership: 30,       // 주도권 경쟁 — 낮아야 맞음
  Attribute.intelligence: 82,
  Attribute.sociability: 88,
  Attribute.emotionality: 45,     // 감정 폭발 가능 — 낮음
  Attribute.stability: 92,
  Attribute.sensuality: 80,
  Attribute.trustworthiness: 95,
  Attribute.attractiveness: 75,
  Attribute.libido: 55,           // 열정 과잉 피로 — 중간
};

// ═══════════════════════════════════════════════════════════════
//  10×10 Archetype Compatibility Matrix
//  Indexed by Attribute enum index (wealth=0 .. libido=9).
//  Order: wealth, leadership, intelligence, sociability, emotionality,
//         stability, sensuality, trustworthiness, attractiveness, libido
// ═══════════════════════════════════════════════════════════════

const _archetypeMatrix = <List<int>>[
  //        wea  lea  int  soc  emo  sta  sen  tru  att  lib
  /* wea */ [42, 72, 85, 55, 35, 80, 48, 75, 50, 40],
  /* lea */ [72, 25, 90, 55, 38, 82, 40, 75, 48, 35],
  /* int */ [85, 90, 50, 60, 82, 88, 45, 72, 55, 42],
  /* soc */ [55, 55, 60, 45, 68, 72, 70, 85, 70, 50],
  /* emo */ [35, 38, 82, 68, 40, 55, 78, 52, 72, 65],
  /* sta */ [80, 82, 88, 72, 55, 62, 45, 88, 55, 40],
  /* sen */ [48, 40, 45, 70, 78, 45, 52, 42, 80, 75],
  /* tru */ [75, 75, 72, 85, 52, 88, 42, 55, 58, 40],
  /* att */ [50, 48, 55, 70, 72, 55, 80, 58, 42, 78],
  /* lib */ [40, 35, 42, 50, 65, 40, 75, 40, 78, 32],
];

// ═══════════════════════════════════════════════════════════════
//  Cross-Attribute Pairs (Step 2)
// ═══════════════════════════════════════════════════════════════

enum _CrossPairType { synergistic, tension, complementary }

class _CrossPairDef {
  final Attribute attrA;
  final Attribute attrB;
  final double weight;
  final String key;
  final _CrossPairType type;

  const _CrossPairDef(this.attrA, this.attrB, this.weight, this.key, this.type);
}

const _crossPairs = <_CrossPairDef>[
  // Synergistic pairs
  _CrossPairDef(Attribute.leadership, Attribute.stability, 2.0,
      'leadership_stability', _CrossPairType.synergistic),
  _CrossPairDef(Attribute.intelligence, Attribute.stability, 1.5,
      'intelligence_stability', _CrossPairType.synergistic),
  _CrossPairDef(Attribute.wealth, Attribute.stability, 1.5,
      'wealth_stability', _CrossPairType.synergistic),
  _CrossPairDef(Attribute.leadership, Attribute.intelligence, 1.5,
      'leadership_intelligence', _CrossPairType.synergistic),
  _CrossPairDef(Attribute.wealth, Attribute.leadership, 1.5,
      'wealth_leadership', _CrossPairType.synergistic),
  _CrossPairDef(Attribute.stability, Attribute.emotionality, 2.0,
      'stability_emotionality', _CrossPairType.synergistic),

  // Complementary pairs
  _CrossPairDef(Attribute.emotionality, Attribute.trustworthiness, 1.5,
      'emotionality_trustworthiness', _CrossPairType.complementary),
  _CrossPairDef(Attribute.sociability, Attribute.trustworthiness, 1.5,
      'sociability_trustworthiness', _CrossPairType.complementary),
  _CrossPairDef(Attribute.intelligence, Attribute.emotionality, 2.0,
      'intelligence_emotionality', _CrossPairType.complementary),
  _CrossPairDef(Attribute.sociability, Attribute.emotionality, 1.0,
      'sociability_emotionality', _CrossPairType.complementary),

  // Tension pairs
  _CrossPairDef(Attribute.libido, Attribute.emotionality, 1.5,
      'libido_emotionality', _CrossPairType.tension),
  _CrossPairDef(Attribute.sensuality, Attribute.trustworthiness, 1.0,
      'sensuality_trustworthiness', _CrossPairType.tension),
  _CrossPairDef(Attribute.attractiveness, Attribute.emotionality, 1.0,
      'attractiveness_emotionality', _CrossPairType.tension),
  _CrossPairDef(Attribute.leadership, Attribute.emotionality, 1.5,
      'leadership_emotionality', _CrossPairType.tension),
  _CrossPairDef(Attribute.sensuality, Attribute.stability, 1.0,
      'sensuality_stability', _CrossPairType.tension),
];

// Score mapping per CrossPairType × threshold pattern
//                       highHigh, highLow, lowHigh, lowLow
const _synergisticScores = (highHigh: 92.0, highLow: 35.0, lowHigh: 65.0, lowLow: 15.0);
const _tensionScores     = (highHigh: 38.0, highLow: 22.0, lowHigh: 58.0, lowLow: 45.0);
const _complementScores  = (highHigh: 82.0, highLow: 30.0, lowHigh: 70.0, lowLow: 12.0);

// ═══════════════════════════════════════════════════════════════
//  Triggered Rule Pairs (Step 5)
// ═══════════════════════════════════════════════════════════════

class _RulePairDef {
  final String effect;
  final double delta;
  final String comment;
  const _RulePairDef(this.effect, this.delta, this.comment);
}

const _rulePairs = <(String, String), _RulePairDef>{
  ('L-R1', 'ST-R2'): _RulePairDef('synergy', 15, '강한 주도력을 가진 사람 곁에 흔들리지 않는 버팀목이 있습니다. 밀어붙이는 힘과 받쳐주는 힘이 맞물려, 현실에서 놀라운 추진력을 발휘하는 조합입니다.'),
  ('L-R1', 'E-R1'): _RulePairDef('clash', -14, '불같은 주도력과 깊은 감정이 정면으로 부딪힙니다. 한쪽은 밀어붙이려 하고 다른 쪽은 감정을 알아달라 하니, 소통 방식이 근본적으로 어긋날 수 있습니다.'),
  ('E-R1', 'T-R2'): _RulePairDef('synergy', 14, '넘치는 감정을 묵묵히 받아주는 신뢰의 그릇이 있는 관계입니다. 감정적으로 흔들려도 상대의 한결같음이 닻 역할을 합니다.'),
  ('S-R1', 'T-R2'): _RulePairDef('synergy', 13, '넓은 인맥과 깊은 신뢰가 만나면 사회적으로나 개인적으로나 단단한 관계가 됩니다. 밖에서 쌓은 신뢰를 안에서도 지킬 줄 아는 조합입니다.'),
  ('SN-R1', 'ST-R2'): _RulePairDef('clash', -12, '강렬한 매혹과 안정을 추구하는 기질은 본질적으로 충돌합니다. 한쪽은 자극을 원하고 다른 쪽은 평온을 원하니, 함께 있어도 서로 다른 곳을 바라볼 수 있습니다.'),
  ('I-R1', 'E-R2'): _RulePairDef('synergy', 12, '날카로운 지성과 풍부한 감정 표현이 만나면 대화의 깊이가 차원이 다릅니다. 머리와 가슴으로 동시에 소통하는 희귀한 관계입니다.'),
  ('L-R2', 'L-R2'): _RulePairDef('clash', -18, '두 호랑이가 한 산에서 만났습니다. 주도권 경쟁이 불가피하며, 양보를 모르는 두 기질이 부딪히면 관계의 기반 자체가 흔들릴 수 있습니다.'),
  ('W-R5', 'ST-R2'): _RulePairDef('synergy', 12, '돈을 벌 줄 아는 감각과 지킬 줄 아는 안정성이 만났습니다. 경제적 파트너십으로서 이상적인 조합이며, 함께 쌓는 기반이 탄탄합니다.'),
  ('E-R1', 'E-R3'): _RulePairDef('volatile', -10, '두 사람 모두 감정의 진폭이 깊어, 행복할 때는 세상을 다 가진 듯하지만 갈등이 시작되면 걷잡을 수 없이 커집니다. 감정의 롤러코스터를 각오해야 합니다.'),
  ('AT-R1', 'SN-R1'): _RulePairDef('amplify', 11, '매력과 관능이 서로를 끌어올려 강렬한 끌림을 만듭니다. 첫 만남부터 불꽃이 튀는 조합이지만, 이 끌림이 식었을 때 남는 것이 무엇인지 생각해볼 필요가 있습니다.'),
  ('LB-R1', 'E-R2'): _RulePairDef('amplify', 10, '뜨거운 정열과 진한 감정 표현이 만나 관계의 온도가 급상승합니다. 열정적이고 드라마틱한 관계를 원한다면 최적의 조합입니다.'),
  ('I-R1', 'I-R2'): _RulePairDef('amplify', 11, '두 사람의 지적 호기심이 무한히 서로를 자극합니다. 밤새 토론하고도 지치지 않는 관계이며, 지적 성장의 최고의 파트너입니다.'),
  ('T-R2', 'T-R2'): _RulePairDef('amplify', 16, '두 사람 모두 신뢰의 깊이가 남다릅니다. 말하지 않아도 서로를 믿을 수 있는 관계이며, 시간이 지날수록 이 신뢰는 다이아몬드처럼 단단해집니다.'),
  ('S-R4', 'E-R4'): _RulePairDef('clash', -14, '소통이 닫히고 감정도 닫힌 상태가 겹쳤습니다. 서로에게 무관심한 것이 아니라 표현할 줄 모르는 것인데, 이 침묵이 오해를 낳고 관계를 서서히 냉각시킵니다.'),
  ('L-R4', 'ST-R4'): _RulePairDef('volatile', -15, '방향을 잡아줄 리더십도, 받쳐줄 안정성도 부족한 조합입니다. 관계가 표류하기 쉬우며, 누군가 먼저 닻을 내리지 않으면 어디로 흘러갈지 모릅니다.'),
  ('GM-R1', 'GF-R1'): _RulePairDef('synergy', 13, '남성의 강인한 턱선에서 오는 권위와 여성의 매혹적인 눈매가 서로를 자연스럽게 끌어당깁니다. 전통적 의미에서 가장 조화로운 궁합 중 하나입니다.'),
  ('GM-R3', 'GF-R3'): _RulePairDef('amplify', 11, '서로의 정열이 거울처럼 공명합니다. 함께 있으면 에너지가 배가되지만, 이 강렬함이 질투나 소유욕으로 변질되지 않도록 주의가 필요합니다.'),
  ('GM-R2', 'ST-R2'): _RulePairDef('synergy', 11, '사업적 직감과 현실적 안정성이 만나 경제적으로 든든한 동반자 관계를 형성합니다. 돈 문제로 싸울 일이 적은 조합입니다.'),
  ('GF-R4', 'L-R1'): _RulePairDef('synergy', 12, '여성의 당당한 리더십이 상대의 주도력과 시너지를 냅니다. 서로 동등한 위치에서 이끌어가는 현대적 파트너십의 표본입니다.'),
  ('GF-R2', 'AT-R1'): _RulePairDef('amplify', 10, '외적 매력이 서로의 끌림을 강하게 증폭시킵니다. 눈에 보이는 아름다움이 관계의 초기 동력이 되지만, 내면의 연결 없이는 오래가기 어렵습니다.'),
  ('W-R5', 'W-R5'): _RulePairDef('amplify', 12, '두 사람 모두 재물을 다루는 감각이 탁월합니다. 함께 투자하거나 사업하면 시너지가 폭발하지만, 돈을 둘러싼 주도권 경쟁이 독이 될 수도 있습니다.'),
  ('LB-R4', 'E-R4'): _RulePairDef('clash', -12, '정열도 식고 감정 표현도 닫힌 관계입니다. 겉으로는 평화로워 보이지만 속은 건조하며, 이 건조함이 어느 날 갑자기 균열로 나타날 수 있습니다.'),
  ('S-R1', 'AT-R3'): _RulePairDef('synergy', 10, '활발한 사교성과 빛나는 매력이 만나 사람들 사이에서 주목받는 커플이 됩니다. 함께 있으면 분위기가 화사해지는 조합입니다.'),
  ('I-R4', 'S-R4'): _RulePairDef('volatile', -13, '지적 무딤과 소통 부재가 겹쳐 서로를 이해하는 통로 자체가 막혀 있습니다. 가장 기본적인 대화조차 어긋나기 쉬운 조합입니다.'),
  ('ST-R2', 'ST-R2'): _RulePairDef('amplify', 15, '두 사람 모두 바위처럼 흔들리지 않는 안정성을 지녔습니다. 외부의 어떤 풍파에도 함께라면 끄떡없는 관계이며, 시간이 이 조합의 가장 강력한 동맹입니다.'),
};

// ═══════════════════════════════════════════════════════════════
//  Personality / Emotion / Practical attribute groupings
// ═══════════════════════════════════════════════════════════════

const _personalityPairKeys = {
  'leadership_stability', 'leadership_intelligence', 'leadership_emotionality',
  'sociability_trustworthiness', 'sociability_emotionality',
};

const _emotionPairKeys = {
  'emotionality_trustworthiness', 'intelligence_emotionality',
  'libido_emotionality', 'sensuality_trustworthiness',
  'attractiveness_emotionality', 'sensuality_stability',
};

const _practicalPairKeys = {
  'wealth_stability', 'wealth_leadership', 'intelligence_stability',
  'stability_emotionality',
};

// ═══════════════════════════════════════════════════════════════
//  Internal helper types
// ═══════════════════════════════════════════════════════════════

class _SpecialResult {
  final double score;
  final String? note;
  const _SpecialResult(this.score, this.note);
}

class _SpecialEffect {
  final double delta;
  final String? note;
  const _SpecialEffect(this.delta, this.note);
}

class _RulePairResult {
  final String ruleA;
  final String ruleB;
  final String effect;
  final double delta;
  final String comment;
  const _RulePairResult(this.ruleA, this.ruleB, this.effect, this.delta, this.comment);
}

class _CrossPairResult {
  final String key;
  final String pattern; // highHigh, highLow, lowHigh, lowLow
  final double score;
  final double weight;
  const _CrossPairResult(this.key, this.pattern, this.score, this.weight);
}

// ═══════════════════════════════════════════════════════════════
//  Main entry point
// ═══════════════════════════════════════════════════════════════

CompatibilityResult evaluateCompatibility(
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
) {
  final categoryScores = <String, double>{};

  // Step 1: Attribute Harmony (30%)
  final attrPatterns = <String, String>{}; // attrName → pattern
  final attrScores = _evaluateAttributeHarmony(
    myReport.attributeScores,
    albumReport.attributeScores,
    categoryScores,
    attrPatterns,
  );
  final attributeAvg = attrScores.isEmpty
      ? 50.0
      : attrScores.reduce((a, b) => a + b) / attrScores.length;

  // Step 2: Cross-Attribute Pairs (20%)
  final crossPairResults = <_CrossPairResult>[];
  final crossPairScore = _evaluateCrossPairs(
    myReport.attributeScores,
    albumReport.attributeScores,
    crossPairResults,
  );
  final crossPairKeys = crossPairResults
      .map((r) => '${r.key}_${r.pattern}')
      .toList();

  // Step 3: Archetype Compatibility (20%)
  final archetypeScore = _archetypeCompatScoreV2(
    myReport.archetype,
    albumReport.archetype,
  );

  // Step 4: Special Archetype (15%)
  final specialResult = _evaluateSpecialArchetypes(
    myReport.archetype,
    albumReport.archetype,
  );
  final specialScore = specialResult.score;
  final specialNote = specialResult.note;

  // Step 5: Triggered Rules Cross-analysis (15%)
  final rulePairResults = <_RulePairResult>[];
  final ruleScore = _evaluateTriggeredRulesV2(
    myReport.triggeredRules,
    albumReport.triggeredRules,
    rulePairResults,
  );

  // Step 6: Total Score (5-way weighted)
  final rawTotal = attributeAvg * 0.30 +
      crossPairScore * 0.20 +
      archetypeScore * 0.20 +
      specialScore * 0.15 +
      ruleScore * 0.15;

  // Spread function: push scores away from center (50)
  // This counters the averaging compression that collapses all scores to 55-65
  final deviation = rawTotal - 50;
  final total = (50 + deviation * 2.2).clamp(8.0, 97.0);

  // Step 7: Summary
  final summary = _buildSummaryV2(
    myReport,
    albumReport,
    categoryScores,
    crossPairKeys,
    rulePairResults,
    specialNote,
    total,
  );

  return CompatibilityResult(
    myFaceTimestamp: myReport.timestamp.toIso8601String(),
    albumTimestamp: albumReport.timestamp.toIso8601String(),
    evaluatedAt: DateTime.now(),
    score: total.clamp(0, 100).roundToDouble(),
    summary: summary,
    categoryScores: categoryScores,
    archetypeScore: archetypeScore,
    specialNote: specialNote,
    myArchetype: myReport.archetype.primaryLabel,
    albumArchetype: albumReport.archetype.primaryLabel,
  );
}

// ═══════════════════════════════════════════════════════════════
//  Step 1: Attribute Harmony
// ═══════════════════════════════════════════════════════════════

List<double> _evaluateAttributeHarmony(
  Map<Attribute, double> myScores,
  Map<Attribute, double> albumScores,
  Map<String, double> categoryScores,
  Map<String, String> attrPatterns,
) {
  final scores = <double>[];

  for (final attr in Attribute.values) {
    final my = myScores[attr] ?? 5.0;
    final album = albumScores[attr] ?? 5.0;
    final diff = (my - album).abs();
    final attrName = attr.name;

    double score;
    String pattern;

    if (my >= 7.0 && album >= 7.0) {
      score = _synergyScores[attr]!;
      pattern = 'synergy';
    } else if ((my >= 7.0 && album <= 3.0) || (my <= 3.0 && album >= 7.0)) {
      // Complement: high variance based on which attr is strong
      score = 55 + 30 * (min(my, album) / 10);
      pattern = 'complement';
    } else if (diff >= 5.0 || (my <= 3.0 && album <= 3.0)) {
      // Clash: genuinely low
      score = 15 + 15 * (1 - diff / 10);
      pattern = 'clash';
    } else if (my >= 4.0 && my <= 6.0 && album >= 4.0 && album <= 6.0) {
      // Neutral: spread wider around 45-65
      final avg = (my + album) / 2;
      score = 35 + avg * 5 - diff * 8;
      pattern = 'neutral';
    } else {
      // Mixed: wider range 15-85
      score = max(15, 85 - diff * 12);
      pattern = 'mixed';
    }

    score = score.clamp(0, 100);
    categoryScores[attrName] = score;
    attrPatterns[attrName] = pattern;
    scores.add(score);
  }

  return scores;
}

// ═══════════════════════════════════════════════════════════════
//  Step 2: Cross-Attribute Pairs
// ═══════════════════════════════════════════════════════════════

double _evaluateCrossPairs(
  Map<Attribute, double> myScores,
  Map<Attribute, double> albumScores,
  List<_CrossPairResult> results,
) {
  double totalWeighted = 0;
  double totalWeight = 0;

  for (final pair in _crossPairs) {
    final aScore = myScores[pair.attrA] ?? 5.0;
    final bScore = albumScores[pair.attrB] ?? 5.0;

    String pattern;
    if (aScore >= 7.0 && bScore >= 7.0) {
      pattern = 'highHigh';
    } else if (aScore >= 7.0 && bScore <= 3.5) {
      pattern = 'highLow';
    } else if (aScore <= 3.5 && bScore >= 7.0) {
      pattern = 'lowHigh';
    } else if (aScore <= 3.5 && bScore <= 3.5) {
      pattern = 'lowLow';
    } else {
      // Mid-range: interpolate with wider spread
      final midScore = 50.0 + (aScore + bScore - 10) * 3.5;
      final score = midScore.clamp(15.0, 90.0);
      results.add(_CrossPairResult(pair.key, 'mid', score, pair.weight));
      totalWeighted += score * pair.weight;
      totalWeight += pair.weight;
      continue;
    }

    final scores = switch (pair.type) {
      _CrossPairType.synergistic => _synergisticScores,
      _CrossPairType.tension => _tensionScores,
      _CrossPairType.complementary => _complementScores,
    };

    final score = switch (pattern) {
      'highHigh' => scores.highHigh,
      'highLow' => scores.highLow,
      'lowHigh' => scores.lowHigh,
      'lowLow' => scores.lowLow,
      _ => 50.0,
    };

    results.add(_CrossPairResult(pair.key, pattern, score, pair.weight));
    totalWeighted += score * pair.weight;
    totalWeight += pair.weight;
  }

  return totalWeight > 0 ? totalWeighted / totalWeight : 50.0;
}

// ═══════════════════════════════════════════════════════════════
//  Step 3: Archetype Compatibility (expanded)
// ═══════════════════════════════════════════════════════════════

double _archetypeCompatScoreV2(
  ArchetypeResult myArch,
  ArchetypeResult albumArch,
) {
  double score =
      _archetypeMatrix[myArch.primary.index][albumArch.primary.index]
          .toDouble();
  score +=
      (_archetypeMatrix[myArch.primary.index][albumArch.secondary.index] - 50) *
          0.3;
  score +=
      (_archetypeMatrix[albumArch.primary.index][myArch.secondary.index] - 50) *
          0.3;
  score +=
      (_archetypeMatrix[myArch.secondary.index][albumArch.secondary.index] -
              50) *
          0.15;
  return score.clamp(0, 100);
}

// ═══════════════════════════════════════════════════════════════
//  Step 4: Special Archetype Interaction
// ═══════════════════════════════════════════════════════════════

_SpecialResult _evaluateSpecialArchetypes(
  ArchetypeResult myArchetype,
  ArchetypeResult albumArchetype,
) {
  final mySpecial = myArchetype.specialArchetype;
  final albumSpecial = albumArchetype.specialArchetype;

  if (mySpecial == null && albumSpecial == null) {
    return const _SpecialResult(50, null);
  }

  double score = 50;
  final notes = <String>[];

  // SP×SP pair lookup
  if (mySpecial != null && albumSpecial != null) {
    final myBase = _extractSpecialBase(mySpecial);
    final albumBase = _extractSpecialBase(albumSpecial);

    // SP×SP pair text lookup
    final spText = _spPairFallbackText(myBase, albumBase);
    if (spText != null) {
      notes.add(spText);
    }
  }

  if (mySpecial != null) {
    final result = _applySpecialEffect(
      mySpecial,
      albumArchetype,
      myArchetype,
      isMySpecial: true,
    );
    score += result.delta;
    if (result.note != null) notes.add(result.note!);
  }

  if (albumSpecial != null) {
    final result = _applySpecialEffect(
      albumSpecial,
      myArchetype,
      albumArchetype,
      isMySpecial: false,
    );
    score += result.delta;
    if (result.note != null) notes.add(result.note!);
  }

  return _SpecialResult(
    score.clamp(0, 100),
    notes.isEmpty ? null : notes.join('\n'),
  );
}

_SpecialEffect _applySpecialEffect(
  String special,
  ArchetypeResult partnerArchetype,
  ArchetypeResult ownerArchetype, {
  required bool isMySpecial,
}) {
  final partnerSpecial = partnerArchetype.specialArchetype;
  final partnerPrimary = partnerArchetype.primary;
  final ownerLabel = ownerArchetype.primaryLabel;
  final partnerLabel = partnerArchetype.primaryLabel;
  final who = isMySpecial ? ownerLabel : partnerLabel;

  final baseName = _extractSpecialBase(special);

  switch (baseName) {
    case '제왕상':
      if (partnerSpecial != null) {
        final partnerBase = _extractSpecialBase(partnerSpecial);
        if (partnerBase == '제왕상' || partnerBase == '광인상') {
          return _SpecialEffect(
            -30,
            '$who의 제왕상과 상대의 $partnerBase이 정면으로 충돌합니다. 두 사람 모두 꺾이지 않는 기질이라, 주도권을 양보하지 못하면 관계는 전쟁터가 될 수 있습니다.',
          );
        }
      }
      return _SpecialEffect(25, '$who에게서 제왕상이 보입니다. 타고난 통솔력이 관계의 방향타 역할을 하며, 상대는 이 사람 곁에서 자연스럽게 안정감을 느낍니다. 다만 일방적인 주도가 되지 않도록 경계해야 합니다.');

    case '복덕상':
      return _SpecialEffect(30, '$who에게서 복덕상이 보입니다. 관계에 들어오는 순간 주변에 온기가 퍼지는 기질로, 함께하는 사람에게 물질적으로나 정서적으로 복을 나눠주는 드문 상입니다.');

    case '도화상':
      return _SpecialEffect(-8, '$who에게서 도화상이 보입니다. 사람을 끌어당기는 매력이 비범하지만, 그 매력이 관계 밖으로도 향할 수 있다는 점을 직시해야 합니다. 상대에게 충분한 관심을 돌리지 않으면 의심의 씨앗이 자랍니다.');

    case '군사상':
      if (partnerPrimary == Attribute.leadership ||
          partnerPrimary == Attribute.wealth) {
        return _SpecialEffect(
          28,
          '$who의 군사상과 $partnerLabel이 만나면 최고의 참모-리더 구도가 완성됩니다. 전략과 실행이 톱니바퀴처럼 맞물려, 사업이든 삶이든 함께하면 시너지가 폭발합니다.',
        );
      }
      return _SpecialEffect(12, '$who에게서 군사상이 보입니다. 냉철한 판단력과 전략적 사고가 관계의 위기 순간에 빛을 발합니다.');

    case '연예인상':
      return _SpecialEffect(18, '$who에게서 연예인상이 보입니다. 주변의 시선을 자연스럽게 끄는 화려함이 있어 관계에 활력을 불어넣지만, 관심을 독점하려는 성향이 상대를 그늘에 세울 수 있습니다.');

    case '대인상':
      return _SpecialEffect(25, '$who에게서 대인상이 보입니다. 넓은 도량과 포용력으로 상대의 부족함까지 감싸안는 기질이라, 이 사람 곁에서는 누구든 자신의 본모습을 드러낼 수 있습니다.');

    case '풍류상':
      if (partnerPrimary == Attribute.stability ||
          partnerPrimary == Attribute.trustworthiness) {
        return _SpecialEffect(
          -22,
          '$who의 풍류상과 안정을 추구하는 $partnerLabel 사이에 근본적인 가치관 충돌이 예상됩니다. 자유를 갈망하는 기질과 안정을 원하는 기질은 서로를 답답하게 만들 수 있습니다.',
        );
      }
      return _SpecialEffect(8, '$who에게서 풍류상이 보입니다. 삶을 즐길 줄 아는 여유로움이 관계에 낭만을 더하지만, 때로는 현실적인 책임감이 부족해 보일 수 있습니다.');

    case '천재상':
      if (partnerPrimary == Attribute.intelligence) {
        return _SpecialEffect(22, '$who의 천재상과 지적인 $partnerLabel이 만나면 끝없는 사유의 세계가 열립니다. 서로의 생각을 자극하며 보통 사람들이 도달하지 못하는 깊이의 대화를 나눌 수 있습니다.');
      }
      return _SpecialEffect(10, '$who에게서 천재상이 보입니다. 독창적이고 비범한 시각이 관계에 새로운 차원을 열어주지만, 상대가 따라가지 못하면 외로운 천재가 될 수 있습니다.');

    case '광인상':
      return _SpecialEffect(-30, '$who에게서 광인상이 보입니다. 극단적인 감정의 진폭이 관계를 롤러코스터로 만듭니다. 영감과 파괴를 동시에 가져오는 기질이라, 상대에게 대단한 인내를 요구합니다.');

    case '사기상':
      return _SpecialEffect(-40, '$who에게서 사기상이 감지됩니다. 신뢰의 기반이 근본적으로 흔들릴 수 있는 심각한 경고 신호입니다. 이 관계에서 상대는 항상 진실을 의심하게 될 가능성이 높으며, 장기적 유대를 기대하기 어렵습니다.');

    default:
      return const _SpecialEffect(0, null);
  }
}

String _extractSpecialBase(String special) {
  final idx = special.indexOf(' ');
  return idx > 0 ? special.substring(0, idx) : special;
}

String? _spPairFallbackText(String myBase, String albumBase) {
  // Known SP×SP interactions
  const spInteractions = <String, String>{
    '제왕상_제왕상': '두 사람 모두 제왕의 기운을 지녀 강렬한 존재감이 부딪히며, 주도권 분배가 관계의 핵심 과제입니다.',
    '제왕상_복덕상': '제왕의 추진력과 복덕의 포용력이 만나 리더와 참모의 이상적 구도를 형성할 수 있습니다.',
    '제왕상_광인상': '두 사람 모두 극단적 에너지를 지녀 폭발적 시너지와 갈등이 공존합니다.',
    '복덕상_복덕상': '두 사람 모두 복과 덕을 갖추어 평화롭고 풍요로운 관계가 기대됩니다.',
    '복덕상_도화상': '복덕의 안정감이 도화의 매력을 안아줄 수 있으나, 가치관 차이에 주의가 필요합니다.',
    '도화상_도화상': '두 사람 모두 강한 매력을 발산하여 화려하지만 신뢰 구축에 각별한 노력이 필요합니다.',
    '군사상_제왕상': '탁월한 전략가와 강한 리더가 만나 현실적 목표를 향한 강력한 팀워크를 발휘합니다.',
    '천재상_천재상': '두 사람의 비범한 지적 능력이 서로를 자극하며 독창적인 관계를 형성합니다.',
    '사기상_사기상': '두 사람 모두 신뢰 위험 요소를 지녀 관계의 기반이 매우 불안정할 수 있습니다.',
    '풍류상_복덕상': '자유로운 감성과 안정적 포용력이 만나 균형 잡힌 관계를 만들 수 있습니다.',
  };

  return spInteractions['${myBase}_$albumBase'] ??
      spInteractions['${albumBase}_$myBase'];
}

// ═══════════════════════════════════════════════════════════════
//  Step 5: Triggered Rules Cross-analysis (v2)
// ═══════════════════════════════════════════════════════════════

double _evaluateTriggeredRulesV2(
  List<TriggeredRule> myRules,
  List<TriggeredRule> albumRules,
  List<_RulePairResult> results,
) {
  double delta = 0;

  for (final myRule in myRules) {
    for (final albumRule in albumRules) {
      final key1 = (myRule.id, albumRule.id);
      final key2 = (albumRule.id, myRule.id);

      final def = _rulePairs[key1] ?? _rulePairs[key2];
      if (def != null) {
        results.add(_RulePairResult(
          myRule.id,
          albumRule.id,
          def.effect,
          def.delta,
          def.comment,
        ));
        delta += def.delta;
      }
    }
  }

  return (50 + delta).clamp(0, 100);
}

// ═══════════════════════════════════════════════════════════════
//  Step 7: Summary — 6 Section Narrative
// ═══════════════════════════════════════════════════════════════

String _buildSummaryV2(
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  Map<String, double> categoryScores,
  List<String> crossPairKeys,
  List<_RulePairResult> rulePairs,
  String? specialNote,
  double totalScore,
) {
  final buf = StringBuffer();
  final myLabel = myReport.archetype.primaryLabel;
  final albumLabel = albumReport.archetype.primaryLabel;
  final mySub = myReport.archetype.secondaryLabel;
  final albumSub = albumReport.archetype.secondaryLabel;
  final me = '나($myLabel)';
  final you = '상대방($albumLabel)';

  // ── Section 1: 총평 ──
  buf.writeln('## 총평');
  final archetypeText = _lookupText(
    text_blocks.archetypeCompatTexts,
    '${myLabel}_$albumLabel',
    '${albumLabel}_$myLabel',
  );
  if (archetypeText != null) {
    buf.writeln(archetypeText);
  }
  if (totalScore >= 80) {
    buf.writeln('$me의 기질과 $you의 성향이 깊이 공명하여, 함께할수록 서로의 빛을 끌어올리는 보기 드문 조합입니다. 나의 $mySub 기질이 상대방의 $albumSub 기질과 자연스럽게 어우러져 관계의 깊이가 더해집니다.');
  } else if (totalScore >= 65) {
    buf.writeln('$me와 $you는 서로의 부족한 면을 채워주는 보완적 관계입니다. 나의 $mySub 기질과 상대방의 $albumSub 기질이 균형을 이루어, 의식적으로 가꾸면 오래도록 안정적인 유대를 유지할 수 있습니다.');
  } else if (totalScore >= 45) {
    buf.writeln('$me와 $you 사이에는 조율이 필요한 지점이 있습니다. 하지만 나의 $mySub 기질과 상대방의 $albumSub 기질이 접점을 만들어, 서로를 이해하려는 노력이 관계를 한 단계 성장시킬 수 있습니다.');
  } else {
    buf.writeln('$me와 $you는 기질의 온도 차이가 큰 조합입니다. 나의 $mySub 기질과 상대방의 $albumSub 기질 사이의 괴리를 인정하고, 서로의 세계를 존중하는 것이 이 관계를 유지하는 핵심입니다.');
  }
  buf.writeln();

  // ── Section 2: 성격·기질 궁합 ──
  buf.writeln('## 성격·기질 궁합');
  _writeSection(buf, crossPairKeys, _personalityPairKeys, categoryScores,
      {'leadership', 'intelligence', 'sociability', 'stability'});
  buf.writeln();

  // ── Section 3: 감정·애정 궁합 ──
  buf.writeln('## 감정·애정 궁합');
  // Always include libido and sensuality for this section — these make it entertaining
  _writeSection(buf, crossPairKeys, _emotionPairKeys, categoryScores,
      {'libido', 'sensuality', 'emotionality', 'attractiveness'});
  buf.writeln();

  // ── Section 4: 생활·현실 궁합 ──
  buf.writeln('## 생활·현실 궁합');
  _writeSection(buf, crossPairKeys, _practicalPairKeys, categoryScores,
      {'wealth', 'stability', 'trustworthiness', 'leadership'});
  buf.writeln();

  // ── Section 5: 갈등 가능성과 조정 ──
  buf.writeln('## 갈등 가능성과 조정');
  _writeConflictSection(buf, crossPairKeys, rulePairs, categoryScores);
  buf.writeln();

  // ── Section 6: 장기 전망과 조언 ──
  buf.writeln('## 장기 전망과 조언');
  _writeLongTermSection(buf, categoryScores, specialNote, totalScore,
      myReport.gender, albumReport.gender, myLabel, albumLabel);

  return buf.toString().trim();
}

// ─── Text Lookup Helpers ─────────────────────────────────────

/// Look up crossPairTexts body by full key (e.g. "leadership_stability_highHigh")
String? _lookupCrossPairBody(String fullKey) {
  try {
    final entry = text_blocks.crossPairTexts[fullKey];
    return entry?['body'];
  } catch (_) {
    return null;
  }
}

/// Look up attributeCompatTexts body by attribute name and score
String? _lookupAttributeBody(String attrName, double score) {
  final pattern = score >= 70 ? 'synergy'
      : score >= 55 ? 'complement'
      : score >= 35 ? 'neutral'
      : 'clash';
  try {
    final attrTexts = text_blocks.attributeCompatTexts[attrName];
    if (attrTexts == null) return null;
    return attrTexts['${attrName}_$pattern']?['body'];
  } catch (_) {
    return null;
  }
}

/// Symmetric key lookup in a map
String? _lookupText(Map<String, String> map, String key1, String key2) {
  return map[key1] ?? map[key2];
}

// ─── Section Writers ─────────────────────────────────────────

void _writeSection(
  StringBuffer buf,
  List<String> crossPairKeys,
  Set<String> targetPairKeys,
  Map<String, double> categoryScores,
  Set<String> relatedAttrs,
) {
  var written = 0;

  // First: use crossPairTexts (highest quality)
  for (final fullKey in crossPairKeys) {
    if (written >= 3) break;
    final pairKey = fullKey.substring(0, fullKey.lastIndexOf('_'));
    if (!targetPairKeys.contains(pairKey)) continue;

    final body = _lookupCrossPairBody(fullKey);
    if (body != null) {
      buf.writeln(body);
      written++;
    }
  }

  // Second: always add attributeCompatTexts — these are the most vivid descriptions
  // Prioritize order: relatedAttrs is a LinkedHashSet, first items matter most
  final relevant = categoryScores.entries
      .where((e) => relatedAttrs.contains(e.key))
      .toList();
  // Sort by relatedAttrs insertion order (priority), then by score extremity
  final attrOrder = relatedAttrs.toList();
  relevant.sort((a, b) {
    final aIdx = attrOrder.indexOf(a.key);
    final bIdx = attrOrder.indexOf(b.key);
    if (aIdx != bIdx) return aIdx.compareTo(bIdx);
    return (b.value - 50).abs().compareTo((a.value - 50).abs());
  });

  for (final entry in relevant) {
    if (written >= 4) break;
    final body = _lookupAttributeBody(entry.key, entry.value);
    if (body != null) {
      buf.writeln(body);
      written++;
    }
  }

  if (written == 0) {
    buf.writeln('이 영역에서 두 사람은 평균적인 조화를 이루고 있어 큰 기복 없이 자연스러운 흐름을 유지할 수 있습니다.');
  }
}

void _writeConflictSection(
  StringBuffer buf,
  List<String> crossPairKeys,
  List<_RulePairResult> rulePairs,
  Map<String, double> categoryScores,
) {
  var written = 0;

  // Cross-pair conflicts: lowLow and lowHigh patterns
  final conflictKeys = crossPairKeys.where((k) =>
      k.endsWith('_lowLow') || k.endsWith('_highLow')).toList();

  for (final fullKey in conflictKeys.take(2)) {
    final body = _lookupCrossPairBody(fullKey);
    if (body != null) {
      buf.writeln(body);
      written++;
    }
  }

  // Rule pair conflicts
  final conflictRules = rulePairs
      .where((r) => r.effect == 'clash' || r.effect == 'volatile')
      .toList()
    ..sort((a, b) => a.delta.compareTo(b.delta));

  for (final rp in conflictRules.take(2)) {
    buf.writeln(rp.comment);
    written++;
  }

  // Low category scores as additional conflict indicators
  if (written < 2) {
    final lowScores = categoryScores.entries
        .where((e) => e.value < 40)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final entry in lowScores.take(2 - written)) {
      final body = _lookupAttributeBody(entry.key, entry.value);
      if (body != null) {
        buf.writeln(body);
        written++;
      }
    }
  }

  if (written == 0) {
    buf.writeln('두 사람 사이에 뚜렷한 갈등 요소는 보이지 않습니다. 다만 어떤 관계든 소통을 게을리하면 작은 오해가 쌓이는 법이니, 꾸준한 대화를 통해 서로의 마음을 확인하는 습관을 들이길 권합니다.');
  } else {
    buf.writeln('갈등이 예상되는 부분을 미리 알고 있다는 것 자체가 큰 강점입니다. 서로의 입장을 먼저 들어보려는 자세가 작은 마찰을 오히려 관계를 깊게 하는 계기로 바꿔줄 것입니다.');
  }
}

void _writeLongTermSection(
  StringBuffer buf,
  Map<String, double> categoryScores,
  String? specialNote,
  double totalScore,
  Gender myGender,
  Gender albumGender,
  String myLabel,
  String albumLabel,
) {
  final stability = categoryScores['stability'] ?? 50;
  final trust = categoryScores['trustworthiness'] ?? 50;
  final longTermBase = (stability + trust) / 2;

  if (longTermBase >= 70) {
    buf.writeln('두 사람 사이의 안정성과 신뢰는 시간이 지날수록 단단해질 기반을 갖추고 있습니다. 이 관계는 급격한 변화보다 꾸준한 깊이로 빛을 발하는 유형입니다.');
  } else if (longTermBase >= 50) {
    buf.writeln('관계의 안정성은 보통 수준이지만, 의식적으로 서로를 향한 신뢰를 쌓아간다면 세월과 함께 더 견고해질 수 있는 잠재력을 지닙니다.');
  } else {
    buf.writeln('안정성과 신뢰의 기반이 아직 약한 편이므로, 작은 약속부터 지켜가며 신뢰를 한 겹씩 쌓아가는 것이 이 관계의 장기적인 열쇠입니다.');
  }

  if (specialNote != null) {
    buf.writeln(specialNote);
  }

  // Gender-aware closing
  if (myGender != albumGender) {
    buf.writeln('서로 다른 에너지가 만나는 관계인 만큼, 상대의 표현 방식이 나와 다르다는 것을 자연스럽게 받아들일 때 관계의 깊이가 한 차원 달라집니다.');
  } else {
    buf.writeln('같은 결의 에너지가 공명하는 관계이기에, 서로의 고유한 영역을 침범하지 않으면서 함께 성장하는 방향을 찾는 것이 중요합니다.');
  }

  // Final advice tied to archetype
  final me = '나($myLabel)';
  final you = '상대방($albumLabel)';
  if (totalScore >= 65) {
    buf.writeln('$me와 $you의 만남은 좋은 궁합 위에 세워진 관계입니다. 서로의 장점을 적극적으로 인정하고 표현하는 것만으로도 이 관계는 한층 풍요로워질 것입니다.');
  } else {
    buf.writeln('$me와 $you 사이의 차이는 극복할 수 없는 장벽이 아니라, 서로를 더 깊이 이해하게 만드는 계기입니다. 차이를 조율하는 과정 자체가 두 사람을 더 단단하게 만들어줄 것입니다.');
  }
}
