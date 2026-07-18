-- 종료된 케미 배틀 dummy 시드 — Supabase SQL Editor 에서 전체 실행.
--
-- 지워지는 것: 이 스크립트가 이전에 만든 dummy 만 (고정 UUID 방 1개 + 가짜
-- 유저 5명 + 그들의 metrics·참가행, FK cascade). 실사용자 데이터는 안 건드림.
-- 재실행 안전 — 돌릴 때마다 지우고 새로 만든다.
--
-- 만드는 것: match 방 6인(남3·여3) completed 배틀.
--   '나' = 가장 최근 my-face 를 가진 로그인 계정 (slot 1, 방장, male 열).
--   가짜 5명 = 준호·민석(남) / 서연·지은·하늘(여). my-face body 는 내 것을
--   복제해 성별·나이대·썸네일만 패치 (엔진 파싱 유효 → 슬롯 meta·쌍 상세
--   unlock 동작). 썸네일 = cdn.facely.kr/dummy/{male,female}/N.jpg 실사 이미지
--   (200x200 아님 — 표시는 BoxFit.cover 원형 크롭이라 무관).
--   result_payload: 9쌍(남×여) 밴드 + 🏆 베스트 = 나(1)×서연(4) 92점.
--   battle_matches: 나×서연 성사 카드 pending (앱에서 수락/거절 테스트 가능).
do $$
declare
  v_team    uuid   := '22222222-2222-2222-2222-222222222222';
  v_dummy   uuid[] := array[
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-000000000002',
    'dddddddd-0000-0000-0000-000000000003',
    'dddddddd-0000-0000-0000-000000000004',
    'dddddddd-0000-0000-0000-000000000005'];
  v_names   text[] := array['준호', '민석', '서연', '지은', '하늘'];
  v_genders text[] := array['male', 'male', 'female', 'female', 'female'];
  v_thumbs  text[] := array[
    'dummy/male/1.jpg', 'dummy/male/2.jpg',
    'dummy/female/1.jpg', 'dummy/female/2.jpg', 'dummy/female/3.jpg'];
  v_me      uuid;
  v_me_nick text;
  v_me_body jsonb;
  v_me_age  int;
  i         int;
begin
  -- '나' = 가장 최근 my-face 의 로그인 소유자.
  select m.user_id, m.body::jsonb into v_me, v_me_body
    from public.metrics m
   where m.is_my_face and m.user_id is not null
   order by m.updated_at desc limit 1;
  if v_me is null then
    raise exception '로그인 계정의 my-face 가 없습니다 — 앱에서 내 관상 등록 후 실행';
  end if;
  select nickname into v_me_nick from public.users where id = v_me;
  v_me_age := greatest(coalesce(
    nullif(regexp_replace(v_me_body->>'ageGroup', '\D', '', 'g'), '')::int, 20), 20);

  -- 이전 dummy 제거 (이 스크립트 산출물만 — cascade 로 참가행·metrics 동반 삭제).
  delete from public.teams where id = v_team;
  delete from auth.users where id = any(v_dummy);

  -- 가짜 유저 5명 (handle_new_user 트리거가 public.users 행 생성) + my-face.
  for i in 1..5 loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                            raw_app_meta_data, raw_user_meta_data,
                            created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_dummy[i],
            'authenticated', 'authenticated',
            'battle-dummy-' || i || '@test.local', '',
            '{"provider":"email"}', jsonb_build_object('nickname', v_names[i]),
            now(), now());
    insert into public.metrics (user_id, body, is_my_face)
    values (v_dummy[i],
            (v_me_body
              || jsonb_build_object(
                   'gender', v_genders[i],
                   'ageGroup', v_me_age::text || 's',
                   'thumbnailKey', v_thumbs[i]))::text,
            true);
  end loop;

  -- 방: match 6인, 공개, 3시간 전 생성 → 2시간 전 시작 → 115분 전 종료.
  insert into public.teams (id, owner_id, title, visibility, room_kind,
                            thumb_open, max_players, age_min, age_max, status,
                            started_at, closed_at, created_at)
  values (v_team, v_me, '서울지역 케미 배틀', 'public', 'match',
          true, 6, v_me_age, v_me_age + 10, 'completed',
          now() - interval '2 hours', now() - interval '115 minutes',
          now() - interval '3 hours');

  -- 참가 6명: slot 1 = 나(방장·male 열), 2~3 남 / 4~6 여.
  insert into public.team_members (team_id, user_id, slot_no, gender, is_owner)
  values (v_team, v_me, 1, 'male', true);
  for i in 1..5 loop
    insert into public.team_members (team_id, user_id, slot_no, gender, is_owner)
    values (v_team, v_dummy[i], i + 1, v_genders[i], false);
  end loop;

  -- snapshot 동결 — join_battle 시작 트랜잭션과 동일한 집계 쿼리.
  update public.teams
     set chemistry_snapshot = (
           select jsonb_object_agg(tm.user_id::text, mf.body::jsonb)
             from public.team_members tm
             join lateral (
               select body from public.metrics m
                where m.user_id = tm.user_id and m.is_my_face
                order by m.updated_at desc limit 1
             ) mf on true
            where tm.team_id = v_team
         ),
         result_payload = jsonb_build_object(
           'players', jsonb_build_array(
             jsonb_build_object('slot', 1, 'name', coalesce(v_me_nick, '나'),
                                'gender', 'male'),
             jsonb_build_object('slot', 2, 'name', '준호', 'gender', 'male'),
             jsonb_build_object('slot', 3, 'name', '민석', 'gender', 'male'),
             jsonb_build_object('slot', 4, 'name', '서연', 'gender', 'female'),
             jsonb_build_object('slot', 5, 'name', '지은', 'gender', 'female'),
             jsonb_build_object('slot', 6, 'name', '하늘', 'gender', 'female')),
           'pairs', '[
             {"a":1,"b":4,"band":0}, {"a":2,"b":5,"band":1},
             {"a":3,"b":6,"band":1}, {"a":1,"b":5,"band":2},
             {"a":2,"b":4,"band":2}, {"a":3,"b":4,"band":2},
             {"a":1,"b":6,"band":2}, {"a":2,"b":6,"band":3},
             {"a":3,"b":5,"band":3}]'::jsonb,
           'best', jsonb_build_object('a', 1, 'b', 4, 'score', 92))
   where id = v_team;

  -- 베스트 쌍(나×서연) 매칭 성사 카드 — 양쪽 미응답 pending.
  insert into public.battle_matches (team_id, user_a, user_b)
  values (v_team, v_me, v_dummy[3]);

  raise notice 'dummy completed battle 생성 — 나 = % (%), 방 = %',
    coalesce(v_me_nick, '?'), v_me, v_team;
end $$;

select t.title, t.status, t.result_payload->'best' as best,
       (select count(*) from public.team_members tm where tm.team_id = t.id)
         as players
  from public.teams t
 where t.id = '22222222-2222-2222-2222-222222222222';
