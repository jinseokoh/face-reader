-- Chemistry Battle RPC smoke — Supabase SQL Editor 에서 전체 실행.
-- begin…rollback 이라 데이터 잔여물 없음. 각 단계가 assert 로 검증하며,
-- 실패 시 해당 라인에서 exception 으로 멈춘다. 끝까지 가면 전부 통과.
begin;

-- 테스트 사용자 13명 (handle_new_user 트리거가 users 행 생성).
-- u1~u6  = team1('all', 6인) · u7~u13 = team2('match', 남3여3 + 조인 실패용 1)
-- team3('all', 6인, 채팅 RLS 용)는 u1~u6 를 재사용한다 (한 유저가 여러 방에 참가 가능).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000',
       ('00000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'authenticated', 'authenticated', 'battle-smoke-' || g || '@test.local', '',
       '{"provider":"email"}', jsonb_build_object('nickname', '테스터' || g),
       now(), now()
from generate_series(1, 13) g;

-- my-face 13개. u4 는 50대(연령 게이트 실패용) — ⑤ 에서 20대로 교체해 합류시킨다.
insert into public.metrics (id, user_id, body, is_my_face) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000002',
   '{"ageGroup":"30s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000003',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000004',
   '{"ageGroup":"50s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000005',
   '{"ageGroup":"20s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000006',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000007',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000008',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000009',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000010',
   '{"ageGroup":"20s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000011',
   '{"ageGroup":"20s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000012',
   '{"ageGroup":"20s","gender":"female","metrics":{}}', true),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000013',
   '{"ageGroup":"20s","gender":"male","metrics":{}}',   true);

-- auth.uid() 시뮬레이션 헬퍼: request.jwt.claims 의 sub 를 바꾼다.
create or replace function pg_temp.act_as(n int) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'),
                      'role', 'authenticated')::text, true);
$$;

-- ① 방 생성: u1, 비밀방 6인, 20~39세.
select pg_temp.act_as(1);
insert into public.teams (id, owner_id, title, visibility, password, max_players,
                          age_min, age_max)
values ('11111111-1111-1111-1111-111111111111', auth.uid(), '스모크 배틀',
        'private', '1234', 6, 20, 30);

-- ② 방장 조인 (비밀번호 필요).
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');

-- ③ 가드 검증 — 각각 지정 에러로 거부돼야 한다.
do $$ begin
  perform pg_temp.act_as(2);
  begin
    perform public.join_team('11111111-1111-1111-1111-111111111111', '0000');
    raise exception 'SMOKE_FAIL: BAD_PASSWORD 가드 미동작';
  exception when others then
    if sqlerrm <> 'BAD_PASSWORD' then raise; end if;
  end;
  begin
    -- 주의: 이 begin 블록은 예외로 끝나므로 안의 성공한 조인도 savepoint
    -- 롤백된다 — 블록이 끝나면 u2 는 미참가 상태다 (④ 가 다시 조인).
    perform public.join_team('11111111-1111-1111-1111-111111111111', '1234');
    perform public.join_team('11111111-1111-1111-1111-111111111111', '1234');
    raise exception 'SMOKE_FAIL: ALREADY_JOINED 가드 미동작';
  exception when others then
    if sqlerrm <> 'ALREADY_JOINED' then raise; end if;
  end;
  perform pg_temp.act_as(4); -- 50대 → 연령 게이트.
  begin
    perform public.join_team('11111111-1111-1111-1111-111111111111', '1234');
    raise exception 'SMOKE_FAIL: AGE_NOT_ALLOWED 가드 미동작';
  exception when others then
    if sqlerrm <> 'AGE_NOT_ALLOWED' then raise; end if;
  end;
end $$;

-- ④ 조인 → 이탈 → 재조인 (u2 — ③ 의 조인은 예외 블록과 함께 롤백된 상태),
--    방장 이탈 금지.
select pg_temp.act_as(2);
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');
select public.leave_team('11111111-1111-1111-1111-111111111111');
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');
do $$ begin
  perform pg_temp.act_as(1);
  begin
    perform public.leave_team('11111111-1111-1111-1111-111111111111');
    raise exception 'SMOKE_FAIL: OWNER_CANNOT_LEAVE 가드 미동작';
  exception when others then
    if sqlerrm <> 'OWNER_CANNOT_LEAVE' then raise; end if;
  end;
end $$;

-- ⑤ 정원 충족(6인) → 자동 시작 + snapshot 동결. (u4 는 연령 미달이므로
--    u3·u5·u6 까지 채운 뒤 u4 의 my-face 를 20대로 교체해 마지막 자리를 채운다.)
update public.metrics set body = '{"ageGroup":"20s","gender":"female","metrics":{}}'
 where user_id = '00000000-0000-0000-0000-000000000004' and is_my_face;
select pg_temp.act_as(3);
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');
select pg_temp.act_as(5);
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');
select pg_temp.act_as(6);
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');
select pg_temp.act_as(4);
select public.join_team('11111111-1111-1111-1111-111111111111', '1234');

do $$
declare v record;
begin
  select status, started_at, chemistry_snapshot into v
    from public.teams where id = '11111111-1111-1111-1111-111111111111';
  if v.status <> 'revealing' then raise exception 'SMOKE_FAIL: 정원 충족 자동 시작 미동작 (%)', v.status; end if;
  if v.started_at is null then raise exception 'SMOKE_FAIL: started_at 미기록'; end if;
  if (select count(*) from jsonb_object_keys(v.chemistry_snapshot)) <> 6 then
    raise exception 'SMOKE_FAIL: snapshot 6인 동결 실패';
  end if;
end $$;

-- ⑥ 시작 후 조인·이탈 차단.
do $$ begin
  begin
    perform public.leave_team('11111111-1111-1111-1111-111111111111');
    raise exception 'SMOKE_FAIL: 시작 후 leave 차단 미동작';
  exception when others then
    if sqlerrm <> 'NOT_LEAVABLE' then raise; end if;
  end;
end $$;

-- ⑦ 결과 기록 first-writer-wins.
select public.submit_team_result('11111111-1111-1111-1111-111111111111',
  '{"players":[],"pairs":[],"best":{"a":1,"b":2,"score":90}}');
select pg_temp.act_as(1);
select public.submit_team_result('11111111-1111-1111-1111-111111111111',
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
  if exists (select 1 from public.public_teams
              where id = '11111111-1111-1111-1111-111111111111') then
    raise exception 'SMOKE_FAIL: 비밀방이 public_teams 에 노출';
  end if;
end $$;

-- ⑨ team_roster — 6명 전원 + 닉네임·gender (handle_new_user 가 raw_user_meta_data
--    의 nickname 을 users.nickname 으로 옮긴다).
do $$
declare
  v_count       int;
  v_null_count  int;
  v_null_gender int;
begin
  select count(*), count(*) filter (where nickname is null),
         count(*) filter (where gender is null)
    into v_count, v_null_count, v_null_gender
    from public.team_roster
   where team_id = '11111111-1111-1111-1111-111111111111';
  if v_count <> 6 then
    raise exception 'SMOKE_FAIL: team_roster 인원수 불일치 (%)', v_count;
  end if;
  if v_null_count <> 0 then
    raise exception 'SMOKE_FAIL: team_roster nickname 누락 (% 명)', v_null_count;
  end if;
  if v_null_gender <> 0 then
    raise exception 'SMOKE_FAIL: team_roster gender 누락 (% 명)', v_null_gender;
  end if;
end $$;

-- ⑩ match 방(6인, 남3여3) — 남 정원 충족 후 4번째 남성 조인 → GENDER_FULL.
select pg_temp.act_as(7);
insert into public.teams (id, owner_id, title, visibility, password, room_kind,
                          max_players, age_min, age_max)
values ('22222222-2222-2222-2222-222222222222', auth.uid(), '매칭 배틀',
        'private', '5678', 'match', 6, 20, 30);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u7 slot1 male
select pg_temp.act_as(8);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u8 slot2 male
select pg_temp.act_as(9);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u9 slot3 male → 남 정원(3) 충족

do $$ begin
  perform pg_temp.act_as(13); -- 4번째 남성.
  begin
    perform public.join_team('22222222-2222-2222-2222-222222222222', '5678');
    raise exception 'SMOKE_FAIL: GENDER_FULL 가드 미동작';
  exception when others then
    if sqlerrm <> 'GENDER_FULL' then raise; end if;
  end;
end $$;

select pg_temp.act_as(10);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u10 slot4 female
select pg_temp.act_as(11);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u11 slot5 female
select pg_temp.act_as(12);
select public.join_team('22222222-2222-2222-2222-222222222222', '5678'); -- u12 slot6 female → 자동 시작

-- ⑪ 결과 기록 → best 쌍(slot 2×5 = u8×u11) 이 team_matches 로 정확히 resolve.
-- 먼저 malformed best (a==b) 를 submit — exception 으로 생략되고 team_matches 생성 안 됨.
select pg_temp.act_as(8);
select public.submit_team_result('22222222-2222-2222-2222-222222222222',
  '{"players":[],"pairs":[],"best":{"a":1,"b":1,"score":1}}');
do $$
declare v int;
begin
  select count(*) into v from public.team_matches
   where team_id = '22222222-2222-2222-2222-222222222222';
  if v <> 0 then
    raise exception 'SMOKE_FAIL: malformed best(a==b) 가 team_matches 를 만들면 안 됨';
  end if;
end $$;

-- 정상 payload submit — first-writer-wins 이므로 위 호출이 기록되지 않아 성공.
select public.submit_team_result('22222222-2222-2222-2222-222222222222',
  '{"players":[],"pairs":[],"best":{"a":2,"b":5,"score":95}}');
do $$
declare v record;
begin
  select user_a, user_b into v from public.team_matches
   where team_id = '22222222-2222-2222-2222-222222222222';
  if not found then raise exception 'SMOKE_FAIL: team_matches 행 미생성'; end if;
  if v.user_a <> '00000000-0000-0000-0000-000000000008'
     or v.user_b <> '00000000-0000-0000-0000-000000000011' then
    raise exception 'SMOKE_FAIL: team_matches best 쌍 resolve 실패 (a=%, b=%)', v.user_a, v.user_b;
  end if;
end $$;

-- ⑫ respond_match — 쌍 아닌 참가자 NOT_MATCHED · 한쪽 수락+상대 거절
--    (opened_at null 유지) · 재응답 ALREADY_DECIDED.
do $$ begin
  perform pg_temp.act_as(7); -- u7: team2 참가자지만 best 쌍(u8×u11) 이 아님.
  begin
    perform public.respond_match('22222222-2222-2222-2222-222222222222', true);
    raise exception 'SMOKE_FAIL: NOT_MATCHED 가드 미동작';
  exception when others then
    if sqlerrm <> 'NOT_MATCHED' then raise; end if;
  end;
end $$;

select pg_temp.act_as(8);
select public.respond_match('22222222-2222-2222-2222-222222222222', true);  -- u8 수락
select pg_temp.act_as(11);
select public.respond_match('22222222-2222-2222-2222-222222222222', false); -- u11 거절 → 종결

do $$
declare v record;
begin
  select a_consent, b_consent, opened_at into v from public.team_matches
   where team_id = '22222222-2222-2222-2222-222222222222';
  if v.a_consent is distinct from true or v.b_consent is distinct from false then
    raise exception 'SMOKE_FAIL: 수락/거절 consent 기록 불일치';
  end if;
  if v.opened_at is not null then
    raise exception 'SMOKE_FAIL: 거절된 매칭인데 opened_at 이 찍힘';
  end if;
end $$;

do $$ begin
  perform pg_temp.act_as(11); -- 이미 거절 응답 완료 — 재응답 불가.
  begin
    perform public.respond_match('22222222-2222-2222-2222-222222222222', true);
    raise exception 'SMOKE_FAIL: ALREADY_DECIDED 가드 미동작';
  exception when others then
    if sqlerrm <> 'ALREADY_DECIDED' then raise; end if;
  end;
end $$;

-- ⑬ team_messages RLS — team3(u1~u6 재사용)는 상호 수락으로 채팅을 연 뒤,
--    쌍 본인만 select/insert 가능함을 set local role authenticated + set_config
--    로 검증한다 (postgres 슈퍼유저로는 RLS 가 항상 우회돼 진짜 검증이 안 된다).
select pg_temp.act_as(1);
insert into public.teams (id, owner_id, title, visibility, max_players,
                          age_min, age_max)
values ('33333333-3333-3333-3333-333333333333', auth.uid(), '채팅 배틀',
        'public', 6, 20, 30);
select public.join_team('33333333-3333-3333-3333-333333333333', null);
select pg_temp.act_as(2);
select public.join_team('33333333-3333-3333-3333-333333333333', null);
select pg_temp.act_as(3);
select public.join_team('33333333-3333-3333-3333-333333333333', null);
select pg_temp.act_as(4);
select public.join_team('33333333-3333-3333-3333-333333333333', null);
select pg_temp.act_as(5);
select public.join_team('33333333-3333-3333-3333-333333333333', null);
select pg_temp.act_as(6);
select public.join_team('33333333-3333-3333-3333-333333333333', null); -- 6번째 → 자동 시작

select public.submit_team_result('33333333-3333-3333-3333-333333333333',
  '{"players":[],"pairs":[],"best":{"a":1,"b":2,"score":88}}');
select pg_temp.act_as(1);
select public.respond_match('33333333-3333-3333-3333-333333333333', true);
select pg_temp.act_as(2);
select public.respond_match('33333333-3333-3333-3333-333333333333', true);

do $$
declare v_opened timestamptz;
begin
  select opened_at into v_opened from public.team_matches
   where team_id = '33333333-3333-3333-3333-333333333333';
  if v_opened is null then
    raise exception 'SMOKE_FAIL: 상호 수락인데 opened_at 미기록';
  end if;
end $$;

do $$
declare
  v_team  uuid := '33333333-3333-3333-3333-333333333333';
  v_u1    uuid := '00000000-0000-0000-0000-000000000001';
  v_u2    uuid := '00000000-0000-0000-0000-000000000002';
  v_u3    uuid := '00000000-0000-0000-0000-000000000003';
  v_count int;
begin
  -- 쌍 본인(u1) insert — RLS 정책 통과해야 한다.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_u1::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into team_messages (team_id, sender_id, body) values (v_team, v_u1, '안녕하세요');

  -- 쌍 본인(u2) select — 방금 넣은 메시지가 보여야 한다.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_u2::text, 'role', 'authenticated')::text, true);
  select count(*) into v_count from team_messages where team_id = v_team;
  if v_count <> 1 then
    raise exception 'SMOKE_FAIL: 쌍 본인(u2) 읽기 실패 (count=%)', v_count;
  end if;

  -- 쌍 외부(u3) select — RLS 필터로 0행이어야 한다.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_u3::text, 'role', 'authenticated')::text, true);
  select count(*) into v_count from team_messages where team_id = v_team;
  if v_count <> 0 then
    raise exception 'SMOKE_FAIL: 쌍 외부(u3) 읽기가 차단되지 않음 (count=%)', v_count;
  end if;

  -- 쌍 외부(u3) insert — RLS 위반으로 거부돼야 한다.
  begin
    insert into team_messages (team_id, sender_id, body) values (v_team, v_u3, '몰래 끼어들기');
    raise exception 'SMOKE_FAIL: 쌍 외부(u3) insert 가 차단되지 않음';
  exception when insufficient_privilege then null;
  end;

  reset role;
end $$;

rollback;

-- rollback 뒤 = 마지막 문장이라야 SQL Editor 가 결과로 보여준다.
-- 여기 도달했다 = 위 assert 전부 통과 (실패면 SMOKE_FAIL exception 으로 중단).
select 'BATTLE RPC SMOKE: ALL PASS' as result;
