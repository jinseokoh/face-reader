# face-share-host

Cloudflare Workers 위에 올라가는 React Router v7 SSR 앱. Flutter 앱이 생성한 공유 link (`/r/{shortId}`) 의 host — 카톡·iMessage 미리보기 카드 (동적 OG meta) + 받는 사람의 OS 기준 universal/app link 시도 → 미설치 시 store fallback.

## 왜 React Router v7 + Cloudflare?

- **OG meta 는 SSR 필수** — 카톡 크롤러는 JS 실행 안 함. SPA 안 된다.
- **Vercel 회피** — 카톡 viral 트래픽 폭주 시 비용 위험. Cloudflare 는 bandwidth unmetered.
- **OpenNext 또는 cloudflare-vite-plugin** — 2026 표준 React + edge stack.

대안 (더 얇게 가고 싶을 때): **Hono + JSX on Workers**. 자세한 비교는 [DEEPLINK.md](./DEEPLINK.md) 참조.

## Stack

- React Router v7 (SSR 모드)
- Cloudflare Workers (`@cloudflare/vite-plugin`)
- Supabase JS (`share_card` row 조회)
- TypeScript / Vite 6

## 동작 흐름

1. Flutter 앱 [공유] 탭 → 카드 PNG 생성 + Supabase `share_card` row insert + 이미지 R2/Storage 업로드
2. share URL `https://face.kr/r/{shortId}` 을 share_plus 또는 KakaoLink 로 발송
3. 받는 사람이 link 탭
   - 앱 설치됨: universal/app link 가 앱을 직접 연다 (Flutter 의 `app_links` 가 `/r/:shortId` 라우팅)
   - 앱 미설치: 이 React 앱이 카드 + 요약 + teaser + store CTA 를 SSR 로 보여준다
4. 카톡 / iMessage / 페북 크롤러: `meta` export 의 OG tag 를 읽어 카드 미리보기 렌더

## Setup

```bash
cd react
pnpm install
cp .dev.vars.example .dev.vars   # SUPABASE_URL 등 채우기
pnpm dev                          # http://localhost:5173
```

`/r/demo` 로 접속하면 supabase 없이도 데모 카드 동작.

## Deploy

```bash
pnpm deploy                       # wrangler deploy
```

`wrangler.jsonc` 의 `vars` 와 secret 명령으로 환경 변수 주입:

```bash
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_ANON_KEY
```

## Routes

- `/` — 랜딩 (앱 다운로드 안내만)
- `/r/:shortId` — 공유 카드 페이지 (loader 가 supabase fetch, meta 가 OG 동적 주입)

## 디렉토리

```
react/
├── workers/app.ts                  # Cloudflare Worker fetch handler (RR7 createRequestHandler)
├── app/
│   ├── root.tsx                    # 루트 레이아웃 + ErrorBoundary
│   ├── routes.ts                   # 라우트 정의
│   ├── routes/_index.tsx           # 랜딩
│   ├── routes/share.tsx            # /r/:shortId (loader + meta + UI)
│   ├── components/
│   │   ├── ShareCard.tsx           # 카드 + 요약 + highlights (3 항목)
│   │   └── CTA.tsx                 # universal link 시도 + store fallback
│   ├── lib/
│   │   ├── supabase.ts             # share_card row 조회
│   │   └── types.ts                # ShareCardData 타입
│   └── app.css                     # 전역 스타일
├── public/
│   └── .well-known/
│       ├── apple-app-site-association
│       └── assetlinks.json
├── react-router.config.ts
├── vite.config.ts
├── wrangler.jsonc
├── tsconfig.json
├── DEEPLINK.md                     # 아키텍처 SSOT — Flutter 와의 계약, AASA, 대안 stack
├── CLAUDE.md                       # AI 세션 오리엔테이션
└── package.json
```

## Supabase `share_card` schema (참고)

```sql
create table share_card (
  id text primary key,                                  -- short8 (nanoid base62)
  kind text not null check (kind in ('physiognomy', 'compat')),
  total_score int not null,
  label text not null,
  tagline text not null,
  highlights jsonb default '[]'::jsonb,
  card_image_url text not null,
  og_title text not null,
  og_description text not null,
  og_image text,
  created_at timestamptz default now(),
  expires_at timestamptz default now() + interval '90 days'
);
create index on share_card (expires_at);
```

저장 정책:

- 친밀(intimacy) 챕터·갈등 시나리오 본문은 row 에 **저장하지 않음** (privacy + 카톡 단톡 leak 방지)
- expires_at 90일 — pg_cron 으로 정기 삭제

## AASA / assetlinks

`public/.well-known/` 의 두 파일은 prod 배포 전에 실제 값으로 교체:

- `apple-app-site-association` — `appIDs` 의 `TEAMID.bundleId`
- `assetlinks.json` — Play Console > Setup > App signing 의 SHA256 fingerprint

Cloudflare Workers 의 assets binding 이 자동으로 서빙. content-type 이 `application/json` 이어야 iOS 가 인식 (`apple-app-site-association` 은 확장자 없음 — 그대로 둘 것).

## OG image 동적 생성 (P2)

현재는 supabase row 의 `og_image` URL 그대로 사용. 추후 satori + @resvg/resvg-js 로 `/og/:shortId.png` route 추가하면 텍스트만으로 카드 PNG 동적 생성 가능 — 이미지 별도 업로드 불필요.

## 마이그레이션 메모

기존 Vite + React 19 SPA scaffold 를 RR7 SSR 로 재구성했습니다. 의존성 변경됐으므로:

```bash
rm -rf node_modules pnpm-lock.yaml
pnpm install
```

`src/` 의 옛 SPA scaffold 와 `index.html`, `tsconfig.app.json`, `tsconfig.node.json`, `eslint.config.js` 는 이 stack 에서 사용하지 않으므로 삭제 가능.
