# HOW-IT-WORKS — face share host

`face.kr` 의 share host. Flutter 앱이 발행하는 `/r/{token}` link 를 받아 카톡·iMessage·Facebook 미리보기 카드 (SSR OG meta) 와 미설치 사용자용 랜딩·store CTA 를 서빙한다. Cloudflare Workers 위에서 React Router v7 SSR 로 동작.

마지막 업데이트: 2026-05-03

---

## 1. 큰 그림

```
[Flutter 앱]
   │ 1. 사용자 [공유] 탭
   │ 2. RepaintBoundary → 1200×630 PNG (in-memory, R2/Storage 0)
   │ 3. POST face.kr/api/share { type, userA, userB? } → { shortId }
   │ 4. share_plus.shareXFiles([PNG], text: 'face.kr/r/${shortId}')
   ▼
[카톡 / iMessage / 페북]
   │ 크롤러: URL fetch → SSR HTML 의 OG meta (title/description/og:image) 만 읽음
   │ 사용자: link 탭
   ▼
[받는 사람의 OS]
   ├─ 앱 설치 + iOS  → universal link → 앱 직접 open → app_links 가 /r/:token 라우팅
   ├─ 앱 설치 + Android → app link (assetlinks 검증) → 앱 직접 open
   └─ 앱 미설치 → 이 React app 의 SSR 페이지
                  (token decode + HMAC verify + metrics fetch + 엔진 호출 + 카드 렌더)
                  → CTA 가 universal link 1.5s 시도 후 store fallback
```

핵심 원칙:
- **OG meta 는 SSR 강제** — 카톡 크롤러는 JS 실행 안 함. SPA 금지.
- **Cloudflare Workers 외 deployment target 금지** — 카톡 viral 트래픽 폭주 시 비용 폭발 회피.
- **Storage / R2 / KV 0** — 카드 PNG 는 카톡 attachment 로 1회성. URL 에는 token 만.
- **친밀 챕터·갈등 시나리오 본문 노출 금지** — 응답·DB·URL 어디에도 0. teaser·점수·archetype label 만.
- **사용자 PII 노출 금지** — URL 에 uuid, 본문에 archetype/score/short_summary 만. 이름·생년월일·얼굴 이미지 0.

---

## 2. URL & Token 구조

```
URL:   https://face.kr/r/{body}.{sig4}

body  = base64url(uuid bytes), no padding
       solo:    16 bytes  → 22자
       compat:  32 bytes  (uuidA‖uuidB) → 43자
sig4  = base64url( HMAC-SHA256(body_bytes, SHARE_TOKEN_SECRET).slice(0, 3) ) → 4자
```

길이:
- solo: `https://face.kr/r/` (18) + 22 + `.` (1) + 4 = **45자**
- compat: 같은 prefix + 43 + `.` + 4 = **66자**

발행:
- Flutter 는 secret 미보유 → server (`POST /api/share`) 가 sign.
- request: `{ type: "solo" | "compat", userA: uuid, userB?: uuid }`
- response: `{ shortId: "AAA....XXX.YYYY" }`

위협 모델:

| 위협 | 방어 |
| --- | --- |
| URL 위조 (가짜 점수 카드 face.kr 도메인 도배) | HMAC 4자 sig (24bit, brute force 1.6 × 10⁷) |
| uuid enumeration → 타인 metrics row 읽기 | uuid v4 randomness + Supabase RLS read-only |
| 친밀·갈등 본문 노출 | 룰로 highlights 만 generate. 본문 응답·DB row 어디에도 0 |
| PII (이름·생년월일·얼굴 이미지) 노출 | `metrics_json` 안에 PII 0개. URL 에 uuid 만 |
| revoke | secret rotation (일괄) / supabase row 삭제 (개별 → 404) |

---

## 3. 데이터 — Flutter 의 `metrics` 테이블 그대로

테이블 변경 0. Flutter (`SupabaseService.saveMetrics`) 가 이미 쓰고 있는 `metrics` (id, user_id, metrics_json, source, ethnicity, gender, age_group, expires_at, alias) 를 React 가 그대로 read.

`metrics_json` 안에는 (`FaceReadingReport.toJsonString()` v3 capture-only):
- `schemaVersion`, `ethnicity`, `gender`, `ageGroup`, `timestamp`, `source`
- `metrics`: { id → rawValue (number) } — 17 frontal ratio/angle
- `lateralMetrics`: { id → rawValue } — 8 lateral, optional
- `faceShapeLabel`, `faceShape`

**PII 0개.** 이름·생년월일·얼굴 이미지·landmark 좌표 모두 안 들어감 → anon read 안전.

RLS policy (Supabase):

```sql
revoke select on metrics from anon;
grant select (id, metrics_json, expires_at) on metrics to anon;
create policy "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());
```

`share_payload jsonb` 컬럼·`share_metrics` view 같은 denormalized 캐시는 사용 안 함. archetype·score·attribute·rule·node 는 절대 DB 저장 금지 — 엔진이 load 시점 재계산.

---

## 4. 엔진 — `/shared/` Dart 패키지 SSOT

```
/Users/chuck/Code/face/
├── flutter/                          # Flutter app — pubspec 에 path: ../shared 의존
├── react/                            # 이 share host — 컴파일된 JS import
└── shared/                           # 공유 엔진 SSOT
    ├── pubspec.yaml
    └── lib/
        ├── face_engine.dart          # 단일 entry: globalThis.runEngine / runCompat
        ├── physiognomy_scoring.dart
        ├── attribute_derivation.dart
        ├── attribute_normalize.dart
        ├── score_calibration.dart
        ├── archetype.dart
        ├── face_metrics.dart
        └── reference_data.dart
```

빌드: `pnpm build:shared` → `dart compile js -O1 ../shared/lib/face_engine.dart -o app/lib/shared/face_engine.js`

산출물 (`app/lib/shared/face_engine.js`) 은 build artifact (`.gitignore`).

엔진 호출 (`app/lib/traits.ts`):
```ts
import "./shared/face_engine.js";  // side-effect: globalThis.runEngine / runCompat 등록
const out = JSON.parse(globalThis.runEngine(JSON.stringify(row.raw)));
```

**룰·reference·quantile 변경 시 양쪽 PR 0번. `/shared/` 한 곳만 수정 → `build:shared` 한 번 → React + Flutter 동시 반영.** engine 재이식·React 쪽 룰 재작성 절대 금지.

---

## 5. 디렉토리 (편집 SSOT)

| 경로                            | 역할 |
| ------------------------------- | ---- |
| `workers/app.ts`                | Cloudflare Worker fetch handler (RR7 createRequestHandler) |
| `app/entry.server.tsx`          | RR7 Cloudflare 런타임 entry (`@react-router/node` 안 씀) |
| `app/root.tsx`                  | 루트 layout + ErrorBoundary (404/410 handling) |
| `app/routes.ts`                 | 명시적 라우트 정의 (3개) |
| `app/routes/_index.tsx`         | landing — dev 모드에서 데모 token 두 개 발행해 표시 |
| `app/routes/share.tsx`          | `/r/:shortId` loader (decode → fetch → render) + meta + 컴포넌트 |
| `app/routes/api.share.ts`       | `POST /api/share` sign-only 발행 endpoint |
| `app/lib/codec.ts`              | uuid ↔ bytes ↔ base64url helper |
| `app/lib/share-id.ts`           | encode/decode + HMAC-SHA256 sig4 verify (constant-time) |
| `app/lib/supabase.ts`           | `fetchMetrics(env, ids)` — REST 호출, demo uuid 는 inline data |
| `app/lib/traits.ts`             | `renderSolo` / `renderCompat` — 엔진 호출 후 `RenderedShare` 합성 |
| `app/lib/shared/face_engine.js` | `pnpm build:shared` 산출물. **commit 금지** |
| `app/lib/types.ts`              | `RawMetrics`, `MetricsRow`, `EngineOutput`, `CompatOutput`, `RenderedShare` SSOT |
| `app/components/ShareCard.tsx`  | 카드 UI — Solo (archetype + chips + top3) / Compat (label + 5요소 페어 + chips) |
| `app/components/CTA.tsx`        | universal link 시도 + 1.5s 후 store fallback (UA 분기) |
| `public/{male,female}.png`      | 카드 portrait — gender 만 보고 swap. archetype 별 storage URL·본인 얼굴 이미지 사용 0 |
| `public/logo.png`               | OG image (1장 static, 1200×630 권장) |
| `public/.well-known/*`          | AASA · assetlinks (prod 전 실값 교체) |
| `wrangler.jsonc`                | env vars + assets binding |

---

## 6. 환경 변수

`wrangler.jsonc` 의 `vars` (public, source-controlled OK):

| key | 용도 |
| --- | --- |
| `APP_LINK_BASE` | universal link prefix (`https://face.kr/r/`) |
| `APP_STORE_URL` | iOS App Store URL |
| `PLAY_STORE_URL` | Google Play URL |
| `APP_BUNDLE_ID_IOS` | AASA 검증 reference |
| `APP_BUNDLE_ID_ANDROID` | assetlinks 검증 reference |

Secrets (`wrangler secret put`, **commit 금지**):

| key | 용도 |
| --- | --- |
| `SHARE_TOKEN_SECRET` | HMAC-SHA256 secret (32 bytes random). token 위조 방지의 유일한 보호막 |
| `SUPABASE_URL` | `metrics` 테이블 read |
| `SUPABASE_ANON_KEY` | RLS 가 read-only 보장 전제 |

Local: `.dev.vars` (gitignored, `.dev.vars.example` 참고).
Prod: `wrangler secret put SHARE_TOKEN_SECRET` 등.

---

## 7. Flutter ↔ React 계약

### 7.1 SharePublisher (Flutter 측)

```dart
class SharePublisher {
  Future<void> publish({
    required String userA,
    String? userB,
    required Uint8List cardPng,
  }) async {
    final res = await http.post(
      Uri.parse('https://face.kr/api/share'),
      body: jsonEncode({
        'type': userB == null ? 'solo' : 'compat',
        'userA': userA,
        if (userB != null) 'userB': userB,
      }),
      headers: {'content-type': 'application/json'},
    );
    final shortId = (jsonDecode(res.body) as Map)['shortId'] as String;
    final url = 'https://face.kr/r/$shortId';
    await Share.shareXFiles(
      [XFile.fromData(cardPng, mimeType: 'image/png', name: 'face-card.png')],
      text: url,
    );
  }
}
```

### 7.2 Inbound deep link (Flutter)

```dart
final appLinks = AppLinks();
appLinks.uriLinkStream.listen((uri) {
  if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'r') {
    final token = uri.pathSegments[1];
    rootNavigatorKey.currentState?.pushNamed('/share/$token');
  }
});
```

cold start + warm 양쪽 처리. token decode 는 server 가 담당 — 앱은 token 그대로 들고 다님.

---

## 8. AASA / assetlinks

### iOS — `apple-app-site-association`

`public/.well-known/apple-app-site-association` (확장자 **없음**, `application/json`):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.scienceintegration.face"],
        "components": [{ "/": "/r/*" }]
      }
    ]
  }
}
```

Flutter `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:face.kr</string>
</array>
```

검증: `swcutil dl -d face.kr` 또는 https://search.developer.apple.com/appsearch-validation-tool/

### Android — `assetlinks.json`

`public/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.scienceintegration.face",
      "sha256_cert_fingerprints": ["XX:XX:..."]
    }
  }
]
```

Flutter `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="face.kr" android:pathPrefix="/r/" />
</intent-filter>
```

검증: `adb shell pm get-app-links com.scienceintegration.face`

content-type 이 `application/json` 이어야 iOS 가 인식. Cloudflare Workers 의 assets binding 이 자동 서빙.

---

## 9. 빌드·테스트

```bash
cd react
pnpm install
pnpm build:shared    # /shared 의 dart 엔진을 JS 로 컴파일 (필수, 첫 실행 전)
pnpm dev             # http://localhost:5173 (또는 5174/5175)
pnpm typecheck
pnpm build
pnpm preview         # wrangler dev (production worker simulation)
pnpm deploy          # Cloudflare 배포
```

**Demo**: dev server 띄우고 `/` 로 접속 → solo·compat 데모 token link 두 개 자동 발행.
uuid 가 `00000000-0000-0000-0000-XXXXXXXXXXXX` 패턴이면 supabase 안 거치고 inline demo data 응답 (dev/preview 모두 동작).

---

## 10. 디자인 룰

- **system font 만 사용.** SongMyung 등 web font 도입 금지 (flutter/CLAUDE.md 의 폰트 룰은 여기 적용 X).
- **5단 hierarchy**: 24/16/14/13/12 px. 그 외 size 추가 금지.
- **컬러 4개**: `#1a1a1a` (text), `#666` (caption), `#c44` (accent — 점수 강조 only), `#f7f7f8` (bg).
- **OG image**: `public/logo.png` static 1장. 1200×630 ratio (안 맞으면 카톡 미리보기 letterbox/crop).
- **카드 portrait**: `public/{male,female}.png` 두 장 static. gender 만 보고 swap.

---

## 11. 절대 쓰지 말 것

- **Branch.io / Adjust** — SaaS 비용. 자체 hosting 으로 충분.
- **Firebase Dynamic Links** — 2025-08-25 종료.
- **클립보드 토큰 + 첫 실행 시 read** — iOS 14 toast 노출, UX 손상.
- **Fingerprint deferred deep link (IP+UA)** — iOS 정확도 낮음.
- **Vercel / 기타 deployment target** — Cloudflare Workers 외 추가 금지.

---

## 12. 참고

- Apple Universal Links: https://developer.apple.com/documentation/xcode/supporting-associated-domains
- Android App Links: https://developer.android.com/training/app-links/verify-android-applinks
- React Router v7 + Cloudflare: https://reactrouter.com/start/framework/deploying#cloudflare
- Web Crypto API (HMAC): https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/sign
- Firebase Dynamic Links shutdown: https://firebase.google.com/support/dynamic-links-faq
