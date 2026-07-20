-- 비밀방 문 앞 PIN 검증 RPC 추가 — 목록에서 비밀 그룹 탭 시 상세 진입 전
-- dialog 가 호출한다. password 봉인은 유지(boolean 만 반환)하고, 조인 시
-- join_team 이 같은 비교를 다시 한다. baseline SSOT 반영 완료 — 이 파일은
-- 라이브 DB 1회 패치용.
-- Supabase SQL Editor 에서 전체 실행.

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

revoke execute on function public.check_team_password(uuid, text) from public;
grant  execute on function public.check_team_password(uuid, text) to anon, authenticated;

-- 검증: 비밀방 하나 골라 오답/정답 비교 (없으면 스킵).
-- select id, check_team_password(id, '0000') from teams where is_private limit 1;
