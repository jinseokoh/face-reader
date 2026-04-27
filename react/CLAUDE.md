# face-share-host — Claude Code 오리엔테이션

Flutter 앱의 공유 link host. 카톡 등에서 받은 `/r/{token}` link 의 미리보기·랜딩·deep link 라우팅을 담당. **Cloudflare Workers + React Router v7 SSR. Storage 0, KV 0, DB 는 Flutter 가 이미 쓰고 있는 Supabase `metrics` 테이블 그대로. archetype·점수·highlights 는 Dart 엔진을 `/shared/` 패키지로 추출해 `build:shared` 가 dart compile js 로 컴파일 → React 가 그 산출물을 import 해서 raw `metrics_json` 위에 직접 돌린다. **Flutter (refine) 와 React 가 같은 엔진을 공유, schema drift 0.****

마지막 업데이트: 2026-04-27 (token-based architecture)

세부 아키텍처·Flutter 계약·대안 stack: [DEEPLINK.md](./DEEPLINK.md) SSOT.

---

## ⛔ 절대 룰

1. **OG meta 는 반드시 server-side.** route 의 `meta` export 만 사용. client-only `<head>` 조작 금지 — 카톡 크롤러는 JS 실행 안 함.
2. **Vercel 배포 금지.** Cloudflare Workers 외 deployment target 추가 금지.
3. **친밀 챕터·갈등 시나리오 본문 노출 금지.** 응답에 절대 포함 금지. teaser·점수·archetype label 만 server 가 generate.
4. **사용자 식별 정보 (이름·생년월일·얼굴 이미지) 노출 금지.** URL 에는 uuid base64url + sig 만. 본문 응답에도 마스킹된 값만.
5. **R2/Storage 도입 금지.** 이미지·파일 host 0. 카드 PNG 는 Flutter 가 카톡 attach 로 직접 발송 (1회성). OG image 는 `/logo.png` static 1장.
6. **친밀·갈등 본문 DB 저장 금지.** `metrics_json` 에는 rawValue + demographic 만 (Flutter 의 `FaceReadingReport.toJsonString()` v3 capture-only). archetype·rule·node·attribute 같은 derived 출력은 절대 DB 에 저장 금지 — 엔진이 load 시점 재계산.
7. **engine 재이식 금지.** archetype·score 룰을 React 쪽에 손으로 다시 짜지 마라. Dart 엔진을 `/shared/` 로 추출 → `build:shared` 로 컴파일 → React import. 양쪽 룰 분기 절대 금지.
7. **flutter/CLAUDE.md 의 SongMyung 폰트 룰 적용 X.** system default 가 카톡 미리보기에 자연스럽다.

---

## 디렉토리 (편집 SSOT)

| 경로 | 역할 |
|---|---|
| `workers/app.ts` | Cloudflare Worker fetch handler |
| `app/entry.server.tsx` | RR7 Cloudflare 런타임 entry (custom; `@react-router/node` 안 씀) |
| `app/routes.ts` | 명시적 라우트 정의 |
| `app/routes/_index.tsx` | landing — 데모 token 두 개 발행해 표시 |
| `app/routes/share.tsx` | `/r/:shortId` loader (token decode → faces fetch → render) + meta + 컴포넌트 |
| `app/routes/api.share.ts` | `POST /api/share` (sign-only 발행 endpoint, body: `{type, userA, userB?}` → `{shortId}`) |
| `app/lib/codec.ts` | uuid ↔ bytes ↔ base64url helpers |
| `app/lib/share-id.ts` | encode/decode + HMAC-SHA256 sig4 verify |
| `app/lib/supabase.ts` | `fetchMetrics(env, ids)` — REST `/rest/v1/metrics?select=id,metrics_json,expires_at` 직접 호출, rawValue + demographic 만 받아옴 |
| `app/lib/traits.ts` | `renderSolo` / `renderCompat` — `/shared/` 의 컴파일된 엔진 (`runEngine(raw)`) 호출 후 RenderedShare 합성. 현재는 stub. |
| `app/lib/shared/face_engine.js` | `pnpm build:shared` 가 `/shared/lib/face_engine.dart` → dart compile js 로 만든 산출물. **commit 금지 (생성 산출물)**. |
| `app/lib/types.ts` | `FaceRow`, `RenderedShare` SSOT |
| `app/components/ShareCard.tsx` | 카드 UI (logo + 점수 + tagline + highlights[3]) |
| `app/components/CTA.tsx` | universal link 시도 + 1.5s 후 store fallback |
| `public/logo.png` | OG image (1장 static, `og:image` 로 사용) |
| `wrangler.jsonc` | env vars + assets binding |
| `public/.well-known/*` | AASA · assetlinks (prod 전 실값 교체 필수) |

---

## 환경 변수

`wrangler.jsonc` 의 `vars` (public, source-controlled OK):
| key | 용도 |
|---|---|
| `APP_LINK_BASE` | universal link prefix (`https://face.kr/r/`) |
| `APP_STORE_URL` | iOS App Store URL |
| `PLAY_STORE_URL` | Google Play URL |
| `APP_BUNDLE_ID_IOS` | AASA 검증 reference |
| `APP_BUNDLE_ID_ANDROID` | assetlinks 검증 reference |

Secrets (`wrangler secret put`, **절대 commit 금지**):
| key | 용도 |
|---|---|
| `SHARE_TOKEN_SECRET` | HMAC-SHA256 secret (32 bytes random). token 위조 방지의 유일한 보호막 |
| `SUPABASE_URL` | `faces` 테이블 read |
| `SUPABASE_ANON_KEY` | RLS 가 read-only 보장 전제 |

Local: `.dev.vars` (gitignored, `.dev.vars.example` 참고).
Prod: `wrangler secret put SHARE_TOKEN_SECRET` 등.

---

## URL & Token 구조

```
URL:   https://face.kr/r/{body}.{sig4}

body  = base64url(uuid bytes), no padding
       solo:    16 bytes → 22자
       compat:  32 bytes (uuidA‖uuidB) → 43자
sig4  = base64url( HMAC-SHA256(body_bytes, SHARE_TOKEN_SECRET).slice(0, 3) ) → 4자
```

URL 길이: solo 27자, compat 50자. carrying capacity:
- 위조 막음 (24bit HMAC, brute force 1.6 × 10⁷ 시도)
- expires/revoke 는 `secret rotation` 으로 일괄 (개별 revoke 는 supabase row 삭제 → 404)

---

## Flutter 쪽과의 계약

`SharePublisher` (P0, Flutter):
1. 사용자 [공유] 탭
2. `RepaintBoundary` → 1200×630 PNG 합성 (in-memory, **storage 업로드 0**)
3. `POST https://face.kr/api/share { type, userA, userB? }` → `{ shortId }` 받음
4. `Share.shareXFiles([XFile.fromData(pngBytes, ...)], text: 'https://face.kr/r/$shortId')` 으로 카톡·OS share sheet 발송

실제 테이블은 Flutter 가 이미 쓰고 있는 `metrics` (id, user_id, metrics_json, source, ethnicity, gender, age_group, expires_at, alias).

**Schema 변경 0**. `metrics` 테이블 그대로. anon 이 raw `metrics_json` 을 읽을 수 있도록 RLS policy 한 줄만 추가:

```sql
create policy "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());
```

`metrics_json` 안에는 PII 0 — rawValue (17 frontal + 8 lateral 의 ratio/angle 숫자) + demographic (ethnicity/gender/ageGroup) + faceShape 만. 이름·생년월일·얼굴 이미지·landmark 좌표 모두 안 들어감. anon 노출 안전.

archetype·score 는 React 쪽에서 `/shared/` 의 컴파일된 엔진을 호출해 즉석 계산. `share_payload` jsonb 컬럼·view 같은 denormalized 캐시 일체 사용 안 함 — 전 세션의 over-engineered 시도, 폐기됨. 만약 옛 마이그레이션을 적용했다면 아래 SQL 로 정리:

```sql
-- share_payload 폐기 + view (있었다면) 폐기 + RLS 정리
drop view if exists share_metrics;
drop policy if exists "anon read shared" on metrics;
alter table metrics drop column if exists share_payload;

-- anon 가 만료 안 된 row 의 metrics_json 까지 읽을 수 있게 column-level grant
revoke select on metrics from anon;
grant select (id, metrics_json, expires_at) on metrics to anon;
drop policy if exists "anon read non-expired" on metrics;
create policy "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());
```

### 카드 portrait
공유 카드의 인물 사진은 `react/public/{male,female}.png` 두 장 static. 사용자 본인 얼굴 이미지·archetype 별 supabase storage URL 모두 사용 안 함 (privacy policy + 통일감). gender 만 보고 swap.

---

## 다음 작업 (우선순위)

| 우선 | 작업 | 재개 지시 |
|---|---|---|
| P0 | Supabase RLS policy — anon 이 만료 안 된 metrics row select 가능 | `"supabase/migrations/ 에 create policy 'anon read non-expired' on metrics for select to anon using (expires_at > now())"` |
| done | `/shared/` Dart 패키지 + 엔진 추출 + dart compile js → globalThis.runEngine / runCompat | — |
| done | React/Refine 가 컴파일 산출물 side-effect import 후 호출 | — |
| P0 | Flutter `SharePublisher` 작성 | `"flutter/lib/domain/services/share/share_publisher.dart 에 publish({uuidA, uuidB?, pngBytes}). POST /api/share → shortId → share_plus shareXFiles 첨부"` |
| P0 | `SHARE_TOKEN_SECRET` 발행·등록 | `"openssl rand -base64 32 → wrangler secret put SHARE_TOKEN_SECRET"` |
| P0 | AASA / assetlinks 실값 교체 | `"public/.well-known/ 두 파일에 실제 TEAMID + Play Console SHA256. flutter/ios/Runner/Runner.entitlements 에 associated-domains"` |
| P0 | Flutter `app_links` 라우팅 | `"flutter/lib/main.dart 에서 app_links 초기화 + /r/:token path → ReportPage 라우팅. cold start + warm 양쪽"` |
| P1 | 카톡 in-app browser fallback | `"CTA.tsx 에 카톡 in-app browser UA 감지 → intent:// (Android) 또는 외부 브라우저 강제 open"` |
| P2 | Analytics (link clicked → app opened → install funnel) | `"Cloudflare Analytics Engine 또는 Plausible 으로 클릭·체류·conversion"` |

---

## 빌드·테스트

```bash
cd react
pnpm install
pnpm dev          # http://localhost:5173 (또는 5174/5175)
pnpm typecheck
pnpm build
pnpm preview      # wrangler dev (production worker simulation)
pnpm deploy       # Cloudflare 배포
```

Demo: dev server 띄우고 `/` 가면 데모 solo / 데모 compat 카드 token link 두 개 자동 발행. uuid `00000000-0000-0000-0000-XXXXXXXXXXXX` 패턴은 supabase 안 거치고 inline demo data 로 응답 (dev 만, supabase 미설정 환경에서도 동작).

---

## 디자인 룰

- **system font** 만 사용. SongMyung 등 web font 도입 금지.
- **5단 hierarchy**: 24/16/14/13/12 px. 그 외 size 추가 금지.
- **컬러 4개**: `#1a1a1a` (text), `#666` (caption), `#c44` (accent — 점수 강조 only), `#f7f7f8` (bg).
- OG image 는 `public/logo.png` static 1장. 1200×630 ratio 권장 (현재 logo.png 가 ratio 안 맞으면 카톡 미리보기에서 letterbox/crop 됨 — 디자이너에게 확인 필요).
