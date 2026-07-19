-- teams.visibility 폐기 — 공개/비밀의 진실을 password 단일 소스로.
-- 지워지는 것: visibility 컬럼 하나 (걸려 있던 CHECK·인덱스·view 는 아래서
-- 재생성). 방·참가자 등 데이터 행은 전부 보존된다.
-- 효과: 모집 중인 모든 방이 목록에 노출되고, password 있는 방만 조인 시
-- PIN 요구 (is_private 파생 컬럼이 자물쇠 표시용).
-- Supabase SQL Editor 에서 전체 실행.

do $$ begin
  alter publication supabase_realtime drop table public.teams;
exception when undefined_object then null; end $$;

drop view if exists public.public_teams;
alter table public.teams drop column if exists visibility cascade;
alter table public.teams add column if not exists is_private boolean
  generated always as (password is not null) stored;

drop index if exists idx_teams_public_recruiting;
create index if not exists idx_teams_recruiting
  on public.teams (created_at desc) where status = 'recruiting';

create or replace view public.public_teams with (security_invoker = on) as
  select t.id, t.title, t.room_kind, t.thumb_open, t.is_private, t.max_players,
         t.age_min, t.age_max, t.created_at,
         (select count(*)::int from public.team_members tm where tm.team_id = t.id)
           as player_count
    from public.teams t
   where t.status = 'recruiting';

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

-- 컬럼 grant 재조정 — password 봉인 유지, is_private 노출.
revoke select on public.teams from anon, authenticated;
grant select (id, owner_id, title, is_private, room_kind, thumb_open, max_players,
              age_min, age_max, status, started_at, closed_at,
              chemistry_snapshot, result_payload, created_at, updated_at)
  on public.teams to anon, authenticated;
revoke insert on public.teams from anon, authenticated;
grant insert (id, owner_id, title, password, room_kind, thumb_open,
              max_players, age_min, age_max)
  on public.teams to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.teams
    (id, owner_id, title, is_private, room_kind, thumb_open, max_players,
     age_min, age_max, status, started_at, closed_at, created_at, updated_at);
exception when duplicate_object then null; end $$;

select 'TEAMS PASSWORD-ONLY OK' as result,
       count(*) filter (where is_private) as private_rooms,
       count(*) as total_rooms
  from public.teams;
