# TO-DO — facely

`HOW-IT-WORKS.md` 의 아키텍처를 실제 배포 가능 상태로 만드는 작업 목록. P0 → P3 순.

각 항목에 **(파일/명령/책임)** 표기. 체크박스 켜진 건 완료, 빈 건 미완.

마지막 업데이트: 2026-05-17 (v7) — **inactivity-based 자동 정리 도입**. metrics 에 `views` + `updated_at` 컬럼 추가, `/r/:id` fetch 마다 RPC `increment_metrics_views` 로 views++ + updated_at 자동 갱신. 3 개월 정체 시 daily cron 으로 metrics 행 + R2 thumbnail 동시 삭제. 활성 카드(누가 보고 있는) 는 영구. user_id 컬럼 추가 거부 (anonymous schema 유지 — PII 면 늘리지 않음). views 는 보너스 product analytics index. 명시 삭제 UI 는 P1 유지.

---

## P0 — 즉시 (analyze 파이프라인 + 공유 link 의 최소 동작에 필수)

### Cloudflare 측

- [x] **R2 bucket `facely` 생성** (Cloudflare 대시보드 → R2)
- [x] **Lifecycle rule** — `Prefix = temp/` / `Expiration = 1 day` (Python 즉시 삭제의 백업). `thumbnails/` 는 룰 0 (영구).
- [x] **Custom domain `cdn.facely.kr`** → bucket public read 매핑 (또는 R2 dev URL 사용)
- [x] **R2 API token #1 (Worker용)** — Object Read & Write, bucket=facely 한정. **Access Key ID / Secret Access Key / Endpoint URL** 확보 (`dash.cloudflare.com/<account-id>/r2/api-tokens` 경로 — 일반 `/profile/api-tokens` 아님)
- [x] **Worker secrets 등록**
  - `pnpm wrangler secret put R2_ACCESS_KEY_ID`
  - `pnpm wrangler secret put R2_SECRET_ACCESS_KEY`
  - `pnpm wrangler secret put FACE_API_SECRET` (32-byte hex, `openssl rand -hex 32`)
- [x] **`pnpm cf-typegen`** → secret 들이 `worker-configuration.d.ts` 에 자동 등재 확인됨. `app/types/env.d.ts` (수동 augmentation) + 빈 `app/types/` 폴더 삭제 완료.
- [x] **`wrangler.jsonc` 의 `R2_ACCOUNT_ID` placeholder** → 실제 account ID 로 교체 (대시보드 우상단).
- [x] **`wrangler.jsonc` routes** — facely.kr / www.facely.kr 바인딩 (`custom_domain: true`).
- [x] **DNS 정리**: 기존 tunnel 레코드 `facely.kr` / `www` 삭제 → Worker 가 자동으로 custom_domain 으로 다시 만듦. `meta` tunnel 추가 (Python 호스트). `cdn` R2 매핑 활성.

### Python 서비스

- [x] `/analyze` HMAC 인증 dependency (이미 구현)
- [ ] **⚠️ 임시 secret-as-token bypass** — `python/app/utils/auth.py` 의 verify_face_token 첫 줄에 `if hmac.compare_digest(token, secret): return True` 분기 + WARN 로그. 추가 env·secret 없음 (기존 `FACE_API_SECRET` 재사용). dev/postman 에서 X-Face-Token 헤더에 secret 그대로 박으면 통과. 자세한 sunset 기준은 HOW-IT-WORKS §6.1.1.
- [ ] **🗓️ SUNSET: secret-as-token bypass 제거** — 외부 베타 시작 또는 Flutter HMAC client 안정화 시점에 (a) auth.py 의 compare_digest 분기 + (b) HOW-IT-WORKS §6.1.1 + (c) 본 task 모두 동시 삭제. **GA 전 마지노선.**
- [ ] **`/analyze` 응답 = DeepFace raw 그대로** — `{age:int, gender:"Man"|"Woman", race:string}` 만 반환. decade 라벨링·소문자·enum 매핑 등 가공 0. (소비자 Flutter 가 알아서 함.)
- [ ] **즉시 R2 DELETE 구현** — `python/app/services/deleter.py` (신규):
  ```python
  async def delete_temp_object(key: str) -> None:
      # SigV4 signed DELETE via httpx
      # endpoint: https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com/{R2_BUCKET_NAME}/{key}
  ```
  의존성: `httpx` (이미 있음) + 가벼운 SigV4 signer (직접 구현 25줄 또는 `aioboto3` 도입).
- [ ] **`/analyze` 끝에 `await delete_temp_object(key)`** (try/except — 실패해도 응답엔 영향 X, 로그만). `key` 는 헤더 `X-Face-Key` 로 이미 들어옴.
- [ ] **docker-compose env** 에 `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (Worker secret 과 동일 값), `R2_ACCOUNT_ID`, `R2_BUCKET_NAME` 추가
- [ ] 같은 `FACE_API_SECRET` 값을 Worker secret 과 동일하게 셸 env 또는 `.env` 로 주입

### Supabase 스키마

- [x] **`metrics` 테이블** — 이미 존재 (id / metrics_json / expires_at). 별도 `share_card` 신설 X.
- [ ] **`views` + `updated_at` 컬럼 추가** + `touch_metrics_updated_at` trigger + `metrics_updated_at_idx` 인덱스 (HOW-IT-WORKS §5.2 SQL 그대로). `expires_at` 컬럼은 더 이상 사용 안 함 (drop 또는 ignore).
- [ ] **RPC `increment_metrics_views(card_id uuid)`** stored function — anon 에 execute 권한 grant. Worker SSR 과 Flutter app 양쪽이 `/r/:id` fetch 시 동일 호출.
- [ ] **metrics_json schemaVersion v2 bump** — Flutter 의 `RawMetrics` 모델에 `thumbnailKey`, `deepfaceAge?`, `deepfaceGender?`, `deepfaceRace?` 필드 추가하고 v2 로 표시. DeepFace raw 는 Flutter 가 보존할지 버릴지 자유. **`kind`/`partnerUuid`/`expires_at` 같은 관계형·만료 필드는 추가 금지**.
- [ ] **RLS 정책** (HOW-IT-WORKS §5.3 SQL 그대로) — `select` 전체 허용, `insert` anon 에 허용하되 PII 키 (`username/alias/birthday/landmarks`) 가 metrics_json 에 있으면 reject, `update`/`delete` 는 service-role 만 (cron 정리·명시 삭제용).
- [ ] **Daily inactivity cron**:
  - Supabase pg_cron: 매일 03:00 KST `select id from metrics where updated_at < now() - interval '3 months'` → list 를 Worker cron 이 받음
  - 또는 Cloudflare Worker Cron Trigger 가 동일 SQL 후 R2 thumbnail DELETE → Supabase 행 DELETE (R2 먼저 → DB 나중 순서)
  - 한 번 dry-run 후 production 배포 (첫 cleanup 카드 수 확인)
- [ ] **`POST /api/erase` Worker endpoint** (명시 삭제용, P1 의 prerequisite) — HMAC 인증 + uuid 받아 R2 + Supabase 동시 DELETE. Flutter "내 공유 link 관리" UI 가 호출.

### Worker 신규/변경 라우트

- [x] **`POST /api/r2/presign`** — 이미 구현 (`app/routes/api.r2.presign.ts`)
- [x] **publish endpoint 없음** — `/api/share` 같은 라우트 의도적 미구현. Flutter ↔ Supabase 직통 UPSERT. (큰 payload 왕복 방지 + Worker write 권한 제거.) 기존 `app/routes/api.share.ts` 가 있다면 삭제.
- [x] **`GET /r/:id`** 재작성 완료 (`app/routes/share.tsx`):
  - routes.ts `:shortId` → `:id` 변경
  - `app/lib/share-id.ts` 폐기된 HMAC codec 제거 → `PAIR_SEP="~"` + `parsePairId` 헬퍼
  - `fetchMetrics(env, ids)` 1 또는 2 행 fetch, 누락 시 404
  - `context.cloudflare.ctx.waitUntil(incrementMetricsViews(env, id))` × ids.length (fire-and-forget)
  - ids.length === 1 → `runEngine`, 2 → `runCompat`
  - meta 에 `robots: noindex,nofollow` 추가
  - `appLinkBase = ${WEBAPP_BASE}/r/` 로 CTA 에 전달
  - 잔여: og:image 가 아직 `/logo.png` fallback (traits.ts 가 `${origin}/logo.png` 사용). 실제 cdn.facely.kr thumbnailKey 연동은 별도 (RawMetrics 가 v2 schema 로 bump 된 후).
- [ ] **루트 페이지 `/`** — 간단한 랜딩 + 스토어 CTA (현 `_index.tsx` 의 dev 데모 토큰 발행 로직 제거)

### Flutter 측

- [x] R2Uploader / FaceMetadataClient / ImageResizer (이미 구현)
- [ ] **`AgeGroup` JSON 직렬화 변경** — `shared/lib/data/enums/age_group.dart` 에 `jsonValue` extension 추가 (`teens→"10s", twenties→"20s", ..., nineties→"90s"`). RawMetrics toJson 에서 `name` 대신 `jsonValue` 사용. fromJson 은 v1 호환 위해 두 포맷 모두 accept (`"twenties"` 도 받음, 신규는 `"20s"` 로 쓰기).
- [ ] **`FaceMetadata` 모델 확장** — DeepFace raw 응답 3 필드 (`age:int`, `gender:"Man"|"Woman"`, `race:string`) 를 `deepfaceAge/Gender/Race` 로 보존. app demographic enum 으로의 매핑은 Flutter 가 자체 책임 (사용자 보정 UI 가 최종).
- [ ] **`share_publisher.dart`** 재작성 — 1인 metrics 직접 UPSERT (Worker 미경유):
  1. analyze pipeline 완료 후 thumbnail 256px 까지 R2 PUT (presign + PUT)
  2. metrics_json 페이로드 조립 — **1인 측정 데이터만** (schemaVersion=2, thumbnailKey, deepface\*?, 기존 rawMetrics, ageGroup="20s" 포맷). `kind`/`partnerUuid`/`expires_at` 같은 필드 추가 금지.
  3. Supabase REST `POST /rest/v1/metrics?on_conflict=id` (anon key, header `Prefer: resolution=merge-duplicates`) 로 UPSERT — 항상 1행, `expires_at` 은 null 그대로
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

### Privacy 의무 (PII = thumbnail)

256² thumbnail 은 PII. 출시 전 법적 의무 정리 — 자세한 frame 은 HOW-IT-WORKS §12.

- [ ] **분석 동의 화면** — Flutter 첫 분석 진입 전 모달. 이미지가 R2 + Python DeepFace 로 전송됨, thumbnail 이 공유 시 R2 보관됨을 명시. `[동의 후 계속]` 버튼.
- [ ] **Privacy policy 페이지** — Worker SSR `app/routes/privacy.tsx` (또는 정적 markdown). 처리목적 / 보유기간 ("이용 종료 시까지 + 본인 명시 삭제 시 즉시") / 제3자 제공 없음 / 국외이전 (R2 글로벌·Supabase Seoul) / 이용자 권리 / 고충처리 / 근거법령.
- [ ] **권한 사유 문구** — iOS `Info.plist` 의 `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription`, Android `AndroidManifest.xml` 의 `<uses-permission>` 옆 설명. 한국어 자연스러운 문장으로.
- [ ] **연령 확인** — 첫 진입 시 "14세 이상입니까?" 체크. 14세 미만 차단 (PIPA 22조의2 법정대리인 동의 회피).
- [ ] **`/r/*` noindex** — `share.tsx` 의 `meta` export 에 `{ name: "robots", content: "noindex,nofollow" }` 추가.
- [ ] **`cdn.facely.kr` 검색엔진 차단** — R2 객체 응답에 `X-Robots-Tag: noindex` 헤더, 또는 R2 root 에 `robots.txt` (Disallow: /).
- [ ] **Supabase region 확인** — `ap-northeast-2` (Seoul) 인지 대시보드 확인. 다른 region 이면 마이그레이션 검토 (privacy policy 의 국외이전 명시와 일치).

---

## P1 — 다음 (배포 후 안정화)

### 콘텐츠

- [ ] **OG 카드 디자인** — 256×256 thumbnail + archetype 타이틀. `ShareCard.tsx` UI 정돈.
- [ ] **인스타 1080×1350 카드 디자인** — Flutter 측 `RepaintBoundary` 위젯. archetype·점수·간단 chip 3개 + 워터마크 "facely.kr".
- [ ] **CTA 카피** — 미설치 사용자가 facely.kr 에 도착했을 때 "앱에서 더 보기" / "내 관상 보기" 두 버튼.
- [ ] **404 페이지** — 잘못된 UUID 또는 inactivity cron 으로 사라진 카드 접근 시 친절한 페이지 + 신규 분석 CTA. (시간 만료/410 분기 없음 — 404 한 케이스로 통합)

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
- [ ] **★ 명시 삭제 UI (PII right-to-erasure)** — "설정 → 내 공유 link 관리" 화면. 본인 Hive history 의 uuid 와 metrics 행 매칭하여 list, 개별 [삭제] 버튼이 R2 thumbnail + Supabase 행을 동시 삭제. service-role 호출은 Worker 의 신규 endpoint `POST /api/erase` (HMAC 인증) 또는 Supabase Edge Function 으로. **법적 의무 (GDPR Art 17 / PIPA 36조)** — P1 내 출시 마지노선.

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

- 2026-05-17 (v7): **inactivity-based 자동 정리 도입**. v5 의 영구 정책 부분 수정 — 모든 카드 영구 보존 → "활성 카드만 영구, dormant 자동 정리". metrics 에 `views (int)` + `updated_at (timestamptz)` 컬럼 + trigger 추가. `/r/:id` fetch 마다 `rpc/increment_metrics_views` 로 views++ → updated_at 자동 갱신. daily cron 이 `updated_at < now() - 3 months` 행 + R2 thumbnail 동시 삭제. user_id 컬럼 추가 거부 (anonymous schema 유지). `views` 자체가 무료 product analytics index 보너스.
- 2026-05-17 (v6): **PII 정정**. R2 `thumbnails/` 의 256² 얼굴 = PII 인정 (GDPR Art 4·Art 9 / PIPA). 그동안 "Supabase 엔 PII 없음" 표현이 시스템 전체 PII 부재로 오해 유도하던 점 정정. HOW-IT-WORKS §12 Privacy 섹션 신설 — PII 분류표·보유기간 정책·동의·noindex·region·access control 의 실체. P0 에 privacy policy / 분석 동의 화면 / 권한 사유 문구 / 연령 확인 / noindex 추가. P1 마지노선으로 명시 삭제 UI (right-to-erasure).
- 2026-05-17 (v5): **v4 의 만료 정책 자체 폐기**. 공유 카드 영구 보존으로 전환. 이유: R2↔Supabase 짝지움·min() 분기·만료 cron·410 페이지 등 operational complexity 비용이, 6개월 후 자동 사라짐의 UX 이득보다 컸음. 비용 산정 결과 100만 카드도 R2 $0.15/월 + Supabase Pro tier 수준이라 영구 보존이 더 합리적. 장기 누적 압박 시점에 batch script 한 번으로 정리 가능 (그땐 expires_at 컬럼이 hook).
- 2026-05-17 (v4): (폐기됨) 공유 카드 만료 정책 도입 plan. R2 `thumbnails/` 객체에 lifecycle 180일 + Supabase `metrics.expires_at = now() + 180 days` 짝. v5 에서 영구로 회귀.
- 2026-05-17 (v3): `metrics` 행은 **1인 측정 데이터만**. `metrics_json` 에서 `kind`, `partnerUuid` 같은 compat 관계형 필드 전부 폐기 — 같은 metrics 행이 N 개 페어에 그대로 참여. 궁합 URL 표현법 결정: `/r/{A}~{B}` 단일 path segment, separator `~` (RFC 3986 unreserved, percent-encode 0). `/c/*` 별도 route 폐기 → `/r/:id` 한 라우트가 split 처리. compat publish 시 Supabase write 0회.
- 2026-05-17 (v2): Worker `/api/share` publish endpoint 도입 plan 폐기 — Flutter 가 Supabase metrics 에 anon key 로 **직접 UPSERT** 한다 (RLS 가 PII 키 reject). Worker 는 read-only SSR 만. metrics_json payload 가 Worker 를 왕복하지 않음 → 1.5–3 KB JSON 의 두 번 흐름 제거. Python `/analyze` 응답은 DeepFace raw 그대로 (`{age, gender, race}`) — decade 라벨링·소문자 변환·race↔Ethnicity 매핑 모두 Flutter 책임. `deepfaceAge/Gender/Race` 슬롯에 raw 보존 가능.
- 2026-05-17 (v1): `share_card` 테이블 plan 폐기 → 기존 `metrics` 한 테이블로 통합 (`thumbnailKey/kind/partnerUuid/deepface*` 를 `metrics_json` JSONB 에). `ageGroup` 값을 `"20s"` decade 라벨로 (Flutter 직렬화 layer). PII 정책 명확화 — thumbnail 본체는 R2 only, Supabase 엔 thumbnailKey 포인터만.
- 2026-05-16: 구 HMAC body+sig 토큰 방식 폐기. UUID 기반 Supabase 행 lookup 로 전환. R2 분리 (`temp/` 분석용 + `thumbnails/` 영구). Worker presign route 추가 (`/api/r2/presign`). Python 즉시 삭제 추가 예정. 본 문서 신규 작성.
- 2026-05-03: 이전 버전 (`face share host`) — HMAC token in URL 방식.
