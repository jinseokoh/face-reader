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
  final FaceReadingReport report;

  const BattlePlayer({
    required this.slot,
    required this.name,
    required this.report,
  });
}

class BattlePair {
  /// slot_no 양끝 — a < b 정규화 (무방향 쌍의 유일 표현).
  final int a;
  final int b;
  final double total;
  final CompatLabel label;

  const BattlePair({
    required this.a,
    required this.b,
    required this.total,
    required this.label,
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

  BattlePair get best => pairs.first;

  /// teams.result_payload 계약 (§6.3): 점수는 best.score 하나뿐,
  /// band = CompatLabel.index (0=천작지합 … 3=형극난조).
  Map<String, dynamic> toPayload() => {
        'players': [
          for (final p in players) {'slot': p.slot, 'name': p.name},
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

BattleResult computeBattle(List<BattlePlayer> players) {
  assert(players.length >= 2, 'battle 은 2명 이상 필요');
  final sorted = [...players]..sort((x, y) => x.slot.compareTo(y.slot));
  final pairs = <BattlePair>[];
  for (int i = 0; i < sorted.length; i++) {
    for (int j = i + 1; j < sorted.length; j++) {
      final report = analyzeCompatibility(
        my: reportToCompatInput(sorted[i].report),
        album: reportToCompatInput(sorted[j].report),
      );
      pairs.add(BattlePair(
        a: sorted[i].slot,
        b: sorted[j].slot,
        total: report.total,
        label: report.label,
      ));
    }
  }
  pairs.sort(battlePairCompare);
  return BattleResult(players: sorted, pairs: pairs);
}
