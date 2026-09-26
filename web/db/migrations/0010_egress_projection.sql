-- 0010 — 웹 SSR 의 Supabase egress 절감 (2026-09-26).
--
-- 실측 (2026-09-26, metrics 108행, 평균 body 4.3KB — 그중 landmarks 68%):
--   • 홈 daily_faces 가 활동일에 60행 × 4.2KB = 252KB 를 요청마다 내려보냈다.
--     홈은 그리드에 썸네일·나이대·성별·유형·top3 만 쓴다 → landmarks 가 필요 없다.
--   • /g/{id} 가 참가자 8명의 my-face body 전문(8×~7KB)을 받아 thumbnailKey·source·
--     ageGroup·ethnicity 네 필드만 꺼내 썼다.
--
-- 1) daily_faces — body 에서 landmarks·lateralLandmarks 를 빼고 `lite: true` 를 붙여 반환.
--    엔진(FaceReadingReport.fromJson)은 lite 면 좌표 없이도 파싱한다 (metrics 가 있을 때만).
--    반환 컬럼(body text, updated_at, opted)은 그대로라 웹 호출부는 바뀌지 않는다.
--    ⚠️ 적용 순서: lite 를 읽는 웹(face_engine.js)이 먼저 배포된 뒤 이 SQL 을 실행한다.
-- 2) team_roster_cards(p_team_id) — 참가자별 네 필드만 돌려주는 RPC. metrics 는
--    public read 라 security invoker 로 충분하지만, users 조인 없는 단순 투영이다.
--
-- idempotent. 적용: Supabase SQL Editor.

-- ── 1) daily_faces: landmarks 제거 투영 ─────────────────────────────────────
drop function if exists public.daily_faces(boolean, boolean, boolean, integer);
create function public.daily_faces(
  p_today_only   boolean default true,
  p_opted_only   boolean default true,
  p_my_face_only boolean default true,
  p_limit        integer default 60
) returns table (body text, updated_at timestamptz, opted boolean)
language sql stable security definer set search_path = public
as $$
  select ((m.body::jsonb - 'landmarks' - 'lateralLandmarks') || '{"lite":true}'::jsonb)::text as body,
         m.updated_at,
         (u.daily_face_opted_since is not null and m.is_my_face) as opted
    from metrics m
    left join users u on u.id = m.user_id
   where (not p_my_face_only or m.is_my_face)
     and (not p_opted_only   or u.daily_face_opted_since is not null)
     and (not p_today_only   or (m.updated_at at time zone 'Asia/Seoul')::date
                              = (now()        at time zone 'Asia/Seoul')::date)
   order by m.updated_at desc
   limit least(greatest(coalesce(p_limit, 60), 1), 200);
$$;
grant execute on function public.daily_faces(boolean, boolean, boolean, integer)
  to anon, authenticated;

-- ── 2) team_roster_cards: 참가자 my-face 의 카드 필드만 ─────────────────────
drop function if exists public.team_roster_cards(uuid);
create function public.team_roster_cards(p_team_id uuid)
returns table (
  user_id       uuid,
  thumbnail_key text,
  source        text,
  age_group     text,
  ethnicity     text
)
language sql stable security invoker set search_path = public
as $$
  select m.user_id,
         m.body::jsonb ->> 'thumbnailKey' as thumbnail_key,
         m.body::jsonb ->> 'source'       as source,
         m.body::jsonb ->> 'ageGroup'     as age_group,
         m.body::jsonb ->> 'ethnicity'    as ethnicity
    from team_members tm
    join metrics m on m.user_id = tm.user_id and m.is_my_face
   where tm.team_id = p_team_id;
$$;
grant execute on function public.team_roster_cards(uuid) to anon, authenticated;
