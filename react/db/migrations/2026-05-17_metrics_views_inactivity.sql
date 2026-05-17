-- ============================================================================
-- 2026-05-17 — metrics views++/updated_at inactivity 정리 + RLS
-- HOW-IT-WORKS §5.2 / §5.3 / §12.2 SSOT
-- ============================================================================
--
-- Supabase SQL Editor 에 한 번에 붙여넣어 실행.
-- 전부 idempotent (DROP + CREATE OR REPLACE / IF EXISTS / IF NOT EXISTS).
-- 한 번 더 돌려도 안전.
-- ============================================================================

-- ───────────────────────────────────────────────────────────────────────────
-- 1. 컬럼 추가
-- ───────────────────────────────────────────────────────────────────────────
-- metrics 행 = 1인 관상 측정 데이터. user_id 없음 (anonymous schema, PII 면 ↓).
-- views: /r/{id} fetch 마다 +1, dormant 판정의 active 신호 + 보너스 analytics.
-- updated_at: views 증가 시 trigger 로 자동 갱신, cron 의 정렬 키.
-- expires_at: v4 까지 사용하던 컬럼. v5 부터 미사용 (영구), v7 부터 inactivity
--             기반으로 전환. 컬럼 자체는 정책 전환 hook 용으로 유지.

alter table public.metrics
  add column if not exists views      integer     not null default 0,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists metrics_updated_at_idx
  on public.metrics (updated_at);

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Trigger: 어떤 UPDATE 든 updated_at 자동 touch
-- ───────────────────────────────────────────────────────────────────────────
-- 즉 views 만 ++ 해도 updated_at 이 같이 움직임. 본 trigger 가 있으니
-- application 코드에서 updated_at 을 명시 set 할 필요 없음.

create or replace function public.touch_metrics_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists metrics_touch on public.metrics;
create trigger metrics_touch
  before update on public.metrics
  for each row execute procedure public.touch_metrics_updated_at();

-- ───────────────────────────────────────────────────────────────────────────
-- 3. RPC: increment_metrics_views(card_id uuid)
-- ───────────────────────────────────────────────────────────────────────────
-- Worker SSR + Flutter 앱 모두 /r/{id} fetch 직후 fire-and-forget 호출.
-- security definer 라 RLS 의 update_none 정책을 우회. anon role 에 execute 권한.
-- 결과는 void — 호출자는 응답 본문 신경 안 씀.

create or replace function public.increment_metrics_views(card_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.metrics set views = views + 1 where id = card_id;
$$;

revoke all on function public.increment_metrics_views(uuid) from public;
grant execute on function public.increment_metrics_views(uuid) to anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. RLS 정책
-- ───────────────────────────────────────────────────────────────────────────
-- - select: 누구나. UUID 모르면 fetch 불가하므로 사실상 link-share 모델.
-- - insert: anon 에 허용하되 metrics_json 안에 PII key 가 있으면 reject.
--           Flutter 가 자기 metrics 행 직접 UPSERT 할 때 사용.
-- - update: 정책 false. 모든 UPDATE 는 security-definer RPC 만 (views++) 또는
--           service-role (dormant cron · 명시 삭제) 로만 가능.
-- - delete: 정책 false. 정리·삭제 모두 service-role 만.

alter table public.metrics enable row level security;

drop policy if exists "metrics_read_anon"    on public.metrics;
drop policy if exists "metrics_insert_anon"  on public.metrics;
drop policy if exists "metrics_update_none"  on public.metrics;
drop policy if exists "metrics_delete_none"  on public.metrics;

create policy "metrics_read_anon"
  on public.metrics for select
  using (true);

create policy "metrics_insert_anon"
  on public.metrics for insert
  with check (
    not (metrics_json ? 'username')
    and not (metrics_json ? 'alias')
    and not (metrics_json ? 'birthday')
    and not (metrics_json ? 'landmarks')
  );

create policy "metrics_update_none"
  on public.metrics for update
  using (false);

create policy "metrics_delete_none"
  on public.metrics for delete
  using (false);

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Smoke test (선택)
-- ───────────────────────────────────────────────────────────────────────────
-- 한 행 INSERT → views++ → 값 확인 → DELETE (service-role 권한 필요).
-- Supabase SQL Editor 는 service-role 로 실행되므로 안전하게 테스트 가능.
--
-- do $$
-- declare
--   sid uuid := gen_random_uuid();
--   v   integer;
-- begin
--   insert into public.metrics(id, metrics_json) values (sid, '{}'::jsonb);
--   perform public.increment_metrics_views(sid);
--   select views into v from public.metrics where id = sid;
--   raise notice 'views after rpc = %', v;  -- 1
--   delete from public.metrics where id = sid;
-- end$$;

-- ============================================================================
-- 별도 단계 (이 파일에 포함 X) — Dormant cleanup cron
-- ============================================================================
--
-- 본 .sql 은 schema 만 적용. dormant 행 정리는 **Cloudflare Worker Cron
-- Trigger** 가 일일 1회 수행 (Supabase 측 cron 의존 회피). 자세한 흐름은
-- HOW-IT-WORKS §12.2 의 "Cron 구현" 블록. 후순위 task — TO-DO 의 ⏳ 마지막
-- 섹션 참조.
