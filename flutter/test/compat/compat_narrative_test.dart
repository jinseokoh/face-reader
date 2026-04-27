// Narrative smoke — 5-section 분석가 리포트 format 검증.
//
//   (1) 같은 입력이면 동일 output (결정성)
//   (2) 필드 5 개 전부 non-empty + 최소 길이
//   (3) 금지어 없음 (한자 남발·추상 표현·레거시 단어)
//
// 실행:
//   flutter test test/compat/compat_narrative_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_reader/domain/services/compat/compat_narrative.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/mc_fixtures.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

CompatPersonInput _sample(Random rng, {Gender? gender, AgeGroup? age}) {
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
  group('CompatNarrative 5-section', () {
    test('결정적 — 같은 입력이면 같은 결과', () {
      final rng = Random(123);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);

      final n1 = buildCompatNarrative(report: r, pairSeed: 987654321);
      final n2 = buildCompatNarrative(report: r, pairSeed: 987654321);
      expect(n1.sectionsInOrder, n2.sectionsInOrder);
      expect(n1.sectionsInOrder.length, 5);
    });

    test('모든 section non-empty + 최소 길이', () {
      final rng = Random(7);
      final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);
      final n = buildCompatNarrative(report: r, pairSeed: 42);

      expect(n.summary.length, greaterThanOrEqualTo(40));
      expect(n.corePoints.length, greaterThanOrEqualTo(80));
      // 갈등·전략 섹션은 3부 구조(도입 + per-item 근거/궤적/폭발·실행/실패 +
      // 마무리)로 농후해졌으므로 이전 대비 약 2 배 길이를 요구한다.
      expect(n.conflictScenarios.length, greaterThanOrEqualTo(200));
      expect(n.strategy.length, greaterThanOrEqualTo(250));
      expect(n.scoreReason.length, greaterThanOrEqualTo(80));
    });

    test('금지어 없음 — 한자 어구·추상 표현·레거시', () {
      // 한자는 괄호 안 보조 풀이만 허용(예: "명궁(命宮)"). 따라서 개별
      // 한자 문자는 검사하지 않고, 본문 흐름에 남발되면 안 되는 한자 어구와
      // 추상 표현, 레거시 관련 단어만 검사한다.
      const forbiddenStrings = [
        '雙聳', '雙峻', '雙厚', '雙薄', '剛柔相濟', '上停', '下停', '中停',
        '宮位', '氣質', '五形和', '情性',
        '기운이 흐른다', '조화를 이룬다', '서로를 비추', '깊은 울림',
        '레거시', '마이그레이션', 'legacy', '기존 구현', '예전',
      ];
      final rng = Random(10);
      for (int i = 0; i < 20; i++) {
        final a = _sample(rng, gender: Gender.male, age: AgeGroup.thirties);
        final b = _sample(rng, gender: Gender.female, age: AgeGroup.forties);
        final r = analyzeCompatibility(my: a, album: b);
        final n = buildCompatNarrative(report: r, pairSeed: i * 37 + 5);

        for (final s in n.sectionsInOrder) {
          for (final fb in forbiddenStrings) {
            expect(s.contains(fb), false,
                reason: '금지어/금지표현 "$fb" 가 narrative 에 포함: $s');
          }
        }
      }
    });

    test('same-sex — intimacy 없이도 5 섹션 모두 출력', () {
      final rng = Random(8);
      final a = _sample(rng, gender: Gender.female, age: AgeGroup.thirties);
      final b = _sample(rng, gender: Gender.female, age: AgeGroup.thirties);
      final r = analyzeCompatibility(my: a, album: b);
      expect(r.intimacy.gateActive, false);
      final n = buildCompatNarrative(report: r, pairSeed: 42);
      expect(n.sectionsInOrder.length, 5);
      expect(n.scoreReason.contains('친밀'), true);
    });
  });
}
