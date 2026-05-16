# HOW-IT-WORKS — facely

`facely.kr` 의 Cloudflare Workers 앱. 두 가지 책임:

1. **모바일 앱의 사이드카** — DeepFace 분석을 위한 R2 presign URL 발급, Supabase 에 share_card 행 publish.
2. **공유 link 의 SSR host** — 받는 사람이 `facely.kr/r/{uuid}` 를 탭했을 때 OG 카드·리포트·딥링크·스토어 fallback 까지 모두 처리.

이미지는 단 한 번도 Worker 메모리에 안 들어옴 (R2 직통 PUT, CDN GET).

---

## 1. 큰 그림

```
┌─────────────────────────────────────────────────────────────────────┐
│                          [Flutter 앱]                                │
│                                                                     │
│  사진 촬영/앨범                                                       │
│   │                                                                 │
│   ├─(A) DeepFace 분석 파이프라인 → age/gender/race                    │
│   │    Flutter ──720 PUT──► R2 temp/{uuid}.jpg                       │
│   │    Flutter ──POST /analyze──► Python                             │
│   │      ├─ HMAC verify                                              │
│   │      ├─ DeepFace.analyze                                         │
│   │      ├─ R2 DELETE temp/{uuid}.jpg (즉시 삭제)                     │
│   │      └─ JSON 응답                                                │
│   │    [안전망] R2 lifecycle: temp/ 1일 자동 만료                     │
│   │                                                                 │
│   ├─(B) 로컬 face mesh + 엔진 → 리포트(archetype 등)                  │
│   │                                                                 │
│   └─(C) 공유 publish                                                 │
│        Flutter ──256 PUT──► R2 thumbnails/{YYYYMM}/{uuid}.jpg        │
│        Flutter ──POST /api/share──► Worker → Supabase share_card     │
│        Flutter ─[share_plus]─► 카톡(link) / Instagram(이미지)          │
└─────────────────────────────────────────────────────────────────────┘

                         ┌──────────────────────────┐
                         │  받는 사람이 카톡 link 탭    │
                         └──────────────────────────┘
                                       │
            ┌──────────────────────────┼───────────────────────────┐
            ▼                          ▼                           ▼
   카톡 크롤러 (서버사이드)     앱 설치된 device         앱 미설치 device
       │                              │                           │
   GET /r/{uuid}                Universal/App link          GET /r/{uuid}
       │                              │                           │
   Worker SSR                  앱 직접 open                Worker SSR
   → OG meta only              → app_links → /r/{uuid}     → 풀 리포트 + CTA
   (head 만 응답)               → Flutter ReportPage         → 1.5s deep link
                                                              시도 → 스토어 fallback
```

핵심 원칙:

- **OG meta 는 SSR 강제** — 카톡 크롤러는 JS 실행 안 함. 메타 데이터는 `route.meta` export 에만.
- **Worker 가 R2 객체를 read/write 하지 않음** — presign 발급만 (`/api/r2/presign`).
- **이미지·landmark·alias 같은 PII 는 Supabase 에 안 들어감** — `share_card` 테이블은 비-식별 데이터만.
- **해석 엔진은 `shared/` 한 곳** — Flutter 와 Worker SSR 이 같은 Dart 코드를 컴파일된 JS 로 공유. 룰 변경 시 양쪽 동시 반영.

---

## 2. 도메인·컴포넌트

| 호스트 | 책임 | 위치 | 비고 |
|---|---|---|---|
| `facely.kr` | Workers SSR (OG, 리포트, 딥링크 fallback, presign API, share publish API) | Cloudflare Workers (이 repo) | 메인 |
| `www.facely.kr` | 동일 | 동일 | 별칭 |
| `cdn.facely.kr` | R2 bucket 의 public read 호스팅 (`thumbnails/`) | Cloudflare R2 custom domain | static asset CDN |
| `meta.facely.kr` | Python FastAPI `/analyze` | 홈서버 Ubuntu (Docker + cloudflared tunnel) | DeepFace age/gender/race |

**Cloudflare 자원**:
- Workers 스크립트 `facely` (이 repo)
- R2 bucket `facely` — prefix 두 갈래:
  - `temp/{uuid}.jpg` — 분석용 임시. Python 이 즉시 삭제. lifecycle rule 로 1일 백업 정리.
  - `thumbnails/{YYYYMM}/{uuid}.jpg` — 영구 256×256.
- DNS records (Workers 자동 관리: facely.kr, www; tunnel: meta; R2: cdn)

**외부 자원**:
- Supabase Postgres + REST — `share_card` 테이블 (UUID 인덱스, 비-PII)
- App Store / Play Store — bundle ID `com.scienceintegration.facely`

---

## 3. 데이터 흐름 — 4 갈래

### 3.1 분석 (analyze pipeline)

```
Flutter                              Worker                          Python
  │                                                                    │
  │ 1. POST /api/r2/presign {prefix:"temp",uuid,...}                   │
  ├──────────────────────────────────► .                               │
  │                                    │ aws4fetch SigV4               │
  │                                    │ HMAC(secret, ts+key)          │
  │ ◄──────────────────────────────────┤                               │
  │ {uploadUrl, publicUrl, key, token}                                 │
  │                                                                    │
  │ 2. PUT 720px JPG → R2 temp/{uuid}.jpg (presigned URL 직통)         │
  │                                                                    │
  │ 3. POST /analyze {image_url:publicUrl}                              │
  │    headers: X-Face-Token, X-Face-Key                                │
  ├────────────────────────────────────────────────────────────────────►
  │                                                                    │ HMAC verify
  │                                                                    │ download → DeepFace
  │                                                                    │ R2 DELETE temp/{uuid}.jpg
  │                                                                    │ (R2 credential: 별도 DELETE-only 토큰)
  │ ◄────────────────────────────────────────────────────────────────┤
  │ {age:28, gender:"Man", race:"asian"}                                │
```

실패 분기:
- presign 실패 / R2 PUT 실패 → Flutter 가 사용자에게 재시도 안내
- /analyze 401 (token expired) → presign 재요청 → 다시 시도
- /analyze 422 (no face) → 다른 사진 안내
- R2 DELETE 실패 → 그래도 JSON 반환 (Python 로그만). 1일 후 lifecycle 이 정리.

### 3.2 publish (공유 카드 발행)

```
Flutter ──256px resize──► R2 thumbnails/{YYYYMM}/{uuid}.jpg
   │
   ├─ POST /api/r2/presign {prefix:"thumbnails",uuid}  → Worker
   ├─ PUT (presigned)                                  → R2
   │
   └─ POST /api/share { uuid, kind, demographic, faceShape, archetype, thumbnailKey, rawMetrics }
      ├──► Worker
      │     └─ Supabase INSERT share_card
      ◄──── { ok: true, url: "https://facely.kr/r/{uuid}" }
```

Worker 가 publish 시 검증:
- request 가 모바일 앱에서 옴을 증명하기 위해 HMAC 토큰 헤더 (`X-Face-Token`) 동일 메커니즘 활용. presign 발급 시 토큰을 같이 줬으니 같은 세션 안에서 재사용.
- 절대 저장하지 않음: 이미지·landmark·사용자 이름·alias·생년월일·세부 위경도.

### 3.3 view-in-app (받는 사람 앱 보유)

```
받는 사람이 카톡에서 https://facely.kr/r/{uuid} 탭
   │
   ▼
iOS:  AASA 검증 (apps[].appIDs == TEAMID.com.scienceintegration.facely
                   + paths == ["/r/*"]) → 앱 직접 launch
Android: assetlinks.json 검증 → app link → 앱 launch
   │
   ▼
Flutter: app_links package 가 incoming uri 수신
        → /r/{uuid} path 파싱
        → Supabase 에서 share_card fetch
        → 본인 앱의 ReportPage 로 navigate
```

앱 미설치 case 로 fallthrough (3.4) 가능 — iOS 가 universal link 검증 실패하면 Safari 가 그냥 URL 열음.

### 3.4 view-on-web (받는 사람 앱 미설치)

```
GET https://facely.kr/r/{uuid}
   │
   ▼
Worker SSR (app/routes/share.tsx)
   1. Supabase fetch share_card WHERE uuid = {uuid}
      → 404 → /r 404 페이지
      → 410 (만료/삭제) → 410 페이지 + 신규 앱 CTA
   2. shared engine 호출:
        out = runEngine(JSON.stringify({raw, demographic}))
        → archetype + top 3 attributes + chips
   3. ShareCard 컴포넌트 + 본문 + CTA 렌더
   4. <head> meta:
        og:title    "AI 관상가가 본 {archetype.primary}"
        og:image    https://cdn.facely.kr/thumbnails/{YYYYMM}/{uuid}.jpg
        og:url      https://facely.kr/r/{uuid}
        twitter:card summary_large_image
   5. CTA.tsx
        useEffect: 1.5s universal/app link 시도 (window.location.href = ...)
        실패 → store fallback (UA detect: iOS → APP_STORE_URL, Android → PLAY_STORE_URL)
```

**카톡 크롤러 분기**: 같은 SSR 결과를 반환하면 됨 — crawler 가 head 의 OG 만 읽고 본문은 무시. JS 실행 안 함 → CTA 의 1.5s 자동 deep-link 도 영향 X.

---

## 4. URL & deep linking

### 4.1 URL 구조

```
https://facely.kr/r/{uuid}
                  └────┘
                  v4 UUID (Supabase share_card.uuid PK)
```

이전(HMAC body+sig 토큰) 방식은 **폐기**. UUID 단순화 이유:
- share_card 행이 어차피 Supabase 에 존재 — 토큰 안에 페이로드 중복 저장 불필요.
- UUID 가 짧음 (36자 vs token 60+자).
- 만료(410)·삭제는 Supabase 행에서 관리.

### 4.2 Universal / App Links

`public/.well-known/apple-app-site-association` (AASA):
```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appIDs": ["TEAMID.com.scienceintegration.facely"],
      "paths": ["/r/*"]
    }]
  }
}
```

`public/.well-known/assetlinks.json` (Android):
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.scienceintegration.facely",
    "sha256_cert_fingerprints": ["<release SHA256>"]
  }
}]
```

두 파일은 prod 배포 직전 실값 (TEAMID, signing cert SHA256) 교체 필요.

Flutter 측:
- `ios/Runner/Runner.entitlements` 의 `com.apple.developer.associated-domains` 에 `applinks:facely.kr`
- `android/app/src/main/AndroidManifest.xml` 의 `intent-filter android:autoVerify="true"` + `<data android:host="facely.kr" android:pathPattern="/r/.*">`
- `app_links` 패키지가 `getInitialAppLink()` + `uriLinkStream` 으로 수신

---

## 5. 저장소

### 5.1 R2 layout

```
bucket: facely
├── temp/                         ← 분석용 임시
│   └── {uuid}.jpg                  Python 이 즉시 DELETE
│                                   lifecycle 룰: ExpirationInDays=1 (백업 정리)
└── thumbnails/                   ← 영구 256×256
    └── {YYYYMM}/
        └── {uuid}.jpg              Worker 가 buildKey 에서 YYYYMM 자동 산출
                                    cdn.facely.kr 로 public read
```

### 5.2 Supabase `share_card` 스키마

```sql
create table share_card (
  uuid           uuid primary key default gen_random_uuid(),
  created_at     timestamptz default now(),
  expires_at     timestamptz,                 -- 만료 정책. null = 영구
  kind           text not null check (kind in ('solo','compat')),

  -- 데모그래픽 (비-PII)
  gender         text not null check (gender in ('male','female')),
  age_group      text not null,               -- "30s" 등
  ethnicity      text not null,               -- "east_asian" 등

  -- 분석 결과
  face_shape     text,                        -- "oval" 등 ML classifier 결과
  archetype_pri  text,                        -- primary archetype id
  archetype_sec  text,                        -- secondary id
  special_arch   text,                        -- nullable special archetype

  -- engine 재계산용 input (rawValue 만 — z-score·해석은 매 load 시 재계산)
  raw_metrics    jsonb not null,              -- {faceAspectRatio: 0.62, ...}
  lateral_flags  jsonb,                       -- {aquilineNose: false, ...}

  -- compat 전용 (kind='compat' 일 때만)
  partner_uuid   uuid references share_card(uuid),

  -- thumbnail
  thumbnail_key  text not null                -- "thumbnails/202605/abc.jpg"
);

create index share_card_expires_idx on share_card(expires_at) where expires_at is not null;
```

**금지 컬럼** (이 테이블엔 절대 안 들어감):
- 사용자 이름·alias·생년월일
- 얼굴 이미지·landmark 좌표
- 친밀 챕터 본문·갈등 시나리오 본문 (앱 안에서만 생성)

`raw_metrics` 가 있으면 Worker SSR 이 매번 shared engine 으로 재계산. 룰 업데이트 시 과거 카드도 새 해석으로 자동 갱신 (저장된 archetype 컬럼은 캐시일 뿐).

---

## 6. 인증·보안

### 6.1 HMAC token (Worker ↔ Python ↔ Flutter)

- Cloudflare Worker 가 presign 응답에 `token` 함께 발행: `base64url(deadline_ms_8B || HMAC_SHA256(FACE_API_SECRET, deadline_ms || key))`
- Flutter 가 `/analyze` 요청에 `X-Face-Token` + `X-Face-Key` 헤더로 전달
- Python 이 동일 secret 으로 검증 (deadline 비교 + HMAC compare_digest)
- TTL 기본 5분 — presign URL 유효시간과 일치
- 같은 secret 을 `Worker.FACE_API_SECRET` + `Python.FACE_API_SECRET` 환경변수에 동일 값으로 주입

### 6.2 R2 credentials 분리

| 서비스 | R2 권한 | 사용 |
|---|---|---|
| Worker | (없음) — S3 API key 로 presign signing only | 객체 자체엔 손 안 댐 |
| Python | bucket=facely, prefix=temp/, **DELETE only** | `/analyze` 후 즉시 cleanup |
| Flutter | (없음) — presigned URL 만 받아서 PUT | secret 단말기에 없음 |

R2 API token 두 개 발급:
1. **Worker용** — Object Read & Write on bucket facely (presign 만들 권한)
2. **Python용** — Object Delete on prefix temp/ (cleanup 만)

### 6.3 Rate-limiting

Cloudflare WAF / Workers Rate Limit:
- `/api/r2/presign` — 60/min/IP
- `/api/share` — 30/min/IP
- `/r/{uuid}` — 안 걸어도 됨 (정적 SSR)

---

## 7. Shared engine — Dart → JS 컴파일

```
shared/lib/face_engine.dart            ← SSOT (모든 룰·reference·quantile)
        │
        │ pnpm build:shared
        │ = dart compile js -O1 ../shared/lib/face_engine.dart -o app/lib/shared/face_engine.js
        ▼
react/app/lib/shared/face_engine.js    ← build artifact (.gitignore)
        │
        │ import (side-effect: globalThis.runEngine / runCompat 등록)
        ▼
react/app/lib/traits.ts                ← out = JSON.parse(globalThis.runEngine(JSON.stringify(raw)))
        │
        ▼
share.tsx SSR 렌더링
```

**룰·reference·quantile 수정 시 절대 React 쪽에서 재구현 금지.** `shared/` 한 번만 수정 → `pnpm build:shared` → 양쪽 자동 반영.

Flutter 측은 `pubspec.yaml` 에 `path: ../shared` 의존으로 들고 옴 — 그쪽은 compile 불필요.

---

## 8. 디렉토리 SSOT

### react/

| 경로 | 역할 |
|---|---|
| `workers/app.ts` | RR7 createRequestHandler entry |
| `app/routes.ts` | 라우트 정의 (4 개) |
| `app/routes/_index.tsx` | landing (dev 데모용) |
| `app/routes/share.tsx` | `GET /r/:uuid` SSR loader + meta + ShareCard |
| `app/routes/api.share.ts` | `POST /api/share` — share_card publish |
| `app/routes/api.r2.presign.ts` | `POST /api/r2/presign` — SigV4 presign + HMAC token |
| `app/lib/supabase.ts` | `fetchShareCard(env, uuid)` REST helper |
| `app/lib/traits.ts` | shared engine 호출 + RenderedShare 합성 |
| `app/lib/shared/face_engine.js` | **commit 금지** build artifact |
| `app/lib/types.ts` | ShareCardRow / RenderedShare / EngineOutput SSOT |
| `app/components/ShareCard.tsx` | 카드 UI |
| `app/components/CTA.tsx` | 1.5s deep link 시도 + 스토어 fallback |
| `app/types/env.d.ts` | secret 타입 augmentation (cf-typegen 자동 보완 전 사용) |
| `public/{male,female}.png` | 카드 portrait fallback (성별만 보고 swap) |
| `public/logo.png` | OG static fallback (1200×630) |
| `public/.well-known/{aasa,assetlinks}` | prod 직전 실값 |
| `wrangler.jsonc` | env vars + assets binding + routes |

### Python (`python/`)

기존 — DeepFace `/analyze` + 즉시 R2 DELETE 추가 예정.

### Flutter (`flutter/`)

기존 + `lib/data/services/{r2_uploader,face_metadata_client,image_resizer}.dart`.

---

## 9. 환경 변수 정리

### Worker (`react/wrangler.jsonc` vars + secrets)

| 이름 | 종류 | 용도 |
|---|---|---|
| `APP_LINK_BASE` | var | 받는 사람 카드 안 link |
| `APP_STORE_URL` / `PLAY_STORE_URL` | var | 스토어 fallback |
| `APP_BUNDLE_ID_IOS` / `APP_BUNDLE_ID_ANDROID` | var | 메타에 반영 |
| `R2_ACCOUNT_ID` | var | SigV4 endpoint host |
| `R2_BUCKET_NAME` | var | `facely` |
| `R2_CDN_BASE` | var | `https://cdn.facely.kr` |
| `FACE_TOKEN_TTL_SEC` | var | `"300"` |
| `R2_ACCESS_KEY_ID` | secret | Worker R2 API token |
| `R2_SECRET_ACCESS_KEY` | secret | Worker R2 API token |
| `FACE_API_SECRET` | secret | HMAC (Python 과 동일 값) |
| `SHARE_TOKEN_SECRET` | secret | 구 토큰 — UUID 전환 후 제거 가능 |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | var | REST 호출 |

### Python (`python/docker-compose.yml` env)

| 이름 | 용도 |
|---|---|
| `FACE_API_SECRET` | Worker 와 동일 HMAC |
| `R2_DELETE_ACCESS_KEY_ID` / `R2_DELETE_SECRET_ACCESS_KEY` | 즉시 삭제용 별도 token |
| `R2_ACCOUNT_ID` / `R2_BUCKET_NAME` | DELETE URL 조립 |
| `DETECTOR_BACKEND` / `MAX_DOWNLOAD_MB` / 등 | 기존 |

### Flutter (`flutter/.env`)

| 이름 | 용도 |
|---|---|
| `SHARE_HOST_BASE` | `https://facely.kr` (presign + share publish + share link host) |
| `FACE_META_API_BASE` | `https://meta.facely.kr` (DeepFace) |
| 기존 SUPABASE / KAKAO / REVENUECAT | 그대로 |

---

## 10. 배포 흐름 요약

```
1. shared/ Dart 룰 변경
   → cd react && pnpm build:shared
2. (필요시) Flutter 빌드 / Worker typecheck
3. Worker: pnpm wrangler deploy
4. Python: cd python && docker compose up -d --build
5. Flutter: 평소 빌드 → 스토어 업로드
```

R2 lifecycle / Supabase 스키마 변경은 별도 절차 (대시보드 또는 마이그레이션 SQL).

---

## 11. 절대 금지 (regression 차단용 chunk)

- 모바일 이미지가 Worker 경유 (Workers 의 R2 binding 으로 PUT) — **금지**. 모바일 ↔ R2 직통 PUT.
- `share_card` 에 이미지·landmark·alias·생년월일 저장 — **금지**.
- React 쪽 룰 재구현 — **금지**. `shared/` 한 곳만.
- Flutter 앱에 R2 secret 박기 — **금지**. presigned URL 만 단기 발급.
- OG meta 를 client-only 로 주입 — **금지**. `route.meta` export 만.
- 친밀 챕터·갈등 시나리오 본문을 Worker 응답에 포함 — **금지** (앱 안에서만 생성).
