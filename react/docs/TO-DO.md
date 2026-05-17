# TO-DO — facely

`HOW-IT-WORKS.md` 의 아키텍처를 실제 배포 가능 상태로 만드는 작업 목록. P0 → P3 순.

마지막 업데이트: 2026-05-17 — 완료된 항목 모두 정리 (lean 상태).

---

## P0 — 남은 출시 필수 작업

### Python

- [ ] **🗓️ SUNSET: secret-as-token bypass 제거** — 외부 베타 시작 또는 Flutter HMAC client 안정화 시점에 (a) `python/app/utils/auth.py` `_verify()` 의 compare_digest 분기 + (b) HOW-IT-WORKS §6.1.1 + (c) 본 task 모두 동시 삭제. **GA 전 마지노선.**

### Supabase 스키마

- [ ] **`POST /api/erase` Worker endpoint** (명시 삭제용, P1 의 prerequisite) — HMAC 인증 + uuid 받아 R2 + Supabase 동시 DELETE. Flutter "내 공유 link 관리" UI 가 호출.

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
- [ ] **`cdn.facely.kr` 검색엔진 차단** — R2 객체 응답에 `X-Robots-Tag: noindex` 헤더, 또는 R2 root 에 `robots.txt` (Disallow: /).

---

## P1 — 안정화

### 콘텐츠

- [ ] **OG 카드 디자인** — 256×256 thumbnail + archetype 타이틀. `ShareCard.tsx` UI 정돈.
- [ ] **인스타 1080×1350 카드 디자인** — Flutter 측 `RepaintBoundary` 위젯. archetype·점수·간단 chip 3개 + 워터마크 "facely.kr".
- [ ] **CTA 카피** — 미설치 사용자가 facely.kr 에 도착했을 때 "앱에서 더 보기" / "내 관상 보기" 두 버튼.
- [ ] **404 페이지** — 잘못된 UUID 또는 inactivity cron 으로 사라진 카드 접근 시 친절한 페이지 + 신규 분석 CTA. (시간 만료/410 분기 없음 — 404 한 케이스로 통합)

### Worker SSR

- [ ] **shared engine 통합** — `app/lib/traits.ts` 가 `app/lib/shared/face_engine.js` 호출. `pnpm build:shared` 명령 작동 확인. CI 에 해당 단계 추가.
- [ ] **og:image 실 thumbnailKey 연동** — 현재 `${origin}/logo.png` fallback. `metrics_json.thumbnailKey` (v2 schema bump 후) 가 채워지면 `${R2_CDN_BASE}/${thumbnailKey}` 로 전환.
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

## P2 — 스케일·유저 경험

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
- [ ] **궁합 OG 합성 PNG** — 두 사람 thumbnail 을 1080×566 (1.91:1) 캔버스에 합성.

---

## ⏳ Backlog — 방식 결정됨, 실행 후순위

### Dormant cleanup cron (Cloudflare Worker Cron Trigger)

활성 카드 보호 + dormant 자동 정리 — 본 작업이 없어도 신규 사용 흐름은 정상 동작 (Flutter UPSERT·SSR fetch·R2 PUT 모두 영향 0). 데이터 누적이 무시할 만한 초기 단계에선 운영 부담을 미루고, 누적이 의미 있어진 시점(또는 GA 직전)에 한 번에 enable.

**채택 방식**: Cloudflare Worker `triggers.crons` (HOW-IT-WORKS §12.2). Supabase 측 pg_cron 등의 cron 확장 의존 회피 — 우리 stack 안의 Cloudflare 만 사용. R2 SigV4 DELETE + Supabase REST DELETE 가 같은 Worker 안에서 처리.

**실행 시 해야 할 것**:

- `react/wrangler.jsonc` 에 `"triggers": { "crons": ["0 18 * * *"] }` (03:00 KST)
- `react/workers/app.ts` 에 `scheduled(event, env, ctx)` 핸들러 + `cleanupDormant` 호출 (또는 `workers/cron.ts` 로 분리)
- `react/app/lib/cleanup.ts` (신규) — Supabase REST select dormant → R2 aws4fetch DELETE → Supabase REST DELETE (R2 먼저 → DB 나중)
- `pnpm wrangler secret put SUPABASE_SERVICE_ROLE_KEY` — anon RLS 의 delete_none bypass 용. cron + `/api/erase` 두 곳만 사용.
- 첫 활성 직후 dry-run (3 month 대신 30 year 같이 가짜 threshold 로 실행) 으로 회로 확인 → production threshold 로 복귀.
