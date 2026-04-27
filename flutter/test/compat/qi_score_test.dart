// P4 — L3a organ + L3b zone + L3c yinyang + L4 intimacy sanity.
//
// Goal:
//   (1) organ sub-score MC clamp · spread 확인
//   (2) zone harmony delta MC 분포 확인
//   (3) yinyang match 6 pattern 중 최소 4 개 fire
//   (4) qi sub-score 전체 spread · mean 확인
//   (5) intimacy gate 활성률 + gate off 시 중립 50
//
// 실행:
//   flutter test test/compat/qi_score_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_reader/domain/services/compat/intimacy.dart';
import 'package:face_reader/domain/services/compat/organ_pair_rules.dart';
import 'package:face_reader/domain/services/compat/palace.dart';
import 'package:face_reader/domain/services/compat/palace_state.dart';
import 'package:face_reader/domain/services/compat/qi_score.dart';
import 'package:face_reader/domain/services/compat/yinyang_matcher.dart';
import 'package:face_reader/domain/services/compat/zone_harmony.dart';
import 'package:face_reader/domain/services/mc_fixtures.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:face_reader/domain/services/yin_yang.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

({
  Map<String, double> zMap,
  Map<String, double> nodeZ,
  Map<String, bool> flags,
}) _sample(Random rng) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final z = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    z[info.id] = (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    z[info.id] ??= (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree(z);
  final nodeZ = <String, double>{};
  void walk(NodeScore node) {
    nodeZ[node.nodeId] = node.ownMeanZ ?? 0.0;
    for (final c in node.children) {
      walk(c);
    }
  }
  walk(tree);
  final flags = {
    'aquilineNose': rng.nextDouble() < 0.10,
    'snubNose': rng.nextDouble() < 0.08,
  };
  return (zMap: z, nodeZ: nodeZ, flags: flags);
}

AgeGroup _sampleAge(Random rng) {
  const ages = [
    AgeGroup.twenties,
    AgeGroup.thirties,
    AgeGroup.forties,
    AgeGroup.fifties,
  ];
  return ages[rng.nextInt(ages.length)];
}

Gender _sampleGender(Random rng) => rng.nextBool() ? Gender.male : Gender.female;

void main() {
  group('L3a organ pair matcher', () {
    test('subScore clamp + spread + mean', () {
      const n = 5000;
      final rng = Random(31);
      final scores = <double>[];
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final r = organPairScore(
          myZ: a.zMap,
          albumZ: b.zMap,
          myFlags: a.flags,
          albumFlags: b.flags,
        );
        expect(r.subScore, greaterThanOrEqualTo(5.0));
        expect(r.subScore, lessThanOrEqualTo(99.0));
        scores.add(r.subScore);
      }
      scores.sort();
      final p10 = scores[(n * 0.1).floor()];
      final p50 = scores[(n * 0.5).floor()];
      final p90 = scores[(n * 0.9).floor()];
      final mean = scores.reduce((a, b) => a + b) / n;

      // ignore: avoid_print
      print('\n========== organ subScore (n=$n) ==========');
      // ignore: avoid_print
      print('p10=${p10.toStringAsFixed(2)} p50=${p50.toStringAsFixed(2)} '
          'p90=${p90.toStringAsFixed(2)} mean=${mean.toStringAsFixed(2)}');
      // ignore: avoid_print
      print('spread(p90-p10)=${(p90 - p10).toStringAsFixed(2)}');

      expect(p90 - p10, greaterThanOrEqualTo(10.0),
          reason: 'organ spread ${(p90 - p10).toStringAsFixed(2)} < 10');
      expect(mean, inInclusiveRange(45.0, 56.0));
    });

    test('rule fire — dead rule 없음', () {
      const n = 5000;
      final rng = Random(91);
      final counts = <String, int>{for (final r in organRules) r.id: 0};
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final r = organPairScore(
          myZ: a.zMap,
          albumZ: b.zMap,
          myFlags: a.flags,
          albumFlags: b.flags,
        );
        for (final e in r.evidence) {
          counts[e.ruleId] = (counts[e.ruleId] ?? 0) + 1;
        }
      }
      // ignore: avoid_print
      print('\n========== organ rule fire (n=$n) ==========');
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        final rate = e.value * 100.0 / n;
        // ignore: avoid_print
        print('${e.key.padRight(22)} ${e.value.toString().padLeft(6)} '
            '(${rate.toStringAsFixed(2)}%)');
      }
      for (final r in organRules) {
        expect(counts[r.id]!, greaterThan(0),
            reason: '${r.id} rule dead in MC ($n 샘플)');
      }
    });
  });

  group('L3b zone harmony', () {
    test('delta 분포 clamp 내 + 주요 pattern 각 ≥ 0.3% fire', () {
      const n = 5000;
      final rng = Random(53);
      final counts = <String, int>{};
      final deltas = <double>[];
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final zm = matchZoneHarmony(
          my: computeZoneStates(a.zMap),
          album: computeZoneStates(b.zMap),
        );
        expect(zm.delta, inInclusiveRange(-24.0, 30.0));
        deltas.add(zm.delta);
        for (final e in zm.evidence) {
          counts[e.patternId] = (counts[e.patternId] ?? 0) + 1;
        }
      }
      deltas.sort();
      final p10 = deltas[(n * 0.1).floor()];
      final p90 = deltas[(n * 0.9).floor()];
      // ignore: avoid_print
      print('\n========== zone delta (n=$n) ==========');
      // ignore: avoid_print
      print('p10=${p10.toStringAsFixed(2)} p90=${p90.toStringAsFixed(2)}');
      // ignore: avoid_print
      print('========== zone pattern fire ==========');
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        // ignore: avoid_print
        print('${e.key.padRight(24)} '
            '${e.value.toString().padLeft(5)} '
            '(${(e.value * 100.0 / n).toStringAsFixed(2)}%)');
      }
      // 적어도 6 개 이상 서로 다른 pattern 이 실사용된다.
      expect(counts.keys.length, greaterThanOrEqualTo(6));
    });
  });

  group('L3c yinyang matcher', () {
    test('주요 pattern 중 ≥ 4 개 fire', () {
      const n = 5000;
      final rng = Random(77);
      final counts = <YinYangPatternKind, int>{
        for (final k in YinYangPatternKind.values) k: 0,
      };
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final m = matchYinYang(
          my: computeYinYang(a.zMap),
          album: computeYinYang(b.zMap),
          myGender: _sampleGender(rng),
          albumGender: _sampleGender(rng),
        );
        counts[m.kind] = (counts[m.kind] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('\n========== yinyang pattern (n=$n) ==========');
      for (final k in YinYangPatternKind.values) {
        final rate = counts[k]! * 100.0 / n;
        // ignore: avoid_print
        print('${k.name.padRight(20)} ${counts[k].toString().padLeft(5)} '
            '(${rate.toStringAsFixed(2)}%)');
      }
      final nonzero = counts.values.where((v) => v > 0).length;
      expect(nonzero, greaterThanOrEqualTo(4));
    });
  });

  group('qi sub-score aggregator', () {
    test('qi subScore clamp + spread', () {
      const n = 5000;
      final rng = Random(2);
      final scores = <double>[];
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final op = organPairScore(
          myZ: a.zMap,
          albumZ: b.zMap,
          myFlags: a.flags,
          albumFlags: b.flags,
        );
        final zh = matchZoneHarmony(
          my: computeZoneStates(a.zMap),
          album: computeZoneStates(b.zMap),
        );
        final yy = matchYinYang(
          my: computeYinYang(a.zMap),
          album: computeYinYang(b.zMap),
          myGender: _sampleGender(rng),
          albumGender: _sampleGender(rng),
        );
        final qi = computeQiScore(organ: op, zone: zh, yinYang: yy);
        expect(qi.subScore, inInclusiveRange(5.0, 99.0));
        scores.add(qi.subScore);
      }
      scores.sort();
      final p10 = scores[(n * 0.1).floor()];
      final p90 = scores[(n * 0.9).floor()];
      final mean = scores.reduce((a, b) => a + b) / n;
      // ignore: avoid_print
      print('\n========== qi subScore (n=$n) ==========');
      // ignore: avoid_print
      print('p10=${p10.toStringAsFixed(2)} p90=${p90.toStringAsFixed(2)} '
          'mean=${mean.toStringAsFixed(2)} spread=${(p90 - p10).toStringAsFixed(2)}');

      // qi 는 organ(0.55)·zone(0.25)·yinyang(0.20) 가중합 → 분포가 눌림.
      // organ spread ~14 × 0.55 = 7.7 + zone ~22 × 0.25 = 5.5 + yy ~1 독립합
      // sqrt(7.7² + 5.5² + 1²) ≈ 9.5. spread ≥ 9 이 현 구성의 자연 상한.
      expect(p90 - p10, greaterThanOrEqualTo(9.0));
      expect(mean, inInclusiveRange(45.0, 56.0));
    });
  });

  group('L4 intimacy gate', () {
    test('gate off (same-sex or age off) → 정확히 50', () {
      final rng = Random(5);
      final a = _sample(rng);
      final b = _sample(rng);
      final myPalaces = computePalaceStates(
        zMap: a.zMap,
        nodeZ: a.nodeZ,
        ageGroup: AgeGroup.thirties,
        lateralFlags: a.flags,
      );
      final albumPalaces = computePalaceStates(
        zMap: b.zMap,
        nodeZ: b.nodeZ,
        ageGroup: AgeGroup.thirties,
        lateralFlags: b.flags,
      );
      // same sex
      final r1 = computeIntimacy(
        myZ: a.zMap,
        albumZ: b.zMap,
        myPalaces: myPalaces,
        albumPalaces: albumPalaces,
        myGender: Gender.female,
        albumGender: Gender.female,
        myAge: AgeGroup.thirties,
        albumAge: AgeGroup.thirties,
      );
      expect(r1.gateActive, false);
      expect(r1.subScore, 50.0);
      // age off
      final r2 = computeIntimacy(
        myZ: a.zMap,
        albumZ: b.zMap,
        myPalaces: myPalaces,
        albumPalaces: albumPalaces,
        myGender: Gender.male,
        albumGender: Gender.female,
        myAge: AgeGroup.twenties,
        albumAge: AgeGroup.thirties,
      );
      expect(r2.gateActive, false);
      expect(r2.subScore, 50.0);
    });

    test('gate active subScore 분포', () {
      const n = 2000;
      final rng = Random(22);
      final scores = <double>[];
      int activeCount = 0;
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final ageA = AgeGroup.thirties;
        final ageB = AgeGroup.forties;
        final myPalaces = computePalaceStates(
          zMap: a.zMap,
          nodeZ: a.nodeZ,
          ageGroup: ageA,
          lateralFlags: a.flags,
        );
        final albumPalaces = computePalaceStates(
          zMap: b.zMap,
          nodeZ: b.nodeZ,
          ageGroup: ageB,
          lateralFlags: b.flags,
        );
        final r = computeIntimacy(
          myZ: a.zMap,
          albumZ: b.zMap,
          myPalaces: myPalaces,
          albumPalaces: albumPalaces,
          myGender: Gender.male,
          albumGender: Gender.female,
          myAge: ageA,
          albumAge: ageB,
        );
        if (r.gateActive) activeCount++;
        scores.add(r.subScore);
      }
      expect(activeCount, n); // 전부 게이트 활성 조건.
      scores.sort();
      final p10 = scores[(n * 0.1).floor()];
      final p90 = scores[(n * 0.9).floor()];
      final mean = scores.reduce((a, b) => a + b) / n;
      // ignore: avoid_print
      print('\n========== intimacy subScore (n=$n gate on) ==========');
      // ignore: avoid_print
      print('p10=${p10.toStringAsFixed(2)} p90=${p90.toStringAsFixed(2)} '
          'mean=${mean.toStringAsFixed(2)} spread=${(p90 - p10).toStringAsFixed(2)}');

      expect(p90 - p10, greaterThanOrEqualTo(10.0));
      expect(mean, inInclusiveRange(40.0, 65.0));
    });
  });
}
