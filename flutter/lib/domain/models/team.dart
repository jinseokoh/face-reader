import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/team.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// chemistry_snapshot({user_id: body}) + roster → 엔진 입력.
/// snapshot 에 없는 참가자(계정 삭제 극단 케이스)는 제외. slot 오름차순.
/// gender 는 roster(join_team 조인 시점 서버 강제값)에서 읽는다 — report
/// 재파싱이 아닌 서버와 동일 소스.
List<TeamPlayer> assembleTeamPlayers({
  required List<TeamRosterEntry> roster,
  required Map<String, dynamic> snapshot,
}) {
  final players = <TeamPlayer>[];
  for (final entry in roster) {
    final body = snapshot[entry.userId];
    if (body == null) continue;
    final report = FaceReadingReport.fromJsonString(jsonEncode(body));
    players.add(
      TeamPlayer(
        slot: entry.slotNo,
        name: entry.alias,
        gender: entry.gender,
        report: report,
      ),
    );
  }
  players.sort((a, b) => a.slot.compareTo(b.slot));
  return players;
}

/// snapshot.blocked([[slotA, slotB], …] — 시작 트랜잭션이 동결한 로스터 내
/// 차단 쌍) → computeTeam 의 blockedKeys. 키 부재·빈 배열이면 빈 집합.
Set<String> blockedKeysFromSnapshot(Map<String, dynamic> snapshot) => {
  for (final p in snapshot['blocked'] as List? ?? const [])
    teamPairKey((p[0] as num).toInt(), (p[1] as num).toInt()),
};

/// snapshot.chatted([[slotA, slotB], …] — 이미 베스트 매칭으로 채팅을 연
/// 사이) → computeTeam 의 chattedKeys. 키 부재·빈 배열이면 빈 집합.
Set<String> chattedKeysFromSnapshot(Map<String, dynamic> snapshot) => {
  for (final p in snapshot['chatted'] as List? ?? const [])
    teamPairKey((p[0] as num).toInt(), (p[1] as num).toInt()),
};

/// GENDER_FULL 중립 카피를 본인 성별로 분기 — 'male'→남자 자리, 그 외(female)→여자 자리.
String genderFullLabel(String myGender) =>
    myGender == 'male' ? '남자 자리가 다 찼습니다' : '여자 자리가 다 찼습니다';

TeamJoinError mapTeamError(Object e) {
  final msg = e is PostgrestException ? e.message : e.toString();
  for (final v in TeamJoinError.values) {
    if (v != TeamJoinError.unknown && msg.contains(v.code)) return v;
  }
  return TeamJoinError.unknown;
}

TeamRoomKind teamRoomKindFrom(String raw) =>
    TeamRoomKind.values.byName(raw);

TeamStatus teamStatusFrom(String raw) =>
    TeamStatus.values.firstWhere((s) => s.name == raw);

String _ageRangeLabel(int? ageMin, int? ageMax) {
  if (ageMin == null || ageMax == null) return '전연령';
  if (ageMin == ageMax) return '$ageMin대';
  return '$ageMin대~$ageMax대';
}

/// 채팅 탭 리스트 한 줄 — 열린 매칭 채팅방의 요약.
/// [hasUnread] 는 Hive 로컬 last-seen 기준 (provider 가 채운다).
class OpenChat {
  final String teamId;
  final String otherUserId;
  final String otherNickname;
  final String? photoUrl;

  /// 상대 my-face 사진의 촬영 경로 — 아바타 border 색 규칙
  /// (카메라 gold / 앨범 lightGray) 에 사용. metrics body 파싱 실패 시 null.
  final AnalysisSource? photoSource;
  final TeamMessage? lastMessage;
  final bool hasUnread;

  const OpenChat({
    required this.teamId,
    required this.otherUserId,
    required this.otherNickname,
    required this.photoUrl,
    required this.photoSource,
    required this.lastMessage,
    required this.hasUnread,
  });
}

class PublicTeam {
  final String id;
  final String title;
  final int maxPlayers;
  final int? ageMin;
  final int? ageMax;
  final TeamRoomKind roomKind;
  final bool isPrivate;
  final DateTime createdAt;
  final int playerCount;

  const PublicTeam({
    required this.id,
    required this.title,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.roomKind,
    required this.isPrivate,
    required this.createdAt,
    required this.playerCount,
  });

  factory PublicTeam.fromRow(Map<String, dynamic> row) => PublicTeam(
    id: row['id'] as String,
    title: row['title'] as String,
    maxPlayers: (row['max_players'] as num).toInt(),
    ageMin: (row['age_min'] as num?)?.toInt(),
    ageMax: (row['age_max'] as num?)?.toInt(),
    roomKind: teamRoomKindFrom(row['room_kind'] as String),
    isPrivate: row['is_private'] as bool? ?? false,
    createdAt: DateTime.parse(row['created_at'] as String),
    playerCount: (row['player_count'] as num).toInt(),
  );

  String get ageRangeLabel => _ageRangeLabel(ageMin, ageMax);
}

class Team {
  final String id;
  final String? ownerId;
  final String title;
  final bool isPublic;
  final int maxPlayers;
  final int? ageMin;
  final int? ageMax;
  final TeamRoomKind roomKind;
  final TeamStatus status;
  final DateTime? startedAt;
  final DateTime? closedAt;
  final Map<String, dynamic>? chemistrySnapshot;
  final Map<String, dynamic>? resultPayload;
  final int views;
  final DateTime createdAt;

  /// 현재 참가 인원 — 목록 조회(fetchMyTeams)가 채운다. 단건 조회는 null.
  final int? playerCount;

  const Team({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.isPublic,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.roomKind,
    required this.status,
    required this.startedAt,
    required this.closedAt,
    required this.chemistrySnapshot,
    required this.resultPayload,
    this.views = 0,
    required this.createdAt,
    this.playerCount,
  });

  factory Team.fromRow(Map<String, dynamic> row, {int? playerCount}) =>
      Team(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String?,
        title: row['title'] as String,
        isPublic: !(row['is_private'] as bool? ?? false),
        maxPlayers: (row['max_players'] as num).toInt(),
        ageMin: (row['age_min'] as num?)?.toInt(),
        ageMax: (row['age_max'] as num?)?.toInt(),
        roomKind: teamRoomKindFrom(row['room_kind'] as String),
        status: teamStatusFrom(row['status'] as String),
        startedAt: row['started_at'] == null
            ? null
            : DateTime.parse(row['started_at'] as String),
        closedAt: row['closed_at'] == null
            ? null
            : DateTime.parse(row['closed_at'] as String),
        chemistrySnapshot: row['chemistry_snapshot'] as Map<String, dynamic>?,
        resultPayload: row['result_payload'] as Map<String, dynamic>?,
        views: (row['views'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(row['created_at'] as String),
        playerCount: playerCount,
      );

  String get ageRangeLabel => _ageRangeLabel(ageMin, ageMax);
  bool get hasResult => resultPayload != null;
  bool get isRecruiting => status == TeamStatus.recruiting;
}

/// 서버 RPC 에러 계약 (Plan 1) — raise exception 메시지 문자열이 코드다.
enum TeamJoinError {
  authRequired('AUTH_REQUIRED', '로그인이 필요합니다'),
  notFound('NOT_FOUND', '존재하지 않는 방입니다'),
  notRecruiting('NOT_RECRUITING', '모집이 끝난 방입니다'),
  badPassword('BAD_PASSWORD', '비밀번호가 일치하지 않습니다'),
  noMyFace('NO_MY_FACE', '내 관상 등록이 필요합니다'),
  ageNotAllowed('AGE_NOT_ALLOWED', '이 방의 연령대에 해당하지 않습니다'),
  // GENDER_FULL 이 'FULL' 을 부분 문자열로 포함하므로 mapTeamError 의 순차
  // contains 매칭에서 full 보다 먼저 검사되도록 앞에 둔다.
  genderFull('GENDER_FULL', '이 방의 남녀 자리 중 한쪽이 다 찼습니다'),
  full('FULL', '정원이 가득 찼습니다'),
  alreadyJoined('ALREADY_JOINED', '이미 참가한 방입니다'),
  // 차단 게이트 — 차단자 방향만 존재 (차단당한 쪽은 참가 자유, 방장이
  // 나를 차단한 방은 서버가 NOT_FOUND 로 숨긴다).
  blockedMember('BLOCKED_MEMBER', '차단한 사람이 참가 중인 방입니다'),
  ownerCannotLeave('OWNER_CANNOT_LEAVE', '방장은 나갈 수 없습니다'),
  notLeavable('NOT_LEAVABLE', '지금은 나갈 수 없습니다'),
  notParticipant('NOT_PARTICIPANT', '참가자가 아닙니다'),
  matchExpired('MATCH_EXPIRED', '응답 기한(결과 발표 후 48시간)이 지났습니다'),
  unknown('UNKNOWN', '잠시 후 다시 시도해 주세요');

  final String code;
  final String labelKo;
  const TeamJoinError(this.code, this.labelKo);
}

/// 매칭 성사 — submit_team_result 가 best 쌍을 확정해 생성, respond_match
/// 로 쌍 각자가 채팅 개설에 동의. consent: null=무응답, true=수락, false=거절.
class TeamMatch {
  final String teamId;
  final String userA;
  final String userB;
  final bool? aConsent;
  final bool? bConsent;
  final DateTime? openedAt;

  /// 채팅방 나가기 — 본인 목록에서만 숨김 (leave_chat RPC).
  final bool aLeft;
  final bool bLeft;

  const TeamMatch({
    required this.teamId,
    required this.userA,
    required this.userB,
    required this.aConsent,
    required this.bConsent,
    required this.openedAt,
    this.aLeft = false,
    this.bLeft = false,
  });

  factory TeamMatch.fromRow(Map<String, dynamic> row) => TeamMatch(
    teamId: row['team_id'] as String,
    userA: row['user_a'] as String,
    userB: row['user_b'] as String,
    aConsent: row['a_consent'] as bool?,
    bConsent: row['b_consent'] as bool?,
    openedAt: row['opened_at'] == null
        ? null
        : DateTime.parse(row['opened_at'] as String),
    aLeft: (row['a_left'] as bool?) ?? false,
    bLeft: (row['b_left'] as bool?) ?? false,
  );

  bool get isOpen => openedAt != null;

  bool? consentOf(String uid) {
    if (uid == userA) return aConsent;
    if (uid == userB) return bConsent;
    return null;
  }

  /// [uid] 가 채팅방을 나갔는지 — 쌍 밖 uid 는 false.
  bool leftOf(String uid) {
    if (uid == userA) return aLeft;
    if (uid == userB) return bLeft;
    return false;
  }

  String otherOf(String uid) => uid == userA ? userB : userA;
}

class TeamMessage {
  final String id;
  final String teamId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const TeamMessage({
    required this.id,
    required this.teamId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory TeamMessage.fromRow(Map<String, dynamic> row) => TeamMessage(
    id: row['id'] as String,
    teamId: row['team_id'] as String,
    senderId: row['sender_id'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// 방 유형 — 'all'(전체 케미) / 'match'(이성 케미).
enum TeamRoomKind { all, match }

class TeamRosterEntry {
  final String teamId;
  final String userId;
  final int slotNo;
  final String gender;
  final bool isOwner;
  final DateTime joinedAt;
  final String alias;

  const TeamRosterEntry({
    required this.teamId,
    required this.userId,
    required this.slotNo,
    required this.gender,
    required this.isOwner,
    required this.joinedAt,
    required this.alias,
  });

  factory TeamRosterEntry.fromRow(Map<String, dynamic> row) =>
      TeamRosterEntry(
        teamId: row['team_id'] as String,
        userId: row['user_id'] as String,
        slotNo: (row['slot_no'] as num).toInt(),
        gender: row['gender'] as String,
        isOwner: row['is_owner'] as bool,
        joinedAt: DateTime.parse(row['joined_at'] as String),
        alias: (row['alias'] as String?) ?? '참가자',
      );
}

/// Chemistry Team 클라이언트 모델 — Plan 1 서버 계약(teams·team_roster·
/// public_teams·RPC 에러 문자열)의 Dart 표현. 서버가 SSOT, 여기는 파싱만.

enum TeamStatus { recruiting, revealing, completed, expired }
