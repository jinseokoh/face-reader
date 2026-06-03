# TO-DO — facely (share host)

`HOW-IT-WORKS.md` 의 아키텍처를 실제 배포 가능 상태로 만드는 작업 목록.

마지막 업데이트: 2026-06-03

---

## P0 — 출시 필수 (남은 것)

### 딥링크 well-known 실값

딥링크 코어(Flutter entitlements·autoVerify intent-filter·app_links·DeepLinkService)는 완료. `.well-known` 두 파일만 placeholder 라 OS 도메인 검증이 안 됨 → 카톡 link 가 앱으로 자동 안 열리고 Worker SSR 거침.

- [ ] **AASA 실값** — `react/public/.well-known/apple-app-site-association` 의 `appIDs` 를 `<TEAMID>.com.scienceintegration.facely` 로 (현재 `TEAMID.` placeholder)
- [ ] **assetlinks 실값** — `react/public/.well-known/assetlinks.json` 의 `sha256_cert_fingerprints` 를 Play Console 앱 서명 키 SHA-256 으로 (현재 `REPLACE_WITH_...` placeholder)
- [ ] **MIME 확인** — 재배포 후 두 파일이 `application/json` 으로 200 응답하는지 (AASA 는 확장자 없음 주의)

### Python

- [ ] **🗓️ SUNSET: secret-as-token bypass 제거** — GA 전 마지노선. `python/app/utils/auth.py` 의 `hmac.compare_digest(token, secret)` bypass 분기 (사용 시 `FACE_TOKEN_BYPASS` WARN 로그) + HOW-IT-WORKS §6.1.1 동시 삭제. 트리거: 외부 베타 시작 또는 Flutter HMAC client stable.

### Privacy 의무 (PII = thumbnail) — Flutter 측

200² thumbnail 은 PII. 법적 frame 은 HOW-IT-WORKS §12.

- [ ] **분석 동의 화면** — 첫 분석 진입 전 모달. 이미지가 R2 + Python DeepFace 로 전송됨, thumbnail 이 공유 시 R2 보관됨 명시.
- [ ] **권한 사유 문구** — iOS `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription`, Android `<uses-permission>` 설명.
- [ ] **연령 확인** — 14세 미만 차단 (PIPA 22조의2).

---

## P1 — 안정화

### Worker SSR

- [ ] **fetch 실패 graceful** — Supabase 5xx 시 retry-with-jitter 1회, 실패면 503 페이지.
- [ ] **404 페이지** — 잘못된 UUID 또는 수동 정리로 사라진 카드 접근 시 친절한 페이지 + 신규 분석 CTA. (만료/410 분기 없음 — 404 한 케이스로 통합)
- [ ] **healthcheck route** — `GET /healthz` + Cloudflare healthcheck 등록.

### 운영

- [ ] **Rate limit** — Cloudflare WAF: `/api/r2/presign` 60/min/IP. (metrics UPSERT 는 Flutter 직통 → Supabase anon limit 위임.)
- [ ] **로그 sanitization** — Worker log 에 UUID 최소화. service key 노출 X.

### 콘텐츠

- [ ] **OG 카드 디자인 정돈** — `ShareCard.tsx` 200² thumbnail + archetype 타이틀.
- [ ] **궁합 OG 합성 PNG** — 두 사람 thumbnail 합성 (`/r/{A}~{B}`). 현재는 A 의 것 또는 logo fallback.

---

## P2 — 스케일·UX

- [ ] **analytics** — Cloudflare Analytics Engine: `/r/{uuid}` 클릭 수, deep link 성공률, store fallback 비율.
- [ ] **A/B copy test** — OG title 두 버전 무작위 → CTR 비교.
- [ ] **thumbnail 압축률 튜닝** — q=85 → 80 (시각 차이 측정 후).
- [ ] **푸시** — 공유 받은 사람이 앱 설치+가입 시 알림.

---

## P3 — 백로그

- [ ] **다국어 OG** — `Accept-Language` → 한·영·일.
- [ ] **body 압축** — `body.metrics` 가 크면 zstd. 100k+ 누적 시 검토.
- [ ] **per-card 명시 삭제 UI** — "설정 → 내 공유 link 관리" 에서 개별 카드 삭제. 현재는 회원 탈퇴(`/api/account/delete`)가 전체 erasure 를 커버. 단건 삭제용 `POST /api/erase`(HMAC) 는 필요 시 신설.

---

## ✅ 완료 (최근)

- **shared engine 통합** — `app/lib/traits.ts` 가 `runEngine(row.raw)` / `runCompat(a.raw, b.raw)` 호출. `pnpm build:shared` 동작.
- **og:image thumbnailKey 연동** — `body.thumbnailKey` → `cdn.facely.kr/{key}`.
- **회원 탈퇴** — `POST /api/account/delete` (JWT → R2 thumbnail 일괄 DELETE → metrics DELETE → auth.users admin DELETE, cascade).
- **contact form** — `/contact` 브라우저 직접 web3forms POST (CF 1106 우회).
- **privacy/terms 페이지** — `/privacy`·`/terms` (public/*.md + 미니 md 렌더).
- **cdn 검색엔진 차단** — R2 root `robots.txt` (사본 `react/r2-assets/robots.txt`).
- **expiry 폐기** — `expires_at` 컬럼·만료 체크·로컬 prune 전부 제거. 정리는 90일+ 미활동 수동 삭제 (§5.2).
- **metrics 소유 모델** — `user_id` 컬럼 + RLS owner update/delete(claim) + 코인 경제 테이블(coins/unlocks/ad_rewards).

---

## ⏳ Backlog — 방식 보류

### Dormant cleanup 자동화

현재는 운영자 수동 정리 (`delete from metrics where updated_at < now() - interval '90 days'`, service-role). 데이터 누적이 의미 있어지면 자동화. **채택 후보**: Cloudflare Worker `triggers.crons` (Supabase pg_cron 의존 회피) — `scheduled()` 핸들러에서 dormant select → R2 SigV4 DELETE → Supabase DELETE (R2 먼저 → DB 나중, orphan 방지). `SUPABASE_SERVICE_ROLE_KEY` 사용. 현재 wrangler.jsonc 에 cron trigger 없음 — 의도적 보류.
