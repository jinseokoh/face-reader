# TO-DO — facely

`HOW-IT-WORKS.md` 의 아키텍처를 실제 배포 가능 상태로 만드는 작업 목록. P0 → P3 순.

각 항목에 **(파일/명령/책임)** 표기. 체크박스 켜진 건 완료, 빈 건 미완.

마지막 업데이트: 2026-05-17 (v3) — `metrics` 행은 **1인 측정 데이터만**. `kind`·`partnerUuid` 같은 compat 관계형 필드 폐기. 궁합은 두 metrics UUID 를 SEP(`~`) 으로 묶은 URL `https://facely.kr/r/{A}~{B}` 로만 표현 — Supabase write 0회. `/c/*` 별도 route 폐기, `/r/:id` 한 라우트가 두 케이스 split 처리.

---

## P0 — 즉시 (analyze 파이프라인 + 공유 link 의 최소 동작에 필수)

### Cloudflare 측

- [ ] **R2 bucket `facely` 생성** (Cloudflare 대시보드 → R2)
- [ ] **Lifecycle rule** 추가: `Prefix = temp/` / `Expiration = 1 day` (Python 즉시 삭제의 백업)
- [ ] **Custom domain `cdn.facely.kr`** → bucket public read 매핑 (또는 R2 dev URL 사용)
- [ ] **R2 API token #1 (Worker용)** — Object Read & Write, bucket=facely 한정. **Access Key ID / Secret Access Key / Endpoint URL** 확보 (`dash.cloudflare.com/<account-id>/r2/api-tokens` 경로 — 일반 `/profile/api-tokens` 아님)
- [ ] **R2 API token #2 (Python용)** — Object Read & Delete, bucket=facely + prefix=temp/ 한정
- [ ] **Worker secrets 등록**
  - `pnpm wrangler secret put R2_ACCESS_KEY_ID`
  - `pnpm wrangler secret put R2_SECRET_ACCESS_KEY`
  - `pnpm wrangler secret put FACE_API_SECRET` (32-byte hex, `openssl rand -hex 32`)
- [ ] **`pnpm cf-typegen`** → `worker-configuration.d.ts` 에 secret 들이 보이는지 확인. 보이면 `app/types/env.d.ts` 삭제 가능.
- [ ] **`wrangler.jsonc` 의 `R2_ACCOUNT_ID` placeholder** → 실제 account ID 로 교체 (대시보드 우상단).
- [x] **`wrangler.jsonc` routes** — facely.kr / www.facely.kr 바인딩 (`custom_domain: true`).
- [ ] **DNS 정리**: 기존 tunnel 레코드 `facely.kr` / `www` 삭제 → Worker 가 자동으로 custom_domain 으로 다시 만듦. `meta` tunnel 추가 (Python 호스트). `cdn` R2 매핑 활성.

### Python 서비스

- [x] `/analyze` HMAC 인증 dependency (이미 구현)
- [ ] **`/analyze` 응답 = DeepFace raw 그대로** — `{age:int, gender:"Man"|"Woman", race:string}` 만 반환. decade 라벨링·소문자·enum 매핑 등 가공 0. (소비자 Flutter 가 알아서 함.)
- [ ] **즉시 R2 DELETE 구현** — `python/app/services/deleter.py` (신규):
  ```python
  async def delete_temp_object(key: str) -> None:
      # SigV4 signed DELETE via httpx
      # endpoint: https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com/{R2_BUCKET_NAME}/{key}
  ```
  의존성: `httpx` (이미 있음) + 가벼운 SigV4 signer (직접 구현 25줄 또는 `aioboto3` 도입).
- [ ] **`/analyze` 끝에 `await delete_temp_object(key)`** (try/except — 실패해도 응답엔 영향 X, 로그만). `key` 는 헤더 `X-Face-Key` 로 이미 들어옴.
- [ ] **docker-compose env** 에 `R2_DELETE_ACCESS_KEY_ID`, `R2_DELETE_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`, `R2_BUCKET_NAME` 추가
- [ ] 같은 `FACE_API_SECRET` 값을 Worker secret 과 동일하게 셸 env 또는 `.env` 로 주입

### Supabase 스키마

- [x] **`metrics` 테이블** — 이미 존재 (id / metrics_json / expires_at). 별도 `share_card` 신설 X.
- [ ] **metrics_json schemaVersion v2 bump** — Flutter 의 `RawMetrics` 모델에 `thumbnailKey`, `deepfaceAge?`, `deepfaceGender?`, `deepfaceRace?` 필드 추가하고 v2 로 표시. DeepFace raw 는 Flutter 가 보존할지 버릴지 자유. **`kind`/`partnerUuid` 같은 compat 관계형 필드는 추가 금지** — 페어링은 URL 이 표현.
- [ ] **RLS 정책** (HOW-IT-WORKS §5.3 SQL 그대로) — `select` 전체 허용, `insert` anon 에 허용하되 PII 키 (`username/alias/birthday/landmarks`) 가 metrics_json 에 있으면 reject, `update`/`delete` 차단. Flutter 가 anon key 로 직접 UPSERT.
- [ ] **만료 정리 cron** — `expires_at < now()` 행 삭제. Supabase pg_cron 또는 별도 Worker cron trigger.

### Worker 신규/변경 라우트

- [x] **`POST /api/r2/presign`** — 이미 구현 (`app/routes/api.r2.presign.ts`)
- [x] **publish endpoint 없음** — `/api/share` 같은 라우트 의도적 미구현. Flutter ↔ Supabase 직통 UPSERT. (큰 payload 왕복 방지 + Worker write 권한 제거.) 기존 `app/routes/api.share.ts` 가 있다면 삭제.
- [ ] **`GET /r/:id`** 재작성 (`app/routes/share.tsx`) — 한 라우트가 관상·궁합 모두 처리:
  - `app/routes.ts` 의 path 를 `/r/:shortId` → `/r/:id` 로 변경
  - `app/lib/share-id.ts` 에 `PAIR_SEP = "~"` + `parsePairId(id): string[]` 헬퍼 (1 또는 2 UUID 반환)
  - `fetchMetrics(env, ids)` 호출 (1행 또는 2행) — 행 누락이면 404 / 하나라도 `expires_at` 지났으면 410
  - 1 행 → `shared/face_engine.js` 의 `runEngine` 호출 (관상)
  - 2 행 → `runCompat` 호출 (궁합 score + 친밀/갈등 chips)
  - `<head>` meta:
    - og:title — 관상은 archetype, 궁합은 "A × B 의 궁합"
    - og:image — 관상은 `${R2_CDN_BASE}/${thumbnailKey}`, 궁합은 1차 단계에선 A 의 것 (P1 에서 합성 PNG)
    - og:url — 원본 그대로
  - 본문 + CTA (CTA 의 deep link target = 같은 URL)
- [ ] **루트 페이지 `/`** — 간단한 랜딩 + 스토어 CTA (현 `_index.tsx` 의 dev 데모 토큰 발행 로직 제거)

### Flutter 측

- [x] R2Uploader / FaceMetadataClient / ImageResizer (이미 구현)
- [ ] **`AgeGroup` JSON 직렬화 변경** — `shared/lib/data/enums/age_group.dart` 에 `jsonValue` extension 추가 (`teens→"10s", twenties→"20s", ..., nineties→"90s"`). RawMetrics toJson 에서 `name` 대신 `jsonValue` 사용. fromJson 은 v1 호환 위해 두 포맷 모두 accept (`"twenties"` 도 받음, 신규는 `"20s"` 로 쓰기).
- [ ] **`FaceMetadata` 모델 확장** — DeepFace raw 응답 3 필드 (`age:int`, `gender:"Man"|"Woman"`, `race:string`) 를 `deepfaceAge/Gender/Race` 로 보존. app demographic enum 으로의 매핑은 Flutter 가 자체 책임 (사용자 보정 UI 가 최종).
- [ ] **`share_publisher.dart`** 재작성 — 1인 metrics 직접 UPSERT (Worker 미경유):
  1. analyze pipeline 완료 후 thumbnail 256px 까지 R2 PUT (presign + PUT)
  2. metrics_json 페이로드 조립 — **1인 측정 데이터만** (schemaVersion=2, thumbnailKey, deepface*?, 기존 rawMetrics, ageGroup="20s" 포맷). `kind`/`partnerUuid` 같은 compat 필드 추가 금지.
  3. Supabase REST `POST /rest/v1/metrics?on_conflict=id` (anon key, header `Prefer: resolution=merge-duplicates`) 로 UPSERT — 항상 1행
  4. **관상 공유**: `https://facely.kr/r/{uuid}` 를 `share_plus`
  5. **궁합 공유**: 두 사람 metrics 가 이미 둘 다 publish 되어 있다는 전제 (정상 case). `share_plus("https://facely.kr/r/${uuidA}${PAIR_SEP}${uuidB}")` — 추가 Supabase write 0회. `PAIR_SEP` 상수는 shared 패키지에 두고 Worker 의 `share-id.ts` 와 동일 값 유지.
- [ ] **인스타용 카드 이미지 생성** — `RepaintBoundary` 로 1080×1350 PNG → `share_plus(files: [bytes])` Instagram 인텐트
- [ ] **deep link 수신** — `app_links` 패키지 + main.dart 에서 `getInitialAppLink()` + stream 구독 → `/r/{id}` path 추출 → `PAIR_SEP` split → 1개면 `ReportPage(uuid)` navigate, 2개면 `CompatReportPage(uuidA, uuidB)` navigate
- [ ] **iOS entitlements** (`ios/Runner/Runner.entitlements`):
  ```xml
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:facely.kr</string>
  </array>
  ```
- [ ] **Android manifest** (`android/app/src/main/AndroidManifest.xml`):
  ```xml
  <intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="facely.kr" android:pathPrefix="/r/"/>
  </intent-filter>
  ```

### Well-known 파일

- [ ] **AASA 실값** — `react/public/.well-known/apple-app-site-association`
  - `appIDs`: `<TEAMID>.com.scienceintegration.facely`
  - paths: `["/r/*"]`
- [ ] **assetlinks 실값** — `react/public/.well-known/assetlinks.json`
  - `package_name`: `com.scienceintegration.facely`
  - `sha256_cert_fingerprints`: release keystore SHA256 (Play Console → Setup → App integrity → App signing key)
- [ ] **MIME 타입 확인** — Cloudflare Workers assets 가 두 파일 모두 `application/json` 으로 응답하는지 (특히 AASA 는 확장자 없음에 주의)

---

## P1 — 다음 (배포 후 안정화)

### 콘텐츠

- [ ] **OG 카드 디자인** — 256×256 thumbnail + archetype 타이틀. `ShareCard.tsx` UI 정돈.
- [ ] **인스타 1080×1350 카드 디자인** — Flutter 측 `RepaintBoundary` 위젯. archetype·점수·간단 chip 3개 + 워터마크 "facely.kr".
- [ ] **CTA 카피** — 미설치 사용자가 facely.kr 에 도착했을 때 "앱에서 더 보기" / "내 관상 보기" 두 버튼.
- [ ] **만료(410) 페이지** — `metrics.expires_at` 지난 카드 접근 시 친절한 페이지 + 신규 분석 CTA.

### Worker SSR

- [ ] **shared engine 통합** — `app/lib/traits.ts` 가 `app/lib/shared/face_engine.js` 호출. `pnpm build:shared` 명령 작동 확인. CI 에 해당 단계 추가.
- [ ] **Solo vs Compat 분기** — URL 의 `PAIR_SEP` 유무 (1 UUID vs 2 UUID) 에 따라 ShareCard / CompatCard 컴포넌트 분기. metrics_json 안에는 어떤 분기 플래그도 없음.
- [ ] **fetch 실패 graceful** — Supabase 다운 / 5xx 시 retry-with-jitter 1회, 그래도 실패면 503 페이지.

### 운영

- [ ] **Rate limit** — Cloudflare WAF: `/api/r2/presign` 60/min/IP. (Supabase metrics UPSERT 는 직통이므로 Supabase 측 anon limit 으로 위임.)
- [ ] **로그 sanitization** — Worker log 에 UUID 가 안 찍히도록 (분석 디버깅 외엔). Supabase service key 절대 노출 X.
- [ ] **healthcheck route** — `GET /healthz` 추가, Cloudflare healthcheck 등록.

### Flutter 측

- [ ] **공유 entry 통합** — 이미지 공유 / 카톡 공유 두 entry → 단일 `[공유]` 버튼. modal sheet 안에서 "인스타에 이미지 / 카톡에 링크" 선택.
- [ ] **share publish 실패 처리** — Supabase 응답 5xx 시 사용자에게 재시도 안내.
- [ ] **deep link cold-start** — 앱이 죽어있는 상태에서 link 받은 경우 `ReportPage` 가 즉시 데이터 로드 (Hive 없으면 Supabase fetch).

---

## P2 — 이후 (스케일·유저 경험)

- [ ] **압축률 튜닝** — thumbnail JPEG q=85 → 80 으로 낮춰 R2 비용 절감 (시각 차이 측정 후).
- [ ] **Compat 카드 UI 완성** — `/r/{A}~{B}` SSR 의 CompatCard 컴포넌트 (P0 의 골격에서 chip·카피·layout 다듬기) + 두 사람 thumbnail 합성 OG PNG.
- [ ] **analytics** — Cloudflare Analytics Engine 으로 `/r/{uuid}` 클릭 수, deep link 성공률, 스토어 fallback 비율 집계.
- [ ] **A/B copy test** — OG title 두 버전 무작위 배포 → CTR 비교.
- [ ] **이메일/SMS 공유** — share_plus 의 다른 분기 활성 (현재는 카톡·인스타 중심).
- [ ] **푸시** — 받는 사람이 app 설치 + 가입한 경우 "공유받은 카드" 알림.

---

## P3 — 백로그

- [ ] **다국어 OG** — `Accept-Language` 헤더 detect → 한·영·일 분기.
- [ ] **인스타 reel 친화 9:16 카드** — 별도 비율.
- [ ] **shared engine 의 narrative 일부 (Beat-Fragment)** Worker SSR 에서도 보여줄지 결정. 현재는 archetype + 칩만; 본문은 앱 안만.
- [ ] **metrics_json 압축** — `metrics_json.metrics` JSONB 가 크면 (~3KB) zstd 압축 슬롯 추가. 100k+ 누적 시점에 검토.
- [ ] **궁합 OG 합성 PNG** — 두 사람 thumbnail 을 1080×566 (1.91:1) 캔버스에 합성. P1 단계. P0 단계에선 A 의 thumbnail 그대로 사용.

---

## 작업 의존 그래프

```
R2 bucket + lifecycle ────┐
R2 API tokens ────────────┼─► Worker secrets ──┐
FACE_API_SECRET 생성 ─────┘                     │
                                                ├─► Worker deploy
DNS 정리 (tunnel 삭제) ──────────────────────────┤
Supabase RLS 정책 적용 ──────────────────────────┤
                                                │
Worker /r/:id 재작성 ────────────────────────────┘
                                                │
                                                ▼
Flutter share_publisher (Supabase 직통) ──┐  배포 가능 (P0 끝)
Flutter deep link 수신 ───────────────────┤
AASA / assetlinks ────────────────────────┤
iOS entitlements / Android manifest ──────┘
                                                │
                                                ▼
                                          P1 안정화
```

각 P0 항목 다 끝나면 한 번 e2e 테스트:

1. Flutter 에서 카메라 → 분석 → 공유 카톡 발송
2. 다른 device 에서 카톡 link 탭
3. (앱 설치) → 앱이 열려 ReportPage 로 navigate
4. (앱 미설치) → facely.kr SSR 페이지 → CTA 누르면 스토어 이동
5. 1시간 후 R2 console 에서 `temp/` prefix 비어있는지 확인 (Python 즉시 삭제)
6. 24시간 후 R2 lifecycle 가 백업 정리 (수동 PUT 한 객체 sample 로 검증)

---

## 변경 기록

- 2026-05-17 (v3): `metrics` 행은 **1인 측정 데이터만**. `metrics_json` 에서 `kind`, `partnerUuid` 같은 compat 관계형 필드 전부 폐기 — 같은 metrics 행이 N 개 페어에 그대로 참여. 궁합 URL 표현법 결정: `/r/{A}~{B}` 단일 path segment, separator `~` (RFC 3986 unreserved, percent-encode 0). `/c/*` 별도 route 폐기 → `/r/:id` 한 라우트가 split 처리. compat publish 시 Supabase write 0회.
- 2026-05-17 (v2): Worker `/api/share` publish endpoint 도입 plan 폐기 — Flutter 가 Supabase metrics 에 anon key 로 **직접 UPSERT** 한다 (RLS 가 PII 키 reject). Worker 는 read-only SSR 만. metrics_json payload 가 Worker 를 왕복하지 않음 → 1.5–3 KB JSON 의 두 번 흐름 제거. Python `/analyze` 응답은 DeepFace raw 그대로 (`{age, gender, race}`) — decade 라벨링·소문자 변환·race↔Ethnicity 매핑 모두 Flutter 책임. `deepfaceAge/Gender/Race` 슬롯에 raw 보존 가능.
- 2026-05-17 (v1): `share_card` 테이블 plan 폐기 → 기존 `metrics` 한 테이블로 통합 (`thumbnailKey/kind/partnerUuid/deepface*` 를 `metrics_json` JSONB 에). `ageGroup` 값을 `"20s"` decade 라벨로 (Flutter 직렬화 layer). PII 정책 명확화 — thumbnail 본체는 R2 only, Supabase 엔 thumbnailKey 포인터만.
- 2026-05-16: 구 HMAC body+sig 토큰 방식 폐기. UUID 기반 Supabase 행 lookup 로 전환. R2 분리 (`temp/` 분석용 + `thumbnails/` 영구). Worker presign route 추가 (`/api/r2/presign`). Python 즉시 삭제 추가 예정. 본 문서 신규 작성.
- 2026-05-03: 이전 버전 (`face share host`) — HMAC token in URL 방식.
