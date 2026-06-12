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

  /// 방 생성 — 방장(내 관상)이 첫 멤버로 자동 합류 (A7).
  Future<TeamRoom> create({
    required String title,
    required String ownerReportId,
  }) async {
    final now = DateTime.now();
    final room = TeamRoom(
      id: const Uuid().v4(),
      title: title,
      memberReportIds: [ownerReportId],
      createdAt: now,
      updatedAt: now,
    );
    state = [room, ...state];
    await _save();
    return room;
  }

  /// 멤버 추가 — cap 12 + 중복 차단. 성공 시 true.
  Future<bool> addMember(String roomId, String reportId) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return false;
    if (room.memberReportIds.length >= TeamRoom.kMaxMembers) return false;
    if (room.memberReportIds.contains(reportId)) return false;
    room.memberReportIds.add(reportId);
    room.updatedAt = DateTime.now();
    _resort();
    await _save();
    return true;
  }

  Future<void> removeMember(String roomId, String reportId) async {
    final room = byId(roomId);
    if (room == null || room.isClosed) return;
    // 방장(첫 멤버)은 제거 불가.
    if (room.memberReportIds.isNotEmpty &&
        room.memberReportIds.first == reportId) {
      return;
    }
    room.memberReportIds.remove(reportId);
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

  /// 멤버 reportId → history 의 FaceReadingReport resolve.
  /// history 에서 삭제된 카드는 자동 제외된다 (dangling 참조 무해화).
  List<FaceReadingReport> resolveMembers(TeamRoom room) {
    final history = ref.read(historyProvider);
    final byId = <String, FaceReadingReport>{
      for (final r in history)
        if (r.supabaseId != null) r.supabaseId!: r,
    };
    return [
      for (final id in room.memberReportIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
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
