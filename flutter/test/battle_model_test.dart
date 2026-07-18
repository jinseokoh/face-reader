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
      'is_private': false,
      'max_players': 8,
      'age_min': 20,
      'age_max': 30,
      'room_kind': 'all',
      'thumb_open': false,
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
    expect(battle.ageRangeLabel, '20대~30대');
    expect(battle.roomKind, BattleRoomKind.all);
    expect(battle.thumbOpen, isFalse);
  });

  test('Battle.fromRow — room_kind=match·thumb_open=true 파싱', () {
    final battle = Battle.fromRow({
      'id': 'b2',
      'owner_id': 'u1',
      'title': '이성 케미방',
      'is_private': true,
      'max_players': 8,
      'age_min': 20,
      'age_max': 30,
      'room_kind': 'match',
      'thumb_open': true,
      'status': 'recruiting',
      'started_at': null,
      'closed_at': null,
      'chemistry_snapshot': null,
      'result_payload': null,
      'created_at': '2026-07-16T09:00:00Z',
    });
    expect(battle.roomKind, BattleRoomKind.match);
    expect(battle.thumbOpen, isTrue);
  });

  test('ageRangeLabel — 전연령·단일 decade·범위', () {
    Battle b(int? lo, int? hi) => Battle.fromRow({
          'id': 'x',
          'owner_id': null,
          'title': 't',
          'is_private': true,
          'max_players': 4,
          'age_min': lo,
          'age_max': hi,
          'room_kind': 'all',
          'thumb_open': false,
          'status': 'expired',
          'started_at': null,
          'closed_at': null,
          'chemistry_snapshot': null,
          'result_payload': null,
          'created_at': '2026-07-16T09:00:00Z',
        });
    expect(b(null, null).ageRangeLabel, '전연령');
    expect(b(30, 30).ageRangeLabel, '30대');
    expect(b(20, 30).ageRangeLabel, '20대~30대');
    expect(b(40, 50).ageRangeLabel, '40대~50대');
  });

  test('BattleRosterEntry / PublicBattle fromRow', () {
    final entry = BattleRosterEntry.fromRow({
      'team_id': 'b1',
      'user_id': 'u2',
      'slot_no': 3,
      'gender': 'female',
      'is_owner': false,
      'joined_at': '2026-07-16T09:10:00Z',
      'nickname': '철수',
    });
    expect(entry.slotNo, 3);
    expect(entry.nickname, '철수');
    expect(entry.gender, 'female');

    final pub = PublicBattle.fromRow({
      'id': 'b1',
      'title': '점심 케미 배틀',
      'max_players': 6,
      'age_min': null,
      'age_max': null,
      'room_kind': 'match',
      'thumb_open': true,
      'created_at': '2026-07-16T09:00:00Z',
      'player_count': 2,
    });
    expect(pub.playerCount, 2);
    expect(pub.ageRangeLabel, '전연령');
    expect(pub.roomKind, BattleRoomKind.match);
    expect(pub.thumbOpen, isTrue);
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
      mapBattleError(const PostgrestException(message: 'GENDER_FULL')),
      BattleJoinError.genderFull,
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

  test('genderFullLabel — 본인 성별로 분기', () {
    expect(genderFullLabel('male'), '남자 자리가 다 찼습니다');
    expect(genderFullLabel('female'), '여자 자리가 다 찼습니다');
  });

  test('BattleMatch.fromRow — consent·isOpen·consentOf·otherOf', () {
    final pending = BattleMatch.fromRow({
      'team_id': 'b1',
      'user_a': 'u1',
      'user_b': 'u2',
      'a_consent': null,
      'b_consent': null,
      'opened_at': null,
    });
    expect(pending.isOpen, isFalse);
    expect(pending.consentOf('u1'), isNull);
    expect(pending.consentOf('u3'), isNull);
    expect(pending.otherOf('u1'), 'u2');
    expect(pending.otherOf('u2'), 'u1');

    final open = BattleMatch.fromRow({
      'team_id': 'b1',
      'user_a': 'u1',
      'user_b': 'u2',
      'a_consent': true,
      'b_consent': true,
      'opened_at': '2026-07-16T09:20:00Z',
    });
    expect(open.isOpen, isTrue);
    expect(open.consentOf('u1'), isTrue);
    expect(open.consentOf('u2'), isTrue);
  });

  test('BattleMessage.fromRow', () {
    final message = BattleMessage.fromRow({
      'id': 'm1',
      'team_id': 'b1',
      'sender_id': 'u1',
      'body': '안녕하세요',
      'created_at': '2026-07-16T09:30:00Z',
    });
    expect(message.id, 'm1');
    expect(message.senderId, 'u1');
    expect(message.body, '안녕하세요');
  });

  test('assembleBattlePlayers — roster+snapshot → slot 오름차순 BattlePlayer', () {
    final rng = Random(42);
    final bodyA = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    final bodyB = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    // roster gender 는 report.gender(항상 female, _fakeReport 고정값)와
    // 일부러 어긋나게 둔다 — gender 소스가 roster 임을 증명.
    final roster = [
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u2', 'slot_no': 2, 'gender': 'female',
        'is_owner': false, 'joined_at': '2026-07-16T09:10:00Z', 'nickname': '영희',
      }),
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u1', 'slot_no': 1, 'gender': 'male',
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
    // gender 는 roster(서버 강제값) 소스 — report.gender(female)와 무관.
    expect(players.first.gender, 'male');
    expect(players.last.slot, 2);
    expect(players.last.gender, 'female');
    // snapshot 에 없는 참가자는 제외 (계정 삭제 등 극단 케이스 방어).
    final partial = assembleBattlePlayers(
      roster: roster,
      snapshot: {'u1': bodyA},
    );
    expect(partial.length, 1);
  });
}
