-- 0005_thumbnail_ownership.sql — 사진의 주인을 카드에서 사람으로
--
-- 0004 의 아웃박스는 "GC 가 모든 참조자를 암묵적으로 안다" 는 지킬 수 없는
-- 전제 위에 있었다. 참조를 metrics 에서만 세는 바람에 결제된 궁합이 붙들고
-- 있던 썸네일 7장이 실제로 지워졌다 (2026-08-22, 확인 쌍 13개 중 8개 손상).
--
-- 해법은 참조를 더 정확히 세는 게 아니라 **참조를 만들지 않는 것**이다.
-- 키의 첫 칸이 소유자가 되고(`thumbnails/{owner}/{sha256}.jpg`), 구매는 남의
-- 사진 주소를 베끼는 대신 자기 폴더로 사본을 만든다. 그러면 객체마다 주인이
-- 정확히 하나라 참조 계수가 필요 없고, 탈퇴는 prefix 하나를 지우는 일이 된다.
--
-- 삭제를 발화시키는 사건도 계정 수명뿐이다 — 재촬영도 카드 삭제도 사진을
-- 지우지 않는다. 200×200 JPEG 은 10KB 이고 R2 는 GB 당 월 $0.015 다.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. GC 철거 — 대체물을 만들지 않는다.
-- ─────────────────────────────────────────────────────────────────────────

drop trigger  if exists metrics_thumbnail_gc on public.metrics;
drop function if exists public.queue_thumbnail_gc();
drop table    if exists public.thumbnail_gc;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. 구매 스냅샷의 썸네일 키 교체 — 사본을 만든 뒤 스냅샷이 그걸 가리키게.
--
-- 결제 시점 복사가 실패했거나, 이 모델 이전에 산 궁합을 앱이 앞으로 나아가며
-- 고친다. compatibilities 에 UPDATE 정책이 없는 건 의도된 것이므로(동결)
-- 이 RPC 만 예외로 열되, 바꿀 수 있는 건 **내 행의 thumbnailKey 하나**이고
-- 가리킬 수 있는 곳은 **내 폴더뿐**이다.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.patch_compat_thumbnail(
  p_a_id uuid,
  p_b_id uuid,
  p_side text,
  p_key  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'auth required';
  end if;
  if p_side not in ('a', 'b') then
    raise exception 'side must be a or b';
  end if;
  -- 내 폴더의 내용 주소 키만 허용 — 남의 폴더나 임의 문자열을 못 심는다.
  if split_part(p_key, '/', 1) <> 'thumbnails'
     or split_part(p_key, '/', 2) <> uid::text
     or split_part(p_key, '/', 3) !~ '^[0-9a-f]{64}\.jpg$' then
    raise exception 'key must be an owner-scoped thumbnail key';
  end if;

  if p_side = 'a' then
    update public.compatibilities
       set a_body = jsonb_set(a_body::jsonb, '{thumbnailKey}', to_jsonb(p_key))::text
     where user_id = uid and a_id = p_a_id and b_id = p_b_id
       and a_body is not null;
  else
    update public.compatibilities
       set b_body = jsonb_set(b_body::jsonb, '{thumbnailKey}', to_jsonb(p_key))::text
     where user_id = uid and a_id = p_a_id and b_id = p_b_id
       and b_body is not null;
  end if;
end;
$$;

revoke all   on function public.patch_compat_thumbnail(uuid, uuid, text, text) from public;
grant execute on function public.patch_compat_thumbnail(uuid, uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────
-- 확인 — 0003 의 grant 누락 사고를 반복하지 않기 위해.
-- 기대: thumbnail_gc 0행(없음), 트리거 목록에 metrics_thumbnail_gc 없음,
--       authenticated 만 execute true.
-- ─────────────────────────────────────────────────────────────────────────

select to_regclass('public.thumbnail_gc') as thumbnail_gc_should_be_null;

select tgname from pg_trigger
 where tgrelid = 'public.metrics'::regclass and not tgisinternal;

select
  has_function_privilege('anon',          'public.patch_compat_thumbnail(uuid,uuid,text,text)', 'execute') as anon_exec,
  has_function_privilege('authenticated', 'public.patch_compat_thumbnail(uuid,uuid,text,text)', 'execute') as auth_exec;
