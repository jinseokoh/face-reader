import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/battle.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Chemistry Battle 클라이언트 모델 — Plan 1 서버 계약(teams·battle_roster·
/// public_battles·RPC 에러 문자열)의 Dart 표현. 서버가 SSOT, 여기는 파싱만.

enum BattleStatus { recruiting, revealing, completed, expired }

BattleStatus battleStatusFrom(String raw) =>
    BattleStatus.values.firstWhere((s) => s.name == raw);

/// 방 유형 — 'all'(전체 케미) / 'match'(남녀 반반 이성 케미).
enum BattleRoomKind { all, match }

BattleRoomKind battleRoomKindFrom(String raw) =>
    BattleRoomKind.values.byName(raw);

String _ageRangeLabel(int? ageMin, int? ageMax) {
  if (ageMin == null || ageMax == null) return '전연령';
  if (ageMin == ageMax) return '$ageMin대';
  return '$ageMin대~$ageMax대';
}

class Battle {
  final String id;
  final String? ownerId;
  final String title;
  final bool isPublic;
  final int maxPlayers;
  final int? ageMin;
  final int? ageMax;
  final BattleRoomKind roomKind;
  final bool thumbOpen;
  final BattleStatus status;
  final DateTime? startedAt;
  final DateTime? closedAt;
  final Map<String, dynamic>? chemistrySnapshot;
  final Map<String, dynamic>? resultPayload;
  final DateTime createdAt;

  /// 현재 참가 인원 — 목록 조회(fetchMyBattles)가 채운다. 단건 조회는 null.
  final int? playerCount;

  const Battle({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.isPublic,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.roomKind,
    required this.thumbOpen,
    required this.status,
    required this.startedAt,
    required this.closedAt,
    required this.chemistrySnapshot,
    required this.resultPayload,
    required this.createdAt,
    this.playerCount,
  });

  factory Battle.fromRow(Map<String, dynamic> row, {int? playerCount}) =>
      Battle(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String?,
        title: row['title'] as String,
        isPublic: !(row['is_private'] as bool? ?? false),
        maxPlayers: (row['max_players'] as num).toInt(),
        ageMin: (row['age_min'] as num?)?.toInt(),
        ageMax: (row['age_max'] as num?)?.toInt(),
        roomKind: battleRoomKindFrom(row['room_kind'] as String),
        thumbOpen: row['thumb_open'] as bool,
        status: battleStatusFrom(row['status'] as String),
        startedAt: row['started_at'] == null
            ? null
            : DateTime.parse(row['started_at'] as String),
        closedAt: row['closed_at'] == null
            ? null
            : DateTime.parse(row['closed_at'] as String),
        chemistrySnapshot: row['chemistry_snapshot'] as Map<String, dynamic>?,
        resultPayload: row['result_payload'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(row['created_at'] as String),
        playerCount: playerCount,
      );

  bool get isRecruiting => status == BattleStatus.recruiting;
  bool get hasResult => resultPayload != null;
  String get ageRangeLabel => _ageRangeLabel(ageMin, ageMax);
}

class BattleRosterEntry {
  final String teamId;
  final String userId;
  final int slotNo;
  final String gender;
  final bool isOwner;
  final DateTime joinedAt;
  final String nickname;

  const BattleRosterEntry({
    required this.teamId,
    required this.userId,
    required this.slotNo,
    required this.gender,
    required this.isOwner,
    required this.joinedAt,
    required this.nickname,
  });

  factory BattleRosterEntry.fromRow(Map<String, dynamic> row) =>
      BattleRosterEntry(
        teamId: row['team_id'] as String,
        userId: row['user_id'] as String,
        slotNo: (row['slot_no'] as num).toInt(),
        gender: row['gender'] as String,
        isOwner: row['is_owner'] as bool,
        joinedAt: DateTime.parse(row['joined_at'] as String),
        nickname: (row['nickname'] as String?) ?? '참가자',
      );
}

class PublicBattle {
  final String id;
  final String title;
  final int maxPlayers;
  final int? ageMin;
  final int? ageMax;
  final BattleRoomKind roomKind;
  final bool thumbOpen;
  final bool isPrivate;
  final DateTime createdAt;
  final int playerCount;

  const PublicBattle({
    required this.id,
    required this.title,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.roomKind,
    required this.thumbOpen,
    required this.isPrivate,
    required this.createdAt,
    required this.playerCount,
  });

  factory PublicBattle.fromRow(Map<String, dynamic> row) => PublicBattle(
    id: row['id'] as String,
    title: row['title'] as String,
    maxPlayers: (row['max_players'] as num).toInt(),
    ageMin: (row['age_min'] as num?)?.toInt(),
    ageMax: (row['age_max'] as num?)?.toInt(),
    roomKind: battleRoomKindFrom(row['room_kind'] as String),
    thumbOpen: row['thumb_open'] as bool,
    isPrivate: row['is_private'] as bool? ?? false,
    createdAt: DateTime.parse(row['created_at'] as String),
    playerCount: (row['player_count'] as num).toInt(),
  );

  String get ageRangeLabel => _ageRangeLabel(ageMin, ageMax);
}

/// 서버 RPC 에러 계약 (Plan 1) — raise exception 메시지 문자열이 코드다.
enum BattleJoinError {
  authRequired('AUTH_REQUIRED', '로그인이 필요합니다'),
  notFound('NOT_FOUND', '존재하지 않는 방입니다'),
  notRecruiting('NOT_RECRUITING', '모집이 끝난 방입니다'),
  badPassword('BAD_PASSWORD', '비밀번호가 일치하지 않습니다'),
  noMyFace('NO_MY_FACE', '내 관상 등록이 필요합니다'),
  ageNotAllowed('AGE_NOT_ALLOWED', '이 방의 연령대에 해당하지 않습니다'),
  // GENDER_FULL 이 'FULL' 을 부분 문자열로 포함하므로 mapBattleError 의 순차
  // contains 매칭에서 full 보다 먼저 검사되도록 앞에 둔다.
  genderFull('GENDER_FULL', '이 방의 남녀 자리 중 한쪽이 다 찼습니다'),
  full('FULL', '정원이 가득 찼습니다'),
  alreadyJoined('ALREADY_JOINED', '이미 참가한 방입니다'),
  ownerCannotLeave('OWNER_CANNOT_LEAVE', '방장은 나갈 수 없습니다'),
  notLeavable('NOT_LEAVABLE', '지금은 나갈 수 없습니다'),
  notParticipant('NOT_PARTICIPANT', '참가자가 아닙니다'),
  unknown('UNKNOWN', '잠시 후 다시 시도해 주세요');

  final String code;
  final String labelKo;
  const BattleJoinError(this.code, this.labelKo);
}

BattleJoinError mapBattleError(Object e) {
  final msg = e is PostgrestException ? e.message : e.toString();
  for (final v in BattleJoinError.values) {
    if (v != BattleJoinError.unknown && msg.contains(v.code)) return v;
  }
  return BattleJoinError.unknown;
}

/// GENDER_FULL 중립 카피를 본인 성별로 분기 — 'male'→남자 자리, 그 외(female)→여자 자리.
String genderFullLabel(String myGender) =>
    myGender == 'male' ? '남자 자리가 다 찼습니다' : '여자 자리가 다 찼습니다';

/// 매칭 성사 — submit_battle_result 가 best 쌍을 확정해 생성, respond_match
/// 로 쌍 각자가 채팅 개설에 동의. consent: null=무응답, true=수락, false=거절.
class BattleMatch {
  final String teamId;
  final String userA;
  final String userB;
  final bool? aConsent;
  final bool? bConsent;
  final DateTime? openedAt;

  const BattleMatch({
    required this.teamId,
    required this.userA,
    required this.userB,
    required this.aConsent,
    required this.bConsent,
    required this.openedAt,
  });

  factory BattleMatch.fromRow(Map<String, dynamic> row) => BattleMatch(
    teamId: row['team_id'] as String,
    userA: row['user_a'] as String,
    userB: row['user_b'] as String,
    aConsent: row['a_consent'] as bool?,
    bConsent: row['b_consent'] as bool?,
    openedAt: row['opened_at'] == null
        ? null
        : DateTime.parse(row['opened_at'] as String),
  );

  bool get isOpen => openedAt != null;

  bool? consentOf(String uid) {
    if (uid == userA) return aConsent;
    if (uid == userB) return bConsent;
    return null;
  }

  String otherOf(String uid) => uid == userA ? userB : userA;
}

class BattleMessage {
  final String id;
  final String teamId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const BattleMessage({
    required this.id,
    required this.teamId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory BattleMessage.fromRow(Map<String, dynamic> row) => BattleMessage(
    id: row['id'] as String,
    teamId: row['team_id'] as String,
    senderId: row['sender_id'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// chemistry_snapshot({user_id: body}) + roster → 엔진 입력.
/// snapshot 에 없는 참가자(계정 삭제 극단 케이스)는 제외. slot 오름차순.
/// gender 는 roster(join_battle 조인 시점 서버 강제값)에서 읽는다 — report
/// 재파싱이 아닌 서버와 동일 소스.
List<BattlePlayer> assembleBattlePlayers({
  required List<BattleRosterEntry> roster,
  required Map<String, dynamic> snapshot,
}) {
  final players = <BattlePlayer>[];
  for (final entry in roster) {
    final body = snapshot[entry.userId];
    if (body == null) continue;
    final report = FaceReadingReport.fromJsonString(jsonEncode(body));
    players.add(
      BattlePlayer(
        slot: entry.slotNo,
        name: entry.nickname,
        gender: entry.gender,
        report: report,
      ),
    );
  }
  players.sort((a, b) => a.slot.compareTo(b.slot));
  return players;
}
