# Supabase SQL Setup — Face Reader App

**마지막 업데이트**: 2026-04-18

## Prerequisites

Connect to your Supabase Postgres database using a Mac client:

### Option 1: Supabase Dashboard (easiest)
1. Go to https://supabase.com/dashboard/project/jicaenyzunjdlcxcdbfb
2. Navigate to **SQL Editor**
3. Paste and run the SQL below

### Option 2: psql (CLI)
```bash
psql "postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres"
```

### Option 3: GUI Client (Postico, TablePlus, DBeaver)
- Host: `db.jicaenyzunjdlcxcdbfb.supabase.co`
- Port: `5432`
- Database: `postgres`
- User: `postgres`
- Password: (Supabase Dashboard → Settings → Database → Database password)
- SSL: Required

---

## Table Creation

### metrics table

```sql
CREATE TABLE metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  metrics_json TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('camera', 'album')),
  ethnicity TEXT NOT NULL,
  gender TEXT NOT NULL,
  age_group TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for expiration cleanup
CREATE INDEX idx_metrics_expires_at ON metrics (expires_at);
```

### Row Level Security (RLS)

`metrics` 테이블은 딥링크 공유를 위해 **select 는 공개** (uuid 가 있는 자만 열람), **insert/update/delete 는 소유자만**.

```sql
ALTER TABLE metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert" ON metrics;
DROP POLICY IF EXISTS "allow_anon_select" ON metrics;

CREATE POLICY "metrics_public_read"  ON metrics FOR SELECT USING (true);
CREATE POLICY "metrics_owner_insert" ON metrics FOR INSERT WITH CHECK (user_id = auth.uid() OR user_id IS NULL);
CREATE POLICY "metrics_owner_update" ON metrics FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "metrics_owner_delete" ON metrics FOR DELETE USING (user_id = auth.uid());
```

### Optional: Automatic expiration cleanup

Supabase에서 만료된 데이터를 자동 삭제하려면 `pg_cron` extension 사용:

```sql
-- Enable pg_cron (Supabase Dashboard → Database → Extensions)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Daily cleanup at 3:00 AM UTC
SELECT cron.schedule(
  'cleanup-expired-metrics',
  '0 3 * * *',
  $$DELETE FROM metrics WHERE expires_at < now()$$
);
```

---

## 이전 스키마 초기화 (dev — data drop)

이전 permissive 스키마가 이미 적용된 경우 아래 먼저 실행. 프로덕션 데이터가 있다면 대신 수동 마이그레이션.

```sql
DROP TABLE IF EXISTS coins CASCADE;
DROP TABLE IF EXISTS users CASCADE;
-- metrics 는 유지하되 FK 와 policy 만 교체 (데이터 보존). 전부 재생성하려면:
-- TRUNCATE metrics;
ALTER TABLE metrics DROP CONSTRAINT IF EXISTS metrics_user_id_fkey;
DROP POLICY IF EXISTS "allow_anon_insert" ON metrics;
DROP POLICY IF EXISTS "allow_anon_select" ON metrics;
```

> Supabase Dashboard → Authentication → Users 에서 기존 카카오 test 계정들은 수동 삭제 (auth.users 는 `DROP TABLE CASCADE` 로도 안 지워짐).

## users (Supabase Auth 연동)

`public.users` 는 `auth.users` 의 1:1 프로필 확장. `id` 를 `auth.users(id)` 에 FK 로 묶어서 `auth.uid()` 로 정책을 건다. Kakao(OAuth) 와 Email provider 둘 다 같은 `auth.users` 로 수렴.

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  kakao_user_id TEXT,                 -- raw_user_meta_data.provider_id (OAuth 시)
  nickname TEXT,
  profile_image_url TEXT,
  coins INT NOT NULL DEFAULT 0,       -- 실제 충전은 트리거가 넣는 bonus RPC 로
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE metrics
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_metrics_user_id ON metrics (user_id);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_self_read"   ON users FOR SELECT USING (id = auth.uid());
CREATE POLICY "users_self_update" ON users FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());
-- INSERT 는 아래 트리거 전용 (anon/authenticated 모두 직접 insert 불가)
```

### 신규 가입 시 프로필 + 보너스 3코인 자동 생성 트리거

`auth.users` 에 row 가 생기는 순간(=Kakao OAuth 또는 Email signup 최초 성공) 자동으로 `public.users` 프로필 + `public.coins` 보너스 1 행을 넣는다. 클라이언트 쪽 race·중복 방지용.

```sql
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nickname TEXT;
  v_avatar TEXT;
  v_kakao_id TEXT;
BEGIN
  v_nickname := COALESCE(
    NEW.raw_user_meta_data->>'name',
    NEW.raw_user_meta_data->>'nickname',
    split_part(NEW.email, '@', 1)
  );
  v_avatar := COALESCE(
    NEW.raw_user_meta_data->>'avatar_url',
    NEW.raw_user_meta_data->>'picture'
  );
  v_kakao_id := NEW.raw_user_meta_data->>'provider_id';

  INSERT INTO public.users (id, kakao_user_id, nickname, profile_image_url, coins)
    VALUES (NEW.id, v_kakao_id, v_nickname, v_avatar, 3);

  INSERT INTO public.coins (user_id, kind, amount, balance_after, description)
    VALUES (NEW.id, 'bonus', 3, 3, '회원가입 보너스');

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```

---

## Verification

테이블 생성 후 확인:

```sql
-- 테이블 존재 확인
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public';

-- 컬럼 확인
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'metrics';

-- RLS 정책 확인
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'metrics';

-- 테스트 insert
INSERT INTO metrics (metrics_json, source, ethnicity, gender, age_group, expires_at)
VALUES ('{"test": true}', 'camera', 'eastAsian', 'male', 'twenties', now() + interval '90 days')
RETURNING id;

-- 테스트 select
SELECT * FROM metrics LIMIT 5;
```

---

## 지갑: coins + RPC

코인 충전·사용 이력 + 잔액 원자적 갱신. 모든 쓰기는 **로그인한 본인만** 수행. 직접 insert/update 는 금지하고 RPC (SECURITY DEFINER) 통해서만 통과.

```sql
CREATE TABLE coins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('purchase', 'spend', 'bonus', 'refund')),
  amount INT NOT NULL,
  balance_after INT NOT NULL,
  product_id TEXT,
  store_transaction_id TEXT,
  reference_id TEXT,
  description TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_coin_user_created ON coins (user_id, created_at DESC);
CREATE UNIQUE INDEX idx_coin_store_tx ON coins (store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

ALTER TABLE coins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert_tx" ON coins;
DROP POLICY IF EXISTS "allow_anon_select_tx" ON coins;

-- 본인 이력만 읽을 수 있음. 쓰기 policy 는 없음 → anon/authenticated 직접 insert 불가.
CREATE POLICY "coins_self_read" ON coins FOR SELECT USING (user_id = auth.uid());
```

### Atomic RPCs (auth.uid() 기반)

`p_user_id` 파라미터 제거 — **어느 누구도 타인의 user_id 를 지정하지 못함**. RPC 가 세션의 `auth.uid()` 를 진실로 삼는다. `SECURITY DEFINER` 로 RLS 우회하여 내부 insert 수행.

```sql
CREATE OR REPLACE FUNCTION grant_coins(
  p_amount INT,
  p_kind TEXT,
  p_product_id TEXT DEFAULT NULL,
  p_store_transaction_id TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;
  IF p_kind NOT IN ('purchase','bonus','refund') THEN
    RAISE EXCEPTION 'invalid kind: %', p_kind;
  END IF;

  IF p_store_transaction_id IS NOT NULL THEN
    SELECT balance_after INTO v_balance
      FROM coins
      WHERE store_transaction_id = p_store_transaction_id AND user_id = v_uid
      LIMIT 1;
    IF v_balance IS NOT NULL THEN RETURN v_balance; END IF;
  END IF;

  UPDATE users SET coins = coins + p_amount
    WHERE id = v_uid
    RETURNING coins INTO v_balance;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'profile missing'; END IF;

  INSERT INTO coins
    (user_id, kind, amount, balance_after, product_id, store_transaction_id, description)
    VALUES (v_uid, p_kind, p_amount, v_balance, p_product_id, p_store_transaction_id, p_description);
  RETURN v_balance;
END; $$;

CREATE OR REPLACE FUNCTION spend_coins(
  p_amount INT,
  p_reference_id TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;

  UPDATE users SET coins = coins - p_amount
    WHERE id = v_uid AND coins >= p_amount
    RETURNING coins INTO v_balance;
  IF v_balance IS NULL THEN RETURN -1; END IF;

  INSERT INTO coins (user_id, kind, amount, balance_after, reference_id, description)
    VALUES (v_uid, 'spend', -p_amount, v_balance, p_reference_id, p_description);
  RETURN v_balance;
END; $$;

REVOKE EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)            FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)             TO authenticated;
```

### 검증

```sql
-- 로그인한 세션으로 호출해야 auth.uid() 가 찬다. SQL Editor 에선 'Run as authenticated
-- user' 옵션 / 또는 app 에서 호출로 테스트.
SELECT grant_coins(3, 'purchase', 'coin_3', NULL, '3 코인 충전');
SELECT spend_coins(1, '<metrics-uuid>', '리포트 열람');

-- 이력 (본인 것만 반환됨)
SELECT kind, amount, balance_after, description, created_at
  FROM coins ORDER BY created_at DESC;
```

---

## 연관 문서

- [PLAN.md](PLAN.md) — Supabase 연동 계획 (Phase 1~3)
- [OUTPUT_SAMPLES.md](../runtime/OUTPUT_SAMPLES.md) — 분석 파이프라인 출력 및 저장 형태
- [OVERVIEW.md](../architecture/OVERVIEW.md) — 전체 아키텍처

---

## 🚀 ONE-SHOT CHEATSHEET (fresh DB, SQL Editor 한 번에 붙여넣기)

> `auth.users` 의 기존 카카오 test 계정은 Dashboard → Authentication → Users 에서 수동 삭제. 나머지 테이블·정책·함수는 이 쿼리 한 방으로 전부 재생성.

```sql
-- ============================================================
-- Face Reader — 전체 스키마 재생성 (metrics + users + coins + RPC)
-- 전제: public.metrics/users/coins, 관련 policy/trigger/function 전부 부재
-- ============================================================

-- 1) metrics -------------------------------------------------
CREATE TABLE metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  metrics_json TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('camera', 'album')),
  ethnicity TEXT NOT NULL,
  gender TEXT NOT NULL,
  age_group TEXT NOT NULL,
  alias TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_metrics_expires_at ON metrics (expires_at);
CREATE INDEX idx_metrics_user_id    ON metrics (user_id);

ALTER TABLE metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "metrics_public_read"  ON metrics FOR SELECT USING (true);
CREATE POLICY "metrics_owner_insert" ON metrics FOR INSERT
  WITH CHECK (user_id = auth.uid() OR user_id IS NULL);
CREATE POLICY "metrics_owner_update" ON metrics FOR UPDATE
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "metrics_owner_delete" ON metrics FOR DELETE
  USING (user_id = auth.uid());

-- 2) users (profile, 1:1 with auth.users) --------------------
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  kakao_user_id TEXT,
  nickname TEXT,
  profile_image_url TEXT,
  coins INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_self_read"   ON users FOR SELECT USING (id = auth.uid());
CREATE POLICY "users_self_update" ON users FOR UPDATE
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- 3) coins (ledger) ------------------------------------------
CREATE TABLE coins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('purchase', 'spend', 'bonus', 'refund')),
  amount INT NOT NULL,
  balance_after INT NOT NULL,
  product_id TEXT,
  store_transaction_id TEXT,
  reference_id TEXT,
  description TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_coin_user_created ON coins (user_id, created_at DESC);
CREATE UNIQUE INDEX idx_coin_store_tx ON coins (store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

ALTER TABLE coins ENABLE ROW LEVEL SECURITY;
CREATE POLICY "coins_self_read" ON coins FOR SELECT USING (user_id = auth.uid());

-- 4) signup trigger: profile + 3-coin bonus ------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nickname TEXT;
  v_avatar   TEXT;
  v_kakao_id TEXT;
BEGIN
  v_nickname := COALESCE(
    NEW.raw_user_meta_data->>'name',
    NEW.raw_user_meta_data->>'nickname',
    split_part(NEW.email, '@', 1)
  );
  v_avatar := COALESCE(
    NEW.raw_user_meta_data->>'avatar_url',
    NEW.raw_user_meta_data->>'picture'
  );
  v_kakao_id := NEW.raw_user_meta_data->>'provider_id';

  INSERT INTO public.users (id, kakao_user_id, nickname, profile_image_url, coins)
    VALUES (NEW.id, v_kakao_id, v_nickname, v_avatar, 3);

  INSERT INTO public.coins (user_id, kind, amount, balance_after, description)
    VALUES (NEW.id, 'bonus', 3, 3, '회원가입 보너스');

  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 5) Atomic RPCs (auth.uid() 기반, SECURITY DEFINER) ---------
CREATE OR REPLACE FUNCTION grant_coins(
  p_amount INT,
  p_kind TEXT,
  p_product_id TEXT DEFAULT NULL,
  p_store_transaction_id TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;
  IF p_kind NOT IN ('purchase','bonus','refund') THEN
    RAISE EXCEPTION 'invalid kind: %', p_kind;
  END IF;

  IF p_store_transaction_id IS NOT NULL THEN
    SELECT balance_after INTO v_balance
      FROM coins
      WHERE store_transaction_id = p_store_transaction_id AND user_id = v_uid
      LIMIT 1;
    IF v_balance IS NOT NULL THEN RETURN v_balance; END IF;
  END IF;

  UPDATE users SET coins = coins + p_amount
    WHERE id = v_uid
    RETURNING coins INTO v_balance;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'profile missing'; END IF;

  INSERT INTO coins
    (user_id, kind, amount, balance_after, product_id, store_transaction_id, description)
    VALUES (v_uid, p_kind, p_amount, v_balance, p_product_id, p_store_transaction_id, p_description);
  RETURN v_balance;
END; $$;

CREATE OR REPLACE FUNCTION spend_coins(
  p_amount INT,
  p_reference_id TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;

  UPDATE users SET coins = coins - p_amount
    WHERE id = v_uid AND coins >= p_amount
    RETURNING coins INTO v_balance;
  IF v_balance IS NULL THEN RETURN -1; END IF;

  INSERT INTO coins (user_id, kind, amount, balance_after, reference_id, description)
    VALUES (v_uid, 'spend', -p_amount, v_balance, p_reference_id, p_description);
  RETURN v_balance;
END; $$;

REVOKE EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)             FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)             TO authenticated;

-- 6) 만료 데이터 자동 정리 (optional) ------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule(
  'cleanup-expired-metrics',
  '0 3 * * *',
  $$DELETE FROM metrics WHERE expires_at < now()$$
);
```

### 확인 쿼리

```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
SELECT tablename, policyname, cmd FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;
SELECT proname FROM pg_proc WHERE proname IN ('handle_new_user','grant_coins','spend_coins');
```
