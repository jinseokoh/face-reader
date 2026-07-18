-- ⚠️ 기존 unlocks 행(지금까지의 궁합 해제 내역)이 전부 삭제된다 — 출시 전
-- 테스트 데이터 전제의 drop-recreate. 코인 잔액·원장(coins)은 건드리지 않음.
--
-- unlocks 를 "구매자 + 무방향 쌍" 구조로 재생성 — baseline §4 와 동일 내용.
-- Supabase SQL Editor 에서 전체 실행.

drop table if exists public.unlocks;
drop function if exists public.unlock_compat(uuid, real, text, text, text, text);

create table public.unlocks (
  user_id     uuid        not null references auth.users(id) on delete cascade,
  a_id        uuid        not null,
  b_id        uuid        not null,
  a_body      text,
  b_body      text,
  a_alias     text,
  b_alias     text,
  total_score real,
  created_at  timestamptz not null default now(),
  primary key (user_id, a_id, b_id),
  check (a_id < b_id)
);

alter table public.unlocks enable row level security;

create policy "unlocks_self_read"
  on public.unlocks for select using (user_id = auth.uid());
create policy "unlocks_self_delete"
  on public.unlocks for delete using (user_id = auth.uid());

create or replace function public.unlock_compat(
  p_a_id        uuid,
  p_b_id        uuid,
  p_total_score real default null,
  p_a_body      text default null,
  p_b_body      text default null,
  p_a_alias     text default null,
  p_b_alias     text default null
)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_balance integer;
  v_already boolean;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_a_id is null or p_b_id is null then raise exception 'pair ids required'; end if;
  if p_a_id >= p_b_id then raise exception 'pair not normalized (a_id < b_id)'; end if;

  select exists(
    select 1 from unlocks
    where user_id = v_uid and a_id = p_a_id and b_id = p_b_id
  ) into v_already;

  if v_already then
    select coins into v_balance from users where id = v_uid;
    return v_balance;
  end if;

  update users set coins = coins - 1
    where id = v_uid and coins >= 1
    returning coins into v_balance;
  if v_balance is null then return -1; end if;

  insert into unlocks (user_id, a_id, b_id, a_body, b_body,
                       a_alias, b_alias, total_score)
    values (v_uid, p_a_id, p_b_id, p_a_body, p_b_body,
            p_a_alias, p_b_alias, p_total_score);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance,
            p_a_id::text || '~' || p_b_id::text, 'compat-unlock');

  return v_balance;
end; $$;

revoke execute on function public.unlock_compat(uuid, uuid, real, text, text, text, text) from public, anon;
grant  execute on function public.unlock_compat(uuid, uuid, real, text, text, text, text) to authenticated;

select 'UNLOCKS PAIR MIGRATION OK' as result,
       count(*) as unlocks_rows from public.unlocks;
