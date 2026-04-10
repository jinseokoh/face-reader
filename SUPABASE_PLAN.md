# Supabase Integration Plan — Face Reader App

## Context

Face Reader(관상앱)는 엔터테인먼트 목적의 경량 앱으로, 카메라/앨범 기반 관상 분석 결과를 Supabase에 저장하고 카카오 공유하기 + 딥링크를 통해 공유하는 기능을 추가한다. 궁합 리포트 등 유료 기능도 계획 중.

## 확정된 결정사항

| 항목 | 결정 |
|------|------|
| Credentials | `flutter_dotenv` + `.env` |
| Auth | Phase 1은 사용자 식별 없음. Phase 3에서 카카오 로그인 도입 |
| DB 구조 | `metrics` 테이블 1개 (users 테이블은 Phase 3에서 추가) |
| 로컬 저장 | Hive 제거, 필요 시 shared_preferences만 사용 |
| 웹앱 | React (Vite) — 별도 프로젝트 |
| 결제 | 인앱 결제 (Google Play / App Store IAP) |
| Supabase URL | `https://jicaenyzunjdlcxcdbfb.supabase.co` |

## Phase 1: Flutter 앱 + Supabase 연동 (이번 작업)

### 1.1 패키지 추가/제거

```yaml
# pubspec.yaml — 추가
dependencies:
  flutter_dotenv: ^5.2.1
  supabase_flutter: ^2.8.4
  uuid: ^4.5.1

# pubspec.yaml — 제거
  hive_ce: ^2.19.3
```

### 1.2 환경 변수 설정

**`.env` (프로젝트 루트)**
```
SUPABASE_URL=https://jicaenyzunjdlcxcdbfb.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**`.gitignore`에 `.env` 추가**

**`pubspec.yaml` assets에 `.env` 등록**

### 1.3 Supabase 테이블 스키마

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

ALTER TABLE metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_insert" ON metrics FOR INSERT WITH CHECK (true);
CREATE POLICY "allow_select_by_id" ON metrics FOR SELECT USING (true);
```

### 1.4 Flutter 코드 변경

**`main.dart` — 초기화 순서**
```
WidgetsFlutterBinding.ensureInitialized()
→ await dotenv.load()
→ await Supabase.initialize(url, anonKey)
→ runApp()
```
Hive 초기화 제거.

**새 파일: `lib/data/services/supabase_service.dart`**
- `saveMetrics(FaceReadingReport report)` → metrics에 insert, UUID 반환
- `getMetrics(String uuid)` → 공유 링크용 단건 조회
- `getMetricsPair(String uuid1, String uuid2)` → 궁합용 2건 조회

**`face_mesh_page.dart` / `album_preview_page.dart`**
- 분석 완료 후 `saveMetrics(report)` 호출

**히스토리**
- 기존 인메모리 `historyProvider` 유지 (앱 종료 시 초기화 — OK for entertainment app)
- Supabase는 공유/딥링크용 원격 저장소

### 1.5 카카오 공유하기

- 딥링크 URL: `https://face.whatsupkorea.com/report/{uuid}`
- 궁합: `https://face.whatsupkorea.com/compat/{uuid1}/{uuid2}`

### 1.6 딥링크 (Universal Links / App Links)

- 앱 설치 시: 앱 내 리포트 페이지
- 앱 미설치 시: React 웹앱 (부분 리포트 + 앱 설치 유도)

## Phase 2: React 웹앱 (나중에)

## Phase 3: 유료 기능 (나중에)
- 카카오 로그인 → `users` 테이블 추가 + `metrics.user_id` 컬럼 추가
- 인앱 결제

## 수정 대상 파일

| 파일 | 변경 내용 |
|------|-----------|
| `pubspec.yaml` | flutter_dotenv, supabase_flutter, uuid 추가; hive_ce 제거 |
| `.env` (신규) | SUPABASE_URL, SUPABASE_ANON_KEY |
| `.gitignore` | .env 추가 |
| `lib/main.dart` | dotenv + Supabase 초기화; Hive 제거 |
| `lib/core/hive/hive_init.dart` | 제거 |
| `lib/data/services/supabase_service.dart` (신규) | Supabase CRUD |
| `lib/presentation/screens/home/face_mesh_page.dart` | 분석 후 saveMetrics 호출 |
| `lib/presentation/screens/home/album_preview_page.dart` | 분석 후 saveMetrics 호출 |
| `lib/domain/models/face_reading_report.dart` | readingId (UUID) 필드 추가 |
| `lib/config/router.dart` | 딥링크 라우트 추가 |

## Verification

1. 앱 실행 → Supabase 연결 확인 (로그)
2. 카메라/앨범 분석 → metrics 테이블에 데이터 저장 확인 (Supabase Dashboard)
3. UUID로 단건 조회 동작 확인
4. .env가 git에 커밋되지 않는지 확인
