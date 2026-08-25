-- 데모 케미 방 seed — Play Store 스크린샷용. Supabase SQL Editor 에서 전체 실행.
--
-- 지워지는 것: teams 전 행 (FK cascade 로 team_members·team_matches·
--             team_messages 까지) + team_reports.
-- 안 건드리는 것: users · metrics · compatibilities · coins (요구사항).
--
-- 만드는 방 6개:
--   ① 퇴근 후 러닝 크루   — 모집중 match 8인 (4/8, 마감 임박 ~22h)
--   ② 홍대 보드게임 소모임 — 모집중 all 6인 (2/6, 방장 = 리수하)
--   ③ 비공개 와인 모임     — 모집중 비밀방 match 6인 (PIN 7777)
--   ④ 금요일 저녁 미술관 동행 — revealing 6인. ⭐ 앱에서 열면 베스트 케미 =
--      홍청(67cc8011) × 리수하(3dbfa1dc) 88점 금슬화합 (엔진 실측 검증).
--      홍청 슬롯의 snapshot body 만 고득점 도너 기하(17c1dfec)로 동결 —
--      계정·metrics 는 무변경, 아바타는 라이브 my-face 라 실사진 유지.
--   ⑤ 주말 새벽 등산       — 인원 미달 종료 (expired)
--   ⑥ 성수동 카페 투어     — revealing all 6인. 열면 베스트 = 강도윤×방하늘
--      91점 천생연분 (리수하는 미선정 → 나가리 red 카드 데모).
--
-- ④·⑥은 payload 를 비워 둔다 — 앱에서 처음 여는 참가자(리수하 계정)가
-- 세리머니와 함께 계산·기록하고, 서버가 베스트 쌍 매칭 카드를 자동 생성한다.
do $$
declare
  v_risuha uuid := '7ad873cd-fd27-4792-8913-be6ca36f97b5';  -- 리수하 (형)
  v_hong   uuid := '09434d9c-7aa6-4e38-a687-369fedd6dc48';  -- 홍청 (부계정)
  -- battle-dummy-1..9
  v_junho   uuid := 'dddddddd-0000-0000-0000-000000000001'; -- 황준호 M
  v_minseok uuid := 'dddddddd-0000-0000-0000-000000000002'; -- 최민석 M
  v_seoyeon uuid := 'dddddddd-0000-0000-0000-000000000003'; -- 강서연 F
  v_euneun  uuid := 'dddddddd-0000-0000-0000-000000000004'; -- 선우은 F
  v_haneul  uuid := 'dddddddd-0000-0000-0000-000000000005'; -- 방하늘 F
  v_doyun   uuid := 'dddddddd-0000-0000-0000-000000000006'; -- 강도윤 M
  v_taeyang uuid := 'dddddddd-0000-0000-0000-000000000007'; -- 이태양 M
  v_sua     uuid := 'dddddddd-0000-0000-0000-000000000008'; -- 현수아 F
  v_yujin   uuid := 'dddddddd-0000-0000-0000-000000000009'; -- 김유진 F

  -- my-face metric id (snapshot body 소스)
  m_risuha  uuid := '3dbfa1dc-11ad-4660-b033-180fb9999796';
  m_hong    uuid := '67cc8011-8838-40a4-86d0-094dcd1d3eec';
  m_junho   uuid := 'ceb45848-21c2-4d4f-bc90-876d221284d6';
  m_minseok uuid := '4ed03ac5-7419-4bde-bf9e-2bf80d038abd';
  m_seoyeon uuid := '2e8ad47e-1b68-438a-9aeb-17d01e4e1659';
  m_euneun  uuid := '17c1dfec-dfa4-4a42-8e7d-f026d85eefb0'; -- ④ 홍청 슬롯 도너 기하
  m_haneul  uuid := 'd90c04f8-f7b1-4b9d-94a2-a2bcfd53539d';
  m_doyun   uuid := '11223ada-5e96-425a-bfdd-4e8105618a51';
  m_sua     uuid := '9c92d215-0863-43af-9c35-d8cf4afe1922';

  t1 uuid := 'aaaa1111-1111-1111-1111-111111111111';
  t2 uuid := 'aaaa2222-2222-2222-2222-222222222222';
  t3 uuid := 'aaaa3333-3333-3333-3333-333333333333';
  t4 uuid := 'aaaa4444-4444-4444-4444-444444444444';
  t5 uuid := 'aaaa5555-5555-5555-5555-555555555555';
  t6 uuid := 'aaaa6666-6666-6666-6666-666666666666';
begin
  -- 케미 아이템 전체 리셋 — 방·참가·매칭·채팅(cascade) + 신고.
  delete from public.teams;
  delete from public.team_reports;

  -- ① 모집중 public match 8인 — 4/8, 마감 임박(생성 6d2h 전 → 잔여 ~22h).
  insert into public.teams (id, owner_id, title, room_kind,
                            max_players, age_min, age_max, status, created_at)
  values (t1, v_junho, '퇴근 후 러닝 크루', 'match',
          8, 20, 40, 'recruiting', now() - interval '6 days 2 hours');
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values
    (t1, v_junho,   1, 'male',   '황준호', true),
    (t1, v_minseok, 2, 'male',   '최민석', false),
    (t1, v_risuha,  3, 'female', '리수하', false),
    (t1, v_yujin,   4, 'female', '김유진', false);

  -- ② 모집중 public all 6인 — 2/6, 방장 = 리수하 (QR·초대 화면용).
  insert into public.teams (id, owner_id, title, room_kind,
                            max_players, age_min, age_max, status, created_at)
  values (t2, v_risuha, '홍대 보드게임 소모임', 'all',
          6, 20, 30, 'recruiting', now() - interval '2 hours');
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values
    (t2, v_risuha, 1, 'female', '리수하', true),
    (t2, v_haneul, 2, 'female', '방하늘', false);

  -- ③ 모집중 비밀방 match 6인 — PIN 7777, 1/6.
  insert into public.teams (id, owner_id, title, room_kind, password,
                            max_players, age_min, age_max, status, created_at)
  values (t3, v_doyun, '비공개 와인 모임', 'match', '7777',
          6, 30, 40, 'recruiting', now() - interval '30 minutes');
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values (t3, v_doyun, 1, 'male', '강도윤', true);

  -- ④ ⭐ revealing 6인 — 베스트 = 홍청×리수하 88점 금슬화합 (엔진 실측).
  --   홍청 슬롯 body 는 도너 기하(m_euneun)에 성별·나이·홍청 실제 썸네일 패치.
  --   강서연 슬롯 body 는 저점 기하(m_minseok)에 동일 방식 패치 — 순위 방해 제거.
  --   나머지는 본인 my-face 그대로. body 는 전부 alias 제거(순수 계측 스냅샷).
  insert into public.teams (id, owner_id, title, room_kind,
                            max_players, age_min, age_max, status,
                            started_at, created_at, chemistry_snapshot)
  values (t4, v_junho, '금요일 저녁 미술관 동행', 'match',
          6, 20, 40, 'revealing',
          now() - interval '10 minutes', now() - interval '20 hours',
          jsonb_build_object(
            v_hong::text,
              ((select body::jsonb from public.metrics where id = m_euneun) - 'alias')
              || jsonb_build_object(
                   'gender', 'male', 'ageGroup', '30s',
                   'thumbnailKey',
                   (select body::jsonb ->> 'thumbnailKey' from public.metrics where id = m_hong)),
            v_doyun::text,
              (select body::jsonb from public.metrics where id = m_doyun) - 'alias',
            v_junho::text,
              (select body::jsonb from public.metrics where id = m_junho) - 'alias',
            v_risuha::text,
              (select body::jsonb from public.metrics where id = m_risuha) - 'alias',
            v_seoyeon::text,
              ((select body::jsonb from public.metrics where id = m_minseok) - 'alias')
              || jsonb_build_object(
                   'gender', 'female', 'ageGroup', '30s',
                   'thumbnailKey',
                   (select body::jsonb ->> 'thumbnailKey' from public.metrics where id = m_seoyeon)),
            v_sua::text,
              (select body::jsonb from public.metrics where id = m_sua) - 'alias'
          ) || jsonb_build_object('blocked', '[]'::jsonb, 'chatted', '[]'::jsonb));
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values
    (t4, v_hong,    1, 'male',   '홍청',   false),
    (t4, v_doyun,   2, 'male',   '강도윤', false),
    (t4, v_junho,   3, 'male',   '황준호', true),
    (t4, v_risuha,  4, 'female', '리수하', false),
    (t4, v_seoyeon, 5, 'female', '강서연', false),
    (t4, v_sua,     6, 'female', '현수아', false);

  -- ⑤ 인원 미달 종료 — 2/8, 모집 7일 초과 expired.
  insert into public.teams (id, owner_id, title, room_kind,
                            max_players, age_min, age_max, status,
                            created_at, closed_at)
  values (t5, v_yujin, '주말 새벽 등산', 'all',
          8, 20, 40, 'expired',
          now() - interval '9 days', now() - interval '2 days');
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values
    (t5, v_yujin,   1, 'female', '김유진', true),
    (t5, v_minseok, 2, 'male',   '최민석', false);

  -- ⑥ revealing all 6인 — 베스트 = 강도윤×방하늘 91점 천생연분 (엔진 실측,
  --   전원 실제 my-face body). 리수하는 미선정 → 목록 red(나가리) 카드 데모.
  insert into public.teams (id, owner_id, title, room_kind,
                            max_players, age_min, age_max, status,
                            started_at, created_at, chemistry_snapshot)
  values (t6, v_doyun, '성수동 카페 투어', 'all',
          6, 20, 40, 'revealing',
          now() - interval '5 minutes', now() - interval '9 hours',
          jsonb_build_object(
            v_doyun::text,
              (select body::jsonb from public.metrics where id = m_doyun) - 'alias',
            v_haneul::text,
              (select body::jsonb from public.metrics where id = m_haneul) - 'alias',
            v_risuha::text,
              (select body::jsonb from public.metrics where id = m_risuha) - 'alias',
            v_euneun::text,
              (select body::jsonb from public.metrics where id = m_euneun) - 'alias',
            v_minseok::text,
              (select body::jsonb from public.metrics where id = m_minseok) - 'alias',
            v_junho::text,
              (select body::jsonb from public.metrics where id = m_junho) - 'alias'
          ) || jsonb_build_object('blocked', '[]'::jsonb, 'chatted', '[]'::jsonb));
  insert into public.team_members (team_id, user_id, slot_no, gender, alias, is_owner)
  values
    (t6, v_doyun,   1, 'male',   '강도윤', true),
    (t6, v_haneul,  2, 'female', '방하늘', false),
    (t6, v_risuha,  3, 'female', '리수하', false),
    (t6, v_euneun,  4, 'female', '선우은', false),
    (t6, v_minseok, 5, 'male',   '최민석', false),
    (t6, v_junho,   6, 'male',   '황준호', false);

  raise notice '데모 방 6개 생성 완료 — ④·⑥은 리수하 계정 앱에서 열면 발표됩니다';
end $$;

-- 확인 — 6행: 상태·인원·snapshot 유무.
select t.title, t.room_kind, t.status, t.max_players,
       (select count(*) from public.team_members tm where tm.team_id = t.id) as players,
       (t.chemistry_snapshot is not null) as snapshot,
       (t.password is not null) as private
  from public.teams t
 order by t.created_at;
