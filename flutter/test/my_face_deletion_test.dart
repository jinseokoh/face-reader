// 내 관상 삭제 전 recruiting 방 처리 판정 — planMyFaceDeletion.
//
// 배경: join_team 은 my-face 없는 조인을 NO_MY_FACE 로 막지만, 조인 뒤
// 관상을 지우는 쪽은 로스터를 몰라서 인원수만 남고 아바타가 없는 유령
// 슬롯이 생겼다 (2026-08-24 실사고). 삭제 쪽에서 같은 불변식을 지킨다.
//
// 실행: flutter test test/my_face_deletion_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:facely/domain/models/team.dart';

const _me = 'me-uuid';
const _other = 'other-uuid';

Team _team({
  required String id,
  required String? ownerId,
  required TeamStatus status,
}) => Team(
  id: id,
  ownerId: ownerId,
  title: id,
  isPublic: true,
  maxPlayers: 8,
  ageMin: null,
  ageMax: null,
  roomKind: TeamRoomKind.all,
  status: status,
  startedAt: null,
  closedAt: null,
  chemistrySnapshot: null,
  resultPayload: null,
  createdAt: DateTime(2026, 8, 24),
);

void main() {
  test('참가 중인 방이 없으면 그냥 삭제', () {
    final plan = planMyFaceDeletion(myTeams: const [], myUid: _me);

    expect(plan.canDelete, isTrue);
    expect(plan.teamsToLeave, isEmpty);
    expect(plan.blockedBy, isEmpty);
  });

  test('남의 recruiting 방에 참가 중이면 그 방에서 나간 뒤 삭제', () {
    final room = _team(id: 'r1', ownerId: _other, status: TeamStatus.recruiting);

    final plan = planMyFaceDeletion(myTeams: [room], myUid: _me);

    expect(plan.canDelete, isTrue);
    expect(plan.teamsToLeave.map((t) => t.id), ['r1']);
  });

  test('내가 방장인 recruiting 방이 있으면 삭제를 막는다', () {
    final mine = _team(id: 'r1', ownerId: _me, status: TeamStatus.recruiting);

    final plan = planMyFaceDeletion(myTeams: [mine], myUid: _me);

    expect(plan.canDelete, isFalse);
    expect(plan.blockedBy.map((t) => t.id), ['r1']);
    // 막힌 이상 나가기는 한 건도 실행하지 않는다.
    expect(plan.teamsToLeave, isEmpty);
  });

  test('recruiting 이 아닌 방은 건드리지 않는다', () {
    // revealing·completed 는 result_payload 에 스냅샷이 동결돼 있어 로스터에서
    // 빼면 이미 발표된 결과가 깨진다. expired 는 leave_team 이 거부한다.
    final rooms = [
      _team(id: 'r1', ownerId: _other, status: TeamStatus.revealing),
      _team(id: 'r2', ownerId: _other, status: TeamStatus.completed),
      _team(id: 'r3', ownerId: _other, status: TeamStatus.expired),
    ];

    final plan = planMyFaceDeletion(myTeams: rooms, myUid: _me);

    expect(plan.canDelete, isTrue);
    expect(plan.teamsToLeave, isEmpty);
  });

  test('내가 방장이어도 recruiting 이 아니면 막지 않는다', () {
    final done = _team(id: 'r1', ownerId: _me, status: TeamStatus.completed);

    final plan = planMyFaceDeletion(myTeams: [done], myUid: _me);

    expect(plan.canDelete, isTrue);
    expect(plan.blockedBy, isEmpty);
    expect(plan.teamsToLeave, isEmpty);
  });

  test('여러 방이 섞여 있으면 남의 recruiting 방만 골라낸다', () {
    final rooms = [
      _team(id: 'leave1', ownerId: _other, status: TeamStatus.recruiting),
      _team(id: 'keep', ownerId: _other, status: TeamStatus.completed),
      _team(id: 'leave2', ownerId: null, status: TeamStatus.recruiting),
    ];

    final plan = planMyFaceDeletion(myTeams: rooms, myUid: _me);

    expect(plan.canDelete, isTrue);
    expect(plan.teamsToLeave.map((t) => t.id), ['leave1', 'leave2']);
  });
}
