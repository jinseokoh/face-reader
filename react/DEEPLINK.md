# DEEPLINK.md — face share host architecture

공유 link 의 end-to-end 아키텍처 SSOT. Flutter 쪽 publish, Cloudflare 쪽 host, OG/카톡 미리보기, universal/app link, store fallback, deferred deep link 까지 한 문서.

마지막 업데이트: 2026-04-26

---

## 1. 큰 그림

```
[Flutter 앱]
   │
   │ 1. 사용자 [공유] 탭
   │ 2. RepaintBoundary → PNG (1200×630)
   │ 3. nanoid → shortId (8자리 base62)
   │ 4. Supabase Storage / R2 upload (PNG)
   │ 5. Supabase insert into share_card (shortId, og_meta, …)
   │ 6. share_plus 로 URL https://share.face.app/r/{shortId} 발송
   ▼
[카톡 / iMessage / 페북]
   │ — 크롤러가 URL fetch
   │   → React app 의 SSR HTML 의 OG meta 만 읽음
   │ — 사용자가 link 탭
   ▼
[받는 사람의 OS]
   │
   ├─ 앱 설치 OK + iOS:
   │     universal link 동작
   │  → Safari 안 거치고 앱 직접 open
   │  → Flutter 의 app_links 가 /r/:shortId 수신
   │  → ReportPage 로 라우팅
   │
   ├─ 앱 설치 OK + Android:
   │     app link 동작 (assetlinks 검증)
   │  → 앱 직접 open
   │
   └─ 앱 미설치:
         Safari/Chrome 으로 share host 페이지 진입
      → React Router v7 SSR 이 카드+요약+CTA 렌더
      → CTA.tsx 가 universal link 한 번 더 시도 (앱 설치 후 들어온 경우 대응)
      → 1.5s 후 fallback 으로 App Store / Play 이동
```

---

## 2. Schema — `share_card` table

```sql
create table share_card (
  id text primary key,                                       -- short8 (nanoid base62)
  kind text not null check (kind in ('physiognomy', 'compat')),
  total_score int not null,
  label text not null,                                       -- "잘 맞는 흐름" 등
  tagline text not null,                                     -- 1~2 문장
  highlights jsonb default '[]'::jsonb,                      -- [{title, detail}, …] 최대 3개
  card_image_url text not null,                              -- 1200×630 PNG
  og_title text not null,                                    -- "둘의 궁합 87점 — AI 관상가"
  og_description text not null,
  og_image text,                                             -- null 이면 card_image_url 사용
  created_at timestamptz default now(),
  expires_at timestamptz default now() + interval '90 days'
);
create index on share_card (expires_at);

-- RLS: anon 은 select-only, 만료 안 된 row 만
alter table share_card enable row level security;
create policy "public read non-expired" on share_card
  for select using (expires_at > now());
```

**저장 정책 — 절대 금지 항목**:
- 친밀(intimacy) 챕터 본문
- 갈등 시나리오 상세 텍스트
- 사용자 이름·생년월일·얼굴 이미지
- raw landmark 데이터·z-score map

→ row 에 들어가는 건 카드 페이지에 보일 minimal subset 뿐.

---

## 3. Flutter ↔ React 계약

### 3.1 `ShareCardData` (TypeScript) ↔ `ShareCard` (Dart) 1:1

| ShareCardData (TS)   | share_card column   | Flutter 출처                          |
|---|---|---|
| `shortId`            | `id`                | `nanoid(8)` 클라이언트 생성              |
| `kind`               | `kind`              | report 종류 ('physiognomy'/'compat')   |
| `cardImageUrl`       | `card_image_url`    | RepaintBoundary → R2 upload URL        |
| `label`              | `label`             | CompatLabel.label 또는 archetype label |
| `totalScore`         | `total_score`       | report.total                           |
| `tagline`            | `tagline`           | summary 의 첫 1~2 문장                  |
| `highlights[]`       | `highlights` (jsonb)| corePoints top 3 의 title + 짧은 detail|
| `ogTitle/Description`| `og_*`              | publish 함수에서 합성                    |
| `ogImage`            | `og_image`          | null OK (card_image_url fallback)      |
| `expiresAt`          | `expires_at`        | DB default                             |

### 3.2 Flutter publish 함수 (P0 작업)

```dart
// lib/domain/services/share/share_publisher.dart
class SharePublisher {
  Future<String> publish(FaceReadingReport|CompatibilityReport report) async {
    final shortId = _nanoid(8);
    final pngBytes = await _renderCard(report);                     // RepaintBoundary
    final imageUrl = await _uploadToR2(pngBytes, shortId);          // R2 또는 Supabase Storage
    await _supabase.from('share_card').insert({
      'id': shortId,
      'kind': report is CompatibilityReport ? 'compat' : 'physiognomy',
      'total_score': report.total.round(),
      'label': _extractLabel(report),
      'tagline': _extractTagline(report),
      'highlights': _extractHighlights(report),                     // 3개
      'card_image_url': imageUrl,
      'og_title': _composeOgTitle(report),
      'og_description': _composeOgDescription(report),
      'og_image': imageUrl,
    });
    final url = '${kShareHostBase}/r/$shortId';
    await Share.shareUri(Uri.parse(url));                           // share_plus
    return shortId;
  }
}
```

### 3.3 Flutter inbound deep link

```dart
// main.dart
final appLinks = AppLinks();
appLinks.uriLinkStream.listen((uri) {
  if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'r') {
    final shortId = uri.pathSegments[1];
    rootNavigatorKey.currentState?.pushNamed('/share/$shortId');
  }
});
```

---

## 4. AASA / assetlinks 설정

### 4.1 iOS — `apple-app-site-association`

`react/public/.well-known/apple-app-site-association` (확장자 **없음**, content-type `application/json`):

```json
{
  "applinks": {
    "details": [
      { "appIDs": ["TEAMID.com.example.face"], "components": [{ "/": "/r/*" }] }
    ]
  }
}
```

Flutter iOS 쪽 (`ios/Runner/Runner.entitlements`):

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:share.face.app</string>
</array>
```

검증: `https://search.developer.apple.com/appsearch-validation-tool/` 또는 `swcutil dl -d share.face.app`.

### 4.2 Android — `assetlinks.json`

`react/public/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.face",
      "sha256_cert_fingerprints": ["XX:XX:..."]
    }
  }
]
```

`android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="share.face.app" android:pathPrefix="/r/" />
</intent-filter>
```

검증: `adb shell pm get-app-links com.example.face`.

---

## 5. 미설치 사용자 처리

### 5.1 현재 (P0): React app SSR 페이지

받는 사람이 미설치 + link 탭 → React app 페이지 → 카드 + 요약 + 3 highlights + store CTA. 충분히 동작.

### 5.2 P2 옵션 — App Clip / Instant App

**iOS App Clip**: 10MB 이하 mini-app 으로 카드 콘텐츠를 즉시 표시. NSUserActivity 로 full-app handoff.
**Android Instant App**: 동일 컨셉. Play Console 에서 별도 module 빌드.

장점: 미설치 사용자에게도 "앱 같은 경험" 제공, install conversion 상승.
단점: 빌드 module 추가, 10MB 제한 (face mesh TFLite 가 클 수 있음 → 카드 표시만 하는 lite module 필요).

### 5.3 절대 쓰지 말 것

- **Branch.io / Adjust** — SaaS 비용. 자체 hosting 으로 충분.
- **Firebase Dynamic Links** — 2025-08-25 종료.
- **클립보드 토큰 + 첫 실행 시 read** — iOS 14 toast 노출, UX 손상.
- **Fingerprint deferred deep link (IP+UA)** — iOS 정확도 낮음.

---

## 6. 대안 stack — Hono + JSX on Workers

React Router v7 stack 이 부담스럽거나 더 얇게 가고 싶을 때.

### 6.1 비교

| 항목 | RR7 + Cloudflare (현재) | Hono + JSX |
|---|---|---|
| 학습 곡선 | RR7 익히면 0 | Hono 1 일 |
| 빌드 산물 크기 | 큼 (RR7 runtime) | 작음 |
| Cold start | ~50ms | <5ms |
| RSC / Loader | ○ | ✗ (직접 fetch) |
| TypeScript | ◎ | ◎ |
| React component reuse | ◎ | △ (JSX SSR만) |
| 페이지 1 개짜리에 적합 | △ (overkill) | ◎ |

### 6.2 Hono 버전 — share host scaffold

`package.json`:

```json
{
  "name": "face-share-host-hono",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.4",
    "hono": "^4.6.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20251101.0",
    "wrangler": "^3.85.0"
  }
}
```

`wrangler.jsonc`:

```jsonc
{
  "name": "face-share-host-hono",
  "compatibility_date": "2026-04-26",
  "main": "src/index.tsx",
  "vars": { "APP_LINK_BASE": "https://share.face.app/r/", "...": "" }
}
```

`src/index.tsx` — 한 파일로 끝:

```tsx
import { Hono } from "hono";
import { html } from "hono/html";
import { createClient } from "@supabase/supabase-js";

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  APP_LINK_BASE: string;
  APP_STORE_URL: string;
  PLAY_STORE_URL: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.get("/", (c) =>
  c.html(html`<!doctype html><html lang="ko"><body>
    <main><h1>AI 관상가</h1><p>공유 link host</p></main>
  </body></html>`),
);

app.get("/r/:shortId", async (c) => {
  const shortId = c.req.param("shortId");
  const sb = createClient(c.env.SUPABASE_URL, c.env.SUPABASE_ANON_KEY);
  const { data } = await sb
    .from("share_card")
    .select("*")
    .eq("id", shortId)
    .maybeSingle();

  if (!data) return c.notFound();
  if (new Date(data.expires_at) < new Date()) {
    return c.html(html`<h1>만료된 카드입니다</h1>`, 410);
  }

  const url = `${c.env.APP_LINK_BASE}${shortId}`;
  return c.html(html`
    <!doctype html>
    <html lang="ko">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${data.og_title}</title>
        <meta property="og:type" content="website" />
        <meta property="og:title" content="${data.og_title}" />
        <meta property="og:description" content="${data.og_description}" />
        <meta property="og:image" content="${data.og_image ?? data.card_image_url}" />
        <meta property="og:url" content="${url}" />
        <meta name="twitter:card" content="summary_large_image" />
      </head>
      <body>
        <main>
          <img src="${data.card_image_url}" alt="공유 카드" style="width:100%" />
          <h1>${data.label} <strong>${data.total_score}점</strong></h1>
          <p>${data.tagline}</p>
          <a href="${url}">앱에서 전체 결과 보기</a>
          <script>
            (function () {
              var ua = navigator.userAgent;
              var iOS = /iPhone|iPad|iPod/.test(ua);
              var And = /Android/.test(ua);
              if (!iOS && !And) return;
              var t = Date.now();
              location.href = "${url}";
              setTimeout(function () {
                if (Date.now() - t < 2500 && document.visibilityState === "visible") {
                  location.href = "${iOS ? c.env.APP_STORE_URL : c.env.PLAY_STORE_URL}";
                }
              }, 1500);
            })();
          </script>
        </main>
      </body>
    </html>
  `);
});

app.get("/.well-known/apple-app-site-association", (c) =>
  c.json({
    applinks: {
      details: [{ appIDs: ["TEAMID.com.example.face"], components: [{ "/": "/r/*" }] }],
    },
  }),
);

app.get("/.well-known/assetlinks.json", (c) =>
  c.json([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: "com.example.face",
        sha256_cert_fingerprints: ["XX:XX:..."],
      },
    },
  ]),
);

export default app;
```

**총 4 파일 (`package.json`, `wrangler.jsonc`, `tsconfig.json`, `src/index.tsx`).** RR7 의 1/5 코드로 동일 기능.

### 6.3 언제 Hono 로 갈아탈까

- 페이지 수가 1~2 개 이상으로 늘지 않을 때
- React component 를 Flutter 쪽과 공유할 일이 없을 때
- Cold start 가 카톡 viral 에서 병목이 될 때
- RSC / streaming / loader chain 같은 RR7 기능이 정말 필요 없을 때

현재는 RR7 으로 두되, P3 시점에 페이지 복잡도가 안 늘면 Hono 로 마이그레이션 검토.

---

## 7. 검증 체크리스트 (prod 배포 전)

- [ ] AASA 의 `appIDs` 에 실제 TEAMID 박혀있나
- [ ] assetlinks 의 SHA256 이 Play Console 의 release key 와 일치하나
- [ ] `https://share.face.app/.well-known/apple-app-site-association` 가 redirect 없이 200 + `application/json` content-type 으로 응답하나
- [ ] Flutter iOS `Runner.entitlements` 의 `applinks:` 도메인 일치
- [ ] Flutter Android Manifest 의 `intent-filter` 에 `android:autoVerify="true"`
- [ ] Supabase RLS 가 select-only 이고 anon key 가 service key 가 아닌가
- [ ] `expires_at` row 가 410 으로 응답하나
- [ ] OG 미리보기: 카톡·iMessage·Facebook debugger 셋 다 카드 정상 표시
- [ ] 앱 설치 상태에서 카톡 link 탭 → 앱 직접 open
- [ ] 앱 미설치 상태에서 카톡 link 탭 → SSR 페이지 + store CTA
- [ ] 카드 이미지 1200×630 비율 — crop 안 됨

---

## 8. 참고

- Apple Universal Links: https://developer.apple.com/documentation/xcode/supporting-associated-domains
- Android App Links: https://developer.android.com/training/app-links/verify-android-applinks
- React Router v7 + Cloudflare: https://reactrouter.com/start/framework/deploying#cloudflare
- Hono on Cloudflare Workers: https://hono.dev/docs/getting-started/cloudflare-workers
- Firebase Dynamic Links shutdown: https://firebase.google.com/support/dynamic-links-faq
