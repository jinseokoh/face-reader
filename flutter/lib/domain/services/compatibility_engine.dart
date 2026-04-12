import 'dart:math';

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/domain/models/compatibility_result.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';

import 'package:face_reader/data/constants/compatibility_text_blocks.dart'
    as text_blocks;

// ═══════════════════════════════════════════════════════════════
//  V5 Importance ranking — drives variable verbosity per attribute
// ═══════════════════════════════════════════════════════════════

enum _AttrImportance { major, moderate, minor }

/// Computes per-attribute "noteworthiness" for a pair: extreme scores and big
/// gaps both raise importance, while balanced mid scores get demoted.
/// Returns a map ranking the top 2 as major, next 3 as moderate, rest as minor.
Map<Attribute, _AttrImportance> _rankByImportance(
  Map<Attribute, double> myScores,
  Map<Attribute, double> albumScores,
) {
  final notes = <Attribute, double>{};
  for (final attr in Attribute.values) {
    final my = myScores[attr] ?? 5.0;
    final album = albumScores[attr] ?? 5.0;
    // extremity: distance of EACH score from neutral 5.0
    // gap: absolute difference
    final extremity = (my - 5.0).abs() + (album - 5.0).abs();
    final gap = (my - album).abs();
    // both high or both low produce strong noteworthiness;
    // big gaps also produce strong noteworthiness;
    // balanced mid produces near zero
    notes[attr] = extremity + gap * 1.2;
  }
  final sorted = notes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final result = <Attribute, _AttrImportance>{};
  for (var i = 0; i < sorted.length; i++) {
    result[sorted[i].key] = i < 2
        ? _AttrImportance.major
        : (i < 5 ? _AttrImportance.moderate : _AttrImportance.minor);
  }
  return result;
}

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
  final specialResult = _evaluateSpecialArchetypes(myReport, albumReport);
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

  // Spread function: push scores away from center (50) but softly to avoid
  // pile-up at the upper clamp ceiling. Multiplier reduced from 2.2 → 1.6
  // and clamp widened to [5, 99] so the top tier is reachable but not
  // saturated. Re-calibrate via test/compat_calibration_test.dart whenever
  // this changes.
  final deviation = rawTotal - 50;
  final total = (50 + deviation * 1.6).clamp(5.0, 99.0);

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
      // Mid-range: split into 3 sub-patterns based on score sum
      final sum = aScore + bScore;
      final String midPattern;
      if (sum >= 13) {
        midPattern = 'midHigh';
      } else if (sum >= 7) {
        midPattern = 'midMid';
      } else {
        midPattern = 'midLow';
      }
      final midScore = 50.0 + (sum - 10) * 3.5;
      final score = midScore.clamp(15.0, 90.0);
      results.add(_CrossPairResult(pair.key, midPattern, score, pair.weight));
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
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
) {
  final myArchetype = myReport.archetype;
  final albumArchetype = albumReport.archetype;
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
      ownerReport: myReport,
      partnerReport: albumReport,
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
      ownerReport: albumReport,
      partnerReport: myReport,
    );
    score += result.delta;
    if (result.note != null) notes.add(result.note!);
  }

  return _SpecialResult(
    score.clamp(0, 100),
    notes.isEmpty ? null : notes.join('\n\n'),
  );
}

// Score deltas per special archetype (text comes from phrase library now).
const _specialDeltas = <String, double>{
  '제왕상': 25,
  '복덕상': 30,
  '도화상': -8,
  '군사상': 12,
  '연예인상': 18,
  '대인상': 25,
  '풍류상': 8,
  '천재상': 10,
  '광인상': -30,
  '사기상': -40,
};

_SpecialEffect _applySpecialEffect(
  String special,
  ArchetypeResult partnerArchetype,
  ArchetypeResult ownerArchetype, {
  required bool isMySpecial,
  required FaceReadingReport ownerReport,
  required FaceReadingReport partnerReport,
}) {
  final baseName = _extractSpecialBase(special);
  double delta = _specialDeltas[baseName] ?? 0;

  // Adjust delta for special × special collisions
  final partnerSpecial = partnerArchetype.specialArchetype;
  if (partnerSpecial != null) {
    final partnerBase = _extractSpecialBase(partnerSpecial);
    if (baseName == '제왕상' && (partnerBase == '제왕상' || partnerBase == '광인상')) {
      delta = -30;
    } else if (baseName == '풍류상' &&
        (partnerArchetype.primary == Attribute.stability ||
            partnerArchetype.primary == Attribute.trustworthiness)) {
      delta = -22;
    } else if (baseName == '군사상' &&
        (partnerArchetype.primary == Attribute.leadership ||
            partnerArchetype.primary == Attribute.wealth)) {
      delta = 28;
    } else if (baseName == '천재상' && partnerArchetype.primary == Attribute.intelligence) {
      delta = 22;
    }
  }

  // Generate text from phrase library using score-based variant seed
  final partnerType = _resolvePartnerType(partnerArchetype.primary);
  final phrases = text_blocks.specialPhrasesV4[baseName];
  if (phrases == null) return _SpecialEffect(delta, null);

  final variants = phrases[partnerType] ?? phrases['default'] ?? const [];
  if (variants.isEmpty) return _SpecialEffect(delta, null);

  // Variant seed based on attribute scores (deterministic but varied)
  final seedSource = isMySpecial ? ownerReport : partnerReport;
  final seed = _scoreSignature(seedSource);
  final rawNote = variants[seed % variants.length];
  // Substitute generic 당사자/상대 placeholders with concrete 나/상대방 based
  // on which side actually owns the special archetype.
  final note = _resolveSpecialPlaceholders(rawNote, isMySpecial);

  return _SpecialEffect(delta, note);
}

/// Resolves the generic 당사자/상대 wording in specialPhrasesV4 entries into
/// concrete "나"/"상대방" labels. Uses private-use placeholders so 상대방 in
/// source data isn't accidentally double-substituted by the 상대 → X step.
String _resolveSpecialPlaceholders(String note, bool isMySpecial) {
  const meTok = '\uE001';
  const partnerTok = '\uE002';
  // Replace longer tokens first (상대방 before 상대) to avoid partial matches.
  final tmp = note
      .replaceAll('당사자', meTok)
      .replaceAll('상대방', partnerTok)
      .replaceAll('상대', partnerTok);
  final meWord = isMySpecial ? '나' : '상대방';
  final partnerWord = isMySpecial ? '상대방' : '나';
  return tmp.replaceAll(meTok, meWord).replaceAll(partnerTok, partnerWord);
}

/// Maps a primary attribute to a partner type key in specialPhrasesV4
String _resolvePartnerType(Attribute primary) {
  switch (primary) {
    case Attribute.leadership:
      return 'withLeader';
    case Attribute.intelligence:
      return 'withScholar';
    case Attribute.stability:
      return 'withSage';
    case Attribute.emotionality:
      return 'withArtist';
    default:
      return 'default';
  }
}

/// Deterministic seed based on a report's full attribute score signature.
/// Tiny score differences produce different seeds → different variant selection.
int _scoreSignature(FaceReadingReport report) {
  int sig = 0;
  for (final attr in Attribute.values) {
    final s = report.attributeScores[attr] ?? 5.0;
    sig = (sig * 31 + (s * 100).round()) & 0x7fffffff;
  }
  return sig;
}

/// Variant seed combining two reports (for shared per-pair selection)
int _pairSignature(FaceReadingReport a, FaceReadingReport b) {
  return (_scoreSignature(a) * 73 + _scoreSignature(b) * 137) & 0x7fffffff;
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
  final pairSeed = _pairSignature(myReport, albumReport);
  final ruleSimilarity = _ruleJaccardSimilarity(
      myReport.triggeredRules, albumReport.triggeredRules);
  final importance = _rankByImportance(
      myReport.attributeScores, albumReport.attributeScores);

  // ── Section 1: 총평 ──
  buf.writeln('## 총평');
  _composeOverallV4(buf, myReport, albumReport, totalScore, pairSeed);
  buf.writeln();

  // ── Section 2: 성격·기질 궁합 ──
  buf.writeln('## 성격·기질 궁합');
  _composeAttrSection(
      buf,
      myReport,
      albumReport,
      const [
        Attribute.leadership,
        Attribute.intelligence,
        Attribute.sociability,
        Attribute.stability,
      ],
      importance);
  buf.writeln();

  // ── Section 3: 감정·애정 궁합 ──
  buf.writeln('## 감정·애정 궁합');
  _composeAttrSection(
      buf,
      myReport,
      albumReport,
      const [
        Attribute.libido,
        Attribute.sensuality,
        Attribute.emotionality,
        Attribute.attractiveness,
      ],
      importance);
  buf.writeln();

  // ── Section 3.5 (conditional): 침실 궁합 — 30~50대 한정 ──
  _composeSexualHarmonyV5(buf, myReport, albumReport, pairSeed);

  // ── Section 4: 생활·현실 궁합 ──
  buf.writeln('## 생활·현실 궁합');
  _composeAttrSection(
      buf,
      myReport,
      albumReport,
      const [
        Attribute.wealth,
        Attribute.stability,
        Attribute.trustworthiness,
        Attribute.leadership,
      ],
      importance);
  buf.writeln();

  // ── Section 5: 갈등 가능성과 조정 ──
  buf.writeln('## 갈등 가능성과 조정');
  _composeConflictV4(buf, myReport, albumReport, rulePairs, pairSeed);
  buf.writeln();

  // ── Section 6: 장기 전망과 조언 ──
  buf.writeln('## 장기 전망과 조언');
  _composeLongTermV4(buf, myReport, albumReport, totalScore,
      ruleSimilarity, specialNote, pairSeed);

  return buf.toString().trim();
}

// ═══════════════════════════════════════════════════════════════
//  V4 Generative Composers
// ═══════════════════════════════════════════════════════════════

/// Picks a phrase from a list using a seed for deterministic variation.
String _pickVariant(List<String> variants, int seed) {
  if (variants.isEmpty) return '';
  return variants[seed.abs() % variants.length];
}

/// Classifies attribute pair into one of 12 sub-patterns
String _classifyAttrPattern(double a, double b) {
  final gap = (a - b).abs();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;

  // Both extreme high
  if (a >= 9.0 && b >= 9.0) return 'bothExtremeHigh';
  // Both high
  if (a >= 7.0 && b >= 7.0) return 'bothHigh';
  // Gap extreme
  if (gap >= 6.0 && hi >= 8.0 && lo <= 2.0) return 'gapExtremeHighLow';
  // Gap high (one very high, other very low)
  if (gap >= 4.0 && hi >= 7.0 && lo <= 4.0) return 'gapHighLow';
  // One high, one mid
  if (hi >= 7.0 && lo >= 5.0 && lo <= 6.0) return 'oneHighOneMid';
  // Both mid-high
  if (a >= 5.5 && b >= 5.5 && a < 7.0 && b < 7.0) return 'bothMidHigh';
  // Both low
  if (a <= 3.5 && b <= 3.5) return 'bothLow';
  // One low, one mid
  if (lo <= 3.5 && hi >= 4.0 && hi <= 6.0) return 'oneLowOneMid';
  // Both mid-low
  if (a >= 3.5 && b >= 3.5 && a <= 5.5 && b <= 5.5) return 'bothMidLow';
  // Equal mid (close together in middle)
  if (gap <= 1.0 && a >= 4.0 && b >= 4.0 && a <= 6.0 && b <= 6.0) {
    return 'equalMid';
  }
  // Gap mid
  if (gap >= 3.0 && gap < 5.0) return 'gapMid';
  // Gap small
  return 'gapSmall';
}

/// Compose overall section (Section 1)
void _composeOverallV4(
  StringBuffer buf,
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  double totalScore,
  int pairSeed,
) {
  final myLabel = myReport.archetype.primaryLabel;
  final albumLabel = albumReport.archetype.primaryLabel;
  final me = '나($myLabel)';
  final you = '상대방($albumLabel)';

  // 1. Score-tier opener
  final overallKey = totalScore >= 80 ? 'overallVeryHigh'
      : totalScore >= 65 ? 'overallHigh'
      : totalScore >= 45 ? 'overallMid'
      : 'overallLow';
  final overallVariants = text_blocks.metaPhrasesV4[overallKey] ?? const [];
  if (overallVariants.isNotEmpty) {
    buf.writeln(_pickVariant(overallVariants, pairSeed));
  }

  // 2. Sub-modifier fingerprint sentence (variation between same-archetype people)
  final mySubModifier = _resolveSubModifier(myReport);
  final albumSubModifier = _resolveSubModifier(albumReport);
  final mySubPhrase =
      _subArchetypePhrase(myReport.archetype.primary, mySubModifier);
  final albumSubPhrase =
      _subArchetypePhrase(albumReport.archetype.primary, albumSubModifier);
  if (mySubPhrase != null && albumSubPhrase != null) {
    buf.writeln('$me는 $mySubPhrase 결을 띠고, $you는 $albumSubPhrase 색채가 짙습니다.');
  }

  // 3. Top resonance axis (둘 다 점수 높은 attribute)
  final myScores = myReport.attributeScores;
  final albumScores = albumReport.attributeScores;
  Attribute? topResonance;
  double topResonanceScore = 0;
  for (final attr in Attribute.values) {
    final my = myScores[attr] ?? 5.0;
    final al = albumScores[attr] ?? 5.0;
    final combined = (my + al) / 2;
    if (my >= 6.0 && al >= 6.0 && combined > topResonanceScore) {
      topResonance = attr;
      topResonanceScore = combined;
    }
  }
  if (topResonance != null) {
    final variants = text_blocks.metaPhrasesV4['topResonance'] ?? const [];
    if (variants.isNotEmpty) {
      final phrase = _pickVariant(variants, pairSeed + 1);
      buf.writeln(phrase.replaceFirst('%s', topResonance.labelKo));
    }
  }

  // 4. Top gap axis
  Attribute? topGap;
  double topGapValue = 0;
  for (final attr in Attribute.values) {
    final my = myScores[attr] ?? 5.0;
    final al = albumScores[attr] ?? 5.0;
    final gap = (my - al).abs();
    if (gap > topGapValue && gap >= 2.0) {
      topGap = attr;
      topGapValue = gap;
    }
  }
  if (topGap != null) {
    final variants = text_blocks.metaPhrasesV4['topGap'] ?? const [];
    if (variants.isNotEmpty) {
      final phrase = _pickVariant(variants, pairSeed + 2);
      buf.writeln(phrase.replaceFirst('%s', topGap.labelKo));
    }
  }

  // 5. Dominant metric trait (one extra fingerprint hint)
  final myDom = _dominantMetricPhrase(myReport);
  final albumDom = _dominantMetricPhrase(albumReport);
  if (myDom != null && albumDom != null) {
    buf.writeln('나에게서는 $myDom이 두드러지고, 상대방에게서는 $albumDom이 인상적으로 드러납니다.');
  }
}

/// Compose an attribute section using per-attribute generative sentences.
/// Length is controlled by the `importance` map: major gets 3 sentences,
/// moderate gets 2 (or whatever the V4 phrase has), minor is shortened to 1.
void _composeAttrSection(
  StringBuffer buf,
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  List<Attribute> attrs,
  Map<Attribute, _AttrImportance> importance,
) {
  for (final attr in attrs) {
    final my = myReport.attributeScores[attr] ?? 5.0;
    final album = albumReport.attributeScores[attr] ?? 5.0;
    final pattern = _classifyAttrPattern(my, album);
    final variants =
        text_blocks.attrPhrasesV4[attr.name]?[pattern] ?? const [];
    if (variants.isEmpty) continue;

    // Variant seed uses both raw scores → tiny diff yields a different variant
    final seed = (my * 73).round() + (album * 137).round();
    final base = _pickVariant(variants, seed);
    final level = importance[attr] ?? _AttrImportance.moderate;

    String phrase;
    switch (level) {
      case _AttrImportance.major:
        // Append a 비범한 관상가 implication. Fallback chain:
        //   1. attr × pattern specific
        //   2. attr × _default
        //   3. _default × _default
        final attrMap = text_blocks.attrPhrasesV5Implications[attr.name];
        List<String> imps = attrMap?[pattern] ?? const [];
        if (imps.isEmpty) imps = attrMap?['_default'] ?? const [];
        if (imps.isEmpty) {
          imps = text_blocks.attrPhrasesV5Implications['_default']
                  ?['_default'] ??
              const [];
        }
        final implication =
            imps.isNotEmpty ? _pickVariant(imps, seed + 11) : '';
        phrase = implication.isEmpty ? base : '$base $implication';
        break;
      case _AttrImportance.moderate:
        phrase = base;
        break;
      case _AttrImportance.minor:
        phrase = _firstSentenceOf(base);
        break;
    }

    final marker = switch (level) {
      _AttrImportance.major => '◆',
      _AttrImportance.moderate => '◇',
      _AttrImportance.minor => '·',
    };
    buf.writeln(
        '$marker ${attr.labelKo} ${my.toStringAsFixed(1)} vs ${album.toStringAsFixed(1)} — $phrase');
  }
}

/// Returns the first sentence of a Korean phrase (split by '. ' or '다.').
String _firstSentenceOf(String phrase) {
  // Split on '다.' followed by space, keeping the first chunk + '다.'
  final idx = phrase.indexOf('다. ');
  if (idx > 0) return phrase.substring(0, idx + 2);
  // Fallback: split on '. '
  final idx2 = phrase.indexOf('. ');
  if (idx2 > 0) return phrase.substring(0, idx2 + 1);
  return phrase;
}

// ═══════════════════════════════════════════════════════════════
//  V5 Sexual Harmony Section (30~50대 한정)
// ═══════════════════════════════════════════════════════════════

bool _isSexualEligibleAge(AgeGroup g) =>
    g == AgeGroup.thirties || g == AgeGroup.forties || g == AgeGroup.fifties;

// ─── V6 axis classifiers — three orthogonal dimensions ───

/// Intensity tier from libido + sensuality average.
String _classifyIntensity(double libAvg, double senAvg) {
  final avg = (libAvg + senAvg) / 2;
  if (avg >= 8.0) return 'blazing';
  if (avg >= 6.5) return 'hot';
  if (avg >= 4.5) return 'warm';
  return 'cold';
}

/// Emotion tier from emotionality average.
String _classifyEmotion(double myEmo, double albumEmo) {
  final avg = (myEmo + albumEmo) / 2;
  if (avg >= 7.0) return 'deep';
  if (avg >= 5.0) return 'balanced';
  return 'shallow';
}

/// Power dynamic tier from libido + sensuality combined gap (who leads).
String _classifyDynamic({
  required double myLib,
  required double albumLib,
  required double mySen,
  required double albumSen,
}) {
  final myTotal = myLib + mySen;
  final albumTotal = albumLib + albumSen;
  final gap = myTotal - albumTotal;
  if (gap.abs() < 1.5) return 'balanced';
  return gap > 0 ? 'meLeads' : 'albumLeads';
}

void _composeSexualHarmonyV5(
  StringBuffer buf,
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  int pairSeed,
) {
  // Gate 1: both partners must be 30~50대
  if (!_isSexualEligibleAge(myReport.ageGroup) ||
      !_isSexualEligibleAge(albumReport.ageGroup)) {
    return;
  }
  // Gate 2: opposite-sex only — same-sex pairs are typically friend selfie
  // comparisons in this market, where the romantic 침실 tone is misaligned;
  // also sidesteps app-store review risk for the wider rollout.
  if (myReport.gender == albumReport.gender) return;

  final myScores = myReport.attributeScores;
  final albumScores = albumReport.attributeScores;
  final myLib = myScores[Attribute.libido] ?? 5.0;
  final albumLib = albumScores[Attribute.libido] ?? 5.0;
  final mySen = myScores[Attribute.sensuality] ?? 5.0;
  final albumSen = albumScores[Attribute.sensuality] ?? 5.0;
  final myEmo = myScores[Attribute.emotionality] ?? 5.0;
  final albumEmo = albumScores[Attribute.emotionality] ?? 5.0;

  final intensity = _classifyIntensity(
      (myLib + albumLib) / 2, (mySen + albumSen) / 2);
  final emotion = _classifyEmotion(myEmo, albumEmo);
  final dynamic_ = _classifyDynamic(
      myLib: myLib, albumLib: albumLib, mySen: mySen, albumSen: albumSen);

  // Per-axis seeds derived from pair signature + raw decimal scores so that
  // tiny score perturbations (0.1) shift each slot independently.
  // Multiplications use distinct primes to keep slots uncorrelated.
  final scoreHash = ((myLib * 13.0).round() ^
          (albumLib * 17.0).round() ^
          (mySen * 23.0).round() ^
          (albumSen * 29.0).round() ^
          (myEmo * 31.0).round() ^
          (albumEmo * 37.0).round()) &
      0x7fffffff;
  final seedOpener = (pairSeed * 31 ^ scoreHash * 41) & 0x7fffffff;
  final seedBody = (pairSeed * 67 ^ scoreHash * 71) & 0x7fffffff;
  final seedClosing = (pairSeed * 113 ^ scoreHash * 131) & 0x7fffffff;

  final openerPool =
      text_blocks.sexualOpenerV6[intensity] ?? const <String>[];
  final bodyPool = text_blocks.sexualBodyV6[emotion] ?? const <String>[];
  final closingPool =
      text_blocks.sexualClosingV6[dynamic_] ?? const <String>[];

  if (openerPool.isEmpty || bodyPool.isEmpty || closingPool.isEmpty) return;

  final opener = _pickVariant(openerPool, seedOpener);
  final body = _pickVariant(bodyPool, seedBody);
  final closing = _pickVariant(closingPool, seedClosing);

  buf.writeln('## 침실 궁합');
  buf.writeln('$opener $body $closing');
  buf.writeln();
}

/// Compose conflict section
void _composeConflictV4(
  StringBuffer buf,
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  List<_RulePairResult> rulePairs,
  int pairSeed,
) {
  final myScores = myReport.attributeScores;
  final albumScores = albumReport.attributeScores;

  // Find top conflict attribute (largest negative impact)
  Attribute? topConflict;
  double topConflictScore = 100;
  for (final attr in Attribute.values) {
    final my = myScores[attr] ?? 5.0;
    final al = albumScores[attr] ?? 5.0;
    final pattern = _classifyAttrPattern(my, al);
    // Negative patterns
    if (pattern == 'bothLow' || pattern == 'gapExtremeHighLow' ||
        pattern == 'gapHighLow' || pattern == 'bothMidLow') {
      final combined = (my + al) / 2 - (my - al).abs();
      if (combined < topConflictScore) {
        topConflict = attr;
        topConflictScore = combined;
      }
    }
  }

  if (topConflict != null) {
    final my = myScores[topConflict] ?? 5.0;
    final album = albumScores[topConflict] ?? 5.0;
    final pattern = _classifyAttrPattern(my, album);
    final variants =
        text_blocks.attrPhrasesV4[topConflict.name]?[pattern] ?? const [];
    if (variants.isNotEmpty) {
      final seed = (my * 73).round() + (album * 137).round() + 1;
      buf.writeln('${topConflict.labelKo} 영역의 균열 — ${_pickVariant(variants, seed)}');
    }
  }

  // Top asymmetric axis (largest gap)
  Attribute? topAsym;
  double topAsymGap = 0;
  for (final attr in Attribute.values) {
    if (attr == topConflict) continue;
    final my = myScores[attr] ?? 5.0;
    final al = albumScores[attr] ?? 5.0;
    final gap = (my - al).abs();
    if (gap > topAsymGap && gap >= 3.0) {
      topAsym = attr;
      topAsymGap = gap;
    }
  }
  if (topAsym != null) {
    final my = myScores[topAsym] ?? 5.0;
    final album = albumScores[topAsym] ?? 5.0;
    final pattern = _classifyAttrPattern(my, album);
    final variants =
        text_blocks.attrPhrasesV4[topAsym.name]?[pattern] ?? const [];
    if (variants.isNotEmpty) {
      final seed = (my * 73).round() + (album * 137).round() + 2;
      buf.writeln('${topAsym.labelKo} 비대칭 — ${_pickVariant(variants, seed)}');
    }
  }

  // Triggered rule conflict (use comment from rule pair)
  final negativeRules = rulePairs
      .where((r) => r.effect == 'clash' || r.effect == 'volatile')
      .toList()
    ..sort((a, b) => a.delta.compareTo(b.delta));
  if (negativeRules.isNotEmpty) {
    buf.writeln(negativeRules.first.comment);
  }

  // Mitigation advice (variant)
  final hasStrongConflict = topConflict != null || negativeRules.isNotEmpty;
  final mitigationKey = hasStrongConflict ? 'mitigationStrong' : 'mitigationMild';
  final mitVariants = text_blocks.metaPhrasesV4[mitigationKey] ?? const [];
  if (mitVariants.isNotEmpty) {
    buf.writeln(_pickVariant(mitVariants, pairSeed));
  }
}

/// Compose long-term section
void _composeLongTermV4(
  StringBuffer buf,
  FaceReadingReport myReport,
  FaceReadingReport albumReport,
  double totalScore,
  double ruleSimilarity,
  String? specialNote,
  int pairSeed,
) {
  // Stability narrative — uses raw stability scores
  final myStab = myReport.attributeScores[Attribute.stability] ?? 5.0;
  final albumStab = albumReport.attributeScores[Attribute.stability] ?? 5.0;
  final stabAvg = (myStab + albumStab) / 2;
  final longTermKey = stabAvg >= 6.5 ? 'longTermSolid' : 'longTermFragile';
  final longTermVariants = text_blocks.metaPhrasesV4[longTermKey] ?? const [];
  if (longTermVariants.isNotEmpty) {
    buf.writeln(_pickVariant(longTermVariants, pairSeed));
  }

  // Stability composer line — direct
  final stabPattern = _classifyAttrPattern(myStab, albumStab);
  final stabVariants =
      text_blocks.attrPhrasesV4['stability']?[stabPattern] ?? const [];
  if (stabVariants.isNotEmpty) {
    final seed = (myStab * 73).round() + (albumStab * 137).round();
    buf.writeln('안정성 ${myStab.toStringAsFixed(1)} vs ${albumStab.toStringAsFixed(1)} — ${_pickVariant(stabVariants, seed)}');
  }

  // Trust composer line
  final myTrust = myReport.attributeScores[Attribute.trustworthiness] ?? 5.0;
  final albumTrust = albumReport.attributeScores[Attribute.trustworthiness] ?? 5.0;
  final trustPattern = _classifyAttrPattern(myTrust, albumTrust);
  final trustVariants =
      text_blocks.attrPhrasesV4['trustworthiness']?[trustPattern] ?? const [];
  if (trustVariants.isNotEmpty) {
    final seed = (myTrust * 73).round() + (albumTrust * 137).round() + 3;
    buf.writeln('신뢰성 ${myTrust.toStringAsFixed(1)} vs ${albumTrust.toStringAsFixed(1)} — ${_pickVariant(trustVariants, seed)}');
  }

  // Jaccard observation
  if (ruleSimilarity >= 0.65) {
    buf.writeln('두 사람의 기질 지문이 서로 닮아 있습니다. 같은 관점으로 세상을 바라보는 안정감이 있지만, 같은 함정에 빠지지 않도록 의식적으로 시야를 넓히는 노력이 필요합니다.');
  } else if (ruleSimilarity >= 0.3) {
    buf.writeln('두 사람의 기질 지문이 적절히 다릅니다. 한쪽이 놓치는 부분을 다른 쪽이 자연스럽게 채워주는 이상적인 차이입니다.');
  } else {
    buf.writeln('두 사람의 기질 지문이 거의 정반대입니다. 매일이 새로운 발견이 될 수 있는 자극적인 관계지만, 가치관 차이를 즐길 수 있는 여유가 필수입니다.');
  }

  // Special archetype note (already generated dynamically)
  if (specialNote != null) {
    buf.writeln(specialNote);
  }

  // Final advice (variant)
  final adviceKey = totalScore >= 65 ? 'finalAdviceHigh' : 'finalAdviceLow';
  final adviceVariants = text_blocks.metaPhrasesV4[adviceKey] ?? const [];
  if (adviceVariants.isNotEmpty) {
    buf.writeln(_pickVariant(adviceVariants, pairSeed + 5));
  }
}

// ─── Metric Fingerprint System ──────────────────────────────
//
// Same archetype + same partner can produce identical reports.
// Fingerprint adds variation by reading the underlying metric Z-scores.

/// Resolves a sub-modifier within an archetype based on metric Z-scores.
/// Returns the sub-modifier key (e.g. 'authority', 'executor', 'balanced').
String _resolveSubModifier(FaceReadingReport report) {
  final arch = report.archetype.primary;
  double z(String name) => report.metrics[name]?.zScore ?? 0;

  switch (arch) {
    case Attribute.wealth:
      if (z('nasalWidthRatio') > 1.0 && z('nasalHeightRatio') > 0.5) return 'tycoon';
      if (z('mouthWidthRatio') > 0.5) return 'merchant';
      return 'collector';
    case Attribute.leadership:
      final gonial = z('gonialAngle');
      final brow = z('eyebrowThickness');
      if (gonial > 1.2 && brow > 0.8) return 'authority';
      if (gonial > 0.5) return 'executor';
      return 'balanced';
    case Attribute.intelligence:
      final eyeFissure = z('eyeFissureRatio');
      final browDist = z('browEyeDistance');
      if (eyeFissure > 1.0 && browDist > 0.5) return 'analyst';
      if (eyeFissure > 0.5) return 'visionary';
      return 'philosopher';
    case Attribute.sociability:
      final mouth = z('mouthWidthRatio');
      final corner = z('mouthCornerAngle');
      if (mouth > 0.8 && corner > 0.5) return 'charmer';
      if (mouth > 0.5) return 'connector';
      return 'mediator';
    case Attribute.emotionality:
      final lip = z('lipFullnessRatio');
      final eyebrow = z('eyebrowThickness');
      if (lip > 1.0 && eyebrow < -0.3) return 'romantic';
      if (lip > 0.5) return 'intense';
      return 'sensitive';
    case Attribute.stability:
      final brow = z('browEyeDistance');
      final eyebrow = z('eyebrowThickness');
      if (brow > 1.0 && eyebrow > 0.5) return 'mountain';
      if (brow > 0.5) return 'pillar';
      return 'shelter';
    case Attribute.sensuality:
      final tilt = z('eyeCanthalTilt');
      final lip = z('lipFullnessRatio');
      if (tilt > 0.8 && lip > 0.5) return 'magnetic';
      if (tilt > 0.3) return 'seductive';
      return 'mystical';
    case Attribute.trustworthiness:
      final brow = z('browEyeDistance');
      final corner = z('mouthCornerAngle');
      if (brow > 1.0 && corner > 0.3) return 'oath';
      if (brow > 0.5) return 'guardian';
      return 'foundation';
    case Attribute.attractiveness:
      final faceAspect = z('faceAspectRatio');
      final taper = z('faceTaperRatio');
      if (faceAspect.abs() < 0.5 && taper < -0.3) return 'classic';
      if (taper < 0) return 'modern';
      return 'distinctive';
    case Attribute.libido:
      final philtrum = z('philtrumLength');
      final lip = z('lipFullnessRatio');
      if (philtrum < -0.8 && lip > 0.5) return 'firework';
      if (philtrum < -0.3) return 'sustained';
      return 'magnetic';
  }
}

/// Returns a phrase describing the dominant Z-score metric (most extreme).
String? _dominantMetricPhrase(FaceReadingReport report) {
  String? maxName;
  double maxAbs = 0.8; // threshold to be "notable"
  for (final entry in report.metrics.entries) {
    final abs = entry.value.zScore.abs();
    if (abs > maxAbs) {
      maxAbs = abs;
      maxName = entry.key;
    }
  }
  if (maxName == null) return null;
  final z = report.metrics[maxName]!.zScore;
  final dir = z > 0 ? 'high' : 'low';
  return text_blocks.metricTraitPhrases[maxName]?[dir];
}

/// Sub-archetype phrase lookup
String? _subArchetypePhrase(Attribute archetype, String subKey) {
  return text_blocks.subArchetypePhrases[archetype.name]?[subKey];
}

/// Jaccard similarity of two triggered rule sets (0~1)
double _ruleJaccardSimilarity(List<TriggeredRule> a, List<TriggeredRule> b) {
  final setA = a.map((r) => r.id).toSet();
  final setB = b.map((r) => r.id).toSet();
  if (setA.isEmpty && setB.isEmpty) return 1.0;
  final intersect = setA.intersection(setB).length;
  final union = setA.union(setB).length;
  return union == 0 ? 0 : intersect / union;
}

