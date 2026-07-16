# Chemistry Battle — Plan 2/3: Flutter 전면 개편 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 케미 탭을 게임 로비 기반 Chemistry Battle 로 전면 교체 — 공개 배틀 목록·방 생성 스텝·Realtime 로비(QR)·조인·카운트다운 리빌 화면을 서버-우선(Plan 1 스키마/RPC) 위에 새로 만들고, 이름 슬롯·walk-in·lazy sync 세계를 삭제한다.

**Architecture:** 신규 파일을 먼저 쌓고(Task 1~6, 매 커밋 컴파일 그린), 마지막 Task 7 에서 한 번에 cutover (chemistry_screen 재작성 + 라우터 교체 + 구 파일 일괄 삭제). 데이터 계층은 `BattleService`(Supabase RPC·view 쿼리·Realtime 채널) + 얇은 FutureProvider 둘. 계산은 Plan 1 의 `computeBattle`(shared)이 SSOT.

**Tech Stack:** Flutter/Riverpod 3.x · supabase_flutter ^2.8.4 (Realtime channel 신규 도입) · qr_flutter (신규 의존성) · shared `face_engine`.

**Spec:** `docs/superpowers/specs/2026-07-16-chemistry-battle-design.md` · 서버 계약은 Plan 1 산출 (`0001_baseline.sql` §11-2~11-5).

## Global Constraints

- UI 통일감 절대 1순위: inline TextStyle/Color/매직넘버 금지 — `AppText`/`AppColors`/`AppSpacing`(4/8/12/16/20/24/32)/`AppRadius`(6/10/14/16) 토큰만. SongMyung 은 `AppText.display`/`appBarTitle` 토큰에만 내장. 아이콘은 `FaIcon(FontAwesomeIcons.*)` 만 (Material/Cupertino 금지). CTA = 흰 배경 + 1px textPrimary border (`PrimaryButton`). 신규 색상 도입 금지 — 밴드 색은 기존 `_kBand*` 4색 재사용.
- 공용 위젯(`PrimaryButton`·`DetailAvatar`·`EmotionEmptyState`·`FaceScanPill`·`CompactSnackBar`·`login_bottom_sheet`) 사용 시 **반드시 해당 위젯 소스를 먼저 읽고 실제 시그니처에 맞출 것** — 본 계획의 코드는 구조·토큰이 규범이고, 공용 위젯 생성자 파라미터는 실소스가 규범이다.
- UI 문구: 한자 단독 표기 금지 · 검증 안 된 감정/효과 단정 카피 금지 ("재밌어요" 류) · 가운데점(`·`)으로 두 의미 잇기 금지.
- payload·모델에 version 필드 금지.
- 서버 에러 메시지 계약 (Plan 1): `AUTH_REQUIRED`·`NOT_FOUND`·`NOT_RECRUITING`·`BAD_PASSWORD`·`NO_MY_FACE`·`AGE_NOT_ALLOWED`·`FULL`·`ALREADY_JOINED`·`OWNER_CANNOT_LEAVE`·`NOT_LEAVABLE`·`NOT_PARTICIPANT`.
- result_payload 계약: `{players:[{slot,name}], pairs:[{a,b,band}], best:{a,b,score}}` — pairs 는 raw total 내림차순(인덱스=순위), band 0~3.
- 게이트: `cd flutter && flutter test` 전부 green · `flutter analyze` 기준선 7건 외 신규 0.
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## 파일 구조

| 파일 | 상태 | 책임 |
|---|---|---|
| `lib/domain/models/battle.dart` | 신규 | Battle/BattleRosterEntry/PublicBattle 모델 + BattleJoinError 매핑 + assembleBattlePlayers |
| `lib/data/services/battle_service.dart` | 신규 | RPC(join/leave/submit)·쿼리(public_battles/battle_roster/teams)·Realtime 채널 |
| `lib/presentation/providers/battle_provider.dart` | 신규 | myBattlesProvider / publicBattlesProvider (FutureProvider) |
| `lib/presentation/screens/team/battle_band.dart` | 신규 | band 0~3 → 색·이모지·라벨 (기존 4색 승계) |
| `lib/presentation/screens/team/battle_create_page.dart` | 신규 | 생성 스텝 플로우 (이름→인원→공개/비밀→연령→공약) |
| `lib/presentation/screens/team/team_lobby_screen.dart` | 신규 | 로비 — 슬롯 그리드·QR·공약 배너·초대·Realtime |
| `lib/presentation/screens/team/battle_join_screen.dart` | 신규 | /g/:id 조인 (로그인·my-face·PIN·공약 동의) |
| `lib/presentation/screens/team/team_reveal_screen.dart` | 신규 | 카운트다운→Best→공약→매트릭스·순위·unlock |
| `lib/presentation/screens/chemistry/chemistry_screen.dart` | 재작성(T7) | 공개 배틀/내 배틀 2탭 |
| `pubspec.yaml` | 수정 | qr_flutter 추가 |
| `config/router.dart`·`hive_setup.dart`·`history_provider.dart`·`onboarding_intro.dart` | 수정(T7) | cutover 배선 |
| 삭제(T7) | — | team_room_screen·team_matrix_screen·team_matrix_snapshot_screen·team_create_page·team_join_screen·team_band·team_matrix.dart·team_provider·team_sync_service·domain/models/team_room.dart·test/team_matrix_test.dart·test/team_text_input_dialog_test.dart |

---

### Task 1: Battle 모델 + 에러 매핑 + 플레이어 조립 (TDD)

**Files:**
- Create: `flutter/lib/domain/models/battle.dart`
- Test: `flutter/test/battle_model_test.dart`

**Interfaces:**
- Consumes: Plan 1 스키마 row 형태(teams/battle_roster/public_battles), shared `BattlePlayer` (`package:face_engine/domain/services/compat/battle.dart`), `FaceReadingReport.fromJsonString`/`toBodyJson`.
- Produces (후속 task 전부가 사용):
  - `enum BattleStatus { recruiting, revealing, completed, expired }` + `BattleStatus battleStatusFrom(String)`
  - `class Battle { String id; String? ownerId; String title; bool isPublic; int maxPlayers; int? ageMin; int? ageMax; String? pledge; String? chatUrl; BattleStatus status; DateTime? startedAt; DateTime? closedAt; Map<String,dynamic>? chemistrySnapshot; Map<String,dynamic>? resultPayload; DateTime createdAt; factory Battle.fromRow(Map<String,dynamic>); }` + getters `bool get isRecruiting/hasResult`, `String ageRangeLabel`
  - `class BattleRosterEntry { String teamId; String userId; int slotNo; bool isOwner; String nickname; factory fromRow; }`
  - `class PublicBattle { String id; String title; int maxPlayers; int? ageMin; int? ageMax; String? pledge; int playerCount; factory fromRow; }` + `String ageRangeLabel`
  - `enum BattleJoinError { authRequired('AUTH_REQUIRED','로그인이 필요합니다'), … , unknown } — .code/.labelKo` + `BattleJoinError mapBattleError(Object e)`
  - `List<BattlePlayer> assembleBattlePlayers({required List<BattleRosterEntry> roster, required Map<String,dynamic> snapshot})`

- [ ] **Step 1: 실패하는 테스트 작성**

`flutter/test/battle_model_test.dart`:

```dart
// Battle 모델 파싱·에러 매핑·플레이어 조립 검증 — Plan 1 서버 계약과의 접점.
// 실행: flutter test test/battle_model_test.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/models/battle.dart';
import 'package:facely/domain/services/mc_fixtures.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

FaceReadingReport _fakeReport(Random rng) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree(frontalZ);
  final nodeScores = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    nodeScores[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final c in node.children) {
      walk(c);
    }
  }

  walk(tree);
  final metrics = <String, MetricResult>{
    for (final info in metricInfoList)
      info.id: MetricResult(
        id: info.id,
        rawValue: 0.5,
        zScore: frontalZ[info.id]!,
        zAdjusted: frontalZ[info.id]!,
        metricScore: 0,
      ),
  };
  final attributes = <Attribute, AttributeEvidence>{
    for (final a in Attribute.values)
      a: AttributeEvidence(
        rawTotal: 0.0,
        normalizedScore: 7.5,
        basePerNode: const {},
        distinctiveness: 0.0,
        contributors: const [],
      ),
  };
  final flat = {for (final a in Attribute.values) a: 7.5};
  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: Gender.female,
    ageGroup: AgeGroup.twenties,
    timestamp: DateTime(2026, 7, 16),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, Gender.female, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
}

void main() {
  test('Battle.fromRow — teams row 파싱 (snake_case, nullable 전부)', () {
    final battle = Battle.fromRow({
      'id': 'b1',
      'owner_id': 'u1',
      'title': '영화보러가자!',
      'visibility': 'public',
      'max_players': 8,
      'age_min': 20,
      'age_max': 30,
      'pledge': '🎬 영화',
      'chat_url': 'https://open.kakao.com/o/x',
      'status': 'recruiting',
      'started_at': null,
      'closed_at': null,
      'chemistry_snapshot': null,
      'result_payload': null,
      'created_at': '2026-07-16T09:00:00Z',
    });
    expect(battle.id, 'b1');
    expect(battle.isPublic, isTrue);
    expect(battle.status, BattleStatus.recruiting);
    expect(battle.isRecruiting, isTrue);
    expect(battle.hasResult, isFalse);
    expect(battle.ageRangeLabel, '20~39세');
  });

  test('ageRangeLabel — 전연령·단일 decade·범위', () {
    Battle b(int? lo, int? hi) => Battle.fromRow({
          'id': 'x',
          'owner_id': null,
          'title': 't',
          'visibility': 'private',
          'max_players': 4,
          'age_min': lo,
          'age_max': hi,
          'pledge': null,
          'chat_url': null,
          'status': 'expired',
          'started_at': null,
          'closed_at': null,
          'chemistry_snapshot': null,
          'result_payload': null,
          'created_at': '2026-07-16T09:00:00Z',
        });
    expect(b(null, null).ageRangeLabel, '전연령');
    expect(b(30, 30).ageRangeLabel, '30대');
    expect(b(20, 30).ageRangeLabel, '20~39세');
    expect(b(40, 50).ageRangeLabel, '40~59세');
  });

  test('BattleRosterEntry / PublicBattle fromRow', () {
    final entry = BattleRosterEntry.fromRow({
      'team_id': 'b1',
      'user_id': 'u2',
      'slot_no': 3,
      'is_owner': false,
      'joined_at': '2026-07-16T09:10:00Z',
      'nickname': '철수',
    });
    expect(entry.slotNo, 3);
    expect(entry.nickname, '철수');

    final pub = PublicBattle.fromRow({
      'id': 'b1',
      'title': '점심 케미 배틀',
      'max_players': 6,
      'age_min': null,
      'age_max': null,
      'pledge': null,
      'created_at': '2026-07-16T09:00:00Z',
      'player_count': 2,
    });
    expect(pub.playerCount, 2);
    expect(pub.ageRangeLabel, '전연령');
  });

  test('mapBattleError — 서버 에러 계약 문자열 매핑', () {
    expect(
      mapBattleError(const PostgrestException(message: 'BAD_PASSWORD')),
      BattleJoinError.badPassword,
    );
    expect(
      mapBattleError(const PostgrestException(message: 'AGE_NOT_ALLOWED')),
      BattleJoinError.ageNotAllowed,
    );
    expect(
      mapBattleError(const PostgrestException(message: 'FULL')),
      BattleJoinError.full,
    );
    expect(
      mapBattleError(Exception('boom')),
      BattleJoinError.unknown,
    );
    // 모든 값이 한국어 라벨을 가진다 (빈 문자열 금지).
    for (final e in BattleJoinError.values) {
      expect(e.labelKo, isNotEmpty);
    }
  });

  test('assembleBattlePlayers — roster+snapshot → slot 오름차순 BattlePlayer', () {
    final rng = Random(42);
    final bodyA = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    final bodyB = jsonDecode(_fakeReport(rng).toBodyJson()) as Map<String, dynamic>;
    final roster = [
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u2', 'slot_no': 2,
        'is_owner': false, 'joined_at': '2026-07-16T09:10:00Z', 'nickname': '영희',
      }),
      BattleRosterEntry.fromRow({
        'team_id': 'b1', 'user_id': 'u1', 'slot_no': 1,
        'is_owner': true, 'joined_at': '2026-07-16T09:00:00Z', 'nickname': '지은',
      }),
    ];
    final players = assembleBattlePlayers(
      roster: roster,
      snapshot: {'u1': bodyA, 'u2': bodyB},
    );
    expect(players.length, 2);
    expect(players.first.slot, 1);
    expect(players.first.name, '지은');
    expect(players.last.slot, 2);
    // snapshot 에 없는 참가자는 제외 (계정 삭제 등 극단 케이스 방어).
    final partial = assembleBattlePlayers(
      roster: roster,
      snapshot: {'u1': bodyA},
    );
    expect(partial.length, 1);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd flutter && flutter test test/battle_model_test.dart`
Expected: FAIL — battle.dart 부재 컴파일 에러

- [ ] **Step 3: 구현**

`flutter/lib/domain/models/battle.dart`:

```dart
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
    players.add(BattlePlayer(
      slot: entry.slotNo,
      name: entry.nickname,
      report: FaceReadingReport.fromJsonString(jsonEncode(body)),
    ));
  }
  players.sort((a, b) => a.slot.compareTo(b.slot));
  return players;
}
```

- [ ] **Step 4: 테스트 통과 + 게이트**

Run: `cd flutter && flutter test test/battle_model_test.dart && flutter test && flutter analyze`
Expected: 신규 5 test PASS · 전체 green · analyze 신규 0

주의: `FaceReadingReport.toBodyJson()` 이 이 시그니처가 아니면(예: `toJsonString`) 실소스(`shared/lib/domain/models/face_reading_report.dart`)를 열어 **서버 metrics.body 를 만드는 그 메서드**로 테스트를 맞춰라 — body 파싱 왕복이 이 테스트의 요지다.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/domain/models/battle.dart flutter/test/battle_model_test.dart
git commit -m "feat(app): Battle 모델 — 서버 계약 파싱·에러 매핑·플레이어 조립

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: BattleService + providers

**Files:**
- Create: `flutter/lib/data/services/battle_service.dart`
- Create: `flutter/lib/presentation/providers/battle_provider.dart`

**Interfaces:**
- Consumes: Task 1 모델, `Supabase.instance.client`, RPC 호출 관례(`client.rpc(name, params: {...})` — `compat_unlock_service.dart:99` 패턴), `ShareReceiveService.fetchByUuid` (라이브 리포트 fetch).
- Produces (화면 task 전부가 사용):
  - `class BattleService` singleton (`BattleService.instance`):
    - `Future<Battle> createBattle({required String title, required bool isPublic, String? password, required int maxPlayers, int? ageMin, int? ageMax, String? pledge, String? chatUrl})`
    - `Future<void> joinBattle(String battleId, {String? password})` — 실패 시 원 예외 throw (호출부가 mapBattleError)
    - `Future<void> leaveBattle(String battleId)` / `Future<void> deleteBattle(String battleId)`
    - `Future<void> submitResult(String battleId, Map<String,dynamic> payload)`
    - `Future<Battle?> fetchBattle(String battleId)` / `Future<List<BattleRosterEntry>> fetchRoster(String battleId)`
    - `Future<List<PublicBattle>> fetchPublicBattles()` / `Future<List<Battle>> fetchMyBattles()`
    - `Future<Map<String,String?>> fetchMyFaceThumbnailUrls(List<String> userIds)` — 로비 아바타용 CDN URL
    - `Future<FaceReadingReport?> fetchLiveReport(String userId)` — 쌍 상세 unlock 용 현재 my-face
    - `RealtimeChannel watchBattle(String battleId, void Function() onChange)` / `Future<void> unwatch(RealtimeChannel)`
    - `String? get myUid` / `bool get isLoggedIn`
  - `battle_provider.dart`: `final publicBattlesProvider = FutureProvider<List<PublicBattle>>(...)` · `final myBattlesProvider = FutureProvider<List<Battle>>(...)` (로그아웃 시 빈 리스트)

- [ ] **Step 1: 구현**

`flutter/lib/data/services/battle_service.dart`:

```dart
import 'dart:convert';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          if (password != null) 'password': password,
          'max_players': maxPlayers,
          if (ageMin != null) 'age_min': ageMin,
          if (ageMax != null) 'age_max': ageMax,
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
        if (password != null) 'p_password': password,
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
        result[uid] = key == null ? null : cdnUrlForThumbnailKey(key);
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
```

주의 2건:
- `cdnUrlForThumbnailKey` 는 존재 확인 필요 — `lib/core/thumbnail_paths.dart` 를 열어 **thumbnailKey → CDN URL 을 만드는 실제 함수명**으로 교체하라 (없으면 그 파일의 기존 CDN base 상수로 `'$cdnBase/$key'` 조립 헬퍼를 battle_service 내 private 로 작성).
- `ShareReceiveService` 생성자/`fetchByUuid` 시그니처는 `share_receive_service.dart` 실소스에 맞춰라.

`flutter/lib/presentation/providers/battle_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/battle_service.dart';
import '../../domain/models/battle.dart';

/// 서버 우선 — 로컬 캐시 없음. 새로고침은 ref.invalidate 로.
final publicBattlesProvider = FutureProvider<List<PublicBattle>>(
  (ref) => BattleService.instance.fetchPublicBattles(),
);

final myBattlesProvider = FutureProvider<List<Battle>>(
  (ref) => BattleService.instance.fetchMyBattles(),
);
```

- [ ] **Step 2: 게이트**

Run: `cd flutter && flutter analyze && flutter test`
Expected: analyze 신규 0 (unused 경고 없어야 — provider 는 아직 미사용이지만 top-level final 이라 무해) · 전체 test green

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/data/services/battle_service.dart flutter/lib/presentation/providers/battle_provider.dart
git commit -m "feat(app): BattleService — RPC·view 쿼리·Realtime 채널 + providers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: battle_band + 방 생성 스텝 플로우

**Files:**
- Create: `flutter/lib/presentation/screens/team/battle_band.dart`
- Create: `flutter/lib/presentation/screens/team/battle_create_page.dart`

**Interfaces:**
- Consumes: Task 1 모델, Task 2 `BattleService.instance.createBattle/joinBattle`, `PrimaryButton`, `CompactSnackBar`.
- Produces:
  - `extension BattleBand on int` — `Color get bandColor` / `String get bandEmoji` / `String get bandLabel` (band 코드 0~3)
  - `Future<Battle?> showBattleCreatePage(BuildContext context)` — 생성+셀프조인까지 끝낸 Battle 반환 (취소 시 null). 호출부는 로비로 push 만.
  - `class AgePreset` 목록: 전체(null,null) · 10대(10,10) · 20대(20,20) · 30대(30,30) · 20~39세(20,30) · 40~59세(40,50)
  - 공약 프리셋: 🎬 영화 · ☕ 커피 · 🍜 밥 한 끼 · 🎤 노래방 · 직접입력(40자)

- [ ] **Step 1: battle_band.dart 작성**

```dart
import 'package:flutter/material.dart';

// 기존 케미 4밴드 색 승계 (신규 색상 도입 금지).
const _kBandGreen = Color(0xFF2E7D32);
const _kBandBlue = Color(0xFF1565C0);
const _kBandOrange = Color(0xFFEF6C00);
const _kBandRed = Color(0xFFD32F2F);

/// result_payload 의 band 코드(0~3 = CompatLabel.index) 표기.
extension BattleBand on int {
  Color get bandColor => switch (this) {
        0 => _kBandGreen,
        1 => _kBandBlue,
        2 => _kBandOrange,
        _ => _kBandRed,
      };

  String get bandEmoji => switch (this) {
        0 => '🟢',
        1 => '🔵',
        2 => '🟠',
        _ => '🔴',
      };

  String get bandLabel => switch (this) {
        0 => '천작지합',
        1 => '금슬상화',
        2 => '마합가성',
        _ => '형극난조',
      };
}
```

- [ ] **Step 2: battle_create_page.dart 작성**

기존 `showTeamCreatePage`(풀페이지 모달 바텀시트, Toss 스텝) 골격 승계 — 파일을 열어 모달 래퍼 관례(showModalBottomSheet isScrollControlled + 높이/라운드)를 그대로 가져오고, 스텝 내용만 아래로 교체한다. 이름 칩(pendingNames) 스텝은 존재하지 않는다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/primary_button.dart';

/// 방 생성 스텝: 이름 → 인원(4~12) → 공개/비밀(+PIN) → 연령대 → 공약(선택)
/// → [배틀 만들기] = createBattle + joinBattle(셀프 조인) 후 Battle 반환.
Future<Battle?> showBattleCreatePage(BuildContext context) {
  return showModalBottomSheet<Battle>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    builder: (_) => const _BattleCreatePage(),
  );
}

enum _Step { name, count, access, age, pledge }

class _AgePreset {
  final String label;
  final int? min;
  final int? max;
  const _AgePreset(this.label, this.min, this.max);
  bool get isAdult => min != null && min! >= 20;
}

const _kAgePresets = [
  _AgePreset('전연령', null, null),
  _AgePreset('10대', 10, 10),
  _AgePreset('20대', 20, 20),
  _AgePreset('30대', 30, 30),
  _AgePreset('20~39세', 20, 30),
  _AgePreset('40~59세', 40, 50),
];

const _kPledgePresets = ['🎬 영화', '☕ 커피', '🍜 밥 한 끼', '🎤 노래방'];

class _BattleCreatePage extends StatefulWidget {
  const _BattleCreatePage();

  @override
  State<_BattleCreatePage> createState() => _BattleCreatePageState();
}

class _BattleCreatePageState extends State<_BattleCreatePage> {
  _Step _step = _Step.name;
  final _titleCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pledgeCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  int _maxPlayers = 8;
  bool _isPublic = false;
  _AgePreset _age = _kAgePresets.first;
  String? _pledgePreset; // null = 공약 없음, '' = 직접입력 모드
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pinCtrl.dispose();
    _pledgeCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  String? get _pledgeValue {
    if (_pledgePreset == null) return null;
    final text =
        _pledgePreset!.isEmpty ? _pledgeCtrl.text.trim() : _pledgePreset!;
    return text.isEmpty ? null : text;
  }

  // 공개방 + 공약 → 성인 연령대 강제 (서버 CHECK 와 동일 규칙의 UI 게이트).
  bool get _pledgeAllowed => !_isPublic || _age.isAdult;

  bool get _stepValid => switch (_step) {
        _Step.name => _titleCtrl.text.trim().isNotEmpty,
        _Step.count => true,
        _Step.access => _isPublic || _pinCtrl.text.trim().length == 4,
        _Step.age => true,
        _Step.pledge => _pledgeValue == null || _pledgeAllowed,
      };

  Future<void> _create() async {
    setState(() => _busy = true);
    final service = BattleService.instance;
    try {
      final battle = await service.createBattle(
        title: _titleCtrl.text.trim(),
        isPublic: _isPublic,
        password: _isPublic ? null : _pinCtrl.text.trim(),
        maxPlayers: _maxPlayers,
        ageMin: _age.min,
        ageMax: _age.max,
        pledge: _pledgeAllowed ? _pledgeValue : null,
        chatUrl: _pledgeValue == null ? null : _chatCtrl.text.trim(),
      );
      await service.joinBattle(battle.id,
          password: _isPublic ? null : _pinCtrl.text.trim());
      if (mounted) Navigator.of(context).pop(battle);
    } catch (e) {
      if (mounted) {
        CompactSnackBar.error(context, mapBattleError(e).labelKo);
        setState(() => _busy = false);
      }
    }
  }

  void _next() {
    if (_step == _Step.pledge) {
      _create();
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.name) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step = _Step.values[_step.index - 1]);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(
                  onPressed: _busy ? null : _back,
                  icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
                ),
                const Spacer(),
                Text(
                  '${_step.index + 1} / ${_Step.values.length}',
                  style: AppText.hint,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Expanded(child: SingleChildScrollView(child: _stepBody())),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _step == _Step.pledge ? '배틀 만들기' : '다음',
              busy: _busy,
              onPressed: _stepValid && !_busy ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
        _Step.name => _nameStep(),
        _Step.count => _countStep(),
        _Step.access => _accessStep(),
        _Step.age => _ageStep(),
        _Step.pledge => _pledgeStep(),
      };

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('배틀 방 이름', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('방 목록과 초대장에 그대로 보입니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _titleCtrl,
          autofocus: true,
          maxLength: 24,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: '예: 우리 팀 케미 배틀'),
        ),
      ],
    );
  }

  Widget _countStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참가 인원', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('정원이 다 차면 배틀이 자동으로 시작됩니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _maxPlayers > 4
                  ? () => setState(() => _maxPlayers--)
                  : null,
              icon: const FaIcon(FontAwesomeIcons.minus, size: 18),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Text('$_maxPlayers명', style: AppText.display),
            ),
            IconButton(
              onPressed: _maxPlayers < 12
                  ? () => setState(() => _maxPlayers++)
                  : null,
              icon: const FaIcon(FontAwesomeIcons.plus, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _accessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공개 방식', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _choiceTile(
          selected: _isPublic,
          title: '공개방',
          caption: '공개 배틀 목록에서 누구나 참가할 수 있습니다',
          onTap: () => setState(() => _isPublic = true),
        ),
        const SizedBox(height: AppSpacing.md),
        _choiceTile(
          selected: !_isPublic,
          title: '비밀방',
          caption: '비밀번호를 아는 사람만 참가할 수 있습니다',
          onTap: () => setState(() => _isPublic = false),
        ),
        if (!_isPublic) ...[
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '비밀번호 4자리'),
          ),
        ],
      ],
    );
  }

  Widget _ageStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참가 연령대', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final preset in _kAgePresets)
              ChoiceChip(
                label: Text(preset.label, style: AppText.caption),
                selected: _age == preset,
                onSelected: (_) => setState(() => _age = preset),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pledgeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공약 (선택)', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('베스트 케미로 뽑힌 두 사람이 실행합니다', style: AppText.caption),
        if (!_pledgeAllowed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '공개방 공약은 20세 이상 연령대 설정이 필요합니다',
            style: AppText.caption.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: Text('공약 없음', style: AppText.caption),
              selected: _pledgePreset == null,
              onSelected: (_) => setState(() => _pledgePreset = null),
            ),
            for (final preset in _kPledgePresets)
              ChoiceChip(
                label: Text(preset, style: AppText.caption),
                selected: _pledgePreset == preset,
                onSelected:
                    _pledgeAllowed ? (_) => setState(() => _pledgePreset = preset) : null,
              ),
            ChoiceChip(
              label: Text('직접입력', style: AppText.caption),
              selected: _pledgePreset == '',
              onSelected:
                  _pledgeAllowed ? (_) => setState(() => _pledgePreset = '') : null,
            ),
          ],
        ),
        if (_pledgePreset == '') ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _pledgeCtrl,
            maxLength: 40,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '공약 내용'),
          ),
        ],
        if (_pledgeValue != null) ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _chatCtrl,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '카카오 오픈채팅 링크 (선택)',
              helperText: '결과 발표에서 당첨된 두 사람에게만 표시됩니다',
            ),
          ),
        ],
      ],
    );
  }

  Widget _choiceTile({
    required bool selected,
    required String title,
    required String caption,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.subTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(caption, style: AppText.caption),
          ],
        ),
      ),
    );
  }
}
```

주의: `PrimaryButton`/`CompactSnackBar` 시그니처·`InputDecoration` 테마 관례는 실소스 확인 후 맞출 것. `ChoiceChip` 이 앱 테마와 어긋나면 기존 chip 레시피(AppRadius.sm 단일톤)를 따르는 file-local `_chip` 헬퍼로 교체 가능 — 단일 색·단일 크기 규칙 유지.

- [ ] **Step 3: 게이트 + Commit**

Run: `cd flutter && flutter analyze && flutter test`
Expected: 신규 이슈 0 · 전체 green

```bash
git add flutter/lib/presentation/screens/team/battle_band.dart flutter/lib/presentation/screens/team/battle_create_page.dart
git commit -m "feat(app): 배틀 밴드 표기 + 방 생성 스텝 플로우 (이름·인원·공개/비밀·연령·공약)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 로비 화면 (Realtime + QR) + qr_flutter 의존성

**Files:**
- Modify: `flutter/pubspec.yaml` (dependencies 에 `qr_flutter: ^4.1.0` 추가)
- Create: `flutter/lib/presentation/screens/team/team_lobby_screen.dart`

**Interfaces:**
- Consumes: Task 1~3 산출, `SharePublisher.instance.teamInviteUrl/publishTeamInvite/shareTeamInviteLink`, `BattleService.watchBattle/unwatch/fetchBattle/fetchRoster/fetchMyFaceThumbnailUrls/leaveBattle/deleteBattle`.
- Produces: `class TeamLobbyScreen extends StatefulWidget { final String battleId; }` — recruiting 방의 대기 화면. status 가 revealing/completed 로 바뀌면 `TeamRevealScreen` 으로 pushReplacement (Task 5 산출물 — 이 task 시점엔 아직 없으므로 **TODO 없이** 콜백 주입으로 분리한다: 생성자에 `void Function(BuildContext, Battle)? onBattleStarted` 를 두고, null 이면 화면 내 안내만. Task 7 cutover 에서 실제 네비게이션을 주입).

  → 단순화 결정: 콜백 주입 대신 **Task 5 를 먼저 구현하지 않아도 컴파일되도록**, 이 task 에서는 `_onBattleStarted(Battle)` 를 화면 내부 hook 메서드(현재 body: 안내 스낵바)로 두고, Task 5 에서 TeamRevealScreen 이 생기면 **Task 5 의 마지막 스텝이 이 hook 을 pushReplacement 로 교체**한다.

- [ ] **Step 1: pubspec 의존성 추가**

`flutter/pubspec.yaml` 의 dependencies 블록에 (알파벳 순 위치에) 추가:

```yaml
  qr_flutter: ^4.1.0
```

Run: `cd flutter && flutter pub get`
Expected: exit 0

- [ ] **Step 2: team_lobby_screen.dart 작성**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../../domain/services/share/share_publisher.dart';
import '../../providers/battle_provider.dart';
import '../../widgets/compact_snack_bar.dart';

/// Chemistry Battle 로비 — 슬롯이 차오르는 대기 화면.
/// Realtime(teams UPDATE + team_members INSERT/DELETE) 구독 + 10초 폴링
/// 안전망. 정원 충족(status=revealing)을 감지하면 리빌로 넘어간다.
class TeamLobbyScreen extends ConsumerStatefulWidget {
  final String battleId;
  const TeamLobbyScreen({super.key, required this.battleId});

  @override
  ConsumerState<TeamLobbyScreen> createState() => _TeamLobbyScreenState();
}

class _TeamLobbyScreenState extends ConsumerState<TeamLobbyScreen> {
  final _service = BattleService.instance;
  Battle? _battle;
  List<BattleRosterEntry> _roster = const [];
  Map<String, String?> _thumbs = const {};
  RealtimeChannel? _channel;
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _channel = _service.watchBattle(widget.battleId, _refresh);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    super.dispose();
  }

  Future<void> _refresh() async {
    final battle = await _service.fetchBattle(widget.battleId);
    if (!mounted) return;
    if (battle == null) {
      Navigator.of(context).maybePop();
      return;
    }
    if (battle.status != BattleStatus.recruiting) {
      _onBattleStarted(battle);
      return;
    }
    final roster = await _service.fetchRoster(widget.battleId);
    final thumbs = await _service
        .fetchMyFaceThumbnailUrls([for (final r in roster) r.userId]);
    if (!mounted) return;
    setState(() {
      _battle = battle;
      _roster = roster;
      _thumbs = thumbs;
      _loading = false;
    });
  }

  /// 배틀 시작 감지 hook — Task 5 에서 TeamRevealScreen pushReplacement 로 교체.
  void _onBattleStarted(Battle battle) {
    CompactSnackBar.success(context, '배틀이 시작되었습니다');
  }

  bool get _isOwner =>
      _battle != null && _battle!.ownerId == _service.myUid;

  Future<void> _leave() async {
    try {
      await _service.leaveBattle(widget.battleId);
      if (mounted) {
        ref.invalidate(myBattlesProvider);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) CompactSnackBar.error(context, mapBattleError(e).labelKo);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방 삭제'),
        content: const Text('참가자 명단이 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppText.subTitle.copyWith(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteBattle(widget.battleId);
      if (mounted) {
        ref.invalidate(myBattlesProvider);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) CompactSnackBar.error(context, mapBattleError(e).labelKo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    return Scaffold(
      appBar: AppBar(
        title: Text(battle?.title ?? '케미 배틀'),
        actions: [
          if (battle != null)
            PopupMenuButton<String>(
              icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18),
              onSelected: (v) => v == 'leave' ? _leave() : _delete(),
              itemBuilder: (_) => [
                if (!_isOwner)
                  const PopupMenuItem(value: 'leave', child: Text('나가기')),
                if (_isOwner)
                  const PopupMenuItem(value: 'delete', child: Text('방 삭제')),
              ],
            ),
        ],
      ),
      body: _loading || battle == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _headerCard(battle),
                  if (battle.pledge != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _pledgeBanner(battle),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _slotGrid(battle),
                  const SizedBox(height: AppSpacing.xl),
                  _qrCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _inviteRow(battle),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(Battle battle) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_roster.length} / ${battle.maxPlayers} 명',
              style: AppText.display),
          const SizedBox(height: AppSpacing.xs),
          Text('정원이 다 차면 자동으로 시작됩니다', style: AppText.caption),
          const SizedBox(height: AppSpacing.sm),
          Text(battle.ageRangeLabel, style: AppText.hint),
        ],
      ),
    );
  }

  Widget _pledgeBanner(Battle battle) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.goldSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 방의 공약', style: AppText.subTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(battle.pledge!, style: AppText.body),
          const SizedBox(height: AppSpacing.xs),
          Text('베스트 케미로 뽑힌 두 사람이 실행합니다', style: AppText.hint),
        ],
      ),
    );
  }

  Widget _slotGrid(Battle battle) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.72,
      ),
      itemCount: battle.maxPlayers,
      itemBuilder: (_, i) {
        final entry = i < _roster.length ? _roster[i] : null;
        return _SlotCell(
          entry: entry,
          thumbUrl: entry == null ? null : _thumbs[entry.userId],
          isMe: entry?.userId == _service.myUid,
        );
      },
    );
  }

  Widget _qrCard() {
    final url = SharePublisher.instance.teamInviteUrl(widget.battleId);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          QrImageView(data: url, size: 160),
          const SizedBox(height: AppSpacing.sm),
          Text('같은 자리에서는 이 코드를 스캔해 참가합니다',
              style: AppText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _inviteRow(Battle battle) {
    return Row(
      children: [
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.solidComment,
            label: '카톡 초대',
            onTap: () => SharePublisher.instance.publishTeamInvite(
              teamTitle: battle.title,
              roomId: widget.battleId,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.arrowUpFromBracket,
            label: '링크 공유',
            onTap: () => SharePublisher.instance.shareTeamInviteLink(
              teamTitle: battle.title,
              roomId: widget.battleId,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.copy,
            label: '복사',
            onTap: () async {
              await Clipboard.setData(ClipboardData(
                  text: SharePublisher.instance
                      .teamInviteUrl(widget.battleId)));
              if (mounted) CompactSnackBar.success(context, '링크를 복사했습니다');
            },
          ),
        ),
      ],
    );
  }

  Widget _inviteTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.textPrimary),
        ),
        child: Column(
          children: [
            FaIcon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: AppText.caption.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  final BattleRosterEntry? entry;
  final String? thumbUrl;
  final bool isMe;
  const _SlotCell({required this.entry, required this.thumbUrl, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final filled = entry != null;
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: filled
                  ? (entry!.isOwner ? AppColors.gold : AppColors.border)
                  : AppColors.border,
            ),
          ),
          child: ClipOval(
            child: !filled
                ? const Center(
                    child: FaIcon(FontAwesomeIcons.user,
                        size: 16, color: AppColors.border))
                : thumbUrl == null
                    ? const Center(
                        child: FaIcon(FontAwesomeIcons.solidUser,
                            size: 16, color: AppColors.textHint))
                    : Image.network(thumbUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: FaIcon(FontAwesomeIcons.solidUser,
                                size: 16, color: AppColors.textHint))),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !filled ? '대기 중' : (isMe ? '나' : entry!.nickname),
          style: AppText.hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
```

주의: 점선 원(pending) 대신 실선 border 빈 슬롯 — 기존 `_DashedCirclePainter` 는 승계하지 않는다(이름 슬롯 개념 소멸). `AppColors.goldSoft.withValues` 는 Flutter 버전에 따라 `withOpacity` — analyze 가 알려주는 쪽으로. `CompactSnackBar`/`SharePublisher` 시그니처는 실소스 기준.

- [ ] **Step 3: 게이트 + Commit**

Run: `cd flutter && flutter analyze && flutter test`
Expected: 신규 이슈 0 · 전체 green

```bash
git add flutter/pubspec.yaml flutter/pubspec.lock flutter/lib/presentation/screens/team/team_lobby_screen.dart
git commit -m "feat(app): 배틀 로비 — Realtime 슬롯 그리드·QR 현장 조인·공약 배너·초대

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 리빌 화면 (카운트다운 → Best → 공약 → 매트릭스·순위·unlock)

**Files:**
- Create: `flutter/lib/presentation/screens/team/team_reveal_screen.dart`
- Modify: `flutter/lib/presentation/screens/team/team_lobby_screen.dart` (`_onBattleStarted` hook 교체)

**Interfaces:**
- Consumes: Task 1~4 산출, shared `computeBattle`, `battle_band.dart`, `BattleService.fetchBattle/fetchRoster/submitResult/fetchLiveReport`. 쌍 상세 unlock 은 **아직 삭제되지 않은** `team_matrix_screen.dart` 의 `_showPairSheet` 가 쓰는 `runCompatUnlock`/`context.pushCompat` 호출 패턴을 그대로 승계 (그 파일을 열어 확인 후 동일 계약으로 호출).
- Produces: `class TeamRevealScreen extends ConsumerStatefulWidget { final String battleId; final bool ceremony; }` — ceremony=true 면 3-2-1 카운트다운 연출, false(완료 방 재열람)면 바로 결과 보드.

- [ ] **Step 1: team_reveal_screen.dart 작성**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:face_engine/domain/services/compat/battle.dart' as engine;

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import 'battle_band.dart';

/// 배틀 결과 — payload(스코어보드)가 없으면 snapshot 으로 계산해 1회 기록
/// (first-writer-wins)하고, 있으면 그대로 렌더한다.
class TeamRevealScreen extends ConsumerStatefulWidget {
  final String battleId;
  final bool ceremony;
  const TeamRevealScreen(
      {super.key, required this.battleId, this.ceremony = false});

  @override
  ConsumerState<TeamRevealScreen> createState() => _TeamRevealScreenState();
}

enum _Phase { loading, countdown, board, orphan }

class _TeamRevealScreenState extends ConsumerState<TeamRevealScreen> {
  final _service = BattleService.instance;
  _Phase _phase = _Phase.loading;
  int _count = 3;
  Battle? _battle;
  Map<String, dynamic>? _payload;
  List<BattleRosterEntry> _roster = const [];
  int? _mySlot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final battle = await _service.fetchBattle(widget.battleId);
    if (!mounted) return;
    if (battle == null) {
      Navigator.of(context).maybePop();
      return;
    }
    final roster = await _service.fetchRoster(widget.battleId);
    Map<String, dynamic>? payload = battle.resultPayload;
    if (payload == null) {
      final snapshot = battle.chemistrySnapshot;
      if (snapshot == null) {
        // revealing 고아(스냅샷 부재는 구조상 없지만 completed+payload null 안전망).
        setState(() {
          _battle = battle;
          _phase = _Phase.orphan;
        });
        return;
      }
      final players =
          assembleBattlePlayers(roster: roster, snapshot: snapshot);
      payload = engine.computeBattle(players).toPayload();
      // 결정론 — 선착 기록만 유효, 실패(후착·비참가자)는 무해.
      try {
        await _service.submitResult(widget.battleId, payload);
      } catch (_) {}
      ref.invalidate(myBattlesProvider);
    }
    if (!mounted) return;
    final myUid = _service.myUid;
    int? mySlot;
    for (final r in roster) {
      if (r.userId == myUid) mySlot = r.slotNo;
    }
    setState(() {
      _battle = battle;
      _payload = payload;
      _roster = roster;
      _mySlot = mySlot;
      _phase = widget.ceremony ? _Phase.countdown : _Phase.board;
    });
    if (widget.ceremony) _tickCountdown();
  }

  void _tickCountdown() {
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_count <= 1) {
        t.cancel();
        setState(() => _phase = _Phase.board);
      } else {
        setState(() => _count--);
      }
    });
  }

  // ── payload 파생 ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _players =>
      [for (final p in _payload!['players'] as List) p as Map<String, dynamic>];
  List<Map<String, dynamic>> get _pairs =>
      [for (final p in _payload!['pairs'] as List) p as Map<String, dynamic>];
  Map<String, dynamic> get _best => _payload!['best'] as Map<String, dynamic>;

  String _nameOf(int slot) {
    for (final p in _players) {
      if (p['slot'] == slot) return p['name'] as String;
    }
    return '참가자';
  }

  int? _bandOf(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    for (final p in _pairs) {
      if (p['a'] == lo && p['b'] == hi) return (p['band'] as num).toInt();
    }
    return null;
  }

  bool get _amInBest =>
      _mySlot != null && (_best['a'] == _mySlot || _best['b'] == _mySlot);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_battle?.title ?? '케미 배틀')),
      body: switch (_phase) {
        _Phase.loading =>
          const Center(child: CircularProgressIndicator()),
        _Phase.countdown => Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text('$_count',
                  key: ValueKey(_count), style: AppText.display),
            ),
          ),
        _Phase.orphan => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.huge),
              child: Text('결과가 생성되지 않은 배틀입니다',
                  style: AppText.body, textAlign: TextAlign.center),
            ),
          ),
        _Phase.board => _board(),
      },
    );
  }

  Widget _board() {
    final battle = _battle!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _bestCard(),
        if (battle.pledge != null) ...[
          const SizedBox(height: AppSpacing.md),
          _pledgeCard(battle),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text('상호 케미 맵', style: AppText.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        _matrix(),
        if (_mySlot != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('나와의 케미 순위', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          ..._myRanking(),
        ],
        const SizedBox(height: AppSpacing.xl),
        _legend(),
      ],
    );
  }

  Widget _bestCard() {
    final a = (_best['a'] as num).toInt();
    final b = (_best['b'] as num).toInt();
    final score = (_best['score'] as num).toInt();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.textPrimary),
      ),
      child: Column(
        children: [
          Text('🏆 베스트 케미', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          Text('${_nameOf(a)} × ${_nameOf(b)}', style: AppText.display),
          const SizedBox(height: AppSpacing.sm),
          Text('$score점', style: AppText.modalTitle),
        ],
      ),
    );
  }

  Widget _pledgeCard(Battle battle) {
    final a = (_best['a'] as num).toInt();
    final b = (_best['b'] as num).toInt();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.goldSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 방의 공약', style: AppText.subTitle),
          const SizedBox(height: AppSpacing.xs),
          Text('${battle.pledge!}
${_nameOf(a)}, ${_nameOf(b)} 두 분의 몫입니다',
              style: AppText.body),
          if (_amInBest && battle.chatUrl != null) ...[
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: () async {
                await Clipboard.setData(
                    ClipboardData(text: battle.chatUrl!));
                if (mounted) {
                  CompactSnackBar.success(context, '오픈채팅 링크를 복사했습니다');
                }
              },
              child: Text(battle.chatUrl!,
                  style: AppText.caption.copyWith(
                      color: AppColors.info,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }

  /// 뷰어 행 최상단 고정 매트릭스 — 셀 = 밴드 색 점.
  Widget _matrix() {
    final slots = [for (final p in _players) (p['slot'] as num).toInt()];
    if (_mySlot != null && slots.contains(_mySlot)) {
      slots
        ..remove(_mySlot)
        ..insert(0, _mySlot!);
    }
    Widget nameCell(int slot, {bool header = false}) => SizedBox(
          width: 64,
          child: Text(
            _nameOf(slot),
            style: header ? AppText.hint : AppText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 64),
            for (final s in slots) nameCell(s, header: true),
          ]),
          for (final row in slots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(children: [
                nameCell(row),
                for (final col in slots)
                  SizedBox(
                    width: 64,
                    child: row == col
                        ? Text('—', style: AppText.hint)
                        : InkWell(
                            onTap: () => _openPair(row, col),
                            child: Text(
                              _bandOf(row, col)?.bandEmoji ?? '',
                              style: AppText.body,
                            ),
                          ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  List<Widget> _myRanking() {
    final rows = <Widget>[];
    for (final p in _pairs) {
      final a = (p['a'] as num).toInt();
      final b = (p['b'] as num).toInt();
      if (a != _mySlot && b != _mySlot) continue;
      final other = a == _mySlot ? b : a;
      final band = (p['band'] as num).toInt();
      rows.add(
        InkWell(
          onTap: () => _openPair(_mySlot!, other),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Text(band.bandEmoji, style: AppText.body),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(_nameOf(other), style: AppText.subTitle)),
                Text(band.bandLabel,
                    style: AppText.caption.copyWith(color: band.bandColor)),
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }

  Widget _legend() {
    return Wrap(
      spacing: AppSpacing.md,
      children: [
        for (int band = 0; band < 4; band++)
          Text('${band.bandEmoji} ${band.bandLabel}', style: AppText.hint),
      ],
    );
  }

  /// 쌍 상세 = 기존 궁합 unlock 흐름 (1🪙). 두 참가자의 현재 my-face 를
  /// live resolve 해 기존 runCompatUnlock → pushCompat 계약으로 넘긴다.
  Future<void> _openPair(int slotA, int slotB) async {
    String? uidOf(int slot) {
      for (final r in _roster) {
        if (r.slotNo == slot) return r.userId;
      }
      return null;
    }

    final uidA = uidOf(slotA);
    final uidB = uidOf(slotB);
    if (uidA == null || uidB == null) {
      CompactSnackBar.error(context, '탈퇴한 참가자와의 상세는 볼 수 없습니다');
      return;
    }
    final myUid = _service.myUid;
    // 내 쌍은 내 리포트를 my 로 — 기존 궁합 상세의 시점 규약.
    final firstUid = uidA == myUid ? uidA : (uidB == myUid ? uidB : uidA);
    final secondUid = firstUid == uidA ? uidB : uidA;
    final my = await _service.fetchLiveReport(firstUid);
    final album = await _service.fetchLiveReport(secondUid);
    if (!mounted) return;
    if (my == null || album == null) {
      CompactSnackBar.error(context, '상세를 불러올 수 없습니다');
      return;
    }
    // ⛳ 여기부터는 team_matrix_screen.dart 의 _showPairSheet 이 쓰는
    // runCompatUnlock/pushCompat 호출과 동일 계약으로 구현한다 —
    // 그 파일(아직 존재)을 열어 시그니처를 그대로 승계할 것.
    await openBattlePairDetail(context, ref, my: my, album: album);
  }
}
```

`openBattlePairDetail(context, ref, {my, album})` 은 이 파일 하단에 top-level 로 구현 — 내용은 기존 `team_matrix_screen.dart::_showPairSheet` 의 unlock 시트 로직(무료 밴드 표시 + [1🪙 상세 보기] → `runCompatUnlock` → 성공 시 `context.pushCompat(my, album)`)을 **승계 이식**한다 (같은 위젯 구조·같은 토큰). 이식이므로 코드는 원본이 규범.

- [ ] **Step 2: 로비 hook 교체**

`team_lobby_screen.dart` 의 `_onBattleStarted` 를:

```dart
  void _onBattleStarted(Battle battle) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TeamRevealScreen(
        battleId: widget.battleId,
        ceremony: !battle.hasResult,
      ),
    ));
  }
```

(+ `import 'team_reveal_screen.dart';` 추가, CompactSnackBar import 는 다른 곳에서 계속 사용)

- [ ] **Step 3: 게이트 + Commit**

Run: `cd flutter && flutter analyze && flutter test`
Expected: 신규 이슈 0 · 전체 green

```bash
git add flutter/lib/presentation/screens/team/team_reveal_screen.dart flutter/lib/presentation/screens/team/team_lobby_screen.dart
git commit -m "feat(app): 배틀 리빌 — 카운트다운·Best·공약 회수·매트릭스·순위·쌍 unlock

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 조인 화면 (/g/:id)

**Files:**
- Create: `flutter/lib/presentation/screens/team/battle_join_screen.dart`

**Interfaces:**
- Consumes: Task 1~5 산출, `historyProvider`(my-face 체크 `history.any((r)=>r.isMyFace)`), `startMyFaceCapture(context, ref)`, `login_bottom_sheet`(기존 로그인 게이트 — `team_join_screen.dart` 의 사용 패턴 승계), `authProvider`.
- Produces: `class BattleJoinScreen extends ConsumerStatefulWidget { final String battleId; }` — 딥링크 `/g/:id`·공개 목록 탭 공용 진입. 성공 시 `TeamLobbyScreen` 으로 pushReplacement.

- [ ] **Step 1: battle_join_screen.dart 작성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/my_face_capture_flow.dart';
import '../../widgets/primary_button.dart';
import 'team_lobby_screen.dart';
import 'team_reveal_screen.dart';

/// 배틀 참가 — 로그인 → 내 관상 → (비밀방) PIN → (공약) 동의 → join_battle.
class BattleJoinScreen extends ConsumerStatefulWidget {
  final String battleId;
  const BattleJoinScreen({super.key, required this.battleId});

  @override
  ConsumerState<BattleJoinScreen> createState() => _BattleJoinScreenState();
}

class _BattleJoinScreenState extends ConsumerState<BattleJoinScreen> {
  final _service = BattleService.instance;
  final _pinCtrl = TextEditingController();
  Battle? _battle;
  int _playerCount = 0;
  bool _agreed = false;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final battle = await _service.fetchBattle(widget.battleId);
    final roster =
        battle == null ? null : await _service.fetchRoster(widget.battleId);
    if (!mounted) return;
    // 이미 참가한 방이면 바로 로비/결과로.
    final myUid = _service.myUid;
    if (battle != null &&
        roster != null &&
        myUid != null &&
        roster.any((r) => r.userId == myUid)) {
      _goInside(battle);
      return;
    }
    setState(() {
      _battle = battle;
      _playerCount = roster?.length ?? 0;
      _loading = false;
    });
  }

  void _goInside(Battle battle) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => battle.isRecruiting
          ? TeamLobbyScreen(battleId: widget.battleId)
          : TeamRevealScreen(battleId: widget.battleId),
    ));
  }

  Future<void> _join() async {
    final battle = _battle!;
    // ① 로그인 게이트 — 기존 team_join_screen 의 login_bottom_sheet 패턴 승계.
    if (!_service.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (ok != true || !mounted) return;
    }
    // ② my-face 게이트.
    final hasMyFace =
        ref.read(historyProvider).any((r) => r.isMyFace);
    if (!hasMyFace) {
      await startMyFaceCapture(context, ref);
      if (!mounted ||
          !ref.read(historyProvider).any((r) => r.isMyFace)) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await _service.joinBattle(
        widget.battleId,
        password: battle.isPublic ? null : _pinCtrl.text.trim(),
      );
      ref.invalidate(myBattlesProvider);
      if (mounted) _goInside(battle);
    } catch (e) {
      final err = mapBattleError(e);
      if (err == BattleJoinError.alreadyJoined) {
        if (mounted) _goInside(battle);
        return;
      }
      if (mounted) {
        CompactSnackBar.error(context, err.labelKo);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    return Scaffold(
      appBar: AppBar(title: const Text('케미 배틀')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : battle == null
              ? Center(
                  child: Text('존재하지 않는 방입니다', style: AppText.body))
              : !battle.isRecruiting
                  ? _closedBody(battle)
                  : _joinBody(battle),
    );
  }

  Widget _closedBody(Battle battle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.huge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              battle.status == BattleStatus.expired
                  ? '인원이 모이지 않아 종료된 방입니다'
                  : '이미 시작된 방입니다',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            if (battle.hasResult) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: '결과 보기',
                onPressed: () => _goInside(battle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinBody(Battle battle) {
    final needsConsent = battle.pledge != null;
    final canJoin = (!needsConsent || _agreed) &&
        (battle.isPublic || _pinCtrl.text.trim().length == 4);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(battle.title, style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('${_playerCount} / ${battle.maxPlayers} 명', style: AppText.body),
        const SizedBox(height: AppSpacing.xs),
        Text(battle.ageRangeLabel, style: AppText.caption),
        if (battle.pledge != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.goldSoft.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.gold),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('이 방의 공약', style: AppText.subTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(battle.pledge!, style: AppText.body),
                const SizedBox(height: AppSpacing.xs),
                Text('베스트 케미로 뽑힌 두 사람이 실행합니다', style: AppText.hint),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text('공약에 동의하고 참가합니다', style: AppText.caption),
          ),
        ],
        if (!battle.isPublic) ...[
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '비밀번호 4자리'),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          label: '참가하기',
          busy: _busy,
          onPressed: canJoin && !_busy ? _join : null,
        ),
      ],
    );
  }
}
```

주의: `showLoginBottomSheet` 는 실존 이름 아님 — `team_join_screen.dart`(아직 존재)를 열어 로그인 게이트의 **실제 호출 계약**(위젯/함수명·반환)을 그대로 승계하라. `startMyFaceCapture` 시그니처는 `my_face_capture_flow.dart:17`.

- [ ] **Step 2: 게이트 + Commit**

Run: `cd flutter && flutter analyze && flutter test`
Expected: 신규 이슈 0 · 전체 green

```bash
git add flutter/lib/presentation/screens/team/battle_join_screen.dart
git commit -m "feat(app): 배틀 조인 — 로그인·내 관상·PIN·공약 동의 게이트

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Cutover — 케미 탭 재작성 + 배선 교체 + 구세계 일괄 삭제

**Files:**
- Rewrite: `flutter/lib/presentation/screens/chemistry/chemistry_screen.dart`
- Modify: `flutter/lib/config/router.dart` (/g/:id → BattleJoinScreen)
- Modify: `flutter/lib/presentation/providers/history_provider.dart` (rehydrateFromServer 호출 제거)
- Modify: `flutter/lib/core/hive_setup.dart` (teams box 제거)
- Modify: `flutter/lib/presentation/widgets/onboarding_intro.dart` (케미 페이지 카피)
- Delete: `lib/presentation/screens/team/team_room_screen.dart` · `team_matrix_screen.dart` · `team_matrix_snapshot_screen.dart` · `team_create_page.dart` · `team_join_screen.dart` · `team_band.dart` · `lib/domain/services/team_matrix.dart` · `lib/presentation/providers/team_provider.dart` · `lib/data/services/team_sync_service.dart` · `lib/domain/models/team_room.dart` · `test/team_matrix_test.dart` · `test/team_text_input_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1~6 전부.
- Produces: 배틀 세계로 완전 전환된 앱. `ChemistryScreen` 클래스명·파일 경로 불변 (app.dart 무수정).

- [ ] **Step 1: chemistry_screen.dart 전면 재작성**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/face_scan_pill.dart';
import '../team/battle_create_page.dart';
import '../team/battle_join_screen.dart';
import '../team/team_lobby_screen.dart';
import '../team/team_reveal_screen.dart';

/// 케미 탭 = Chemistry Battle 로비 브라우저.
/// 내부 2탭: 공개 배틀(목록에서 발견·참가) / 내 배틀(진행·완료).
class ChemistryScreen extends ConsumerStatefulWidget {
  const ChemistryScreen({super.key});

  @override
  ConsumerState<ChemistryScreen> createState() => _ChemistryScreenState();
}

class _ChemistryScreenState extends ConsumerState<ChemistryScreen> {
  Future<void> _create() async {
    final battle = await showBattleCreatePage(context);
    if (battle == null || !mounted) return;
    ref.invalidate(myBattlesProvider);
    ref.invalidate(publicBattlesProvider);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeamLobbyScreen(battleId: battle.id),
    ));
  }

  void _openMine(Battle battle) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => battle.isRecruiting
          ? TeamLobbyScreen(battleId: battle.id)
          : TeamRevealScreen(battleId: battle.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasMyFace =
        ref.watch(historyProvider).any((r) => r.isMyFace);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('케미'),
          actions: [
            if (!hasMyFace)
              const FaceScanPill()
            else
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: _CreatePill(onTap: _create),
              ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '공개 배틀'), Tab(text: '내 배틀')],
          ),
        ),
        body: !hasMyFace
            ? const EmotionEmptyState(
                asset: 'assets/images/emotions/shrug.png',
                message: '내 관상을 등록하면 케미 배틀에 참가할 수 있습니다',
              )
            : const TabBarView(
                children: [_PublicTab(), _MineTab()],
              ),
      ),
    );
  }
}

/// AppBar 우측 pill — 기존 outlined stadium 레시피 (케미 그룹 시작 자리 승계).
class _CreatePill extends StatelessWidget {
  final VoidCallback onTap;
  const _CreatePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.textPrimary),
          ),
          child: Text(
            '배틀 만들기',
            style: AppText.caption.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _PublicTab extends ConsumerWidget {
  const _PublicTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battles = ref.watch(publicBattlesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(publicBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Text('목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption, textAlign: TextAlign.center),
          ),
        ]),
        data: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotions/frown.png',
                  message: '모집 중인 공개 배틀이 없습니다',
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                itemBuilder: (ctx, i) => _PublicCard(battle: list[i]),
              ),
      ),
    );
  }
}

class _PublicCard extends StatelessWidget {
  final PublicBattle battle;
  const _PublicCard({required this.battle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BattleJoinScreen(battleId: battle.id),
      )),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(battle.title, style: AppText.subTitle),
            const SizedBox(height: AppSpacing.xs),
            Text('${battle.playerCount} / ${battle.maxPlayers} 명',
                style: AppText.caption),
            Text(battle.ageRangeLabel,
                style: AppText.caption.copyWith(color: AppColors.textHint)),
            if (battle.pledge != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('공약 ${battle.pledge!}', style: AppText.hint),
            ],
          ],
        ),
      ),
    );
  }
}

class _MineTab extends ConsumerWidget {
  const _MineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battles = ref.watch(myBattlesProvider);
    final state = context.findAncestorStateOfType<_ChemistryScreenState>()!;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Text('목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption, textAlign: TextAlign.center),
          ),
        ]),
        data: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotions/laugh.png',
                  message: '참가 중인 배틀이 없습니다',
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                itemBuilder: (ctx, i) =>
                    _MineCard(battle: list[i], onOpen: state._openMine),
              ),
      ),
    );
  }
}

class _MineCard extends ConsumerWidget {
  final Battle battle;
  final void Function(Battle) onOpen;
  const _MineCard({required this.battle, required this.onOpen});

  String get _statusLabel => switch (battle.status) {
        BattleStatus.recruiting => '모집 중',
        BattleStatus.revealing => '결과 공개 중',
        BattleStatus.completed => '완료',
        BattleStatus.expired => '종료',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = battle.ownerId == BattleService.instance.myUid;
    return InkWell(
      onTap: battle.status == BattleStatus.expired
          ? null
          : () => onOpen(battle),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(battle.title, style: AppText.subTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_statusLabel, style: AppText.caption),
                ],
              ),
            ),
            if (isOwner && battle.isRecruiting)
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.trashCan,
                    size: 16, color: AppColors.textHint),
                onPressed: () async {
                  await BattleService.instance.deleteBattle(battle.id);
                  ref.invalidate(myBattlesProvider);
                  ref.invalidate(publicBattlesProvider);
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

주의: `EmotionEmptyState` 파라미터(asset 경로·기존 배치 규칙 — 케미 탭은 laugh/shrug/frown)는 실소스·기존 chemistry_screen(재작성 전) 사용부를 먼저 읽고 동일 계약으로. `_MineTab` 의 `findAncestorStateOfType` 가 어색하면 콜백을 생성자로 내려도 됨 — 구조 판단은 구현자 재량 (토큰 규칙만 불변).

- [ ] **Step 2: 배선 교체 4건**

1. `config/router.dart`: `import` 의 `team_join_screen.dart` → `battle_join_screen.dart`, `GoRoute('/g/:id')` builder 를 `BattleJoinScreen(battleId: state.pathParameters['id']!)` 로.
2. `history_provider.dart`: `ref.read(teamsProvider.notifier).rehydrateFromServer()` 호출(±import) 제거 — 배틀은 서버 우선이라 로그인 rehydrate 불필요 (myBattlesProvider 가 항상 서버를 읽음).
3. `core/hive_setup.dart`: `HiveBoxes.teams` 상수와 teams box open 라인 제거.
4. `onboarding_intro.dart` 케미 페이지(L42-44 근방): chips `['케미 배틀 무료']`, body `'배틀 방을 만들면 참가자들이 각자 들어옵니다\n인원이 모이면 케미 결과가 공개됩니다.'` (title '케미' 유지).

- [ ] **Step 3: 구세계 일괄 삭제**

```bash
cd flutter
git rm lib/presentation/screens/team/team_room_screen.dart \
       lib/presentation/screens/team/team_matrix_screen.dart \
       lib/presentation/screens/team/team_matrix_snapshot_screen.dart \
       lib/presentation/screens/team/team_create_page.dart \
       lib/presentation/screens/team/team_join_screen.dart \
       lib/presentation/screens/team/team_band.dart \
       lib/domain/services/team_matrix.dart \
       lib/presentation/providers/team_provider.dart \
       lib/data/services/team_sync_service.dart \
       lib/domain/models/team_room.dart \
       test/team_matrix_test.dart \
       test/team_text_input_dialog_test.dart
```

- [ ] **Step 4: dangling 확인 + 게이트**

```bash
cd flutter
grep -rn "team_provider\|team_sync_service\|team_room\.dart\|team_matrix\|team_band\|TeamRoom\|TeamMember\b\|computeTeamMatrix\|teamsProvider" lib/ test/ || echo CLEAN
flutter analyze
flutter test
```

Expected: `CLEAN` (주석 잔재는 정리) · analyze 기준선 7건 외 0 · 전체 test green (battle 계열 + 기존)

- [ ] **Step 5: Commit**

```bash
git add -A flutter/lib flutter/test
git commit -m "feat(app)!: 케미 탭 Chemistry Battle 전환 — 공개/내 배틀 2탭 + 구세계 삭제

이름 슬롯·walk-in·lazy sync·Hive teams box·matrix 스냅샷 화면 폐기.
/g/:id 는 BattleJoinScreen 으로.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 완료 기준 (Plan 2 전체)

1. `flutter test` 전부 green (battle_model_test 포함) · `flutter analyze` 기준선 7건 외 0.
2. 구세계 식별자(teamsProvider·TeamRoom·computeTeamMatrix 등) grep CLEAN.
3. 실기기 시나리오 (사람 확인): 방 생성(공약 포함) → 두 번째 계정 QR/링크 조인 → 로비 실시간 반영 → 정원 충족 → 양쪽 카운트다운 → 같은 Best → 매트릭스·순위 → 쌍 1🪙 unlock → 케미 탭 내 배틀 목록 상태 정확.
4. 웹(`/g/:id`) 은 Plan 3 전까지 구 JoinWizard 그대로 — 이름 스텝이 서버와 안 맞아 웹 조인은 Plan 3 완료까지 일시 불능 (앱 조인·QR 은 정상). 알려진 공백으로 기록.

이후: **Plan 3 (웹)** — JoinWizard 를 join_battle RPC 로 교체, 로비 라이브(supabase-js Realtime), 쇼케이스 payload 렌더(`runBattle` fallback), 문서 일괄 갱신 (ARCHITECTURE·PRD·react HOW-IT-WORKS·CLAUDE 용어).
