import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/team_sync_service.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/screens/team/team_band.dart';

final teamsProvider = NotifierProvider<TeamsNotifier, List<TeamRoom>>(
  TeamsNotifier.new,
);

class TeamsNotifier extends Notifier<List<TeamRoom>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.teams);

  final TeamSyncService _sync = TeamSyncService();

  /// 원격(서버) 멤버 리포트 캐시 — 로컬 history 에 없는 합류자를 매트릭스에서
  /// 쓰려고 pull 시 채운다. [reportFor] 가 history 다음으로 여기서 resolve.
  final Map<String, FaceReadingReport> _remoteCache = {};

  @override
  List<TeamRoom> build() {
    final rooms = <TeamRoom>[];
    for (int i = 0; i < _box.length; i++) {
      final json = _box.getAt(i);
      if (json == null) continue;
      try {
        rooms.add(TeamRoom.fromJsonString(json));
      } catch (_) {
        // 깨진 entry 는 건너뛴다 — capture-only 라 잃는 건 방 목록뿐.
      }
    }
    // 활동 최신순 (A5 ②).
    rooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rooms;
  }

  /// 방 생성 — 방장(내 관상)이 첫 멤버(스캔 완료)로 자동 합류 (A7).
  /// [pendingNames] = 생성 시 칩 입력으로 미리 깐 대기 멤버 이름 (미스캔).
  Future<TeamRoom> create({
    required String title,
    required String ownerReportId,
    List<String> pendingNames = const [],
    bool includeOwner = true,
  }) async {
    final now = DateTime.now();
    // 나 포함이면 방장 1 자리를 빼고, 미포함이면 전부 참가자(하드캡 12).
    final names = pendingNames
        .take(includeOwner ? TeamRoom.kMaxMembers - 1 : TeamRoom.kMaxMembers)
        .toList();
    final room = TeamRoom(
      id: const Uuid().v4(),
      title: title,
      members: [
        if (includeOwner) TeamMember(name: '나', reportId: ownerReportId),
        for (final n in names) TeamMember(name: n),
      ],
      createdAt: now,
      updatedAt: now,
      includeOwner: includeOwner,
    );
    state = [room, ...state];
    await _save();
    return room;
  }

  /// 대기 슬롯을 스캔 결과로 채운다 — [index] 멤버에 reportId 부여.
  /// 이미 다른 슬롯이 같은 reportId 면 거부(중복 스캔). 성공 시 true.
  Future<bool> fillSlot(String roomId, int index, String reportId) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return false;
    if (index < 0 || index >= room.members.length) return false;
    if (room.members.any((m) => m.reportId == reportId)) return false;
    room.members[index].reportId = reportId;
    final justClosed = _autoCloseIfComplete(room);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
    if (justClosed) unawaited(_syncClose(room));
    return true;
  }

  /// 명단에 없던 새 멤버를 스캔으로 추가 (walk-in). cap 12 + 중복 차단.
  Future<bool> addScannedMember(
    String roomId, {
    required String name,
    required String reportId,
  }) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return false;
    if (room.members.length >= TeamRoom.kMaxMembers) return false;
    if (room.members.any((m) => m.reportId == reportId)) return false;
    room.members.add(TeamMember(name: name, reportId: reportId));
    final justClosed = _autoCloseIfComplete(room);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
    if (justClosed) unawaited(_syncClose(room));
    return true;
  }

  /// 멤버 제거 — 방장(index 0)은 불가.
  Future<void> removeMemberAt(String roomId, int index) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return;
    if (index <= 0 || index >= room.members.length) return;
    room.members.removeAt(index);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
  }

  Future<void> rename(String roomId, String title) async {
    final room = byId(roomId);
    if (room == null) return;
    room.title = title;
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
  }

  /// 그룹 설정 저장 — 제목과 대기(미스캔) 명단을 한 번에 갱신.
  /// 방장(0)·스캔 완료 멤버는 [isScanned] 로 보존하고, 대기 슬롯만
  /// [pendingNames] 로 통째 교체한다 (명수 편집). 하드캡 12.
  Future<void> updateRoster(
    String roomId, {
    required String title,
    required List<String> pendingNames,
  }) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return;
    room.title = title;
    room.members.removeWhere((m) => !m.isScanned);
    for (final raw in pendingNames) {
      if (room.members.length >= TeamRoom.kMaxMembers) break;
      final name = raw.trim();
      if (name.isEmpty || name == '나') continue;
      if (room.members.any((m) => m.name == name)) continue;
      room.members.add(TeamMember(name: name));
    }
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
  }

  /// 빈자리 없이 전원 스캔되면 자동 마감 — 교감도는 최소 3명부터 성립.
  /// 더는 채울 사람이 없으므로 수동 마감 단계를 생략한다. 방금 닫혔으면 true.
  bool _autoCloseIfComplete(TeamRoom room) {
    if (room.closedAt != null) return false;
    final scanned = room.members.where((m) => m.isScanned).length;
    if (scanned >= TeamRoom.kMinMembers && scanned == room.members.length) {
      room.closedAt = DateTime.now();
      return true;
    }
    return false;
  }

  /// 마감 — 🏆 발표 상태로 전환 (A6 방 화면 스펙). 서버 push 된 그룹이면
  /// 매트릭스 payload 와 함께 마감 반영 (best-effort).
  Future<void> close(String roomId) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return;
    room.closedAt = DateTime.now();
    room.updatedAt = room.closedAt!;
    _resort();
    await _save();
    await _syncClose(room);
  }

  /// 마감을 서버에 반영 — 매트릭스 payload(이름+밴드만) 동봉. push 안 됐거나
  /// 비로그인이면 owner 불일치로 0행 update (무해). 네트워크 실패도 무시.
  Future<void> _syncClose(TeamRoom room) async {
    try {
      await _sync.closeTeam(room.id, matrixPayload: _buildPayload(room));
    } catch (_) {
      // 로컬 마감은 이미 반영됨 — 서버 반영 실패는 다음 동기화에서 재시도.
    }
  }

  /// 마감 그룹의 web 쇼케이스용 payload. 멤버 표시 이름은 그룹 명단 우선.
  /// 방장의 로컬 전용 표기 '나' 는 웹에 그대로 노출되면 안 된다 — 프로필
  /// nickname 으로 치환 (로컬 매트릭스 화면은 '나' 유지).
  Map<String, dynamic>? _buildPayload(TeamRoom room) {
    final myNickname = AuthService().currentUser?.nickname;
    final nameById = <String, String>{
      for (final m in room.members)
        if (m.reportId != null)
          m.reportId!: m.name == '나' ? (myNickname ?? m.name) : m.name,
    };
    return buildTeamMatrixPayload(
      title: room.title,
      reports: scannedReports(room),
      nameOf: (r) => nameById[r.supabaseId] ?? r.alias ?? '익명',
    );
  }

  // ── 원격 동기화 (P3) ─────────────────────────────────────────────

  /// owner 가 그룹을 서버로 push (초대·마감 직전). 로그인 안 됐으면 false.
  /// push 전에 방장 슬롯을 현재 내 관상으로 rebind — 내 사진 교체가 서버
  /// team_members 의 내 metrics_id 에도 반영되게 한다(내쪽 live).
  Future<bool> pushToServer(String roomId) async {
    final room = byId(roomId);
    if (room == null) return false;
    if (room.ownedByMe && room.includeOwner && room.members.isNotEmpty) {
      final myId = _currentMyFace()?.supabaseId;
      if (myId != null && room.members[0].reportId != myId) {
        room.members[0].reportId = myId;
        await _save();
      }
    }
    return _sync.pushTeam(room);
  }

  /// 서버에서 그룹 1건을 미리보기로 fetch (합류 화면용, 로컬 병합 없음).
  Future<RemoteTeam?> peekRemoteTeam(String teamId) => _sync.fetchTeam(teamId);

  /// 로그인 rehydrate — **모집 중인** 내 방(owned+invited)만 서버에서 복원.
  /// metrics rehydrate 완료 후 호출 (invited 매칭이 내 metrics id 에 의존).
  /// closed 방은 부활 금지 정책으로 제외. 이미 로컬에 있는 방은 skip.
  Future<void> rehydrateFromServer() async {
    try {
      final myIds = <String>[
        for (final r in ref.read(historyProvider))
          if (r.supabaseId != null) r.supabaseId!,
      ];
      final ids = await _sync.fetchMyOpenTeamIds(myIds);
      if (ids.isEmpty) return;
      final known = {for (final r in state) r.id};
      var restored = 0;
      for (final id in ids) {
        if (known.contains(id)) continue;
        try {
          final room = await refreshFromServer(id);
          if (room != null) restored++;
        } catch (_) {
          // 개별 실패 무시 — 나머지 방은 계속 복원.
        }
      }
      if (restored > 0) {
        debugPrint('[TeamRehydrate] restored $restored open room(s)');
      }
    } catch (e) {
      debugPrint('[TeamRehydrate] error: $e');
    }
  }

  /// 초대받은 그룹 합류 — 서버에 내 등록 추가 후 pull 해서 로컬에 반영.
  /// 성공 시 invited 그룹(ownedByMe=false), 실패(비로그인 등) 시 null.
  Future<TeamRoom?> joinRemoteTeam(
    String teamId, {
    required String myReportId,
    required String myName,
  }) async {
    final ok = await _sync.joinTeam(
      teamId: teamId,
      metricsId: myReportId,
      name: myName.isEmpty ? '게스트' : myName,
    );
    if (!ok) return null;
    return refreshFromServer(teamId);
  }

  /// 서버에서 그룹 pull → 로컬 state 병합 + 멤버 리포트 캐시. owned(내 그룹)면
  /// 로컬 대기 명단을 유지하며 새 합류자만 추가하고, invited 면 서버 뷰로
  /// 구성한다. 없으면 null.
  Future<TeamRoom?> refreshFromServer(String teamId) async {
    final remote = await _sync.fetchTeam(teamId);
    if (remote == null) return null;

    // 원격 멤버 리포트 캐시 (매트릭스용).
    final ids =
        remote.members.map((m) => m.metricsId).whereType<String>().toList();
    if (ids.isNotEmpty) {
      _remoteCache.addAll(await _sync.fetchMemberReports(ids));
    }

    final mine = _sync.myUid != null && remote.ownerId == _sync.myUid;
    final existing = byId(teamId);

    if (mine && existing != null) {
      // 내 그룹 — 로컬 명단 유지하며 서버의 합류를 병합.
      final known =
          existing.members.map((m) => m.reportId).whereType<String>().toSet();
      for (final m in remote.members) {
        final mid = m.metricsId;
        if (mid == null || m.isOwner || known.contains(mid)) continue;
        // 같은 이름의 로컬 **대기 슬롯**이 있으면 그 슬롯을 채운다(원격 claim 반영).
        // 없으면 새 합류자로 추가.
        final slot = existing.members
            .where((lm) => lm.reportId == null && lm.name == m.name)
            .firstOrNull;
        if (slot != null) {
          slot.reportId = mid;
        } else {
          existing.members.add(TeamMember(name: m.name, reportId: mid));
        }
      }
      if (remote.closedAt != null) {
        existing.closedAt = remote.closedAt;
        // 서버(48h cron)가 닫은 방은 matrix_payload 가 없다 — owner 의 다음
        // refresh 에서 웹 쇼케이스용 payload 를 backfill. 결과표는 **전원
        // 등록** 시에만 생성 (옛 ≥3 기준 폐기, 2026-07-12) — 전원 미충족
        // 종료 방은 웹이 "전원이 모이지 않아 종료" 를 렌더.
        final scanned = existing.members.where((m) => m.isScanned).length;
        if (remote.matrixPayload == null &&
            scanned >= TeamRoom.kMinMembers &&
            scanned == existing.members.length) {
          unawaited(_syncClose(existing));
        }
      }
      existing.updatedAt = DateTime.now();
      _resort();
      await _save();
      return existing;
    }

    // 초대받은 그룹(또는 로컬에 없던 내 그룹) — 서버 뷰로 구성. 방장 먼저.
    final ordered = [
      ...remote.members.where((m) => m.isOwner),
      ...remote.members.where((m) => !m.isOwner),
    ];
    final room = TeamRoom(
      id: teamId,
      title: remote.title,
      members: [
        for (final m in ordered)
          TeamMember(name: m.name, reportId: m.metricsId),
      ],
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      closedAt: remote.closedAt,
      ownedByMe: mine,
    );
    final next = [room, ...state.where((r) => r.id != teamId)];
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = next;
    await _save();
    return room;
  }

  Future<void> delete(String roomId) async {
    state = state.where((r) => r.id != roomId).toList();
    await _save();
  }

  TeamRoom? byId(String roomId) {
    for (final r in state) {
      if (r.id == roomId) return r;
    }
    return null;
  }

  /// 스캔된 멤버 한 명의 FaceReadingReport resolve (대기·삭제 카드는 null).
  FaceReadingReport? reportFor(TeamMember member) {
    final id = member.reportId;
    if (id == null) return null;
    for (final r in ref.read(historyProvider)) {
      if (r.supabaseId == id) return r;
    }
    // 로컬에 없으면 원격 pull 캐시 (합류자 등).
    return _remoteCache[id];
  }

  /// 현재 내 관상 (isMyFace). 없으면 null.
  FaceReadingReport? _currentMyFace() {
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) return r;
    }
    return null;
  }

  /// 그룹 맥락 멤버 resolve — **내가 만든 그룹의 방장 슬롯(index 0)은 저장된
  /// reportId(생성 당시 스냅샷) 대신 현재 내 관상으로 live resolve**. 내 사진을
  /// 바꾸면 그룹 매트릭스·썸네일이 즉시 새 사진으로 갱신된다. 타인 멤버·초대받은
  /// 그룹은 동결 스냅샷(reportFor) 유지.
  FaceReadingReport? reportForInRoom(TeamRoom room, int index) {
    if (room.ownedByMe && room.includeOwner && index == 0) {
      return _currentMyFace() ?? reportFor(room.members[index]);
    }
    return reportFor(room.members[index]);
  }

  /// 스캔이 끝난 멤버들의 리포트 목록 — 매트릭스·프리뷰용. 방장 슬롯은 live
  /// (reportForInRoom). history 에서 삭제된 카드는 자동 제외(dangling 무해화).
  List<FaceReadingReport> scannedReports(TeamRoom room) {
    final out = <FaceReadingReport>[];
    for (int i = 0; i < room.members.length; i++) {
      final r = reportForInRoom(room, i);
      if (r != null) out.add(r);
    }
    return out;
  }

  void _resort() {
    final rooms = [...state];
    rooms.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = rooms;
  }

  Future<void> _save() async {
    await _box.clear();
    for (final room in state) {
      await _box.add(room.toJsonString());
    }
    await _box.flush();
  }
}
