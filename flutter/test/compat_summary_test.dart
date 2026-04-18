// Verifies the V5 compatibility summary changes:
//
//  1. Variable verbosity by importance: top 2 attributes (major) get a 비범한
//     관상가 implication appended; minor attributes are shortened to one
//     sentence.
//  2. Sexual harmony section appears ONLY when both partners are 30~50대.
//
// Run via: flutter test test/compat_summary_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/compatibility_engine.dart';
import 'package:face_reader/domain/services/metric_score.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

FaceReadingReport _synthetic(Random rng, Gender gender, AgeGroup age) {
  final zMap = <String, double>{};
  final intScores = <String, int>{};
  for (final info in metricInfoList) {
    final z = (_normal(rng) * 0.85 + 0.2).clamp(-3.5, 3.5);
    zMap[info.id] = z;
    intScores[info.id] = convertToScore(z, info.type);
  }
  final tree = scoreTree(zMap);
  final breakdown = deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: age.isOver50,
    hasLateral: false,
  );
  final normalized = normalizeAllScores(breakdown.total, gender);
  final archetype = classifyArchetype(normalized);
  final metricResults = <String, MetricResult>{};
  for (final info in metricInfoList) {
    metricResults[info.id] = MetricResult(
      id: info.id,
      rawValue: 0,
      zScore: zMap[info.id]!,
      zAdjusted: zMap[info.id]!,
      metricScore: intScores[info.id]!,
    );
  }
  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime.now(),
    source: AnalysisSource.album,
    metrics: metricResults,
    nodeScores: _collectNodeScores(tree),
    attributes: _buildAttributeEvidence(breakdown, normalized),
    rules: _buildRuleEvidence(breakdown),
    archetype: archetype,
  );
}

Map<String, NodeEvidence> _collectNodeScores(NodeScore root) {
  final out = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    out[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final child in node.children) {
      walk(child);
    }
  }
  walk(root);
  return out;
}

Map<Attribute, AttributeEvidence> _buildAttributeEvidence(
  AttributeBreakdown breakdown,
  Map<Attribute, double> normalizedScores,
) {
  final out = <Attribute, AttributeEvidence>{};
  for (final attr in Attribute.values) {
    final base = breakdown.basePerNode[attr] ?? const <String, double>{};
    final dist = breakdown.distinctiveness[attr] ?? 0.0;
    final raw = breakdown.total[attr] ?? 0.0;
    final norm = normalizedScores[attr] ?? 5.0;
    final bag = <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
    if (dist.abs() > 0.05) bag['distinctiveness'] = dist;
    for (final r in [...breakdown.zoneRules, ...breakdown.organRules,
        ...breakdown.palaceRules, ...breakdown.ageRules, ...breakdown.lateralRules]) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    final sorted = bag.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    out[attr] = AttributeEvidence(
      rawTotal: raw,
      normalizedScore: norm,
      basePerNode: Map<String, double>.from(base),
      distinctiveness: dist,
      contributors: sorted.map((e) => Contributor(id: e.key, value: e.value)).toList(),
    );
  }
  return out;
}

List<RuleEvidence> _buildRuleEvidence(AttributeBreakdown breakdown) {
  final out = <RuleEvidence>[];
  for (final r in breakdown.zoneRules) {
    out.add(RuleEvidence(id: r.id, stage: 'zone', effects: r.effects));
  }
  for (final r in breakdown.organRules) {
    out.add(RuleEvidence(id: r.id, stage: 'organ', effects: r.effects));
  }
  for (final r in breakdown.palaceRules) {
    out.add(RuleEvidence(id: r.id, stage: 'palace', effects: r.effects));
  }
  for (final r in breakdown.ageRules) {
    out.add(RuleEvidence(id: r.id, stage: 'age', effects: r.effects));
  }
  for (final r in breakdown.lateralRules) {
    out.add(RuleEvidence(id: r.id, stage: 'lateral', effects: r.effects));
  }
  return out;
}

void main() {
  test('침실 궁합 section appears only for 30~50대', () {
    final rng = Random(42);

    final eligibleAges = [
      AgeGroup.thirties,
      AgeGroup.forties,
      AgeGroup.fifties,
    ];
    final ineligibleAges = [
      AgeGroup.teens,
      AgeGroup.twenties,
      AgeGroup.sixties,
      AgeGroup.seventies,
    ];

    // ─── Eligible: BOTH 30~50대 → must have section ───
    int eligibleHits = 0;
    int eligibleTotal = 0;
    for (final ageA in eligibleAges) {
      for (final ageB in eligibleAges) {
        for (var i = 0; i < 5; i++) {
          final my = _synthetic(rng, Gender.male, ageA);
          final album = _synthetic(rng, Gender.female, ageB);
          final result = evaluateCompatibility(my, album);
          eligibleTotal++;
          if (result.summary.contains('## 침실 궁합')) eligibleHits++;
        }
      }
    }
    expect(eligibleHits, equals(eligibleTotal),
        reason:
            '30~50대 페어 $eligibleTotal중 $eligibleHits 개만 침실 궁합 섹션 포함됨 (전체 포함되어야 함)');

    // ─── Ineligible: at least one outside 30~50대 → must NOT have section ───
    int ineligibleLeaks = 0;
    int ineligibleTotal = 0;
    for (final ageA in ineligibleAges) {
      for (final ageB in [...eligibleAges, ...ineligibleAges]) {
        final my = _synthetic(rng, Gender.male, ageA);
        final album = _synthetic(rng, Gender.female, ageB);
        final result = evaluateCompatibility(my, album);
        ineligibleTotal++;
        if (result.summary.contains('## 침실 궁합')) ineligibleLeaks++;
      }
    }
    expect(ineligibleLeaks, equals(0),
        reason:
            '30~50대가 아닌 페어 $ineligibleTotal 중 $ineligibleLeaks 개에 침실 궁합 섹션이 잘못 포함됨');

    // ignore: avoid_print
    print('\n========== 침실 궁합 Section Gating ==========');
    // ignore: avoid_print
    print('30~50대 페어 (포함되어야 함): $eligibleHits/$eligibleTotal');
    // ignore: avoid_print
    print('비-30~50대 페어 (제외되어야 함): leaks=$ineligibleLeaks/$ineligibleTotal');
  });

  test('major attributes get longer text than minor attributes', () {
    final rng = Random(7);
    int majorLongerCount = 0;
    int sampled = 0;

    for (var i = 0; i < 50; i++) {
      final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
      final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
      final result = evaluateCompatibility(my, album);

      // Find one major-marked line and one minor-marked line in summary
      final lines = result.summary.split('\n');
      String? majorLine;
      String? minorLine;
      for (final l in lines) {
        if (majorLine == null && l.startsWith('◆ ')) majorLine = l;
        if (minorLine == null && l.startsWith('· ')) minorLine = l;
        if (majorLine != null && minorLine != null) break;
      }
      if (majorLine != null && minorLine != null) {
        sampled++;
        if (majorLine.length > minorLine.length) majorLongerCount++;
      }
    }

    expect(sampled, greaterThan(20),
        reason: 'not enough samples produced both major and minor lines');
    // Major lines should be longer than minor lines in the vast majority of cases
    expect(majorLongerCount / sampled, greaterThan(0.85),
        reason:
            'major lines were longer in only ${majorLongerCount}/$sampled cases');

    // ignore: avoid_print
    print('\n========== Major vs Minor Length ==========');
    // ignore: avoid_print
    print('Sampled: $sampled, major-longer: $majorLongerCount '
        '(${(majorLongerCount / sampled * 100).toStringAsFixed(1)}%)');
  });

  test('침실 궁합: same-sex pairs must NOT have the section', () {
    final rng = Random(7777);
    int sameSexLeaks = 0;
    int sameSexTotal = 0;

    // 남남 + 여여 페어 30~50대 안에서 다수 생성, 침실 궁합 섹션 누출 검사
    for (final age in [
      AgeGroup.thirties,
      AgeGroup.forties,
      AgeGroup.fifties,
    ]) {
      for (final g in [Gender.male, Gender.female]) {
        for (var i = 0; i < 10; i++) {
          final my = _synthetic(rng, g, age);
          final partner = _synthetic(rng, g, age);
          final result = evaluateCompatibility(my, partner);
          sameSexTotal++;
          if (result.summary.contains('## 침실 궁합')) sameSexLeaks++;
        }
      }
    }

    // ignore: avoid_print
    print('\n========== Same-Sex Sexual Harmony Gate ==========');
    // ignore: avoid_print
    print('동성 페어 (30~50대) 표본: $sameSexTotal, 섹션 누출: $sameSexLeaks');

    expect(sameSexLeaks, equals(0),
        reason: '동성 페어 $sameSexTotal중 $sameSexLeaks개에 침실 궁합 섹션이 잘못 포함됨');

    // 한편 이성 페어 30~50대는 여전히 섹션이 있어야 한다 (sanity)
    int oppositeHits = 0;
    int oppositeTotal = 0;
    for (var i = 0; i < 30; i++) {
      final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
      final partner = _synthetic(rng, Gender.female, AgeGroup.thirties);
      final result = evaluateCompatibility(my, partner);
      oppositeTotal++;
      if (result.summary.contains('## 침실 궁합')) oppositeHits++;
    }
    expect(oppositeHits, equals(oppositeTotal),
        reason: '이성 페어 30대 $oppositeTotal중 $oppositeHits개만 섹션 포함');
  });

  test('침실 궁합 V6: high variety across many pairs', () {
    final rng = Random(2026);
    final summaries = <String>{};
    const samples = 200;

    for (var i = 0; i < samples; i++) {
      final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
      final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
      final result = evaluateCompatibility(my, album);
      // Extract just the 침실 궁합 section content
      final lines = result.summary.split('\n');
      final idx = lines.indexOf('## 침실 궁합');
      if (idx >= 0 && idx + 1 < lines.length) {
        summaries.add(lines[idx + 1]);
      }
    }

    // ignore: avoid_print
    print('\n========== 침실 궁합 Variety ==========');
    // ignore: avoid_print
    print('Samples: $samples, unique outputs: ${summaries.length}');

    // Compositional pools should produce ≥100 unique outputs in 200 samples
    expect(summaries.length, greaterThanOrEqualTo(100),
        reason: 'only ${summaries.length} unique outputs in $samples pairs '
            '— pools too repetitive');
  });

  test('침실 궁합 V6: tiny score perturbations shift output', () {
    // Build two reports differing by one attribute by 0.1
    final rng = Random(31);
    final myA = _synthetic(rng, Gender.male, AgeGroup.thirties);
    final albumA = _synthetic(rng, Gender.female, AgeGroup.thirties);

    int shifts = 0;
    int trials = 0;
    for (final attr in Attribute.values) {
      final base = albumA.attributeScores[attr] ?? 5.0;
      // Skip attributes already at boundary
      if (base >= 9.9 || base <= 5.1) continue;
      // Mutate album by +0.2 on this attribute
      final mutated = Map<Attribute, double>.from(albumA.attributeScores);
      mutated[attr] = (base + 0.2).clamp(5.0, 10.0);
      // Rebuild attributes with mutated normalized scores
      final mutatedAttrs = <Attribute, AttributeEvidence>{};
      for (final attr in Attribute.values) {
        final orig = albumA.attributes[attr]!;
        mutatedAttrs[attr] = AttributeEvidence(
          rawTotal: orig.rawTotal,
          normalizedScore: mutated[attr] ?? orig.normalizedScore,
          basePerNode: orig.basePerNode,
          distinctiveness: orig.distinctiveness,
          contributors: orig.contributors,
        );
      }
      final albumB = FaceReadingReport(
        ethnicity: albumA.ethnicity,
        gender: albumA.gender,
        ageGroup: albumA.ageGroup,
        timestamp: albumA.timestamp,
        source: albumA.source,
        metrics: albumA.metrics,
        nodeScores: albumA.nodeScores,
        attributes: mutatedAttrs,
        rules: albumA.rules,
        archetype: albumA.archetype,
      );
      final resA = evaluateCompatibility(myA, albumA);
      final resB = evaluateCompatibility(myA, albumB);
      final lA = resA.summary.split('\n');
      final lB = resB.summary.split('\n');
      final iA = lA.indexOf('## 침실 궁합');
      final iB = lB.indexOf('## 침실 궁합');
      if (iA >= 0 && iB >= 0) {
        trials++;
        if (lA[iA + 1] != lB[iB + 1]) shifts++;
      }
    }

    // ignore: avoid_print
    print('\n========== 침실 궁합 Sensitivity ==========');
    // ignore: avoid_print
    print('Trials: $trials, output-shifted: $shifts '
        '(${(shifts / trials * 100).toStringAsFixed(0)}%)');

    // At least half the perturbations should change the output
    expect(shifts / trials, greaterThan(0.4),
        reason: 'only $shifts/$trials perturbations changed the output');
  });

  test('sample summary print (30대 vs 30대)', () {
    final rng = Random(2026);
    final my = _synthetic(rng, Gender.male, AgeGroup.thirties);
    final album = _synthetic(rng, Gender.female, AgeGroup.thirties);
    final result = evaluateCompatibility(my, album);
    // ignore: avoid_print
    print('\n========== Sample Summary (30대 vs 30대) ==========');
    // ignore: avoid_print
    print('Score: ${result.score}');
    // ignore: avoid_print
    print(result.summary);
  });
}
