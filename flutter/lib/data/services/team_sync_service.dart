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
        final id = room.members[i].reportId;
        // 방장 슬롯의 로컬 전용 표기 '나' 는 웹 초대장·쇼케이스에 그대로
        // 노출되면 안 된다 — 프로필 nickname 으로 치환해 올린다 (로컬 화면은
        // '나' 유지).
        var name = room.members[i].name;
        if (i == 0 && name == '나') {
          name = AuthService().currentUser?.nickname ?? name;
        }
        final row = {
          'team_id': room.id,
          'metrics_id': id,
          'name': name,
          'is_owner': i == 0,
        };
        (id == null ? pendingRows : memberRows).add(row);
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

  /// 멤버 metrics 들을 FaceReadingReport 로 복원 — 매트릭스 계산용. 로컬 history
  /// 에 없는 원격 멤버를 서버에서 read-only 로 끌어온다 (ShareReceiveService 재사용).
  /// 실패/삭제된 id 는 결과에서 빠진다.
  Future<Map<String, FaceReadingReport>> fetchMemberReports(
    Iterable<String> metricsIds,
  ) async {
    final out = <String, FaceReadingReport>{};
    for (final id in metricsIds) {
      final r = await _receive.fetchByUuid(id);
      if (r != null) out[id] = r;
    }
    return out;
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
  final String name;
  final bool isOwner;

  const RemoteMember({
    required this.metricsId,
    required this.name,
    required this.isOwner,
  });

  factory RemoteMember.fromRow(Map<String, dynamic> m) => RemoteMember(
        metricsId: m['metrics_id'] as String?,
        name: m['name'] as String? ?? '',
        isOwner: m['is_owner'] as bool? ?? false,
      );
}
