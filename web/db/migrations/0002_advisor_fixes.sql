-- ═════════════════════════════════════════════════════════════════════════════
-- 0002_advisor_fixes.sql — Supabase Advisor 지적 3건 + realtime 발행 누락
-- 2026-08-17 · 안드로이드 출시 후 첫 마이그레이션
-- ═════════════════════════════════════════════════════════════════════════════
-- 0001_baseline.sql 은 이 시점으로 동결한다. 이후 스키마 변경은 이 파일처럼
-- 번호를 붙여 쌓고, baseline 은 다시 손대지 않는다.
--
-- 세 덩어리 모두 여러 번 돌려도 안전하다(idempotent). §1 은 운영에 이미
-- 적용돼 있고 재실행해도 결과가 같다.
--
--   §1  definer view 3개 → invoker + 스칼라 헬퍼 2개   (Advisor: CRITICAL ×3)
--   §2  RLS 정책 23개의 auth.uid() → (select auth.uid())  (Advisor: 성능)
--   §3  teams 를 realtime 발행 목록에 복구              (문장 실패로 누락돼 있었음)
--
-- 검증: postgres:15 컨테이너에 운영과 같은 상태(구 baseline)를 만든 뒤 이
-- 파일을 적용해 최종 상태가 baseline 과 일치하는 것을 확인했다.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- §1. definer view → invoker
-- ─────────────────────────────────────────────────────────────────────────────
-- view 본문 전체가 owner(postgres) 권한으로 돌아 RLS 를 통째로 우회했다.
-- select 목록을 한 번만 잘못 고쳐도 users 전 컬럼이 새는 구조였고, 폰이
-- Postgres 에 직접 붙으므로 중간에서 걸러줄 앱 서버도 없다.
--
-- 우회가 실제로 필요한 지점은 users.nickname 과 user_blocks 역방향 둘뿐이다.
-- teams·team_members 는 이미 `for select using (true)` 라 우회가 필요 없다.
-- 그 둘만 스칼라 함수로 승격하고 view 는 invoker 로 되돌린다.

-- 1. 승격 범위를 스칼라 둘로 좁히는 헬퍼
create or replace function public.nickname_of(p_user_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select u.nickname from users u where u.id = p_user_id;
$$;

create or replace function public.is_blocked_with_me(p_other uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from user_blocks b
     where (b.blocker_id = auth.uid() and b.blocked_id = p_other)
        or (b.blocker_id = p_other     and b.blocked_id = auth.uid())
  );
$$;

revoke execute on function public.nickname_of(uuid)        from public;
revoke execute on function public.is_blocked_with_me(uuid) from public;
grant  execute on function public.nickname_of(uuid)        to anon, authenticated;
grant  execute on function public.is_blocked_with_me(uuid) to anon, authenticated;

-- 2. view 셋을 invoker 로 재생성
drop view if exists public.public_teams;
create view public.public_teams with (security_invoker = on) as
  select t.id, t.title, t.room_kind, t.is_private, t.max_players,
         t.age_min, t.age_max, t.created_at,
         (select count(*)::int from public.team_members tm where tm.team_id = t.id)
           as player_count
    from public.teams t
   where t.status = 'recruiting'
     and not public.is_blocked_with_me(t.owner_id);

drop view if exists public.team_roster;
create view public.team_roster with (security_invoker = on) as
  select tm.team_id, tm.user_id, tm.slot_no, tm.gender, tm.is_owner, tm.joined_at,
         coalesce(tm.alias, public.nickname_of(tm.user_id)) as alias
    from public.team_members tm;

drop view if exists public.my_blocks;
create view public.my_blocks with (security_invoker = on) as
  select b.blocker_id, b.blocked_id, b.created_at,
         public.nickname_of(b.blocked_id) as nickname
    from public.user_blocks b;

-- 3. drop 으로 사라진 권한 복원 — baseline §11-1 grant + §11-4 write revoke 와 동일
grant all on public.public_teams to anon, authenticated, service_role;
grant all on public.team_roster  to anon, authenticated, service_role;
grant all on public.my_blocks    to anon, authenticated, service_role;

revoke insert, update, delete on public.public_teams from anon, authenticated;
revoke insert, update, delete on public.team_roster  from anon, authenticated;
revoke insert, update, delete on public.my_blocks    from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §2. RLS 정책의 auth.uid() 를 (select auth.uid()) 로
-- ─────────────────────────────────────────────────────────────────────────────
-- Postgres 는 정책 안의 auth.uid() 를 행마다 다시 부른다. 스칼라 서브쿼리로
-- 감싸면 InitPlan 으로 한 번만 평가하고 재사용한다. 판정 결과는 동일하고
-- 성능만 바뀐다. 정책 본문은 0001_baseline.sql 에서 그대로 옮겼다.

drop policy if exists "users_self_read" on public.users;
create policy "users_self_read"
  on public.users for select using (id = (select auth.uid()));

drop policy if exists "users_self_update" on public.users;
create policy "users_self_update"
  on public.users for update using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "coins_self_read" on public.coins;
create policy "coins_self_read"
  on public.coins for select using (user_id = (select auth.uid()));

drop policy if exists "metrics_insert_anon" on public.metrics;
create policy "metrics_insert_anon"
  on public.metrics for insert with check (
        (user_id is null or user_id = (select auth.uid()))
    and (body::jsonb ->> 'username') is null
    and (body::jsonb ->> 'alias')    is null
    and (body::jsonb ->> 'birthday') is null
    and not (body::jsonb ? 'landmarks')
  );

drop policy if exists "metrics_owner_update" on public.metrics;
create policy "metrics_owner_update"
  on public.metrics for update
    using (user_id is null or user_id = (select auth.uid()))
    with check (user_id is not distinct from (select auth.uid()));

drop policy if exists "metrics_owner_delete" on public.metrics;
create policy "metrics_owner_delete"
  on public.metrics for delete
    using (user_id is null or user_id = (select auth.uid()));

drop policy if exists "compatibilities_self_read" on public.compatibilities;
create policy "compatibilities_self_read"
  on public.compatibilities for select using (user_id = (select auth.uid()));

drop policy if exists "compatibilities_self_delete" on public.compatibilities;
create policy "compatibilities_self_delete"
  on public.compatibilities for delete using (user_id = (select auth.uid()));

drop policy if exists "ad_rewards_self_read" on public.ad_rewards;
create policy "ad_rewards_self_read"
  on public.ad_rewards for select using (user_id = (select auth.uid()));

drop policy if exists "teams_owner_insert" on public.teams;
create policy "teams_owner_insert"
  on public.teams for insert with check (owner_id = (select auth.uid()));

drop policy if exists "teams_owner_update" on public.teams;
create policy "teams_owner_update"
  on public.teams for update using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "teams_owner_delete" on public.teams;
create policy "teams_owner_delete"
  on public.teams for delete using (owner_id = (select auth.uid()));

drop policy if exists "team_matches_pair_read" on public.team_matches;
create policy "team_matches_pair_read"
  on public.team_matches for select
  using ((select auth.uid()) = user_a or (select auth.uid()) = user_b);

drop policy if exists "team_messages_pair_read" on public.team_messages;
create policy "team_messages_pair_read"
  on public.team_messages for select
  using (exists (
    select 1 from public.team_matches m
     where m.team_id = team_messages.team_id
       and m.opened_at is not null
       and ((select auth.uid()) = m.user_a or (select auth.uid()) = m.user_b)
  ));

drop policy if exists "team_messages_pair_insert" on public.team_messages;
create policy "team_messages_pair_insert"
  on public.team_messages for insert
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.team_matches m
       where m.team_id = team_messages.team_id
         and m.opened_at is not null
         and ((select auth.uid()) = m.user_a or (select auth.uid()) = m.user_b)
    )
  );

drop policy if exists "team_reports_pair_insert" on public.team_reports;
create policy "team_reports_pair_insert"
  on public.team_reports for insert
  with check (
    reporter_id = (select auth.uid())
    and exists (
      select 1 from public.team_matches m
       where m.team_id = team_reports.team_id
         and (((select auth.uid()) = m.user_a and team_reports.reported_id = m.user_b)
           or ((select auth.uid()) = m.user_b and team_reports.reported_id = m.user_a))
    )
  );

drop policy if exists "user_blocks_self_read" on public.user_blocks;
create policy "user_blocks_self_read"
  on public.user_blocks for select using (blocker_id = (select auth.uid()));

drop policy if exists "user_blocks_self_insert" on public.user_blocks;
create policy "user_blocks_self_insert"
  on public.user_blocks for insert with check (blocker_id = (select auth.uid()));

drop policy if exists "user_blocks_self_delete" on public.user_blocks;
create policy "user_blocks_self_delete"
  on public.user_blocks for delete using (blocker_id = (select auth.uid()));

drop policy if exists "push_tokens_self_select" on public.push_tokens;
create policy "push_tokens_self_select"
  on public.push_tokens for select using (user_id = (select auth.uid()));

drop policy if exists "push_tokens_self_insert" on public.push_tokens;
create policy "push_tokens_self_insert"
  on public.push_tokens for insert with check (user_id = (select auth.uid()));

drop policy if exists "push_tokens_self_update" on public.push_tokens;
create policy "push_tokens_self_update"
  on public.push_tokens for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "push_tokens_self_delete" on public.push_tokens;
create policy "push_tokens_self_delete"
  on public.push_tokens for delete using (user_id = (select auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- §3. teams 를 realtime 발행 목록에 복구
-- ─────────────────────────────────────────────────────────────────────────────
-- 컬럼 목록에 is_private 가 들어 있었다. stored 생성 컬럼이라 값은 디스크에
-- 실재하지만, Postgres 는 발행 컬럼 목록에 생성 컬럼의 "이름을 적는 것"을
-- 거부한다 (cannot use generated column ... in publication column list).
-- 목록을 아예 생략하면 생성 컬럼도 함께 발행되므로 막히는 것은 이름을 적는
-- 경우뿐인데, 여기서는 password 를 빼야 해서 목록이 필수다. 그래서 뺀다.
--
-- ⚠️ teams 는 반드시 컬럼 목록으로만 등록한다. 대시보드 Realtime 토글로
-- 켜면 목록 없는 전체 발행이 되어 password 가 방송을 탄다.
--
-- 이 한 단어 탓에 문장 전체가 실패해 teams 가 목록에서 빠져 있었다. 정원
-- 마감(recruiting→revealing)은 같은 트랜잭션의 team_members INSERT 알림이
-- 대신 잡아 즉시 반영됐고, 못 받던 것은 team_members 가 그대로인 채 teams
-- 만 바뀌는 사건들이다: 결과 저장(completed), 제목 수정, 만료(expired).
-- is_private 를 빼도 잃는 것이 없다 — 클라이언트는 payload 를 버리고
-- (`callback: (_) => onChange()`), 필터에 쓰는 id 는 목록에 남아 있다.
do $$ begin
  alter publication supabase_realtime add table public.teams
    (id, owner_id, title, room_kind, max_players,
     age_min, age_max, status, started_at, closed_at, created_at, updated_at);
exception when duplicate_object then null; end $$;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- 확인 — teams 행이 나오고 attnames 에 password 가 없어야 한다.
select tablename, attnames
  from pg_publication_tables
 where pubname = 'supabase_realtime'
 order by tablename;
