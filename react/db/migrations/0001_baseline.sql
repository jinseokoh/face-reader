-- ============================================================================
-- 0001 — facely Supabase clean-slate baseline
-- ============================================================================
--
-- 이 한 파일이 모든 public schema 의 **현재 운영 상태** 를 재현한다. 시스템
-- 이전·재해복구·새 환경 부트스트랩 시 빈 Supabase 프로젝트의 SQL Editor 에
-- 통째로 붙여 넣고 RUN. extension 외엔 모두 idempotent (DROP IF EXISTS + CREATE
-- OR REPLACE).
--
-- 포함:
--   • tables    : users · coins · metrics · unlocks · bonus_recipients
--                 (+ ads / ad_views — TODO 블록 참조)
--   • triggers  : handle_new_user (auth.users → public.users + 보너스 3 코인)
--                 touch_metrics_updated_at (views++ 시 updated_at 자동 갱신)
--   • rpcs      : grant_coins / spend_coins / unlock_compat
--                 increment_metrics_views
--                 (+ claim_ad_reward — TODO)
--   • rls       : 각 테이블 별 정책
--   • indexes   : 운영 query 패턴 기반
--   • grants    : RPC 권한
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
-- body (text) 안에 schema (HOW-IT-WORKS §5.2) — thumbnailKey,
-- deepface*, rawValue, demographic 카테고리 등.
-- SELECT 는 anon 공개 (UUID 모르면 fetch 불가하므로 link-share 모델).
-- INSERT 는 anon 도 허용 (publish 직통 UPSERT) — PII 값 RLS check 로 차단.
-- views++ 는 increment_metrics_views (SECURITY DEFINER) RPC 만.

create table if not exists public.metrics (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        references auth.users(id) on delete set null,
  body         text        not null,
  source       text        not null check (source in ('camera','album')),
  ethnicity    text        not null,
  gender       text        not null,
  age_group    text        not null,
  alias        text,
  expires_at   timestamptz not null,
  views        integer     not null default 0,
  updated_at   timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create index if not exists idx_metrics_expires_at  on public.metrics (expires_at);
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
create policy "metrics_insert_anon"
  on public.metrics for insert with check (
        (user_id is null or user_id = auth.uid())
    and (body::jsonb -> 'username') is null
    and (body::jsonb -> 'alias')    is null
    and (body::jsonb -> 'birthday') is null
    and not (body::jsonb ? 'landmarks')
  );

create policy "metrics_owner_update"
  on public.metrics for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "metrics_owner_delete"
  on public.metrics for delete using (user_id = auth.uid());
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
-- pair_key = `${my.supabaseId}::${album.supabaseId}` (client 가 생성, 비대칭).
-- INSERT 는 unlock_compat (SECURITY DEFINER) RPC 만 — 코인 차감 + 삽입 트랜잭션.

create table if not exists public.unlocks (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  pair_key   text        not null,
  created_at timestamptz not null default now(),
  primary key (user_id, pair_key)
);

alter table public.unlocks enable row level security;

drop policy if exists "unlocks_self_read" on public.unlocks;
create policy "unlocks_self_read"
  on public.unlocks for select using (user_id = auth.uid());

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

create or replace function public.unlock_compat(p_pair_key text)
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

  insert into unlocks (user_id, pair_key) values (v_uid, p_pair_key);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance, p_pair_key, 'compat-unlock');

  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RPC grants
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function public.grant_coins(integer, text, text, text, text) from public, anon;
revoke execute on function public.spend_coins(integer, text, text)              from public, anon;
revoke execute on function public.unlock_compat(text)                            from public, anon;

grant  execute on function public.grant_coins(integer, text, text, text, text) to authenticated;
grant  execute on function public.spend_coins(integer, text, text)              to authenticated;
grant  execute on function public.unlock_compat(text)                            to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. TODO — ads / ad_views / claim_ad_reward
-- ─────────────────────────────────────────────────────────────────────────────
-- 보상형 광고 시스템. Flutter `lib/data/services/ad_service.dart` 가 참조하나
-- 본 baseline 작성 시점엔 운영 schema dump 가 없어 정확한 DDL 미반영.
--
-- 코드 시그니처에서 추정되는 형상:
--
--   create table public.ads (
--     id            uuid primary key default gen_random_uuid(),
--     title         text not null,
--     storage_path  text not null,        -- supabase storage 'ads' bucket 의 key
--     duration_sec  integer,
--     reward_coins  integer not null,
--     active        boolean not null default true,
--     created_at    timestamptz not null default now()
--   );
--
--   create table public.ad_views (
--     id         uuid primary key default gen_random_uuid(),
--     user_id    uuid not null references auth.users(id) on delete cascade,
--     ad_id      uuid not null references public.ads(id) on delete cascade,
--     created_at timestamptz not null default now()
--   );
--
--   -- function claim_ad_reward(p_ad_id uuid) returns integer
--   --   - 24h 내 5건 daily cap
--   --   - 24h 내 같은 ad 중복 차단
--   --   - ad active 확인 → reward_coins 만큼 grant + ad_views insert
--
-- 실제 DDL 은 Supabase 대시보드 → Database → Tables 에서 export 하여 본 블록에
-- 직접 채울 것. 또는:
--
--   pg_dump --schema public --table ads --table ad_views \
--           --function claim_ad_reward "$DB_URL" >> 0001_baseline.sql

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Storage bucket — 'ads' (수동 생성)
-- ─────────────────────────────────────────────────────────────────────────────
-- Supabase 대시보드 → Storage → Create bucket
--   name: ads
--   public: true (Flutter 가 public URL 로 비디오 fetch)
-- 본 SQL 로는 buckets 메타테이블 직접 INSERT 가능하지만 dashboard 가 더 안전.

-- ============================================================================
-- 검증 스모크 (선택)
-- ============================================================================
-- do $$
-- declare sid uuid := gen_random_uuid(); v integer;
-- begin
--   -- metrics: insert (anon 가능) → views++ RPC → updated_at 자동 변화 → 삭제
--   insert into public.metrics (id, body, source, ethnicity, gender, age_group, expires_at)
--   values (sid, '{}', 'album', 'eastAsian', 'male', '20s', now() + interval '90 days');
--   perform public.increment_metrics_views(sid);
--   select views into v from public.metrics where id = sid;
--   raise notice 'views after rpc = %', v;  -- 1
--   delete from public.metrics where id = sid;
-- end$$;

-- ============================================================================
-- DEV ONLY — reset (전체 데이터 날아감)
-- ============================================================================
-- drop trigger if exists on_auth_user_created on auth.users;
-- drop trigger if exists metrics_touch on public.metrics;
-- drop function if exists public.handle_new_user();
-- drop function if exists public.touch_metrics_updated_at();
-- drop function if exists public.increment_metrics_views(uuid);
-- drop function if exists public.grant_coins(integer, text, text, text, text);
-- drop function if exists public.spend_coins(integer, text, text);
-- drop function if exists public.unlock_compat(text);
-- drop table    if exists public.bonus_recipients cascade;
-- drop table    if exists public.unlocks          cascade;
-- drop table    if exists public.metrics          cascade;
-- drop table    if exists public.coins            cascade;
-- drop table    if exists public.users            cascade;
-- -- 그 후 본 0001_baseline.sql 통째로 다시 RUN.
