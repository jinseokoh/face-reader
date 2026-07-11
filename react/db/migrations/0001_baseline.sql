-- ============================================================================
-- 0001 — facely Supabase clean-slate baseline
-- ============================================================================
--
-- 이 한 파일이 모든 public schema 의 **현재 운영 상태** 를 재현한다. 시스템
-- 이전·재해복구·새 환경 부트스트랩 시 빈 Supabase 프로젝트의 SQL Editor 에
-- 통째로 붙여 넣고 RUN. extension 외엔 모두 idempotent (DROP IF EXISTS + CREATE
-- OR REPLACE).
--
-- ⚠️ 완전 초기화 (clean slate — 데이터까지 삭제):
--   테이블이 `create table if not exists` 라, 이 파일을 그대로 RUN 하면
--   policy·RPC·view·trigger 만 갱신되고 **기존 행 데이터는 보존**된다. 데이터까지
--   비우려면 SQL Editor 에서 아래를 먼저 실행한 뒤 이 파일 전체를 붙여넣고 RUN:
--
--     drop schema public cascade;
--     create schema public;
--
--   (테이블/시퀀스 GRANT 는 baseline §11-1 이 재부여하므로 위 두 줄이면 충분.
--    그 GRANT 를 빠뜨리면 로그인 직후 `42501 permission denied for table users`.)
--
--   주의:
--     • auth.users 는 public 밖이라 위 drop 으로 안 지워진다 → 계정·코인까지
--       리셋하려면 대시보드 Authentication → Users 에서 별도 삭제. (재가입 시
--       handle_new_user 트리거가 public.users + 보너스 3 코인 재생성)
--     • R2(cdn.facely.kr) 썸네일 객체는 supabase 와 무관 — 별도로 남는다.
--
-- 포함:
--   • tables    : users · coins · metrics · unlocks · bonus_recipients · ad_rewards
--                 · ad_videos (custom video, §11-0) · ad_images (홈 배너, §11-0b)
--                 · teams · team_members (교감도 그룹 원격 경로, §11-2/11-3, P3)
--   • views     : admin_users (users + auth.users.email · service_role 전용)
--   • triggers  : handle_new_user (auth.users → public.users + 보너스 3 코인)
--                 touch_metrics_updated_at (views++ 시 updated_at 자동 갱신)
--   • rpcs      : grant_coins · admin_grant_coins · spend_coins · unlock_compat
--                 increment_metrics_views · ad_reward_status · ad_reward_record_view
--   • rls       : 각 테이블 별 정책
--   • indexes   : 운영 query 패턴 기반
--   • grants    : RPC 권한 + 테이블/시퀀스 (§11-1)
--
-- SSOT for application contract:
--   • Worker  : react/app/lib/supabase.ts (fetchMetrics / incrementMetricsViews)
--               react/app/routes/api.r2.presign.ts
--   • Flutter : flutter/lib/data/services/{supabase_service, auth_service,
--               wallet_service, compat_unlock_service, ad_service}.dart
--
-- 아키텍처 문서: react/docs/HOW-IT-WORKS.md
--
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. extensions
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. public.users — 프로필 + 코인 잔액 SoT
-- ─────────────────────────────────────────────────────────────────────────────
-- auth.users 와 1:1. 가입 시 handle_new_user 트리거가 자동 생성.
-- coins 컬럼이 잔액 SoT — coins ledger (public.coins) 와 RPC 가 동기화.
-- signup_bonus_skipped: 같은 email/kakao_id 가 과거 보너스를 받은 적 있어
-- dedup 으로 보너스가 차단된 계정 표시 (클라이언트가 1회 안내 다이얼로그).

create table if not exists public.users (
  id                   uuid        primary key references auth.users(id) on delete cascade,
  kakao_user_id        text,
  nickname             text,
  profile_image_url    text,
  coins                integer     not null default 0,
  signup_bonus_skipped boolean     not null default false,
  created_at           timestamptz not null default now()
);

alter table public.users enable row level security;

drop policy if exists "users_self_read"   on public.users;
drop policy if exists "users_self_update" on public.users;

create policy "users_self_read"
  on public.users for select using (id = auth.uid());
create policy "users_self_update"
  on public.users for update using (id = auth.uid()) with check (id = auth.uid());
-- INSERT 는 handle_new_user 트리거 (SECURITY DEFINER) 전용.

-- admin_users — public.users + auth.users.email (service_role 전용).
-- email 은 auth.users 에만 존재. 컬럼 복제 없이 view 로만 노출하므로 drift 없음.
-- view 는 owner(postgres) 권한으로 auth.users 를 읽고, anon/authenticated 는 차단.
create or replace view public.admin_users as
select
  u.id,
  u.kakao_user_id,
  u.nickname,
  u.profile_image_url,
  u.coins,
  u.signup_bonus_skipped,
  u.created_at,
  au.email
from public.users u
left join auth.users au on au.id = u.id;

revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. public.coins — 코인 거래 ledger
-- ─────────────────────────────────────────────────────────────────────────────
-- kind:
--   purchase — RevenueCat 결제
--   bonus    — 가입 보너스 / 프로모션
--   refund   — 환불 보정
--   spend    — 기능 사용 차감 (amount 음수)

create table if not exists public.coins (
  id                   uuid        primary key default gen_random_uuid(),
  user_id              uuid        not null references auth.users(id) on delete cascade,
  kind                 text        not null check (kind in ('purchase','spend','bonus','refund')),
  amount               integer     not null,
  balance_after        integer     not null,
  product_id           text,
  store_transaction_id text,
  reference_id         text,
  description          text,
  metadata             jsonb,
  created_at           timestamptz not null default now()
);

create index        if not exists idx_coin_user_created on public.coins (user_id, created_at desc);
create unique index if not exists idx_coin_store_tx     on public.coins (store_transaction_id)
  where store_transaction_id is not null;

alter table public.coins enable row level security;

drop policy if exists "coins_self_read" on public.coins;
create policy "coins_self_read"
  on public.coins for select using (user_id = auth.uid());
-- INSERT/UPDATE/DELETE 정책 없음 — RPC (SECURITY DEFINER) 만.

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. public.metrics — 관상 원본 + 공유 link payload
-- ─────────────────────────────────────────────────────────────────────────────
-- 1 face capture = 1 metrics row (1 UUID = trace id, HOW-IT-WORKS §3.1).
-- body (text) = 분석 결과 payload (canonical): source·ethnicity·gender·ageGroup
-- (demographics) · metrics rawValue · faceShape · thumbnailKey · deepface* 등.
--   ↳ demographics 는 body 안에만 존재 (top-level 컬럼 아님). refine 가 body 파싱.
-- 컬럼 = 관계/소유 메타 + 쿼리 키: user_id · alias(소유자 지정 이름) · is_my_face.
--   ↳ is_my_face·alias 는 body 에 안 넣음 (toBodyJson 제외). 컬럼이 canonical.
-- SELECT 는 anon 공개 (UUID 모르면 fetch 불가하므로 link-share 모델).
-- INSERT 는 anon 도 허용 (publish 직통 UPSERT) — PII 값 RLS check 로 차단.
-- views++ 는 increment_metrics_views (SECURITY DEFINER) RPC 만.

create table if not exists public.metrics (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        references auth.users(id) on delete cascade,
  body         text        not null,
  alias        text,
  is_my_face   boolean     not null default false,
  views        integer     not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- on delete cascade 반영 (기존 DB 용 — create table if not exists 는 이미 있는
-- 테이블의 FK 를 못 바꾼다). 탈퇴 시 익명화된 고아 row 가 남지 않도록 유저
-- 삭제에 metrics 도 딸려 지운다. 탈퇴 endpoint 의 명시적 DELETE 는 R2 썸네일
-- 정리·순서 보장용으로 유지 — cascade 는 endpoint 우회 경로의 안전망.
alter table public.metrics drop constraint if exists metrics_user_id_fkey;
alter table public.metrics add constraint metrics_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

-- updated_at 인덱스: refine "90일+ 미활동 삭제" 정리 쿼리용.
create index if not exists idx_metrics_updated_at  on public.metrics (updated_at);

alter table public.metrics enable row level security;

drop policy if exists "metrics_public_read"  on public.metrics;
drop policy if exists "metrics_insert_anon"  on public.metrics;
drop policy if exists "metrics_owner_update" on public.metrics;
drop policy if exists "metrics_owner_delete" on public.metrics;
-- 옛 정책 잔재 정리
drop policy if exists "metrics_owner_insert" on public.metrics;
drop policy if exists "metrics_update_none"  on public.metrics;
drop policy if exists "metrics_delete_none"  on public.metrics;
drop policy if exists "metrics_read_anon"    on public.metrics;

create policy "metrics_public_read"
  on public.metrics for select using (true);

-- anon publish 직통 UPSERT 허용 — body 안에 PII (username/alias/birthday)
-- 의 실제 값이 들어있으면 reject. null 값 또는 key 자체가 없으면 통과.
-- landmarks 는 key 존재 자체로 차단 (재구성 위험).
-- user_id 는 null (anon) 또는 본인 한정.
--
-- `->>` (text accessor) 를 쓰는 이유: `->` 는 JSON null 값을 JSONB null 로
-- 반환해서 SQL `IS NULL` 매칭이 false. `->>` 는 키 부재 + JSON null 둘 다
-- SQL NULL 로 정규화. Dart `jsonEncode` 가 null 필드도 emit 하므로 `->`
-- 사용 시 정상 capture 의 anon insert 가 전부 reject 됨.
create policy "metrics_insert_anon"
  on public.metrics for insert with check (
        (user_id is null or user_id = auth.uid())
    and (body::jsonb ->> 'username') is null
    and (body::jsonb ->> 'alias')    is null
    and (body::jsonb ->> 'birthday') is null
    and not (body::jsonb ? 'landmarks')
  );

-- USING 은 본인 행(user_id = auth.uid) + anon 행(user_id null) 둘 다 허용.
-- 시나리오: anon 으로 분석·공유(user_id=null)한 뒤 로그인해 재공유하면 upsert 의
-- UPDATE 분기에서 authed 가 그 anon 행을 claim(소유권 이전)한다. WITH CHECK 가
-- 결과 user_id = auth.uid 를 강제하므로 claim 후 행은 본인 소유가 된다.
-- anon→anon (양쪽 null) 도 IS NOT DISTINCT 로 통과. 타 유저 소유 행은 차단.
create policy "metrics_owner_update"
  on public.metrics for update
    using (user_id is null or user_id = auth.uid())
    with check (user_id is not distinct from auth.uid());

create policy "metrics_owner_delete"
  on public.metrics for delete
    using (user_id is null or user_id = auth.uid());
-- cron · /api/erase 는 service-role 로 직접 DELETE (RLS bypass).

-- 어떤 UPDATE 든 updated_at 자동 touch. views++ RPC 의 사이드이펙트 활용.
create or replace function public.touch_metrics_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists metrics_touch on public.metrics;
create trigger metrics_touch
  before update on public.metrics
  for each row execute procedure public.touch_metrics_updated_at();

-- 원자적 views++ (Worker SSR + Flutter app 양쪽 호출). security definer 라
-- metrics_update_none/owner_update 정책을 우회.
create or replace function public.increment_metrics_views(card_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.metrics set views = views + 1 where id = card_id;
$$;

revoke all   on function public.increment_metrics_views(uuid) from public;
grant execute on function public.increment_metrics_views(uuid) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. public.unlocks — 궁합 카드 해제 ledger
-- ─────────────────────────────────────────────────────────────────────────────
-- pair_key = `${my.supabaseId}~${album.supabaseId}` (client 가 생성, 비대칭).
-- INSERT 는 unlock_compat (SECURITY DEFINER) RPC 만 — 코인 차감 + 삽입 트랜잭션.

create table if not exists public.unlocks (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  pair_key   text        not null,
  owner_body   text,      -- 결제 시점 본인(pair_key 1번째 uuid) metrics body 스냅샷.
  partner_body text,      -- 결제 시점 상대(pair_key 2번째 uuid) metrics body 스냅샷.
                          -- 두 body 를 동결해 구매한 궁합을 self-contained 로 보존.
                          -- metrics row·로컬 history 에 의존하지 않고 단독 복원/표시.
  total_score real,       -- 해제 시점 궁합 총점(0~100). admin 콘솔 정렬·필터용.
  created_at timestamptz not null default now(),
  primary key (user_id, pair_key)
);

alter table public.unlocks enable row level security;

drop policy if exists "unlocks_self_read" on public.unlocks;
create policy "unlocks_self_read"
  on public.unlocks for select using (user_id = auth.uid());

-- 사용자가 확인 리스트에서 "내 목록에서 제거" — 본인 unlock 행만 삭제 가능.
-- (INSERT 는 여전히 unlock_compat RPC 만. 코인 환불 없음 — 단순 ledger 제거.)
drop policy if exists "unlocks_self_delete" on public.unlocks;
create policy "unlocks_self_delete"
  on public.unlocks for delete using (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. public.bonus_recipients — 가입 보너스 dedup ledger (영구)
-- ─────────────────────────────────────────────────────────────────────────────
-- 같은 사용자가 계정을 지웠다 재가입하거나 다른 provider 로 갈아탈 때 보너스
-- 3 코인이 이중 발급되지 않도록 email + kakao_user_id 단위 영구 기록.
-- handle_new_user 트리거 (SECURITY DEFINER) 만 접근.

create table if not exists public.bonus_recipients (
  id            bigserial   primary key,
  email         text,
  kakao_user_id text,
  granted_at    timestamptz not null default now(),
  check (email is not null or kakao_user_id is not null)
);

create index if not exists bonus_recipients_email_idx
  on public.bonus_recipients (email) where email is not null;
create index if not exists bonus_recipients_kakao_idx
  on public.bonus_recipients (kakao_user_id) where kakao_user_id is not null;

alter table public.bonus_recipients enable row level security;

drop policy if exists "bonus_recipients_no_access" on public.bonus_recipients;
create policy "bonus_recipients_no_access"
  on public.bonus_recipients for all to authenticated, anon
  using (false) with check (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Trigger: handle_new_user (auth.users → public.users + 보너스)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_nickname        text;
  v_avatar          text;
  v_kakao_id        text;
  v_email           text := lower(new.email);
  v_already_bonused boolean;
begin
  v_nickname := coalesce(
    new.raw_user_meta_data->>'name',
    new.raw_user_meta_data->>'nickname',
    split_part(new.email, '@', 1)
  );
  v_avatar := coalesce(
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'picture'
  );
  v_kakao_id := new.raw_user_meta_data->>'provider_id';

  select exists (
    select 1 from public.bonus_recipients
    where (v_email    is not null and email         = v_email)
       or (v_kakao_id is not null and kakao_user_id = v_kakao_id)
  ) into v_already_bonused;

  if v_already_bonused then
    insert into public.users
      (id, kakao_user_id, nickname, profile_image_url, coins, signup_bonus_skipped)
    values
      (new.id, v_kakao_id, v_nickname, v_avatar, 0, true);
  else
    insert into public.users
      (id, kakao_user_id, nickname, profile_image_url, coins, signup_bonus_skipped)
    values
      (new.id, v_kakao_id, v_nickname, v_avatar, 3, false);

    insert into public.coins (user_id, kind, amount, balance_after, description)
    values (new.id, 'bonus', 3, 3, '회원가입 보너스');

    if v_email is not null or v_kakao_id is not null then
      insert into public.bonus_recipients (email, kakao_user_id)
      values (v_email, v_kakao_id);
    end if;
  end if;

  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. RPC: grant_coins — 적립 (purchase / bonus / refund)
-- ─────────────────────────────────────────────────────────────────────────────
-- 영수증 중복 방지: store_transaction_id 가 이미 ledger 에 있으면 잔액만 반환.

create or replace function public.grant_coins(
  p_amount               integer,
  p_kind                 text,
  p_product_id           text default null,
  p_store_transaction_id text default null,
  p_description          text default null
) returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_balance integer;
begin
  if v_uid is null      then raise exception 'not authenticated'; end if;
  if p_amount <= 0      then raise exception 'amount must be positive'; end if;
  if p_kind not in ('purchase','bonus','refund') then
    raise exception 'invalid kind: %', p_kind;
  end if;

  if p_store_transaction_id is not null then
    select balance_after into v_balance
      from coins
      where store_transaction_id = p_store_transaction_id and user_id = v_uid
      limit 1;
    if v_balance is not null then return v_balance; end if;
  end if;

  update users set coins = coins + p_amount
    where id = v_uid
    returning coins into v_balance;
  if v_balance is null then raise exception 'profile missing'; end if;

  insert into coins
    (user_id, kind, amount, balance_after, product_id, store_transaction_id, description)
    values (v_uid, p_kind, p_amount, v_balance, p_product_id, p_store_transaction_id, p_description);
  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7-1. RPC: admin_grant_coins — 관리자(refine) 임의 사용자 코인 지급
-- ─────────────────────────────────────────────────────────────────────────────
-- service_role 전용. auth.uid() 가 아니라 p_user_id 대상에 직접 적립 + bonus ledger.
-- 반환: 대상 사용자의 새 잔액.
create or replace function public.admin_grant_coins(
  p_user_id     uuid,
  p_amount      integer,
  p_description text default null
) returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_balance integer;
begin
  if p_amount <= 0 then raise exception 'amount must be positive'; end if;

  update users set coins = coins + p_amount
    where id = p_user_id
    returning coins into v_balance;
  if v_balance is null then raise exception 'user not found: %', p_user_id; end if;

  insert into coins (user_id, kind, amount, balance_after, description)
    values (p_user_id, 'bonus', p_amount, v_balance, coalesce(p_description, 'admin grant'));
  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RPC: spend_coins — 차감 (범용)
-- ─────────────────────────────────────────────────────────────────────────────
-- 반환: 성공 시 새 잔액, 잔액 부족 시 -1.

create or replace function public.spend_coins(
  p_amount       integer,
  p_reference_id text default null,
  p_description  text default null
) returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_balance integer;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_amount <= 0 then raise exception 'amount must be positive'; end if;

  update users set coins = coins - p_amount
    where id = v_uid and coins >= p_amount
    returning coins into v_balance;
  if v_balance is null then return -1; end if;

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -p_amount, v_balance, p_reference_id, p_description);
  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. RPC: unlock_compat — 궁합 카드 해제 (1 코인 차감 + unlocks insert)
-- ─────────────────────────────────────────────────────────────────────────────
-- 이미 해제됐으면 idempotent — 잔액만 반환.
-- 잔액 부족이면 -1.

drop function if exists public.unlock_compat(text);
drop function if exists public.unlock_compat(text, real);

create or replace function public.unlock_compat(
  p_pair_key     text,
  p_total_score  real default null,
  p_owner_body   text default null,
  p_partner_body text default null
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
  if p_pair_key is null or length(p_pair_key) = 0 then
    raise exception 'pair_key required';
  end if;

  select exists(
    select 1 from unlocks
    where user_id = v_uid and pair_key = p_pair_key
  ) into v_already;

  if v_already then
    select coins into v_balance from users where id = v_uid;
    return v_balance;
  end if;

  update users set coins = coins - 1
    where id = v_uid and coins >= 1
    returning coins into v_balance;
  if v_balance is null then return -1; end if;

  -- 결제 확정 → 본인·상대 두 body 를 클라이언트가 넘긴 그대로 동결 저장.
  -- metrics row 존재 여부에 의존하지 않아 (업로드 누락·삭제·만료와 무관)
  -- 구매한 궁합이 self-contained 로 영구 보존된다.
  insert into unlocks (user_id, pair_key, owner_body, partner_body, total_score)
    values (v_uid, p_pair_key, p_owner_body, p_partner_body, p_total_score);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance, p_pair_key, 'compat-unlock');

  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RPC grants
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function public.grant_coins(integer, text, text, text, text) from public, anon;
revoke execute on function public.spend_coins(integer, text, text)              from public, anon;
revoke execute on function public.unlock_compat(text, real, text, text)          from public, anon;
revoke execute on function public.admin_grant_coins(uuid, integer, text)         from public, anon, authenticated;

grant  execute on function public.grant_coins(integer, text, text, text, text) to authenticated;
grant  execute on function public.spend_coins(integer, text, text)              to authenticated;
grant  execute on function public.unlock_compat(text, real, text, text)          to authenticated;
grant  execute on function public.admin_grant_coins(uuid, integer, text)         to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. ad_rewards — AdMob 일일 무료 코인 (3편 시청 = 1 코인)
-- ─────────────────────────────────────────────────────────────────────────────
-- 정책:
--   - day = (now() AT TIME ZONE 'Asia/Seoul')::date — KST 자정 기준 reset
--   - 하루 최대 3편 시청 → 자동 +1 코인 (kind=bonus), 그날은 더 받을 수 없음
--   - 진행도 / claim 여부는 (user_id, day) row 1건에 누적
--   - Flutter `PurchaseSheet` "오늘의 무료 코인" 카드가 상태 표시 + 진입

create table if not exists public.ad_rewards (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  day        date        not null default ((now() at time zone 'Asia/Seoul')::date),
  views      integer     not null default 0,
  claimed    boolean     not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ad_rewards enable row level security;

drop policy if exists "ad_rewards_self_read" on public.ad_rewards;
create policy "ad_rewards_self_read"
  on public.ad_rewards for select using (user_id = auth.uid());

-- write 는 RPC (security definer) 만. anon/authenticated 직접 write 없음.

-- RPC: ad_reward_status — 오늘의 진행도 read
create or replace function public.ad_reward_status()
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid    := auth.uid();
  v_day     date    := (now() at time zone 'Asia/Seoul')::date;
  v_views   integer := 0;
  v_claimed boolean := false;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select views, claimed into v_views, v_claimed
    from ad_rewards
    where user_id = v_uid and day = v_day;
  return json_build_object(
    'progress',      coalesce(v_views, 0),
    'max',           3,
    'claimed_today', coalesce(v_claimed, false),
    'balance_after', null
  );
end; $$;

-- RPC: ad_reward_record_view — 광고 1편 시청 기록 + 3편 도달 시 자동 +1 코인
-- 반환: { progress, max, claimed_today, balance_after }
--   balance_after — 이번 호출로 코인 지급된 경우 새 잔액, 아니면 null
create or replace function public.ad_reward_record_view()
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_day     date := (now() at time zone 'Asia/Seoul')::date;
  v_views   integer;
  v_claimed boolean;
  v_balance integer;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  insert into ad_rewards (user_id, day, views, claimed, updated_at)
    values (v_uid, v_day, 1, false, now())
    on conflict (user_id, day) do update
      set views = case
            when ad_rewards.claimed then ad_rewards.views
            when ad_rewards.views >= 3 then ad_rewards.views
            else ad_rewards.views + 1
          end,
          updated_at = now()
    returning views, claimed into v_views, v_claimed;

  if v_views >= 3 and not v_claimed then
    -- 자동 +1 코인 grant. grant_coins 가 SECURITY DEFINER 이지만
    -- auth.uid() 는 동일 JWT 컨텍스트 — 정상 동작.
    select grant_coins(1, 'bonus', null, null, '광고 3편 무료 보상')
      into v_balance;
    update ad_rewards
      set claimed = true, updated_at = now()
      where user_id = v_uid and day = v_day;
    v_claimed := true;
  end if;

  return json_build_object(
    'progress',      v_views,
    'max',           3,
    'claimed_today', v_claimed,
    'balance_after', v_balance
  );
end; $$;

revoke execute on function public.ad_reward_status()      from public, anon;
revoke execute on function public.ad_reward_record_view() from public, anon;
grant  execute on function public.ad_reward_status()      to authenticated;
grant  execute on function public.ad_reward_record_view() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-0. public.ad_videos — custom video 광고 (refine 등록, §11-1 grant 보다 앞)
-- ─────────────────────────────────────────────────────────────────────────────
-- 데일리 무료코인 "광고 3편" 중 1편을 내 브랜드 영상으로 강제 노출(나머지 2편은
-- AdMob). 활성 영상이 없으면 3편 전부 AdMob. refine 이 service_role 로 직접 CRUD,
-- Flutter 가 active=true 행을 읽어 재생한다. 시청은 AdMob 과 동일하게
-- ad_reward_record_view 로 카운트되므로 per-video reward_coins·dedup 불필요.
create table if not exists public.ad_videos (
  id            uuid        primary key default gen_random_uuid(),
  title         text        not null,
  storage_path  text        not null,   -- storage 'ad_videos' 버킷 key
  duration_sec  integer,                 -- 브라우저 probe 결과 (null 가능)
  active        boolean     not null default true,
  created_at    timestamptz not null default now()
);

alter table public.ad_videos enable row level security;

drop policy if exists "ad_videos_active_read" on public.ad_videos;
-- 활성 영상은 누구나 읽기 (Flutter 재생). 쓰기는 refine(service_role, RLS bypass)만.
create policy "ad_videos_active_read"
  on public.ad_videos for select using (active = true);

create index if not exists ad_videos_active_created_idx
  on public.ad_videos (created_at desc) where active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-0b. public.ad_images — 외부 광고주 배너 (홈 탭 타이틀 위, rotation 노출)
-- ─────────────────────────────────────────────────────────────────────────────
-- 외부 광고주에게서 받은 배너. 홈 탭 "관상은 과학이다." 타이틀 위 영역에서
-- 활성 배너들을 rotation(자동 순환)으로 노출하고, 탭하면 link_url 로 이동(외부
-- 브라우저). 수익은 오프라인 정액 계약("배너만 얼마")이라 impression/click 측정은
-- 하지 않는다(측정 컬럼 없음). 활성 배너가 없으면 앱이 정적 home.png 로 fallback.
-- refine 이 service_role 로 직접 CRUD, Flutter 가 active=true 를 sort_order 순 rotation.
create table if not exists public.ad_images (
  id            uuid        primary key default gen_random_uuid(),
  title         text        not null,
  storage_path  text        not null,   -- storage 'ad_images' 버킷 key
  link_url      text,                    -- 탭 시 이동 URL (null 이면 비탭 배너)
  active        boolean     not null default true,
  sort_order    integer     not null default 0,  -- 작을수록 우선
  created_at    timestamptz not null default now()
);

alter table public.ad_images enable row level security;

drop policy if exists "ad_images_active_read" on public.ad_images;
create policy "ad_images_active_read"
  on public.ad_images for select using (active = true);

create index if not exists ad_images_active_sort_idx
  on public.ad_images (sort_order, created_at desc) where active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-2. public.teams — 교감도 그룹 (원격 경로, P3)
-- ─────────────────────────────────────────────────────────────────────────────
-- 그룹 1개 = 1 row. 멤버는 public.team_members (metrics_id 참조).
-- lazy sync: 그룹은 로컬(Hive) 우선 생성되고, [카톡 초대]·[마감] 등 원격 행동
-- 시점에만 서버로 push 된다 (현장 경로의 무마찰 유지).
-- title·closed_at 은 owner 관리. matrix_payload(jsonb) = 마감 시 앱이 계산한
-- 밴드 매트릭스 (이름+밴드만, 점수·landmark 없음 — react 는 그리기만).
-- 읽기 = groupId(UUID) 아는 사람 (link-share 모델, metrics 와 동일). 쓰기 = owner
-- (원격 그룹은 안정적 소유 식별이 필요해 anon 소유 불가 — push 시 로그인 게이트).
create table if not exists public.teams (
  id             uuid        primary key default gen_random_uuid(),
  owner_id       uuid        references auth.users(id) on delete set null,
  title          text        not null,
  closed_at      timestamptz,
  matrix_payload jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists idx_teams_owner on public.teams (owner_id, updated_at desc);

alter table public.teams enable row level security;

drop policy if exists "teams_public_read" on public.teams;
drop policy if exists "teams_owner_insert" on public.teams;
drop policy if exists "teams_owner_update" on public.teams;
drop policy if exists "teams_owner_delete" on public.teams;

-- 읽기: UUID 모르면 접근 불가 (link-share). 초대장·쇼케이스가 anon 으로 읽는다.
create policy "teams_public_read"
  on public.teams for select using (true);
-- 생성·수정·삭제: owner 본인(auth 필요)만.
create policy "teams_owner_insert"
  on public.teams for insert with check (owner_id = auth.uid());
create policy "teams_owner_update"
  on public.teams for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "teams_owner_delete"
  on public.teams for delete using (owner_id = auth.uid());

-- 어떤 UPDATE 든 updated_at 자동 touch (pull-to-refresh 폴링 변경 감지용).
create or replace function public.touch_teams_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;

drop trigger if exists teams_touch on public.teams;
create trigger teams_touch
  before update on public.teams
  for each row execute procedure public.touch_teams_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-3. public.team_members — 그룹 멤버 (metrics_id 참조)
-- ─────────────────────────────────────────────────────────────────────────────
-- 멤버 = (team_id, metrics_id). name = 그룹 안 표시 이름(방장이 깐 이름 또는
-- 본인 alias). 대기(미등록) 슬롯은 metrics_id null + name 만, 등록되면 채운다.
-- 한 그룹에 같은 metrics_id 1회 (등록 중복 차단, 부분 unique).
create table if not exists public.team_members (
  id         uuid        primary key default gen_random_uuid(),
  team_id    uuid        not null references public.teams(id) on delete cascade,
  metrics_id uuid        references public.metrics(id) on delete set null,
  name       text        not null,
  is_owner   boolean     not null default false,
  joined_at  timestamptz not null default now()
);

create index        if not exists idx_team_members_team    on public.team_members (team_id);
-- (team_id, metrics_id) unique — 등록 중복 차단 + upsert onConflict 추론 대상.
-- 비부분(non-partial) 이라야 ON CONFLICT 가 추론한다. metrics_id NULL 행(대기·
-- metrics 삭제로 set null)은 PG 기본 NULL-distinct 라 여러 개 허용돼 무해.
create unique index if not exists idx_team_members_metrics on public.team_members (team_id, metrics_id);
-- (team_id, name) unique — 그룹 안 이름이 슬롯 키. 합류자가 방장이 깐 대기
-- 이름("까불이")으로 upsert 하면 그 대기 행이 채워진다(claim by name). 등록·대기
-- 모두 한 이름당 한 행.
create unique index if not exists idx_team_members_name on public.team_members (team_id, name);

alter table public.team_members enable row level security;

drop policy if exists "team_members_public_read" on public.team_members;
drop policy if exists "team_members_insert"      on public.team_members;
drop policy if exists "team_members_update"      on public.team_members;
drop policy if exists "team_members_claim_slot"  on public.team_members;
drop policy if exists "team_members_delete"      on public.team_members;

-- 읽기: 그룹과 동일 link-share (team UUID 아는 사람).
create policy "team_members_public_read"
  on public.team_members for select using (true);

-- 쓰기(insert): owner 가 멤버를 깔거나, 합류자가 자기 자신(metrics 소유)을 넣는다.
create policy "team_members_insert"
  on public.team_members for insert with check (
       exists (select 1 from public.teams t   where t.id = team_id    and t.owner_id  = auth.uid())
    or exists (select 1 from public.metrics m where m.id = metrics_id and m.user_id   = auth.uid())
  );

-- 수정: owner 만 (명단 관리·슬롯 채움).
create policy "team_members_update"
  on public.team_members for update using (
    exists (select 1 from public.teams t where t.id = team_id and t.owner_id = auth.uid())
  );

-- 슬롯 claim: 합류자가 **대기 슬롯(metrics_id null)** 을 자기 metrics 로 채운다.
-- USING = 빈 슬롯만(기존 점유 행은 못 가로챔), WITH CHECK = 새 metrics_id 가
-- 본인 소유. team_members_update(owner) 와 OR 로 합쳐져, 합류자도 빈 이름 슬롯에
-- 한해 채울 수 있다.
create policy "team_members_claim_slot"
  on public.team_members for update
    using (metrics_id is null)
    with check (
      exists (select 1 from public.metrics m where m.id = metrics_id and m.user_id = auth.uid())
    );

-- 삭제: owner(멤버 제거) 또는 본인(그룹 나가기).
create policy "team_members_delete"
  on public.team_members for delete using (
       exists (select 1 from public.teams t   where t.id = team_id    and t.owner_id  = auth.uid())
    or exists (select 1 from public.metrics m where m.id = metrics_id and m.user_id   = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-1. 테이블/시퀀스 GRANT — drop schema 후에도 self-contained
-- ─────────────────────────────────────────────────────────────────────────────
-- `drop schema public cascade` 는 Supabase 가 깔아둔 anon/authenticated 기본
-- 테이블 권한(default ACL)까지 지운다. 그 상태로 baseline 만 RUN 하면 테이블에
-- GRANT 가 없어 로그인 직후 `42501 permission denied for table users` 가 난다.
-- 따라서 여기서 테이블·시퀀스 권한을 명시 부여해 reset 후 self-contained 하게
-- 만든다. row 접근은 각 테이블 RLS 정책이 통제하므로, GRANT 는 롤이 테이블에
-- "닿을" 수만 있게 한다. (함수 권한은 위 RPC grant/revoke 가 SoT — 여기서
-- routines 는 건드리지 않아 grant_coins 등의 revoke 가 유지된다.)
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on all tables    in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;

-- ⚠️ 위 `grant all on all tables` 는 뷰까지 포함한다. admin_users 뷰는
-- owner(postgres) 권한으로 auth.users.email 을 읽으므로 anon/authenticated 에
-- 새면 이메일 유출 — §1 의 revoke 를 일괄 grant 뒤에서 다시 적용해 좁힌다.
revoke all on public.admin_users from anon, authenticated, public;
grant select on public.admin_users to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. 광고 시스템 현황 메모 (모든 오브젝트 ad_* 네이밍)
-- ─────────────────────────────────────────────────────────────────────────────
-- • ad_videos (§11-0)  → custom video 광고. 무료코인 3편 중 1편으로 노출. refine CRUD.
-- • ad_images (§11-0b) → 홈 배너 이미지. 탭 시 link_url 이동. refine CRUD.
-- • 무료코인 카운터     → ad_rewards 테이블(§11) + ad_reward_status /
--   ad_reward_record_view RPC(§11). AdMob·custom video 시청 모두 record_view 로 카운트,
--   3편 누적 시 1코인. (과거 ad_views·claim_ad_reward 는 폐기 — 이 카운터로 흡수.)
-- • Flutter: free_coin_service.dart (카운터) · ad_service.dart (custom video 재생).

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. Storage buckets — 'ad_videos' · 'ad_images' (대시보드 수동 생성)
-- ─────────────────────────────────────────────────────────────────────────────
-- Supabase 대시보드 → Storage → Create bucket (둘 다 public: true)
--   • ad_videos : custom video mp4 (Flutter 가 public URL 로 재생)
--   • ad_images : 홈 배너 이미지 (Flutter 가 public URL 로 표시)
-- buckets 메타테이블 직접 INSERT 도 가능하나 대시보드가 안전.

-- ============================================================================
-- 검증 스모크 (선택)
-- ============================================================================
-- do $$
-- declare sid uuid := gen_random_uuid(); v integer;
-- begin
--   -- metrics: insert (anon 가능) → views++ RPC → updated_at 자동 변화 → 삭제
--   insert into public.metrics (id, body) values (sid, '{}');
--   perform public.increment_metrics_views(sid);
--   select views into v from public.metrics where id = sid;
--   raise notice 'views after rpc = %', v;  -- 1
--   delete from public.metrics where id = sid;
-- end$$;

-- ============================================================================
-- DEV ONLY — reset (⚠️ 파괴적 · 전체 초기화)
-- ============================================================================
-- ⚠️ 사용법: 평소 주석 유지. reset 시 "이 블록만" 선택해 주석 해제 후 단독 RUN
--    → 그 다음 본 0001_baseline.sql 을 통째로 다시 RUN.
--    ❌ 이 블록을 해제한 채 파일 전체를 한 번에 RUN 금지 — 맨 끝에서 방금 만든
--       객체를 전부 drop 해버린다.
--    ✅ reset·baseline 모두 Supabase SQL Editor(=postgres 롤)에서 실행할 것.
--       (default privileges 가 "객체를 만든 롤" 기준이라 롤이 다르면 권한 누락)
--
-- 메커니즘: enumerated drop 과 달리 객체가 늘어도 안 썩음 — public 을 스키마째
-- 비운다. on_auth_user_created 트리거는 public.handle_new_user() drop 시 cascade
-- 로 함께 제거된다. drop schema 가 default privileges 도 지우므로 Supabase 기본
-- 권한을 복원한다.
--
-- drop schema public 은 public 만 지우므로 가입 계정(auth.users)까지 비워 진짜
-- clean slate 로 만든다. baseline 재실행 후 사용자는 재가입부터 시작 —
-- handle_new_user 가 profile + 가입 보너스 3 코인 을 재생성.
--
-- drop schema public cascade;
-- create schema public;
-- delete from auth.users;   -- auth.identities/sessions 로 cascade. storage 객체가 있으면 먼저 비울 것.
--
-- 그다음 이 파일 전체 RUN. 테이블/시퀀스 GRANT 는 §11-1 이 재부여하므로 별도
-- 수동 grant 불필요. (빠뜨리면 로그인 직후 `42501 permission denied for table`.)

-- ============================================================================
-- 관리자(refine) 로그인 계정 생성
-- ============================================================================
-- refine admin 은 별도 role 검사 없이 "인증된 Supabase 계정이면" 로그인 가능하고,
-- 데이터 접근은 env 의 service_role 키로 한다 (refine/src/providers/supabase-client.ts).
-- 따라서 "관리자 계정" = refine 에 로그인할 email/password 계정 1개만 만들면 된다.
-- 관리 권한의 실체는 refine env 의 VITE_SUPABASE_SERVICE_KEY 이지 DB role 이 아니다.
--
-- reset + baseline RUN 후:
--   Supabase 대시보드 → Authentication → Users → Add user
--     · Email / Password 입력 + "Auto Confirm User" 체크 (이메일 인증 생략)
--   → on_auth_user_created 트리거가 public.users profile + 3 코인 을 자동 생성
--   → 이 email/password 로 refine 로그인.
