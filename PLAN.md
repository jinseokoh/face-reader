# PLAN — iOS 앱 레코드 이관 (facely → MeSo) · **철회됨**

> 🚫 **이 계획은 실행하지 않는다 (2026-08-23 철회).**
>
> App Store 리젝을 두 번 받고 이미 승인된 MeSo 앱의 껍데기를 빌리려던 우회였다.
> 정식 심사로 정면 돌파하기로 방향을 바꿔 **번들 ID 를 `…facely` 로 되돌렸다.**
> appeal 이 통하지 않으면 2차 대안으로 이 문서를 다시 꺼낸다 — 그래서 지우지
> 않고 남긴다.
>
> 되돌린 것: `project.pbxproj`(6곳) · `web/wrangler.jsonc` 의
> `APP_BUNDLE_ID_IOS` · `apple-app-site-association` 의 appID ·
> `coin_service.dart` 의 iOS 제품 ID(`meso_*` → `coin_3`/`coin_14`, 두 스토어
> 동일). `GoogleService-Info.plist` 는 애초에 `…facely` 라 손댈 것이 없었다.
>
> **아래 본문의 번들 ID 는 그 시절 기준이다.** 다시 실행할 때만 유효하다.

지금 iOS 빌드는 번들 ID 가 `com.scienceintegration.facely` 다. 이걸 이미 승인되어
있는 MeSo 앱의 번들 ID `com.scienceintegration.meetsocrates` 로 바꾼다.

번들 ID 를 바꾸면 Apple 은 이 앱을 "완전히 다른 앱"으로 취급한다. 그래서 번들 ID
에 묶여 있던 것들(Firebase 앱 등록, 인앱 상품, 광고 단위, 유니버설 링크, 각종
capability)을 전부 새 번들 ID 기준으로 다시 만들어야 한다. **이 문서는 그
"다시 만들어야 하는 것들"의 목록과 방법이다.**

Android 는 이미 Play 에 출시돼 있고 번들 ID 도 그대로 `…facely` 를 쓴다.
**Android 쪽은 아무것도 건드리지 않는다.**

---

## 기본 정보

| 항목       | 값                                                    |
| ---------- | ----------------------------------------------------- |
| Team ID    | `279L8K77C3`                                          |
| 새 번들 ID | `com.scienceintegration.meetsocrates`                 |
| 옛 번들 ID | `com.scienceintegration.facely` (iOS 는 미출시 상태)  |
| Apple ID   | `6478495062`                                          |

---

## 진행 현황

| 단계 | 작업 | 상태 |
| ---- | ---- | ---- |
| 1 | App ID capability (3개 전부 활성 확인) | ✅ 변경 0건 |
| 2 | Firebase iOS 앱 등록 + plist 교체 | ✅ |
| 3 | 번들 ID 6곳 | ✅ |
| 4 | 카카오 번들 ID 교체 + 앱스토어 ID | ✅ |
| 5 | RevenueCat 번들 ID 교체 + 상품 import | ✅ public key 유지 |
| 6 | 인앱 상품 표시 이름·설명·가격 | ✅ 심사 스크린샷은 10단계로 이월 |
| 7 | AdMob 앱·광고 단위 → plist·`.env` | ✅ 코드 반영 완료 · 인증 대기 |
| 8-a·b | AASA 교정 + 배포 | ✅ Team ID `TDP4V3QVVM`→`279L8K77C3` 버그 수정 |
| 8-c | 워커 env `APP_BUNDLE_ID_IOS` | ✅ `APP_STORE_URL` 은 10단계로 보류 |
| 8-d | `app-ads.txt` 신규 배포 | ✅ 크롤링 대기 (최대 24h) |
| 9 | ASC 새 버전 + 등록 정보 | ⬜ |
| 10 | 스크린샷·빌드 업로드·제출 | ⬜ |

## 역할 분담 (한눈에)

**원칙** — 웹 콘솔 로그인이 필요한 작업은 전부 사용자, 리포지토리 파일 수정은
전부 Claude.

| 단계 | 작업                     | 하는 곳            | 👤 사용자 | 🤖 Claude |
| ---- | ------------------------ | ------------------ | :-------: | :-------: |
| 1    | App ID 기능 켜기         | Developer Portal   |     ●     |           |
| 2-a  | Firebase iOS 앱 등록     | Firebase Console   |     ●     |           |
| 2-b  | plist 파일 교체          | 리포지토리         |           |     ●     |
| 3    | 번들 ID 6곳 수정         | 리포지토리         |           |     ●     |
| 4    | 카카오 번들 ID 등록      | Kakao Developers   |     ●     |           |
| 5-a  | RevenueCat 앱·상품 등록  | RevenueCat         |     ●     |           |
| 5-b  | `.env` 키 교체           | 리포지토리         |           |     ●     |
| 6    | 인앱 상품 편집           | App Store Connect  |     ●     |           |
| 7-a  | AdMob 앱·광고 단위 생성  | AdMob              |     ●     |           |
| 7-b  | plist·`.env` ID 교체     | 리포지토리         |           |     ●     |
| 8-a  | AASA 파일 수정           | 리포지토리         |           |     ●     |
| 8-b  | 웹 배포                  | 터미널             |           |     ●     |
| 9    | 앱 등록 정보·개인정보 라벨 | App Store Connect  |     ●     |           |
| 10   | 빌드 업로드·심사 제출    | Xcode / ASC        |     ●     |           |

**검증 담당**

| 검증 항목                | 방법                              | 담당      |
| ------------------------ | --------------------------------- | --------- |
| iOS 빌드 성공            | `flutter build ios --release`     | 🤖 Claude |
| 정적 분석 통과           | `flutter analyze`                 | 🤖 Claude |
| AASA 배포 확인           | `curl -sI …`                      | 🤖 Claude |
| 카카오 로그인 동작       | 실기기                            | 👤 사용자 |
| 인앱 결제 상품 표시      | TestFlight 실기기                 | 👤 사용자 |
| 보상형 광고 재생         | release 빌드 실기기               | 👤 사용자 |
| 유니버설 링크로 앱 열림  | 실기기                            | 👤 사용자 |

> 실기기·TestFlight 검증은 Claude 가 할 수 없다. 결과만 알려주면 코드 쪽 원인은
> Claude 가 추적한다.

### 사용자 → Claude 로 넘겨야 하는 값 4개

이게 없으면 Claude 쪽 작업이 멈춘다.

| 순서 | 넘길 것                       | 어디서 얻나            | 형태                    | 쓰이는 곳          |
| ---- | ----------------------------- | ---------------------- | ----------------------- | ------------------ |
| ①    | `GoogleService-Info.plist`    | Firebase Console (2-a) | 파일 (다운로드 경로)    | 2-b                |
| ②    | RevenueCat public API key     | RevenueCat (5-a)       | `appl_` 로 시작하는 문자열 | 5-b `.env`      |
| ③    | AdMob **앱** ID               | AdMob (7-a)            | `ca-app-pub-…~…` (`~`)  | 7-b Info.plist     |
| ④    | AdMob **광고 단위** ID        | AdMob (7-a)            | `ca-app-pub-…/…` (`/`)  | 7-b `.env`         |

③과 ④는 다른 값이다. 둘 다 필요하다.

### 진행 순서

```
1단계 👤 ─┐
4단계 👤  ├─ 서로 무관, 아무 때나 병렬로 진행 가능
6단계 👤 ─┘

2-a 👤 → ① 전달 → 2-b 🤖 ─┐
5-a 👤 → ② 전달 → 5-b 🤖  ├─→ 3단계 🤖 → 빌드 검증 🤖 → 10단계 👤
7-a 👤 → ③④ 전달 → 7-b 🤖 ┘        ↑
                    8-a 🤖 → 8-b 🤖 ┘
                              9단계 👤 ┘
```

3단계(번들 ID 교체)는 1단계가 끝난 뒤에 검증해야 서명이 통과한다.

---

## 1단계 — Apple Developer Portal 에서 기능 켜기

> **담당: 👤 사용자** — Claude 는 접근 권한이 없다.

새 번들 ID 의 App ID 에 필요한 기능이 켜져 있어야 Xcode 가 서명할 수 있다.

**어디서**
[developer.apple.com/account](https://developer.apple.com/account) →
`Certificates, Identifiers & Profiles` → 왼쪽 `Identifiers` →
목록에서 `com.scienceintegration.meetsocrates` 클릭

**무엇을**

| 기능                 | 현재 상태 | 할 일            |
| -------------------- | --------- | ---------------- |
| Push Notifications   | 켜져 있음 | 확인만           |
| Sign in with Apple   | 켜져 있음 | 확인만           |
| Associated Domains   | **꺼짐**  | **체크 후 Save** |

Associated Domains 가 없으면 `facely.kr` 링크를 눌러도 앱이 열리지 않는다. MeSo
원본은 이 기능을 릴리스에 안 실었기 때문에 꺼져 있을 가능성이 높다.

**확인** — Save 후 Xcode 에서 프로젝트를 열었을 때 Signing & Capabilities 탭에
빨간 경고가 없으면 된다.

---

## 2단계 — Firebase 에 새 iOS 앱 등록

> **2-a 담당: 👤 사용자** (콘솔 작업 + 파일 다운로드)
> **2-b 담당: 🤖 Claude** (리포지토리 파일 교체)

Firebase 는 번들 ID 별로 앱을 따로 등록한다. 지금 `GoogleService-Info.plist` 는
옛 번들 ID 용이라 그대로 쓰면 앱이 실행 직후 죽는다.

### 2-a 👤 콘솔 작업

**어디서**
[console.firebase.google.com](https://console.firebase.google.com) → 프로젝트
`ai-face-reader-1960a` → 왼쪽 위 톱니바퀴 → `프로젝트 설정` → `내 앱` →
`앱 추가` → **iOS** 아이콘

**무엇을**

1. `Apple 번들 ID` 칸에 `com.scienceintegration.meetsocrates` 입력 → 앱 등록
2. `GoogleService-Info.plist` 다운로드
3. **다운로드된 파일 경로를 Claude 에게 알려준다** (보통 `~/Downloads/`)

> 이 번들 ID 는 MeSo 원본의 Firebase 프로젝트 `meetsocrates-fd76c` 에 이미
> 등록되어 있다. **문제 없다.** Firebase 는 같은 번들 ID 를 여러 프로젝트에
> 등록할 수 있고, 앱이 어느 프로젝트와 통신할지는 번들에 포함된
> `GoogleService-Info.plist` 가 결정한다. 등록 시 경고가 떠도 그대로 진행한다.
> `meetsocrates-fd76c` 프로젝트는 삭제하지 말고 방치한다.

기존 facely iOS 앱 등록은 지우지 않는다. 그냥 두면 된다.

**APNs 인증 키** — 새로 발급할 필요 없다. FCM 은 `.p8` 키 기반 인증을 쓰고,
이 키는 Team ID + Key ID 로 동작하므로 팀 내 모든 번들 ID 에 공용이다.
(Developer Portal 의 `Configure` 안에 있는 Development / Production **SSL
Certificate 는 만들지 않는다** — 인증서 기반 APNs 용이라 해당 없음.)
`프로젝트 설정` → `클라우드 메시징` → `Apple 앱 구성` 에서 새 앱에 인증 키가
붙어 있는지만 확인하고, 안 보이면 기존 `.p8` 파일을 다시 업로드한다.
`.p8` 은 계정당 최대 2개이고 발급 시 한 번만 다운로드되므로 **새로 만들지 않는다.**

### 2-b 🤖 파일 교체

받은 파일로 `flutter/ios/Runner/GoogleService-Info.plist` 를 덮어쓴다.

**확인 🤖** — 새 plist 의 `BUNDLE_ID` 가 `com.scienceintegration.meetsocrates`,
`PROJECT_ID` 가 `ai-face-reader-1960a` 인지 검사한다.

---

## 3단계 — Xcode 프로젝트의 번들 ID 교체

> **담당: 🤖 Claude**

`flutter/ios/Runner.xcodeproj/project.pbxproj` 파일 안에
`PRODUCT_BUNDLE_IDENTIFIER` 가 **6곳** 있다. 전부 바꾼다.

| 줄 번호       | 지금                                        | 바꿀 값                                           |
| ------------- | ------------------------------------------- | ------------------------------------------------- |
| 517, 701, 725 | `com.scienceintegration.facely`             | `com.scienceintegration.meetsocrates`             |
| 534, 552, 568 | `com.scienceintegration.facely.RunnerTests` | `com.scienceintegration.meetsocrates.RunnerTests` |

`ios/Runner/Runner.entitlements` 는 **손대지 않는다.** 지금 파일이 맞다.
MeSo 원본 프로젝트에는 entitlements 가 3개 있는데, 그중 릴리스용 파일의
`aps-environment` 값이 `development` 로 잘못 설정돼 있다. 가져오면 안 된다.

**확인 🤖**

```bash
cd flutter && flutter build ios --release --no-codesign
```

서명까지 포함한 최종 확인은 1단계가 끝난 뒤 👤 사용자가 Xcode 에서 한다.

---

## 4단계 — 카카오 개발자 콘솔에 번들 ID 등록

> **담당: 👤 사용자** — Claude 는 접근 권한이 없다.

카카오는 등록된 번들 ID 에서 오는 로그인만 받아준다.

MeSo 전용 카카오 앱은 존재하지 않는다. MeSo 원본도 facely 와 **같은 카카오 앱
키**(`kakao6d20884c…d4a0`)를 쓰고 있었다. 따라서 기존 앱 하나만 수정한다.

**어디서**
[developers.kakao.com](https://developers.kakao.com) → `내 애플리케이션` →
`관상은 과학이다` → `앱 설정` → `플랫폼 키` → `플랫폼 키 수정`

**무엇을** — `iOS 앱 정보` 섹션에서 두 가지.

| 칸           | 값                                                     |
| ------------ | ------------------------------------------------------ |
| 번들 ID      | `com.scienceintegration.facely` 를 지우고 `com.scienceintegration.meetsocrates` 입력 |
| 스토어 URL   | `앱스토어 ID` 에 `6478495062` 입력 (URL 은 자동 완성)  |

> iOS 번들 ID 는 **단일 입력란이라 하나만 등록된다.** 교체 외에 방법이 없다.
> 교체해도 잃는 것이 없다 — Android 는 `키 해시` + `Android 패키지명` 이라는
> 별도 필드로 검증하므로 무영향이고, facely iOS 는 출시된 적이 없어 이 번들
> ID 로 카카오를 쓰는 사용자가 0 이다.

**건드리지 말 것**

- **키 해시 3개** — Android 서명 인증서 값. 지우면 Play 출시본의 카카오 로그인이
  죽는다.
- **스킴** `kakao6d20884c…d4a0` — 앱 키 기반이라 번들 ID 와 무관하다.

`.env` 의 `KAKAO_NATIVE_APP_KEY`, `Info.plist` 의 URL 스킴, Supabase 의 카카오
OAuth 설정 모두 **변경 없음** → Claude 쪽 작업 없음.

**저장 직후 확인 👤** — 페이지 하단 `스킴` 표에서 `iOS 번들 ID` 열이
`…meetsocrates`, `Android 패키지명` 열이 `…facely` 로 나오면 정상.

**확인 👤** — 실기기에서 카카오 로그인 → 카카오톡 앱으로 넘어갔다가 다시 앱으로
돌아오면 성공.

---

## 5단계 — RevenueCat 에 새 iOS 앱 추가

> **5-a 담당: 👤 사용자** (콘솔 작업)
> **5-b 담당: 🤖 Claude** (`.env` 수정)

RevenueCat 도 번들 ID 별로 앱을 등록한다. 지금 `.env` 의 iOS 키는 옛 번들 ID 용
이라 그대로 두면 결제 화면에 상품이 안 뜬다.

**새 앱을 만들지 않는다.** `.env` 에 `REVENUECAT_API_KEY_IOS = appl_eIzE…` 가 이미
있으므로 이 프로젝트에는 App Store 앱이 `com.scienceintegration.facely` 로 등록돼
있다. **기존 앱의 번들 ID 만 고친다.** 그러면 public key 가 유지되어 `.env` 를
건드릴 일이 없다.

> MeSo 의 RevenueCat 프로젝트는 사라졌다(삭제 또는 만료). 상관없다 — 처음부터
> 쓸 계획이 없었다. `관상은 과학이다` 프로젝트가 유일하고, 그게 맞는 프로젝트다.

### 5-a 👤 콘솔 작업

**어디서**
[app.revenuecat.com](https://app.revenuecat.com) → `관상은 과학이다` 프로젝트 →
`Apps & providers` → 기존 **App Store** 앱 클릭

**무엇을**

| 칸                                | 값                                                      |
| --------------------------------- | ------------------------------------------------------- |
| App Bundle ID                     | `com.scienceintegration.meetsocrates` 로 **교체**        |
| In-app purchase key (Required)    | 비어 있으면 `Select existing key`, 없으면 신규 업로드    |
| App Store Connect API (선택)      | 있으면 선택, 없으면 건너뜀                               |
| Custom URL Scheme                 | 비움 — 페이월 기능을 쓰지 않는다                         |
| App-specific shared secret        | 건드리지 않음 — IAP key 를 쓰면 불필요한 구식 방식       |

→ `Save changes`

> **In-app purchase key 는 반드시 채운다.** 없으면 StoreKit 2 환경에서 결제가
> 기록되지 않아, 사용자가 결제하고도 코인을 받지 못한다. App Store Connect →
> `사용자 및 액세스` → `통합` → `앱 내 구입` 에서 발급하는 계정 단위 `.p8` 키다.

**상품 등록** — `Product catalog` → `Products` → `+ New` → App Store 앱 선택 →
`meso_coin_1`, `meso_coins_10` 추가.
기존 `coin_3` / `coin_14` 항목은 삭제하지 않는다 (Android 가 계속 쓴다).

**public key 확인** — 왼쪽 하단 `API keys` 에서 iOS public key 를 본다.

| 결과              | 조치                                        |
| ----------------- | ------------------------------------------- |
| `appl_eIzE…` 유지 | **5-b 불필요** — `.env` 변경 없음           |
| 값이 바뀜         | 새 키를 Claude 에게 전달 ② → 5-b 진행       |

**번들 ID 칸이 수정 불가일 때만** `Apps & providers` → `+ New` → App Store 로
새로 만든다. App name 은 `관상은 과학이다 (App Store)`, Bundle ID 는 새 번들 ID.
이 경로는 새 public key 가 발급되므로 ② 전달이 반드시 필요하다.

### 5-b 🤖 `.env` 수정 (public key 가 바뀐 경우에만)

`flutter/.env` 의 `REVENUECAT_API_KEY_IOS` 값을 받은 키로 교체한다.
`REVENUECAT_API_KEY_ANDROID` 는 건드리지 않는다.

**확인 👤** — TestFlight 빌드에서 코인 구매 시트를 열었을 때 상품 2개와 가격이
뜨면 성공.

---

## 6단계 — App Store Connect 에서 인앱 상품 정리

> **담당: 👤 사용자** — Claude 는 접근 권한이 없다. 코드 변경은 이미 완료됐다.

인앱 상품 ID 는 개발자 계정 전체에서 딱 한 번만 쓸 수 있고, 지운 뒤에도 재사용이
안 된다. `coin_3` / `coin_14` 는 facely 앱에 이미 만들어놔서 **이미 소진됐다.**
MeSo 에는 같은 ID 를 만들 수 없다.

대신 MeSo 에 **이미 승인 완료된 소모품 3개**가 있다. 이걸 재활용한다. 상품 ID 는
사용자 화면에 절대 안 보이고, 사용자가 보는 건 표시 이름과 가격뿐이다.

**어디서**
[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → `앱` → `MeSo` →
`수익 창출` → `앱 내 구입`

**무엇을** — `meso_coin_1`, `meso_coins_10` 두 개만 편집한다.
`meso_coins_100` 은 **편집하지도, 삭제하지도 않는다.** 승인된 상태로 남겨두면
나중에 티어를 늘릴 때 쓸 수 있는 예비 ID 가 된다.

상품 상세 화면의 필드는 성격이 제각각이다. **사용자에게 보이는 값은 상세 화면
상단이 아니라 아래쪽 `App Store 현지화` 섹션에 있다.**

| 필드            | 위치            | 사용자에게 보임 | 심사              |
| --------------- | --------------- | --------------- | ----------------- |
| 제품 ID         | 상세 상단       | ✗               | **변경 불가**     |
| 식별 정보       | 상세 상단       | ✗ 내부 관리용   | 불필요            |
| **표시 이름**   | App Store 현지화 | **✓**          | **필요**          |
| **설명**        | App Store 현지화 | **✓**          | **필요**          |
| 가격            | 상세 상단       | ✓               | 불필요 — 즉시 반영 |
| 심사용 스크린샷 | 심사 정보       | ✗ 심사관만      | 필요              |

바꿀 값:

| 제품 ID         | 표시 이름 | 설명            | 가격                  | 지급 코인 |
| --------------- | --------- | --------------- | --------------------- | --------- |
| `meso_coin_1`   | `3 코인`  | facely 문구     | facely 의 3코인 가격  | 3         |
| `meso_coins_10` | `14 코인` | facely 문구     | facely 의 14코인 가격 | 14        |

식별 정보도 같은 이름으로 맞춰두면 목록에서 헷갈리지 않는다 (내부용이라 심사 무관).

**심사용 스크린샷** — `심사 정보` 에 MeSo 시절 이미지가 남아 있다. facely 의 코인
구매 시트 캡처로 교체한다. 심사관만 보는 이미지지만 설명과 어긋나면 불필요한
질문을 부른다.

> ⚠️ **`사용 가능 여부` 를 반드시 확인한다.** 상품이 "175개 중 **1개** 국가"로
> 제한되어 있다. `편집` 을 눌러 그 1개가 **대한민국**인지 확인한다. 다른
> 나라라면 한국 사용자에게 상품이 조회되지 않아 구매 시트가 빈 채로 뜬다.
> 아래 `가격` 표의 "175개의 국가 또는 지역"은 가격이 정의된 범위일 뿐
> 판매 가능 범위가 아니다. 두 값은 별개다.

> ⚠️ **`심사에 추가` 버튼을 누르지 않는다.** 앱 버전과 분리된 단독 제출이 될 수
> 있고, 그러면 심사관이 서버가 소실된 현재 라이브 MeSo 를 열어볼 경로가 생긴다.
> **지금은 `저장`만 한다.** 새 앱 버전을 준비하는 10단계에서 그 버전에 인앱
> 상품을 함께 올린다.

**확인 👤** — 앱에서 구매 시트를 열었을 때 상품이 2개 뜬다.

---

## 7단계 — AdMob 앱 새로 만들기

> **7-a 담당: 👤 사용자** (콘솔 작업)
> **7-b 담당: 🤖 Claude** (plist·`.env` 수정)

AdMob 앱은 스토어 등록 정보에 묶인다. 번들 ID 가 바뀌면 새로 만들어야 한다.

### 7-a 👤 콘솔 작업

**어디서**
[apps.admob.com](https://apps.admob.com) → `앱` → `앱 추가` → 플랫폼 **iOS**

**무엇을**

1. 앱을 등록하고 **앱 ID** 를 복사 → Claude 에게 전달 ③
   (`ca-app-pub-…~…` 형태, **`~` 포함**)
2. `광고 단위` → `보상형` 광고 단위를 새로 만들고 **광고 단위 ID** 를 복사 →
   Claude 에게 전달 ④ (`ca-app-pub-…/…` 형태, **`/` 포함**)

> ③과 ④는 다른 값이다. 헷갈리면 광고가 안 나온다.

### 7-b 🤖 파일 수정

| 받은 값 | 넣을 곳                                                   |
| ------- | --------------------------------------------------------- |
| ③ 앱 ID | `flutter/ios/Runner/Info.plist` 의 `GADApplicationIdentifier` |
| ④ 단위 ID | `flutter/.env` 의 `ADMOB_REWARDED_UNIT_ID_IOS`           |

Android 쪽 값(`AndroidManifest.xml` 의 `APPLICATION_ID`,
`ADMOB_REWARDED_UNIT_ID_ANDROID`)은 **바꾸지 않는다.**

### 7-c 👤 app-ads.txt 인증

AdMob 은 스토어 등록 정보의 개발자 웹사이트 도메인에서 `app-ads.txt` 를 크롤링해
앱 소유권을 확인한다. 인증 전에는 광고 게재가 제한된다.

`web/public/app-ads.txt` 를 배포해 `https://facely.kr/app-ads.txt` 가 200 으로
응답한다 (8-d). Play 리스팅의 개발자 웹사이트도 이미 `https://facely.kr` 다.

| 앱 | 남은 조건 |
| --- | --- |
| 관상은 과학이다 (Android) | 없음 — 크롤링만 기다리면 된다 (최대 24h) |
| MeSo (iOS) | 새 버전의 **마케팅 URL = `https://facely.kr`** 이 라이브가 된 뒤 인증 가능 |
| 관상은 과학이다 (iOS) | 스토어 연결 없음 — 방치. 옛 facely 번들용이라 인증될 일이 없다 |

> `업데이트 확인` 버튼은 크롤링을 즉시 실행하지 않고 **마지막 크롤 결과를 다시
> 읽을 뿐이다.** 파일을 올린 직후에 눌러도 같은 오류가 나온다. 하루 뒤에 누른다.

MeSo(iOS) 의 광고 단위 `rewarded_coin`(`…/1130700485`) 연결은 확인됐다.
생성 직후 목록에 `0개` 로 보이는 것은 반영 지연이다.

**확인 👤** — release 빌드에서 무료 코인용 보상형 광고가 재생된다.
(debug 빌드는 항상 구글 테스트 광고를 쓰도록 코드가 되어 있어 확인이 안 된다.)

---

## 8단계 — 유니버설 링크(AASA) 파일 수정

> **담당: 🤖 Claude** — 파일 수정과 배포 모두. 배포 전 승인만 받는다.

`facely.kr/r/{id}` 같은 링크를 눌렀을 때 앱이 열리게 하는 설정이다. 파일에 적힌
App ID 와 실제 앱의 번들 ID 가 정확히 일치해야 동작한다.

### 8-a 🤖 파일 수정

**파일** — `web/public/.well-known/apple-app-site-association`

`appIDs` 배열에 새 App ID 를 **추가한다.** 기존 항목은 지우지 않는다.

```json
"appIDs": [
  "279L8K77C3.com.scienceintegration.meetsocrates",
  "279L8K77C3.com.scienceintegration.facely"
],
```

> **기존 파일의 접두사가 `TDP4V3QVVM` 으로 잘못 적혀 있었다.** 실제 Team ID 는
> `279L8K77C3` 이다 (Xcode `DEVELOPMENT_TEAM`, Developer Portal Membership
> details 양쪽에서 확인). 이 오류 때문에 iOS 유니버설 링크는 처음부터 동작하지
> 않았고, iOS 를 출시한 적이 없어 드러나지 않았다. 두 항목 모두 올바른
> 접두사로 교정했다. Android 는 `assetlinks.json` 이 별도 파일이라 영향 없다.

### 8-b 🤖 배포

```bash
cd web && pnpm build && pnpm run deploy
```

> `deploy` 는 빌드를 하지 않는다. `build` 를 생략하면 낡은 파일이 올라간다.

**확인 🤖**

```bash
curl -sI https://facely.kr/.well-known/apple-app-site-association | head -3
```

`content-type: application/json` 이 나오고, 본문에 새 App ID 가 들어 있으면 된다.

**확인 👤** — 실기기에서 `https://facely.kr/r/{아무_리포트_id}` 를 눌러 앱이
열리는지 본다.

---

## 9단계 — App Store Connect 등록 정보 수정

> **담당: 👤 사용자** — Claude 는 접근 권한이 없다. 리포지토리 작업 없음.

**어디서** — `appstoreconnect.apple.com` → `앱` → `MeSo`

바꿔야 하는 것:

- 앱 이름, 부제, 아이콘, 스크린샷, 설명
- 카테고리
- 연령 등급
- **개인정보 라벨** — MeSo 는 위치 정보 수집을 선언해뒀는데 facely 는 위치를
  쓰지 않는다. 선언을 지운다. (`앱이 수집하는 개인정보` 메뉴)

> 홈 화면에 표시되는 앱 이름(`Info.plist` 의 `CFBundleDisplayName`)과 App Store
> 에 표시되는 앱 이름은 **다른 값**이다. 둘 다 확인한다.
> Info.plist 쪽 수정이 필요하면 🤖 Claude 가 한다.

---

## 8-c — 워커 환경변수

> **담당: 🤖 Claude** — `web/wrangler.jsonc` 의 `vars`.

| 변수                    | 처리                                                       |
| ----------------------- | ---------------------------------------------------------- |
| `APP_BUNDLE_ID_IOS`     | ✅ `…meetsocrates` 로 변경 완료 (런타임에서 읽지 않는 값)   |
| `APP_STORE_URL`         | ⏸ **10단계로 보류** — 아래 사유                             |
| `PLAY_STORE_URL`        | 변경 없음                                                   |
| `APP_BUNDLE_ID_ANDROID` | 변경 없음                                                   |

`APP_STORE_URL` 은 `/app`, `share`, `r/{id}/open`, `g/{id}/open` 네 라우트에서
스토어 리디렉션에 쓰인다. 지금 `id6478495062` 로 바꾸면 공유 링크를 연 iOS
사용자가 **서버가 소실된 구 MeSo 를 설치**하게 된다. 설치 유입이 늘수록 낮은
평점·사용자 신고로 2.1(App Completeness) 이 걸릴 위험이 커지고, 그건 앱 레코드가
내려가는 경로다. 현재 값(facely `id6776864670`)도 iOS 미출시라 죽은 링크지만,
**죽은 링크가 죽은 앱 설치보다 낫다.**

## 10단계 — 빌드 업로드와 심사 제출

> **담당: 👤 사용자** — Xcode Archive / Transporter 업로드와 심사 제출은
> Apple 계정 세션이 필요하다.

신규 인앱 상품을 만들지 않았으므로 새로 심사받을 상품이 없다. 상품 표시 이름
변경분만 앱 버전 심사에 같이 올라간다.

**제출 전 👤**

- 인앱 상품 2개에 **심사용 스크린샷** 업로드 (설정 탭에서 연 코인 충전 시트 캡처).
  기존 MeSo 이미지는 이미 삭제했다.
- 인앱 상품을 **이 앱 버전에 포함**시켜 함께 제출한다 (단독 제출 금지).

**승인되어 라이브가 된 직후 🤖**

- `web/wrangler.jsonc` 의 `APP_STORE_URL` 을 `https://apps.apple.com/app/id6478495062`
  로 변경 후 재배포 (8-c 참고).

---

## 코드 변경 요약 (🤖 Claude 담당 전체 목록)

| 파일                                                | 무엇을                                     | 단계 | 선행 조건       | 상태     |
| --------------------------------------------------- | ------------------------------------------ | ---- | --------------- | -------- |
| `flutter/lib/data/services/coin_service.dart`        | 상품 ID 를 iOS/Android 로 분기             | —    | 없음            | **완료** |
| `flutter/ios/Runner.xcodeproj/project.pbxproj`       | 번들 ID 6곳                                | 3    | 없음            | 대기     |
| `flutter/ios/Runner/GoogleService-Info.plist`        | 파일 통째로 교체                           | 2-b  | ① 파일          | 대기     |
| `flutter/.env` → `REVENUECAT_API_KEY_IOS`            | 변경 불필요 — 기존 앱을 수정해 public key 가 `appl_eIzE…` 로 유지됨 | 5-b | — | **해당 없음** |
| `flutter/ios/Runner/Info.plist`                      | `GADApplicationIdentifier`                 | 7-b  | ③ 앱 ID         | 대기     |
| `flutter/.env` → `ADMOB_REWARDED_UNIT_ID_IOS`        | 값 교체                                    | 7-b  | ④ 단위 ID       | 대기     |
| `web/public/.well-known/apple-app-site-association`  | `appIDs` 항목 추가                         | 8-a  | 없음            | 대기     |

`flutter/ios/Runner/Runner.entitlements` 는 변경 없음.

선행 조건이 "없음"인 두 건(3단계, 8-a)은 지금 바로 진행할 수 있다.

완료된 변경(`coin_service.dart`):

```dart
static List<String> get _productIds => Platform.isIOS
    ? ['meso_coin_1', 'meso_coins_10']   // App Store — MeSo 승인 상품 재활용
    : ['coin_3', 'coin_14'];             // Play — 기존 그대로

static const _coinMap = {
  'coin_3': 3, 'coin_14': 14,            // Android
  'meso_coin_1': 3, 'meso_coins_10': 14, // iOS
};
```

---

## 절대 하면 안 되는 것

**MeSo 의 인앱 상품을 삭제하지 마라.** (👤)
상품 ID 는 삭제해도 영구히 재사용할 수 없다. 지우는 순간 되돌릴 방법이 없다.

**`coin_3` / `coin_14` 를 MeSo 에 만들려고 시도하지 마라.** (👤)
facely 앱에서 이미 써버린 ID 라 생성 자체가 거부된다.

**MeSo 원본 코드(`~/Code/meso`)의 설정 파일을 가져오지 마라.** (🤖)
릴리스용 entitlements 의 `aps-environment` 가 `development` 로 잘못 돼 있다.
가져오면 프로덕션 푸시 알림이 동작하지 않는다.

**Android 관련 값을 바꾸지 마라.** (🤖👤)
`applicationId`, Play 인앱 상품 ID, Android 광고 단위, Android RevenueCat 키.
Android 는 이미 출시된 상태다.

**인앱 상품을 앱 버전과 따로 제출하지 마라.** (👤)
인앱 상품만 단독으로 심사에 올리면 심사관이 현재 라이브 중인 MeSo 를 열어볼 수
있다. 서버가 없어져서 앱이 동작하지 않으므로 "앱이 완성되지 않았다"는 사유로
앱이 스토어에서 내려갈 수 있다. 반드시 새 앱 버전과 **함께** 제출한다.

---

## 아직 확인 안 된 것 (👤 사용자가 콘솔에서 확인)

- **MeSo 의 현재 카테고리** — 유지할지 바꿀지에 따라 9단계 작업량이 달라진다.
- **MeSo 개인정보 라벨의 위치 수집 선언 여부** — 있으면 지워야 한다.
- **`meso_coin_1` / `meso_coins_10` 의 현재 가격** — facely 의 3코인·14코인
  가격과 순서가 반대라면(즉 `meso_coin_1` 이 더 비싸다면) `coin_service.dart` 의
  매핑을 서로 바꾸는 게 가격 수정이 덜 든다. → 알려주면 🤖 Claude 가 수정한다.
