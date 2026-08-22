-- 0004_thumbnail_gc.sql — 썸네일 객체 회수 아웃박스
--
-- R2 썸네일을 지우는 코드가 네 곳에 흩어져 있었다: 앱의 saveMetrics(재촬영
-- 교체), /api/r2/delete(클라이언트 호출), /api/account/delete(탈퇴),
-- cron cleanupStaleMetrics(익명 90일). 넷 다 "행을 지우기 전에 키를 챙겨야
-- 한다"는 순서 제약을 각자 지켰고, 클라이언트 경로는 재시도가 없어 실패하면
-- 그대로 고아가 됐다.
--
-- 행 삭제를 진실로 두고 객체 회수가 그 뒤를 따르게 한다. 트리거가 **행 삭제와
-- 같은 트랜잭션에서** 키를 큐에 넣으므로 유실이 없고, cron 이 비우다 실패해도
-- 다음 실행이 재시도한다. 순서 제약도 사라진다.
--
-- 큐일 뿐 영구 데이터가 아니다 — 처리한 행은 지운다.

create table if not exists public.thumbnail_gc (
  key       text        primary key,
  queued_at timestamptz not null default now()
);

comment on table public.thumbnail_gc is
  '참조가 끊긴 R2 썸네일 키. cron drainThumbnailGc 가 비운다.';

create index if not exists thumbnail_gc_queued_at_idx
  on public.thumbnail_gc (queued_at);

-- 클라이언트는 이 테이블을 볼 일이 없다. service_role 은 RLS 를 우회한다.
alter table public.thumbnail_gc enable row level security;
revoke all on public.thumbnail_gc from anon, authenticated;
grant select, insert, update, delete on public.thumbnail_gc to service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 트리거 — 행이 사라지거나 썸네일 키가 바뀌면 옛 키를 큐에 넣는다.
--
-- metrics.body 는 text 다. 캐스팅 예외를 삼키지 않으면 body 가 깨진 행 하나가
-- **그 행의 DELETE 자체를 실패시킨다**. 회수를 못 하는 것보다 삭제를 막는 쪽이
-- 훨씬 나쁘므로 예외는 여기서 끊는다.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.queue_thumbnail_gc()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_key text;
  new_key text;
begin
  begin
    old_key := (old.body::jsonb ->> 'thumbnailKey');
    if tg_op = 'UPDATE' then
      new_key := (new.body::jsonb ->> 'thumbnailKey');
    end if;
  exception when others then
    return null;  -- body 가 JSON 이 아니다. 회수는 포기하고 삭제는 통과시킨다.
  end;

  if old_key is null then
    return null;
  end if;

  -- 키가 그대로면 회수 대상이 아니다 (alias·views 갱신 등).
  if tg_op = 'UPDATE' and new_key is not distinct from old_key then
    return null;
  end if;

  insert into public.thumbnail_gc (key)
  values (old_key)
  on conflict (key) do nothing;

  return null;
end;
$$;

drop trigger if exists metrics_thumbnail_gc on public.metrics;
create trigger metrics_thumbnail_gc
  after delete or update of body on public.metrics
  for each row execute function public.queue_thumbnail_gc();

-- PostgREST 스키마 캐시 갱신 — cron 이 REST 로 이 테이블을 읽는다.
notify pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────
-- 확인 — 0003 의 grant 누락 사고를 반복하지 않기 위해 세 롤을 모두 본다.
-- 기대: anon/authenticated 는 전부 false, service_role 은 전부 true.
-- ─────────────────────────────────────────────────────────────────────────

select
  has_table_privilege('anon',          'public.thumbnail_gc', 'select') as anon_select,
  has_table_privilege('anon',          'public.thumbnail_gc', 'insert') as anon_insert,
  has_table_privilege('authenticated', 'public.thumbnail_gc', 'select') as auth_select,
  has_table_privilege('authenticated', 'public.thumbnail_gc', 'insert') as auth_insert,
  has_table_privilege('service_role',  'public.thumbnail_gc', 'select') as svc_select,
  has_table_privilege('service_role',  'public.thumbnail_gc', 'delete') as svc_delete;

-- 트리거가 붙었는지도 함께 확인.
select tgname, tgenabled
  from pg_trigger
 where tgrelid = 'public.metrics'::regclass
   and not tgisinternal;
