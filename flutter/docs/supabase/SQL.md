# Supabase — Face Reader 현재 스키마 SSOT

**마지막 업데이트**: 2026-04-24
**프로젝트 ref**: `jicaenyzunjdlcxcdbfb`

이 문서는 현재 Supabase DB 의 **실제 상태**를 그대로 기록한다. 마이그레이션 내역이 아니라 "지금 대시보드에 있는 것 그대로". 스키마를 바꿀 때는 이 파일을 함께 갱신한다.

Drop-recreate 를 두려워하지 말 것 — Flutter 측 Hive 는 schema 변경 시 clear 가 기본 정책이고, Supabase metrics 는 TTL 로 자동 만료된다.

---

## 접속

### Option 1 · Supabase Dashboard
- https://supabase.com/dashboard/project/jicaenyzunjdlcxcdbfb → **SQL Editor**
- 가장 간편. DDL 적용에 권장.

### Option 2 · psql
```bash
psql "postgresql://postgres.jicaenyzunjdlcxcdbfb:[password]@aws-0-[region].pooler.supabase.com:6543/postgres"
```

### Option 3 · GUI (Postico / TablePlus / DBeaver)
- Host: `db.jicaenyzunjdlcxcdbfb.supabase.co`
- Port: `5432` · DB: `postgres` · User: `postgres`
- Password: Dashboard → Settings → Database → Database password
- SSL: Required

---

## Tables

### `users` — 프로필 + 코인 잔액 (SoT)

`auth.users` 와 1:1. 가입 시 트리거로 자동 생성. `coins` 컬럼이 잔액 SoT — ledger(`public.coins`) 와 동기화는 `grant_coins`/`spend_coins` RPC 가 보장.

```sql
CREATE TABLE users (
  id                UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  kakao_user_id     TEXT,
  nickname          TEXT,
  profile_image_url TEXT,
  coins             INT         NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_self_read"   ON users FOR SELECT USING (id = auth.uid());
CREATE POLICY "users_self_update" ON users FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());
-- INSERT 는 handle_new_user 트리거 (SECURITY DEFINER) 만.
```

### `coins` — 코인 거래 ledger

`kind` 값:
- `purchase` — RevenueCat 결제
- `bonus`    — 가입 보너스 / 프로모션
- `refund`   — 환불 보정
- `spend`    — 기능 사용 차감 (`amount` 는 음수 저장)

`store_transaction_id` unique index 로 RevenueCat 영수증 중복 방지. `reference_id` 는 spend 시 무엇을 샀는지 (예: compat `pair_key`).

```sql
CREATE TABLE coins (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind                 TEXT        NOT NULL CHECK (kind IN ('purchase','spend','bonus','refund')),
  amount               INT         NOT NULL,
  balance_after        INT         NOT NULL,
  product_id           TEXT,
  store_transaction_id TEXT,
  reference_id         TEXT,
  description          TEXT,
  metadata             JSONB,
  created_at           TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX        idx_coin_user_created ON coins (user_id, created_at DESC);
CREATE UNIQUE INDEX idx_coin_store_tx     ON coins (store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

ALTER TABLE coins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coins_self_read" ON coins FOR SELECT USING (user_id = auth.uid());
-- INSERT/UPDATE/DELETE 정책 없음 — RPC 만 (SECURITY DEFINER) 경유.
```

### `metrics` — 관상 원본 + 공유 링크용 저장소

딥링크 공유를 위해 **SELECT 는 anon 공개** (UUID 를 가진 자만 열람), write 는 소유자만.

```sql
CREATE TABLE metrics (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  metrics_json TEXT        NOT NULL,
  source       TEXT        NOT NULL CHECK (source IN ('camera','album')),
  ethnicity    TEXT        NOT NULL,
  gender       TEXT        NOT NULL,
  age_group    TEXT        NOT NULL,
  alias        TEXT,
  expires_at   TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_metrics_expires_at ON metrics (expires_at);

ALTER TABLE metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "metrics_public_read"  ON metrics FOR SELECT USING (true);
CREATE POLICY "metrics_owner_insert" ON metrics FOR INSERT WITH CHECK (user_id = auth.uid() OR user_id IS NULL);
CREATE POLICY "metrics_owner_update" ON metrics FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "metrics_owner_delete" ON metrics FOR DELETE USING (user_id = auth.uid());
```

#### 만료 자동 정리 (optional, pg_cron)

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  'cleanup-expired-metrics',
  '0 3 * * *',
  $$DELETE FROM metrics WHERE expires_at < now()$$
);
```

### `unlocks` — 궁합 카드 해제 내역

리스트의 각 (my × album) 페어는 기본 **lock**. `unlock_compat` RPC 가 코인 1 개 차감 + 이 테이블에 row insert 를 한 트랜잭션으로 수행. client 는 이 테이블을 읽어 "어떤 페어가 unlock 인지" 판정.

```sql
CREATE TABLE unlocks (
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pair_key   TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, pair_key)
);

ALTER TABLE unlocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "unlocks_self_read" ON unlocks
  FOR SELECT USING (user_id = auth.uid());
-- INSERT/DELETE 정책 없음 — unlock_compat RPC 만.
```

**pair_key 규칙** (client 가 생성): `${my.supabaseId}::${album.supabaseId}` — 비대칭 (나 × 상대), 순서 고정. 두 report 모두 `supabaseId` 가 할당된 뒤에만 unlock 시도.

---

## Triggers

### `handle_new_user` — 가입 시 프로필 + 보너스 3 코인

`auth.users` 에 insert 가 일어날 때 `public.users` 행 + `public.coins` ledger row 자동 생성. Kakao 로그인에서 넘어오는 메타데이터(`name`, `nickname`, `avatar_url`, `picture`, `provider_id`) 를 유연하게 수용.

```sql
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```

---

## RPCs

모든 RPC 는 `auth.uid()` 를 세션의 진실로 삼는다. `p_user_id` 같은 파라미터 **없음** — 타인 계정 조작 차단. `SECURITY DEFINER` 로 RLS 우회해 내부 insert 를 수행한다.

### `grant_coins` — 코인 적립

RevenueCat 결제 · 보너스 · 환불 보정에 사용. `store_transaction_id` 가 주어지면 해당 거래가 이미 기록됐는지 먼저 확인해 **영수증 중복 방지**.

```sql
CREATE OR REPLACE FUNCTION grant_coins(
  p_amount               INT,
  p_kind                 TEXT,
  p_product_id           TEXT DEFAULT NULL,
  p_store_transaction_id TEXT DEFAULT NULL,
  p_description          TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_balance INT;
BEGIN
  IF v_uid IS NULL      THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_amount <= 0      THEN RAISE EXCEPTION 'amount must be positive'; END IF;
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
```

### `spend_coins` — 코인 차감 (범용)

반환값: 성공 시 새 잔액, 잔액 부족 시 `-1`.

```sql
CREATE OR REPLACE FUNCTION spend_coins(
  p_amount       INT,
  p_reference_id TEXT DEFAULT NULL,
  p_description  TEXT DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
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
```

### `unlock_compat` — 궁합 카드 해제 (코인 1 차감)

원자 단위로: ①이미 해제됐는지 확인 → 그러면 잔액만 반환 (idempotent), ②잔액 1 이상이면 차감, ③`unlocks` insert, ④`coins` ledger 에 `spend` 기록.

반환값: 성공·기해제 시 새 잔액, 잔액 부족 시 `-1`.

```sql
CREATE OR REPLACE FUNCTION unlock_compat(p_pair_key TEXT)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_balance INT;
  v_already BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_pair_key IS NULL OR length(p_pair_key) = 0 THEN
    RAISE EXCEPTION 'pair_key required';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM unlocks
    WHERE user_id = v_uid AND pair_key = p_pair_key
  ) INTO v_already;

  IF v_already THEN
    SELECT coins INTO v_balance FROM users WHERE id = v_uid;
    RETURN v_balance;
  END IF;

  UPDATE users SET coins = coins - 1
    WHERE id = v_uid AND coins >= 1
    RETURNING coins INTO v_balance;
  IF v_balance IS NULL THEN RETURN -1; END IF;

  INSERT INTO unlocks (user_id, pair_key) VALUES (v_uid, p_pair_key);

  INSERT INTO coins (user_id, kind, amount, balance_after, reference_id, description)
    VALUES (v_uid, 'spend', -1, v_balance, p_pair_key, 'compat-unlock');

  RETURN v_balance;
END; $$;
```

### 권한

RPC 는 로그인 사용자에게만 허용.

```sql
REVOKE EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)             FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION unlock_compat(TEXT)                      FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION grant_coins(INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT  EXECUTE ON FUNCTION spend_coins(INT, TEXT, TEXT)             TO authenticated;
GRANT  EXECUTE ON FUNCTION unlock_compat(TEXT)                      TO authenticated;
```

---

## 검증 스모크

```sql
-- 로그인된 세션에서 (Dashboard SQL Editor 는 'Run as authenticated' 체크)
SELECT coins FROM users WHERE id = auth.uid();
SELECT * FROM coins WHERE user_id = auth.uid() ORDER BY created_at DESC LIMIT 10;
SELECT * FROM unlocks WHERE user_id = auth.uid();

-- 잔액 부족 시 -1 확인
SELECT spend_coins(9999, 'test', 'smoke');

-- unlock 중복 호출 idempotent 확인
SELECT unlock_compat('test-pair-key');  -- 차감
SELECT unlock_compat('test-pair-key');  -- 잔액 그대로 (재차감 없음)
```

---

## 리셋 (dev only)

```sql
-- WARNING: 데이터 전부 날아감. prod 금지.
DROP TABLE IF EXISTS unlocks CASCADE;
DROP TABLE IF EXISTS coins          CASCADE;
DROP TABLE IF EXISTS metrics        CASCADE;
DROP TABLE IF EXISTS users          CASCADE;

DROP FUNCTION IF EXISTS unlock_compat(TEXT);
DROP FUNCTION IF EXISTS spend_coins(INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS grant_coins(INT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
```

Dashboard → Authentication → Users 의 기존 테스트 계정은 **수동 삭제** (auth.users 는 CASCADE 로도 안 지워짐).
