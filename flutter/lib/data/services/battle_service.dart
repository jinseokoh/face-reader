import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/thumbnail_paths.dart';
import '../../domain/models/battle.dart';
import '../../domain/services/share/share_receive_service.dart';

/// Chemistry Battle 서버 접점 — 방은 서버 우선(로컬 캐시 없음).
/// 쓰기는 RPC(security definer)와 owner 직접 insert/delete 뿐,
/// 읽기는 teams(컬럼 grant)·battle_roster·public_battles view.
class BattleService {
  BattleService._();
  static final BattleService instance = BattleService._();

  SupabaseClient get _client => Supabase.instance.client;
  final ShareReceiveService _receive = ShareReceiveService();

  String? get myUid => _client.auth.currentUser?.id;
  bool get isLoggedIn => myUid != null;

  Future<Battle> createBattle({
    required String title,
    required bool isPublic,
    String? password,
    required int maxPlayers,
    int? ageMin,
    int? ageMax,
    String? pledge,
    String? chatUrl,
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
          if (pledge != null && pledge.isNotEmpty) 'pledge': pledge,
          if (chatUrl != null && chatUrl.isNotEmpty) 'chat_url': chatUrl,
        })
        .select()
        .single();
    return Battle.fromRow(row);
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
        .select(
            'id, owner_id, title, visibility, max_players, age_min, age_max, '
            'pledge, chat_url, status, started_at, closed_at, '
            'chemistry_snapshot, result_payload, created_at')
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
        .select(
            'id, owner_id, title, visibility, max_players, age_min, age_max, '
            'pledge, chat_url, status, started_at, closed_at, '
            'chemistry_snapshot, result_payload, created_at')
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
}
