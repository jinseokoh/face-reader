import 'package:face_engine/data/constants/model_version.dart';
import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';
import 'package:face_engine/domain/services/first_impression.dart';

/// Chemistry Team 집계 — 스펙 2026-07-16-chemistry-team-design §5/§6.
///
/// 쌍 채점기([TeamScoring])를 모든 쌍 N(N-1)/2 회 호출해 정렬한다. 채점기는
/// 결정론·대칭이라 같은 입력(chemistry_snapshot)은 어느 클라이언트에서든 같은
/// payload 를 낸다. 정렬이 곧 순위(내림차순).
///
/// 채점기는 방의 계산 방식(`teams.mode`)에 따라 둘 중 하나다.
/// - physiognomy: 전통 관상 궁합 엔진 total(0~100) + 4단 등급.
/// - firstImpression: 조화도 + 보완도 + 닮은 정도 (0~300, APPLE.md §81.4).
///   등급은 AAF 무작위 쌍 분포의 사분위.
class TeamPlayer {
  final int slot;
  final String name;

  /// 'male' | 'female' — join_team 조인 시점 my-face body 에서 기록된 값.
  final String gender;
  final FaceReadingReport report;

  const TeamPlayer({
    required this.slot,
    required this.name,
    required this.gender,
    required this.report,
  });
}

/// 케미 계산 방식 — `teams.mode` 의 엔진 표현.
enum TeamChemistryMode {
  physiognomy('physiognomy'),
  firstImpression('first_impression');

  const TeamChemistryMode(this.dbValue);
  final String dbValue;

  static TeamChemistryMode fromDb(String? raw) => values.firstWhere(
        (m) => m.dbValue == raw,
        orElse: () => TeamChemistryMode.physiognomy,
      );
}

/// 차단 쌍 점수 상한(관상) — 형극난조 경계(61.5)에서 여유를 둔 값. 차단 관계가
/// 베스트·매칭 카드로 이어지지 않도록 발표 점수를 최하 등급으로 고정한다.
/// 결과표엔 낮은 점수가 그대로 찍히므로 자기모순(1등인데 채팅 없음)이 없고,
/// 차단당한 쪽에는 "궁합이 나쁘다"로만 보여 차단 사실이 새지 않는다.
const double kTeamBlockCap = 60.0;

/// 첫인상 케미 등급 경계 — AAF 11,800장 무작위 쌍 20,000개의 케미 합
/// (조화도+보완도+닮은 정도) 분포에서 p75 / p50 / p25. 위에서부터 band 0~3.
/// 재생성: 무작위 쌍 분위(seed 11). 차단 상한은 p25 바로 아래 — 최하 등급 확정.
const List<double> kFirstImpressionBandCuts = [165.8, 148.0, 131.1];
const double kTeamBlockCapFirstImpression = 131.0;

/// 무방향 쌍의 정규화 키 — blocked·chatted 집합·조회 공용.
String teamPairKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

/// 쌍 채점 결과 — total 과 등급(band 0~3), 그리고 방식별 성분.
class TeamPairScore {
  final double total;
  final int band;

  /// 첫인상: {'sim','harm','comp'} (닮은 정도·조화도·보완도). 관상: 없음.
  final Map<String, double> extras;

  const TeamPairScore({
    required this.total,
    required this.band,
    this.extras = const {},
  });
}

typedef TeamPairScorer = TeamPairScore Function(
    FaceReadingReport a, FaceReadingReport b);

/// 방식별 채점기 + 차단 상한 + total→등급 함수 묶음.
class TeamScoring {
  final TeamChemistryMode mode;
  final TeamPairScorer score;
  final double blockCap;
  final int Function(double total) bandOf;

  const TeamScoring._({
    required this.mode,
    required this.score,
    required this.blockCap,
    required this.bandOf,
  });

  static final TeamScoring physiognomy = TeamScoring._(
    mode: TeamChemistryMode.physiognomy,
    score: _physiognomyPairScore,
    blockCap: kTeamBlockCap,
    bandOf: (t) => classifyLabel(t).index,
  );

  static final TeamScoring firstImpression = TeamScoring._(
    mode: TeamChemistryMode.firstImpression,
    score: _firstImpressionPairScore,
    blockCap: kTeamBlockCapFirstImpression,
    bandOf: firstImpressionBand,
  );

  /// 방의 mode 로 고른다. measure 에디션 클라이언트는 이 함수 대신
  /// [firstImpression] 을 상수 분기로 직접 넘겨 관상 채점기가 빌드에서 빠지게 한다.
  static TeamScoring forMode(TeamChemistryMode mode) => switch (mode) {
        TeamChemistryMode.physiognomy => physiognomy,
        TeamChemistryMode.firstImpression => firstImpression,
      };
}

int firstImpressionBand(double total) {
  for (var i = 0; i < kFirstImpressionBandCuts.length; i++) {
    if (total >= kFirstImpressionBandCuts[i]) return i;
  }
  return kFirstImpressionBandCuts.length;
}

TeamPairScore _physiognomyPairScore(FaceReadingReport a, FaceReadingReport b) {
  final report = analyzeCompatibility(
    my: reportToCompatInput(a),
    album: reportToCompatInput(b),
  );
  return TeamPairScore(total: report.total, band: report.label.index);
}

final List<String> _referenceIds = [for (final m in metricInfoList) m.id];

Map<String, double> _zMap(FaceReadingReport r) =>
    {for (final e in r.metrics.entries) e.key: e.value.zScore};

TeamPairScore _firstImpressionPairScore(
    FaceReadingReport a, FaceReadingReport b) {
  final zA = _zMap(a);
  final zB = _zMap(b);
  final pa = computeFirstImpression(zA,
      gender: a.gender,
      referenceMetricIds: _referenceIds,
      symmetryZ: symmetryOverallZ(a.symmetry, a.gender));
  final pb = computeFirstImpression(zB,
      gender: b.gender,
      referenceMetricIds: _referenceIds,
      symmetryZ: symmetryOverallZ(b.symmetry, b.gender));
  final pair = analyzePair(
    zA: zA,
    profileA: pa,
    zB: zB,
    profileB: pb,
    referenceMetricIds: _referenceIds,
  );
  return TeamPairScore(
    total: pair.chemistry,
    band: firstImpressionBand(pair.chemistry),
    extras: {
      'sim': pair.similarity.overall,
      'harm': pair.harmony,
      'comp': pair.complementarity,
    },
  );
}

class TeamPair {
  /// slot_no 양끝 — a < b 정규화 (무방향 쌍의 유일 표현).
  final int a;
  final int b;
  final double total;

  /// 등급 0(최상)~3. 관상 = CompatLabel.index, 첫인상 = 사분위.
  final int band;

  /// 방식별 성분 (첫인상: sim·harm·comp). payload 에 그대로 실린다.
  final Map<String, double> extras;

  /// 차단 쌍 여부 — total 이 상한으로 눌린 상태.
  final bool blocked;

  /// 이미 베스트 매칭으로 채팅까지 한 사이 — 점수·등급은 실제 그대로,
  /// 베스트 자격만 제외 (또 만날 필요가 없다).
  final bool chatted;

  const TeamPair({
    required this.a,
    required this.b,
    required this.total,
    required this.band,
    this.extras = const {},
    this.blocked = false,
    this.chatted = false,
  });

  /// 베스트 자격을 건너뛸 이유 있음 — 차단이든 기채팅이든.
  bool get bypass => blocked || chatted;
}

/// raw total 내림차순 → a 오름차순 → b 오름차순. 완전 동점도 단독 수상
/// (공동 수상 없음 — 연출·공약 회수가 항상 한 쌍을 가리켜야 한다).
int teamPairCompare(TeamPair x, TeamPair y) {
  final byTotal = y.total.compareTo(x.total);
  if (byTotal != 0) return byTotal;
  final byA = x.a.compareTo(y.a);
  if (byA != 0) return byA;
  return x.b.compareTo(y.b);
}

class TeamResult {
  final TeamChemistryMode mode;
  final List<TeamPlayer> players;

  /// teamPairCompare 정렬 완료 — 배열 인덱스가 곧 케미 순위.
  final List<TeamPair> pairs;

  const TeamResult({
    this.mode = TeamChemistryMode.physiognomy,
    required this.players,
    required this.pairs,
  });

  /// bypass 쌍(차단·기채팅)은 베스트 자격이 없다 — 차단은 상한으로 눌려
  /// 사실상 정렬만으로도 밀리지만, 전 쌍이 bypass 인 극단까지 명시 제외로
  /// 보장한다.
  TeamPair get best =>
      pairs.firstWhere((p) => !p.bypass, orElse: () => pairs.first);

  /// teams.result_payload 계약 (§6.3): band 0~3. 쌍마다 score 를 함께 실어
  /// 어드민·웹이 재계산 없이 앱과 같은 숫자를 보여준다. 정렬이 곧 순위라 별도
  /// best 키는 없다 — best = bypass 아닌 첫 쌍 (차단·기채팅 쌍만 bypass: true).
  /// 첫인상 방은 root 에 mode 와 쌍마다 sim·harm·comp 가 붙는다.
  Map<String, dynamic> toPayload() => {
        if (mode != TeamChemistryMode.physiognomy) ...{
          'mode': mode.dbValue,
          'modelVersion': {
            'impression': kImpressionModelVersion,
            'pair': kPairModelVersion,
          },
        },
        'players': [
          for (final p in players)
            {'slot': p.slot, 'name': p.name, 'gender': p.gender},
        ],
        'pairs': [
          for (final p in pairs)
            {
              'a': p.a,
              'b': p.b,
              'band': p.band,
              'score': p.total.round(),
              for (final e in p.extras.entries) e.key: e.value.round(),
              if (p.bypass) 'bypass': true,
            },
        ],
      };
}

/// matchOnly 면 `a.gender != b.gender` 쌍만 계산 (동성 쌍은 pairs 에 존재하지
/// 않음 — rev2 §3). 정렬·tie-break·best 규칙은 두 모드 동일.
/// blockedKeys 는 chemistry_snapshot.blocked 의 [teamPairKey] 집합 —
/// 해당 쌍은 total 을 채점기의 상한으로 눌러 최하 등급을 확정한다.
/// chattedKeys 는 chemistry_snapshot.chatted (이미 베스트 매칭으로 채팅을
/// 연 사이) — 점수·등급은 실제 그대로 두고 베스트 자격만 제외한다.
TeamResult computeTeam(
  List<TeamPlayer> players, {
  TeamScoring? scoring,
  bool matchOnly = false,
  Set<String> blockedKeys = const {},
  Set<String> chattedKeys = const {},
}) {
  assert(players.length >= 2, 'team 은 2명 이상 필요');
  final s = scoring ?? TeamScoring.physiognomy;
  final sorted = [...players]..sort((x, y) => x.slot.compareTo(y.slot));
  final pairs = <TeamPair>[];
  for (int i = 0; i < sorted.length; i++) {
    for (int j = i + 1; j < sorted.length; j++) {
      if (matchOnly && sorted[i].gender == sorted[j].gender) continue;
      final scored = s.score(sorted[i].report, sorted[j].report);
      final key = teamPairKey(sorted[i].slot, sorted[j].slot);
      final blocked = blockedKeys.contains(key);
      final total = blocked && scored.total > s.blockCap
          ? s.blockCap
          : scored.total;
      pairs.add(TeamPair(
        a: sorted[i].slot,
        b: sorted[j].slot,
        total: total,
        band: blocked ? s.bandOf(total) : scored.band,
        extras: scored.extras,
        blocked: blocked,
        chatted: chattedKeys.contains(key),
      ));
    }
  }
  pairs.sort(teamPairCompare);
  // matchOnly 인데 pairs 가 비면 호출부(서버 정원 계약) 위반 — best 접근이
  // StateError 가 되므로 방어는 assert 수준, 실제 방어는 클라이언트 몫.
  assert(pairs.isNotEmpty, 'team pairs 는 비어 있을 수 없다');
  return TeamResult(mode: s.mode, players: sorted, pairs: pairs);
}
