# unlocks 칼럼 보강 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** unlocks 테이블을 실체에 맞는 이름(`partner_id`/`user_body`)으로 정정하고 결제 시점 alias 스냅샷(`user_alias`/`partner_alias`)을 추가, 앱·admin 이 이름을 표시하게 한다.

**Architecture:** DB 변경 SQL(rename + 컬럼 추가 + RPC 재정의) → flutter 서비스/호출부 → refine 타입/페이지. pair_key 는 이미 "상대 metrics id 단독"이므로 클라이언트 로직 의미는 불변 — 컬럼명·RPC 시그니처·alias 전달만 바뀐다. 스펙: `docs/superpowers/specs/2026-07-12-unlocks-columns-design.md`.

**Tech Stack:** Supabase(Postgres RPC/RLS), Flutter(Riverpod), React(refine + antd).

## Global Constraints

- 이전 RPC 시그니처와의 이중 유지 없음 — clean cut (프로젝트 룰).
- `partner_id` 에 FK 금지 — 스냅샷은 metrics 삭제를 견뎌야 함.
- 표시 우선순위 A: 로컬 history 카드(supabaseId 일치)의 현재 이름 우선, 없으면 `partner_alias` 스냅샷.
- flutter: `flutter analyze` 변경 파일 0 issue, `flutter test` 151개 green 유지.
- refine: `pnpm exec tsc --noEmit` 통과.
- unlocks 신규 단위 테스트는 만들지 않는다 — RPC 래퍼는 Supabase mock 인프라가 없어 기존 관례대로 전체 스위트 + 실기 확인으로 검증.

---

### Task 1: DB 스키마 — 0001_baseline.sql 직접 수정 + 프로덕션 one-off 적용

배포 전이므로 변경 파일(0002)을 만들지 않고 `0001_baseline.sql` 을 최종 상태로 직접 수정한다 (사용자 지시). 프로덕션에는 이미 이전 스키마가 적용돼 있으므로, 반영은 커밋하지 않는 one-off ALTER SQL 로 한다 (`create table if not exists` 는 기존 테이블을 바꾸지 못함).

**Files:**
- Modify: `react/db/migrations/0001_baseline.sql` — §4 unlocks 테이블(라인 ~250-266), §9 unlock_compat RPC(라인 ~465-518), §10 grants(라인 ~525·530), 파일 헤더는 변경 없음
- Create(비커밋, scratch): 프로덕션 반영용 one-off ALTER SQL — 세션 scratchpad 에 `unlocks-oneoff.sql`

**Interfaces:**
- Produces: `unlocks(user_id uuid, partner_id uuid, user_body text, partner_body text, user_alias text, partner_alias text, total_score real, created_at timestamptz)`, PK `(user_id, partner_id)`
- Produces: RPC `unlock_compat(p_partner_id uuid, p_total_score real, p_user_body text, p_partner_body text, p_user_alias text, p_partner_alias text) returns integer`

- [ ] **Step 1: baseline §4 unlocks 테이블 정의 교체**

기존 §4 의 헤더 주석 + `create table` 블록을 다음으로 교체 (RLS/policy 부분은 그대로):

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 4. public.unlocks — 궁합 카드 해제 ledger
-- ─────────────────────────────────────────────────────────────────────────────
-- partner_id = 상대 metrics id 단독 (shared compat_pair_key 설계 — 내 사진을
-- 바꿔도 같은 상대의 unlock 이 유지된다). FK 없음 — 스냅샷은 metrics 삭제를 견딤.
-- INSERT 는 unlock_compat (SECURITY DEFINER) RPC 만 — 코인 차감 + 삽입 트랜잭션.

create table if not exists public.unlocks (
  user_id       uuid        not null references auth.users(id) on delete cascade,
  partner_id    uuid        not null,
  user_body     text,      -- 결제 시점 본인 metrics body 스냅샷.
  partner_body  text,      -- 결제 시점 상대 metrics body 스냅샷.
                           -- 두 body 를 동결해 구매한 궁합을 self-contained 로 보존.
                           -- metrics row·로컬 history 에 의존하지 않고 단독 복원/표시.
  user_alias    text,      -- 결제 시점 본인 닉네임 — admin 표시용.
  partner_alias text,      -- 결제 시점 상대 alias — 앱 fallback + admin 표시.
                           -- (body 스냅샷은 PII 정책상 alias 를 담지 않음.
                           --  unlocks 는 RLS self-read 라 컬럼 저장이 안전.)
  total_score real,        -- 해제 시점 궁합 총점(0~100). admin 콘솔 정렬·필터용.
  created_at timestamptz not null default now(),
  primary key (user_id, partner_id)
);
```

- [ ] **Step 2: baseline §9 RPC 교체**

drop 라인들을 아래로 교체하고:

```sql
drop function if exists public.unlock_compat(text);
drop function if exists public.unlock_compat(text, real);
drop function if exists public.unlock_compat(text, real, text, text);
```

`create or replace function public.unlock_compat(...)` 본문 전체를 다음으로 교체 (§9 헤더 주석의 "이미 해제됐으면 idempotent / 잔액 부족이면 -1" 은 유지):

```sql
create or replace function public.unlock_compat(
  p_partner_id    uuid,
  p_total_score   real default null,
  p_user_body     text default null,
  p_partner_body  text default null,
  p_user_alias    text default null,
  p_partner_alias text default null
)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_balance integer;
  v_already boolean;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_partner_id is null then raise exception 'partner_id required'; end if;

  select exists(
    select 1 from unlocks
    where user_id = v_uid and partner_id = p_partner_id
  ) into v_already;

  if v_already then
    select coins into v_balance from users where id = v_uid;
    return v_balance;
  end if;

  update users set coins = coins - 1
    where id = v_uid and coins >= 1
    returning coins into v_balance;
  if v_balance is null then return -1; end if;

  -- 결제 확정 → body·alias 를 클라이언트가 넘긴 그대로 동결 저장.
  -- metrics row 존재 여부에 의존하지 않아 (업로드 누락·삭제·만료와 무관)
  -- 구매한 궁합이 self-contained 로 영구 보존된다.
  insert into unlocks (user_id, partner_id, user_body, partner_body,
                       user_alias, partner_alias, total_score)
    values (v_uid, p_partner_id, p_user_body, p_partner_body,
            p_user_alias, p_partner_alias, p_total_score);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance, p_partner_id::text, 'compat-unlock');

  return v_balance;
end; $$;
```

- [ ] **Step 3: baseline §10 grants 시그니처 갱신**

`unlock_compat(text, real, text, text)` 를 언급하는 revoke/grant 두 줄을 `unlock_compat(uuid, real, text, text, text, text)` 로.

- [ ] **Step 4: 프로덕션 one-off SQL 작성 (scratch, 커밋 금지)**

세션 scratchpad 에 `unlocks-oneoff.sql` 로 저장:

```sql
begin;

alter table public.unlocks rename column pair_key   to partner_id;
alter table public.unlocks rename column owner_body to user_body;
alter table public.unlocks
  alter column partner_id type uuid using partner_id::uuid;
alter table public.unlocks add column if not exists user_alias    text;
alter table public.unlocks add column if not exists partner_alias text;

-- 기존 행 backfill — 살아 있는 row 에서만 채운다.
update public.unlocks u
   set partner_alias = m.alias
  from public.metrics m
 where m.id = u.partner_id and u.partner_alias is null;

update public.unlocks u
   set user_alias = us.nickname
  from public.users us
 where us.id = u.user_id and u.user_alias is null;

drop function if exists public.unlock_compat(text, real, text, text);

-- 아래 create function·revoke·grant 는 baseline §9·§10 과 동일 내용을 붙여넣는다.
-- (Step 2 의 create or replace function 전문 + Step 3 의 grant 2줄)

commit;
```

(작성 시 주석 자리에 실제 함수 전문과 grant 문을 인라인으로 포함할 것 — SQL Editor 에 한 번에 붙여넣어 실행 가능해야 한다.)

- [ ] **Step 5: 프로덕션 적용**

Supabase 대시보드 → SQL Editor 에 one-off SQL 을 붙여넣어 실행 (supabase CLI 미설치, DDL 은 REST 로 불가 — 사용자 실행 필요).

- [ ] **Step 6: REST 로 결과 검증**

```bash
cd /Users/chuck/Code/face/refine
URL=$(grep VITE_SUPABASE_URL .env | cut -d= -f2) && KEY=$(grep VITE_SUPABASE_SERVICE_KEY .env | cut -d= -f2) && \
curl -s "$URL/rest/v1/unlocks?select=user_id,partner_id,user_alias,partner_alias,total_score" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: 기존 1행이 `partner_id`(uuid)·`user_alias`(닉네임)·`partner_alias`(metrics.alias 값 또는 null) 로 반환.

- [ ] **Step 7: Commit (baseline 만 — one-off scratch 는 커밋하지 않음)**

```bash
cd /Users/chuck/Code/face
git add react/db/migrations/0001_baseline.sql
git commit -m "feat(db): unlocks pair_key→partner_id·alias 스냅샷 + unlock_compat 재정의"
```

---

### Task 2: flutter CompatUnlockService + provider

**Files:**
- Modify: `flutter/lib/data/services/compat_unlock_service.dart`
- Modify: `flutter/lib/presentation/providers/compat_unlock_provider.dart`

**Interfaces:**
- Produces: `CompatUnlockService.list() → Future<Set<String>>` (partner_id 집합 — 값 의미는 이전과 동일: 상대 metrics id)
- Produces: `partnerSnapshotsByPartnerId() → Future<Map<String, FaceReadingReport>>` (`partnerSnapshotsByPairKey` 에서 rename; 스냅샷 report 의 `alias` 에 `partner_alias` 주입)
- Produces: `unlock(String partnerId, {required String userBody, required String partnerBody, String? userAlias, String? partnerAlias, double? totalScore}) → Future<int>`
- Produces: `deleteUnlock(List<String> partnerIds)`

- [ ] **Step 1: 서비스 갱신**

`compat_unlock_service.dart` 의 클래스 본문을 다음으로 교체 (import·클래스 선언·`_client` getter 는 그대로):

```dart
  /// 현 사용자의 unlock 된 상대 metrics id(partner_id) 집합. 비로그인이면 빈 set.
  Future<Set<String>> list() async {
    if (_client.auth.currentUser == null) return const {};
    try {
      final rows = await _client.from('unlocks').select('partner_id');
      return {for (final r in rows) r['partner_id'] as String};
    } catch (e) {
      debugPrint('[CompatUnlock] list error: $e');
      return const {};
    }
  }

  /// unlocks 의 `partner_body`(결제 시점 상대 스냅샷)를 [FaceReadingReport] 로 복원.
  ///
  /// body 는 `toBodyJson()` 출력이라 supabaseId 가 빠져 있으므로 partner_id 를
  /// supabaseId 로 주입하고, source/isMyFace/alias/thumbnailPath 를 override 한 뒤
  /// parse. metrics row·로컬 history 에 의존하지 않는 self-contained 복원.
  Future<List<FaceReadingReport>> reconstructUnlockedPartners() async {
    return (await partnerSnapshotsByPartnerId()).values.toList();
  }

  /// `partner_id → 결제 시점 partner 스냅샷(FaceReadingReport)` 맵.
  ///
  /// `unlocks.partner_body` 만 디코드하므로 로컬 history·metrics row 에 의존하지
  /// 않는다. ledger(코인 사용내역)·확인 리스트가 기기·재설치·eviction 무관하게
  /// 항상 상대 사진/인적정보를 띄우는 source of truth. 이름은 body 가 아니라
  /// `partner_alias` 컬럼 스냅샷(결제 시점 동결)에서 주입.
  Future<Map<String, FaceReadingReport>> partnerSnapshotsByPartnerId() async {
    if (_client.auth.currentUser == null) return const {};
    final List<dynamic> rows;
    try {
      rows = await _client
          .from('unlocks')
          .select('partner_id, partner_body, partner_alias');
    } catch (e) {
      debugPrint('[CompatUnlock] partner snapshot fetch error: $e');
      return const {};
    }
    final map = <String, FaceReadingReport>{};
    for (final r in rows) {
      final partnerId = r['partner_id'] as String?;
      final body = r['partner_body'] as String?;
      if (partnerId == null || body == null || body.isEmpty) continue;
      try {
        final original = jsonDecode(body) as Map<String, dynamic>;
        final overridden = <String, dynamic>{
          ...original,
          'supabaseId': partnerId,
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': r['partner_alias'],
          'thumbnailPath': null,
        };
        map[partnerId] =
            FaceReadingReport.fromJsonString(jsonEncode(overridden));
      } catch (e) {
        debugPrint(
            '[CompatUnlock] partner snapshot decode failed partnerId=$partnerId: $e');
      }
    }
    return map;
  }

  /// unlock_compat RPC 호출. body·alias 를 결제 시점 스냅샷으로 동결.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  ///
  /// RPC 자체가 실패하면 [Exception] 을 그대로 throw — 호출부에서 try/catch
  /// 로 감싸 사용자 피드백을 띄울 것.
  Future<int> unlock(
    String partnerId, {
    required String userBody,
    required String partnerBody,
    String? userAlias,
    String? partnerAlias,
    double? totalScore,
  }) async {
    final result = await _client.rpc('unlock_compat', params: {
      'p_partner_id': partnerId,
      'p_total_score': ?totalScore,
      'p_user_body': userBody,
      'p_partner_body': partnerBody,
      'p_user_alias': ?userAlias,
      'p_partner_alias': ?partnerAlias,
    });
    debugPrint(
        '[CompatUnlock] unlock $partnerId → $result (${result.runtimeType})');
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.parse(result);
    throw StateError(
        'unlock_compat returned unexpected type: ${result.runtimeType} ($result)');
  }

  /// 확인 리스트에서 "내 목록에서 제거" — unlock 행 삭제. RLS(`unlocks_self_delete`)
  /// 가 user_id 로 스코프하므로 partner_id 만으로 본인 행만 지운다. 코인 환불 없음.
  Future<void> deleteUnlock(List<String> partnerIds) async {
    for (final id in partnerIds) {
      await _client.from('unlocks').delete().eq('partner_id', id);
    }
  }
```

클래스 헤더 doc comment 는 그대로 두되, 파일 상단에 변경 없음.

- [ ] **Step 2: provider 갱신**

`compat_unlock_provider.dart` — 메서드 rename 반영 + 주석 정정:

```dart
/// 현 사용자의 compat unlock partner_id 집합.
/// auth (로그인/로그아웃/잔액 리프레시) 변화에 재구독돼 자동 refetch.
final compatUnlocksProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(authProvider);
  return CompatUnlockService().list();
});

/// unlocks.partner_body 에서 복원한 파트너 리포트 목록 (로컬에 없는 갭 메우기용).
/// auth 변화에 재구독.
final unlockedPartnerBodiesProvider =
    FutureProvider.autoDispose<List<FaceReadingReport>>((ref) async {
  ref.watch(authProvider);
  return CompatUnlockService().reconstructUnlockedPartners();
});

/// `partner_id → 결제 시점 partner 스냅샷` 맵. ledger(코인 사용내역)가 로컬
/// 히스토리 의존 없이 항상 상대 사진·인적정보를 띄우는 source. auth 변화에 재구독.
final compatPartnerSnapshotsProvider =
    FutureProvider.autoDispose<Map<String, FaceReadingReport>>((ref) async {
  ref.watch(authProvider);
  return CompatUnlockService().partnerSnapshotsByPartnerId();
});
```

- [ ] **Step 3: 컴파일 확인**

Run: `cd /Users/chuck/Code/face/flutter && flutter analyze`
Expected: 변경 파일 0 issue (다른 파일의 7개 pre-existing 이슈만).
(이 시점에 호출부 `unlock(key, ownerBody: ...)` 가 아직 안 고쳐져 에러가 나면 정상 — Task 3 후 재확인.)

---

### Task 3: flutter 호출부 — alias 전달 + 표시 우선순위 A

**Files:**
- Modify: `flutter/lib/presentation/screens/compatibility/compat_unlock_action.dart`
- Modify: `flutter/lib/presentation/screens/ledger/ledger_page.dart`
- Modify: `flutter/lib/presentation/screens/compatibility/compatibility_screen.dart` (주석 1곳)

**Interfaces:**
- Consumes: Task 2 의 `unlock(partnerId, {userBody, partnerBody, userAlias, partnerAlias, totalScore})`

- [ ] **Step 1: unlock 호출에 alias 전달**

`compat_unlock_action.dart` — import 추가:

```dart
import 'package:facely/data/services/auth_service.dart';
```

RPC 호출부(기존 Step 5 블록)를 교체:

```dart
  // 5. RPC. unlock 직전에 분석을 실행해 total_score 를 함께 기록 — admin 콘솔
  // (refine) 에서 점수별 정렬·필터 가능하도록. alias 는 결제 시점 이름 스냅샷
  // (내 쪽 = 프로필 닉네임, 상대 쪽 = 카드에 지정한 이름).
  final preBundle = analyzeCompatibilityFromReports(my: my, album: album);
  final int newBalance;
  try {
    newBalance = await CompatUnlockService().unlock(
      key,
      userBody: my.toBodyJson(),
      partnerBody: album.toBodyJson(),
      userAlias: AuthService().currentUser?.nickname,
      partnerAlias: album.alias,
      totalScore: preBundle.report.total,
    );
  } catch (e, st) {
```

(catch 이하는 기존 그대로.)

- [ ] **Step 2: ledger 에 표시 우선순위 A**

`ledger_page.dart` — import 추가:

```dart
import 'package:facely/presentation/providers/history_provider.dart';
```

`_TransactionTile.build` 의 subtitle 계산부를 교체:

```dart
    final snapshots =
        ref.watch(compatPartnerSnapshotsProvider).asData?.value ?? const {};
    final album = _resolveAlbum(snapshots);
    // 이름 우선순위: 로컬 history 의 현재 이름(개명 반영) → 결제 시점
    // partner_alias 스냅샷 (재설치·새 기기 fallback).
    String? alias = album?.alias;
    for (final r in ref.watch(historyProvider)) {
      if (r.supabaseId != null && r.supabaseId == tx.referenceId) {
        if (r.alias != null && r.alias!.isNotEmpty) alias = r.alias;
        break;
      }
    }
    final demographic = album == null
        ? null
        : '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';
    final subtitle = album == null
        ? null
        : (alias != null && alias.isNotEmpty
            ? '$alias · $demographic'
            : demographic);
```

`_resolveAlbum` 내부 주석 한 줄 정정:

```dart
    // reference_id 는 곧 partner_id — 스냅샷 맵 직접 조회.
```

- [ ] **Step 3: compatibility_screen 주석 정정**

`compatibility_screen.dart` 의 삭제 흐름 주석(`// pair_key = 상대 supabaseId 단독.`, `deleteUnlock` 위)을:

```dart
    // partner_id = 상대 supabaseId. RLS 가 본인 행만 지운다.
```

(확인 리스트의 local-first 는 이미 구조적으로 우선순위 A — 로컬 카드를 직접 쓰고 복원 파트너는 갭 메우기만.)

- [ ] **Step 4: 검증**

Run: `cd /Users/chuck/Code/face/flutter && flutter analyze && flutter test`
Expected: 변경 파일 0 issue, 151 tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/chuck/Code/face
git add flutter/lib
git commit -m "feat(flutter): unlock 에 alias 스냅샷 전달 + ledger 이름 로컬우선 표시"
```

---

### Task 4: refine — 타입·궁합 리스트/상세·사용자 상세

**Files:**
- Modify: `refine/src/types.ts` (Unlock 타입)
- Modify: `refine/src/pages/unlocks/list.tsx`
- Modify: `refine/src/pages/unlocks/show.tsx`
- Modify: `refine/src/pages/users/show.tsx` (궁합 unlock 카드)

**Interfaces:**
- Consumes: Task 1 의 새 unlocks 스키마

- [ ] **Step 1: Unlock 타입 갱신**

`types.ts`:

```ts
export type Unlock = {
  user_id: string;
  /** 상대 metrics id — FK 없음(스냅샷은 metrics 삭제를 견딤). */
  partner_id: string;
  /** 결제 시점 본인/상대 metrics body 스냅샷 — metrics row 삭제와 무관하게
   *  궁합을 self-contained 로 복원한다 (해석의 1차 소스). */
  user_body: string | null;
  partner_body: string | null;
  /** 결제 시점 이름 스냅샷 — user: 본인 닉네임, partner: 카드에 지정한 이름. */
  user_alias: string | null;
  partner_alias: string | null;
  total_score: number | null;
  created_at: string;
};
```

- [ ] **Step 2: unlocks/list.tsx 갱신**

- `rowKey={(r) => \`${r.user_id}~${r.pair_key}\`}` → `rowKey={(r) => \`${r.user_id}~${r.partner_id}\`}`
- `pair_key (my~album)` 컬럼을 교체:

```tsx
        <Table.Column<Unlock>
          title="상대"
          dataIndex="partner_id"
          render={(v: string, r: Unlock) => (
            <Space>
              {r.partner_alias ? (
                <Text strong>{r.partner_alias}</Text>
              ) : (
                <Text type="secondary">(이름 없음)</Text>
              )}
              <Text code copyable={{ text: v }} style={{ fontSize: 11 }}>
                {v.slice(0, 8)}…
              </Text>
            </Space>
          )}
        />
```

- 메뉴 컬럼: `dataIndex="pair_key"` → `"partner_id"`, render 파라미터 `(pairKey: string, r: Unlock)` → `(partnerId: string, r: Unlock)`, `<ShowButton ... recordItemId={partnerId} />`
- `handleDelete`: `.eq("pair_key", r.pair_key)` → `.eq("partner_id", r.partner_id)`

- [ ] **Step 3: unlocks/show.tsx 재작성**

파일 전체를 교체 — 스냅샷 단일 소스(모든 현행 행이 스냅샷 보유), `pair_key.split("~")` 기반 live-metrics 경로는 partner-only 키에서 성립 불가라 제거:

```tsx
import { Show } from "@refinedev/antd";
import { useList } from "@refinedev/core";
import { Alert, Descriptions, Space, Typography } from "antd";
import { useMemo } from "react";
import { useParams } from "react-router";
import type { Unlock } from "../../types";
import { metricThumbUrl } from "../../types";
import { runCompat, type CompatOutput } from "../../lib/share-engine";
import { CompatHeroCard } from "../metrics/HeroCard";

const { Text } = Typography;

export const UnlockShow = () => {
  const { id } = useParams<{ id: string }>();
  const partnerId = id ? decodeURIComponent(id) : "";

  // 결제 시점 body 스냅샷이 해석 소스 — metrics row 삭제와 무관.
  const { result: unlockResult, query: unlockQuery } = useList<Unlock>({
    resource: "unlocks",
    filters: [{ field: "partner_id", operator: "eq", value: partnerId }],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 1 },
    queryOptions: { enabled: Boolean(partnerId) },
  });
  const unlock = (unlockResult?.data ?? [])[0];
  const hasSnapshot = Boolean(unlock?.user_body && unlock?.partner_body);

  const compat = useMemo<{ out?: CompatOutput; error?: string }>(() => {
    if (!hasSnapshot) return {};
    try {
      return { out: runCompat(unlock!.user_body!, unlock!.partner_body!) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [hasSnapshot, unlock]);

  const isLoading = unlockQuery.isLoading;

  return (
    <Show isLoading={isLoading} title="궁합 해석">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        <Descriptions column={2} bordered size="small">
          <Descriptions.Item label="partner_id (상대 metrics)" span={2}>
            <Text code copyable={{ text: partnerId }} style={{ fontSize: 12 }}>
              {partnerId}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="본인 (user_alias)">
            {unlock?.user_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
          <Descriptions.Item label="상대 (partner_alias)">
            {unlock?.partner_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
        </Descriptions>

        {!isLoading && !hasSnapshot && (
          <Alert
            type="warning"
            showIcon
            message="복원 불가"
            description="unlock 행에 body 스냅샷이 없어 해석할 수 없습니다."
          />
        )}

        {compat.error && (
          <Alert
            type="error"
            showIcon
            message="엔진 실행 실패"
            description={
              <Text code style={{ whiteSpace: "pre-wrap" }}>
                {compat.error}
              </Text>
            }
          />
        )}

        {compat.out && (
          <CompatHeroCard
            compat={compat.out}
            thumbA={metricThumbUrl(unlock?.user_body ?? undefined)}
            thumbB={metricThumbUrl(unlock?.partner_body ?? undefined)}
          />
        )}
      </Space>
    </Show>
  );
};
```

(`metricThumbUrl` 시그니처가 `string | null | undefined` 를 받지 않으면 `?? undefined` 대신 기존 시그니처에 맞춰 조정.)

- [ ] **Step 4: users/show.tsx 궁합 카드 갱신**

`rowKey="pair_key"` → `rowKey="partner_id"`, `pair_key` 컬럼을 교체:

```tsx
            <Table.Column<Unlock>
              title="상대"
              dataIndex="partner_id"
              render={(v: string, r: Unlock) => (
                <Space>
                  {r.partner_alias ? (
                    <Text strong>{r.partner_alias}</Text>
                  ) : (
                    <Text type="secondary">-</Text>
                  )}
                  <Text code style={{ fontSize: 11 }}>
                    {v.slice(0, 8)}…
                  </Text>
                </Space>
              )}
            />
```

- [ ] **Step 5: 검증**

Run: `cd /Users/chuck/Code/face/refine && pnpm exec tsc --noEmit`
Expected: 통과 (출력 없음).

- [ ] **Step 6: Commit**

```bash
cd /Users/chuck/Code/face
git add refine/src
git commit -m "feat(refine): unlocks partner_id·alias 스냅샷 반영 — 궁합 리스트/상세 이름 표시"
```

---

### Task 5: 통합 검증

- [ ] **Step 1: REST 스모크** — Task 1 Step 3 쿼리 재실행, 스키마·데이터 확인.
- [ ] **Step 2: flutter 전체** — `flutter analyze && flutter test` green.
- [ ] **Step 3: refine 육안** — `pnpm dev` 로 궁합 리스트(상대 이름 컬럼)·궁합 상세(user/partner_alias·HeroCard)·사용자 상세(궁합 카드) 확인.
- [ ] **Step 4: 실기(선택, 사용자)** — 앱에서 새 unlock 1건 → 확인 리스트·코인 사용내역에 상대 이름 표시, refine 궁합 상세에 alias 2개 확인.
