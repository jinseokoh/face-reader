# DEEPLINK.md — face share host architecture

공유 link 의 end-to-end 아키텍처 SSOT. Flutter 쪽 publish, Cloudflare 쪽 host, OG/카톡 미리보기, universal/app link, store fallback, deferred deep link 까지 한 문서.

마지막 업데이트: 2026-04-27 (token-based, storage 0)

---

## 1. 큰 그림

```
[Flutter 앱]
   │
   │ 1. 사용자 [공유] 탭
   │ 2. RepaintBoundary → PNG (1200×630, in-memory)
   │ 3. POST https://face.kr/api/share { type, userA, userB? } → { shortId }
   │ 4. share_plus 의 Share.shareXFiles([XFile.fromData(pngBytes, ...)],
   │    text: 'https://face.kr/r/$shortId') 으로 OS share sheet 발송
   │
   │   (storage 업로드 없음. PNG 는 카톡 thread attachment 로 1회성. URL 은 token 만.)
   ▼
[카톡 / iMessage / 페북]
   │ — 크롤러가 URL fetch
   │   → React app 의 SSR HTML 의 OG meta (title/description/og:image=/logo.png) 만 읽음
   │ — 사용자가 link 탭
   ▼
[받는 사람의 OS]
   │
   ├─ 앱 설치 OK + iOS:
   │     universal link 동작
   │  → Safari 안 거치고 앱 직접 open
   │  → Flutter 의 app_links 가 /r/:token 수신
   │  → ReportPage 로 라우팅 (token decode 는 server 에서만, app 은 token 자체로 lookup 또는 supabase 직접 fetch)
   │
   ├─ 앱 설치 OK + Android:
   │     app link 동작 (assetlinks 검증)
   │  → 앱 직접 open
   │
   └─ 앱 미설치:
         Safari/Chrome 으로 share host 페이지 진입
      → React Router v7 SSR loader 가 token decode + HMAC verify + faces fetch + 룰 적용 + 렌더
      → CTA.tsx 가 universal link 한 번 더 시도 (앱 설치 후 들어온 경우 대응)
      → 1.5s 후 fallback 으로 App Store / Play 이동
```

---

## 2. URL & Token

```
URL:   https://face.kr/r/{body}.{sig4}

body  = base64url(uuid bytes), no padding
       solo:    16 bytes  → 22자
       compat:  32 bytes  (uuidA bytes ‖ uuidB bytes) → 43자
sig4  = base64url( HMAC-SHA256(body_bytes, SHARE_TOKEN_SECRET).slice(0, 3) ) → 4자
```

### 길이
- solo:   `https://face.kr/r/` (18) + 22 + `.` (1) + 4 = 45자
- compat: `https://face.kr/r/` (18) + 43 + `.` (1) + 4 = 66자

카톡·iMessage·트위터 모두 OK (URL 본문은 어차피 카드로 가려짐).

### 위협 모델
| 위협 | 방어 |
|---|---|
| URL 위조 (가짜 점수 카드 face.kr 도메인으로 도배) | HMAC 4자 sig (24bit, brute force 1.6 × 10⁷ 시도) |
| uuid enumeration → 타인 face row 읽기 | uuid v4 randomness + Supabase RLS read-only public (write 차단) |
| 친밀·갈등 본문 노출 | URL·loader 응답·DB row 어디에도 본문 0. 룰로 highlights 만 generate. |
| 식별 정보 (이름·생년월일·얼굴 이미지) 노출 | URL 에 uuid 만, 본문엔 archetype/score/short_summary 만 |
| revoke | secret rotation 으로 일괄. 개별 revoke 는 supabase row 삭제 → 404 |

### 발행
Flutter 는 secret 안 가짐 → server 가 sign 한다. `POST /api/share` 한 번 round-trip.

```ts
// app/routes/api.share.ts (sign-only)
POST /api/share
  body: { type: "solo" | "compat", userA: uuid, userB?: uuid }
  resp: { shortId: "AAAA...AAA.XXXX" }
```

---

## 3. Schema — Flutter 의 `metrics` 테이블 그대로 + dart 엔진 SSOT

테이블 변경 0. Flutter (`SupabaseService.saveMetrics`) 가 이미 쓰고 있는 `metrics` (id, user_id, metrics_json, source, ethnicity, gender, age_group, expires_at, alias) 를 React 도 그대로 읽는다.

`metrics_json` 안에는 (`FaceReadingReport.toJsonString()` v3 capture-only):
- `schemaVersion`, `ethnicity`, `gender`, `ageGroup`, `timestamp`, `source`
- `metrics`: { id → rawValue (number) } — 17 frontal ratio/angle
- `lateralMetrics`: { id → rawValue } — 8 lateral, optional
- `faceShapeLabel`, `faceShape`

**PII 0개.** 이름·생년월일·얼굴 이미지·landmark 좌표 모두 들어가지 않는다. anon 노출 안전. RLS policy 한 줄만:

```sql
create policy "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());
```

archetype·score·attribute·rule·node 는 절대 저장하지 않는다. 엔진이 load 시점 재계산하는 구조 (engine v3). React 도 같은 엔진을 호출해 즉석 계산.

### 엔진 — `/shared/` Dart 패키지 + `build:shared`

```
/Users/chuck/Code/face/
├── flutter/                          # Flutter app — refine 에서 /shared/ 의존
├── react/                            # 이 share host — 컴파일된 JS import
└── shared/                           # 공유 엔진 SSOT
    ├── pubspec.yaml
    ├── lib/
    │   ├── face_engine.dart          # 단일 entry: runEngine(rawJson) → ShareOutput
    │   ├── physiognomy_scoring.dart  # flutter/lib/domain/services/ 에서 이전
    │   ├── attribute_derivation.dart
    │   ├── attribute_normalize.dart
    │   ├── score_calibration.dart
    │   ├── archetype.dart
    │   ├── face_metrics.dart
    │   └── reference_data.dart
    └── README.md
```

빌드:
```bash
# react/package.json
"build:shared": "cd ../shared && dart compile js -O2 lib/face_engine.dart -o ../react/app/lib/shared/face_engine.js"
```

산출물 (`react/app/lib/shared/face_engine.js`) 은 `.gitignore` (build artifact).

`face_engine.dart` 단일 entry 시그니처:
```dart
@JS()
external set runEngine(JSFunction fn);

void main() {
  runEngine = ((String rawJson) {
    final raw = jsonDecode(rawJson) as Map<String, dynamic>;
    // 1) raw → MetricResult Map
    // 2) z-score, age adjustment, scoreTree, derivation, normalize
    // 3) classifyArchetype
    // 4) ShareOutput { score, archetype, highlights[3] } 합성
    return jsify(out);
  }).toJS;
}
```

Flutter 측은 `pubspec.yaml` 의 `dependencies` 에 `path: ../shared` 로 의존. React 측은 `import { runEngine } from "./shared/face_engine.js"` 후 `JSON.parse(metrics_json)` → `runEngine` 호출.

**룰 / reference / quantile 변경 시 양쪽 PR 0번. `/shared/` 한 곳만 수정 → `build:shared` 한 번 → React 와 Flutter 동시 반영.**

### `share_payload` 컬럼 / `share_metrics` view 폐기

세션 초반 시도된 denormalized 캐시 (metrics 테이블의 `share_payload jsonb` 컬럼 + view) 는 모두 폐기. archetype·score·narrative 는 매 요청마다 dart 엔진이 즉석 계산해서 돌려준다 (요청당 ~30ms, edge cache 가 흡수). 이미 마이그레이션을 적용했다면 다음 SQL 로 정리:

```sql
drop view if exists share_metrics;
drop policy if exists "anon read shared" on metrics;
alter table metrics drop column if exists share_payload;

revoke select on metrics from anon;
grant select (id, metrics_json, expires_at) on metrics to anon;
create policy if not exists "anon read non-expired" on metrics
  for select to anon
  using (expires_at > now());
```

### 카드 portrait 자산

공유 카드의 인물 사진은 `react/public/{male,female}.png` 두 장 static. `archetype` 별 supabase storage URL·사용자 본인 얼굴 이미지·local Hive 썸네일 모두 사용 안 함 — privacy policy 위반 + 통일감 가치. gender 만 보고 `<img src={`/${gender}.png`}>` 로 swap. (refine/public/ 도 동일 두 장 보유.)

---

## 4. Flutter ↔ React 계약

### 4.1 데이터 계약

`SupabaseService.saveMetrics` 은 손대지 않는다. `metrics_json` (= `FaceReadingReport.toJsonString()` v3) 이 양쪽이 보는 SSOT.

React 가 받은 `metrics_json` 을 그대로 `runEngine(rawJson)` 으로 넘기면 끝. archetype·score·highlights 가 즉석 계산되어 돌아온다.

### 4.2 엔진 추출 (완료)

`flutter/lib/domain/services/` 의 physiognomy + compat 엔진과 `flutter/lib/data/constants/{face_reference_data,archetype_catchphrase}.dart` 가 모두 `/shared/lib/` 로 이동 완료. flutter 의 `pubspec.yaml` 은 `face_engine: { path: ../shared }` 의존, react·refine 은 `pnpm build:shared` 가 dart compile js -O1 으로 단일 JS 번들을 만들어 import. globalThis 에 `runEngine(metricsJson)` / `runCompat(a, b)` 두 함수가 등록된다.

### 4.3 Flutter `SharePublisher` (P0)

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

### 4.4 Flutter inbound deep link

```dart
// main.dart
final appLinks = AppLinks();
appLinks.uriLinkStream.listen((uri) {
  if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'r') {
    final token = uri.pathSegments[1];
    rootNavigatorKey.currentState?.pushNamed('/share/$token');
    // 앱 안에선 token 을 그대로 들고 다님. server-side decode 필요시
    // GET /api/decode?token=... 같은 endpoint 추가하거나, supabase 에서 직접 metadata fetch.
  }
});
```

---

## 5. AASA / assetlinks 설정

### 5.1 iOS — `apple-app-site-association`

`react/public/.well-known/apple-app-site-association` (확장자 **없음**, content-type `application/json`):

```json
{
  "applinks": {
    "details": [
      { "appIDs": ["TEAMID.com.scienceintegration.face"], "components": [{ "/": "/r/*" }] }
    ]
  }
}
```

Flutter iOS 쪽 (`ios/Runner/Runner.entitlements`):

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:face.kr</string>
</array>
```

검증: `https://search.developer.apple.com/appsearch-validation-tool/` 또는 `swcutil dl -d face.kr`.

### 5.2 Android — `assetlinks.json`

`react/public/.well-known/assetlinks.json`:

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

`android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="face.kr" android:pathPrefix="/r/" />
</intent-filter>
```

검증: `adb shell pm get-app-links com.scienceintegration.face`.

---

## 6. 미설치 사용자 처리

### 6.1 현재 (P0): React app SSR 페이지

받는 사람이 미설치 + link 탭 → React app 페이지 → logo + 점수 + tagline + 3 highlights + store CTA. 충분히 동작.

### 6.2 절대 쓰지 말 것

- **Branch.io / Adjust** — SaaS 비용. 자체 hosting 으로 충분.
- **Firebase Dynamic Links** — 2025-08-25 종료.
- **클립보드 토큰 + 첫 실행 시 read** — iOS 14 toast 노출, UX 손상.
- **Fingerprint deferred deep link (IP+UA)** — iOS 정확도 낮음.

---

## 7. 검증 체크리스트 (prod 배포 전)

- [ ] AASA 의 `appIDs` 에 실제 TEAMID 박혀있나
- [ ] assetlinks 의 SHA256 이 Play Console 의 release key 와 일치하나
- [ ] `https://face.kr/.well-known/apple-app-site-association` 가 redirect 없이 200 + `application/json` 으로 응답하나
- [ ] Flutter iOS `Runner.entitlements` 의 `applinks:face.kr`
- [ ] Flutter Android Manifest 의 `intent-filter` 에 `android:autoVerify="true"`
- [ ] Supabase RLS 가 select-only, anon key 가 service key 가 아닌가
- [ ] `wrangler secret put SHARE_TOKEN_SECRET` 등록됨, 32 bytes random
- [ ] Supabase RLS — `revoke select on metrics from anon` + `grant select (id, metrics_json, expires_at) on metrics to anon` + policy `expires_at > now()`. (옛 share_payload 컬럼/view 가 있다면 §3 의 drop SQL 로 정리)
- [ ] `react/public/{male,female}.png` 두 장 prod 디자인 컨펌 (1200×630 or 카드 크기 적정)
- [ ] dart 엔진 응답에 친밀 챕터 본문·갈등 시나리오·이름·생년월일·얼굴 이미지·raw landmark 0개 (`face_engine.dart::_composeShareOutput` / `_composeCompatOutput` 코드 review 필수)
- [ ] OG 미리보기: 카톡·iMessage·Facebook debugger 셋 다 logo + title + description 정상 표시
- [ ] 앱 설치 상태에서 카톡 link 탭 → 앱 직접 open
- [ ] 앱 미설치 상태에서 카톡 link 탭 → SSR 페이지 + store CTA
- [ ] 위조 sig (`/r/AAAA.XXXX`) → 403
- [ ] 길이 잘못된 token → 400
- [ ] 정상 sig + 존재 안 하는 uuid → 404

---

## 8. 참고

- Apple Universal Links: https://developer.apple.com/documentation/xcode/supporting-associated-domains
- Android App Links: https://developer.android.com/training/app-links/verify-android-applinks
- React Router v7 + Cloudflare: https://reactrouter.com/start/framework/deploying#cloudflare
- Web Crypto API (HMAC): https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/sign
- Firebase Dynamic Links shutdown: https://firebase.google.com/support/dynamic-links-faq
