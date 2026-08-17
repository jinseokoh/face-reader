-- ═════════════════════════════════════════════════════════════════════════════
-- 0003_service_role_execute.sql — 헬퍼 함수 실행 권한을 service_role 에도
-- 2026-08-17
-- ═════════════════════════════════════════════════════════════════════════════
-- 0002 에서 view 셋을 security_invoker = on 으로 바꾸면서 nickname_of ·
-- is_blocked_with_me 의 execute 를 anon·authenticated 에만 부여했다. invoker
-- view 는 함수를 "호출자 권한"으로 실행하므로, service_role 로 접근하는
-- 경로(refine 콘솔)에서 세 view 가 전부 막혔다.
--
--   service_role → team_roster   403 permission denied for function nickname_of
--   service_role → public_teams  403 permission denied for function is_blocked_with_me
--   service_role → my_blocks     403 permission denied for function nickname_of
--
-- anon·authenticated 는 정상이라 앱은 멀쩡했고, 그래서 0002 적용 직후의 라이브
-- 검증(anon 으로만 확인)을 통과해 버렸다. 검증 롤을 하나만 쓴 것이 원인이다.
--
-- service_role 은 §11-1 에서 테이블·시퀀스 권한을 일괄로 받지만 함수는 받지
-- 않는다 (routines 는 RPC grant/revoke 가 SoT). 그래서 명시 부여가 필요하다.
grant execute on function public.nickname_of(uuid)        to service_role;
grant execute on function public.is_blocked_with_me(uuid) to service_role;

-- 확인 — 세 롤 모두 EXECUTE 를 가져야 한다.
select p.proname,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
       has_function_privilege('service_role',  p.oid, 'EXECUTE') as service_role
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('nickname_of', 'is_blocked_with_me')
 order by p.proname;
