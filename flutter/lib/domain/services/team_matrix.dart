import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';

/// 교감도 매트릭스 계산 — PIVOT A4/A7.
///
/// 기존 궁합 엔진을 멤버 모든 쌍 N(N-1)/2 회 호출하는 순수 함수 래퍼.
/// total 은 엔진이 대칭을 보장(§8.2 #3)하므로 (a,b)와 (b,a)는 같은 값 —
/// 한 방향만 계산해 양방향에 쓴다. 엔진이 결정론적이라 같은 멤버 구성은
/// 항상 같은 매트릭스를 낸다 (capture-only: 저장하지 않고 매번 재계산).
class TeamPair {
  final FaceReadingReport a;
  final FaceReadingReport b;
  final double total;
  final CompatLabel label;

  const TeamPair({
    required this.a,
    required this.b,
    required this.total,
    required this.label,
  });
}

class TeamMatrix {
  final List<FaceReadingReport> members;
  final Map<String, TeamPair> _pairs;

  /// 🏆 베스트 — 최고 표시 점수(xx점) 그룹. 동점자 모두 포함, 점수 내림차순.
  final List<TeamPair> bests;

  /// 😲 버금가는 케미 — 두 번째 표시 점수 그룹. 동점자 모두 포함. 없으면 빈 리스트.
  final List<TeamPair> surprises;

  const TeamMatrix._({
    required this.members,
    required Map<String, TeamPair> pairs,
    required this.bests,
    required this.surprises,
  }) : _pairs = pairs;

  /// 베스트 대표(최고 총점) — 홈 티저 등 단일 페어가 필요한 곳.
  TeamPair get best => bests.first;

  /// 버금가는 대표 — 없으면 null.
  TeamPair? get surprise => surprises.isEmpty ? null : surprises.first;

  static String _keyOf(String idA, String idB) =>
      idA.compareTo(idB) <= 0 ? '$idA~$idB' : '$idB~$idA';

  TeamPair? pairOf(FaceReadingReport a, FaceReadingReport b) {
    final idA = a.supabaseId;
    final idB = b.supabaseId;
    if (idA == null || idB == null) return null;
    return _pairs[_keyOf(idA, idB)];
  }

  List<TeamPair> get allPairs => _pairs.values.toList();
}

/// [members] 는 supabaseId 가 있는 리포트 2개 이상이어야 한다.
/// (min 3 / cap 12 의 인원 정책 게이트는 UI — 방 화면/provider — 책임.)
TeamMatrix computeTeamMatrix(List<FaceReadingReport> members) {
  final valid = [
    for (final m in members)
      if (m.supabaseId != null) m,
  ];
  assert(valid.length >= 2, 'team matrix 는 멤버 2명 이상 필요');

  final pairs = <String, TeamPair>{};
  final all = <TeamPair>[];
  for (int i = 0; i < valid.length; i++) {
    for (int j = i + 1; j < valid.length; j++) {
      final a = valid[i];
      final b = valid[j];
      final report = analyzeCompatibility(
        my: reportToCompatInput(a),
        album: reportToCompatInput(b),
      );
      final pair = TeamPair(
        a: a,
        b: b,
        total: report.total,
        label: report.label,
      );
      pairs[TeamMatrix._keyOf(a.supabaseId!, b.supabaseId!)] = pair;
      all.add(pair);
    }
  }
  all.sort((x, y) => y.total.compareTo(x.total));

  // 표시 점수(xx점 = total 반올림) 기준 그룹핑 — 같은 점수 동점자는 모두 포함.
  // 베스트 = 1위 점수 그룹, 버금가는 = 2위(그보다 낮은 첫) 점수 그룹.
  int scoreOf(TeamPair p) => p.total.round();
  final bests = <TeamPair>[];
  final surprises = <TeamPair>[];
  if (all.isNotEmpty) {
    final topScore = scoreOf(all.first);
    bests.addAll(all.where((p) => scoreOf(p) == topScore));
    final rest = all.where((p) => scoreOf(p) < topScore).toList();
    if (rest.isNotEmpty) {
      final secondScore = scoreOf(rest.first);
      surprises.addAll(rest.where((p) => scoreOf(p) == secondScore));
    }
  }
  return TeamMatrix._(
    members: valid,
    pairs: pairs,
    bests: bests,
    surprises: surprises,
  );
}
