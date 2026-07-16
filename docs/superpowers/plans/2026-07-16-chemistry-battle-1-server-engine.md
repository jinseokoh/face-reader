# Chemistry Battle — Plan 1/3: 서버 기반 + 엔진 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chemistry Battle 의 서버 데이터 모델(teams 재구성·RPC 상태 머신·RLS·공개 목록 view·Realtime publication·cron)과 결정론 배틀 집계 엔진(`computeBattle` + `runBattle` JS export)을 완성한다.

**Architecture:** Supabase Postgres 가 방의 SSOT — 조인·시작·결과 기록은 전부 SECURITY DEFINER RPC 단일 트랜잭션. 배틀 계산은 클라이언트 엔진(shared Dart → JS)이 `chemistry_snapshot`(서버가 시작 시 동결한 입력)으로 수행하고 `result_payload`(출력)를 한 번 기록한다. 이 계획은 Flutter/웹 UI 를 건드리지 않는다 (Plan 2 = Flutter, Plan 3 = 웹).

**Tech Stack:** Supabase Postgres (RLS·plpgsql RPC·Realtime publication) · 순수 Dart `shared/`(face_engine) · `dart compile js -O1` · Cloudflare Workers cron.

**Spec:** `docs/superpowers/specs/2026-07-16-chemistry-battle-design.md`

## Global Constraints

- DDL 은 `react/db/migrations/0001_baseline.sql` **단일 파일 직접 수정** — 새 마이그레이션 파일 생성 금지.
- payload·스키마에 version 필드/bump 금지 (출시 전 호환 후크 금지).
- 엔진 변경은 `shared/lib/` 에서만. JS 빌드는 `cd react && pnpm build:shared` (**`-O2` 금지**, `-O1` 고정).
- `react/app/lib/shared/face_engine.js` 는 build artifact — **commit 금지** (.gitignore 됨).
- Flutter 게이트: `cd flutter && flutter test` 전부 green (기존 151 + 신규), `flutter analyze` 기준선 7건 외 신규 0.
- react 게이트: `cd react && pnpm typecheck` 통과.
- 문서(ARCHITECTURE/PRD/HOW-IT-WORKS) 갱신은 Plan 3 완료 후 일괄 — 이 계획에서 건드리지 않는다.
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## 파일 구조 (이 계획이 만들고/바꾸는 것)

| 파일 | 책임 |
|---|---|
| `shared/lib/domain/services/compat/battle.dart` (신규) | 배틀 집계 SSOT — 쌍 계산·정렬(=순위)·tie-break·best·payload 직렬화 |
| `flutter/test/battle_test.dart` (신규) | computeBattle 결정론·정렬·tie-break·payload 계약 테스트 |
| `shared/lib/face_engine.dart` (수정) | `runBattle` JS export 추가 |
| `react/db/migrations/0001_baseline.sql` (수정) | §11-2/11-3 재작성 + RPC 3종 + view + realtime + column grants |
| `react/db/tests/battle_rpc_smoke.sql` (신규) | Supabase SQL 콘솔용 상태 머신 smoke 시나리오 (begin…rollback) |
| `react/workers/cron.ts` (수정) | closeStaleTeams → expireStaleTeams + completeOrphanReveals |
| `react/workers/app.ts` (수정) | scheduled 핸들러 연결 교체 |

기존 `flutter/lib/domain/services/team_matrix.dart` 는 이 계획에서 **삭제하지 않는다** — 기존 화면이 아직 참조하므로 Plan 2(Flutter 개편)에서 화면과 함께 제거한다.

---

### Task 1: `computeBattle` — shared 배틀 집계 엔진 (TDD)

**Files:**
- Create: `shared/lib/domain/services/compat/battle.dart`
- Test: `flutter/test/battle_test.dart`

**Interfaces:**
- Consumes: `analyzeCompatibility({my, album})` (`compat_pipeline.dart`, → `.total double`·`.label CompatLabel`), `reportToCompatInput(FaceReadingReport)` (`compat_adapter.dart`), `CompatLabel` enum (`compat_label.dart`, 선언 순서 = cheonjakjihap·geumseulsanghwa·mahapgaseong·hyeonggeuknanjo → `index` 0~3 이 band 코드).
- Produces (Plan 2·3 과 Task 2 가 의존):
  - `class BattlePlayer { final int slot; final String name; final FaceReadingReport report; }`
  - `class BattlePair { final int a; final int b; final double total; final CompatLabel label; }` (a < b 불변)
  - `int battlePairCompare(BattlePair x, BattlePair y)` — raw total desc → a asc → b asc
  - `BattleResult computeBattle(List<BattlePlayer> players)` — `.pairs`(정렬됨) · `.best` · `.toPayload()`
  - payload 계약: `{players:[{slot,name}], pairs:[{a,b,band}], best:{a,b,score}}` — pairs 에 점수 없음, band = `CompatLabel.index`, best.score = `total.round()`

- [ ] **Step 1: 실패하는 테스트 작성**

`flutter/test/battle_test.dart` 생성 (합성 리포트 헬퍼는 `team_matrix_test.dart` 의 검증된 패턴을 복제):

```dart
// Chemistry Battle 집계 엔진 검증 — 스펙 §5/§6.3:
// 쌍 수 · a<b 정규화 · 정렬=순위(raw total desc) · tie-break 결정론 ·
// best = pairs[0] · payload 계약 (점수는 best.score 만, band 0~3).
//
// 실행: flutter test test/battle_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/compat/battle.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/services/mc_fixtures.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

FaceReadingReport _fakeReport(
  Random rng, {
  required Gender gender,
  required AgeGroup age,
}) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final lateralZ = <String, double>{};
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    lateralZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree({...frontalZ, ...lateralZ});
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
        rawValue: 0.0,
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
    gender: gender,
    ageGroup: age,
    timestamp: DateTime(2026, 7, 16),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, gender, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
}

List<BattlePlayer> _players(int n, {int seed = 42}) {
  final rng = Random(seed);
  return [
    for (int i = 0; i < n; i++)
      BattlePlayer(
        slot: i + 1,
        name: '플레이어$i',
        report: _fakeReport(
          rng,
          gender: i.isEven ? Gender.male : Gender.female,
          age: AgeGroup.values[i % 5],
        ),
      ),
  ];
}

void main() {
  test('쌍 수 = N(N-1)/2, 모든 쌍은 a < b 정규화', () {
    final result = computeBattle(_players(4));
    expect(result.pairs.length, 6);
    for (final p in result.pairs) {
      expect(p.a < p.b, isTrue);
    }
  });

  test('정렬 = 순위 — pairs 는 raw total 내림차순, best = pairs[0]', () {
    final result = computeBattle(_players(6));
    for (int i = 1; i < result.pairs.length; i++) {
      expect(
        result.pairs[i - 1].total >= result.pairs[i].total,
        isTrue,
      );
    }
    expect(identical(result.best, result.pairs.first), isTrue);
  });

  test('결정론 — 같은 입력은 항상 같은 payload', () {
    final players = _players(6);
    final a = computeBattle(players).toPayload();
    final b = computeBattle(players).toPayload();
    expect(a, equals(b));
  });

  test('tie-break 비교자 — total 동점이면 (a, b) 사전순, 공동 수상 없음', () {
    BattlePair pair(int a, int b, double total) =>
        BattlePair(a: a, b: b, total: total, label: CompatLabel.mahapgaseong);
    // total 다르면 내림차순.
    expect(battlePairCompare(pair(1, 2, 90), pair(3, 4, 80)) < 0, isTrue);
    expect(battlePairCompare(pair(1, 2, 80), pair(3, 4, 90)) > 0, isTrue);
    // 완전 동점 → a 오름차순 → b 오름차순.
    expect(battlePairCompare(pair(1, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    expect(battlePairCompare(pair(2, 3, 85), pair(2, 4, 85)) < 0, isTrue);
    // 동일 쌍은 0.
    expect(battlePairCompare(pair(2, 4, 85), pair(2, 4, 85)), 0);
  });

  test('payload 계약 — players/pairs/best 만, pairs 에 점수 없음, band 0~3', () {
    final result = computeBattle(_players(4));
    final payload = result.toPayload();
    expect(payload.keys.toSet(), {'players', 'pairs', 'best'});

    final players = payload['players'] as List;
    expect(players.length, 4);
    for (final p in players) {
      expect((p as Map).keys.toSet(), {'slot', 'name'});
    }

    final pairs = payload['pairs'] as List;
    expect(pairs.length, 6);
    for (final p in pairs) {
      expect((p as Map).keys.toSet(), {'a', 'b', 'band'});
      expect(p['band'], inInclusiveRange(0, 3));
    }

    final best = payload['best'] as Map;
    expect(best.keys.toSet(), {'a', 'b', 'score'});
    expect(best['score'], result.best.total.round());
    expect(best['a'], result.pairs.first.a);
    expect(best['b'], result.pairs.first.b);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd flutter && flutter test test/battle_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package ... battle.dart` (파일 부재 컴파일 에러)

- [ ] **Step 3: 최소 구현**

`shared/lib/domain/services/compat/battle.dart` 생성:

```dart
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';

/// Chemistry Battle 집계 — 스펙 2026-07-16-chemistry-battle-design §5/§6.
///
/// 궁합 엔진을 모든 쌍 N(N-1)/2 회 호출해 정렬한다. 엔진이 결정론·대칭이라
/// 같은 입력(chemistry_snapshot)은 어느 클라이언트에서든 같은 payload 를 낸다.
/// 정렬이 곧 순위(내림차순) — payload 는 점수를 싣지 않는다 (best.score 만,
/// "숫자·풀이 = 유료" 정책).
class BattlePlayer {
  final int slot;
  final String name;
  final FaceReadingReport report;

  const BattlePlayer({
    required this.slot,
    required this.name,
    required this.report,
  });
}

class BattlePair {
  /// slot_no 양끝 — a < b 정규화 (무방향 쌍의 유일 표현).
  final int a;
  final int b;
  final double total;
  final CompatLabel label;

  const BattlePair({
    required this.a,
    required this.b,
    required this.total,
    required this.label,
  });
}

/// raw total 내림차순 → a 오름차순 → b 오름차순. 완전 동점도 단독 수상
/// (공동 수상 없음 — 연출·공약 회수가 항상 한 쌍을 가리켜야 한다).
int battlePairCompare(BattlePair x, BattlePair y) {
  final byTotal = y.total.compareTo(x.total);
  if (byTotal != 0) return byTotal;
  final byA = x.a.compareTo(y.a);
  if (byA != 0) return byA;
  return x.b.compareTo(y.b);
}

class BattleResult {
  final List<BattlePlayer> players;

  /// battlePairCompare 정렬 완료 — 배열 인덱스가 곧 케미 순위.
  final List<BattlePair> pairs;

  const BattleResult({required this.players, required this.pairs});

  BattlePair get best => pairs.first;

  /// teams.result_payload 계약 (§6.3): 점수는 best.score 하나뿐,
  /// band = CompatLabel.index (0=천작지합 … 3=형극난조).
  Map<String, dynamic> toPayload() => {
        'players': [
          for (final p in players) {'slot': p.slot, 'name': p.name},
        ],
        'pairs': [
          for (final p in pairs) {'a': p.a, 'b': p.b, 'band': p.label.index},
        ],
        'best': {
          'a': best.a,
          'b': best.b,
          'score': best.total.round(),
        },
      };
}

BattleResult computeBattle(List<BattlePlayer> players) {
  assert(players.length >= 2, 'battle 은 2명 이상 필요');
  final sorted = [...players]..sort((x, y) => x.slot.compareTo(y.slot));
  final pairs = <BattlePair>[];
  for (int i = 0; i < sorted.length; i++) {
    for (int j = i + 1; j < sorted.length; j++) {
      final report = analyzeCompatibility(
        my: reportToCompatInput(sorted[i].report),
        album: reportToCompatInput(sorted[j].report),
      );
      pairs.add(BattlePair(
        a: sorted[i].slot,
        b: sorted[j].slot,
        total: report.total,
        label: report.label,
      ));
    }
  }
  pairs.sort(battlePairCompare);
  return BattleResult(players: sorted, pairs: pairs);
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd flutter && flutter test test/battle_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: 전체 게이트**

Run: `cd flutter && flutter test && flutter analyze`
Expected: 전부 green (기존 151 + 6) · analyze 기준선 7건 외 신규 0

- [ ] **Step 6: Commit**

```bash
git add shared/lib/domain/services/compat/battle.dart flutter/test/battle_test.dart
git commit -m "feat(engine): computeBattle — 배틀 집계 SSOT (정렬=순위·tie-break·payload 계약)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `runBattle` JS export

**Files:**
- Modify: `shared/lib/face_engine.dart`

**Interfaces:**
- Consumes: Task 1 의 `BattlePlayer`/`computeBattle`, `FaceReadingReport.fromJsonString(String)`.
- Produces: `globalThis.runBattle(battleJson)` — 입력 `{"players":[{"slot":1,"name":"지은","body":{…metrics body…}}, …]}` JSON 문자열, 출력 = `result_payload` JSON 문자열 (§6.3 계약). Plan 3(웹) 이 이 시그니처를 사용.

- [ ] **Step 1: export 추가**

`shared/lib/face_engine.dart` 수정 — import 블록에 추가:

```dart
import 'package:face_engine/domain/services/compat/battle.dart';
```

`@JS` 선언부(`_setRunMetrics` 아래)에 추가:

```dart
@JS('runBattle')
external set _setRunBattle(JSFunction fn);
```

`main()` 끝(`_setRunMetrics` 할당 아래)에 추가:

```dart
  // Chemistry Battle — chemistry_snapshot 기반 배틀 집계 (§6.3 payload 계약).
  // 입력: {"players":[{"slot":1,"name":"지은","body":{…metrics body…}}, …]}
  // 출력: {"players":[…],"pairs":[…],"best":{…}} — pairs 정렬 = 순위.
  _setRunBattle = ((String battleJson) {
    final raw = jsonDecode(battleJson) as Map<String, dynamic>;
    final players = [
      for (final p in raw['players'] as List)
        BattlePlayer(
          slot: (p['slot'] as num).toInt(),
          name: p['name'] as String,
          report: FaceReadingReport.fromJsonString(jsonEncode(p['body'])),
        ),
    ];
    return jsonEncode(computeBattle(players).toPayload());
  }).toJS;
```

파일 상단 doc comment 의 Output 목록에도 한 줄 추가:

```dart
///   globalThis.runBattle(battleJson)         → battle result payload
```

- [ ] **Step 2: JS 빌드 검증**

Run: `cd react && pnpm build:shared`
Expected: exit 0, `react/app/lib/shared/face_engine.js` 재생성 (commit 금지 artifact)

- [ ] **Step 3: Flutter 게이트 재확인** (shared 수정이 앱 컴파일을 깨지 않는지)

Run: `cd flutter && flutter test test/battle_test.dart && flutter analyze`
Expected: PASS · 신규 이슈 0

- [ ] **Step 4: Commit**

```bash
git add shared/lib/face_engine.dart
git commit -m "feat(engine): runBattle JS export — 웹 배틀 계산 단일 SSOT

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: baseline.sql — teams/team_members 재구성

**Files:**
- Modify: `react/db/migrations/0001_baseline.sql` (§11-2 lines ~694-743, §11-3 lines ~745-828, §11-1 뒤 column-grant 블록 추가)

**Interfaces:**
- Produces (Task 4·Plan 2·3 이 의존하는 스키마):
  - `teams`: `id·owner_id·title·visibility('public'|'private')·password(클라이언트 SELECT 불가)·max_players(4~12)·age_min/age_max(decade, 둘 다 null 또는 둘 다 값)·pledge(≤40자)·chat_url·status('recruiting'|'revealing'|'completed'|'expired')·started_at·closed_at·chemistry_snapshot jsonb·result_payload jsonb·created_at·updated_at`
  - `team_members`: `id·team_id(cascade)·user_id not null(cascade)·slot_no·is_owner·joined_at`, unique `(team_id,user_id)`·`(team_id,slot_no)`
  - `name`·`metrics_id` 컬럼과 이름 슬롯 claim 정책은 존재하지 않는다.

- [ ] **Step 1: §11-2 교체**

`0001_baseline.sql` 의 `-- 11-2. public.teams` 구획 헤더부터 `teams_touch` 트리거 정의 끝(`for each row execute procedure public.touch_teams_updated_at();`)까지를 다음으로 교체:

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 11-2. public.teams — Chemistry Battle 방 (게임 로비, 서버 우선)
-- ─────────────────────────────────────────────────────────────────────────────
-- 방은 생성 즉시 서버에 존재한다 (로컬 우선/lazy sync 폐기). 참가자는 이름
-- 선등록 없이 join_battle RPC 로 셀프 조인. 시작 조건은 정원 충족 하나뿐 —
-- 모이면 시작, 48h 안에 안 모이면 expired (cron).
--
-- chemistry_snapshot = 시작 트랜잭션이 동결한 {user_id: metrics body} — 엔진
-- 입력. 시작 후 재촬영·metrics 변경이 결과에 영향을 못 주게 하는 치팅 방어.
-- result_payload = 클라이언트가 snapshot 으로 계산해 1회 기록하는 스코어보드
-- (players/pairs/best — 점수는 best.score 만).
-- password 는 column grant 로 클라이언트 SELECT 차단 (§11-4) — 비교는
-- join_battle 내부에서만. 상태 전이는 RPC 전용 (직접 UPDATE 는 title 만).
create table if not exists public.teams (
  id                 uuid        primary key default gen_random_uuid(),
  owner_id           uuid        references auth.users(id) on delete set null,
  title              text        not null,
  visibility         text        not null default 'private'
                                 check (visibility in ('public', 'private')),
  password           text,
  max_players        int         not null default 8
                                 check (max_players between 4 and 12),
  age_min            int         check (age_min is null or age_min between 10 and 90),
  age_max            int         check (age_max is null or age_max between 10 and 90),
  pledge             text        check (pledge is null or char_length(pledge) <= 40),
  chat_url           text,
  status             text        not null default 'recruiting'
                                 check (status in ('recruiting', 'revealing', 'completed', 'expired')),
  started_at         timestamptz,
  closed_at          timestamptz,
  chemistry_snapshot jsonb,
  result_payload     jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  -- 연령 범위는 둘 다 null(전연령) 또는 둘 다 값 + 순서.
  check ((age_min is null) = (age_max is null)),
  check (age_min is null or age_min <= age_max),
  -- 비밀방은 비밀번호 필수, 공개방은 비밀번호 없음.
  check (visibility <> 'private' or password is not null),
  check (visibility <> 'public' or password is null),
  -- 공약 공개방 성인 게이트: 공개방 + 공약이면 age_min >= 20 (10대 차단).
  check (not (visibility = 'public' and pledge is not null
              and (age_min is null or age_min < 20)))
);

create index if not exists idx_teams_owner on public.teams (owner_id, updated_at desc);
-- 공개 목록 조회 (public_battles view).
create index if not exists idx_teams_public_recruiting
  on public.teams (created_at desc) where visibility = 'public' and status = 'recruiting';

alter table public.teams enable row level security;

drop policy if exists "teams_public_read" on public.teams;
drop policy if exists "teams_owner_insert" on public.teams;
drop policy if exists "teams_owner_update" on public.teams;
drop policy if exists "teams_owner_delete" on public.teams;

-- 읽기: UUID 아는 사람 (link-share). 컬럼 접근은 §11-4 column grant 가 좁힌다.
create policy "teams_public_read"
  on public.teams for select using (true);
-- 생성: owner 본인. status 등 계산 컬럼은 column grant 로 insert 불가 (§11-4).
create policy "teams_owner_insert"
  on public.teams for insert with check (owner_id = auth.uid());
-- 수정: owner 본인 — 단 column grant 가 title 로 제한 (상태 전이는 RPC 전용).
create policy "teams_owner_update"
  on public.teams for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- 삭제: owner 본인 (모집 중 방 접기 — 멤버는 FK cascade).
create policy "teams_owner_delete"
  on public.teams for delete using (owner_id = auth.uid());

-- 어떤 UPDATE 든 updated_at 자동 touch.
create or replace function public.touch_teams_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;

drop trigger if exists teams_touch on public.teams;
create trigger teams_touch
  before update on public.teams
  for each row execute procedure public.touch_teams_updated_at();
```

- [ ] **Step 2: §11-3 교체**

`-- 11-3. public.team_members` 구획 헤더부터 `team_members_delete` 정책 끝(`);` — §11-1 GRANT 구획 헤더 직전)까지를 다음으로 교체:

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 11-3. public.team_members — 배틀 참가자 (전원 로그인 셀프 조인)
-- ─────────────────────────────────────────────────────────────────────────────
-- 참가자 = 로그인 사용자. 이름·얼굴 컬럼 없음 — 표시 이름은 users.nickname,
-- 얼굴은 조회 시 user_id → 현재 my-face live resolve (시작 후엔 teams.
-- chemistry_snapshot 이 입력). 계정 삭제 = FK cascade 로 참가 행 소멸 →
-- 슬롯 자동 반환. 쓰기는 전부 RPC (join_battle / leave_battle) — 직접
-- insert/update/delete 정책 없음 (RLS deny by default).
create table if not exists public.team_members (
  id        uuid        primary key default gen_random_uuid(),
  team_id   uuid        not null references public.teams(id) on delete cascade,
  user_id   uuid        not null references auth.users(id) on delete cascade,
  slot_no   int         not null,
  is_owner  boolean     not null default false,
  joined_at timestamptz not null default now(),
  unique (team_id, user_id),
  unique (team_id, slot_no)
);

create index if not exists idx_team_members_team on public.team_members (team_id);
-- 로그인 rehydrate: 내가 참가한 방 조회.
create index if not exists idx_team_members_user on public.team_members (user_id);

alter table public.team_members enable row level security;

drop policy if exists "team_members_public_read" on public.team_members;
drop policy if exists "team_members_insert"      on public.team_members;
drop policy if exists "team_members_update"      on public.team_members;
drop policy if exists "team_members_claim_slot"  on public.team_members;
drop policy if exists "team_members_delete"      on public.team_members;

-- 읽기: 방과 동일 link-share. 쓰기 정책은 의도적으로 없음 — RPC 전용.
create policy "team_members_public_read"
  on public.team_members for select using (true);
```

- [ ] **Step 3: §11-1 blanket grant 뒤에 column-grant 블록 추가**

§11-1 의 `revoke all on public.admin_users from anon, authenticated, public;` 줄 **바로 아래**에 추가 (blanket `grant all on all tables` 가 이 앞에서 실행되므로, 좁히는 grant 는 반드시 그 뒤에 와야 유지된다):

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 11-4. teams column grants — password 봉인 + 상태 전이 RPC 전용화
-- ─────────────────────────────────────────────────────────────────────────────
-- §11-1 의 blanket grant 가 teams 전 컬럼을 열어 두므로 여기서 다시 좁힌다.
-- SELECT: password 만 제외 — 비교는 join_battle 내부에서만.
revoke select on public.teams from anon, authenticated;
grant select (id, owner_id, title, visibility, max_players, age_min, age_max,
              pledge, chat_url, status, started_at, closed_at,
              chemistry_snapshot, result_payload, created_at, updated_at)
  on public.teams to anon, authenticated;
-- INSERT: 생성 입력 컬럼만 — status/started_at/snapshot/payload 는 default·RPC 전용.
revoke insert on public.teams from anon, authenticated;
grant insert (id, owner_id, title, visibility, password, max_players,
              age_min, age_max, pledge, chat_url)
  on public.teams to authenticated;
-- UPDATE: title 만 (방 이름 수정). 상태 전이·payload 는 RPC 전용.
revoke update on public.teams from anon, authenticated;
grant update (title) on public.teams to authenticated;
-- team_members 직접 쓰기 차단 — RPC (security definer) 전용.
revoke insert, update, delete on public.team_members from anon, authenticated;
```

- [ ] **Step 4: 헤더 목차 주석 갱신**

파일 상단(line ~30) `-- · teams · team_members (교감도 그룹 원격 경로, §11-2/11-3, P3)` 를 다음으로 교체:

```sql
--                 · teams · team_members (Chemistry Battle 로비, §11-2/11-3/11-4)
```

- [ ] **Step 5: 구문 검증 (로컬)**

Run: `cd react && node -e "const s=require('fs').readFileSync('db/migrations/0001_baseline.sql','utf8'); console.log('teams cols ok:', /chemistry_snapshot jsonb/.test(s), '| name col gone:', !/team_members[\s\S]{0,900}name\s+text/.test(s))"`
Expected: `teams cols ok: true | name col gone: true`

- [ ] **Step 6: Commit**

```bash
git add react/db/migrations/0001_baseline.sql
git commit -m "feat(db): Chemistry Battle 스키마 — teams 재구성·team_members 셀프 조인·password 봉인

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: RPC 상태 머신 + 공개 목록 view + Realtime + smoke 스크립트

**Files:**
- Modify: `react/db/migrations/0001_baseline.sql` (§11-3 뒤에 §11-5 RPC 구획 추가 — §11-1 grant 구획 앞)
- Create: `react/db/tests/battle_rpc_smoke.sql`

**Interfaces:**
- Produces (Plan 2·3 이 호출):
  - `join_battle(p_team_id uuid, p_password text default null)` — 에러 메시지 계약: `AUTH_REQUIRED`·`NOT_FOUND`·`NOT_RECRUITING`·`BAD_PASSWORD`·`NO_MY_FACE`·`AGE_NOT_ALLOWED`·`FULL`·`ALREADY_JOINED`. 정원 도달 시 같은 트랜잭션에서 snapshot 동결 + `status='revealing'`.
  - `leave_battle(p_team_id uuid)` — `AUTH_REQUIRED`·`OWNER_CANNOT_LEAVE`·`NOT_LEAVABLE`.
  - `submit_battle_result(p_team_id uuid, p_payload jsonb)` — `AUTH_REQUIRED`·`NOT_PARTICIPANT`. first-writer-wins (이미 기록 시 무해 no-op).
  - view `public.public_battles`: `id·title·max_players·age_min·age_max·pledge·created_at·player_count`.
  - Realtime publication 에 `teams`(UPDATE)·`team_members`(INSERT/DELETE) 등록.

- [ ] **Step 1: RPC 구획 추가**

§11-3 의 `team_members_public_read` 정책 끝 바로 아래(§11-1 GRANT 구획 헤더 앞)에 추가:

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 11-5. Battle RPC 상태 머신 + 공개 목록 view + Realtime
-- ─────────────────────────────────────────────────────────────────────────────
-- 조인·이탈·결과 기록은 전부 security definer 단일 트랜잭션 — 정원·비밀번호·
-- 연령·상태 가드를 원자 검증한다. 시작 조건은 정원 충족 하나뿐 (join 내장).

-- 조인: recruiting · 정원 미달 · 미중복 · 비밀번호 · 연령대 · my-face 존재.
-- 마지막 참가자의 트랜잭션이 chemistry_snapshot 동결 + revealing 전이까지 수행.
create or replace function public.join_battle(p_team_id uuid, p_password text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_team  record;
  v_age   int;
  v_count int;
  v_slot  int;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  -- 방 행 잠금 — 동시 조인의 정원 검사를 직렬화 (race 원천 차단).
  select * into v_team from teams where id = p_team_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_team.status <> 'recruiting' then raise exception 'NOT_RECRUITING'; end if;
  if v_team.visibility = 'private'
     and (p_password is null or p_password <> v_team.password) then
    raise exception 'BAD_PASSWORD';
  end if;

  -- my-face 필수 + 연령대 게이트 (body.ageGroup "20s" → 20).
  select nullif(regexp_replace(m.body::jsonb->>'ageGroup', '\D', '', 'g'), '')::int
    into v_age
    from metrics m
   where m.user_id = v_uid and m.is_my_face
   order by m.updated_at desc limit 1;
  if v_age is null then raise exception 'NO_MY_FACE'; end if;
  if v_team.age_min is not null
     and (v_age < v_team.age_min or v_age > v_team.age_max) then
    raise exception 'AGE_NOT_ALLOWED';
  end if;

  select count(*), coalesce(max(slot_no), 0) into v_count, v_slot
    from team_members where team_id = p_team_id;
  if v_count >= v_team.max_players then raise exception 'FULL'; end if;

  begin
    insert into team_members (team_id, user_id, slot_no, is_owner)
    values (p_team_id, v_uid, v_slot + 1, v_uid = v_team.owner_id);
  exception when unique_violation then
    raise exception 'ALREADY_JOINED';
  end;

  -- 정원 충족 = 유일한 시작 조건. 입력(snapshot)을 서버가 동결 — 시작 후
  -- 재촬영이 결과에 영향을 못 주는 치팅 방어 + 전 클라이언트 동일 입력.
  if v_count + 1 = v_team.max_players then
    update teams
       set status = 'revealing',
           started_at = now(),
           chemistry_snapshot = (
             select jsonb_object_agg(tm.user_id::text, mf.body::jsonb)
               from team_members tm
               join lateral (
                 select body from metrics m
                  where m.user_id = tm.user_id and m.is_my_face
                  order by m.updated_at desc limit 1
               ) mf on true
              where tm.team_id = p_team_id
           )
     where id = p_team_id;
  end if;
end;
$$;

-- 이탈: recruiting 중 본인만 (방장은 방 삭제로만 접는다).
create or replace function public.leave_battle(p_team_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if exists (select 1 from teams where id = p_team_id and owner_id = v_uid) then
    raise exception 'OWNER_CANNOT_LEAVE';
  end if;
  delete from team_members tm
   using teams t
   where tm.team_id = p_team_id and tm.user_id = v_uid
     and t.id = tm.team_id and t.status = 'recruiting';
  if not found then raise exception 'NOT_LEAVABLE'; end if;
end;
$$;

-- 결과 기록: revealing 방의 참가자가 1회. first-writer-wins — 입력이
-- snapshot 으로 동결돼 전원이 같은 payload 를 내므로 후착은 무해 no-op.
create or replace function public.submit_battle_result(p_team_id uuid, p_payload jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists (select 1 from team_members
                  where team_id = p_team_id and user_id = v_uid) then
    raise exception 'NOT_PARTICIPANT';
  end if;
  update teams
     set result_payload = p_payload, status = 'completed', closed_at = now()
   where id = p_team_id and status = 'revealing' and result_payload is null;
end;
$$;

revoke execute on function public.join_battle(uuid, text)          from public, anon;
revoke execute on function public.leave_battle(uuid)               from public, anon;
revoke execute on function public.submit_battle_result(uuid, jsonb) from public, anon;
grant  execute on function public.join_battle(uuid, text)          to authenticated;
grant  execute on function public.leave_battle(uuid)               to authenticated;
grant  execute on function public.submit_battle_result(uuid, jsonb) to authenticated;

-- 공개 배틀 목록 — 모집 중 공개방만, 컬럼 화이트리스트 (password 접근 없음).
create or replace view public.public_battles as
  select t.id, t.title, t.max_players, t.age_min, t.age_max, t.pledge, t.created_at,
         (select count(*)::int from public.team_members tm where tm.team_id = t.id)
           as player_count
    from public.teams t
   where t.visibility = 'public' and t.status = 'recruiting';

-- Realtime: 로비 라이브 반영 — teams UPDATE(status 전이) + team_members
-- INSERT/DELETE(입장·이탈). 재실행 안전 (duplicate 무시).
do $$ begin
  alter publication supabase_realtime add table public.teams;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.team_members;
exception when duplicate_object then null; end $$;
```

- [ ] **Step 2: smoke 스크립트 작성**

`react/db/tests/battle_rpc_smoke.sql` 생성 (Supabase SQL 콘솔에 통째로 붙여 실행 — `rollback` 으로 잔여물 0):

```sql
-- Chemistry Battle RPC smoke — Supabase SQL Editor 에서 전체 실행.
-- begin…rollback 이라 데이터 잔여물 없음. 각 단계가 assert 로 검증하며,
-- 실패 시 해당 라인에서 exception 으로 멈춘다. 끝까지 가면 전부 통과.
begin;

-- 테스트 사용자 4명 (handle_new_user 트리거가 users 행 생성).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000',
       ('00000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'authenticated', 'authenticated', 'battle-smoke-' || g || '@test.local', '',
       '{"provider":"email"}', jsonb_build_object('nickname', '테스터' || g),
       now(), now()
from generate_series(1, 4) g;

-- my-face 4개 (u1=20대, u2=30대, u3=20대, u4=50대).
insert into public.metrics (id, user_id, body, is_my_face) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',  true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000002',
   '{"ageGroup":"30s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000003',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',  true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000004',
   '{"ageGroup":"50s","gender":"female","metrics":{}}', true);

-- auth.uid() 시뮬레이션 헬퍼: request.jwt.claims 의 sub 를 바꾼다.
create or replace function pg_temp.act_as(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'),
                      'role', 'authenticated')::text, true);
$$;

-- ① 방 생성: u1, 비밀방 4인, 20~39세, 공약.
select pg_temp.act_as(1);
insert into public.teams (id, owner_id, title, visibility, password, max_players,
                          age_min, age_max, pledge)
values ('11111111-1111-1111-1111-111111111111', auth.uid(), '스모크 배틀',
        'private', '1234', 4, 20, 30, '☕ 커피');

-- ② 방장 조인 (비밀번호 필요).
select public.join_battle('11111111-1111-1111-1111-111111111111', '1234');

-- ③ 가드 검증 — 각각 지정 에러로 거부돼야 한다.
do $$ begin
  perform pg_temp.act_as(2);
  begin
    perform public.join_battle('11111111-1111-1111-1111-111111111111', '0000');
    raise exception 'SMOKE_FAIL: BAD_PASSWORD 가드 미동작';
  exception when others then
    if sqlerrm <> 'BAD_PASSWORD' then raise; end if;
  end;
  begin
    -- 주의: 이 begin 블록은 예외로 끝나므로 안의 성공한 조인도 savepoint
    -- 롤백된다 — 블록이 끝나면 u2 는 미참가 상태다 (④ 가 다시 조인).
    perform public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
    perform public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
    raise exception 'SMOKE_FAIL: ALREADY_JOINED 가드 미동작';
  exception when others then
    if sqlerrm <> 'ALREADY_JOINED' then raise; end if;
  end;
  perform pg_temp.act_as(4); -- 50대 → 연령 게이트.
  begin
    perform public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
    raise exception 'SMOKE_FAIL: AGE_NOT_ALLOWED 가드 미동작';
  exception when others then
    if sqlerrm <> 'AGE_NOT_ALLOWED' then raise; end if;
  end;
end $$;

-- ④ 조인 → 이탈 → 재조인 (u2 — ③ 의 조인은 예외 블록과 함께 롤백된 상태),
--    방장 이탈 금지.
select pg_temp.act_as(2);
select public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
select public.leave_battle('11111111-1111-1111-1111-111111111111');
select public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
do $$ begin
  perform pg_temp.act_as(1);
  begin
    perform public.leave_battle('11111111-1111-1111-1111-111111111111');
    raise exception 'SMOKE_FAIL: OWNER_CANNOT_LEAVE 가드 미동작';
  exception when others then
    if sqlerrm <> 'OWNER_CANNOT_LEAVE' then raise; end if;
  end;
end $$;

-- ⑤ 정원 충족 → 자동 시작 + snapshot 동결. (u4 는 연령 미달이므로 u3 까지 3명
--    + 20대 my-face 를 가진 u4 대체가 필요 — u4 의 my-face 를 20대로 교체해 채운다.)
update public.metrics set body = '{"ageGroup":"20s","gender":"female","metrics":{}}'
 where user_id = '00000000-0000-0000-0000-000000000004' and is_my_face;
select pg_temp.act_as(3);
select public.join_battle('11111111-1111-1111-1111-111111111111', '1234');
select pg_temp.act_as(4);
select public.join_battle('11111111-1111-1111-1111-111111111111', '1234');

do $$
declare v record;
begin
  select status, started_at, chemistry_snapshot into v
    from public.teams where id = '11111111-1111-1111-1111-111111111111';
  if v.status <> 'revealing' then raise exception 'SMOKE_FAIL: 정원 충족 자동 시작 미동작 (%)', v.status; end if;
  if v.started_at is null then raise exception 'SMOKE_FAIL: started_at 미기록'; end if;
  if (select count(*) from jsonb_object_keys(v.chemistry_snapshot)) <> 4 then
    raise exception 'SMOKE_FAIL: snapshot 4인 동결 실패';
  end if;
end $$;

-- ⑥ 시작 후 조인·이탈 차단.
do $$ begin
  begin
    perform public.leave_battle('11111111-1111-1111-1111-111111111111');
    raise exception 'SMOKE_FAIL: 시작 후 leave 차단 미동작';
  exception when others then
    if sqlerrm <> 'NOT_LEAVABLE' then raise; end if;
  end;
end $$;

-- ⑦ 결과 기록 first-writer-wins.
select public.submit_battle_result('11111111-1111-1111-1111-111111111111',
  '{"players":[],"pairs":[],"best":{"a":1,"b":2,"score":90}}');
select pg_temp.act_as(1);
select public.submit_battle_result('11111111-1111-1111-1111-111111111111',
  '{"players":[],"pairs":[],"best":{"a":9,"b":9,"score":1}}');  -- 후착 no-op
do $$
declare v record;
begin
  select status, result_payload into v
    from public.teams where id = '11111111-1111-1111-1111-111111111111';
  if v.status <> 'completed' then raise exception 'SMOKE_FAIL: completed 전이 실패'; end if;
  if v.result_payload->'best'->>'score' <> '90' then
    raise exception 'SMOKE_FAIL: first-writer-wins 위반 (후착이 덮어씀)';
  end if;
end $$;

-- ⑧ 공개 목록 view — 비밀방은 안 보인다.
do $$ begin
  if exists (select 1 from public.public_battles
              where id = '11111111-1111-1111-1111-111111111111') then
    raise exception 'SMOKE_FAIL: 비밀방이 public_battles 에 노출';
  end if;
end $$;

select 'BATTLE RPC SMOKE: ALL PASS' as result;
rollback;
```

- [ ] **Step 3: Supabase 에 baseline + smoke 실행**

1. Supabase SQL Editor 에서 `0001_baseline.sql` 전체 RUN (drop-recreate 자유 — 출시 전).
2. 이어서 `battle_rpc_smoke.sql` 전체 RUN.

Expected: 마지막 결과 행 `BATTLE RPC SMOKE: ALL PASS` (중간 `SMOKE_FAIL` 예외 0). 실행 후 `select count(*) from teams where title='스모크 배틀'` = 0 (rollback 확인).

- [ ] **Step 4: password 봉인 확인 (column grant)**

Supabase SQL Editor:

```sql
set local role authenticated;
select password from public.teams limit 1;  -- 42501 permission denied 기대
reset role;
```

Expected: `permission denied for table teams` (컬럼 SELECT 거부)

- [ ] **Step 5: Commit**

```bash
git add react/db/migrations/0001_baseline.sql react/db/tests/battle_rpc_smoke.sql
git commit -m "feat(db): battle RPC 상태 머신·public_battles view·Realtime publication + smoke

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: cron 개편 — 48h expired + 24h revealing 안전망

**Files:**
- Modify: `react/workers/cron.ts` (closeStaleTeams 교체 + 신규 함수)
- Modify: `react/workers/app.ts:3-7, 26-35` (import·scheduled 분기)

**Interfaces:**
- Consumes: Task 3 스키마 (`teams.status`, `closed_at`).
- Produces: `expireStaleTeams(env)` — 48h 지난 recruiting 방을 `{status:'expired', closed_at}` 처리. `completeOrphanReveals(env)` — 24h 지난 revealing 방(payload null)을 `{status:'completed', closed_at}` 처리 (쇼케이스는 payload null → "결과 미생성" 렌더). `purgeExpiredTeams` 는 `closed_at` 기반이라 무수정 재사용 (expired/completed 모두 30일 후 삭제).

- [ ] **Step 1: cron.ts 의 closeStaleTeams 를 교체**

`react/workers/cron.ts` 에서 `closeStaleTeams` 함수와 그 doc comment 전체(lines ~26-49)를 다음으로 교체:

```typescript
/**
 * 48h 만료 — 시작 조건은 정원 충족 하나뿐이므로 cron 은 시작을 수행하지
 * 않는다. 모집 48h 안에 정원을 못 채운 방은 인원 무관 expired (모이면 굿,
 * 안 모이면 꽝). closed_at 을 찍어 30일 purge 수명주기에 진입시킨다.
 */
export async function expireStaleTeams(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?status=eq.recruiting&created_at=lt.${daysAgo(2)}&select=id`,
    {
      method: 'PATCH',
      headers: {
        ...serviceHeaders(env),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        status: 'expired',
        closed_at: new Date().toISOString(),
      }),
    },
  )
  if (!res.ok) throw new Error(`expireStaleTeams failed: ${res.status}`)
  const expired = ((await res.json()) as unknown[]).length
  if (expired > 0) console.log(`[cron] expireStaleTeams: expired ${expired}`)
  return expired
}

/**
 * revealing 고아 안전망 — 시작됐지만 전 참가자 이탈 등으로 24h 내
 * result_payload 가 backfill 되지 않은 방을 completed 로 닫는다.
 * payload 는 null 로 남고 쇼케이스가 "결과 미생성" 을 렌더.
 */
export async function completeOrphanReveals(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?status=eq.revealing&result_payload=is.null&started_at=lt.${daysAgo(1)}&select=id`,
    {
      method: 'PATCH',
      headers: {
        ...serviceHeaders(env),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        status: 'completed',
        closed_at: new Date().toISOString(),
      }),
    },
  )
  if (!res.ok) throw new Error(`completeOrphanReveals failed: ${res.status}`)
  const closed = ((await res.json()) as unknown[]).length
  if (closed > 0) console.log(`[cron] completeOrphanReveals: closed ${closed}`)
  return closed
}
```

파일 상단 doc comment 의 잡 목록도 갱신:

```typescript
/**
 * Cron Triggers 잡 4종 — wrangler.jsonc `triggers.crons` 가 스케줄, 호출은
 * Cloudflare 플랫폼이 직접 (`workers/app.ts` 의 `scheduled` 핸들러).
 *
 *   매시    expireStaleTeams      — 모집 48h 초과 방 expired (시작은 cron 몫 아님).
 *   매시    completeOrphanReveals — revealing 24h 고아 방 completed 안전망.
 *   매일    cleanupStaleMetrics   — 90일 미활동 anon metrics + R2 썸네일 삭제.
 *   매일    purgeExpiredTeams     — 종료 후 30일 지난 teams 삭제 (멤버 cascade).
 *
 * 로컬 테스트: `pnpm wrangler dev` 후
 *   curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"
 */
```

- [ ] **Step 2: app.ts scheduled 연결 교체**

`react/workers/app.ts` import 를:

```typescript
import {
  cleanupStaleMetrics,
  completeOrphanReveals,
  expireStaleTeams,
  purgeExpiredTeams,
} from "./cron";
```

scheduled 핸들러의 else 분기(`await closeStaleTeams(env);`)를:

```typescript
    } else {
      // 매시 정각 — 48h 만료 + revealing 고아 안전망.
      await expireStaleTeams(env);
      await completeOrphanReveals(env);
    }
```

- [ ] **Step 3: typecheck + 로컬 cron 실행**

Run: `cd react && pnpm typecheck && pnpm build:shared && pnpm wrangler dev` (별도 셸에서) `curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"`
Expected: typecheck exit 0 · curl 200 · wrangler 로그에 에러 없음 (대상 0건이면 로그 무출력이 정상)

- [ ] **Step 4: Commit**

```bash
git add react/workers/cron.ts react/workers/app.ts
git commit -m "feat(cron): 48h expired + 24h revealing 안전망 — 자동 발표 폐기

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 완료 기준 (Plan 1 전체)

1. `flutter test` 전부 green (기존 + battle_test 6) · `flutter analyze` 신규 0.
2. `pnpm build:shared` 성공 — `runBattle` 이 JS 산출물에 포함.
3. Supabase 에 baseline 재적용 후 `battle_rpc_smoke.sql` → `ALL PASS`.
4. authenticated 롤로 `teams.password` SELECT 시 42501.
5. `pnpm typecheck` + 로컬 `__scheduled` 호출 정상.

이후: **Plan 2 (Flutter 개편)** — 케미 탭 2탭·생성 스텝·로비(Realtime 구독 + QR)·조인·결과 연출 화면, `teamsProvider` 서버-우선 재작성, walk-in·이름 슬롯 UI 제거, `team_matrix.dart` 삭제. **Plan 3 (웹)** — JoinWizard RPC 교체·로비 라이브·쇼케이스 payload 렌더·`runBattle` 사용. 두 계획은 이 계획의 산출 인터페이스가 실재가 된 뒤 작성한다.
