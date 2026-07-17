import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/thumbnail_paths.dart';
import '../../domain/models/battle.dart';
import '../../domain/services/share/share_receive_service.dart';
import 'supabase_service.dart';

/// 로비 슬롯 프로필 — my-face 썸네일 URL + 관상 유형(archetype) 라벨.
typedef BattleSlotProfile = ({String? thumbUrl, String? archetype});

/// Chemistry Battle 서버 접점 — 방은 서버 우선(로컬 캐시 없음).
/// 쓰기는 RPC(security definer)와 owner 직접 insert/delete 뿐,
/// 읽기는 teams(컬럼 grant)·battle_roster·public_battles view.
class BattleService {
  BattleService._();
  static final BattleService instance = BattleService._();

  SupabaseClient get _client => Supabase.instance.client;
  final ShareReceiveService _receive = ShareReceiveService();

  // teams 는 password 컬럼에 authenticated 권한 grant 가 없어 bare `select()`
  // (select=*) 가 42501 로 실패한다 — grant 된 컬럼만 명시.
  static const _teamCols =
      'id, owner_id, title, visibility, max_players, age_min, age_max, '
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
          'visibility': isPublic ? 'public' : 'private',
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
  /// 서버 행이 익명(user_id null)으로 남아 join_battle 이 NO_MY_FACE 를
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

  Future<void> joinBattle(String battleId, {String? password}) =>
      _client.rpc('join_battle', params: {
        'p_team_id': battleId,
        'p_password': ?password,
      });

  Future<void> leaveBattle(String battleId) =>
      _client.rpc('leave_battle', params: {'p_team_id': battleId});

  Future<void> submitResult(String battleId, Map<String, dynamic> payload) =>
      _client.rpc('submit_battle_result', params: {
        'p_team_id': battleId,
        'p_payload': payload,
      });

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
        .from('battle_roster')
        .select()
        .eq('team_id', battleId)
        .order('slot_no', ascending: true);
    return [for (final r in rows) BattleRosterEntry.fromRow(r)];
  }

  Future<List<PublicBattle>> fetchPublicBattles() async {
    final rows = await _client
        .from('public_battles')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final r in rows) PublicBattle.fromRow(r)];
  }

  Future<List<Battle>> fetchMyBattles() async {
    final uid = myUid;
    if (uid == null) return const [];
    final memberRows =
        await _client.from('team_members').select('team_id').eq('user_id', uid);
    final ids = [for (final r in memberRows) r['team_id'] as String];
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('teams')
        .select(_teamCols)
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return [for (final r in rows) Battle.fromRow(r)];
  }

  /// 로비 아바타 — 참가자들의 현재 my-face 썸네일 CDN URL. 없으면 null.
  Future<Map<String, String?>> fetchMyFaceThumbnailUrls(
      List<String> userIds) async {
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
      } catch (_) {/* malformed body — fallback 아바타 */}
    }
    return result;
  }

  /// 로비 슬롯 표기용 — 각 유저 my-face 의 썸네일 URL + 관상 유형 라벨.
  /// metrics body 한 번의 조회로 둘 다 뽑는다. 유형은 body 를 엔진으로
  /// 재계산한 archetype(신의형·연예인형…), 실패한 유저는 해당 값만 null.
  Future<Map<String, BattleSlotProfile>> fetchSlotProfiles(
      List<String> userIds) async {
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
      String? archetype;
      try {
        final bodyStr = r['body'] as String;
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final key = body['thumbnailKey'] as String?;
        thumbUrl = key == null ? null : ThumbnailPaths.cdnUrl(key);
        try {
          archetype =
              FaceReadingReport.fromJsonString(bodyStr).archetype.primaryLabel;
        } catch (_) {/* 엔진 재계산 실패 — 유형만 생략 */}
      } catch (_) {/* malformed body — 아바타·유형 없이 표시 */}
      result[uid] = (thumbUrl: thumbUrl, archetype: archetype);
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

  /// 로비 라이브 — teams UPDATE(status 전이) + team_members INSERT/DELETE.
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

  /// 매칭 성사 상태 — RLS 상 쌍 본인에게만 row 가 보인다(남에겐 null).
  Future<BattleMatch?> fetchMatch(String teamId) async {
    final row = await _client
        .from('battle_matches')
        .select()
        .eq('team_id', teamId)
        .maybeSingle();
    return row == null ? null : BattleMatch.fromRow(row);
  }

  Future<void> respondMatch(String teamId, bool accept) =>
      _client.rpc('respond_match', params: {
        'p_team_id': teamId,
        'p_accept': accept,
      });

  Future<List<BattleMessage>> fetchMessages(String teamId) async {
    final rows = await _client
        .from('battle_messages')
        .select()
        .eq('team_id', teamId)
        .order('created_at', ascending: true)
        .limit(200);
    return [for (final r in rows) BattleMessage.fromRow(r)];
  }

  /// sender_id 는 RLS 가 auth.uid() 일치를 강제 — 명시적으로 실어 보낸다.
  Future<void> sendMessage(String teamId, String body) =>
      _client.from('battle_messages').insert({
        'team_id': teamId,
        'sender_id': myUid,
        'body': body,
      });

  /// 매칭·채팅 라이브 — battle_matches UPDATE(상대 응답) + battle_messages
  /// INSERT(새 메시지). 콜백은 신호일 뿐: 수신 시 호출부가 refetch.
  RealtimeChannel watchMatch(String teamId, void Function() onChange) {
    final channel = _client.channel('battle_match:$teamId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'battle_matches',
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
        table: 'battle_messages',
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
