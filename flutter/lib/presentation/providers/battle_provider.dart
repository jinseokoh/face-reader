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
