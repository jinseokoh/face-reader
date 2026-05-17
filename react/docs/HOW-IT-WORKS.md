# HOW-IT-WORKS — facely

`facely.kr` 의 Cloudflare Workers 앱. 책임을 **최소 두 가지** 로 좁힌다:

1. **R2 presign URL 발급** (`POST /api/r2/presign`) — 모바일 앱이 분석용 임시 이미지·공유 thumbnail 을 R2 에 직접 PUT 할 수 있도록 단기 SigV4 URL 만 발급. 객체 자체엔 손 안 댄다.
2. **공유 link 의 SSR host** (`GET /r/{uuid}`) — 받는 사람이 카톡에서 link 탭했을 때 OG 카드·리포트·딥링크·스토어 fallback. Supabase `metrics` 행을 **read-only** 로 fetch.

이미지 본체는 단 한 번도 Worker 메모리에 안 들어옴 (R2 직통 PUT, CDN GET). Worker 는 어떤 데이터도 Supabase 에 write 하지 않는다 — Flutter 가 직접 `metrics` 에 UPSERT 하고 Worker 는 그 행을 읽기만 한다 (왕복 최소화).

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
│        Flutter ──presign(thumbnails)──► Worker (signing only)        │
│        Flutter ──256 PUT──► R2 thumbnails/{YYYYMM}/{uuid}.jpg        │
│        Flutter ──UPSERT──► Supabase metrics (id=uuid)                │
│        Flutter ─[share_plus]─► https://facely.kr/r/{uuid}            │
│        (카톡 link / Instagram 이미지 — Worker 호출 0회)                │
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
- **이미지 본체는 R2 `thumbnails/` 에만; Supabase 엔 thumbnail key 포인터 + 비-식별 demographic / rawValue 만.** landmark 좌표·alias·사용자 이름·생년월일은 어떤 store 에도 안 들어감.
- **해석 엔진은 `shared/` 한 곳** — Flutter 와 Worker SSR 이 같은 Dart 코드를 컴파일된 JS 로 공유. 룰 변경 시 양쪽 동시 반영.
- **별도 `share_card` 테이블 없음.** 공유·재계산·OG 모두 기존 `metrics` 테이블의 `metrics_json` 한 곳을 source-of-truth 로 사용 (이전 plan 의 share_card 는 metrics 와 중복이라 폐기).
- **1 face capture = 1 UUID.** Flutter 가 analyze 시점에 v4 한 번 발급 → 그 uuid 가 `temp/{uuid}.jpg` → `thumbnails/{YYYYMM}/{uuid}.jpg` → `metrics.id` → `https://facely.kr/r/{uuid}` 까지 그대로 흐름. 단일 trace id 로 incident response·log grep 한 번에 끝. publish 단계에서 새 uuid 발급 금지.

---

## 2. 도메인·컴포넌트

| 호스트           | 책임                                                                             | 위치                                        | 비고                     |
| ---------------- | -------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------ |
| `facely.kr`      | Workers (R2 presign API + `GET /r/:uuid` SSR + OG + 딥링크 fallback) — write 0회 | Cloudflare Workers (이 repo)                | 메인                     |
| `www.facely.kr`  | 동일                                                                             | 동일                                        | 별칭                     |
| `cdn.facely.kr`  | R2 bucket 의 public read 호스팅 (`thumbnails/`)                                  | Cloudflare R2 custom domain                 | static asset CDN         |
| `meta.facely.kr` | Python FastAPI `/analyze`                                                        | 홈서버 Ubuntu (Docker + cloudflared tunnel) | DeepFace age/gender/race |

**Cloudflare 자원**:

- Workers 스크립트 `facely` (이 repo)
- R2 bucket `facely` — prefix 두 갈래:
  - `temp/{uuid}.jpg` — 분석용 임시. Python 이 즉시 삭제. lifecycle rule 로 1일 백업 정리.
  - `thumbnails/{YYYYMM}/{uuid}.jpg` — 영구 256×256.
- DNS records (Workers 자동 관리: facely.kr, www; tunnel: meta; R2: cdn)

**외부 자원**:

- Supabase Postgres + REST — `metrics` 테이블 (UUID PK, `metrics_json` JSONB, `expires_at`). PII 아님.
- App Store / Play Store — bundle ID `com.scienceintegration.facely`

---

## 3. 데이터 흐름 — 4 갈래

### 3.1 분석 (analyze pipeline)

> Flutter 는 **analyze 진입 시점에 UUID v4 를 한 번 발급**한다. 이 uuid 가
> `temp/{uuid}.jpg`, (분석 성공 시) `thumbnails/{YYYYMM}/{uuid}.jpg`, 그리고
> 이후 publish 시점의 `metrics.id` + `/r/{uuid}` 까지 그대로 흐른다. 단일
> capture 의 모든 부산물이 같은 trace id 로 묶임 — Flutter ↔ Worker ↔ Python ↔
> Supabase 로그 grep 한 번이면 끝.

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

한 줄 요약: **`key` = "bucket 안 어디에 있는지"** (S3/R2 저장소 객체식별자를 나타내는 universal 컨벤션), **`token` = "그 key 를 분석하러 갈 수 있는 5분짜리 통행증"** (Python `/analyze` 인증 한 용도).

응답 JSON 계약 (Python `/analyze` → Flutter) — **DeepFace raw 그대로, 매핑·정규화 0**:

```json
{
  "age": 28,
  "gender": "Man",
  "race": "asian"
}
```

Python 의 책임은 여기까지. decade 라벨링·소문자 정규화·`race → Ethnicity` enum 매핑·`gender → male/female` 변환 등 **모든 가공 책임은 소비자(Flutter)** 가 진다. Flutter 는 받은 raw 값을 자기 필요한 만큼만 쓰고 (예: `metrics_json.deepfaceAge/Gender/Race` 슬롯에 raw 그대로 보존, 사용자 선택 보정 UI 가 있으면 그 위에 overwrite), 안 쓰면 버린다.

실패 분기:

- presign 실패 / R2 PUT 실패 → Flutter 가 사용자에게 재시도 안내
- /analyze 401 (token expired) → presign 재요청 → 다시 시도
- /analyze 422 (no face) → 다른 사진 안내
- R2 DELETE 실패 → 그래도 JSON 반환 (Python 로그만). 1일 후 lifecycle 이 정리.

### 3.2 publish (공유 카드 발행)

> 여기서 사용하는 `<uuid>` 는 §3.1 의 analyze 시점에 이미 발급된 그 uuid 다.
> Flutter 는 `FaceReadingReport.supabaseId` 에 그 값을 들고 있으므로 publish
> 시점에 새로 생성하지 않는다. 결과적으로 `metrics.id`·`thumbnailKey` 의 uuid
> 부분·`/r/{uuid}` 가 모두 동일.

```
Flutter
  ├─ POST /api/r2/presign {prefix:"thumbnails", uuid}  → Worker (signing only)
  ├─ PUT (presigned, 256 JPG)                          → R2 thumbnails/{YYYYMM}/{uuid}.jpg
  │
  └─ Supabase REST UPSERT /rest/v1/metrics             → Supabase (anon key)
        body: { id: "<uuid>", metrics_json: { … thumbnailKey 포함 … }, expires_at }
        on conflict (id) do update set metrics_json = excluded.metrics_json,
                                        expires_at = excluded.expires_at
   ◄──── 200/201
  └─ share_plus("https://facely.kr/r/<uuid>")  ← Worker 호출 0 회
```

핵심: **Worker 측에 `/api/share` 같은 publish endpoint 가 존재하지 않는다.**

- metrics_json 의 payload 가 일반적으로 1.5–3 KB → Flutter 와 Supabase 사이에 한 번만 흐른다 (Worker 경유 시엔 두 번 흐름 → 폐기).
- Worker 는 어차피 Supabase 에 write 권한 없음. service-role key 비치 X.
- Supabase RLS 가 `metrics.insert` 를 anon 에 허용 (행에 PII 없음을 schema check 로 강제). 자세한 RLS 는 §5.2.

compat 카드는 publish 단계에서 metrics 에 추가 write 0회. 두 사람의 metrics 행은 이미 각자의 솔로 분석에서 UPSERT 되어 있다 (정상 case). 만약 한쪽 metrics 가 누락된 상태에서 compat 을 만들고 싶다면 그 한 사람의 솔로 publish 먼저 1회 — 평소 흐름과 동일. compat link 는 그저 두 UUID 를 SEP 으로 묶은 URL 일 뿐 (`/r/{A}~{B}`).

### 3.3 view-in-app (받는 사람 앱 보유)

```
받는 사람이 카톡에서 https://facely.kr/r/{id} 탭
   ({id} 는 단일 UUID = 관상, 또는 "{uuidA}~{uuidB}" = 궁합. SEP="~")
   │
   ▼
iOS:  AASA 검증 (apps[].appIDs == TEAMID.com.scienceintegration.facely
                   + paths == ["/r/*"]) → 앱 직접 launch
Android: assetlinks.json 검증 → app link → 앱 launch
   │
   ▼
Flutter: app_links package 가 incoming uri 수신
        → /r/{id} path 파싱 → SEP("~") split
        → 1개면 관상: metrics 1행 fetch → ReportPage
        → 2개면 궁합: metrics 2행 fetch → 궁합 engine → CompatReportPage
```

앱 미설치 case 로 fallthrough (3.4) 가능 — iOS 가 universal link 검증 실패하면 Safari 가 그냥 URL 열음.

### 3.4 view-on-web (받는 사람 앱 미설치)

```
GET https://facely.kr/r/{id}
   │ ({id} 를 SEP("~") 로 split → 1 또는 2 UUID)
   ▼
Worker SSR (app/routes/share.tsx)
   1. fetchMetrics(env, ids[])  // 1 또는 2 행
      → 404 (요청 id 중 하나라도 없음) → /r 404 페이지
      → 410 (어느 한 행이라도 expires_at 지남) → 410 페이지 + 신규 앱 CTA
   2. shared engine 호출
      ids.length === 1 (관상):
        out = runEngine(JSON.stringify({raw: row.metrics, demographic}))
        → archetype + top 3 attributes + chips
      ids.length === 2 (궁합):
        out = runCompat(JSON.stringify({a: rowA, b: rowB}))
        → 두 사람의 archetype + 궁합 score + 친밀/갈등 chips
      (어느 경우든 결과는 절대 DB 저장 X — 매 load 시 재계산)
   3. ShareCard / CompatCard 분기 + 본문 + CTA 렌더
   4. <head> meta:
        og:title    관상: "AI 관상가가 본 {archetype.primary}"
                    궁합: "{A.archetype} × {B.archetype} 의 궁합"
        og:image    관상: https://cdn.facely.kr/{rowA.thumbnailKey}
                    궁합: 합성 (두 thumbnail 합성 PNG) 또는 A 의 것
        og:url      https://facely.kr/r/{id}
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
관상:  https://facely.kr/r/{uuid}
                          └────┘
                          v4 UUID (Supabase metrics.id PK)

궁합:  https://facely.kr/r/{uuidA}~{uuidB}
                          └─────┘ └─────┘
                          metrics.id  metrics.id
                          (separator: "~" — RFC 3986 unreserved, percent-encode 안 됨, UUID 표준에 없음)
```

핵심:

- **route 1 개**: `/r/:id` 한 라우트가 두 케이스 다 처리. SEP(`~`) 가 있으면 split, 없으면 단일.
- **AASA 매칭 단순**: `paths: ["/r/*"]` 한 패턴이 두 케이스 다 매칭.
- **궁합은 metrics 에 어떤 흔적도 안 남김** — 두 UUID 를 SEP 으로 묶은 문자열 자체가 궁합 카드의 id. 같은 metrics 행이 N 개 페어에 그대로 참여 가능.
- 만료(410)·삭제는 `metrics.expires_at` 으로 관리. 궁합은 어느 한 행이라도 만료면 410.
- **separator 는 한 곳에서만 정의** — `app/lib/share-id.ts` 의 `PAIR_SEP = "~"` 상수. 향후 변경되면 그 한 곳만 수정.

이전(HMAC body+sig 토큰) 방식은 **폐기**.

### 4.2 Universal / App Links

`public/.well-known/apple-app-site-association` (AASA):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["TEAMID.com.scienceintegration.facely"],
        "paths": ["/r/*"]
      }
    ]
  }
}
```

`public/.well-known/assetlinks.json` (Android):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.scienceintegration.facely",
      "sha256_cert_fingerprints": ["<release SHA256>"]
    }
  }
]
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

### 5.2 Supabase `metrics` 스키마

`metrics` 는 이미 운영 중인 테이블 — 별도 `share_card` 신설 X. `metrics` 행은 **한 사람의 관상 측정 데이터만** 담는다 (1 face → 1 metrics row). 궁합·페어링 같은 관계형 메타는 일절 없음 — 궁합은 두 metrics UUID 를 URL 로 묶는 것 뿐 (§4.1 참조). 같은 metrics 행은 N 개 서로 다른 compat 페어에 그대로 참여할 수 있다 (write 0회).

```sql
-- 기존 테이블 (스키마 변경 없음)
create table if not exists metrics (
  id           uuid primary key default gen_random_uuid(),  -- 정상 경로는 client 가 명시. default 는 fallback only.
  metrics_json jsonb not null,
  expires_at   timestamptz                 -- null = 영구. 만료 정책에 사용.
);

create index if not exists metrics_expires_idx
  on metrics(expires_at) where expires_at is not null;
```

`metrics.id` 의 출처: Flutter 가 analyze 시점에 발급한 uuid 를 `FaceReadingReport.supabaseId` 로 들고 publish 시 그대로 UPSERT 한다. DB 의 `default gen_random_uuid()` 는 analyze 미경유 케이스(라이브 mesh-only 캡처·legacy entry)용 safety net — 정상 trace 에선 발동하지 않는다.

`metrics_json` payload 계약 (Flutter 가 채워서 Supabase REST UPSERT 로 직접 씀):

```jsonc
{
  "schemaVersion": 2,           // v1 → v2 bump: deepface* / thumbnailKey 추가
  "source": "camera",            // "camera" | "album"
  "timestamp": "2026-05-17T...",

  // Flutter 가 결정한 demographic (DeepFace raw 를 참고만; 최종은 Flutter 책임)
  "gender": "male",              // app Gender enum
  "ageGroup": "20s",             // "10s".."90s" decade 라벨 (Flutter 가 AgeGroup enum 을 이 포맷으로 직렬화)
  "ethnicity": "eastAsian",      // app Ethnicity enum

  // DeepFace raw (참고용, optional — Flutter 가 보존할지 버릴지 자유)
  "deepfaceAge": 28,             // int
  "deepfaceGender": "Man",       // raw "Man" | "Woman"
  "deepfaceRace": "asian",       // raw — 매핑 안 함

  // 분석 결과 (engine 재계산 input)
  "faceShape": "oval",
  "faceShapeLabel": "타원형",     // optional 한글
  "metrics": { "faceAspectRatio": 0.62, ... },  // mediapipe rawValue 17+
  "lateralMetrics": { "aquilineNose": 0.0, ... }, // optional

  // 1인 카드 자원
  "thumbnailKey": "thumbnails/202605/abc.jpg"
}
```

**저장 금지 (절대 metrics_json 에 안 들어감)**:

- 사용자 이름·alias·생년월일
- 얼굴 원본 이미지·landmark 좌표 (정규화된 rawValue 만; 좌표 X)
- archetype / 점수 / 친밀 챕터 본문 / 갈등 시나리오 본문 — engine 매 load 재계산 (react/CLAUDE.md §5)
- **관계형 메타**: `kind`, `partnerUuid`, `pairedWith`, `compat*` 등 — 1인 측정 데이터 외 압류. 페어링은 URL 이 표현.

Worker SSR 이 `metrics_json.metrics` + `lateralMetrics` 만으로 shared engine 을 호출해서 archetype·score 를 매번 산출. 룰 업데이트 시 과거 카드도 새 해석으로 자동 갱신.

**궁합 모델**: 별도 테이블·플래그·필드 없음. 두 사람이 각각 솔로 분석을 완료해 metrics A·B 행이 Supabase 에 존재할 때, 그 두 UUID 를 SEP(`~`) 으로 묶은 `https://facely.kr/r/{A}~{B}` 가 곧 compat 카드. Worker SSR (`/r/:id` 단일 route) 이 path 를 SEP 으로 split — 1 개면 관상, 2 개면 궁합. 후자는 `id=in.(A,B)` 한 번 호출 → 양쪽 raw 받아 shared 궁합 engine 에 던짐 → 페어 카드 렌더. compat publish 시 Supabase write 0회 (A·B metrics 는 이미 솔로 단계에서 UPSERT 된 상태).

### 5.3 RLS 정책

Flutter 가 직접 anon key 로 `metrics` UPSERT 를 하므로 RLS 로 PII 차단 + 행 변조 차단:

```sql
alter table metrics enable row level security;

-- 누구나 한 행 읽기 (UUID 모르면 fetch 불가하므로 사실상 link-share 모델)
create policy "metrics_read_anon" on metrics for select using (true);

-- anon INSERT/UPSERT — PII 없는 행만 허용
create policy "metrics_insert_anon" on metrics for insert with check (
  not (metrics_json ? 'username')
  and not (metrics_json ? 'alias')
  and not (metrics_json ? 'birthday')
  and not (metrics_json ? 'landmarks')
);

-- 자기 행만 UPDATE 가능 (anon 은 jwt 없으므로 사실상 불가; service-role 만)
create policy "metrics_update_none" on metrics for update using (false);

-- DELETE 차단; 만료는 expires_at + 별도 cron 으로
create policy "metrics_delete_none" on metrics for delete using (false);
```

`schemaVersion` 알 수 없는 값으로 INSERT 시도 시 Worker SSR 측에서 fetch 후 응답을 410 처리 (forward-compat).

---

## 6. 인증·보안

### 6.1 HMAC token (Worker ↔ Python ↔ Flutter)

- Cloudflare Worker 가 presign 응답에 `token` 함께 발행: `base64url(deadline_ms_8B || HMAC_SHA256(FACE_API_SECRET, deadline_ms || key))`
- Flutter 가 `/analyze` 요청에 `X-Face-Token` + `X-Face-Key` 헤더로 전달
- Python 이 동일 secret 으로 검증 (deadline 비교 + HMAC compare_digest)
- TTL 기본 5분 — presign URL 유효시간과 일치
- 같은 secret 을 `Worker.FACE_API_SECRET` + `Python.FACE_API_SECRET` 환경변수에 동일 값으로 주입

### 6.2 R2 credentials 분리

| 서비스  | R2 권한                                      | 사용                       |
| ------- | -------------------------------------------- | -------------------------- |
| Worker  | (없음) — S3 API key 로 presign signing only  | 객체 자체엔 손 안 댐       |
| Python  | bucket=facely, prefix=temp/, **DELETE only** | `/analyze` 후 즉시 cleanup |
| Flutter | (없음) — presigned URL 만 받아서 PUT         | secret 단말기에 없음       |

R2 API token 두 개 발급:

1. **Worker용** — Object Read & Write on bucket facely (presign 만들 권한)
2. **Python용** — Object Delete on prefix temp/ (cleanup 만)

### 6.3 Rate-limiting

Cloudflare WAF / Workers Rate Limit:

- `/api/r2/presign` — 60/min/IP
- `/r/{uuid}` — 안 걸어도 됨 (정적 SSR)

Supabase rate-limit (metrics UPSERT 는 Flutter 직통이므로):

- Supabase 프로젝트 기본 limit (free tier 60 req/s 정도) 로 충분. 비정상 트래픽은 Supabase 대시보드의 anon key abuse 감지에 의존.

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

| 경로                           | 역할                                                                        |
| ------------------------------ | --------------------------------------------------------------------------- |
| `workers/app.ts`               | RR7 createRequestHandler entry                                              |
| `app/routes.ts`                | 라우트 정의 (4 개)                                                          |
| `app/routes/_index.tsx`        | landing (dev 데모용)                                                        |
| `app/routes/share.tsx`         | `GET /r/:id` SSR loader (PAIR_SEP split → 1 또는 2 UUID) + meta + ShareCard/CompatCard |
| `app/lib/share-id.ts`          | `PAIR_SEP = "~"` + `parsePairId(id): string[]` 헬퍼 (관상·궁합 분기 SSOT)            |
| `app/routes/api.r2.presign.ts` | `POST /api/r2/presign` — SigV4 presign + HMAC token                         |
| `app/lib/supabase.ts`          | `fetchMetrics(env, ids[])` read-only REST helper (compat 도 multi-id 한 번) |

> Worker 가 metrics 에 write 하지 않음 → `/api/share` 같은 publish endpoint 는 일부러 만들지 않음. Flutter ↔ Supabase 직통.
> | `app/lib/traits.ts` | shared engine 호출 + RenderedShare 합성 |
> | `app/lib/shared/face_engine.js` | **commit 금지** build artifact |
> | `app/lib/types.ts` | ShareCardRow / RenderedShare / EngineOutput SSOT |
> | `app/components/ShareCard.tsx` | 카드 UI |
> | `app/components/CTA.tsx` | 1.5s deep link 시도 + 스토어 fallback |
> | `app/types/env.d.ts` | secret 타입 augmentation (cf-typegen 자동 보완 전 사용) |
> | `public/{male,female}.png` | 카드 portrait fallback (성별만 보고 swap) |
> | `public/logo.png` | OG static fallback (1200×630) |
> | `public/.well-known/{aasa,assetlinks}` | prod 직전 실값 |
> | `wrangler.jsonc` | env vars + assets binding + routes |

### Python (`python/`)

기존 — DeepFace `/analyze` + 즉시 R2 DELETE 추가 예정.

### Flutter (`flutter/`)

기존 + `lib/data/services/{r2_uploader,face_metadata_client,image_resizer}.dart`.

---

## 9. 환경 변수 정리

### Worker (`react/wrangler.jsonc` vars + secrets)

| 이름                                          | 종류   | 용도                                                                     |
| --------------------------------------------- | ------ | ------------------------------------------------------------------------ |
| `APP_LINK_BASE`                               | var    | 받는 사람 카드 안 link                                                   |
| `APP_STORE_URL` / `PLAY_STORE_URL`            | var    | 스토어 fallback                                                          |
| `APP_BUNDLE_ID_IOS` / `APP_BUNDLE_ID_ANDROID` | var    | 메타에 반영                                                              |
| `R2_ACCOUNT_ID`                               | var    | SigV4 endpoint host                                                      |
| `R2_BUCKET_NAME`                              | var    | `facely`                                                                 |
| `R2_CDN_BASE`                                 | var    | `https://cdn.facely.kr`                                                  |
| `FACE_TOKEN_TTL_SEC`                          | var    | `"300"`                                                                  |
| `R2_ACCESS_KEY_ID`                            | secret | Worker R2 API token                                                      |
| `R2_SECRET_ACCESS_KEY`                        | secret | Worker R2 API token                                                      |
| `FACE_API_SECRET`                             | secret | HMAC (Python 과 동일 값). presign 발급 시 함께 줘서 `/analyze` 호출 인증 |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY`          | var    | metrics REST `select` 만 (read-only). Worker 는 write 안 함              |

### Python (`python/docker-compose.yml` env)

| 이름                                                      | 용도                   |
| --------------------------------------------------------- | ---------------------- |
| `FACE_API_SECRET`                                         | Worker 와 동일 HMAC    |
| `R2_DELETE_ACCESS_KEY_ID` / `R2_DELETE_SECRET_ACCESS_KEY` | 즉시 삭제용 별도 token |
| `R2_ACCOUNT_ID` / `R2_BUCKET_NAME`                        | DELETE URL 조립        |
| `DETECTOR_BACKEND` / `MAX_DOWNLOAD_MB` / 등               | 기존                   |

### Flutter (`flutter/.env`)

| 이름                               | 용도                                                            |
| ---------------------------------- | --------------------------------------------------------------- |
| `SHARE_HOST_BASE`                  | `https://facely.kr` (presign + share publish + share link host) |
| `FACE_META_API_BASE`               | `https://meta.facely.kr` (DeepFace)                             |
| 기존 SUPABASE / KAKAO / REVENUECAT | 그대로                                                          |

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
- Worker 가 Supabase 에 write — **금지**. Worker 는 read-only. `/api/share` 같은 publish endpoint 도입 X. Flutter ↔ Supabase 직통.
- Worker 와 Flutter 사이에 metrics_json payload 왕복 — **금지** (큰 데이터 두 번 흐름). UUID 만 흐른다.
- Python `/analyze` 가 DeepFace raw (`{age, gender, race}`) 외 가공·매핑·정규화 응답 — **금지**. 모든 변환 책임은 소비자(Flutter).
- `metrics_json` 에 얼굴 원본 이미지·landmark 좌표·alias·사용자 이름·생년월일 저장 — **금지** (thumbnailKey 포인터만 허용; RLS check 로 강제).
- 별도 `share_card` 테이블 생성 — **금지**. 공유 payload 는 기존 `metrics` 한 테이블로.
- archetype·점수·rule 결과를 DB 에 저장 — **금지**. 매 load 시 shared engine 재계산.
- React 쪽 룰 재구현 — **금지**. `shared/` 한 곳만.
- Flutter 앱에 R2 secret·Supabase service-role key 박기 — **금지**. presigned URL + anon key 만.
- OG meta 를 client-only 로 주입 — **금지**. `route.meta` export 만.
- 친밀 챕터·갈등 시나리오 본문을 Worker 응답에 포함 — **금지** (앱 안에서만 생성).
- publish 단계에서 **새 UUID 발급** — **금지**. analyze 시점에 발급한 uuid 가 `temp/{uuid}.jpg` → `thumbnails/{YYYYMM}/{uuid}.jpg` → `metrics.id` → `/r/{uuid}` 까지 그대로 흐른다. `SupabaseService.saveMetrics` 의 `?? _uuid.v4()` fallback 은 analyze 미경유 케이스(라이브 mesh-only 캡처 등) 한정.
