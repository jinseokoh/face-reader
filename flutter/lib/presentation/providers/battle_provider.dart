import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../core/hive/hive_setup.dart';
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

/// 마지막으로 채팅방을 본 시각의 Hive prefs 키 — 안읽음 판정 기준.
/// BattleChatScreen 이 메시지 로드마다 갱신, openChatsProvider 가 읽는다.
String chatLastSeenKey(String teamId) => 'chat_last_seen:$teamId';

/// 채팅 탭·셸 뱃지·새 메시지 밴드 공용 — 열린 채팅 요약 + 안읽음 판정.
/// 안읽음 = 상대가 보낸 마지막 메시지가 로컬 last-seen 이후.
/// 갱신은 ref.invalidate (채팅방에서 복귀·당겨서 새로고침·채팅 탭 선택).
final openChatsProvider = FutureProvider<List<OpenChat>>((ref) async {
  final chats = await BattleService.instance.fetchOpenChats();
  final prefs = Hive.box<String>(HiveBoxes.prefs);
  final myUid = BattleService.instance.myUid;
  return [
    for (final c in chats)
      OpenChat(
        teamId: c.teamId,
        otherUserId: c.otherUserId,
        otherNickname: c.otherNickname,
        photoUrl: c.photoUrl,
        lastMessage: c.lastMessage,
        hasUnread: _isUnread(c.lastMessage, myUid, prefs.get(chatLastSeenKey(c.teamId))),
      ),
  ];
});

bool _isUnread(BattleMessage? last, String? myUid, String? lastSeenIso) {
  if (last == null || last.senderId == myUid) return false;
  if (lastSeenIso == null) return true;
  final lastSeen = DateTime.tryParse(lastSeenIso);
  return lastSeen == null || last.createdAt.isAfter(lastSeen);
}
