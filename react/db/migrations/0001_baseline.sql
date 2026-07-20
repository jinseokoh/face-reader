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
--                 · teams · team_members (Chemistry Battle 로비, §11-2/11-3/11-4)
--                 · team_matches · team_messages (매칭·채팅, §11-6)
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
create extension if not exists "pg_net";    -- 매칭 푸시 webhook (net.http_post)

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
-- 4. public.unlocks — 궁합 풀이 해제 ledger (구매자 + 무방향 쌍)
-- ─────────────────────────────────────────────────────────────────────────────
-- 규칙 하나: "1코인 = 두 사람의 궁합 풀이, 구매자에게 영구" — 내 쌍이든
-- 케미 매칭의 제3자 쌍이든 동일. 키 = (구매자, a_id<b_id 정규화 쌍 metrics id).
-- 내 궁합은 a/b 중 하나가 내 my-face id 인 특수경우일 뿐 (id 는 로그인 유저
-- 기준 영구 고정이라 재촬영에도 unlock 유지). FK 없음 — 스냅샷은 metrics
-- 삭제를 견딘다. INSERT 는 unlock_compat RPC 만 — 코인 차감 + 삽입 트랜잭션.

create table if not exists public.unlocks (
  user_id     uuid        not null references auth.users(id) on delete cascade,
  a_id        uuid        not null,
  b_id        uuid        not null,
  a_body      text,      -- 결제 시점 두 body 스냅샷 — 구매한 궁합을
  b_body      text,      -- self-contained 로 보존 (방 purge·metrics 삭제 무관).
  a_alias     text,      -- 결제 시점 두 이름 스냅샷 — 앱 fallback + admin 표시.
  b_alias     text,      -- (body 스냅샷은 PII 정책상 alias 를 담지 않음.
                         --  unlocks 는 RLS self-read 라 컬럼 저장이 안전.)
  total_score real,      -- 해제 시점 궁합 총점(0~100). admin 콘솔 정렬·필터용.
  created_at  timestamptz not null default now(),
  primary key (user_id, a_id, b_id),
  check (a_id < b_id)
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
drop function if exists public.unlock_compat(text, real, text, text);
drop function if exists public.unlock_compat(uuid, real, text, text, text, text);

-- 쌍 (p_a_id < p_b_id 정규화, 클라이언트가 body/alias 를 같은 순서로 정렬해
-- 전달) 의 풀이 해제 — 내 쌍이든 매칭 제3자 쌍이든 동일 규칙.
create or replace function public.unlock_compat(
  p_a_id        uuid,
  p_b_id        uuid,
  p_total_score real default null,
  p_a_body      text default null,
  p_b_body      text default null,
  p_a_alias     text default null,
  p_b_alias     text default null
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
  if p_a_id is null or p_b_id is null then raise exception 'pair ids required'; end if;
  if p_a_id >= p_b_id then raise exception 'pair not normalized (a_id < b_id)'; end if;

  select exists(
    select 1 from unlocks
    where user_id = v_uid and a_id = p_a_id and b_id = p_b_id
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
  -- metrics row 존재 여부에 의존하지 않아 (업로드 누락·삭제·만료·방 purge 와
  -- 무관) 구매한 궁합이 self-contained 로 영구 보존된다.
  insert into unlocks (user_id, a_id, b_id, a_body, b_body,
                       a_alias, b_alias, total_score)
    values (v_uid, p_a_id, p_b_id, p_a_body, p_b_body,
            p_a_alias, p_b_alias, p_total_score);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance,
            p_a_id::text || '~' || p_b_id::text, 'compat-unlock');

  return v_balance;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RPC grants
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function public.grant_coins(integer, text, text, text, text) from public, anon;
revoke execute on function public.spend_coins(integer, text, text)              from public, anon;
revoke execute on function public.unlock_compat(uuid, uuid, real, text, text, text, text) from public, anon;
revoke execute on function public.admin_grant_coins(uuid, integer, text)         from public, anon, authenticated;

grant  execute on function public.grant_coins(integer, text, text, text, text) to authenticated;
grant  execute on function public.spend_coins(integer, text, text)              to authenticated;
grant  execute on function public.unlock_compat(uuid, uuid, real, text, text, text, text) to authenticated;
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
-- 11-2. public.teams — Chemistry Battle 방 (게임 로비, 서버 우선)
-- ─────────────────────────────────────────────────────────────────────────────
-- 방은 생성 즉시 서버에 존재한다 (로컬 우선/lazy sync 폐기). 참가자는 이름
-- 선등록 없이 join_team RPC 로 셀프 조인. 시작 조건은 정원 충족 하나뿐 —
-- 모이면 시작, 48h 안에 안 모이면 expired (cron).
--
-- chemistry_snapshot = 시작 트랜잭션이 동결한 {user_id: metrics body} — 엔진
-- 입력. 시작 후 재촬영·metrics 변경이 결과에 영향을 못 주게 하는 치팅 방어.
-- result_payload = 클라이언트가 snapshot 으로 계산해 1회 기록하는 스코어보드
-- (players/pairs/best — 점수는 best.score 만).
-- password 는 column grant 로 클라이언트 SELECT 차단 (§11-4) — 비교는
-- join_team 내부에서만. 상태 전이는 RPC 전용 (직접 UPDATE 는 title 만).
-- 공개/비밀 개념은 password 단일 소스 — 모든 모집 방이 목록에 노출되고,
-- password 있는 방만 조인 시 PIN 을 요구한다. is_private 는 클라이언트
-- 표시용 파생 컬럼(password 봉인 유지, 어긋날 수 없음).
create table if not exists public.teams (
  id                 uuid        primary key default gen_random_uuid(),
  owner_id           uuid        references auth.users(id) on delete set null,
  title              text        not null,
  password           text,
  is_private         boolean     generated always as (password is not null) stored,
  room_kind          text        not null default 'all'
                                 check (room_kind in ('all', 'match')),
  thumb_open         boolean     not null default false,
  max_players        int         not null default 8
                                 check (max_players in (6, 8, 10, 12)),
  age_min            int         not null check (age_min >= 20),
  age_max            int         not null check (age_max >= age_min and age_max <= age_min + 20),
  status             text        not null default 'recruiting'
                                 check (status in ('recruiting', 'revealing', 'completed', 'expired')),
  started_at         timestamptz,
  closed_at          timestamptz,
  chemistry_snapshot jsonb,
  result_payload     jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_teams_owner on public.teams (owner_id, updated_at desc);
-- 목록 조회 (public_teams view — 모집 중 전 방).
create index if not exists idx_teams_recruiting
  on public.teams (created_at desc) where status = 'recruiting';

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

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-3. public.team_members — 매칭 참가자 (전원 로그인 셀프 조인)
-- ─────────────────────────────────────────────────────────────────────────────
-- 참가자 = 로그인 사용자. 이름·얼굴 컬럼 없음 — 표시 이름은 users.nickname,
-- 얼굴은 조회 시 user_id → 현재 my-face live resolve (시작 후엔 teams.
-- chemistry_snapshot 이 입력). 계정 삭제 = FK cascade 로 참가 행 소멸 →
-- 슬롯 자동 반환. 쓰기는 전부 RPC (join_team / leave_team) — 직접
-- insert/update/delete 정책 없음 (RLS deny by default).
create table if not exists public.team_members (
  id        uuid        primary key default gen_random_uuid(),
  team_id   uuid        not null references public.teams(id) on delete cascade,
  user_id   uuid        not null references auth.users(id) on delete cascade,
  slot_no   int         not null,
  gender    text        not null check (gender in ('male', 'female')),
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-6. public.team_matches / public.team_messages — 매칭 성사·인앱 채팅
-- ─────────────────────────────────────────────────────────────────────────────
-- best 쌍의 채팅 개설 상호 동의. 방당 1행, 행 자체는 submit_team_result
-- 가 생성한다 (best 는 payload 확정 이후에만 알 수 있다). consent: null=무응답,
-- true=수락, false=거절 — 거절은 즉시 종결(재응답 불가). 쓰기는 전부 RPC
-- (submit_team_result / respond_match) — 직접 insert/update/delete 정책 없음.
create table if not exists public.team_matches (
  team_id    uuid primary key references public.teams(id) on delete cascade,
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  a_consent  boolean,
  b_consent  boolean,
  opened_at  timestamptz,           -- 둘 다 true 가 된 시각 = 채팅 개설
  check (user_a <> user_b)
);

alter table public.team_matches enable row level security;

drop policy if exists "team_matches_pair_read" on public.team_matches;

-- 읽기: 해당 쌍 본인만 — 타 참가자에게 동의 현황 비노출.
create policy "team_matches_pair_read"
  on public.team_matches for select
  using (auth.uid() = user_a or auth.uid() = user_b);

-- 인앱 1:1 채팅 — 성사된 쌍 전용. 방 삭제(30일 purge)와 함께 cascade.
create table if not exists public.team_messages (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.team_matches(team_id) on delete cascade,
  sender_id  uuid not null references auth.users(id) on delete cascade,
  body       text not null check (char_length(body) <= 500),
  created_at timestamptz not null default now()
);

alter table public.team_messages enable row level security;

drop policy if exists "team_messages_pair_read"   on public.team_messages;
drop policy if exists "team_messages_pair_insert" on public.team_messages;

-- 읽기/쓰기 모두 opened_at 이 찍힌(채팅 개설) 매치의 쌍 본인만.
-- insert 는 sender_id 위조 방지로 auth.uid() 강제.
create policy "team_messages_pair_read"
  on public.team_messages for select
  using (exists (
    select 1 from public.team_matches m
     where m.team_id = team_messages.team_id
       and m.opened_at is not null
       and (auth.uid() = m.user_a or auth.uid() = m.user_b)
  ));
create policy "team_messages_pair_insert"
  on public.team_messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.team_matches m
       where m.team_id = team_messages.team_id
         and m.opened_at is not null
         and (auth.uid() = m.user_a or auth.uid() = m.user_b)
    )
  );

-- Realtime: team_matches 변경 감지 (publish 액션은 publication 전역 설정이라 테이블별 제한 불가 — RLS 가 쌍 외 수신을 차단)
-- + team_messages 전체(채팅 왕복). 재실행 안전 (duplicate 무시).
do $$ begin
  alter publication supabase_realtime add table public.team_matches;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.team_messages;
exception when duplicate_object then null; end $$;

-- 채팅 신고 — 스토어 UGC 정책(신고 경로 필수) 충족. 방 30일 purge 후에도
-- 운영 감사 흔적이 남도록 FK 없이 uuid 만 기록한다. select 정책 없음 —
-- 열람은 service role(운영) 전용.
create table if not exists public.team_reports (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null,
  reporter_id uuid not null,
  reported_id uuid not null,
  reason      text not null check (char_length(reason) <= 200),
  created_at  timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

alter table public.team_reports enable row level security;

drop policy if exists "team_reports_pair_insert" on public.team_reports;

-- insert: 신고자 = 본인이면서 해당 매치 쌍의 당사자, 피신고자 = 그 상대만.
create policy "team_reports_pair_insert"
  on public.team_reports for insert
  with check (
    reporter_id = auth.uid()
    and exists (
      select 1 from public.team_matches m
       where m.team_id = team_reports.team_id
         and ((auth.uid() = m.user_a and team_reports.reported_id = m.user_b)
           or (auth.uid() = m.user_b and team_reports.reported_id = m.user_a))
    )
  );

-- 차단 — 비용은 전부 차단자가 진다. 차단자는 상대가 있는 방에 못 들어가고
-- (BLOCKED_MEMBER), 차단당한 쪽은 어디든 참가 가능 — 불이익도, 차단 사실을
-- 눈치챌 단서도 없다. 예외는 서로가 만든 방 하나: 상호 비공개 (목록에서
-- 숨기고 직접 진입은 NOT_FOUND). 제3자 방에서 두 사람이 같이 매칭하게 되면
-- 그 쌍의 발표 점수를 엔진이 상한 60점(형극난조 확정)으로 눌러 베스트·매칭
-- 카드로 이어지지 않게 한다 (snapshot.blocked 동결 — join_team 참고).
-- 차단 순간 같이 있던 모집 중 방에서는 차단자가 자동 퇴장(트리거). 본인 행만
-- 읽기/쓰기.
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.user_blocks enable row level security;

drop policy if exists "user_blocks_self_read"   on public.user_blocks;
drop policy if exists "user_blocks_self_insert" on public.user_blocks;
drop policy if exists "user_blocks_self_delete" on public.user_blocks;

create policy "user_blocks_self_read"
  on public.user_blocks for select using (blocker_id = auth.uid());
create policy "user_blocks_self_insert"
  on public.user_blocks for insert with check (blocker_id = auth.uid());
create policy "user_blocks_self_delete"
  on public.user_blocks for delete using (blocker_id = auth.uid());

-- 차단 순간, 두 사람이 같이 있는 모집 중 방에서 차단자가 자동 퇴장한다
-- (차단 비용은 차단자 부담). 차단자가 방장인 방만은 방장 자리를 비울 수
-- 없으므로 상대가 나가진다 — 자기 공간 보호 예외. 시작된 방(revealing~)은
-- 되돌리지 않는다 — snapshot 재확인·엔진 상한이 결과를 무해화.
create or replace function public.block_auto_leave()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  delete from team_members tm
   using teams t, team_members other
   where t.id = tm.team_id and t.status = 'recruiting'
     and other.team_id = tm.team_id
     and ((tm.user_id = new.blocker_id and other.user_id = new.blocked_id
           and t.owner_id <> new.blocker_id)
       or (tm.user_id = new.blocked_id and other.user_id = new.blocker_id
           and t.owner_id = new.blocker_id));
  return new;
end;
$$;

drop trigger if exists user_blocks_auto_leave on public.user_blocks;
create trigger user_blocks_auto_leave
  after insert on public.user_blocks
  for each row execute function public.block_auto_leave();

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-4b. 매칭 응답 푸시 — push_tokens + team_matches trigger → Worker → FCM
-- ─────────────────────────────────────────────────────────────────────────────
-- 기기 FCM token — 로그인 세션마다 앱이 upsert (token 이 PK: 기기당 1행,
-- 계정 전환 시 user_id 만 갈아탄다). 로그아웃 시 앱이 본인 행 삭제.
create table if not exists public.push_tokens (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  token      text        primary key,
  platform   text        not null default 'android',
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens_self_select" on public.push_tokens;
drop policy if exists "push_tokens_self_insert" on public.push_tokens;
drop policy if exists "push_tokens_self_update" on public.push_tokens;
drop policy if exists "push_tokens_self_delete" on public.push_tokens;

create policy "push_tokens_self_select"
  on public.push_tokens for select using (user_id = auth.uid());
create policy "push_tokens_self_insert"
  on public.push_tokens for insert with check (user_id = auth.uid());
create policy "push_tokens_self_update"
  on public.push_tokens for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "push_tokens_self_delete"
  on public.push_tokens for delete using (user_id = auth.uid());

-- 서버 전용 비밀 저장소 — API 로 절대 노출 금지 (RLS 켜고 정책 없음 + revoke).
-- push_webhook_secret 값은 baseline 에 싣지 않는다 — 운영 patch 로 1회 insert.
create table if not exists public.app_secrets (
  key   text primary key,
  value text not null
);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;

-- consent 변경 → Worker(/api/push/match) 로 webhook — 상대에게 FCM 발송.
-- 비밀 미설정이면 조용히 통과 (푸시만 안 나감, 매칭 흐름 무영향).
create or replace function public.notify_match_response()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_target    uuid;
  v_responder uuid;
  v_accepted  boolean;
  v_secret    text;
begin
  -- null 전이(응답 철회 — 운영·시험 리셋에서만 발생)는 알릴 사건이 아니다.
  if new.a_consent is distinct from old.a_consent
     and new.a_consent is not null then
    v_responder := new.user_a; v_target := new.user_b; v_accepted := new.a_consent;
  elsif new.b_consent is distinct from old.b_consent
     and new.b_consent is not null then
    v_responder := new.user_b; v_target := new.user_a; v_accepted := new.b_consent;
  else
    return new;
  end if;
  select value into v_secret from app_secrets where key = 'push_webhook_secret';
  if v_secret is null then return new; end if;
  perform net.http_post(
    url     := 'https://facely.kr/api/push/match',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'x-push-secret', v_secret),
    body    := jsonb_build_object(
      'team_id', new.team_id, 'target', v_target, 'responder', v_responder,
      'accepted', v_accepted, 'opened', new.opened_at is not null)
  );
  return new;
end;
$$;

drop trigger if exists team_matches_notify on public.team_matches;
create trigger team_matches_notify
  after update on public.team_matches
  for each row execute function public.notify_match_response();

-- 채팅 메시지 INSERT → Worker(/api/push/chat) — 상대에게 FCM 발송.
-- 대상 = 그 방 매칭 쌍에서 보낸이의 반대편. 비밀 미설정이면 조용히 통과.
create or replace function public.notify_chat_message()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_target uuid;
  v_secret text;
begin
  select case when m.user_a = new.sender_id then m.user_b else m.user_a end
    into v_target
    from team_matches m
   where m.team_id = new.team_id;
  if v_target is null or v_target = new.sender_id then return new; end if;
  select value into v_secret from app_secrets where key = 'push_webhook_secret';
  if v_secret is null then return new; end if;
  perform net.http_post(
    url     := 'https://facely.kr/api/push/chat',
    headers := jsonb_build_object(
      'Content-Type', 'application/json', 'x-push-secret', v_secret),
    body    := jsonb_build_object(
      'team_id', new.team_id, 'target', v_target,
      'sender', new.sender_id, 'preview', left(new.body, 80))
  );
  return new;
end;
$$;

drop trigger if exists team_messages_notify on public.team_messages;
create trigger team_messages_notify
  after insert on public.team_messages
  for each row execute function public.notify_chat_message();

-- ─────────────────────────────────────────────────────────────────────────────
-- 11-5. Battle RPC 상태 머신 + 공개 목록 view + Realtime
-- ─────────────────────────────────────────────────────────────────────────────
-- 조인·이탈·결과 기록은 전부 security definer 단일 트랜잭션 — 정원·비밀번호·
-- 연령·상태 가드를 원자 검증한다. 시작 조건은 정원 충족 하나뿐 (join 내장).

-- 조인: recruiting · 정원 미달 · 미중복 · 비밀번호 · 연령대 · 성별 정원(match
-- 방) · my-face 존재. 마지막 참가자의 트랜잭션이 chemistry_snapshot 동결 +
-- revealing 전이까지 수행.
create or replace function public.join_team(p_team_id uuid, p_password text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_team         record;
  v_age          int;
  v_gender       text;
  v_count        int;
  v_slot         int;
  v_gender_count int;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  -- 방 행 잠금 — 동시 조인의 정원 검사를 직렬화 (race 원천 차단).
  select * into v_team from teams where id = p_team_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  -- 방장이 나를 차단한 방은 상호 비공개 — 존재하지 않는 방과 같은 중립
  -- 코드로 숨긴다 (목록 숨김은 public_teams 가 담당, 직접 링크는 여기).
  if exists (select 1 from user_blocks b
              where b.blocker_id = v_team.owner_id and b.blocked_id = v_uid) then
    raise exception 'NOT_FOUND';
  end if;
  if v_team.status <> 'recruiting' then raise exception 'NOT_RECRUITING'; end if;
  if v_team.password is not null
     and (p_password is null or p_password <> v_team.password) then
    raise exception 'BAD_PASSWORD';
  end if;

  -- my-face 필수 + 연령대·성별 게이트 (body.ageGroup "20s" → 20, body.gender).
  -- gender 는 my-face body 필수 필드라 결측도 NO_MY_FACE 로 준용한다.
  select nullif(regexp_replace(m.body::jsonb->>'ageGroup', '\D', '', 'g'), '')::int,
         m.body::jsonb->>'gender'
    into v_age, v_gender
    from metrics m
   where m.user_id = v_uid and m.is_my_face
   order by m.updated_at desc limit 1;
  if v_age is null or v_gender is null then raise exception 'NO_MY_FACE'; end if;
  if v_age < v_team.age_min or v_age > v_team.age_max then
    raise exception 'AGE_NOT_ALLOWED';
  end if;

  -- 차단 게이트 — 로스터(방장 포함)에 내가 차단한 사람이 있으면 사실대로
  -- 거부 (차단자는 자기 차단 목록을 아니 새는 것이 없다). 차단당한 쪽은
  -- 여기서 막지 않는다 — 막으면 로스터를 본 뒤라 차단 사실이 역산되고,
  -- 남의 선택으로 참가를 거부당하는 부당함도 있다. 같이 시작되는 경우는
  -- snapshot.blocked 동결 + 엔진 상한 60점이 결과를 무해화한다.
  if exists (select 1 from team_members tm
              join user_blocks b on b.blocked_id = tm.user_id
             where tm.team_id = p_team_id and b.blocker_id = v_uid) then
    raise exception 'BLOCKED_MEMBER';
  end if;

  select count(*), coalesce(max(slot_no), 0) into v_count, v_slot
    from team_members where team_id = p_team_id;
  if v_count >= v_team.max_players then raise exception 'FULL'; end if;

  -- match 방: 성별 정원 = max_players/2 — 한쪽 성별이 차면 반대 성별만 남는다.
  if v_team.room_kind = 'match' then
    select count(*) into v_gender_count
      from team_members where team_id = p_team_id and gender = v_gender;
    if v_gender_count >= v_team.max_players / 2 then
      raise exception 'GENDER_FULL';
    end if;
  end if;

  begin
    insert into team_members (team_id, user_id, slot_no, gender, is_owner)
    values (p_team_id, v_uid, v_slot + 1, v_gender, v_uid = v_team.owner_id);
  exception when unique_violation then
    raise exception 'ALREADY_JOINED';
  end;

  -- 정원 충족 = 유일한 시작 조건. 입력(snapshot)을 서버가 동결 — 시작 후
  -- 재촬영이 결과에 영향을 못 주는 치팅 방어 + 전 클라이언트 동일 입력.
  -- blocked = 로스터 내 차단 쌍(방향 무관)의 slot 쌍 — 엔진이 이 쌍의 발표
  -- 점수를 상한 60점(형극난조)으로 눌러 베스트·매칭에서 배제한다. key 는
  -- user_id(uuid) 와 충돌하지 않아 {user_id: body} 소비자에 무해.
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
           ) || jsonb_build_object('blocked', coalesce((
             select jsonb_agg(jsonb_build_array(x.slot_no, y.slot_no))
               from team_members x
               join team_members y
                 on y.team_id = x.team_id and x.slot_no < y.slot_no
              where x.team_id = p_team_id
                and exists (select 1 from user_blocks ub
                             where (ub.blocker_id = x.user_id and ub.blocked_id = y.user_id)
                                or (ub.blocker_id = y.user_id and ub.blocked_id = x.user_id))
           ), '[]'::jsonb))
     where id = p_team_id;
  end if;
end;
$$;

-- 비밀방 문 앞 PIN 검증 — 목록 탭 → 상세 진입 전 dialog 용. password 봉인은
-- 유지(boolean 만 반환)하고, 조인 시 join_team 이 같은 비교를 다시 한다.
-- 비밀번호 없는 방·없는 방 id 는 각각 true/false. anon 도 목록을 탭할 수
-- 있어 anon 까지 grant — 4자리 PIN oracle 노출은 join_team 과 동일 수위.
create or replace function public.check_team_password(p_team_id uuid, p_password text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from teams t
     where t.id = p_team_id
       and (t.password is null or t.password = p_password)
  );
$$;

-- 이탈: recruiting 중 본인만 (방장은 방 삭제로만 접는다).
create or replace function public.leave_team(p_team_id uuid)
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
-- 최초 기록 성공 시 payload 의 best 쌍(slot) 을 roster 로 resolve 해
-- team_matches 행을 만든다 — payload 의 best 와 roster 만 신뢰하는
-- definer 전용 지점 (클라이언트가 임의 상대를 지목해 위조할 수 없다).
create or replace function public.submit_team_result(p_team_id uuid, p_payload jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists (select 1 from team_members
                  where team_id = p_team_id and user_id = v_uid) then
    raise exception 'NOT_PARTICIPANT';
  end if;
  update teams
     set result_payload = p_payload, status = 'completed', closed_at = now()
   where id = p_team_id and status = 'revealing' and result_payload is null;

  if found then
    begin
      select user_id into v_user_a from team_members
       where team_id = p_team_id and slot_no = (p_payload->'best'->>'a')::int;
      select user_id into v_user_b from team_members
       where team_id = p_team_id and slot_no = (p_payload->'best'->>'b')::int;
      -- 최후 방어선 — 시작 후에 생긴 차단(snapshot 동결이 못 본 것)까지
      -- 여기서 걸러 매칭 카드·채팅이 열리지 않게 한다.
      if v_user_a is not null and v_user_b is not null and v_user_a <> v_user_b
         and not exists (select 1 from user_blocks ub
                          where (ub.blocker_id = v_user_a and ub.blocked_id = v_user_b)
                             or (ub.blocker_id = v_user_b and ub.blocked_id = v_user_a)) then
        insert into team_matches (team_id, user_a, user_b)
        values (p_team_id, v_user_a, v_user_b)
        on conflict (team_id) do nothing;
      end if;
    exception when others then
      null;
    end;
  end if;
end;
$$;

-- 매칭 성사 상호 동의: completed 방의 best 쌍 각자가 채팅 개설 여부를 응답.
-- 거절은 즉시 종결 정책이라 재응답 불가 — consent 는 최초 응답으로 고정.
-- 둘 다 true 가 되는 호출에서 opened_at 을 찍어 채팅을 연다.
create or replace function public.respond_match(p_team_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_match record;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists (select 1 from teams where id = p_team_id and status = 'completed') then
    raise exception 'NOT_MATCHED';
  end if;

  select * into v_match from team_matches where team_id = p_team_id for update;
  if not found or (v_uid <> v_match.user_a and v_uid <> v_match.user_b) then
    raise exception 'NOT_MATCHED';
  end if;
  if (v_uid = v_match.user_a and v_match.a_consent is not null)
     or (v_uid = v_match.user_b and v_match.b_consent is not null) then
    raise exception 'ALREADY_DECIDED';
  end if;

  if v_uid = v_match.user_a then
    update team_matches set a_consent = p_accept where team_id = p_team_id;
  else
    update team_matches set b_consent = p_accept where team_id = p_team_id;
  end if;

  update team_matches
     set opened_at = now()
   where team_id = p_team_id and opened_at is null
     and a_consent is true and b_consent is true;
end;
$$;

revoke execute on function public.check_team_password(uuid, text) from public;
grant  execute on function public.check_team_password(uuid, text) to anon, authenticated;
revoke execute on function public.join_team(uuid, text)          from public, anon;
revoke execute on function public.leave_team(uuid)               from public, anon;
revoke execute on function public.submit_team_result(uuid, jsonb) from public, anon;
revoke execute on function public.respond_match(uuid, boolean)     from public, anon;
grant  execute on function public.join_team(uuid, text)          to authenticated;
grant  execute on function public.leave_team(uuid)               to authenticated;
grant  execute on function public.submit_team_result(uuid, jsonb) to authenticated;
grant  execute on function public.respond_match(uuid, boolean)     to authenticated;

-- 공개 매칭 목록 — 모집 중 공개방만, 컬럼 화이트리스트 (password 접근 없음).
-- 모집 중 전 방 노출 — 비밀방도 목록에 보이고(is_private 로 자물쇠 표시),
-- 입장만 PIN 으로 잠긴다. 방장과 차단 관계면 방향 무관 숨김 (상호 비공개) —
-- "나를 차단한 방장" 방향은 user_blocks RLS(본인 행만)로는 볼 수 없어
-- team_roster 와 같은 owner 실행 view 로 양방향을 필터한다. 노출 컬럼은
-- 종전과 동일 화이트리스트라 owner 실행이 새로 여는 정보는 없다. 비로그인은
-- 차단 행이 없어 전 방 노출.
create or replace view public.public_teams with (security_invoker = off) as
  select t.id, t.title, t.room_kind, t.thumb_open, t.is_private, t.max_players,
         t.age_min, t.age_max, t.created_at,
         (select count(*)::int from public.team_members tm where tm.team_id = t.id)
           as player_count
    from public.teams t
   where t.status = 'recruiting'
     and not exists (
       select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = t.owner_id)
           or (b.blocker_id = t.owner_id and b.blocked_id = auth.uid())
     );

-- 로비·리빌 명단 — team_members 에 users.nickname 을 붙인 읽기 전용 view.
-- 의도적으로 owner 권한 실행(비-invoker): users RLS(self-read)를 우회해
-- 참가자 "닉네임만" 노출한다 (coins·kakao_user_id 등은 select 목록에 없음).
-- 읽기 범위 = 방과 동일 link-share 모델. 다중 테이블 join 이라 auto-update
-- 불가지만 §11-4 에서 write revoke 로 이중 봉인.
create or replace view public.team_roster as
  select tm.team_id, tm.user_id, tm.slot_no, tm.gender, tm.is_owner, tm.joined_at,
         u.nickname
    from public.team_members tm
    join public.users u on u.id = tm.user_id;

-- 내 차단 목록 — team_roster 와 같은 owner 실행 view 패턴으로 users RLS
-- (self-read)를 우회해 차단 상대의 "닉네임만" 노출한다. 행 범위는 본인 차단
-- 행만 (auth.uid() 필터).
create or replace view public.my_blocks as
  select b.blocker_id, b.blocked_id, b.created_at, u.nickname
    from public.user_blocks b
    join public.users u on u.id = b.blocked_id
   where b.blocker_id = auth.uid();

-- Realtime: 로비 라이브 반영 — teams UPDATE(status 전이) + team_members
-- INSERT/DELETE(입장·이탈). 재실행 안전 (duplicate 무시).
-- Realtime full-row payload 가 column grant 를 우회해 password 를 실어나르지
-- 않도록 컬럼 리스트로 발행 (PG15+). chemistry_snapshot/result_payload 도
-- 제외 — 변경 이벤트는 신호이고 본문은 클라이언트가 refetch 한다.
do $$ begin
  alter publication supabase_realtime add table public.teams
    (id, owner_id, title, is_private, room_kind, thumb_open, max_players,
     age_min, age_max, status, started_at, closed_at, created_at, updated_at);
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.team_members;
exception when duplicate_object then null; end $$;

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
-- 11-4. teams column grants — password 봉인 + 상태 전이 RPC 전용화
-- ─────────────────────────────────────────────────────────────────────────────
-- §11-1 의 blanket grant 가 teams 전 컬럼을 열어 두므로 여기서 다시 좁힌다.
-- SELECT: password 만 제외 — 비교는 join_team 내부에서만.
revoke select on public.teams from anon, authenticated;
grant select (id, owner_id, title, is_private, room_kind, thumb_open, max_players,
              age_min, age_max, status, started_at, closed_at,
              chemistry_snapshot, result_payload, created_at, updated_at)
  on public.teams to anon, authenticated;
-- INSERT: 생성 입력 컬럼만 — status/started_at/snapshot/payload 는 default·RPC 전용.
revoke insert on public.teams from anon, authenticated;
grant insert (id, owner_id, title, password, room_kind, thumb_open,
              max_players, age_min, age_max)
  on public.teams to authenticated;
-- UPDATE: title 만 (방 이름 수정). 상태 전이·payload 는 RPC 전용.
revoke update on public.teams from anon, authenticated;
grant update (title) on public.teams to authenticated;
-- team_members 직접 쓰기 차단 — RPC (security definer) 전용.
revoke insert, update, delete on public.team_members from anon, authenticated;
-- team_matches 직접 쓰기 차단 — RPC (submit_team_result/respond_match) 전용.
revoke insert, update, delete on public.team_matches from anon, authenticated;
-- team_messages: update/delete 차단 (불변 로그) — insert 는 RLS 정책이 쌍 본인만 허용.
revoke update, delete on public.team_messages from anon, authenticated;
-- view 쓰기 봉인 — public_teams 는 단일 테이블이라 auto-updatable,
-- owner 권한 실행이면 RLS 우회 쓰기 통로가 된다 (final review Critical).
revoke insert, update, delete on public.public_teams from anon, authenticated;
revoke insert, update, delete on public.team_roster  from anon, authenticated;
revoke insert, update, delete on public.my_blocks      from anon, authenticated;

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
