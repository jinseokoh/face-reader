-- 0007_daily_face_rename.sql — "오늘의 관상" → "오늘 등록된 관상"
--
-- 기능은 그대로다. 홈 그리드에 **오늘 등록된 사람들의 얼굴**을 모아 보여주는
-- 갤러리이고, 사용자에게 매일 운세를 주는 기능이 아니다. 그런데 이름이
-- "오늘의 관상"(Today's Physiognomy)이라 daily reading 으로 읽힌다 —
-- App Store 4.3(b) 리젝을 두 번 받은 앱에서 이 오해는 값이 비싸다.
--
-- 코인 내역의 description 은 화면에 그대로 노출되므로(ledger_page.dart:25)
-- 함수 안의 문구와 이미 쌓인 행을 둘 다 바꾼다.

create or replace function public.claim_daily_face_bonus()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_since   timestamptz;
  v_balance integer;
  v_email   text;
  v_kakao   text;
  v_already boolean;
  v_granted boolean := false;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select daily_face_opted_since, coins
    into v_since, v_balance
    from users where id = v_uid
    for update;
  if not found then raise exception 'profile missing'; end if;

  select lower(au.email), au.raw_user_meta_data->>'provider_id'
    into v_email, v_kakao
    from auth.users au where au.id = v_uid;

  v_already := exists (
    select 1 from bonus_recipients
     where ((v_email is not null and email         = v_email)
         or (v_kakao is not null and kakao_user_id = v_kakao))
       and daily_face_bonus_at is not null);

  if not v_already
     and v_since is not null
     and now() >= v_since + interval '7 days'
     and (v_email is not null or v_kakao is not null) then
    update users set coins = coins + 3 where id = v_uid
      returning coins into v_balance;
    insert into coins (user_id, kind, amount, balance_after, description)
      values (v_uid, 'bonus', 3, v_balance, '오늘 등록된 관상 7일 공개 유지 보너스');
    update bonus_recipients set daily_face_bonus_at = now()
     where (v_email is not null and email         = v_email)
        or (v_kakao is not null and kakao_user_id = v_kakao);
    if not found then
      insert into bonus_recipients (email, kakao_user_id, daily_face_bonus_at)
        values (v_email, v_kakao, now());
    end if;
    v_granted := true;
    v_already := true;
  end if;

  return jsonb_build_object(
    'granted', v_granted, 'already', v_already,
    'opted_since', v_since, 'balance', v_balance);
end; $$;

-- 이미 쌓인 내역 행도 함께. 화면에 옛 이름이 남아 있으면 고친 의미가 없다.
update public.coins
   set description = '오늘 등록된 관상 7일 공개 유지 보너스'
 where description = '오늘의 관상 7일 공개 유지 보너스';

notify pgrst, 'reload schema';

-- 확인 — 기대: 옛 문구 0행.
select count(*) filter (where description = '오늘의 관상 7일 공개 유지 보너스') as old_label,
       count(*) filter (where description = '오늘 등록된 관상 7일 공개 유지 보너스') as new_label
  from public.coins;
