# HOW-IT-WORKS — facely

`facely.kr` 의 Cloudflare Workers 앱. 책임을 **최소 두 가지** 로 좁힌다:

1. **R2 presign URL 발급** (`POST /api/r2/presign`) — 모바일 앱이 분석용 임시 이미지·공유 thumbnail 을 R2 에 직접 PUT 할 수 있도록 단기 SigV4 URL 만 발급. 객체 자체엔 손 안 댄다.
2. **공유 link 의 SSR host** (`GET /r/{uuid}`) — 받는 사람이 카톡에서 link 탭했을 때 OG 카드·리포트·딥링크·스토어 fallback. Supabase `metrics` 행을 **read-only** 로 fetch.

이미지 본체는 단 한 번도 Worker 메모리에 안 들어옴 (R2 직통 PUT, CDN GET). Worker 는 어떤 데이터도 Supabase 에 write 하지 않는다 — Flutter 가 직접 `metrics` 에 UPSERT 하고 Worker 는 그 행을 읽기만 한다 (왕복 최소화).

---

## 1. 큰 그림

```
┌─────────────────────────────────────────────────────────────────────┐
│                          [Flutter 앱]                                │
│                                                                     │
│  사진 촬영/앨범                                                       │
│   │                                                                 │
│   ├─(A) DeepFace 분석 파이프라인 → age/gender/race                    │
│   │    Flutter ──720 PUT──► R2 temp/{uuid}.jpg                       │
│   │    Flutter ──POST /analyze──► Python                             │
│   │      ├─ HMAC verify                                              │
│   │      ├─ DeepFace.analyze                                         │
│   │      ├─ R2 DELETE temp/{uuid}.jpg (즉시 삭제)                     │
│   │      └─ JSON 응답                                                │
│   │    [안전망] R2 lifecycle: temp/ 1일 자동 만료                     │
│   │                                                                 │
│   ├─(B) 로컬 face mesh + 엔진 → 리포트(archetype 등)                  │
│   │                                                                 │
│   └─(C) 공유 publish                                                 │
│        Flutter ──presign(thumbnails)──► Worker (signing only)        │
│        Flutter ──256 PUT──► R2 thumbnails/{YYYYMM}/{uuid}.jpg        │
│        Flutter ──UPSERT──► Supabase metrics (id=uuid)                │
│        Flutter ─[share_plus]─► https://facely.kr/r/{uuid}            │
│        (카톡 link / Instagram 이미지 — Worker 호출 0회)                │
└─────────────────────────────────────────────────────────────────────┘

                         ┌──────────────────────────┐
                         │  받는 사람이 카톡 link 탭    │
                         └──────────────────────────┘
                                       │
            ┌──────────────────────────┼───────────────────────────┐
            ▼                          ▼                           ▼
   카톡 크롤러 (서버사이드)     앱 설치된 device         앱 미설치 device
       │                              │                           │
   GET /r/{uuid}                Universal/App link          GET /r/{uuid}
       │                              │                           │
   Worker SSR                  앱 직접 open                Worker SSR
   → OG meta only              → app_links → /r/{uuid}     → 풀 리포트 + CTA
   (head 만 응답)               → Flutter ReportPage         → 1.5s deep link
                                                              시도 → 스토어 fallback
```

핵심 원칙:

- **OG meta 는 SSR 강제** — 카톡 크롤러는 JS 실행 안 함. 메타 데이터는 `route.meta` export 에만.
- **Worker 가 R2 객체를 read/write 하지 않음** — presign 발급만 (`/api/r2/presign`).
- **시스템 안 PII 의 실질 보관소는 R2 `thumbnails/` 한 곳** (256² 얼굴 = PII). UUID-as-unguessable-URL access control. Supabase 행은 비-PII (정규화 카테고리·rawValue·thumbnailKey 포인터). 즉 "Supabase 엔 PII 없음" 은 사실이지만 **시스템 전체에 PII 없음 ≠ 사실** — §12 Privacy 참조. landmark 좌표·alias·사용자 이름·생년월일은 어떤 store 에도 안 들어감.
- **해석 엔진은 `shared/` 한 곳** — Flutter 와 Worker SSR 이 같은 Dart 코드를 컴파일된 JS 로 공유. 룰 변경 시 양쪽 동시 반영.
- **공유·재계산·OG 모두 `metrics` 테이블의 `body` 한 곳을 SSOT 로 사용.** 별도 `share_card` 같은 행 단위 압축 metadata 테이블 도입 금지.
- **1 face capture = 1 UUID.** Flutter 가 analyze 시점에 v4 한 번 발급 → 그 uuid 가 `temp/{uuid}.jpg` → `thumbnails/{YYYYMM}/{uuid}.jpg` → `metrics.id` → `https://facely.kr/r/{uuid}` 까지 그대로 흐름. 단일 trace id 로 incident response·log grep 한 번에 끝. publish 단계에서 새 uuid 발급 금지.

---

## 2. 도메인·컴포넌트

| 호스트           | 책임                                                                             | 위치                                        | 비고                     |
| ---------------- | -------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------ |
| `facely.kr`      | Workers (R2 presign API + `GET /r/:uuid` SSR + OG + 딥링크 fallback) — write 0회 | Cloudflare Workers (이 repo)                | 메인                     |
| `www.facely.kr`  | 동일                                                                             | 동일                                        | 별칭                     |
| `cdn.facely.kr`  | R2 bucket 의 public read 호스팅 (`thumbnails/`)                                  | Cloudflare R2 custom domain                 | static asset CDN         |
| `meta.facely.kr` | Python FastAPI `/analyze`                                                        | 홈서버 Ubuntu (Docker + cloudflared tunnel) | DeepFace age/gender/race |

**Cloudflare 자원**:

- Workers 스크립트 `facely` (이 repo)
- R2 bucket `facely` — prefix 두 갈래:
  - `temp/{uuid}.jpg` — 분석용 임시. Python 이 즉시 삭제. lifecycle rule 로 1일 백업 정리.
  - `thumbnails/{YYYYMM}/{uuid}.jpg` — 영구 256×256.
- DNS records (Workers 자동 관리: facely.kr, www; tunnel: meta; R2: cdn)

**외부 자원**:

- Supabase Postgres + REST — `metrics` 테이블 (UUID PK, `body` JSONB, `views` int, `updated_at` timestamptz). 행 자체는 anonymous (user_id 없음).
- App Store / Play Store — bundle ID `com.scienceintegration.facely`

---

## 3. 데이터 흐름 — 4 갈래

### 3.1 분석 (analyze pipeline)

> Flutter 는 **analyze 진입 시점에 UUID v4 를 한 번 발급**한다. 이 uuid 가
> `temp/{uuid}.jpg`, (분석 성공 시) `thumbnails/{YYYYMM}/{uuid}.jpg`, 그리고
> 이후 publish 시점의 `metrics.id` + `/r/{uuid}` 까지 그대로 흐른다. 단일
> capture 의 모든 부산물이 같은 trace id 로 묶임 — Flutter ↔ Worker ↔ Python ↔
> Supabase 로그 grep 한 번이면 끝.

```
Flutter                              Worker                          Python
  │                                                                    │
  │ 1. POST /api/r2/presign {prefix:"temp",uuid,...}                   │
  ├──────────────────────────────────► .                               │
  │                                    │ aws4fetch SigV4               │
  │                                    │ HMAC(secret, ts+key)          │
  │ ◄──────────────────────────────────┤                               │
  │ {uploadUrl, publicUrl, key, token}                                 │
  │                                                                    │
  │ 2. PUT 720px JPG → R2 temp/{uuid}.jpg (presigned URL 직통)         │
  │                                                                    │
  │ 3. POST /analyze {image_url:publicUrl}                              │
  │    headers: X-Face-Token, X-Face-Key                                │
  ├────────────────────────────────────────────────────────────────────►
  │                                                                    │ HMAC verify
  │                                                                    │ download → DeepFace
  │                                                                    │ R2 DELETE temp/{uuid}.jpg
  │                                                                    │ (R2 credential: 별도 DELETE-only 토큰)
  │ ◄────────────────────────────────────────────────────────────────┤
  │ {age:28, gender:"Man", race:"asian"}                                │
```

한 줄 요약: **`key` = "bucket 안 어디에 있는지"** (S3/R2 저장소 객체식별자를 나타내는 universal 컨벤션), **`token` = "그 key 를 분석하러 갈 수 있는 5분짜리 통행증"** (Python `/analyze` 인증 한 용도).

응답 JSON 계약 (Python `/analyze` → Flutter) — **DeepFace raw 그대로, 매핑·정규화 0**:

```json
{
  "age": 28,
  "gender": "Man",
  "race": "asian"
}
```

Python 의 책임은 여기까지. decade 라벨링·소문자 정규화·`race → Ethnicity` enum 매핑·`gender → male/female` 변환 등 **모든 가공 책임은 소비자(Flutter)** 가 진다. Flutter 는 받은 raw 값을 자기 필요한 만큼만 쓰고 (예: `body.deepfaceAge/Gender/Race` 슬롯에 raw 그대로 보존, 사용자 선택 보정 UI 가 있으면 그 위에 overwrite), 안 쓰면 버린다.

실패 분기:

- presign 실패 / R2 PUT 실패 → Flutter 가 사용자에게 재시도 안내
- /analyze 401 (token expired) → presign 재요청 → 다시 시도
- /analyze 422 (no face) → 다른 사진 안내
- R2 DELETE 실패 → 그래도 JSON 반환 (Python 로그만). 1일 후 lifecycle 이 정리.

### 3.2 publish (공유 카드 발행)

> 여기서 사용하는 `<uuid>` 는 §3.1 의 analyze 시점에 이미 발급된 그 uuid 다.
> Flutter 는 `FaceReadingReport.supabaseId` 에 그 값을 들고 있으므로 publish
> 시점에 새로 생성하지 않는다. 결과적으로 `metrics.id`·`thumbnailKey` 의 uuid
> 부분·`/r/{uuid}` 가 모두 동일.

```
Flutter
  ├─ POST /api/r2/presign {prefix:"thumbnails", uuid}  → Worker (signing only)
  ├─ PUT (presigned, 256 JPG)                          → R2 thumbnails/{YYYYMM}/{uuid}.jpg
  │
  └─ Supabase REST UPSERT /rest/v1/metrics             → Supabase (anon key)
        body: { id: "<uuid>", body: { … thumbnailKey 포함 … } }
        on conflict (id) do update set body = excluded.body
   ◄──── 200/201
  └─ share_plus("https://facely.kr/r/<uuid>")  ← Worker 호출 0 회
```

핵심: **Worker 측에 `/api/share` 같은 publish endpoint 가 존재하지 않는다.**

- body 의 payload 가 일반적으로 1.5–3 KB → Flutter 와 Supabase 사이에 한 번만 흐른다 (Worker 경유 시엔 두 번 흐름 → 폐기).
- Worker 는 어차피 Supabase 에 write 권한 없음. service-role key 비치 X.
- Supabase RLS 가 `metrics.insert` 를 anon 에 허용 (행에 PII 없음을 schema check 로 강제). 자세한 RLS 는 §5.2.

compat 카드는 publish 단계에서 metrics 에 추가 write 0회. 두 사람의 metrics 행은 이미 각자의 솔로 분석에서 UPSERT 되어 있다 (정상 case). 만약 한쪽 metrics 가 누락된 상태에서 compat 을 만들고 싶다면 그 한 사람의 솔로 publish 먼저 1회 — 평소 흐름과 동일. compat link 는 그저 두 UUID 를 SEP 으로 묶은 URL 일 뿐 (`/r/{A}~{B}`).

### 3.3 view-in-app (받는 사람 앱 보유)

```
받는 사람이 카톡에서 https://facely.kr/r/{id} 탭
   ({id} 는 단일 UUID = 관상, 또는 "{uuidA}~{uuidB}" = 궁합. SEP="~")
   │
   ▼
iOS:  AASA 검증 (apps[].appIDs == TEAMID.com.scienceintegration.facely
                   + paths == ["/r/*"]) → 앱 직접 launch
Android: assetlinks.json 검증 → app link → 앱 launch
   │
   ▼
Flutter: app_links package 가 incoming uri 수신
        → /r/{id} path 파싱 → SEP("~") split
        → 1개면 관상: metrics 1행 fetch → ReportPage
        → 2개면 궁합: metrics 2행 fetch → 궁합 engine → CompatReportPage
```

앱 미설치 case 로 fallthrough (3.4) 가능 — iOS 가 universal link 검증 실패하면 Safari 가 그냥 URL 열음.

### 3.4 view-on-web (받는 사람 앱 미설치)

```
GET https://facely.kr/r/{id}
   │ ({id} 를 SEP("~") 로 split → 1 또는 2 UUID)
   ▼
Worker SSR (app/routes/share.tsx)
   1. fetchMetrics(env, ids[])  // 1 또는 2 행
      → 404 (요청 id 중 하나라도 없음) → /r 404 페이지
      → fetch 성공 시: 각 id 에 대해 rpc/increment_metrics_views(id) 비동기 호출
        · views++ + updated_at 자동 갱신 (active 신호 — §5.2 dormant cleanup 의 입력)
        · 사람·크롤러 구분 안 함 (의도적 단순화)
   2. shared engine 호출
      ids.length === 1 (관상):
        out = runEngine(JSON.stringify({raw: row.metrics, demographic}))
        → archetype + top 3 attributes + chips
      ids.length === 2 (궁합):
        out = runCompat(JSON.stringify({a: rowA, b: rowB}))
        → 두 사람의 archetype + 궁합 score + 친밀/갈등 chips
      (어느 경우든 결과는 절대 DB 저장 X — 매 load 시 재계산)
   3. ShareCard / CompatCard 분기 + 본문 + CTA 렌더
   4. <head> meta:
        og:title    관상: "AI 관상가가 본 {archetype.primary}"
                    궁합: "{A.archetype} × {B.archetype} 의 궁합"
        og:image    관상: https://cdn.facely.kr/{rowA.thumbnailKey}
                    궁합: 합성 (두 thumbnail 합성 PNG) 또는 A 의 것
        og:url      https://facely.kr/r/{id}
        twitter:card summary_large_image
        robots      noindex,nofollow (PII 검색엔진 차단 — §12.4)
   5. CTA.tsx
        useEffect: 1.5s universal/app link 시도 (window.location.href = ...)
        실패 → store fallback (UA detect: iOS → APP_STORE_URL, Android → PLAY_STORE_URL)
```

**카톡 크롤러 분기**: 같은 SSR 결과를 반환하면 됨 — crawler 가 head 의 OG 만 읽고 본문은 무시. JS 실행 안 함 → CTA 의 1.5s 자동 deep-link 도 영향 X.

### 3.5 데모그래픽 orchestration — age × gender × ethnicity 가 파이프라인에 미치는 영향

10 attribute score 와 narrative 출력은 **landmark geometry 단독으로 결정되지 않는다**. 사용자가 고른 (또는 DeepFace 가 추정한) `ageGroup·gender·ethnicity` 세 demographic 이 파이프라인의 여러 stage 에 끼어들어 같은 얼굴이라도 demographic 별로 다른 해석을 만든다. 어디서 어떻게 들어가는지 stage-by-stage 로 정리.

```
MediaPipe 468 landmarks
        │
        ▼
17 frontal + 8 lateral raw metric
        │
        │  ← (1) referenceData[ethnicity][gender][metricId]
        ▼     · Farkas 1994 / 2005 anthropometry baseline
z-score        · 6 ethnicity × 2 gender 표 (frontal + lateral 모두 분화)
        │
        │  ← (2) adjustForAge(metricId, z, gender, ethnicity, isOver50)
        ▼     · 50+ 만 발동, gender × ethnicity 별 다른 강도
z-adjusted     · ethnicity scale (Vashi 2016): EA/SEA 0.6, AF 0.5, 그 외 1.0
        │
        ▼
14-node tree (scoreTree)
        │
        ▼
5-stage attribute pipeline
   Stage 1  base linear per-node × gender × ethnicity
              │
              │  ← (3) _effectiveWeight + dimorphismScale[ethnicity]
              │     · gender delta (±0.05) × scale
              │     · 동아 0.7, 아프리카 0.6, 그 외 1.0
              │
   Stage 1b distinctiveness (demographics-blind)
              │
   Stage 2-5  Zone / Organ / Palace / Age / Lateral rules
              │
              │  ← (4) physiognomyCanonScale[ethnicity]
              │     · 동아 1.0, 동남아 0.9, 그 외 0.7
              │     · 모든 rule effect magnitude 에 곱함
              │
              ├─ Stage 5 Age rules:
              │       ageGroup.band 으로 dispatch
              │     · young (10~20대): A-Y01/Y02/Y03 (매력·학습·신선함)
              │     · mid   (30~40대): A-M01/M02/M03 (재물·대표성·신뢰)
              │     · late  (50+):     A-01~A-04    (회수·전수·노화)
              │
              └─ Stage 5 Lateral flag rules:
                    aquilineNose 등 raw ° cutoff 가 gender-conditional
                    · snub: 남 ≥113° / 여 ≥118°
                    · droopTip: 남 ≤110° / 여 ≤115°
        │
        ▼
10 raw attribute
        │
        │  ← (5) normalizeAllScores(rawScores, gender, shape)
        ▼     · gender × shape 별 21-point quantile table
10 normalized attribute (5.0~10.0)
        │
        │  ← (6) classifyArchetype(scores, gender, shape)
        ▼     · gender prior (장군형·도화형 등 archetype 별 ±10%)
ArchetypeResult
        │
        │  ← (7) computeYinYang(zMap, gender)
        ▼     · gender baseline (남 +0.30 / 여 −0.30) 제거
YinYangBalance — 성별 expectation 대비 deviation 표시
        │
        ▼
life_question_narrative
   · gender 분기: 연애·관능 섹션은 male/female pool 완전 분리
   · age 분기: 7 인생 질문 Advice 의 fragment pool 이
                young/mid/late 별 다른 fragment 활성화
   · 관능도 섹션은 30+ 에서만 출력 (under 30 은 hidden)
```

**한눈 요약표**: 각 demographic 이 끼어드는 stage·SSOT·근거

| 단계 | demographic | 적용 위치 (코드) | 데이터 SSOT | 학술 근거 |
|---|---|---|---|---|
| (1) z-score baseline | ethnicity × gender | `face_analysis.dart:64` | `face_reference_data.dart::referenceData` (frontal 17 × 6 인종 × 2 성별), `lateralReferenceData` (lateral 8 × 6 × 2) | Farkas 1994/2005, Sforza 2009, Mommaerts 2014, Naini 2017 |
| (2) age adjustment 50+ | gender × ethnicity | `age_adjustment.dart::adjustForAge` | `ethnicity_factors.dart::agingTrajectoryScale` | Vashi 2016, Rawlings 2006 (인종별 노화 ~10년 shift) |
| (3) gender delta 크기 | ethnicity | `attribute_derivation.dart::_effectiveWeight` | `ethnicity_factors.dart::dimorphismScale` | Kleisner 2021, Weinberg 2016, Flis review (인종별 남녀 dimorphism 강도) |
| (4) rule magnitude cap | ethnicity | `attribute_derivation.dart::_scaleRules` (Stage 2-5 전체) | `ethnicity_factors.dart::physiognomyCanonScale` | 한국 관상 전통 = 동아 canon (동남아 0.9 / 그 외 0.7 로 dampen) |
| (4-age) age-banded rules | ageGroup | `attribute_derivation.dart::_ageRulesFor(band)` | `_youngAgeRules` / `_midAgeRules` / `_lateAgeRules` | 연령별 발복·노화 변곡점 (관상 전통 + 일반 commonsense) |
| (4-lateral) flag cutoff | gender | `face_analysis.dart:177` 근방 | `_snubRawCutoff`, `_droopRawCutoff` inline | Sforza 2009 (남녀 nasolabial baseline ~5° gap) |
| (5) normalize quantile | gender × shape | `attribute_normalize.dart` | `_attrQuantilesByShape` (MC 생성) | MC baseline: eastAsian × 30대 (CLAUDE.md N=14 cohort) |
| (6) archetype classifier | gender | `archetype.dart::classifyArchetype` | `_genderPriors` | 한국 관상 전통 archetype 의 gender 함의 (장군·미인 등) |
| (7) yin-yang balance | gender | `yin_yang.dart::computeYinYang` | `_yyGenderBaseline` | 한국 관상 전통: 남=양 base, 여=음 base |
| (narrative) | gender | `life_question_narrative.dart` | `_romanceBeatsMale/Female` 등 pool | UX 자연스러움 |
| (narrative) | ageGroup | `_isYoung/_isMid/_isLate` predicate + Advice pool 의 age-stratified fragment | inline content | UX 적합성 |
| (narrative) | ageGroup gate | `_concludeStage` + 관능도 섹션 30+ gate | inline | UX 적합성 |

**중요 invariant**:
- demographic 정보는 **rule trigger condition** 에 들어가지 않는다 (얼굴 geometry z-score 만 trigger). 영향은 항상 *rule 발동 강도·임계·해석 톤* 의 modulation 형태.
- 단 한 곳의 예외: Stage 5 age rules — band 별 *다른 rule set* 이 dispatch 된다 (조건이 아니라 rule 자체가 갈림).
- demographic 입력이 분석 단계와 narrative 단계에서 **동일 값** 사용 — Hive `prefs` box 에 persist 된 사용자 선택이 SSOT. DeepFace 추정값 (`deepfaceAge`/`deepfaceGender`/`deepfaceEthnicity`) 은 audit 용으로만 보존 (engine 미경유).

**연구 누적 시 분화 예정 (보류 항목)**:
- Stage 1 quantile normalize 의 ethnicity 분화 (현재 MC = eastAsian 30대 단일 cohort, 5 ethnicity × 5 shape × 2 gender = 60-table 확장 필요)
- frontal Phase 1B metric (foreheadWidth·cheekboneWidth·chinAngle·eyeAspect·eyebrowCurvature·eyebrowTiltDirection·upperVsLowerLipRatio·browSpacing) 8개 + lateral 8개의 ethnicity 별 mean/sd empirical 측정 (현재는 EA-extrapolated)
- 실사용자 N 확장: 동아 30대 여성 14명 외 male/caucasian/40s 등 데이터 누적 → per-demographic recalibration

---

## 4. URL & deep linking

### 4.1 URL 구조

```
관상:  https://facely.kr/r/{uuid}
                          └────┘
                          v4 UUID (Supabase metrics.id PK)

궁합:  https://facely.kr/r/{uuidA}~{uuidB}
                          └─────┘ └─────┘
                          metrics.id  metrics.id
                          (separator: "~" — RFC 3986 unreserved, percent-encode 안 됨, UUID 표준에 없음)
```

핵심:

- **route 1 개**: `/r/:id` 한 라우트가 두 케이스 다 처리. SEP(`~`) 가 있으면 split, 없으면 단일.
- **AASA 매칭 단순**: `paths: ["/r/*"]` 한 패턴이 두 케이스 다 매칭.
- **궁합은 metrics 에 어떤 흔적도 안 남김** — 두 UUID 를 SEP 으로 묶은 문자열 자체가 궁합 카드의 id. 같은 metrics 행이 N 개 페어에 그대로 참여 가능.
- **시간 기반 만료 없음, inactivity 자동 정리** — `/r/{id}` fetch 마다 views++ + updated_at 갱신. updated_at 이 3 개월 이상 정체한 행만 daily cron 으로 정리 (§5.2). 활성 카드는 영구. 친구·본인 누구든 보면 자동 보호.
- **separator 는 한 곳에서만 정의** — `app/lib/share-id.ts` 의 `PAIR_SEP = "~"` 상수. 향후 변경되면 그 한 곳만 수정.

### 4.2 Universal / App Links

`public/.well-known/apple-app-site-association` (AASA):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["TEAMID.com.scienceintegration.facely"],
        "paths": ["/r/*"]
      }
    ]
  }
}
```

`public/.well-known/assetlinks.json` (Android):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.scienceintegration.facely",
      "sha256_cert_fingerprints": ["<release SHA256>"]
    }
  }
]
```

두 파일은 prod 배포 직전 실값 (TEAMID, signing cert SHA256) 교체 필요.

Flutter 측:

- `ios/Runner/Runner.entitlements` 의 `com.apple.developer.associated-domains` 에 `applinks:facely.kr`
- `android/app/src/main/AndroidManifest.xml` 의 `intent-filter android:autoVerify="true"` + `<data android:host="facely.kr" android:pathPattern="/r/.*">`
- `app_links` 패키지가 `getInitialAppLink()` + `uriLinkStream` 으로 수신

---

## 5. 저장소

### 5.1 R2 layout

```
bucket: facely
├── temp/                         ← 분석용 임시
│   └── {uuid}.jpg                  Python 이 즉시 DELETE
│                                   lifecycle 룰: ExpirationInDays=1 (백업 정리)
└── thumbnails/                   ← 영구 256×256
    └── {YYYYMM}/
        └── {uuid}.jpg              Worker 가 buildKey 에서 YYYYMM 자동 산출
                                    cdn.facely.kr 로 public read
                                    lifecycle 룰 없음 (의도적)
```

**lifecycle 룰 1 개** (Cloudflare R2 콘솔 → bucket facely → Settings → Object lifecycle rules):

| Rule name        | Prefix  | Action         | Days |
| ---------------- | ------- | -------------- | ---- |
| `temp-expire-1d` | `temp/` | Delete objects | 1    |

`thumbnails/` 는 시간 기반 만료 없음. 정리는 Supabase `metrics.updated_at` 의 inactivity 기반 cron 에서 행 삭제와 함께 R2 객체 삭제 (§5.2 참조).

### 5.2 Supabase `metrics` 스키마

`metrics` 는 이미 운영 중인 테이블 — 별도 `share_card` 신설 X. `metrics` 행은 **한 사람의 관상 측정 데이터만** 담는다 (1 face → 1 metrics row). 궁합·페어링 같은 관계형 메타는 일절 없음 — 궁합은 두 metrics UUID 를 URL 로 묶는 것 뿐 (§4.1 참조). 같은 metrics 행은 N 개 서로 다른 compat 페어에 그대로 참여할 수 있다 (write 0회).

```sql
create table if not exists metrics (
  id            uuid primary key default gen_random_uuid(),  -- 정상 경로는 client 가 명시. default 는 fallback only.
  body  jsonb not null,
  views         integer not null default 0,              -- /r/:id fetch 마다 +1 (사람·크롤러 구분 X)
  updated_at    timestamptz not null default now()       -- views 증가 시 trigger 로 자동 갱신
);

-- views 증가만으로 updated_at 자동 touch
create or replace function touch_metrics_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger metrics_touch
  before update on metrics
  for each row execute procedure touch_metrics_updated_at();

-- 원자적 views++ (Worker SSR / Flutter 양쪽에서 RPC 호출)
create or replace function increment_metrics_views(card_id uuid)
returns void as $$
  update metrics set views = views + 1 where id = card_id;
$$ language sql;

create index if not exists metrics_updated_at_idx on metrics(updated_at);
```

**보유기간 정책 — Inactive 자동 정리 (views/updated_at 기반)**

- 모든 카드는 default 영구. 시간 기반 자동 만료 없음.
- `/r/{id}` fetch (Worker SSR, Flutter 앱 어느 쪽이든) 시 `rpc/increment_metrics_views(id)` 호출 — views++ + updated_at 자동 갱신.
- 카톡 크롤러·봇·사람 구분 안 함. 노출 자체가 active 신호 (의도적 단순화).
- **Daily cron**: `delete from metrics where updated_at < now() - interval '3 months'` → 동시에 Worker cron 이 동일 id 의 R2 thumbnail 도 DELETE.
- 본인이 자기 카드 한 번이라도 가끔 보면 자동 보호. 친구한테 보낸 카드도 누군가 보고 있으면 살아있음. 정말 아무도 안 보는 카드만 자연 소멸.

**보너스 — `views` 가 무료 product analytics index**: archetype 별·gender 별 viral 분포, A/B test, 인기 카드 상위권 등 SQL 한 줄로 뽑힘. 별도 analytics 인프라 안 박아도 됨.

비용: thumbnail 10 KB × 100만 카드 ≈ R2 $0.15/월. body 2 KB × 100만 행 ≈ Supabase 2 GB. inactive cleanup 으로 자연 감소.

`metrics.id` 의 출처: Flutter 가 analyze 시점에 발급한 uuid 를 `FaceReadingReport.supabaseId` 로 들고 publish 시 그대로 UPSERT 한다. DB 의 `default gen_random_uuid()` 는 analyze 미경유 케이스(라이브 mesh-only 캡처·legacy entry)용 safety net — 정상 trace 에선 발동하지 않는다.

`body` payload 계약 (Flutter 가 채워서 Supabase REST UPSERT 로 직접 씀):

```jsonc
{
  "schemaVersion": 1,           // 배포 전 고정 — install base 생긴 후에 bump
  "source": "camera",            // "camera" | "album"
  "timestamp": "2026-05-17T...",

  // ── demographic 페어 (정제값 ↔ DeepFace raw) ──────────────────────
  // 각 항목은 의도적으로 2개씩 보존: app 의 최종 정제값 + DeepFace 원본 raw.
  // 정제값은 engine input·UI 표시·공유 카드 등 일상 소비에 사용.
  // raw 는 후속 정확도 측정의 근거자료 (DeepFace 예측 vs 사용자/Flutter 확정값
  // 의 일치율·편향 분석). DeepFace 의 정확도가 100% 가 아니라는 전제 하에,
  // 둘 다 살려둔 redundancy 는 audit trail. "정리" 금지.
  "ageGroup": "20s",                // "10s".."90s"      ↔ deepfaceAge (int)
  "gender": "male",                 // app Gender enum   ↔ deepfaceGender
  "ethnicity": "eastAsian",         // app Ethnicity enum ↔ deepfaceEthnicity

  "deepfaceAge": 28,                // DeepFace raw int (정제값은 ageGroup decade 라벨)
  "deepfaceGender": "male",         // DeepFace raw - 단순화를 위해 python 에서 매핑
  "deepfaceEthnicity": "eastAsian", // DeepFace raw — 단순화를 위해 python 에서 매핑

  // 분석 결과 (engine 재계산 input)
  "faceShape": "oval",
  "faceShapeLabel": "타원형",     // optional 한글
  "metrics": { "faceAspectRatio": 0.62, ... },  // mediapipe rawValue 17+
  "lateralMetrics": { "aquilineNose": 0.0, ... }, // optional

  // 1인 카드 자원
  "thumbnailKey": "thumbnails/202605/abc.jpg"
}
```

**저장 금지 (절대 body 에 안 들어감)**:

- 사용자 이름·alias·생년월일
- 얼굴 원본 이미지·landmark 좌표 (정규화된 rawValue 만; 좌표 X)
- archetype / 점수 / 친밀 챕터 본문 / 갈등 시나리오 본문 — engine 매 load 재계산 (react/CLAUDE.md §5)
- **관계형 메타**: `kind`, `partnerUuid`, `pairedWith`, `compat*` 등 — 1인 측정 데이터 외 압류. 페어링은 URL 이 표현.

Worker SSR 이 `body.metrics` + `lateralMetrics` 만으로 shared engine 을 호출해서 archetype·score 를 매번 산출. 룰 업데이트 시 과거 카드도 새 해석으로 자동 갱신.

**궁합 모델**: 별도 테이블·플래그·필드 없음. 두 사람이 각각 솔로 분석을 완료해 metrics A·B 행이 Supabase 에 존재할 때, 그 두 UUID 를 SEP(`~`) 으로 묶은 `https://facely.kr/r/{A}~{B}` 가 곧 compat 카드. Worker SSR (`/r/:id` 단일 route) 이 path 를 SEP 으로 split — 1 개면 관상, 2 개면 궁합. 후자는 `id=in.(A,B)` 한 번 호출 → 양쪽 raw 받아 shared 궁합 engine 에 던짐 → 페어 카드 렌더. compat publish 시 Supabase write 0회 (A·B metrics 는 이미 솔로 단계에서 UPSERT 된 상태).

### 5.3 RLS 정책

Flutter 가 직접 anon key 로 `metrics` UPSERT 를 하므로 RLS 로 PII 차단 + 행 변조 차단:

```sql
alter table metrics enable row level security;

-- 누구나 한 행 읽기 (UUID 모르면 fetch 불가하므로 사실상 link-share 모델)
create policy "metrics_read_anon" on metrics for select using (true);

-- anon INSERT/UPSERT — PII 없는 행만 허용
create policy "metrics_insert_anon" on metrics for insert with check (
  not (body ? 'username')
  and not (body ? 'alias')
  and not (body ? 'birthday')
  and not (body ? 'landmarks')
);

-- 직접 UPDATE 차단. views++ 는 `increment_metrics_views` (security definer) RPC 로만.
create policy "metrics_update_none" on metrics for update using (false);

-- 직접 DELETE 차단. inactivity cron 과 명시 삭제(/api/erase) 는 service-role 사용 (RLS bypass).
create policy "metrics_delete_none" on metrics for delete using (false);
```

`schemaVersion` 알 수 없는 값으로 INSERT 시도 시 Worker SSR 측에서 fetch 후 응답을 410 처리 (forward-compat).

---

## 6. 인증·보안

### 6.1 HMAC token (Worker ↔ Python ↔ Flutter)

- Cloudflare Worker 가 presign 응답에 `token` 함께 발행: `base64url(deadline_ms_8B || HMAC_SHA256(FACE_API_SECRET, deadline_ms || key))`
- Flutter 가 `/analyze` 요청에 `X-Face-Token` + `X-Face-Key` 헤더로 전달
- Python 이 동일 secret 으로 검증 (deadline 비교 + HMAC compare_digest)
- TTL 기본 5분 — presign URL 유효시간과 일치
- 같은 secret 을 `Worker.FACE_API_SECRET` + `Python.FACE_API_SECRET` 환경변수에 동일 값으로 주입

#### ⚠️ 6.1.1 임시 secret-as-token bypass (DEV ONLY — GA 전 제거)

개발·디버깅 편의로 `X-Face-Token` 헤더에 `FACE_API_SECRET` 자체를 그대로 보내면 HMAC 검증을 우회한다. 한시적 dev convenience.

```python
# python/app/utils/auth.py
def verify_face_token(token: str, key: str, secret: str) -> bool:
    # ⚠️ TEMPORARY: secret 자체를 token 으로 받으면 bypass. GA 전 제거 (§6.1.1, TO-DO sunset task).
    if hmac.compare_digest(token, secret):
        logger.warning("FACE_TOKEN_BYPASS used (secret-as-token)", extra={"key": key})
        return True
    # ... 기존 HMAC + deadline 검증 ...
```

- 추가 env 0 개 — 이미 있는 `FACE_API_SECRET` 재사용. 별도 설정 task 없음.
- `compare_digest` 사용 — timing attack 회피.
- 매 사용마다 WARN 로그 (남용 감지·sunset 시점 판단 근거).
- secret 을 안 가진 누구도 못 씀 — bypass 가 활성이라도 secret 보안 = 인증 보안.
- **반드시 GA 전 제거** — auth.py 의 `compare_digest` 분기 + 본 문서 §6.1.1 + TO-DO 의 sunset task 모두 동시 삭제. sunset 트리거: (a) 첫 외부 사용자 베타 시작 또는 (b) Flutter HMAC 클라이언트가 stable 판정.
- **secret 노출 위험은 그대로** — 누군가 `FACE_API_SECRET` 을 손에 넣으면 정상 HMAC 도 위조 가능 + 이 bypass 로 직접 호출도 가능. 추가 손실은 사실상 0 (HMAC 깨진 시점에 모든 게 깨짐). 하지만 bypass 가 살아있는 동안엔 "직접 호출" 의 evidence/timestamp 가 더 명확하지 않아 incident response 가 약간 어려움.

### 6.2 R2 credentials

| 서비스  | R2 권한                                                     | 사용                               |
| ------- | ----------------------------------------------------------- | ---------------------------------- |
| Worker  | Object Read & Write on bucket `facely` (presign signing 용) | 객체 자체엔 손 안 댐. SigV4 서명만 |
| Python  | **동일 토큰 공유** — Object Read & Write on bucket `facely` | `/analyze` 후 temp/ 즉시 DELETE    |
| Flutter | (없음) — presigned URL 만 받아서 PUT                        | secret 단말기에 없음               |

**한 토큰 공유**: Cloudflare R2 의 dashboard token UI 는 prefix scoping·DELETE-only tier 가 없다 (Object R&W / R only / Admin R&W / Admin R only 의 4 단계가 끝, scope 는 bucket 단위). 별도 토큰 만들어도 권한 자체는 동일하니 identity 분리만 위한 운영 비용은 ROI 안 나옴 — 한 토큰 공유가 합리적.

수용된 trade-off: Python 호스트가 뚫리면 thumbnail 까지 read/write/delete 가능. 그 위험은 (a) Python 호스트 hardening, (b) `FACE_API_SECRET` 로 외부 호출 차단, (c) secret rotation 으로 완화. 더 강한 격리가 필요해지면 Cloudflare API 로 custom policy token 발급(programmatic) 으로 전환 가능 — 현재는 over-engineering.

R2 API token 1 개:

- **`facely-r2-rw`** — Object Read & Write on bucket facely. Worker secret + Python env 에 동일 값 주입.

### 6.3 Rate-limiting

Cloudflare WAF / Workers Rate Limit:

- `/api/r2/presign` — 60/min/IP
- `/r/{uuid}` — 안 걸어도 됨 (정적 SSR)

Supabase rate-limit (metrics UPSERT 는 Flutter 직통이므로):

- Supabase 프로젝트 기본 limit (free tier 60 req/s 정도) 로 충분. 비정상 트래픽은 Supabase 대시보드의 anon key abuse 감지에 의존.

---

## 7. Shared engine — Dart → JS 컴파일

```
shared/lib/face_engine.dart            ← SSOT (모든 룰·reference·quantile)
        │
        │ pnpm build:shared
        │ = dart compile js -O1 ../shared/lib/face_engine.dart -o app/lib/shared/face_engine.js
        ▼
react/app/lib/shared/face_engine.js    ← build artifact (.gitignore)
        │
        │ import (side-effect: globalThis.runEngine / runCompat 등록)
        ▼
react/app/lib/traits.ts                ← out = JSON.parse(globalThis.runEngine(JSON.stringify(raw)))
        │
        ▼
share.tsx SSR 렌더링
```

**룰·reference·quantile 수정 시 절대 React 쪽에서 재구현 금지.** `shared/` 한 번만 수정 → `pnpm build:shared` → 양쪽 자동 반영.

Flutter 측은 `pubspec.yaml` 에 `path: ../shared` 의존으로 들고 옴 — 그쪽은 compile 불필요.

---

## 8. 디렉토리 SSOT

### react/

| 경로                           | 역할                                                                                   |
| ------------------------------ | -------------------------------------------------------------------------------------- |
| `workers/app.ts`               | RR7 createRequestHandler entry                                                         |
| `app/routes.ts`                | 라우트 정의 (4 개)                                                                     |
| `app/routes/_index.tsx`        | landing (dev 데모용)                                                                   |
| `app/routes/share.tsx`         | `GET /r/:id` SSR loader (PAIR_SEP split → 1 또는 2 UUID) + meta + ShareCard/CompatCard |
| `app/lib/share-id.ts`          | `PAIR_SEP = "~"` + `parsePairId(id): string[]` 헬퍼 (관상·궁합 분기 SSOT)              |
| `app/routes/api.r2.presign.ts` | `POST /api/r2/presign` — SigV4 presign + HMAC token                                    |
| `app/lib/supabase.ts`          | `fetchMetrics(env, ids[])` read-only REST helper (compat 도 multi-id 한 번)            |

> Worker 가 metrics 에 write 하지 않음 → `/api/share` 같은 publish endpoint 는 일부러 만들지 않음. Flutter ↔ Supabase 직통.
> | `app/lib/traits.ts` | shared engine 호출 + RenderedShare 합성 |
> | `app/lib/shared/face_engine.js` | **commit 금지** build artifact |
> | `app/lib/types.ts` | ShareCardRow / RenderedShare / EngineOutput SSOT |
> | `app/components/ShareCard.tsx` | 카드 UI |
> | `app/components/CTA.tsx` | 1.5s deep link 시도 + 스토어 fallback |
> | `app/types/env.d.ts` | secret 타입 augmentation (cf-typegen 자동 보완 전 사용) |
> | `public/{male,female}.png` | 카드 portrait fallback (성별만 보고 swap) |
> | `public/logo.png` | OG static fallback (1200×630) |
> | `public/.well-known/{aasa,assetlinks}` | prod 직전 실값 |
> | `wrangler.jsonc` | env vars + assets binding + routes |

### Python (`python/`)

기존 — DeepFace `/analyze` + 즉시 R2 DELETE 추가 예정.

### Flutter (`flutter/`)

기존 + `lib/data/services/{r2_uploader,face_metadata_client,image_resizer}.dart`.

---

## 9. 환경 변수 정리

### Worker (`react/wrangler.jsonc` vars + secrets)

| 이름                                          | 종류   | 용도                                                                                                                                            |
| --------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `WEBAPP_BASE`                                 | var    | `https://facely.kr` (canonical host). 자기 자신 reference·OG url·CTA deep link 조립 모두 이 값 기반. **Flutter `.env` 의 동일 변수와 같은 값**. |
| `APP_STORE_URL` / `PLAY_STORE_URL`            | var    | 스토어 fallback                                                                                                                                 |
| `APP_BUNDLE_ID_IOS` / `APP_BUNDLE_ID_ANDROID` | var    | 메타에 반영                                                                                                                                     |
| `R2_ACCOUNT_ID`                               | var    | SigV4 endpoint host                                                                                                                             |
| `R2_BUCKET_NAME`                              | var    | `facely`                                                                                                                                        |
| `R2_CDN_BASE`                                 | var    | `https://cdn.facely.kr`                                                                                                                         |
| `FACE_TOKEN_TTL_SEC`                          | var    | `"300"`                                                                                                                                         |
| `R2_ACCESS_KEY_ID`                            | secret | Worker R2 API token                                                                                                                             |
| `R2_SECRET_ACCESS_KEY`                        | secret | Worker R2 API token                                                                                                                             |
| `FACE_API_SECRET`                             | secret | HMAC (Python 과 동일 값). presign 발급 시 함께 줘서 `/analyze` 호출 인증                                                                        |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY`          | var    | metrics REST `select` 만 (read-only). Worker 는 write 안 함                                                                                     |

### Python (`python/docker-compose.yml` env)

| 이름                                        | 용도                                                           |
| ------------------------------------------- | -------------------------------------------------------------- |
| `FACE_API_SECRET`                           | Worker 와 동일 HMAC                                            |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | Worker 와 **동일한 한 토큰** 공유 (§6.2). temp/ 즉시 DELETE 용 |
| `R2_ACCOUNT_ID` / `R2_BUCKET_NAME`          | DELETE URL 조립                                                |
| `DETECTOR_BACKEND` / `MAX_DOWNLOAD_MB` / 등 | 기존                                                           |

### Flutter (`flutter/.env`)

| 이름                               | 용도                                                                                            |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| `WEBAPP_BASE`                      | `https://facely.kr` (Worker `WEBAPP_BASE` 와 동일 값). presign API · share URL 조립 양쪽에 사용 |
| `FACE_META_API_BASE`               | `https://meta.facely.kr` (DeepFace)                                                             |
| 기존 SUPABASE / KAKAO / REVENUECAT | 그대로                                                                                          |

---

## 10. 배포 흐름 요약

```
1. shared/ Dart 룰 변경
   → cd react && pnpm build:shared
2. (필요시) Flutter 빌드 / Worker typecheck
3. Worker: pnpm wrangler deploy
4. Python: cd python && docker compose up -d --build
5. Flutter: 평소 빌드 → 스토어 업로드
```

R2 lifecycle / Supabase 스키마 변경은 별도 절차 (대시보드 또는 마이그레이션 SQL).

---

## 11. 절대 금지 (regression 차단용 chunk)

- 모바일 이미지가 Worker 경유 (Workers 의 R2 binding 으로 PUT) — **금지**. 모바일 ↔ R2 직통 PUT.
- Worker 가 Supabase 에 write — **금지**. Worker 는 read-only. `/api/share` 같은 publish endpoint 도입 X. Flutter ↔ Supabase 직통.
- Worker 와 Flutter 사이에 body payload 왕복 — **금지** (큰 데이터 두 번 흐름). UUID 만 흐른다.
- Python `/analyze` 가 DeepFace raw (`{age, gender, race}`) 외 가공·매핑·정규화 응답 — **금지**. 모든 변환 책임은 소비자(Flutter).
- `body` 에 얼굴 원본 이미지·landmark 좌표·alias·사용자 이름·생년월일 저장 — **금지** (thumbnailKey 포인터만 허용; RLS check 로 강제).
- 별도 `share_card` 테이블 생성 — **금지**. 공유 payload 는 기존 `metrics` 한 테이블로.
- archetype·점수·rule 결과를 DB 에 저장 — **금지**. 매 load 시 shared engine 재계산.
- React 쪽 룰 재구현 — **금지**. `shared/` 한 곳만.
- Flutter 앱에 R2 secret·Supabase service-role key 박기 — **금지**. presigned URL + anon key 만.
- OG meta 를 client-only 로 주입 — **금지**. `route.meta` export 만.
- 친밀 챕터·갈등 시나리오 본문을 Worker 응답에 포함 — **금지** (앱 안에서만 생성).
- publish 단계에서 **새 UUID 발급** — **금지**. analyze 시점에 발급한 uuid 가 `temp/{uuid}.jpg` → `thumbnails/{YYYYMM}/{uuid}.jpg` → `metrics.id` → `/r/{uuid}` 까지 그대로 흐른다. `SupabaseService.saveMetrics` 의 `?? _uuid.v4()` fallback 은 analyze 미경유 케이스(라이브 mesh-only 캡처 등) 한정.

---

## 12. PII & Privacy

### 12.1 PII 분류표

| 데이터                                                                                                          | PII 여부                                             | 위치                                         | 비고                                                                        |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------- |
| 720² 분석용 이미지                                                                                              | PII (얼굴)                                           | R2 `temp/`                                   | Python 즉시 DELETE + 1일 lifecycle. 노출 창 짧음.                           |
| **256² thumbnail**                                                                                              | **PII (얼굴, 식별 가능)**                            | R2 `thumbnails/` (cdn.facely.kr public read) | UUID-as-unguessable-URL access control. inactivity 3개월 자동 정리 (§12.2). |
| body (rawValue·demographic 카테고리·thumbnailKey·deepface raw·schemaVersion·source·timestamp·faceShape) | 비-PII                                               | Supabase `metrics`                           | 정규화된 값만. landmark 좌표·이름·생년월일 0.                               |
| `metrics.id` (UUID)                                                                                             | 준-PII (PII 인 thumbnail 을 가리키는 capability key) | Supabase + URL                               | UUID v4 (122 bit) — guess 사실상 불가.                                      |

법적 frame:

- **GDPR Art 4(1)**: 식별 가능 사진 = personal data. 얼굴 인식 목적 시 Art 9 special category (biometric).
- **한국 PIPA**: 사진은 개인정보. 자동 분석 결과(나이·성별·인종 추정) 도 개인정보.
- 따라서 facely 는 GDPR 의 controller / PIPA 의 개인정보처리자.

### 12.2 보유기간 정책 (inactive 3개월 자동 정리 + 명시 삭제)

- **default**: 시간 기반 자동 만료 X. 대신 **inactivity 기반** — `/r/{id}` fetch 마다 `views++` + `updated_at` 갱신 (§5.2 RPC), `updated_at < now() - 3 months` 인 행이 daily cron 의 대상.
- **active 보호**: 본인이 자기 카드 가끔 보거나, 친구가 카톡 link 클릭만 해도 자동 보호. 정말 아무도 안 보는 카드만 정리.
- **right to erasure (즉시 삭제)**: 본인 명시 삭제 시 즉시 처리. 삭제 경로:
  - Worker 신규 endpoint `POST /api/erase` (HMAC 인증) — R2 thumbnail DELETE + Supabase 행 DELETE 둘 다 처리
  - 또는 Supabase Edge Function 으로 동일 작업
- **사용자 통제권**: P1 단계에 "내 공유 link 관리" UI — 본인 device 의 Hive history 의 uuid list 로 본인이 만든 카드 확인, 개별 [삭제] 버튼이 `/api/erase` 호출.
- **데이터 minimization 양립**: inactivity cleanup 으로 dormant 데이터 자연 감소. user_id 같은 ownership 컬럼 추가 0 → metrics 행은 여전히 anonymous (신원 join 불가).

#### Cron 구현 — Cloudflare Worker Cron Trigger

Supabase 측 cron 확장(pg_cron 등) 의존 회피 — 이미 사용 중인 Cloudflare Workers 의 `triggers.crons` 로 일일 1회 실행. 같은 Worker 코드 안에서 R2 DELETE + Supabase REST DELETE 둘 다 처리하므로 vendor·infra 추가 0.

```jsonc
// react/wrangler.jsonc
"triggers": { "crons": ["0 18 * * *"] }   // 03:00 KST = 18:00 UTC prev day
```

```ts
// react/workers/app.ts (또는 workers/cron.ts 분리)
export default {
  fetch: requestHandler, // 기존 RR7 handler

  async scheduled(event, env, ctx) {
    ctx.waitUntil(cleanupDormant(env))
  },
} satisfies ExportedHandler<Env>
```

`cleanupDormant(env)` 흐름:

1. **select** — Supabase REST `?select=id,body&updated_at=lt.{now-3months}` 로 dormant 후보 list (id + thumbnailKey).
2. **R2 DELETE** — aws4fetch 로 각 `thumbnailKey` SigV4 signed DELETE. 실패 row 는 skip (다음 cron 에서 재시도).
3. **Supabase DELETE** — service-role key 로 metrics 행 삭제. R2 DELETE 성공한 행만 대상.

순서: **R2 먼저 → DB 나중**. DB 먼저 지우면 orphan R2 객체가 영원히 남을 위험. R2 실패 시 row 는 살려두고 다음 cron 재시도.

필요 Worker secret 추가:

- `SUPABASE_SERVICE_ROLE_KEY` — metrics 행 DELETE 전용. anon RLS 의 `delete_none` 정책을 bypass 하기 위함. cron + `/api/erase` 두 곳만 사용.

### 12.3 동의 / privacy policy

P0 출시 전 필수:

- **분석 동의 화면** — 카메라/앨범 이미지가 외부(R2 + Python DeepFace) 로 전송됨, thumbnail 이 공유 시 R2 보관됨을 명시
- **privacy policy 페이지** — 처리목적·보유기간·제3자 제공(없음)·국외이전(R2/Supabase 리전 명시)·이용자 권리(열람·삭제·정정·처리정지)·고충처리부서·근거법령
- **카메라/사진 권한 사유 문구** — iOS Info.plist / Android manifest 의 권한 설명 (`NSCameraUsageDescription` 등)
- **연령 확인** — 14세 미만 사용 제한 (PIPA 22조의2 법정대리인 동의 회피)

### 12.4 access control 의 실체

`cdn.facely.kr/thumbnails/{YYYYMM}/{uuid}.jpg` 는 **public read** — UUID 만 알면 누구나 GET. 보호는 "UUID 가 unguessable" 에 의존 (security through obscurity, 단 122 bit entropy 라 brute-force 가 사실상 불가능):

- **공유 link 발송 = 그 thumbnail URL 의 발송과 사실상 동일** — 사용자가 share_plus 로 카톡에 보내는 행위는 "이 사진 URL 을 카톡방 참여자에게 공개한다" 는 동의로 간주.
- **검색엔진 indexing 방지** — `/r/*` 라우트에 `<meta name="robots" content="noindex">` SSR 강제 + `cdn.facely.kr` 의 R2 객체에 robots.txt 또는 `X-Robots-Tag` 헤더로 noindex.
- **referer leak 방지** — R2 객체 응답 헤더에 `Referrer-Policy: no-referrer` (가능하면).

### 12.5 region

- Supabase: 프로젝트 region 명시 (e.g., `ap-northeast-2` Seoul) — 국내 데이터 거주 명확화.
- R2: Cloudflare R2 는 region auto-distributed (글로벌). PIPA 국외이전 동의 대상 — privacy policy 에 명시.
- Python: 홈서버 (국내). 국외이전 0.
