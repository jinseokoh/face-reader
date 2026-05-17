# Supabase — operational notes

본 문서는 **운영 안내** 만 다룬다 (접속·검증·dev reset). **schema/RPC/RLS DDL 의 SSOT 는** `react/db/migrations/0001_baseline.sql` 한 파일. 아키텍처 설명은 `react/docs/HOW-IT-WORKS.md` §5 / §6 / §12.

**프로젝트 ref**: `jicaenyzunjdlcxcdbfb`

---

## 접속

### Option 1 · Supabase Dashboard
- https://supabase.com/dashboard/project/jicaenyzunjdlcxcdbfb → **SQL Editor**
- DDL 적용·smoke test 에 가장 간편.

### Option 2 · psql
```bash
psql "postgresql://postgres.jicaenyzunjdlcxcdbfb:[password]@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres"
```

### Option 3 · GUI (Postico / TablePlus / DBeaver)
- Host: `db.jicaenyzunjdlcxcdbfb.supabase.co`
- Port: `5432` · DB: `postgres` · User: `postgres`
- Password: Dashboard → Settings → Database → Database password
- SSL: Required

---

## clean-slate 복구 / 새 환경 부트스트랩

1. 빈 Supabase 프로젝트 생성 (또는 기존 프로젝트 reset).
2. `react/db/migrations/0001_baseline.sql` 전체를 SQL Editor 에 붙여넣고 RUN.
3. 본 파일의 「검증 스모크」 블록으로 확인.
4. `ads` / `ad_views` / `claim_ad_reward` 가 운영에 필요하면 baseline 의 §11 TODO 블록을 채우거나 별도 `pg_dump` 결과 append.

baseline 은 모두 idempotent (drop if exists + create / create if not exists / create or replace). 이미 채워진 DB 에 재실행해도 안전.

---

## 운영 prod schema 의 진짜 dump 가져오기

baseline.sql 의 누락·drift 가 의심되면 prod 와 직접 비교:

```bash
pg_dump --schema=public --no-owner --no-privileges \
  "postgresql://postgres.jicaenyzunjdlcxcdbfb:[PASSWORD]@aws-0-ap-northeast-2.pooler.supabase.com:5432/postgres" \
  > /tmp/prod_dump.sql

diff <(grep -E '^(CREATE TABLE|CREATE FUNCTION|CREATE POLICY|CREATE INDEX|CREATE TRIGGER)' /tmp/prod_dump.sql | sort) \
     <(grep -iE '^(create table|create or replace function|create policy|create.* index|create trigger)' \
        ../react/db/migrations/0001_baseline.sql | sort)
```

빠진 게 있으면 baseline 에 직접 채울 것.

---

## 검증 스모크

Supabase SQL Editor 는 service-role 로 실행 → RLS bypass. 일반 사용자 체험으로 확인하려면 "Run as authenticated" 체크 후 실행.

```sql
-- 1) public.users / public.coins / public.unlocks read self
select coins from users   where id = auth.uid();
select * from coins       where user_id = auth.uid() order by created_at desc limit 10;
select * from unlocks     where user_id = auth.uid();

-- 2) metrics: anon insert → views++ RPC → updated_at 변화 → delete
do $$
declare sid uuid := gen_random_uuid(); v integer;
begin
  insert into public.metrics
    (id, metrics_json, source, ethnicity, gender, age_group, expires_at)
  values
    (sid, '{}', 'album', 'eastAsian', 'male', '20s', now() + interval '90 days');
  perform public.increment_metrics_views(sid);
  select views into v from public.metrics where id = sid;
  raise notice 'views after rpc = %', v;  -- 1
  delete from public.metrics where id = sid;
end$$;

-- 3) 잔액 부족 시 -1
select spend_coins(9999, 'test', 'smoke');

-- 4) unlock 중복 호출 idempotent
select unlock_compat('test-pair-key');  -- 차감
select unlock_compat('test-pair-key');  -- 잔액 그대로

-- 5) PII 키 INSERT 거부 (RLS check) — 실패해야 정상
do $$
begin
  insert into public.metrics
    (id, metrics_json, source, ethnicity, gender, age_group, expires_at)
  values
    (gen_random_uuid(), '{"username":"hacker"}', 'album', 'eastAsian',
     'male', '20s', now() + interval '90 days');
  raise exception 'PII guard 실패 — 보안 hole';
exception when others then
  raise notice 'PII guard OK: %', sqlerrm;
end$$;
```

---

## DEV ONLY — reset

baseline.sql 의 §「DEV ONLY — reset」 주석 블록 사용. 본 reset 블록은 `auth.users` 의 트리거만 떼지 않고 public 측 테이블·함수만 정리하므로, 기존 테스트 계정은 Dashboard → Authentication → Users 에서 수동 삭제 필요.
