# unlocks 칼럼 보강 설계

2026-07-12 승인. 궁합 unlock ledger 를 실체에 맞는 이름과 alias 스냅샷으로 보강한다.

## 배경 (확인된 사실)

- `pair_key` 는 이미 **상대 metrics id 단독**이다 (`shared/.../compat_pair_key.dart` 설계 결정: 내 사진을 바꿔도 같은 상대의 unlock 유지). `my~album` 복합 키라는 baseline.sql 주석과 refine 컬럼 표기가 실체와 다르다.
- body 스냅샷(`toBodyJson()`)에는 alias 가 없다(공개 read 인 metrics 의 body 내 PII 금지 정책). 그래서 재설치·새 기기에서 궁합 확인 리스트/코인 사용내역의 상대가 이름 없이 복원된다.
- unlocks 는 RLS 로 본인만 read/delete — alias 를 **컬럼**으로 저장하는 것이 안전하고 올바른 위치.
- 프로덕션 unlocks 는 1행, pair_key 값은 이미 uuid 형식. 복합 키 잔재 없음.

## 최종 스키마

```sql
create table public.unlocks (
  user_id       uuid not null references auth.users(id) on delete cascade,
  partner_id    uuid not null,  -- 상대 metrics id. FK 없음 — 스냅샷은 metrics 삭제를 견뎌야 함
  user_body     text,           -- 결제 시점 내 관상 body (owner_body 에서 rename)
  partner_body  text,           -- 결제 시점 상대 body
  user_alias    text,           -- 결제 시점 내 닉네임 — admin 표시용
  partner_alias text,           -- 결제 시점 상대 alias — 앱 fallback + admin
  total_score   real,
  created_at    timestamptz not null default now(),
  primary key (user_id, partner_id)
);
```

RLS 정책(`unlocks_self_read`/`unlocks_self_delete`)은 그대로.

## 변경 SQL (react/db/migrations/0002)

1. `pair_key` → `partner_id` rename + `uuid` 타입 캐스팅, `owner_body` → `user_body` rename
2. `user_alias`, `partner_alias` 컬럼 추가
3. backfill: `partner_alias` ← `metrics.alias` (해당 row 가 살아 있는 경우), `user_alias` ← `users.nickname`
4. RPC `unlock_compat` 재정의:
   `(p_partner_id uuid, p_total_score real, p_user_body text, p_partner_body text, p_user_alias text, p_partner_alias text)`
   — 이전 시그니처는 drop, 이중 유지 없음
5. `coins.reference_id` 는 값이 동일(상대 uuid 문자열)이므로 변경 없음

## 앱 (flutter)

- `CompatUnlockService`: `unlock()` 이 alias 2개 전달 — 내 쪽 `nickname`, 상대 쪽 카드 `alias`. `list()`/`partnerSnapshotsByPairKey()`/`deleteUnlock()` 을 `partner_id` 컬럼명으로 갱신. 스냅샷 복원 시 `alias: null` override 를 `alias: partner_alias` 로 교체.
- **표시 우선순위 (승인된 규칙 A)**: 확인 리스트·코인 사용내역에서 로컬 history 에 해당 카드(supabaseId 일치)가 있으면 현재 이름(개명 반영), 없으면 `partner_alias` 스냅샷.

## refine

- `Unlock` 타입 필드명 갱신, 궁합 리스트의 `pair_key (my~album)` 컬럼을 `상대`(= `partner_alias` + id 축약)로, `user_alias` 는 상세에서 표시.
- 궁합 상세(unlocks body 1차 소스)의 `owner_body` 참조를 `user_body` 로.

## 검증

- SQL 적용 후 기존 1행이 새 컬럼으로 온전한지 조회 확인
- flutter analyze / flutter test green, 실기에서 unlock → 확인 리스트 이름 표시 확인
- refine `tsc --noEmit` 통과 + 궁합 리스트/상세 육안 확인
