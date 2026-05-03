# TO-DO — face share host

prod 배포까지 남은 작업. 우선순위는 P0 (배포 차단) → P1 (배포 직후) → P2 (개선).

마지막 업데이트: 2026-05-03

---

## P0 — prod 차단 (없으면 카톡 link 안 동작)

### 1. `SHARE_TOKEN_SECRET` 발행·등록
- 32 bytes random 생성 후 wrangler secret 등록
- 명령: `openssl rand -base64 32 | wrangler secret put SHARE_TOKEN_SECRET`
- 확인: `wrangler secret list` 에 노출

### 2. Supabase RLS policy
`supabase/migrations/` 에 마이그레이션 추가:

```sql
revoke select on metrics from anon;
grant select (id, metrics_json, expires_at) on metrics to anon;
drop policy if exists "anon read non-expired" on metrics;
create policy "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());

-- 옛 시도가 있었다면 cleanup
drop view if exists share_metrics;
drop policy if exists "anon read shared" on metrics;
alter table metrics drop column if exists share_payload;
```

검증: anon key 로 `select id, metrics_json from metrics where id = '...'` 통과 / `select user_id` 차단.

### 3. AASA / assetlinks 실값 교체
- `public/.well-known/apple-app-site-association` 의 `appIDs` → 실제 `TEAMID.com.scienceintegration.face`
- `public/.well-known/assetlinks.json` 의 `sha256_cert_fingerprints` → Play Console > Setup > App signing 의 SHA256
- 배포 후 `https://face.kr/.well-known/apple-app-site-association` 가 redirect 없이 200 + `application/json` 으로 응답해야 iOS 가 인식

### 4. `wrangler.jsonc` env vars 실값 교체
현재 placeholder: `https://share.face.app/r/`, `idXXXXXXXXX`, `com.example.face`.
- `APP_LINK_BASE` → `https://face.kr/r/`
- `APP_STORE_URL` → 실제 App Store URL
- `PLAY_STORE_URL` → 실제 Play URL
- `APP_BUNDLE_ID_IOS` / `APP_BUNDLE_ID_ANDROID` → `com.scienceintegration.face`

### 5. Flutter `SharePublisher` 작성
`flutter/lib/domain/services/share/share_publisher.dart` 에 `publish({uuidA, uuidB?, pngBytes})` 구현.
- `RepaintBoundary` → 1200×630 PNG (in-memory)
- `POST face.kr/api/share` → `{ shortId }`
- `Share.shareXFiles([XFile.fromData(pngBytes, ...)], text: 'face.kr/r/$shortId')`

### 6. Flutter inbound deep link
`flutter/lib/main.dart` 에서 `app_links` 초기화 + `/r/:token` path → ReportPage 라우팅.
- cold start: `appLinks.getInitialLink()` 처리
- warm: `appLinks.uriLinkStream` listen
- iOS `Runner.entitlements` 에 `applinks:face.kr` 추가
- Android `AndroidManifest.xml` 에 `intent-filter` + `android:autoVerify="true"` 추가

### 7. portrait 자산 디자인 컨펌
`public/{male,female}.png` 두 장이 prod 카드에 적합한 비율·해상도인지 디자이너 확인 (카톡 미리보기 + SSR 카드 양쪽).

---

## P1 — 배포 직후

### 8. 카톡 in-app browser fallback
`app/components/CTA.tsx` 에서 카톡 in-app browser UA 감지 → Android 는 `intent://` URL 로 외부 브라우저 강제 open. iOS 는 "Safari 에서 열기" 안내.

### 9. 위조·invalid token 회귀 테스트
- 위조 sig (`/r/AAAA...AAA.XXXX`) → 403
- 길이 잘못된 token → 400
- 정상 sig + 존재 안 하는 uuid → 404
- 만료된 row (expires_at < now) → 404

### 10. OG 미리보기 검증
prod 배포 후 카톡·iMessage·Facebook debugger 셋 다 logo + title + description 정상 표시 확인.

### 11. 친밀·갈등 본문 leak 회귀 review
`/shared/lib/face_engine.dart` 의 `_composeShareOutput` / `_composeCompatOutput` 출력에 친밀 챕터 본문·갈등 시나리오 본문·이름·생년월일·얼굴 이미지·raw landmark 0개 확인. 룰 변경 시마다 점검.

---

## P2 — 개선

### 12. Analytics
Cloudflare Analytics Engine 또는 Plausible 으로 link clicked → app opened → install funnel 추적.

### 13. OG image 동적 생성
satori + `@resvg/resvg-js` 로 `/og/:shortId.png` route. 텍스트만으로 카드 PNG 동적 생성 → 이미지 별도 업로드 불필요.
현재는 `/logo.png` static 1장 ( `traits.ts::renderSolo/renderCompat` 의 `ogImage`).

### 14. metrics row pg_cron 정기 삭제
`expires_at < now() - interval '1 day'` row 를 daily 삭제. 현재 RLS 가 만료 row read 차단해서 기능적 문제는 없지만 storage 정리 차원.

---

## 완료 (이력 보존용)

- ✅ `/shared/` Dart 패키지 + 엔진 추출
- ✅ React 가 `globalThis.runEngine` / `runCompat` 호출 (`app/lib/traits.ts`)
- ✅ token codec (`app/lib/codec.ts`, `app/lib/share-id.ts`) — base64url + HMAC-SHA256 sig4
- ✅ `POST /api/share` sign-only endpoint (`app/routes/api.share.ts`)
- ✅ `/r/:shortId` SSR loader + OG meta + ShareCard / CTA UI
- ✅ landing demo (uuid 끝 1/2 패턴 → supabase bypass)
