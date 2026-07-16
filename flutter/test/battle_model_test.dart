// Battle 모델 파싱·에러 매핑·플레이어 조립 검증 — Plan 1 서버 계약과의 접점.
// 실행: flutter test test/battle_model_test.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/models/battle.dart';
import 'package:facely/domain/services/mc_fixtures.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

FaceReadingReport _fakeReport(Random rng) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree(frontalZ);
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
        rawValue: 0.5,
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
    gender: Gender.female,
    ageGroup: AgeGroup.twenties,
    timestamp: DateTime(2026, 7, 16),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, Gender.female, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
}

void main() {
  test('Battle.fromRow — teams row 파싱 (snake_case, nullable 전부)', () {
    final battle = Battle.fromRow({
      'id': 'b1',
      'owner_id': 'u1',
      'title': '영화보러가자!',
      'visibility': 'public',
      'max_players': 8,
      'age_min': 20,
      'age_max': 30,
      'pledge': '🎬 영화',
      'chat_url': 'https://open.kakao.com/o/x',
      'status': 'recruiting',
      'started_at': null,
      'closed_at': null,
      'chemistry_snapshot': null,
      'result_payload': null,
      'created_at': '2026-07-16T09:00:00Z',
    });
    expect(battle.id, 'b1');
    expect(battle.isPublic, isTrue);
    expect(battle.status, BattleStatus.recruiting);
    expect(battle.isRecruiting, isTrue);
    expect(battle.hasResult, isFalse);
    expect(battle.ageRangeLabel, '20~39세');
  });

  test('ageRangeLabel — 전연령·단일 decade·범위', () {
    Battle b(int? lo, int? hi) => Battle.fromRow({
          'id': 'x',
          'owner_id': null,
          'title': 't',
          'visibility': 'private',
          'max_players': 4,
          'age_min': lo,
          'age_max': hi,
          'pledge': null,
          'chat_url': null,
          'status': 'expired',
          'started_at': null,
          'closed_at': null,
          'chemistry_snapshot': null,
          'result_payload': null,
          'created_at': '2026-07-16T09:00:00Z',
        });
    expect(b(null, null).ageRangeLabel, '전연령');
    expect(b(30, 30).ageRangeLabel, '30대');
    expect(b(20, 30).ageRangeLabel, '20~39세');
    expect(b(40, 50).ageRangeLabel, '40~59세');
  });

  test('BattleRosterEntry / PublicBattle fromRow', () {
    final entry = BattleRosterEntry.fromRow({
      'team_id': 'b1',
      'user_id': 'u2',
      'slot_no': 3,
      'is_owner': false,
      'joined_at': '2026-07-16T09:10:00Z',
      'nickname': '철수',
    });
    expect(entry.slotNo, 3);
    expect(entry.nickname, '철수');

    final pub = PublicBattle.fromRow({
      'id': 'b1',
      'title': '점심 케미 배틀',
      'max_players': 6,
      'age_min': null,
      'age_max': null,
      'pledge': null,
      'created_at': '2026-07-16T09:00:00Z',
      'player_count': 2,
    });
    expect(pub.playerCount, 2);
    expect(pub.ageRangeLabel, '전연령');
  });

  test('mapBattleError — 서버 에러 계약 문자열 매핑', () {
    expect(
      mapBattleError(const PostgrestException(message: 'BAD_PASSWORD')),
      BattleJoinError.badPassword,
    );
    expect(
      mapBattleError(const PostgrestException(message: 'AGE_NOT_ALLOWED')),
      BattleJoinError.ageNotAllowed,
    );
    expect(
      mapBattleError(const PostgrestException(message: 'FULL')),
      BattleJoinError.full,
    );
    expect(
      mapBattleError(Exception('boom')),
      BattleJoinError.unknown,
    );
    // 모든 값이 한국어 라벨을 가진다 (빈 문자열 금지).
    for (final e in BattleJoinError.values) {
      expect(e.labelKo, isNotEmpty);
    }
  });

  test('assembleBattlePlayers — roster+snapshot → slot 오름차순 BattlePlayer', () {
    final rng = Random(42);
    final bodyA = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    final bodyB = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    final roster = [
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u2', 'slot_no': 2,
        'is_owner': false, 'joined_at': '2026-07-16T09:10:00Z', 'nickname': '영희',
      }),
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u1', 'slot_no': 1,
        'is_owner': true, 'joined_at': '2026-07-16T09:00:00Z', 'nickname': '지은',
      }),
    ];
    final players = assembleBattlePlayers(
      roster: roster,
      snapshot: {'u1': bodyA, 'u2': bodyB},
    );
    expect(players.length, 2);
    expect(players.first.slot, 1);
    expect(players.first.name, '지은');
    expect(players.last.slot, 2);
    // snapshot 에 없는 참가자는 제외 (계정 삭제 등 극단 케이스 방어).
    final partial = assembleBattlePlayers(
      roster: roster,
      snapshot: {'u1': bodyA},
    );
    expect(partial.length, 1);
  });
}
