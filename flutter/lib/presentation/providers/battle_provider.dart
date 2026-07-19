import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/battle_service.dart';
import '../../domain/models/battle.dart';

/// 서버 우선 — 로컬 캐시 없음. 새로고침은 ref.invalidate 로.
final publicBattlesProvider = FutureProvider<List<PublicBattle>>(
  (ref) => BattleService.instance.fetchPublicBattles(),
);

final myBattlesProvider = FutureProvider<List<Battle>>(
  (ref) => BattleService.instance.fetchMyBattles(),
);

/// 채팅방이 열린 내 매칭 team_id 집합 — 내 매칭 카드의 초록 강조.
final openChatTeamsProvider = FutureProvider<Set<String>>(
  (ref) => BattleService.instance.fetchOpenChatTeamIds(),
);
