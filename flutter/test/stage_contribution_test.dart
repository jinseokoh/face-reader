// Phase 3D — stage contribution balance diagnostic.
//
// Runs template-correlated Monte Carlo through the tree engine and reports
// the mean absolute contribution of each pipeline stage (base, distinct,
// zone, organ, palace) per attribute. A dominant stage or a fully dormant
// stage signals a weight/threshold imbalance.
//
// Uses the shared `faceTemplates` (same distribution as compat calibration)
// because real faces have STRONG metric correlations (e.g. nose ↔ mouth for
// wealth rules) that independent Gaussian sampling underrepresents.
//
// Run via: flutter test test/stage_contribution_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/compat_calibration.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

const double _noiseStd = 0.6;
const double _baseBias = 0.2;

double _sumAbs(Iterable<double> xs) =>
    xs.fold<double>(0, (a, b) => a + b.abs());

void main() {
  test('stage contribution balance across 20000 faces', () {
    const samples = 20000;
    final rng = Random(7777);

    final base = {for (final a in Attribute.values) a: 0.0};
    final distinct = {for (final a in Attribute.values) a: 0.0};
    final zone = {for (final a in Attribute.values) a: 0.0};
    final organ = {for (final a in Attribute.values) a: 0.0};
    final palace = {for (final a in Attribute.values) a: 0.0};

    final stageFireCount = <String, int>{
      'zone': 0,
      'organ': 0,
      'palace': 0,
    };
    final ruleFireCount = <String, int>{};

    for (int i = 0; i < samples; i++) {
      final gender = i.isEven ? Gender.male : Gender.female;
      final template = faceTemplates[rng.nextInt(faceTemplates.length)];
      final z = <String, double>{};
      for (final info in metricInfoList) {
        final bias = template.bias[info.id] ?? _baseBias;
        z[info.id] = (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5);
      }
      final breakdown = deriveAttributeScoresDetailed(
        tree: scoreTree(z),
        gender: gender,
        isOver50: false,
        hasLateral: false,
      );

      for (final attr in Attribute.values) {
        base[attr] = base[attr]! + _sumAbs(breakdown.basePerNode[attr]!.values);
        distinct[attr] =
            distinct[attr]! + (breakdown.distinctiveness[attr] ?? 0).abs();
        for (final r in breakdown.zoneRules) {
          zone[attr] = zone[attr]! + (r.effects[attr] ?? 0).abs();
        }
        for (final r in breakdown.organRules) {
          organ[attr] = organ[attr]! + (r.effects[attr] ?? 0).abs();
        }
        for (final r in breakdown.palaceRules) {
          palace[attr] = palace[attr]! + (r.effects[attr] ?? 0).abs();
        }
      }

      if (breakdown.zoneRules.isNotEmpty) stageFireCount['zone'] = stageFireCount['zone']! + 1;
      if (breakdown.organRules.isNotEmpty) stageFireCount['organ'] = stageFireCount['organ']! + 1;
      if (breakdown.palaceRules.isNotEmpty) stageFireCount['palace'] = stageFireCount['palace']! + 1;

      for (final r in [
        ...breakdown.zoneRules,
        ...breakdown.organRules,
        ...breakdown.palaceRules,
      ]) {
        ruleFireCount[r.id] = (ruleFireCount[r.id] ?? 0) + 1;
      }
    }

    // Normalize to mean per face
    void normalize(Map<Attribute, double> m) {
      for (final a in Attribute.values) {
        m[a] = m[a]! / samples;
      }
    }

    normalize(base);
    normalize(distinct);
    normalize(zone);
    normalize(organ);
    normalize(palace);

    // ignore: avoid_print
    print('\n========== Stage Contribution per Attribute (mean |value| per face) ==========');
    // ignore: avoid_print
    print('${'attr'.padRight(16)}${'base'.padLeft(8)}${'distinct'.padLeft(10)}'
        '${'zone'.padLeft(8)}${'organ'.padLeft(8)}${'palace'.padLeft(8)}${'total'.padLeft(8)}');
    for (final attr in Attribute.values) {
      final total = base[attr]! + distinct[attr]! + zone[attr]! + organ[attr]! + palace[attr]!;
      // ignore: avoid_print
      print('${attr.name.padRight(16)}'
          '${base[attr]!.toStringAsFixed(3).padLeft(8)}'
          '${distinct[attr]!.toStringAsFixed(3).padLeft(10)}'
          '${zone[attr]!.toStringAsFixed(3).padLeft(8)}'
          '${organ[attr]!.toStringAsFixed(3).padLeft(8)}'
          '${palace[attr]!.toStringAsFixed(3).padLeft(8)}'
          '${total.toStringAsFixed(3).padLeft(8)}');
    }

    // ignore: avoid_print
    print('\n========== Stage Firing Rate ==========');
    for (final e in stageFireCount.entries) {
      // ignore: avoid_print
      print('${e.key.padRight(8)} ${(e.value / samples * 100).toStringAsFixed(1)}% '
          '($e) of faces have ≥1 triggered rule');
    }

    // ignore: avoid_print
    print('\n========== Rule Firing Rate (sorted desc) ==========');
    final sortedRules = ruleFireCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sortedRules) {
      // ignore: avoid_print
      print('${e.key.padRight(8)} ${(e.value / samples * 100).toStringAsFixed(2)}%');
    }

    // ─── Assertions: balance invariants ───

    // 1. Every attribute receives at least *some* base contribution —
    //    weight matrix row must be non-empty / non-trivial.
    for (final attr in Attribute.values) {
      expect(base[attr]!, greaterThan(0.05),
          reason: '${attr.name} base stage contributes almost nothing ($base[attr])');
    }

    // 2. No single stage dominates >95% of the magnitude for any attribute.
    //    (base will usually lead but rules must move the needle.) 95% is
    //    loose because attributes with sparse rule menus (e.g. sociability,
    //    emotionality) are legitimately base-heavy; this catches the
    //    "wealth has zero rule contribution" pathology, not normal ratios.
    for (final attr in Attribute.values) {
      final total =
          base[attr]! + distinct[attr]! + zone[attr]! + organ[attr]! + palace[attr]!;
      if (total < 0.01) continue; // attributes with ~zero weight are fine.
      final stages = [base[attr]!, distinct[attr]!, zone[attr]!, organ[attr]!, palace[attr]!];
      final maxStage = stages.reduce((a, b) => a > b ? a : b);
      expect(maxStage / total, lessThan(0.95),
          reason:
              '${attr.name} dominated by one stage (${(maxStage / total * 100).toStringAsFixed(0)}%)');
    }

    // 3. Each of zone / organ / palace stages fires in non-trivial portion of faces.
    //    <1% firing means rule thresholds are too tight.
    for (final stage in ['zone', 'organ', 'palace']) {
      final rate = stageFireCount[stage]! / samples;
      expect(rate, greaterThan(0.05),
          reason:
              '$stage rules fire on only ${(rate * 100).toStringAsFixed(1)}% of faces');
    }

    // 4. Not every rule is dead code — at least 60% of defined rules must fire ≥0.1%.
    //    (Some rules are rare by design but wholesale dormancy is a bug.)
    final activeRules = ruleFireCount.entries.where((e) => e.value / samples >= 0.001).length;
    expect(activeRules, greaterThanOrEqualTo(15),
        reason:
            'only $activeRules rules fire ≥0.1% — most rules dead in realistic input');
  });
}
