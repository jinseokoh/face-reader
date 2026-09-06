// Chemistry Team 집계 엔진 검증 — 스펙 §5/§6.3:
// 쌍 수 · a<b 정규화 · 정렬=순위(raw total desc) · tie-break 결정론 ·
// best = pairs[0] · payload 계약 (점수는 best.score 만, band 0~3).
//
// 실행: flutter test test/team_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/compat/team.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'support/fake_report.dart';

List<TeamPlayer> _players(int n, {int seed = 42}) {
  final rng = Random(seed);
  return [
    for (int i = 0; i < n; i++)
      TeamPlayer(
        slot: i + 1,
        name: '플레이어$i',
        gender: i.isEven ? 'male' : 'female',
        report: fakeReport(
          rng,
          gender: i.isEven ? Gender.male : Gender.female,
          age: AgeGroup.values[i % 5],
        ),
      ),
  ];
}

void main() {
  _firstImpressionTeamTests();
  test('쌍 수 = N(N-1)/2, 모든 쌍은 a < b 정규화', () {
    final result = computeTeam(_players(4));
    expect(result.pairs.length, 6);
    for (final p in result.pairs) {
      expect(p.a < p.b, isTrue);
    }
  });

  test('정렬 = 순위 — pairs 는 raw total 내림차순, best = pairs[0]', () {
    final result = computeTeam(_players(6));
    for (int i = 1; i < result.pairs.length; i++) {
      expect(result.pairs[i - 1].total >= result.pairs[i].total, isTrue);
    }
    expect(identical(result.best, result.pairs.first), isTrue);
  });

  test('결정론 — 같은 입력은 항상 같은 payload', () {
    final players = _players(6);
    final a = computeTeam(players).toPayload();
    final b = computeTeam(players).toPayload();
    expect(a, equals(b));
  });

  test('tie-break 비교자 — total 동점이면 (a, b) 사전순, 공동 수상 없음', () {
    TeamPair pair(int a, int b, double total) =>
        TeamPair(a: a, b: b, total: total, band: CompatLabel.mahapgaseong.index);
    // total 다르면 내림차순.
    expect(teamPairCompare(pair(1, 2, 90), pair(3, 4, 80)) < 0, isTrue);
    expect(teamPairCompare(pair(1, 2, 80), pair(3, 4, 90)) > 0, isTrue);
    // 완전 동점 → a 오름차순 → b 오름차순.
    expect(teamPairCompare(pair(1, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    expect(teamPairCompare(pair(2, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    // 동일 쌍은 0.
    expect(teamPairCompare(pair(2, 4, 85), pair(2, 4, 85)), 0);
  });

  test('payload 계약 — players/pairs 만, pairs 에 band 0~3 + score', () {
    final result = computeTeam(_players(4));
    final payload = result.toPayload();
    expect(payload.keys.toSet(), {'players', 'pairs'});

    final players = payload['players'] as List;
    expect(players.length, 4);
    for (final p in players) {
      expect((p as Map).keys.toSet(), {'slot', 'name', 'gender'});
    }

    // best 는 별도 키가 아니라 정렬(=순위)에서 파생 — blocked 아닌 첫 쌍.
    final pairs = payload['pairs'] as List;
    expect(pairs.length, 6);
    for (final p in pairs) {
      expect((p as Map).keys.toSet(), {'a', 'b', 'band', 'score'});
      expect(p['band'], inInclusiveRange(0, 3));
      expect(p['score'], inInclusiveRange(0, 100));
    }
    final first = pairs.first as Map;
    expect(first['a'], result.best.a);
    expect(first['b'], result.best.b);
    expect(first['score'], result.best.total.round());
  });

  test('matchOnly — pairs 수 = 남수 × 여수', () {
    final players = _players(6); // 짝수 slot(1,3,5) male, 홀수(2,4,6) female.
    final maleCount = players.where((p) => p.gender == 'male').length;
    final femaleCount = players.where((p) => p.gender == 'female').length;
    final result = computeTeam(players, matchOnly: true);
    expect(result.pairs.length, maleCount * femaleCount);
  });

  test('matchOnly — 모든 쌍이 이성, 동성 쌍은 존재하지 않음', () {
    final players = _players(8);
    final genderBySlot = {for (final p in players) p.slot: p.gender};
    final result = computeTeam(players, matchOnly: true);
    for (final pair in result.pairs) {
      expect(genderBySlot[pair.a], isNot(equals(genderBySlot[pair.b])));
    }
  });

  test('payload — players[].gender 키 존재', () {
    final result = computeTeam(_players(4));
    final payload = result.toPayload();
    final players = payload['players'] as List;
    for (final p in players) {
      expect((p as Map)['gender'], anyOf('male', 'female'));
    }
  });

  test('차단 쌍 — 상한 60점·형극난조 확정·베스트 제외, 다른 쌍은 불변', () {
    final players = _players(6);
    final open = computeTeam(players);
    final key = teamPairKey(open.best.a, open.best.b);
    final result = computeTeam(players, blockedKeys: {key});

    final blockedPair = result.pairs.firstWhere(
      (p) => teamPairKey(p.a, p.b) == key,
    );
    expect(blockedPair.blocked, isTrue);
    expect(blockedPair.total, lessThanOrEqualTo(kTeamBlockCap));
    expect(blockedPair.band, CompatLabel.hyeonggeuknanjo.index);
    expect(teamPairKey(result.best.a, result.best.b), isNot(key));

    for (final p in result.pairs.where((p) => !p.blocked)) {
      final original = open.pairs.firstWhere((o) => o.a == p.a && o.b == p.b);
      expect(p.total, original.total);
      expect(p.band, original.band);
    }
  });

  test('기채팅 쌍 — 실점수·등급 유지, 베스트만 제외, payload bypass 마킹', () {
    final players = _players(6);
    final open = computeTeam(players);
    final key = teamPairKey(open.best.a, open.best.b);
    final result = computeTeam(players, chattedKeys: {key});

    final chattedPair = result.pairs.firstWhere(
      (p) => teamPairKey(p.a, p.b) == key,
    );
    final original = open.pairs.firstWhere(
      (p) => teamPairKey(p.a, p.b) == key,
    );
    expect(chattedPair.chatted, isTrue);
    expect(chattedPair.blocked, isFalse);
    expect(chattedPair.bypass, isTrue);
    expect(chattedPair.total, original.total);
    expect(chattedPair.band, original.band);
    expect(teamPairKey(result.best.a, result.best.b), isNot(key));

    final payloadPairs = result.toPayload()['pairs'] as List;
    final marked = (payloadPairs.cast<Map>()).firstWhere(
      (p) => teamPairKey(p['a'] as int, p['b'] as int) == key,
    );
    expect(marked['bypass'], isTrue);
    expect(marked['score'], original.total.round());
  });

  test('전 쌍 차단 극단 — best 는 pairs.first 로 후퇴', () {
    const pairs = [
      TeamPair(
        a: 1,
        b: 2,
        total: 60,
        band: 3,
        blocked: true,
      ),
    ];
    const result = TeamResult(players: [], pairs: pairs);
    expect(identical(result.best, pairs.first), isTrue);
  });

  test('all 모드(matchOnly 기본값 false) — pairs 수 N(N-1)/2 유지, 동성 쌍 포함', () {
    final players = _players(6);
    final result = computeTeam(players);
    expect(result.pairs.length, 6 * 5 ~/ 2);
    final genderBySlot = {for (final p in players) p.slot: p.gender};
    expect(
      result.pairs.any((p) => genderBySlot[p.a] == genderBySlot[p.b]),
      isTrue,
    );
  });
}

// ── 첫인상 케미 방 (teams.mode = first_impression) ──
void _firstImpressionTeamTests() {
  test('첫인상 채점 — score 0~300, band 0~3, 쌍마다 sim·harm·comp, root mode', () {
    final result = computeTeam(
      _players(6),
      scoring: TeamScoring.firstImpression,
    );
    expect(result.mode, TeamChemistryMode.firstImpression);
    final payload = result.toPayload();
    expect(payload['mode'], 'first_impression');
    for (final p in (payload['pairs'] as List).cast<Map>()) {
      expect(p.keys.toSet(), {'a', 'b', 'band', 'score', 'sim', 'harm', 'comp'});
      expect(p['score'], inInclusiveRange(0, 300));
      expect(p['band'], inInclusiveRange(0, 3));
      final parts = (p['sim'] as int) + (p['harm'] as int) + (p['comp'] as int);
      expect((p['score'] as int) - parts, inInclusiveRange(-2, 2));
    }
    for (int i = 1; i < result.pairs.length; i++) {
      expect(result.pairs[i - 1].total >= result.pairs[i].total, isTrue);
    }
  });

  test('첫인상 차단 — 상한은 p25 바로 아래(131.0), 등급은 최하(3)', () {
    final players = _players(6);
    final open = computeTeam(players, scoring: TeamScoring.firstImpression);
    final key = teamPairKey(open.best.a, open.best.b);
    final result = computeTeam(
      players,
      scoring: TeamScoring.firstImpression,
      blockedKeys: {key},
    );
    final blockedPair = result.pairs.firstWhere((p) => teamPairKey(p.a, p.b) == key);
    expect(blockedPair.total, lessThanOrEqualTo(kTeamBlockCapFirstImpression));
    expect(blockedPair.band, 3);
    expect(teamPairKey(result.best.a, result.best.b), isNot(key));
  });

  test('관상 payload 는 mode 키가 없다 (계약 불변)', () {
    final payload = computeTeam(_players(4)).toPayload();
    expect(payload.containsKey('mode'), isFalse);
  });
}
