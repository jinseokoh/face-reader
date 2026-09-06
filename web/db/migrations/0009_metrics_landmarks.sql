-- 0009 — metrics.body 에 랜드마크 좌표 저장 허용 (리포트 스키마 2, 2026-09-06).
--
-- 스키마 2 부터 body 에 `landmarks`(정면 468×[x,y] 등방 좌표)와 선택적
-- `lateralLandmarks` 가 들어간다 (APPLE.md §5·§24·§26). 0001/0002 의
-- metrics_insert_anon 정책이 `landmarks` 키 존재만으로 insert 를 막았으므로 그
-- 조건만 뺀다. username/alias/birthday 금지는 그대로.
--
-- 스키마 1(좌표 없음) 행은 앱·웹이 더 읽지 못한다 (schemaVersion 불일치 → 폐기).
-- 지우는 것은 운영자 결정 — 아래 주석의 DELETE 를 SQL Editor 에서 직접 실행한다.
--   delete from public.metrics where (body::jsonb ->> 'schemaVersion')::int < 2;
-- 케미 방의 chemistry_snapshot 도 스키마 1 body 를 품고 있으면 runTeam 이 실패한다.
-- 데모 방 seed(web/db/tests/demo_teams.sql)는 새 빌드로 다시 찍은 뒤 재생성.
--
-- idempotent. 적용: Supabase SQL Editor.

drop policy if exists "metrics_insert_anon" on public.metrics;
create policy "metrics_insert_anon"
  on public.metrics for insert with check (
        (user_id is null or user_id = (select auth.uid()))
    and (body::jsonb ->> 'username') is null
    and (body::jsonb ->> 'alias')    is null
    and (body::jsonb ->> 'birthday') is null
  );
