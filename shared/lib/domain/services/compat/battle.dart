import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';

/// Chemistry Battle 집계 — 스펙 2026-07-16-chemistry-battle-design §5/§6.
///
/// 궁합 엔진을 모든 쌍 N(N-1)/2 회 호출해 정렬한다. 엔진이 결정론·대칭이라
/// 같은 입력(chemistry_snapshot)은 어느 클라이언트에서든 같은 payload 를 낸다.
/// 정렬이 곧 순위(내림차순) — payload 는 점수를 싣지 않는다 (best.score 만,
/// "숫자·풀이 = 유료" 정책).
class BattlePlayer {
  final int slot;
  final String name;

  /// 'male' | 'female' — join_battle 조인 시점 my-face body 에서 기록된 값.
  final String gender;
  final FaceReadingReport report;

  const BattlePlayer({
    required this.slot,
    required this.name,
    required this.gender,
    required this.report,
  });
}

/// 차단 쌍 점수 상한 — 형극난조 경계(61.5)에서 여유를 둔 값. 차단 관계가
/// 베스트·매칭 카드로 이어지지 않도록 발표 점수를 최하 등급으로 고정한다.
/// 결과표엔 낮은 점수가 그대로 찍히므로 자기모순(1등인데 채팅 없음)이 없고,
/// 차단당한 쪽에는 "궁합이 나쁘다"로만 보여 차단 사실이 새지 않는다.
const double kBattleBlockCap = 60.0;

/// 무방향 쌍의 정규화 키 — blocked 집합·조회 공용.
String battlePairKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

class BattlePair {
  /// slot_no 양끝 — a < b 정규화 (무방향 쌍의 유일 표현).
  final int a;
  final int b;
  final double total;
  final CompatLabel label;

  /// 차단 쌍 여부 — total 이 [kBattleBlockCap] 으로 눌린 상태, 베스트 제외.
  final bool blocked;

  const BattlePair({
    required this.a,
    required this.b,
    required this.total,
    required this.label,
    this.blocked = false,
  });
}

/// raw total 내림차순 → a 오름차순 → b 오름차순. 완전 동점도 단독 수상
/// (공동 수상 없음 — 연출·공약 회수가 항상 한 쌍을 가리켜야 한다).
int battlePairCompare(BattlePair x, BattlePair y) {
  final byTotal = y.total.compareTo(x.total);
  if (byTotal != 0) return byTotal;
  final byA = x.a.compareTo(y.a);
  if (byA != 0) return byA;
  return x.b.compareTo(y.b);
}

class BattleResult {
  final List<BattlePlayer> players;

  /// battlePairCompare 정렬 완료 — 배열 인덱스가 곧 케미 순위.
  final List<BattlePair> pairs;

  const BattleResult({required this.players, required this.pairs});

  /// 차단 쌍은 베스트 자격이 없다 — 상한 60점이라 사실상 정렬만으로도
  /// 밀리지만, 전 쌍이 60점 이하인 극단까지 명시 제외로 보장한다.
  BattlePair get best =>
      pairs.firstWhere((p) => !p.blocked, orElse: () => pairs.first);

  /// teams.result_payload 계약 (§6.3): 점수는 best.score 하나뿐,
  /// band = CompatLabel.index (0=천생연분 … 3=형극난조).
  Map<String, dynamic> toPayload() => {
        'players': [
          for (final p in players)
            {'slot': p.slot, 'name': p.name, 'gender': p.gender},
        ],
        'pairs': [
          for (final p in pairs) {'a': p.a, 'b': p.b, 'band': p.label.index},
        ],
        'best': {
          'a': best.a,
          'b': best.b,
          'score': best.total.round(),
        },
      };
}

/// matchOnly 면 `a.gender != b.gender` 쌍만 계산 (동성 쌍은 pairs 에 존재하지
/// 않음 — rev2 §3). 정렬·tie-break·best 규칙은 두 모드 동일.
/// blockedKeys 는 chemistry_snapshot.blocked 의 [battlePairKey] 집합 —
/// 해당 쌍은 total 을 [kBattleBlockCap] 으로 눌러 형극난조를 확정한다.
BattleResult computeBattle(
  List<BattlePlayer> players, {
  bool matchOnly = false,
  Set<String> blockedKeys = const {},
}) {
  assert(players.length >= 2, 'battle 은 2명 이상 필요');
  final sorted = [...players]..sort((x, y) => x.slot.compareTo(y.slot));
  final pairs = <BattlePair>[];
  for (int i = 0; i < sorted.length; i++) {
    for (int j = i + 1; j < sorted.length; j++) {
      if (matchOnly && sorted[i].gender == sorted[j].gender) continue;
      final report = analyzeCompatibility(
        my: reportToCompatInput(sorted[i].report),
        album: reportToCompatInput(sorted[j].report),
      );
      final blocked =
          blockedKeys.contains(battlePairKey(sorted[i].slot, sorted[j].slot));
      final total = blocked && report.total > kBattleBlockCap
          ? kBattleBlockCap
          : report.total;
      pairs.add(BattlePair(
        a: sorted[i].slot,
        b: sorted[j].slot,
        total: total,
        label: blocked ? classifyLabel(total) : report.label,
        blocked: blocked,
      ));
    }
  }
  pairs.sort(battlePairCompare);
  // matchOnly 인데 pairs 가 비면 호출부(서버 정원 계약) 위반 — best 접근이
  // StateError 가 되므로 방어는 assert 수준, 실제 방어는 클라이언트 몫.
  assert(pairs.isNotEmpty, 'battle pairs 는 비어 있을 수 없다');
  return BattleResult(players: sorted, pairs: pairs);
}
