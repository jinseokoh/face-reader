import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/domain/services/share/share_receive_service.dart';

/// 교감도 그룹의 원격 동기화 (P3). **lazy sync** — 그룹은 로컬(Hive) 우선
/// 생성되고, [카톡 초대]·[마감] 등 원격 행동 시점에만 서버로 push 된다
/// (현장 경로의 무마찰 유지).
///
/// 서버 `team_members` 는 **실제 등록된 멤버(metrics_id 보유)만** 담는다. 방장이
/// 칩으로 깐 대기 이름(metrics_id null)은 로컬 owner 의 명단 계획일 뿐 서버엔
/// 올리지 않는다 — 누군가 원격 합류하면 그때 서버 멤버로 나타난다. 덕분에
/// `(team_id, metrics_id)` unique 로 **비파괴 upsert** 가 가능하고, owner 의
/// re-push 가 원격 합류자 행을 지우지 않는다.
class TeamSyncService {
  TeamSyncService({ShareReceiveService? receive})
      : _receive = receive ?? ShareReceiveService();

  final ShareReceiveService _receive;

  SupabaseClient get _client => Supabase.instance.client;

  /// 현재 로그인 사용자 uid (없으면 null = 비로그인).
  String? get myUid => _client.auth.currentUser?.id;
  bool get isLoggedIn => myUid != null;

  /// 그룹을 서버에 push (owner 전용, 로그인 필요). `teams` upsert + 등록 멤버
  /// (metrics_id 보유) upsert. 원격 합류자 행은 건드리지 않는다(비파괴).
  /// 로그인 안 됐으면 false.
  Future<bool> pushTeam(TeamRoom room) async {
    final uid = myUid;
    if (uid == null) return false;
    try {
      await _client.from('teams').upsert({
        'id': room.id,
        'owner_id': uid,
        'title': room.title,
        'closed_at': room.closedAt?.toIso8601String(),
      });

      // 등록된 멤버(metrics 보유)와 대기 이름 슬롯을 분리 — 슬롯 키는 (team_id,
      // name). 등록 멤버는 DO UPDATE(이름 슬롯 채움), 대기 이름은 ignoreDuplicates
      // (DO NOTHING) 로 **이미 누가 claim 한 슬롯을 덮지 않게** 한다.
      final memberRows = <Map<String, dynamic>>[];
      final pendingRows = <Map<String, dynamic>>[];
      for (int i = 0; i < room.members.length; i++) {
        final member = room.members[i];
        final id = member.reportId;
        // 방장 슬롯의 로컬 전용 표기 '나' 는 웹 초대장·쇼케이스에 그대로
        // 노출되면 안 된다 — 프로필 nickname 으로 치환해 올린다 (로컬 화면은
        // '나' 유지).
        var name = member.name;
        if (i == 0 && name == '나') {
          name = AuthService().currentUser?.nickname ?? name;
        }
        // user_id = 사람 참조: 방장 슬롯은 내 uid, 합류자는 로컬에 동기화된
        // userId, 직접촬영/walk-in 은 null (metrics 스냅샷 유지).
        final row = {
          'team_id': room.id,
          'metrics_id': id,
          'user_id': i == 0 && room.includeOwner ? uid : member.userId,
          'name': name,
          'is_owner': i == 0,
        };
        (id == null ? pendingRows : memberRows).add(row);
      }

      // 유령 행 제거 — push 가 insert-only 라 로컬에서 사라진(삭제·개명) 이름이
      // 서버 슬롯으로 남아 초대장에 계속 노출된다 (예: 방장 표기 '나' 가
      // nickname 으로 바뀐 뒤 남은 옛 '나' 슬롯). upsert 전에 지워야 옛 방장
      // 행의 (team_id, metrics_id) unique 와 새 이름 insert 가 충돌하지 않는다.
      // 합류자가 점유한 행은 로컬 병합 전일 수 있으므로 절대 지우지 않는다 —
      // 미점유 행 + (점유돼도 나 자신인) 옛 방장 행만.
      final localNames = {
        ...memberRows.map((r) => r['name'] as String),
        ...pendingRows.map((r) => r['name'] as String),
      };
      final serverRows = await _client
          .from('team_members')
          .select('id, name, metrics_id, is_owner')
          .eq('team_id', room.id);
      final unclaimedStale = <String>[];
      final ownerStale = <String>[];
      for (final r in (serverRows as List).cast<Map<String, dynamic>>()) {
        if (localNames.contains(r['name'] as String)) continue;
        if (r['metrics_id'] == null) {
          unclaimedStale.add(r['id'] as String);
        } else if (r['is_owner'] == true) {
          ownerStale.add(r['id'] as String);
        }
      }
      if (unclaimedStale.isNotEmpty) {
        // metrics_id null 재확인 — fetch 이후 누가 claim 한 행 오삭제 방지.
        await _client
            .from('team_members')
            .delete()
            .inFilter('id', unclaimedStale)
            .isFilter('metrics_id', null);
      }
      if (ownerStale.isNotEmpty) {
        await _client.from('team_members').delete().inFilter('id', ownerStale);
      }

      if (memberRows.isNotEmpty) {
        await _client
            .from('team_members')
            .upsert(memberRows, onConflict: 'team_id,name');
      }
      if (pendingRows.isNotEmpty) {
        await _client.from('team_members').upsert(
              pendingRows,
              onConflict: 'team_id,name',
              ignoreDuplicates: true,
            );
      }
      return true;
    } catch (e, st) {
      debugPrint('[TeamSync.push] FAIL ${room.id}: $e\n$st');
      rethrow;
    }
  }

  /// 합류 — 초대받은 그룹에 내 등록(metrics)을 멤버로 넣는다 (로그인 필요).
  /// 키가 (team_id, name) 이라:
  ///   - [name] 이 방장이 깐 **대기 슬롯 이름**("까불이")이면 그 빈 행을 채운다(claim).
  ///   - 새 이름이면 새 멤버로 insert.
  ///   - 이미 누가 점유한 이름이면 RLS(claim_slot USING metrics_id is null)가 막아 throw.
  /// 성공 시 true.
  Future<bool> joinTeam({
    required String teamId,
    required String metricsId,
    required String name,
  }) async {
    if (myUid == null) return false;
    try {
      await _client.from('team_members').upsert({
        'team_id': teamId,
        'metrics_id': metricsId,
        'user_id': myUid,
        'name': name,
        'is_owner': false,
      }, onConflict: 'team_id,name');
      return true;
    } catch (e, st) {
      debugPrint('[TeamSync.join] FAIL $teamId: $e\n$st');
      rethrow;
    }
  }

  /// 마감 — owner 가 `closed_at` + (선택) `matrix_payload` 를 기록.
  /// RLS 가 owner 한정이라 타인 호출은 0행 update.
  Future<bool> closeTeam(
    String teamId, {
    Map<String, dynamic>? matrixPayload,
  }) async {
    final uid = myUid;
    if (uid == null) return false;
    try {
      await _client.from('teams').update({
        'closed_at': DateTime.now().toIso8601String(),
        'matrix_payload': ?matrixPayload,
      }).eq('id', teamId).eq('owner_id', uid);
      return true;
    } catch (e, st) {
      debugPrint('[TeamSync.close] FAIL $teamId: $e\n$st');
      rethrow;
    }
  }

  /// 로그인 rehydrate 용 — **모집 중(closed_at null)** 인 내 방 id 열거.
  /// owned = teams.owner_id, invited = 내가 멤버인 방 (user_id 사람 참조 우선,
  /// user_id 없는 옛 합류 행은 내 metrics 로 보조 매칭).
  /// closed 방은 의도적으로 제외 (부활 금지 정책, 2026-07-12): 끝난 방을
  /// 지운 사용자 의도 존중 + 결과표는 웹 링크로 열람 가능.
  Future<List<String>> fetchMyOpenTeamIds(List<String> myMetricsIds) async {
    final uid = myUid;
    if (uid == null) return const [];
    final ids = <String>{};
    final owned = await _client
        .from('teams')
        .select('id')
        .eq('owner_id', uid)
        .isFilter('closed_at', null);
    for (final r in (owned as List).cast<Map<String, dynamic>>()) {
      ids.add(r['id'] as String);
    }
    final joined = <String>{};
    final byUid = await _client
        .from('team_members')
        .select('team_id')
        .eq('user_id', uid);
    for (final r in (byUid as List).cast<Map<String, dynamic>>()) {
      joined.add(r['team_id'] as String);
    }
    if (myMetricsIds.isNotEmpty) {
      final memberRows = await _client
          .from('team_members')
          .select('team_id')
          .inFilter('metrics_id', myMetricsIds);
      for (final r in (memberRows as List).cast<Map<String, dynamic>>()) {
        joined.add(r['team_id'] as String);
      }
    }
    joined.removeAll(ids);
    if (joined.isNotEmpty) {
      final open = await _client
          .from('teams')
          .select('id')
          .inFilter('id', joined.toList())
          .isFilter('closed_at', null);
      for (final r in (open as List).cast<Map<String, dynamic>>()) {
        ids.add(r['id'] as String);
      }
    }
    return ids.toList();
  }

  /// 그룹 1건 fetch (입장·pull-to-refresh). 없으면 null.
  Future<RemoteTeam?> fetchTeam(String teamId) async {
    final t = await _client
        .from('teams')
        .select()
        .eq('id', teamId)
        .maybeSingle();
    if (t == null) return null;
    final ms = await _client
        .from('team_members')
        .select()
        .eq('team_id', teamId)
        .order('joined_at');
    return RemoteTeam.fromRows(
      t,
      (ms as List).cast<Map<String, dynamic>>(),
    );
  }

  /// 멤버들의 FaceReadingReport 복원 — 매트릭스 계산용. 결과 key = 슬롯의
  /// metrics_id (provider 의 reportId resolve 키와 일치).
  ///
  /// user_id 가 있는 멤버(본인 합류)는 그 유저의 **현재 my-face** 로 live
  /// resolve — 재촬영·claim 귀속으로 my-face row 가 바뀌어도 항상 최신 관상
  /// (케미 = 최신 데이터). 반환 report 의 supabaseId 가 슬롯 metrics_id 와
  /// 다를 수 있고, provider 가 그 값으로 로컬 슬롯을 self-heal 한다.
  /// user_id 없는 멤버(직접촬영)는 metrics_id 스냅샷 그대로.
  /// 실패/삭제(탈퇴)된 멤버는 결과에서 빠진다.
  Future<Map<String, FaceReadingReport>> fetchMemberReports(
    Iterable<({String metricsId, String? userId})> members,
  ) async {
    final out = <String, FaceReadingReport>{};
    for (final m in members) {
      var id = m.metricsId;
      final uid = m.userId;
      if (uid != null) {
        final liveId = await _liveMyFaceId(uid);
        // my-face 가 없으면(탈퇴 직전·전부 강등) 스냅샷 id 로 fallback.
        if (liveId != null) id = liveId;
      }
      final r = await _receive.fetchByUuid(id);
      if (r != null) out[m.metricsId] = r;
    }
    return out;
  }

  /// 유저의 현재 my-face metrics id. 없거나 조회 실패면 null.
  Future<String?> _liveMyFaceId(String uid) async {
    try {
      final row = await _client
          .from('metrics')
          .select('id')
          .eq('user_id', uid)
          .eq('is_my_face', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (e) {
      debugPrint('[TeamSync] live my-face 조회 실패 uid=$uid: $e');
      return null;
    }
  }
}

/// 서버 `teams` + `team_members` 의 read DTO. 로컬 TeamRoom 으로의 매핑·병합은
/// provider 책임 (ownedByMe = ownerId == myUid, 로컬 대기 명단과 merge).
class RemoteTeam {
  final String id;
  final String? ownerId;
  final String title;
  final DateTime? closedAt;
  final Map<String, dynamic>? matrixPayload;
  final List<RemoteMember> members;

  const RemoteTeam({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.closedAt,
    required this.matrixPayload,
    required this.members,
  });

  factory RemoteTeam.fromRows(
    Map<String, dynamic> t,
    List<Map<String, dynamic>> memberRows,
  ) {
    return RemoteTeam(
      id: t['id'] as String,
      ownerId: t['owner_id'] as String?,
      title: t['title'] as String? ?? '',
      closedAt: t['closed_at'] == null
          ? null
          : DateTime.parse(t['closed_at'] as String),
      matrixPayload: (t['matrix_payload'] as Map?)?.cast<String, dynamic>(),
      members: memberRows.map(RemoteMember.fromRow).toList(),
    );
  }
}

class RemoteMember {
  final String? metricsId;

  /// 멤버 본인 계정 uid (본인 합류 슬롯). null = 직접촬영·대기.
  final String? userId;
  final String name;
  final bool isOwner;

  const RemoteMember({
    required this.metricsId,
    required this.userId,
    required this.name,
    required this.isOwner,
  });

  factory RemoteMember.fromRow(Map<String, dynamic> m) => RemoteMember(
        metricsId: m['metrics_id'] as String?,
        userId: m['user_id'] as String?,
        name: m['name'] as String? ?? '',
        isOwner: m['is_owner'] as bool? ?? false,
      );
}
