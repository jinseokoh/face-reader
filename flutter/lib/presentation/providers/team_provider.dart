import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/history_provider.dart';

final teamsProvider = NotifierProvider<TeamsNotifier, List<TeamRoom>>(
  TeamsNotifier.new,
);

class TeamsNotifier extends Notifier<List<TeamRoom>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.teams);

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
  }) async {
    final now = DateTime.now();
    final names = pendingNames
        .take(TeamRoom.kMaxMembers - 1) // 방장 1 + 대기 (하드캡 12)
        .toList();
    final room = TeamRoom(
      id: const Uuid().v4(),
      title: title,
      members: [
        TeamMember(name: '나', reportId: ownerReportId),
        for (final n in names) TeamMember(name: n),
      ],
      createdAt: now,
      updatedAt: now,
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
    _autoCloseIfComplete(room);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
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
    _autoCloseIfComplete(room);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
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

  /// 빈자리 없이 전원 스캔되면 자동 마감 — 교감도는 최소 3명부터 성립.
  /// 더는 채울 사람이 없으므로 수동 마감 단계를 생략한다.
  void _autoCloseIfComplete(TeamRoom room) {
    if (room.isClosed) return;
    final scanned = room.members.where((m) => m.isScanned).length;
    if (scanned >= TeamRoom.kMinMembers && scanned == room.members.length) {
      room.closedAt = DateTime.now();
    }
  }

  /// 마감 — 🏆 발표 상태로 전환 (A6 방 화면 스펙).
  Future<void> close(String roomId) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return;
    room.closedAt = DateTime.now();
    room.updatedAt = room.closedAt!;
    _resort();
    await _save();
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
    return null;
  }

  /// 스캔이 끝난 멤버들의 리포트 목록 — 매트릭스·프리뷰용.
  /// history 에서 삭제된 카드는 자동 제외(dangling 무해화).
  List<FaceReadingReport> scannedReports(TeamRoom room) {
    final out = <FaceReadingReport>[];
    for (final m in room.members) {
      final r = reportFor(m);
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
