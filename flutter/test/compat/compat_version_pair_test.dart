// 궁합 코퍼스 v1/v2 짝 검증.
//
// 확인하는 것:
//   (1) 섹션 6개가 두 버전 모두에서 non-empty 로 나온다.
//   (2) v2 는 v1 이 쓰는 풀을 하나도 참조하지 않는다 — 풀 15개가 전부 짝을
//       갖는지 소스에서 직접 확인한다.
//   (3) v2 톤 규칙 — 제3자 단정·속마음 단정·미래 단정이 v2 출력에 없다.
//
// (3) 은 현재 v2 문장이 v1 복제본이라 실패한다. 문장 작업이 끝나면 green.
// 실패가 곧 "아직 안 고친 섹션이 남았다"는 신호이므로 skip 하지 않는다.
//
// 실행:
//   flutter test test/compat/compat_version_pair_test.dart

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/compat/compat_narrative.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/services/mc_fixtures.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

CompatPersonInput _sample(Random rng, Gender gender, AgeGroup age) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final z = <String, double>{};
  for (final info in metricInfoList) {
    z[info.id] = ((t.bias[info.id] ?? 0.0) + _normal(rng) * 0.85)
        .clamp(-3.5, 3.5)
        .toDouble();
  }
  for (final info in lateralMetricInfoList) {
    z[info.id] ??= ((t.bias[info.id] ?? 0.0) + _normal(rng) * 0.85)
        .clamp(-3.5, 3.5)
        .toDouble();
  }
  final tree = scoreTree(z);
  final nodeZ = <String, double>{};
  void walk(NodeScore n) {
    nodeZ[n.nodeId] = n.ownMeanZ ?? 0.0;
    for (final c in n.children) {
      walk(c);
    }
  }

  walk(tree);
  return CompatPersonInput(
    zMap: z,
    nodeZ: nodeZ,
    lateralFlags: const {},
    faceShape: FaceShape.oval,
    shapeConfidence: 0.5,
    gender: gender,
    ageGroup: age,
  );
}

/// 여러 조합을 돌려 v2 출력을 모은다 — 톤(pure/flirty/spicy)·bucket 이
/// 조합마다 달라서 한 쌍만 보면 spicy 풀이 안 열린다.
List<CompatNarrative> _v2Corpus() {
  final out = <CompatNarrative>[];
  for (var seed = 0; seed < 60; seed++) {
    final rng = Random(seed);
    for (final pair in const [
      (Gender.male, Gender.female),
      (Gender.female, Gender.male),
      (Gender.male, Gender.male),
      (Gender.female, Gender.female),
    ]) {
      final a = _sample(rng, pair.$1, AgeGroup.thirties);
      final b = _sample(rng, pair.$2, AgeGroup.thirties);
      out.add(buildCompatNarrative(
        report: analyzeCompatibility(my: a, album: b),
        pairSeed: seed * 7919 + 13,
        version: CompatVersion.v2,
      ));
    }
  }
  return out;
}

String _compatSrc(String name) =>
    File('../shared/lib/domain/services/compat/$name').readAsStringSync();

void main() {
  group('v1/v2 짝', () {
    test('섹션 6개가 두 버전 모두 non-empty', () {
      final rng = Random(42);
      final a = _sample(rng, Gender.male, AgeGroup.thirties);
      final b = _sample(rng, Gender.female, AgeGroup.forties);
      final r = analyzeCompatibility(my: a, album: b);

      for (final v in CompatVersion.values) {
        final n = buildCompatNarrative(report: r, pairSeed: 555, version: v);
        for (final e in {
          'summary': n.summary,
          'corePoints': n.corePoints,
          'conflictScenarios': n.conflictScenarios,
          'strategy': n.strategy,
          'scoreReason': n.scoreReason,
          'intimacyChapter': n.intimacyChapter,
        }.entries) {
          expect(e.value.trim(), isNotEmpty,
              reason: '$v 의 ${e.key} 가 비어 있다');
        }
      }
    });

    test('풀 15개가 전부 V2 짝을 갖는다', () {
      final decl = RegExp(
          r'(?:const|final)\s+(?:[\w<>,\s?\[\]]|\n)+?\s(\w+)\s*=\s*\{',
          multiLine: true);
      final v1 = decl
          .allMatches(_compatSrc('compat_phrase_pool.dart'))
          .map((m) => m.group(1)!)
          .toSet();
      final v2 = decl
          .allMatches(_compatSrc('compat_phrase_pool_v2.dart'))
          .map((m) => m.group(1)!)
          .toSet();
      expect(v1, isNotEmpty);
      final missing = v1.where((n) => !v2.contains('${n}V2')).toList();
      expect(missing, isEmpty, reason: 'V2 짝이 없는 풀: $missing');
      final orphan = v2.where((n) => !n.endsWith('V2')).toList();
      expect(orphan, isEmpty, reason: 'V2 접미사가 없는 v2 풀: $orphan');
    });

    test('v2 섹션 빌더가 v1 풀을 참조하지 않는다', () {
      final src = _compatSrc('compat_narrative_v2.dart');
      // v1 풀 이름이 V2 접미사 없이 등장하면 잘못 연결된 것.
      final bad = <String>[];
      for (final name in RegExp(
              r'(?:const|final)\s+(?:[\w<>,\s?\[\]]|\n)+?\s(\w+)\s*=\s*\{',
              multiLine: true)
          .allMatches(_compatSrc('compat_phrase_pool.dart'))
          .map((m) => m.group(1)!)) {
        if (RegExp('\\b$name\\b(?!V2)').hasMatch(src)) bad.add(name);
      }
      expect(bad, isEmpty, reason: 'v2 가 v1 풀을 직접 읽는다: $bad');
    });
  });

  group('v2 톤 규칙', () {
    final banned = <String, RegExp>{
      '제3자 단정': RegExp(r'이 남자(는|가)|이 여자(는|가)|이 여성(은|이)'),
      '속마음 단정':
          RegExp(r'아무 생각도|떠오른 적이|무심히 넘기지 못|상상하게|생각이 스쳤'),
      // "받아 주는 쪽" 은 음양 서술에서 의사결정을 수용하는 쪽이라는 뜻이라
      // 제외한다 (compat_finding.dart 의 yinyang 템플릿). 신체와 무관하다.
      '신체 접근': RegExp(r'안기고 싶|몸이 먼저 대답|밀어내지 마|기꺼이 받아'),
      '미래 단정': RegExp(r'평생'),
    };

    for (final e in banned.entries) {
      test('v2 출력에 ${e.key} 없음', () {
        final hits = <String>[];
        for (final n in _v2Corpus()) {
          for (final body in [
            n.summary,
            n.corePoints,
            n.conflictScenarios,
            n.strategy,
            n.scoreReason,
            n.intimacyChapter,
          ]) {
            for (final m in e.value.allMatches(body)) {
              final s = (m.start - 30).clamp(0, body.length);
              final t = (m.end + 50).clamp(0, body.length);
              hits.add(body.substring(s, t).replaceAll('\n', ' '));
            }
          }
        }
        expect(hits, isEmpty,
            reason: '${e.key} ${hits.length}건\n${hits.take(5).join('\n')}');
      });
    }
  });
}
