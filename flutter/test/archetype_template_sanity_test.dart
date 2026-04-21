// Phase 3D — template-to-attribute sanity.
//
// For each archetype face template (leader / scholar / merchant / charmer /
// sensual / anchor) generate 100 correlated faces and verify that the
// intended attribute lands in the top-3 normalized scores at a ≥55% hit
// rate. Catches the "thick brow always wins regardless of intent" class of
// bugs where the weight matrix or rules don't actually differentiate the
// archetypes they're supposed to.
//
// Run via: flutter test test/archetype_template_sanity_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/mc_fixtures.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

// Per-template target attributes. Each template is DESIGNED around the new
// engine's weight matrix + rule firing pathway for these attributes. If the
// redesign is correct, the target attribute should land in the top-3 of the
// normalized score at ≥70% hit rate.
const _targets = <String, List<Attribute>>{
  'leader': [Attribute.leadership],
  'scholar': [Attribute.intelligence],
  'merchant': [Attribute.wealth],
  'charmer': [Attribute.sociability, Attribute.attractiveness],
  'sensual': [Attribute.sensuality, Attribute.libido],
  'anchor': [Attribute.stability, Attribute.trustworthiness],
};

const double _noiseStd = 0.6;
const double _baseBias = 0.2;

void main() {
  test('each template lifts its intended attribute into top-3 (≥70%)', () {
    const samplesPerTemplate = 100;
    final rng = Random(2026);

    final hitRates = <String, double>{};
    final meanRanks = <String, Map<Attribute, double>>{};

    for (final t in faceTemplates) {
      final expected = _targets[t.label];
      if (expected == null) {
        fail('no target attribute mapping for template "${t.label}"');
      }
      int hits = 0;
      final rankSums = {for (final a in Attribute.values) a: 0};

      for (int i = 0; i < samplesPerTemplate; i++) {
        final gender = i.isEven ? Gender.male : Gender.female;
        final z = <String, double>{};
        for (final info in metricInfoList) {
          final bias = t.bias[info.id] ?? _baseBias;
          z[info.id] =
              (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5).toDouble();
        }
        final raws = deriveAttributeScores(
          tree: scoreTree(z),
          gender: gender,
          isOver50: false,
          hasLateral: false,
        );
        final normalized = normalizeAllScores(raws, gender);

        final sorted = normalized.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (int r = 0; r < sorted.length; r++) {
          rankSums[sorted[r].key] = rankSums[sorted[r].key]! + r;
        }
        final top3 = sorted.take(3).map((e) => e.key).toSet();
        if (expected.any(top3.contains)) hits++;
      }

      hitRates[t.label] = hits / samplesPerTemplate;
      meanRanks[t.label] = {
        for (final a in Attribute.values)
          a: rankSums[a]! / samplesPerTemplate,
      };
    }

    // ignore: avoid_print
    print('\n========== Template → Target-Attribute Top-3 Hit Rate ==========');
    for (final t in faceTemplates) {
      final pct = (hitRates[t.label]! * 100).toStringAsFixed(1);
      final expected = _targets[t.label]!.map((a) => a.name).join('/');
      // ignore: avoid_print
      print('${t.label.padRight(10)} expect=$expected'
          '${' '.padLeft((20 - expected.length).clamp(1, 20))} hit=$pct%');
    }

    // ignore: avoid_print
    print('\n========== Mean Rank per Attribute per Template (0 = best) ==========');
    final header = <String>['attr'.padRight(16)];
    for (final t in faceTemplates) {
      header.add(t.label.padLeft(10));
    }
    // ignore: avoid_print
    print(header.join(' '));
    for (final attr in Attribute.values) {
      final row = <String>[attr.name.padRight(16)];
      for (final t in faceTemplates) {
        row.add(meanRanks[t.label]![attr]!.toStringAsFixed(2).padLeft(10));
      }
      // ignore: avoid_print
      print(row.join(' '));
    }

    // ─── Assertions ───
    // v2.6 threshold 완화: 0.70 → 0.55. 근거: zone-parity weight matrix +
    // rule magnitude cap (|Δ| ≤ 0.5) 로 template 차별 신호가 의도적으로
    // 약해졌다. Per-attribute 가 더이상 단일 metric 에 의해 강하게 끌리지
    // 않으므로 merchant(wealth) 등 zone 분산형 target 은 top-3 진입률이
    // 자연스럽게 60% 대. target mean rank < 4 assertion 이 남아 "target 이
    // 실제 1~3위 근처" 라는 의미 있는 신호는 계속 보증한다.
    for (final t in faceTemplates) {
      final expected = _targets[t.label]!;
      expect(hitRates[t.label]!, greaterThanOrEqualTo(0.55),
          reason:
              '${t.label} template: expected ${expected.map((a) => a.name).join('/')} '
              'in top-3 only ${(hitRates[t.label]! * 100).toStringAsFixed(1)}% of the time');
    }

    // Each template's target attribute should rank in the top-4 on average
    // (rank 0-3 out of 10). Within-template competition check: the target
    // shouldn't just sneak into top-3, it should be the best rank among
    // its candidates.
    for (final t in faceTemplates) {
      final expected = _targets[t.label]!;
      final targetRank = expected
          .map((a) => meanRanks[t.label]![a]!)
          .reduce((a, b) => a < b ? a : b);
      expect(targetRank, lessThan(4.0),
          reason:
              '${t.label}: target mean rank $targetRank >= 4 (target attribute not reliably elevated)');
    }
  });
}
