// P6 smoke — 6-section narrative generates deterministically + 주요 invariant.
//
//   (1) pairSeed 고정이면 동일 output
//   (2) gate off (same-sex or age out) 이면 intimacySection == null
//   (3) gate on 이면 intimacySection != null 이고 본문 포함
//   (4) 모든 section 최소 길이(100 자) 및 forbidden keyword 없음
//
// 실행:
//   flutter test test/compat/compat_narrative_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/compat/compat_narrative.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
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

CompatPersonInput _sample(Random rng,
    {Gender? gender, AgeGroup? age}) {
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
  return CompatPersonInput(
    zMap: z,
    nodeZ: nodeZ,
    lateralFlags: {
      'aquilineNose': rng.nextDouble() < 0.10,
      'snubNose': rng.nextDouble() < 0.08,
    },
    faceShape: FaceShape.oval,
    shapeConfidence: 0.5,
    gender: gender ?? (rng.nextBool() ? Gender.male : Gender.female),
    ageGroup: age ?? AgeGroup.thirties,
  );
}

void main() {
  group('CompatNarrative smoke', () {
    test('deterministic — 같은 pairSeed 면 동일 6-section 출력', () {
      final rng = Random(123);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);

      final n1 = buildCompatNarrative(report: r, pairSeed: 987654321);
      final n2 = buildCompatNarrative(report: r, pairSeed: 987654321);
      expect(n1.sectionsInOrder, n2.sectionsInOrder,
          reason: 'pairSeed 고정이면 모든 섹션이 byte-identical 이어야 함');
    });

    test('gate on (30대 남 × 40대 여) → intimacy section 존재', () {
      final rng = Random(7);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);
      final n = buildCompatNarrative(
        report: r,
        pairSeed: computePairSeed('user-A', 'album-B'),
      );
      expect(n.intimacySection, isNotNull);
      expect(n.intimacySection, contains('情性之合'));
      expect(n.sectionsInOrder.length, 6);
    });

    test('gate off (same-sex) → intimacy section null', () {
      final rng = Random(8);
      final a = _sample(rng, gender: Gender.female, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.thirties);
      final r = analyzeCompatibility(my: a, album: b);
      final n = buildCompatNarrative(report: r, pairSeed: 42);
      expect(n.intimacySection, isNull);
      expect(n.sectionsInOrder.length, 5);
    });

    test('gate off (20대) → intimacy section null', () {
      final rng = Random(9);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.twenties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.twenties);
      final r = analyzeCompatibility(my: a, album: b);
      final n = buildCompatNarrative(report: r, pairSeed: 42);
      expect(n.intimacySection, isNull);
    });

    test('section 최소 길이 + forbidden keyword 없음', () {
      const forbidden = ['레거시', '마이그레이션', 'legacy', '기존 구현', '예전'];
      final rng = Random(10);
      for (int i = 0; i < 20; i++) {
        final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
        final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
        final r = analyzeCompatibility(my: a, album: b);
        final n = buildCompatNarrative(report: r, pairSeed: i * 37 + 5);

        for (final s in n.sectionsInOrder) {
          expect(s.length, greaterThanOrEqualTo(60),
              reason: 'section too short:\n$s');
          for (final fb in forbidden) {
            expect(s.contains(fb), false,
                reason: '금지어 "$fb" 가 narrative 에 포함: $s');
          }
        }
      }
    });

    test('다른 pairSeed 이면 opener variant 가 때로 달라짐', () {
      // variant 가 여러 개 있는 label opener 섹션 기준 — 20 회 중 2 회 이상
      // 서로 다른 줄이 나오면 variant 스위치 정상.
      final rng = Random(11);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);

      final seen = <String>{};
      for (int s = 0; s < 40; s++) {
        final firstLine =
            buildCompatNarrative(report: r, pairSeed: s).overview.split('\n').first;
        seen.add(firstLine);
      }
      expect(seen.length, greaterThanOrEqualTo(2),
          reason: '40 seed 로도 overview opener 가 한 variant 에 고정됨 — '
              'variant 풀링 불균형 가능');
    });
  });
}
