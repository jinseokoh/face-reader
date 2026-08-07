-- 라이브 적용: unlocks → compatibilities rename. 기존 행(구매 내역)·코인
-- 잔액·원장 전부 보존 — 사라지는 것 없음. Supabase SQL Editor 에서 전체 실행.
-- 실행 후 결과는 baseline §4(테이블·정책)·§9(RPC) 와 동일.
--
-- 주의: rename 만으로는 unlock_compat RPC 가 깨진다 (plpgsql 본문이 옛
-- 테이블명을 런타임 참조) — 아래 재생성까지 반드시 함께 실행할 것.
-- create or replace 는 기존 grant(authenticated)를 보존한다.

alter table public.unlocks rename to compatibilities;

alter policy "unlocks_self_read"   on public.compatibilities
  rename to "compatibilities_self_read";
alter policy "unlocks_self_delete" on public.compatibilities
  rename to "compatibilities_self_delete";

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
    select 1 from compatibilities
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

  insert into compatibilities (user_id, a_id, b_id, a_body, b_body,
                               a_alias, b_alias, total_score)
    values (v_uid, p_a_id, p_b_id, p_a_body, p_b_body,
            p_a_alias, p_b_alias, p_total_score);

  insert into coins (user_id, kind, amount, balance_after, reference_id, description)
    values (v_uid, 'spend', -1, v_balance,
            p_a_id::text || '~' || p_b_id::text, 'compat-unlock');

  return v_balance;
end; $$;
