-- ─────────────────────────────────────────────────────────────────────────────
-- 0002 — `metrics.metrics_json` → `metrics.body` column rename
-- ─────────────────────────────────────────────────────────────────────────────
-- 이유: `metrics.metrics_json` 이 prefix 중복 (table.metrics → column.metrics_json)
-- 으로 가독성 저하. REST payload 어휘 `body` 가 의미적으로 정확.
--
-- 변경 항목:
--   1. ALTER TABLE — column rename (값 변환 없음, 인덱스·트리거 그대로)
--   2. RLS policy `metrics_insert_anon` — `metrics_json::jsonb` 참조를 `body::jsonb` 로
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.metrics rename column metrics_json to body;

-- RLS policy 재작성 (column 이름이 정의 본문에 박혀 있으므로 DROP+CREATE).
drop policy if exists "metrics_insert_anon" on public.metrics;

create policy "metrics_insert_anon"
  on public.metrics for insert with check (
        (user_id is null or user_id = auth.uid())
    and not (body::jsonb ? 'username')
    and not (body::jsonb ? 'alias')
    and not (body::jsonb ? 'birthday')
    and not (body::jsonb ? 'landmarks')
  );
