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

```sql
-- Enable RLS
ALTER TABLE metrics ENABLE ROW LEVEL SECURITY;

-- Allow anonymous insert (app uses anon key)
CREATE POLICY "allow_anon_insert"
  ON metrics
  FOR INSERT
  WITH CHECK (true);

-- Allow anonymous select by ID (for shared links)
CREATE POLICY "allow_anon_select"
  ON metrics
  FOR SELECT
  USING (true);
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

## Phase 3 (나중에): users table

카카오 로그인 도입 시 추가:

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kakao_user_id TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add user_id column to metrics
ALTER TABLE metrics ADD COLUMN user_id UUID REFERENCES users(id);
CREATE INDEX idx_metrics_user_id ON metrics (user_id);

-- RLS for users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_anon_insert_users"
  ON users
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "allow_select_own_user"
  ON users
  FOR SELECT
  USING (true);
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

## 연관 문서

- [SUPABASE_PLAN.md](SUPABASE_PLAN.md) — Supabase 연동 계획 (Phase 1~3)
- [ANALYSIS.md](ANALYSIS.md) — 분석 파이프라인 출력 및 저장 형태
- [ARCHITECTURE.md](ARCHITECTURE.md) — 전체 아키텍처
