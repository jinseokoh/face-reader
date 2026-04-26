# face-share-host — Claude Code 오리엔테이션

Flutter 앱의 공유 link host. 카톡 등에서 받은 `/r/{shortId}` link 의 미리보기·랜딩·deep link 라우팅을 담당. **Cloudflare Workers + React Router v7 SSR**.

마지막 업데이트: 2026-04-26 (initial scaffold)

세부 아키텍처·Flutter 계약·대안 stack: [DEEPLINK.md](./DEEPLINK.md) SSOT.

---

## ⛔ 절대 룰

1. **OG meta 는 반드시 server-side.** route 의 `meta` export 만 사용. client-only `<head>` 조작 금지 — 카톡 크롤러는 JS 실행 안 함, 동적 OG 가 안 보이면 share host 의 존재 의미가 없다.
2. **Vercel 배포 금지.** 비용 안전성이 stack 결정 이유. Cloudflare Workers 외 deployment target 추가 금지.
3. **친밀 챕터·갈등 시나리오 본문 노출 금지.** Supabase 에 저장하지 않고, 페이지에도 렌더하지 않는다. 30~50 ageGate 콘텐츠 + 카톡 단톡 leak 위험.
4. **사용자 식별 정보 (이름·생년월일·얼굴 이미지) 노출 금지.** 공유 카드 페이지는 anonymous 접근 가능해야 한다.
5. **expires_at 무시 금지.** loader 에서 `expires_at < now()` 면 410 처리. 무기한 공개 link 방지.
6. **flutter/CLAUDE.md 의 SongMyung 폰트 룰 적용 X.** 외부 host 페이지라 system default 가 더 자연스러움. 카톡 미리보기에서 폰트 로딩 늦으면 카드 깨짐.

---

## 디렉토리 (편집 SSOT)

| 경로 | 역할 |
|---|---|
| `workers/app.ts` | Cloudflare Worker fetch handler. RR7 `createRequestHandler` 으로 SSR 위임 |
| `app/routes.ts` | RR7 라우트 정의 (file-based 안 씀, 명시적) |
| `app/routes/share.tsx` | `/r/:shortId` 의 loader + meta + 컴포넌트. 핵심 파일 |
| `app/components/ShareCard.tsx` | 카드 이미지 + 요약 + highlights (3 항목) |
| `app/components/CTA.tsx` | useEffect 로 universal link 시도, 1.5s 후 store fallback |
| `app/lib/supabase.ts` | `fetchShareCard(env, shortId)` — env 는 AppLoadContext.cloudflare.env |
| `app/lib/types.ts` | `ShareCardData` 타입 SSOT (Flutter publish 와 1:1 매핑) |
| `wrangler.jsonc` | 환경 변수·assets binding·compatibility flags |
| `public/.well-known/*` | AASA · assetlinks (prod 전 실값 교체 필수) |

---

## 환경 변수 (Worker bindings)

| key | 용도 |
|---|---|
| `SUPABASE_URL` | secret. share_card 조회 |
| `SUPABASE_ANON_KEY` | secret. RLS 가 read-only 보장 전제 |
| `APP_LINK_BASE` | `https://share.face.app/r/` — universal link prefix |
| `APP_STORE_URL` | iOS App Store URL |
| `PLAY_STORE_URL` | Google Play URL |
| `APP_BUNDLE_ID_IOS` | AASA 검증 reference |
| `APP_BUNDLE_ID_ANDROID` | assetlinks 검증 reference |

Local: `.dev.vars` (gitignored, `.dev.vars.example` 참고).
Prod: `wrangler secret put` + `wrangler.jsonc` 의 `vars`.

---

## Flutter 쪽과의 계약

[DEEPLINK.md](./DEEPLINK.md) 의 "계약" section 이 SSOT.

요약:

| 항목 | Flutter 책임 | 이 앱 책임 |
|---|---|---|
| `shortId` | nanoid 8자리 base62 생성 | 그대로 받음 |
| 카드 PNG | `RepaintBoundary` → 1200×630 PNG → R2/Storage | URL 만 받아 렌더 |
| Supabase insert | `share_card` row + 이미지 storage | row read only |
| URL 발송 | `share_plus` 의 text 에 URL 첨부 | OS sniff 기반 fallback |
| Deep link 라우팅 | `app_links` 패키지로 `/r/:shortId` 수신 | universal link attempt |

**계약 변경 시 양쪽 동시 PR 필수.** Flutter 의 share publish 함수와 이 앱의 `fetchShareCard` schema 가 한 쌍.

---

## 다음 작업 (우선순위)

| 우선 | 작업 | 재개 지시 |
|---|---|---|
| P0 | Supabase `share_card` 테이블 마이그레이션 | `"DEEPLINK.md §schema 의 SQL 을 supabase/migrations/ 에 마이그레이션으로 추가, RLS 는 select-only public"` |
| P0 | Flutter `SharePublisher` 작성 | `"flutter/lib/domain/services/share/share_publisher.dart 에 publish(report) → shortId. nanoid+supabase insert+R2 upload+share_plus 호출"` |
| P0 | AASA / assetlinks 실값 교체 | `"public/.well-known/ 두 파일에 실제 TEAMID + Play Console SHA256 박기. flutter/ios/Runner/Runner.entitlements 에 associated-domains 추가"` |
| P0 | Flutter `app_links` 라우팅 | `"flutter/lib/main.dart 에서 app_links 초기화 + /r/:shortId path → ReportPage 로 라우팅. cold start + warm 양쪽"` |
| P1 | OG image 동적 생성 (`/og/:shortId.png` route) | `"app/routes/og.\$shortId.tsx 추가. satori + @resvg/resvg-js 로 PNG 합성. og_image 가 비어있으면 이 endpoint 로 fallback"` |
| P1 | expires_at 만료 케이스 UI | `"loader 에서 throw new Response('Expired', { status: 410 }). root.tsx ErrorBoundary 의 410 케이스 다듬기"` |
| P2 | KakaoLink Feed Template (옵션) | `"flutter/lib/domain/services/share/kakao_share.dart — KakaoLink SDK Feed template 으로 카드 카드디자인·복수 버튼 직접 제어"` |
| P2 | 카톡 in-app browser fallback | `"CTA.tsx 에 카톡 in-app browser UA 감지 → intent:// (Android) 또는 외부 브라우저 강제 open"` |
| P3 | Analytics (link clicked → app opened → install funnel) | `"Cloudflare Analytics Engine 또는 Plausible 으로 클릭·체류·conversion 이벤트 측정"` |

---

## 빌드·테스트

```bash
cd react
pnpm install
pnpm dev          # http://localhost:5173
pnpm typecheck
pnpm build
pnpm preview      # wrangler dev (production worker simulation)
pnpm deploy       # Cloudflare 배포
```

---

## 디자인 룰

- **system font** 만 사용. SongMyung 등 web font 도입 금지 (카톡 미리보기에서 FOIT 로 카드 깨짐).
- **5단 hierarchy**: 24/16/14/13/12 px. 그 외 size 추가 금지.
- **컬러 4개**: `#1a1a1a` (text), `#666` (caption), `#c44` (accent — 점수 강조 only), `#f7f7f8` (bg).
- 카드 이미지는 **1200×630** OG 표준 ratio. ratio 깨지면 카톡·페북 미리보기에서 crop 됨.
