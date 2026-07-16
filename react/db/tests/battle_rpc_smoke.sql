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

-- ⑨ battle_roster — 4명 전원 + 닉네임 (handle_new_user 가 raw_user_meta_data
--    의 nickname 을 users.nickname 으로 옮긴다).
do $$
declare
  v_count      int;
  v_null_count int;
begin
  select count(*), count(*) filter (where nickname is null)
    into v_count, v_null_count
    from public.battle_roster
   where team_id = '11111111-1111-1111-1111-111111111111';
  if v_count <> 4 then
    raise exception 'SMOKE_FAIL: battle_roster 인원수 불일치 (%)', v_count;
  end if;
  if v_null_count <> 0 then
    raise exception 'SMOKE_FAIL: battle_roster nickname 누락 (% 명)', v_null_count;
  end if;
end $$;

rollback;

-- rollback 뒤 = 마지막 문장이라야 SQL Editor 가 결과로 보여준다.
-- 여기 도달했다 = 위 assert 전부 통과 (실패면 SMOKE_FAIL exception 으로 중단).
select 'BATTLE RPC SMOKE: ALL PASS' as result;
