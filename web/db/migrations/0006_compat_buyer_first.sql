-- 0006_compat_buyer_first.sql — 저장 순서를 화면 순서로
--
-- `a_id < b_id` 는 쌍 동일성(같은 두 사람 = 한 행)을 위한 정규화였다. 그런데
-- 그 정렬이 **화면 순서까지 결정**해 버려서, 구매자가 uuid 운에 따라 오른쪽에
-- 놓였다. 그러면 화면마다 "구매자를 왼쪽으로" 재배치 규칙을 따로 들고 있어야
-- 하고, 실제로 앱엔 있고 admin 콘솔엔 없어서 같은 궁합이 두 화면에서 좌우가
-- 다르게 보였다.
--
-- 순서 규칙을 바꾼다:
--
--     구매자가 쌍에 포함 → 구매자 카드가 a
--     포함되지 않음      → uuid 오름차순 (종전과 동일)
--
-- 중복 결제 검사는 여전히 `(user_id, a_id, b_id)` 한 번이다. 구매자가 포함된
-- 쌍은 구매자 카드가 고정으로 a 라 순서가 흔들릴 수 없고, 포함되지 않은 쌍
-- (케미 결과표에서 남의 쌍 구매)은 매트릭스의 (i,j)·(j,i) 어느 칸을 눌러도
-- uuid 정렬이 같은 키로 모아준다. 양방향 검사가 필요 없는 이유다.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. a_id < b_id 제약 해제 (인라인 생성이라 이름이 자동 부여됐다)
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare cn text;
begin
  select conname into cn
    from pg_constraint
   where conrelid = 'public.compatibilities'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%a_id < b_id%';
  if cn is not null then
    execute format('alter table public.compatibilities drop constraint %I', cn);
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. 기존 행 정렬 — 구매자 my-face 가 b 쪽이면 좌우를 통째로 뒤집는다.
--    id·body·alias 가 한 벌로 움직여야 한다. 하나라도 빠지면 얼굴과 이름이
--    어긋난다.
-- ─────────────────────────────────────────────────────────────────────────

update public.compatibilities c
   set a_id    = c.b_id,
       b_id    = c.a_id,
       a_body  = c.b_body,
       b_body  = c.a_body,
       a_alias = c.b_alias,
       b_alias = c.a_alias
 where exists (
         select 1 from public.metrics m
          where m.user_id = c.user_id
            and m.is_my_face
            and m.id = c.b_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 3. unlock_compat — 정규화 검사 제거. 나머지는 그대로.
-- ─────────────────────────────────────────────────────────────────────────

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
  if p_a_id = p_b_id then raise exception 'pair ids must differ'; end if;

  -- 순서는 클라이언트가 정한다 (구매자 우선, 없으면 uuid 정렬). 같은 입력이면
  -- 같은 순서가 나오므로 이 단일 검사로 중복 결제가 막힌다.
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

notify pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────
-- 확인 — 기대: buyer_on_b = 0 (전부 a 쪽), check 제약 0건.
-- ─────────────────────────────────────────────────────────────────────────

select
  count(*) filter (
    where exists (select 1 from public.metrics m
                   where m.user_id = c.user_id and m.is_my_face and m.id = c.b_id)
  ) as buyer_on_b,
  count(*) filter (
    where exists (select 1 from public.metrics m
                   where m.user_id = c.user_id and m.is_my_face and m.id = c.a_id)
  ) as buyer_on_a,
  count(*) as total
  from public.compatibilities c;

select conname, pg_get_constraintdef(oid)
  from pg_constraint
 where conrelid = 'public.compatibilities'::regclass and contype = 'c';
