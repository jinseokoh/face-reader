-- 0008_team_mode.sql — 케미 방 계산 방식 (APPLE.md §81.4)
--
-- teams.mode: 'physiognomy'(전통 관상 쌍 엔진) / 'first_impression'(문헌 기반
-- 첫인상 쌍 엔진). Android 는 방을 만들 때 둘 중 고르고, iOS(measure 에디션)는
-- first_impression 으로만 만들며 physiognomy 방은 목록·상세·참여 어디서도
-- 보지 않는다 (클라이언트 필터 — 서버는 두 모드를 모두 저장·제공한다).
-- 기존 방은 전부 physiognomy.
--
-- 적용: Supabase SQL Editor 에 수동. 여러 번 실행해도 안전(idempotent).

-- 1) 컬럼
alter table public.teams
  add column if not exists mode text not null default 'physiognomy';
do $$ begin
  alter table public.teams
    add constraint teams_mode_check
    check (mode in ('physiognomy', 'first_impression'));
exception when duplicate_object then null; end $$;

-- 2) 목록 조회 인덱스 — 모집 중 방을 모드로 거른다 (iOS 목록).
create index if not exists idx_teams_recruiting_mode
  on public.teams (mode, created_at desc) where status = 'recruiting';

-- 3) public_teams 뷰 — mode 노출. 0001 과 같이 drop→create (create or replace 는
--    컬럼을 끝에만 붙일 수 있다). select 권한은 0001 의 default privileges 가
--    새 뷰에도 붙고, 쓰기 revoke 는 뷰가 새로 생기므로 다시 건다.
drop view if exists public.public_teams;
create view public.public_teams with (security_invoker = on) as
  select t.id, t.title, t.room_kind, t.mode, t.is_private, t.max_players,
         t.age_min, t.age_max, t.created_at,
         (select count(*)::int from public.team_members tm where tm.team_id = t.id)
           as player_count
    from public.teams t
   where t.status = 'recruiting'
     and not public.is_blocked_with_me(t.owner_id);
revoke insert, update, delete on public.public_teams from anon, authenticated;

-- 3b) 결과 payload 와 방 방식의 일치 — 구버전 클라이언트(mode 를 모르는 Android)가
--     첫인상 방에 관상 payload 를 쓰는 것을 서버가 거부한다. 첫인상 payload 는
--     root 에 "mode":"first_impression" 을 싣고, 관상 payload 는 mode 키가 없다.
--     기존 행은 전부 physiognomy + mode 키 없음이라 그대로 통과한다.
do $$ begin
  alter table public.teams
    add constraint teams_payload_mode_check
    check (
      result_payload is null
      or (mode = 'physiognomy' and not (result_payload ? 'mode'))
      or (mode = 'first_impression' and result_payload->>'mode' = 'first_impression')
    );
exception when duplicate_object then null; end $$;

-- 4) column grant — SELECT/INSERT 에 mode 추가 (기존 목록은 0001 §11-4 와 동일).
grant select (mode) on public.teams to anon, authenticated;
grant insert (mode) on public.teams to authenticated;

-- 5) Realtime 발행 컬럼 목록에 mode 추가. 컬럼 목록 변경은 drop→add 뿐이다.
--    ⚠️ 반드시 컬럼 목록으로 다시 등록한다 — 목록 없이 등록하면 password 가
--    방송을 탄다 (0001 의 경고 그대로).
do $$ begin
  alter publication supabase_realtime drop table public.teams;
exception when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.teams
    (id, owner_id, title, room_kind, mode, max_players,
     age_min, age_max, status, started_at, closed_at, created_at, updated_at);
exception when duplicate_object then null; end $$;
