// Chemistry Battle 집계 엔진 검증 — 스펙 §5/§6.3:
// 쌍 수 · a<b 정규화 · 정렬=순위(raw total desc) · tie-break 결정론 ·
// best = pairs[0] · payload 계약 (점수는 best.score 만, band 0~3).
//
// 실행: flutter test test/battle_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/compat/battle.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
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

FaceReadingReport _fakeReport(
  Random rng, {
  required Gender gender,
  required AgeGroup age,
}) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final lateralZ = <String, double>{};
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    lateralZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree({...frontalZ, ...lateralZ});
  final nodeScores = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    nodeScores[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final c in node.children) {
      walk(c);
    }
  }

  walk(tree);
  final metrics = <String, MetricResult>{
    for (final info in metricInfoList)
      info.id: MetricResult(
        id: info.id,
        rawValue: 0.0,
        zScore: frontalZ[info.id]!,
        zAdjusted: frontalZ[info.id]!,
        metricScore: 0,
      ),
  };
  final attributes = <Attribute, AttributeEvidence>{
    for (final a in Attribute.values)
      a: AttributeEvidence(
        rawTotal: 0.0,
        normalizedScore: 7.5,
        basePerNode: const {},
        distinctiveness: 0.0,
        contributors: const [],
      ),
  };
  final flat = {for (final a in Attribute.values) a: 7.5};
  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime(2026, 7, 16),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, gender, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
}

List<BattlePlayer> _players(int n, {int seed = 42}) {
  final rng = Random(seed);
  return [
    for (int i = 0; i < n; i++)
      BattlePlayer(
        slot: i + 1,
        name: '플레이어$i',
        gender: i.isEven ? 'male' : 'female',
        report: _fakeReport(
          rng,
          gender: i.isEven ? Gender.male : Gender.female,
          age: AgeGroup.values[i % 5],
        ),
      ),
  ];
}

void main() {
  test('쌍 수 = N(N-1)/2, 모든 쌍은 a < b 정규화', () {
    final result = computeBattle(_players(4));
    expect(result.pairs.length, 6);
    for (final p in result.pairs) {
      expect(p.a < p.b, isTrue);
    }
  });

  test('정렬 = 순위 — pairs 는 raw total 내림차순, best = pairs[0]', () {
    final result = computeBattle(_players(6));
    for (int i = 1; i < result.pairs.length; i++) {
      expect(
        result.pairs[i - 1].total >= result.pairs[i].total,
        isTrue,
      );
    }
    expect(identical(result.best, result.pairs.first), isTrue);
  });

  test('결정론 — 같은 입력은 항상 같은 payload', () {
    final players = _players(6);
    final a = computeBattle(players).toPayload();
    final b = computeBattle(players).toPayload();
    expect(a, equals(b));
  });

  test('tie-break 비교자 — total 동점이면 (a, b) 사전순, 공동 수상 없음', () {
    BattlePair pair(int a, int b, double total) =>
        BattlePair(a: a, b: b, total: total, label: CompatLabel.mahapgaseong);
    // total 다르면 내림차순.
    expect(battlePairCompare(pair(1, 2, 90), pair(3, 4, 80)) < 0, isTrue);
    expect(battlePairCompare(pair(1, 2, 80), pair(3, 4, 90)) > 0, isTrue);
    // 완전 동점 → a 오름차순 → b 오름차순.
    expect(battlePairCompare(pair(1, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    expect(battlePairCompare(pair(2, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    // 동일 쌍은 0.
    expect(battlePairCompare(pair(2, 4, 85), pair(2, 4, 85)), 0);
  });

  test('payload 계약 — players/pairs/best 만, pairs 에 점수 없음, band 0~3', () {
    final result = computeBattle(_players(4));
    final payload = result.toPayload();
    expect(payload.keys.toSet(), {'players', 'pairs', 'best'});

    final players = payload['players'] as List;
    expect(players.length, 4);
    for (final p in players) {
      expect((p as Map).keys.toSet(), {'slot', 'name', 'gender'});
    }

    final pairs = payload['pairs'] as List;
    expect(pairs.length, 6);
    for (final p in pairs) {
      expect((p as Map).keys.toSet(), {'a', 'b', 'band'});
      expect(p['band'], inInclusiveRange(0, 3));
    }

    final best = payload['best'] as Map;
    expect(best.keys.toSet(), {'a', 'b', 'score'});
    expect(best['score'], result.best.total.round());
    expect(best['a'], result.pairs.first.a);
    expect(best['b'], result.pairs.first.b);
  });

  test('matchOnly — pairs 수 = 남수 × 여수', () {
    final players = _players(6); // 짝수 slot(1,3,5) male, 홀수(2,4,6) female.
    final maleCount = players.where((p) => p.gender == 'male').length;
    final femaleCount = players.where((p) => p.gender == 'female').length;
    final result = computeBattle(players, matchOnly: true);
    expect(result.pairs.length, maleCount * femaleCount);
  });

  test('matchOnly — 모든 쌍이 이성, 동성 쌍은 존재하지 않음', () {
    final players = _players(8);
    final genderBySlot = {for (final p in players) p.slot: p.gender};
    final result = computeBattle(players, matchOnly: true);
    for (final pair in result.pairs) {
      expect(genderBySlot[pair.a], isNot(equals(genderBySlot[pair.b])));
    }
  });

  test('payload — players[].gender 키 존재', () {
    final result = computeBattle(_players(4));
    final payload = result.toPayload();
    final players = payload['players'] as List;
    for (final p in players) {
      expect((p as Map)['gender'], anyOf('male', 'female'));
    }
  });

  test('all 모드(matchOnly 기본값 false) — pairs 수 N(N-1)/2 유지, 동성 쌍 포함', () {
    final players = _players(6);
    final result = computeBattle(players);
    expect(result.pairs.length, 6 * 5 ~/ 2);
    final genderBySlot = {for (final p in players) p.slot: p.gender};
    expect(
      result.pairs.any((p) => genderBySlot[p.a] == genderBySlot[p.b]),
      isTrue,
    );
  });
}
