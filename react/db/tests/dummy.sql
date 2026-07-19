-- 케미 방 전체 초기화 + dummy 방 2개 시드 — Supabase SQL Editor 에서 전체 실행.
--
-- 지워지는 것: 모든 방(teams 전 행 — FK cascade 로 참가·매칭 카드·채팅까지
-- 소멸) + 신고 기록(team_reports) + dummy 유저 6~9번의 옛 metrics.
-- 계정·코인·실사용자 관상(metrics)은 안 건드린다.
--
-- 만드는 것:
--   방 ① 서울지역 케미 그룹 — match 8인(남4·여4) 전원 참여, 나 = 방장.
--   방 ② 직장인 케미 그룹 — all 10인 전원 참여, 나 = 참가자(방장 = 준호).
--
-- 두 방 모두 status='revealing' + chemistry_snapshot 동결, result_payload 는
-- 비워 둔다 — 앱에서 방을 열면 그 기기의 엔진이 snapshot 으로 결과를 계산해
-- submit_team_result 로 1회 기록(first-writer-wins)하고 completed 로 넘어간다.
-- 베스트 쌍 매칭 카드도 그때 서버가 자동 생성한다. 결과 밴드를 SQL 로
-- 조작하지 않으므로 목록·시트·풀이가 항상 일치한다.
--
-- dummy 유저: dddddddd-...-0001~0009. 1~5번의 관상 body 는 기존 시드(엔진
-- 탐색 jitter)를 재사용해 밴드 다양성을 유지하고, 6~9번은 1~4번 body 를
-- 복제해 성별·썸네일만 패치한다. 썸네일 = cdn.facely.kr/dummy/{male,female}/N.jpg.
do $$
declare
  v_team1   uuid   := '22222222-2222-2222-2222-222222222222';
  v_team2   uuid   := '33333333-3333-3333-3333-333333333333';
  v_dummy   uuid[] := array[
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-000000000002',
    'dddddddd-0000-0000-0000-000000000003',
    'dddddddd-0000-0000-0000-000000000004',
    'dddddddd-0000-0000-0000-000000000005',
    'dddddddd-0000-0000-0000-000000000006',
    'dddddddd-0000-0000-0000-000000000007',
    'dddddddd-0000-0000-0000-000000000008',
    'dddddddd-0000-0000-0000-000000000009'];
  -- 1~5 = 기존 시드와 동일 (준호·민석 남 / 서연·지은·하늘 여), 6~9 = 신규.
  v_names   text[] := array['준호','민석','서연','지은','하늘','도윤','지훈','수아','유진'];
  v_genders text[] := array['male','male','female','female','female',
                            'male','male','female','female'];
  v_thumbs  text[] := array[
    'dummy/male/1.jpg', 'dummy/male/2.jpg',
    'dummy/female/1.jpg', 'dummy/female/2.jpg', 'dummy/female/3.jpg',
    'dummy/male/3.jpg', 'dummy/male/4.jpg',
    'dummy/female/4.jpg', 'dummy/female/5.jpg'];
  v_me      uuid;
  v_me_body jsonb;
  v_me_age  int;
  v_base    jsonb;
  i         int;
begin
  -- '나' = 가장 최근 my-face 의 로그인 소유자 — dummy 는 반드시 제외.
  select m.user_id, m.body::jsonb into v_me, v_me_body
    from public.metrics m
   where m.is_my_face and m.user_id is not null
     and m.user_id <> all(v_dummy)
   order by m.updated_at desc limit 1;
  if v_me is null then
    raise exception '로그인 계정의 my-face 가 없습니다 — 앱에서 내 관상 등록 후 실행';
  end if;
  v_me_age := greatest(coalesce(
    nullif(regexp_replace(v_me_body->>'ageGroup', '\D', '', 'g'), '')::int, 20), 20);

  -- 케미 아이템 전체 제거 — 방·참가·매칭·채팅(cascade) + 신고.
  delete from public.teams;
  delete from public.team_reports;

  -- dummy 유저 9명 upsert. 관상 body: 1~5번은 기존 것 유지(없으면 내 body
  -- 복제), 6~9번은 1~4번 body 복제 후 성별·나이대·썸네일 패치.
  for i in 1..9 loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                            raw_app_meta_data, raw_user_meta_data,
                            created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_dummy[i],
            'authenticated', 'authenticated',
            'battle-dummy-' || i || '@test.local', '',
            '{"provider":"email"}', jsonb_build_object('nickname', v_names[i]),
            now(), now())
    on conflict (id) do update
      set raw_user_meta_data = excluded.raw_user_meta_data;
    update public.users set nickname = v_names[i] where id = v_dummy[i];

    if i <= 5 then
      -- 기존 jitter body 유지 — 없을 때만 내 body 복제로 채운다.
      if not exists (select 1 from public.metrics m
                      where m.user_id = v_dummy[i] and m.is_my_face) then
        insert into public.metrics (user_id, body, is_my_face)
        values (v_dummy[i],
                (v_me_body || jsonb_build_object(
                   'gender', v_genders[i],
                   'ageGroup', v_me_age::text || 's',
                   'thumbnailKey', v_thumbs[i]))::text,
                true);
      end if;
    else
      select m.body::jsonb into v_base
        from public.metrics m
       where m.user_id = v_dummy[i - 5] and m.is_my_face
       order by m.updated_at desc limit 1;
      v_base := coalesce(v_base, v_me_body);
      delete from public.metrics where user_id = v_dummy[i];
      insert into public.metrics (user_id, body, is_my_face)
      values (v_dummy[i],
              (v_base || jsonb_build_object(
                 'gender', v_genders[i],
                 'ageGroup', v_me_age::text || 's',
                 'thumbnailKey', v_thumbs[i]))::text,
              true);
    end if;
  end loop;

  -- 방 ① match 8인 — 나 = 방장(slot 1). 남: 나·준호·민석·도윤 / 여: 서연·지은·하늘·수아.
  insert into public.teams (id, owner_id, title, room_kind, thumb_open,
                            max_players, age_min, age_max, status,
                            started_at, created_at)
  values (v_team1, v_me, '서울지역 케미 그룹', 'match', true,
          8, v_me_age, v_me_age + 10, 'revealing',
          now() - interval '5 minutes', now() - interval '1 hour');

  insert into public.team_members (team_id, user_id, slot_no, gender, is_owner)
  values
    (v_team1, v_me,        1, 'male',   true),
    (v_team1, v_dummy[1],  2, 'male',   false),  -- 준호
    (v_team1, v_dummy[2],  3, 'male',   false),  -- 민석
    (v_team1, v_dummy[6],  4, 'male',   false),  -- 도윤
    (v_team1, v_dummy[3],  5, 'female', false),  -- 서연
    (v_team1, v_dummy[4],  6, 'female', false),  -- 지은
    (v_team1, v_dummy[5],  7, 'female', false),  -- 하늘
    (v_team1, v_dummy[8],  8, 'female', false);  -- 수아

  -- 방 ② all 10인 — 방장 = 준호, 나 = 참가자(slot 2).
  insert into public.teams (id, owner_id, title, room_kind, thumb_open,
                            max_players, age_min, age_max, status,
                            started_at, created_at)
  values (v_team2, v_dummy[1], '직장인 케미 그룹', 'all', true,
          10, v_me_age, v_me_age + 10, 'revealing',
          now() - interval '3 minutes', now() - interval '2 hours');

  insert into public.team_members (team_id, user_id, slot_no, gender, is_owner)
  values
    (v_team2, v_dummy[1],  1, 'male',   true),   -- 준호(방장)
    (v_team2, v_me,        2, 'male',   false),
    (v_team2, v_dummy[2],  3, 'male',   false),  -- 민석
    (v_team2, v_dummy[6],  4, 'male',   false),  -- 도윤
    (v_team2, v_dummy[7],  5, 'male',   false),  -- 지훈
    (v_team2, v_dummy[3],  6, 'female', false),  -- 서연
    (v_team2, v_dummy[4],  7, 'female', false),  -- 지은
    (v_team2, v_dummy[5],  8, 'female', false),  -- 하늘
    (v_team2, v_dummy[8],  9, 'female', false),  -- 수아
    (v_team2, v_dummy[9], 10, 'female', false);  -- 유진

  -- snapshot 동결 — join_team 시작 트랜잭션과 동일 (blocked 쌍 포함).
  update public.teams t
     set chemistry_snapshot = (
           select jsonb_object_agg(tm.user_id::text, mf.body::jsonb)
             from public.team_members tm
             join lateral (
               select body from public.metrics m
                where m.user_id = tm.user_id and m.is_my_face
                order by m.updated_at desc limit 1
             ) mf on true
            where tm.team_id = t.id
         ) || jsonb_build_object('blocked', coalesce((
           select jsonb_agg(jsonb_build_array(x.slot_no, y.slot_no))
             from public.team_members x
             join public.team_members y
               on y.team_id = x.team_id and x.slot_no < y.slot_no
            where x.team_id = t.id
              and exists (select 1 from public.user_blocks ub
                           where (ub.blocker_id = x.user_id and ub.blocked_id = y.user_id)
                              or (ub.blocker_id = y.user_id and ub.blocked_id = x.user_id))
         ), '[]'::jsonb))
   where t.id in (v_team1, v_team2);

  raise notice 'dummy 생성 — 나 = %, match 8인 방(방장) = %, all 10인 방(참가자) = %',
    v_me, v_team1, v_team2;
end $$;

-- 성공 확인 — 2행: 서울지역(match·8/8·revealing) + 직장인(all·10/10·revealing).
select t.title, t.room_kind, t.status, t.max_players,
       (select count(*) from public.team_members tm where tm.team_id = t.id)
         as players,
       (t.chemistry_snapshot is not null) as snapshot_ok,
       (t.result_payload is null) as payload_pending
  from public.teams t
 order by t.title;
