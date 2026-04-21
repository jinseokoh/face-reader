// P3 — 十二宮 state computer sanity.
//
// Goal: MC 샘플을 돌려 각 궁이
//   (1) strong/weak/balanced 3 단계를 의미 있는 비율로 발동한다 (no dead state)
//   (2) 정의된 sub-flag 들이 일정 비율 이상 fire 한다 (임계가 절대 dead 아님)
//
// 실행:
//   flutter test test/compat/palace_state_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/domain/services/compat/palace.dart';
import 'package:face_reader/domain/services/compat/palace_state.dart';
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

/// 샘플 하나 생성 + nodeZ 추출.
({Map<String, double> zMap, Map<String, double> nodeZ}) _sample(Random rng) {
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
  return (zMap: z, nodeZ: nodeZ);
}

/// 샘플마다 age 를 랜덤. fishTailWrinkle 은 30+ gate 이므로 분포 비율 고루.
AgeGroup _sampleAge(Random rng) {
  const ages = [
    AgeGroup.twenties,
    AgeGroup.thirties,
    AgeGroup.forties,
    AgeGroup.fifties,
  ];
  return ages[rng.nextInt(ages.length)];
}

void main() {
  group('L2 palace state computer', () {
    test('각 궁의 strong/weak/balanced 3 단계가 모두 fire', () {
      const n = 2000;
      final rng = Random(42);
      final levelCounts = <Palace, Map<PalaceLevel, int>>{
        for (final p in Palace.values)
          p: {for (final l in PalaceLevel.values) l: 0},
      };

      for (int i = 0; i < n; i++) {
        final s = _sample(rng);
        final states = computePalaceStates(
          zMap: s.zMap,
          nodeZ: s.nodeZ,
          ageGroup: _sampleAge(rng),
          lateralFlags: const {},
        );
        for (final entry in states.entries) {
          levelCounts[entry.key]![entry.value.level] =
              levelCounts[entry.key]![entry.value.level]! + 1;
        }
      }

      // ignore: avoid_print
      print('\n========== palace level distribution (n=$n) ==========');
      for (final p in Palace.values) {
        final c = levelCounts[p]!;
        final s = c[PalaceLevel.strong]! * 100.0 / n;
        final b = c[PalaceLevel.balanced]! * 100.0 / n;
        final w = c[PalaceLevel.weak]! * 100.0 / n;
        // ignore: avoid_print
        print('${p.hanja.padRight(4)} strong=${s.toStringAsFixed(1)}% '
            'bal=${b.toStringAsFixed(1)}% weak=${w.toStringAsFixed(1)}%');
      }

      for (final p in Palace.values) {
        final c = levelCounts[p]!;
        // strong/weak 각 최소 5% 이상 fire (단조 balanced 방지).
        expect(c[PalaceLevel.strong]! / n, greaterThanOrEqualTo(0.05),
            reason: '${p.hanja} strong 발동률 < 5% — 임계 재조정 필요');
        expect(c[PalaceLevel.weak]! / n, greaterThanOrEqualTo(0.05),
            reason: '${p.hanja} weak 발동률 < 5% — 임계 재조정 필요');
        // balanced 도 완전 0 이면 안됨 (항상 strong/weak 쪽으로 몰림).
        expect(c[PalaceLevel.balanced]! / n, greaterThanOrEqualTo(0.10),
            reason: '${p.hanja} balanced 발동률 < 10%');
      }
    });

    test('정의된 sub-flag 들이 적어도 1% 이상 fire 한다', () {
      const n = 3000;
      final rng = Random(777);
      final flagCounts = <PalaceFlag, int>{
        for (final f in PalaceFlag.values) f: 0,
      };

      for (int i = 0; i < n; i++) {
        final s = _sample(rng);
        final states = computePalaceStates(
          zMap: s.zMap,
          nodeZ: s.nodeZ,
          ageGroup: _sampleAge(rng),
          lateralFlags: {
            // aquilineNose 는 dorsalConvexity z≥3 — MC 샘플에서는 희소.
            // 인위적으로 일부 샘플에 true 박아서 hookedNose flag 도 fire.
            'aquilineNose': rng.nextDouble() < 0.08,
          },
        );
        for (final st in states.values) {
          for (final f in st.flags) {
            flagCounts[f] = flagCounts[f]! + 1;
          }
        }
      }

      // ignore: avoid_print
      print('\n========== palace flag fire rate (n=$n) ==========');
      for (final f in PalaceFlag.values) {
        final rate = flagCounts[f]! * 100.0 / n;
        // ignore: avoid_print
        print('${f.name.padRight(22)} ${rate.toStringAsFixed(2)}%');
      }

      for (final f in PalaceFlag.values) {
        expect(flagCounts[f]! / n, greaterThanOrEqualTo(0.01),
            reason: '${f.name} 발동률 < 1% — 임계가 너무 빡빡');
      }
    });
  });
}
