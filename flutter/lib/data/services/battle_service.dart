import 'dart:convert';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/thumbnail_paths.dart';
import '../../domain/models/battle.dart';
import '../../domain/services/share/share_receive_service.dart';
import 'supabase_service.dart';

/// 슬롯 프로필 — my-face 썸네일 URL + meta 부품. 화면이 조합한다:
/// 상세 슬롯 = "$ageGender $ethnicity", 베스트 카드 = "$ageGender $faceShape",
/// archetype 은 공용 ("신의형 · 호감형 기질").
typedef BattleSlotProfile = ({
  String? thumbUrl,
  String? ageGender,
  String? ethnicity,
  String? faceShape,
  String? archetype,
});

/// 차단 목록 행 — my_blocks view 의 상대 id + 닉네임.
typedef BlockedUser = ({String userId, String nickname});

/// Chemistry Battle 서버 접점 — 방은 서버 우선(로컬 캐시 없음).
/// 쓰기는 RPC(security definer)와 owner 직접 insert/delete 뿐,
/// 읽기는 teams(컬럼 grant)·team_roster·public_teams view.
class BattleService {
  BattleService._();
  static final BattleService instance = BattleService._();

  SupabaseClient get _client => Supabase.instance.client;
  final ShareReceiveService _receive = ShareReceiveService();

  // teams 는 password 컬럼에 authenticated 권한 grant 가 없어 bare `select()`
  // (select=*) 가 42501 로 실패한다 — grant 된 컬럼만 명시.
  static const _teamCols =
      'id, owner_id, title, is_private, max_players, age_min, age_max, '
      'room_kind, thumb_open, status, started_at, closed_at, '
      'chemistry_snapshot, result_payload, created_at';

  String? get myUid => _client.auth.currentUser?.id;
  bool get isLoggedIn => myUid != null;

  Future<Battle> createBattle({
    required String title,
    required bool isPublic,
    String? password,
    required int maxPlayers,
    int? ageMin,
    int? ageMax,
    required BattleRoomKind roomKind,
    required bool thumbOpen,
  }) async {
    final row = await _client
        .from('teams')
        .insert({
          'owner_id': myUid,
          'title': title,
          // 공개/비밀 = password 유무 단일 소스 (is_private 는 파생 컬럼).
          'password': ?password,
          'max_players': maxPlayers,
          'age_min': ?ageMin,
          'age_max': ?ageMax,
          'room_kind': roomKind.name,
          'thumb_open': thumbOpen,
        })
        .select(_teamCols)
        .single();
    return Battle.fromRow(row);
  }

  /// 조인 전 서버 my-face 보장. 비로그인 등록 → 로그인 직후 조인 경로에서
  /// 서버 행이 익명(user_id null)으로 남아 join_team 이 NO_MY_FACE 를
  /// 던지는 것을 saveMetrics 재호출(고정 행 upsert = 귀속)로 자가 치유.
  Future<bool> ensureMyFaceOnServer(FaceReadingReport myFace) async {
    final uid = myUid;
    if (uid == null) return false;
    final row = await _client
        .from('metrics')
        .select('id')
        .eq('user_id', uid)
        .eq('is_my_face', true)
        .limit(1)
        .maybeSingle();
    if (row != null) return true;
    try {
      await SupabaseService().saveMetrics(myFace);
      return true;
    } catch (e) {
      debugPrint('[Battle.ensureMyFace] saveMetrics fail: $e');
      return false;
    }
  }

  Future<void> joinBattle(String battleId, {String? password}) => _client.rpc(
    'join_team',
    params: {'p_team_id': battleId, 'p_password': ?password},
  );

  /// 비밀방 문 앞 PIN 검증 — 목록 탭 → 상세 진입 전 dialog 용. password 는
  /// 봉인 유지(boolean 만 반환), 최종 검증은 join_team 이 다시 한다.
  Future<bool> checkPassword(String battleId, String password) async =>
      await _client.rpc(
            'check_team_password',
            params: {'p_team_id': battleId, 'p_password': password},
          )
          as bool;

  Future<void> leaveBattle(String battleId) =>
      _client.rpc('leave_team', params: {'p_team_id': battleId});

  Future<void> submitResult(String battleId, Map<String, dynamic> payload) =>
      _client.rpc(
        'submit_team_result',
        params: {'p_team_id': battleId, 'p_payload': payload},
      );

  Future<void> deleteBattle(String battleId) =>
      _client.from('teams').delete().eq('id', battleId);

  Future<Battle?> fetchBattle(String battleId) async {
    final row = await _client
        .from('teams')
        .select(_teamCols)
        .eq('id', battleId)
        .maybeSingle();
    return row == null ? null : Battle.fromRow(row);
  }

  Future<List<BattleRosterEntry>> fetchRoster(String battleId) async {
    final rows = await _client
        .from('team_roster')
        .select()
        .eq('team_id', battleId)
        .order('slot_no', ascending: true);
    return [for (final r in rows) BattleRosterEntry.fromRow(r)];
  }

  Future<List<PublicBattle>> fetchPublicBattles() async {
    final rows = await _client
        .from('public_teams')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final r in rows) PublicBattle.fromRow(r)];
  }

  Future<List<Battle>> fetchMyBattles() async {
    final uid = myUid;
    if (uid == null) return const [];
    final memberRows = await _client
        .from('team_members')
        .select('team_id')
        .eq('user_id', uid);
    final ids = [for (final r in memberRows) r['team_id'] as String];
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('teams')
        .select(_teamCols)
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    // 방별 현재 인원 — 카드 정원 표기용 (공개 목록 view 의 player_count 대응).
    final memberAll = await _client
        .from('team_members')
        .select('team_id')
        .inFilter('team_id', ids);
    final counts = <String, int>{};
    for (final r in memberAll) {
      final id = r['team_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return [
      for (final r in rows)
        Battle.fromRow(r, playerCount: counts[r['id'] as String] ?? 0),
    ];
  }

  /// 참가자 아바타 — 참가자들의 현재 my-face 썸네일 CDN URL. 없으면 null.
  Future<Map<String, String?>> fetchMyFaceThumbnailUrls(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _client
        .from('metrics')
        .select('user_id, body')
        .inFilter('user_id', userIds)
        .eq('is_my_face', true);
    final result = <String, String?>{for (final id in userIds) id: null};
    for (final r in rows) {
      final uid = r['user_id'] as String?;
      if (uid == null) continue;
      try {
        final body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
        final key = body['thumbnailKey'] as String?;
        result[uid] = key == null ? null : ThumbnailPaths.cdnUrl(key);
      } catch (_) {
        /* malformed body — fallback 아바타 */
      }
    }
    return result;
  }

  /// 상세 페이지 슬롯 표기용 — 각 유저 my-face 의 썸네일 URL + meta 두 줄.
  /// metrics body 한 번의 조회로 전부 뽑는다. meta 는 body 를 엔진으로
  /// 재계산한 리포트에서 (인구통계·archetype), 실패한 유저는 해당 값만 null.
  Future<Map<String, BattleSlotProfile>> fetchSlotProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _client
        .from('metrics')
        .select('user_id, body')
        .inFilter('user_id', userIds)
        .eq('is_my_face', true);
    final result = <String, BattleSlotProfile>{};
    for (final r in rows) {
      final uid = r['user_id'] as String?;
      if (uid == null) continue;
      String? thumbUrl;
      String? ageGender;
      String? ethnicity;
      String? faceShape;
      String? archetype;
      try {
        final bodyStr = r['body'] as String;
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final key = body['thumbnailKey'] as String?;
        thumbUrl = key == null ? null : ThumbnailPaths.cdnUrl(key);
        try {
          final report = FaceReadingReport.fromJsonString(bodyStr);
          ageGender = '${report.ageGroup.labelKo} ${report.gender.labelKo}';
          ethnicity = report.ethnicity.labelKo;
          faceShape = report.faceShape.korean;
          archetype =
              '${report.archetype.primaryLabel} · '
              '${report.archetype.secondaryLabel} 기질';
        } catch (_) {
          /* 엔진 재계산 실패 — meta 만 생략 */
        }
      } catch (_) {
        /* malformed body — 아바타·meta 없이 표시 */
      }
      result[uid] = (
        thumbUrl: thumbUrl,
        ageGender: ageGender,
        ethnicity: ethnicity,
        faceShape: faceShape,
        archetype: archetype,
      );
    }
    return result;
  }

  /// 쌍 상세 unlock 용 — 해당 유저의 현재 my-face 리포트 (live resolve).
  Future<FaceReadingReport?> fetchLiveReport(String userId) async {
    final row = await _client
        .from('metrics')
        .select('id')
        .eq('user_id', userId)
        .eq('is_my_face', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final id = row?['id'] as String?;
    if (id == null) return null;
    return _receive.fetchByUuid(id);
  }

  /// 상세 페이지 라이브 — teams UPDATE(status 전이) + team_members INSERT/DELETE.
  /// 콜백은 신호일 뿐: 수신 시 호출부가 fetchBattle/fetchRoster 로 refetch.
  RealtimeChannel watchBattle(String battleId, void Function() onChange) {
    final channel = _client.channel('battle:$battleId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'teams',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: battleId,
        ),
        callback: (_) => onChange(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'team_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'team_id',
          value: battleId,
        ),
        callback: (_) => onChange(),
      );
    channel.subscribe();
    return channel;
  }

  Future<void> unwatch(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  /// 채팅방이 열린 내 매칭의 team_id 집합 — 내 매칭 카드 강조용.
  /// RLS(pair_read)가 내 쌍 행만 돌려주므로 필터는 opened 여부 하나면 된다.
  Future<Set<String>> fetchOpenChatTeamIds() async {
    if (myUid == null) return const {};
    final rows = await _client
        .from('team_matches')
        .select('team_id')
        .not('opened_at', 'is', null);
    return {for (final r in rows) r['team_id'] as String};
  }

  /// 채팅 탭 리스트 — 열린 매칭 전부의 상대·썸네일·마지막 메시지 요약.
  /// unread 판정은 provider 몫 (여기선 hasUnread=false 로 채운다).
  /// 마지막 메시지 최신순, 메시지 없는 방은 뒤로.
  Future<List<OpenChat>> fetchOpenChats() async {
    final uid = myUid;
    if (uid == null) return const [];
    final matchRows = await _client
        .from('team_matches')
        .select()
        .not('opened_at', 'is', null);
    final matches = [for (final r in matchRows) BattleMatch.fromRow(r)];
    if (matches.isEmpty) return const [];

    final teamIds = [for (final m in matches) m.teamId];
    final otherIds = [for (final m in matches) m.otherOf(uid)];
    final results = await Future.wait<dynamic>([
      _client
          .from('team_roster')
          .select('team_id, user_id, nickname')
          .inFilter('team_id', teamIds),
      fetchMyFaceThumbnailUrls(otherIds),
      for (final id in teamIds)
        _client
            .from('team_messages')
            .select()
            .eq('team_id', id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
    ]);

    // (teamId, userId) → nickname. 상대 계정 삭제로 로스터가 없으면 '상대'.
    final nicknames = <String, String>{
      for (final r in results[0] as List)
        '${r['team_id']}:${r['user_id']}': (r['nickname'] as String?) ?? '상대',
    };
    final thumbs = results[1] as Map<String, String?>;

    final chats = <OpenChat>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final other = otherIds[i];
      final lastRow = results[2 + i] as Map<String, dynamic>?;
      chats.add(
        OpenChat(
          teamId: m.teamId,
          otherUserId: other,
          otherNickname: nicknames['${m.teamId}:$other'] ?? '상대',
          photoUrl: thumbs[other],
          lastMessage: lastRow == null ? null : BattleMessage.fromRow(lastRow),
          hasUnread: false,
        ),
      );
    }
    chats.sort((a, b) {
      final at = a.lastMessage?.createdAt;
      final bt = b.lastMessage?.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return chats;
  }

  /// 매칭 성사 상태 — RLS 상 쌍 본인에게만 row 가 보인다(남에겐 null).
  Future<BattleMatch?> fetchMatch(String teamId) async {
    final row = await _client
        .from('team_matches')
        .select()
        .eq('team_id', teamId)
        .maybeSingle();
    return row == null ? null : BattleMatch.fromRow(row);
  }

  Future<void> respondMatch(String teamId, bool accept) => _client.rpc(
    'respond_match',
    params: {'p_team_id': teamId, 'p_accept': accept},
  );

  Future<List<BattleMessage>> fetchMessages(String teamId) async {
    final rows = await _client
        .from('team_messages')
        .select()
        .eq('team_id', teamId)
        .order('created_at', ascending: true)
        .limit(200);
    return [for (final r in rows) BattleMessage.fromRow(r)];
  }

  /// sender_id 는 RLS 가 auth.uid() 일치를 강제 — 명시적으로 실어 보낸다.
  Future<void> sendMessage(String teamId, String body) => _client
      .from('team_messages')
      .insert({'team_id': teamId, 'sender_id': myUid, 'body': body});

  /// 채팅 상대 신고 — RLS 가 신고자 본인·매치 쌍 당사자·피신고자=상대를 강제.
  Future<void> reportChatUser({
    required String teamId,
    required String reportedId,
    required String reason,
  }) => _client.from('team_reports').insert({
    'team_id': teamId,
    'reporter_id': myUid,
    'reported_id': reportedId,
    'reason': reason,
  });

  /// 상대 차단 — 이후 서로의 매칭방 조인이 양방향으로 거부되고(join_team
  /// 게이트), 상대가 방장인 방은 공개 목록에서 숨는다. 중복 차단은 no-op.
  Future<void> blockUser(String blockedId) =>
      _client.from('user_blocks').upsert({
        'blocker_id': myUid!,
        'blocked_id': blockedId,
      }, ignoreDuplicates: true);

  Future<void> unblockUser(String blockedId) => _client
      .from('user_blocks')
      .delete()
      .match({'blocker_id': myUid!, 'blocked_id': blockedId});

  /// 내 차단 목록 — my_blocks view (본인 행 + 상대 닉네임만 노출).
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final rows = await _client
        .from('my_blocks')
        .select()
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        (
          userId: r['blocked_id'] as String,
          nickname: (r['nickname'] as String?) ?? '사용자',
        ),
    ];
  }

  /// 매칭·채팅 라이브 — team_matches UPDATE(상대 응답) + team_messages
  /// INSERT(새 메시지). 콜백은 신호일 뿐: 수신 시 호출부가 refetch.
  RealtimeChannel watchMatch(String teamId, void Function() onChange) {
    final channel = _client.channel('battle_match:$teamId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'team_matches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'team_id',
          value: teamId,
        ),
        callback: (_) => onChange(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'team_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'team_id',
          value: teamId,
        ),
        callback: (_) => onChange(),
      );
    channel.subscribe();
    return channel;
  }
}
