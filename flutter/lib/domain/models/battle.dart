import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/battle.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Chemistry Battle 클라이언트 모델 — Plan 1 서버 계약(teams·battle_roster·
/// public_battles·RPC 에러 문자열)의 Dart 표현. 서버가 SSOT, 여기는 파싱만.

enum BattleStatus { recruiting, revealing, completed, expired }

BattleStatus battleStatusFrom(String raw) =>
    BattleStatus.values.firstWhere((s) => s.name == raw);

String _ageRangeLabel(int? ageMin, int? ageMax) {
  if (ageMin == null || ageMax == null) return '전연령';
  if (ageMin == ageMax) return '$ageMin대';
  return '$ageMin~${ageMax + 9}세';
}

class Battle {
  final String id;
  final String? ownerId;
  final String title;
  final bool isPublic;
  final int maxPlayers;
  final int? ageMin;
  final int? ageMax;
  final String? pledge;
  final String? chatUrl;
  final BattleStatus status;
  final DateTime? startedAt;
  final DateTime? closedAt;
  final Map<String, dynamic>? chemistrySnapshot;
  final Map<String, dynamic>? resultPayload;
  final DateTime createdAt;

  const Battle({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.isPublic,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.pledge,
    required this.chatUrl,
    required this.status,
    required this.startedAt,
    required this.closedAt,
    required this.chemistrySnapshot,
    required this.resultPayload,
    required this.createdAt,
  });

  factory Battle.fromRow(Map<String, dynamic> row) => Battle(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String?,
        title: row['title'] as String,
        isPublic: (row['visibility'] as String) == 'public',
        maxPlayers: (row['max_players'] as num).toInt(),
        ageMin: (row['age_min'] as num?)?.toInt(),
        ageMax: (row['age_max'] as num?)?.toInt(),
        pledge: row['pledge'] as String?,
        chatUrl: row['chat_url'] as String?,
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
      );

  bool get isRecruiting => status == BattleStatus.recruiting;
  bool get hasResult => resultPayload != null;
  String get ageRangeLabel => _ageRangeLabel(ageMin, ageMax);
}

class BattleRosterEntry {
  final String teamId;
  final String userId;
  final int slotNo;
  final bool isOwner;
  final DateTime joinedAt;
  final String nickname;

  const BattleRosterEntry({
    required this.teamId,
    required this.userId,
    required this.slotNo,
    required this.isOwner,
    required this.joinedAt,
    required this.nickname,
  });

  factory BattleRosterEntry.fromRow(Map<String, dynamic> row) =>
      BattleRosterEntry(
        teamId: row['team_id'] as String,
        userId: row['user_id'] as String,
        slotNo: (row['slot_no'] as num).toInt(),
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
  final String? pledge;
  final DateTime createdAt;
  final int playerCount;

  const PublicBattle({
    required this.id,
    required this.title,
    required this.maxPlayers,
    required this.ageMin,
    required this.ageMax,
    required this.pledge,
    required this.createdAt,
    required this.playerCount,
  });

  factory PublicBattle.fromRow(Map<String, dynamic> row) => PublicBattle(
        id: row['id'] as String,
        title: row['title'] as String,
        maxPlayers: (row['max_players'] as num).toInt(),
        ageMin: (row['age_min'] as num?)?.toInt(),
        ageMax: (row['age_max'] as num?)?.toInt(),
        pledge: row['pledge'] as String?,
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

/// chemistry_snapshot({user_id: body}) + roster → 엔진 입력.
/// snapshot 에 없는 참가자(계정 삭제 극단 케이스)는 제외. slot 오름차순.
List<BattlePlayer> assembleBattlePlayers({
  required List<BattleRosterEntry> roster,
  required Map<String, dynamic> snapshot,
}) {
  final players = <BattlePlayer>[];
  for (final entry in roster) {
    final body = snapshot[entry.userId];
    if (body == null) continue;
    final report = FaceReadingReport.fromJsonString(jsonEncode(body));
    players.add(BattlePlayer(
      slot: entry.slotNo,
      name: entry.nickname,
      gender: report.gender.name,
      report: report,
    ));
  }
  players.sort((a, b) => a.slot.compareTo(b.slot));
  return players;
}
