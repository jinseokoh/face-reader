# Face Reader — Claude Code 오리엔테이션

## ⛔ 0. UI 통일감 — 절대 1순위 (이 규칙 위반 시 즉시 폐기·재작업)

**대부님은 화면 간·요소 간 디자인 불일치를 못 견디는 사람이다.** 폰트 패밀리·크기·웨이트가 화면마다 다르면 그 자체로 결함이다. 모든 신규/수정 UI 는 아래 토큰 외 값을 절대 쓰지 않는다.

### 0.1 폰트 — 본문은 SongMyung, 버튼은 system default

- **본문/제목/라벨**: SongMyung 단일 패밀리. (Pretendard·기타 sans 금지. material default 금지 — `fontFamily: 'SongMyung'` 명시.)
- **버튼 라벨 (TextButton/ElevatedButton/OutlinedButton/FilledButton/IconButton/CupertinoButton/MaterialButton 의 child Text, AppBar action, 다이얼로그 actions, BottomSheet CTA)**: fontFamily 자체를 명시하지 않는다 (system default 사용). 위반은 `.claude/hooks/block-button-songmyung.py` PreToolUse hook 이 자동 차단한다.
- 영문/숫자만 단독으로 나오는 메타 캡션은 예외 가능. 한국어와 함께 나오는 본문 줄은 무조건 SongMyung.

### 0.2 텍스트 hierarchy — 6 단 token 만 허용

| token | size | weight | color | 용도 |
|---|---|---|---|---|
| display | 28 | bold | textPrimary | 화면 최상단 타이틀 (예: "AI 관상가") |
| modalTitle | 18 | w600 | textPrimary | AlertDialog/모달 제목 |
| sectionTitle | 16 | w600 | textPrimary | 섹션 헤딩 (리포트 내 큰 구획) |
| subTitle | 14 | w600 | textPrimary | InfoRow / LabelRow / 카드 헤더 |
| body | 15 | w400 | textSecondary | 모달·리포트 본문 단락 (height 1.7~1.8) |
| caption | 13 | w400 | textSecondary | 보조 설명·tagline (height 1.5~1.6) |
| hint | 12 | w400 | textHint | 한자·메타라벨·percent |

**금지:** 같은 modal 안에서 두 가지 fontWeight 가 섞여 있는데 한쪽만 명시(나머지 default w400) 되는 패턴. 모든 Text 위젯은 fontFamily/size/weight/color 를 명시하거나 위 token 의 helper 를 통해서만 만든다.

### 0.3 모달·다이얼로그 표준
- background: `Colors.white`
- shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`
- title: modalTitle token (18 / w600 / SongMyung / textPrimary)
- content body: body token (15 / w400 / SongMyung / textSecondary / height 1.8)
- 닫기 버튼: TextButton, fontSize 15 / w600 / textPrimary, **fontFamily 미지정 (system default)** — §0.1 의 버튼 룰 적용

### 0.4 pill / chip / row label 안 텍스트 단일톤
하나의 pill/chip/single-line label 안에서 색·크기를 분리하지 않는다. priority 차이는 줄 분리 또는 background tint 로만.

### 0.5 가운데점(`·`) 남발 금지
한 줄에 두 개 이상의 의미를 우겨넣을 때 `·` 로 잇지 않는다. 줄 바꿈으로 분리한다. 예:
```
✗  얼굴로 읽으면 흔치 않게 잘 맞는 자리 · 좋은 점 압도
✓  좋은 점 압도
   얼굴로 읽으면 흔치 않게 잘 맞는 자리.
```

### 0.6 같은 역할이면 같은 위젯
"관상 분석에 대하여" / "궁합 분석에 대하여" 처럼 역할이 같은 두 modal 은 동일한 base widget(또는 동일한 style 토큰 set)을 공유해야 한다. 따로 만들면 반드시 어긋난다.

---

관상 분석 Flutter 앱. MediaPipe Face Mesh(468 landmarks) 을 입력으로 17 frontal + 8 lateral metric → z-score → 14-node tree → 10 attribute → archetype 까지 일관된 관상 파이프라인. 궁합은 관상 엔진과 **동등한 별도 엔진**으로 전통 관상학(五行·十二宮·五官·三停·陰陽) grounded 재설계 중 — 설계 SSOT: `docs/compat/FRAMEWORK.md`.

마지막 업데이트: 2026-04-21 (engine v2.9 · Opt-D per-shape quantile + narrative soft predicate + 음양 bar UI)

---

## 🚀 다음 PC 에서 이어받을 때 먼저 읽기

세션 시작 시 이 섹션 먼저 확인. engine v2.9 (美人相 rule 7 개 도입 + 매력도 lax/stacking narrowing) 이 현재 stable baseline.

### 엔진 버전 스냅샷 (2026-04-20)

- **engine v2.9** · narrative v3 · Hive schemaVersion 1
- Stage 0 shape preset: **철수** (raw score 에 얼굴형 관여 0)
- 매력도 Stage 1b distinctiveness: **철수** (bell 제거)
- 얼굴형 은 archetype shape-gated overlay + narrative Layer B 에만 남음
- MC sampler **bias=0.0, std=1.0** (N=14 eastAsian female 30s 실사용자 empirical z 가 N(0,1) 에 수렴하도록 ref 재보정 완료)
- eastAsian female reference 19 metric mean 재조정 (faceAspectRatio 1.35→1.30, midFaceRatio 0.30→0.32, cheekboneWidth 0.90→0.93 등)
- 美人相 rule set (v2.9): Z-NG 五官端正, O-MM 桃花眼, O-EM2 眉目清秀, O-RL 朱唇小口, O-CKE 顴骨突過(-), O-EZ 目偏不正(-), P-MJ 印堂明潤. 麻衣相法·神相全編 grounded
- 매력도 narrowing: O-EM 임계 0.5→1.0 + attractiveness 제거, Z-07/Z-09/P-03/Z-LFR 의 attractiveness 부분 제거

#### v2.9 핵심 invariant (회귀 차단용)

1. **attribute row 합 = 1.00 ± 0.01** — 9 node(face/ear 제외) 가중치 정규화.
2. **zone 합 ∈ [0.25, 0.40]** per (attribute × zone) — 각 속성이 상·중·하정 중 어느 한 곳에 55% 이상 몰리지 않도록.
3. **3 zone 모두 non-zero** per attribute — 각 속성이 상·중·하정 3 zone 전부 참여.
4. **per-metric 영향력 ∈ [0.15, 1.20]** — single-metric 노드(glabella=browSpacing, cheekbone=cheekboneWidth, philtrum=philtrumLength)는 구조상 sum-across-attributes ≈ 1.0 까지 오름. 고아 차단(≥0.15) + 다중 metric 노드 dilution 허용.
5. **per-metric max/min ≤ 6.5×** — v2.7 decorrelation 후 single-metric vs 4-metric(mouth) 노드 dilution 격차 5~6× 가 구조적 정상.
6. **rule magnitude cap |Δ| ≤ 0.5** — Zone/Organ/Palace/Age/Lateral rule 의 단일 effect 는 0.5 이상 못 줌. step-function dominance 방지.
7. **decorrelated dominant nodes** — 10 attribute 가 각기 다른 1 개 노드를 top weight(≥0.17) 로 가짐: wealth=nose, leadership=chin, intelligence=forehead, sociability=mouth, emotionality=eye, stability=chin+glabella, sensuality=eye+mouth tied, trustworthiness=forehead+eye+chin tied, attractiveness=eye+mouth tied, libido=eyebrow. 학자형/외교형 cluster-dominance 차단.

### 회귀 차단 test

- `test/physiognomy_tree_sanity_test.dart` (18 assertion) — row sum, zone 합, zone coverage, per-metric 영향력(≤1.20), max/min ratio(≤6.5). v2.7 invariant 강제.
- `test/shape_archetype_bias_test.dart` — 5 shape × 2000 샘플 → 각 shape 의 top-1 attr 분포 < 35%. shape-bound archetype 편향 부활 차단.
- `test/archetype_template_sanity_test.dart` — 6 template hit rate ≥ 55% (rule cap 으로 template 차별 신호 약화를 의도적으로 허용).
- `test/score_distribution_test.dart` — spread invariant, saturation < 5%.
- `test/evidence_snapshot_test.dart` — 고정 z-map 에 대한 rule/score/contributor 완전 snapshot.
- `test/real_users_recalibration_test.dart` — N=14 실사용자 empirical z 분포 + archetype concentration 진단 (현재 max 28.6% = 4/14).

### 이번 세션 완료 (2026-04-21)

- **per-shape quantile (Opt-D)** — `attribute_normalize.dart` 에 `_attrQuantilesByShape` 도입 (5 shape × 2 gender × 10 attr × 21-point). `score_calibration.dart` 에 `calibrateQuantilesByShape` + `_simulateRaws(fixedShape:)` stratification 추가. shape-conditional bias 근본 제거.
- **narrative soft predicate** — `_Frag.weight: double Function` 로 전환 (bool → double). band plateau/cliff 제거, `_hi/_lo/_mi` ramp + `_softHiZ/_softLoZ/_softMidZ` + cumulative-weight sampling 으로 인접 z 의 변화가 fragment 선택에 연속 반영. 결정성(동일 seed → 동일 fragment) 유지.
- **narrative fallback 1→5** — 재능·재물·사회·건강 섹션의 Opening/Advice/Shadow/Strength 16 개 pool 을 각 5 variants 로 확장. @{slot} 토큰(palace_*·mount_*·talent_word·structure) + @__STRONGEST_NODE__ 조합.
- **음양 bar UI** — `report_page.dart` 에 `_YinYangBar` 위젯 추가. 부위별 상세 해석 섹션 상단 (삼정 radar 위) 에 음기(푸른)→조화(amber)→양기(붉음) 그라디언트 + skew marker + tone pill. PDF/텍스트 export 에도 음양 균형 line 추가.

`flutter analyze` clean, **133 test 전부 green** (neural calibration prints 포함).

### 다음 작업 (우선순위순)

| 우선 | 작업 | 근거 | 재개 지시 |
|---|---|---|---|
| P0 | **공유 link 통합 — share_card publish + app_links 라우팅** | 이미지 공유 / 카톡 공유 두 entry 를 share_plus 단일 [공유] 버튼으로 통합. 카드 PNG + 요약 row 를 supabase 에 publish 하면 `react/` 의 share host 가 카톡 미리보기 + 미설치 사용자용 SSR 페이지 + universal/app link 라우팅 담당. 자세한 계약·schema·AASA 는 `react/DEEPLINK.md` SSOT | `"react/DEEPLINK.md §3 의 SharePublisher 스펙 그대로 lib/domain/services/share/share_publisher.dart 작성. nanoid + RepaintBoundary PNG + R2 upload + supabase share_card insert + share_plus shareUri. 그 다음 main.dart 에 app_links 패키지 초기화 + /r/:shortId path → ReportPage routing"` |
| P0 | **AASA / assetlinks 실값 + iOS entitlements + Android intent-filter** | universal/app link 동작의 양쪽 필수 설정. `react/public/.well-known/` 두 파일은 placeholder 상태. iOS Runner.entitlements + Android Manifest 양쪽 도메인 박기 | `"react/DEEPLINK.md §4 체크리스트 따라가며 react/public/.well-known/ TEAMID + Play SHA256 실값 박기. ios/Runner/Runner.entitlements 에 applinks:share.face.app, AndroidManifest.xml 에 autoVerify intent-filter 추가"` |
| P1 | **궁합 엔진 P2 — 五行 body classifier 구현** | `lib/domain/services/compat/` 하위 신규 파일군. `docs/compat/FRAMEWORK.md` §2 z-score weighted formula 그대로. distribution test 로 5 element 고르게 나오는지 검증 | `"docs/compat/FRAMEWORK.md §2 읽고 five_element_classifier.dart + test/compat/five_element_distribution_test.dart 작성"` |
| P0 | **pull-to-refresh state 증발 root-cause 고정** | 진단 로그는 삽입 완료. 실기에서 재현 후 stacktrace 확보가 필요. `fromJsonString` 이 rawValue→엔진 재계산 도중 어느 라인에서 터지는지 정확히 짚어야 함 | `"실기 앱 run → 관상 tab 에서 pull-to-refresh → 콘솔의 [History] reload FAIL entry N: … + stacktrace + raw head 전부 수집. 해당 라인 원인 제거 + reloadFromHive 가 parse 실패 시 in-memory state entry 드롭하지 않도록 방어(현재는 parsed 만 state 로 커밋 → 실패 entry 소멸). 관건은 'Hive raw 보존' 은 이미 되어 있으니 state 쪽 보수적 업데이트만 추가"` |
| P0 | **실사용자 N 확장** (현 N=14 eastAsian female 30s → ≥100 전 demographic) | v2.8 은 단일 demographic 14 명으로 ref 재보정. 남·타 ethnicity·age 는 아직 idealized MC 기반 | `"test/fixtures/real_users_*.json 에 male/caucasian/40s 등 추가 수집 후 real_users_recalibration_test.dart 로 per-demographic 재보정"` |
| P1 | **친밀 narrative gender 분기 컨텐츠 채우기** | `compat_phrase_pool.dart` 의 `intimacyAxisDetailsByGender` / `intimacyOpenerByBucketByGender` / `intimacyClosingByBucketByGender` male/female 두 블록은 동일 복제 상태. male 은 적극·결단 톤, female 은 수용·해석 톤으로 자유 분기 | `"compat_phrase_pool.dart 의 Gender.female 블록 3 곳을 수용·해석 톤으로 다듬기. 같은 fact 의 정반대 시점 (남자=행동 지시 / 여자=수용·해석 프레이밍)"` |

### 공유 link 통합 — Flutter ↔ React 앱 인터랙트 (2026-04-26 추가)

이미지/카톡 공유의 두 entry 를 `share_plus` 단일 [공유] 버튼으로 통합하고, 받는 사람이 link 를 탭했을 때 `react/` 폴더의 Cloudflare Workers + React Router v7 SSR 앱이 카드 미리보기·랜딩·deep link 라우팅을 담당. 비용 안전성 (Vercel 회피) + 카톡 viral bandwidth unmetered 가 stack 결정 이유. 자세한 SSOT: `react/DEEPLINK.md`.

```
[Flutter] [공유] 탭
  → RepaintBoundary → 1200×630 PNG
  → nanoid 8자리 shortId
  → R2 / Supabase Storage upload (PNG)
  → Supabase share_card insert (shortId, og_meta, highlights[3], …)
  → share_plus 로 https://share.face.app/r/{shortId} 발송
        ↓
[받는 사람 카톡 탭]
  → 앱 설치 OK : universal/app link → app_links 패키지가 /r/:shortId 라우팅 → ReportPage
  → 앱 미설치  : react/ 의 SSR 페이지가 카드+요약+CTA → store fallback
  → 카톡 크롤러: react/ 의 meta export 가 OG tag 동적 주입
```

Flutter 쪽 책임:
- **publish**: `lib/domain/services/share/share_publisher.dart` (P0 신규) — nanoid + RepaintBoundary + R2 upload + supabase insert + share_plus
- **inbound**: `lib/main.dart` — `app_links` 패키지로 `/r/:shortId` 수신 → ReportPage 라우팅
- **iOS associated-domains**: `ios/Runner/Runner.entitlements` 에 `applinks:share.face.app`
- **Android intent-filter**: `AndroidManifest.xml` 에 `autoVerify="true"` + `https://share.face.app/r/`
- **저장 금지 항목**: 친밀 챕터·갈등 시나리오 본문·얼굴 이미지·landmark — share_card row 에 절대 들어가지 않음 (privacy + 카톡 단톡 leak 방지)

React 앱 쪽 책임 (참고용, 작업은 별도 디렉토리):
- `react/app/routes/share.tsx` — loader (supabase fetch) + meta (OG 동적) + UI
- `react/app/lib/types.ts` — `ShareCardData` 인터페이스가 share_card row schema 의 SSOT — Flutter 의 publish 함수와 1:1 매칭. 변경 시 양쪽 동시 PR
- `react/public/.well-known/{aasa, assetlinks.json}` — Flutter 의 entitlements/manifest 와 도메인·bundle ID 일치 필수
- `react/wrangler.jsonc` 의 `APP_STORE_URL` / `PLAY_STORE_URL` — 미설치 fallback CTA URL

### 최근 커밋 시퀀스 (역순)
```
8ee3870 report: 음양 균형 bar — 부위별 상세 해석 섹션 상단 시각화
6e29f86 narrative fallback variants 1→5 — 재능·재물·사회·건강 4 섹션
7e705fe narrative soft predicate — band plateau/cliff 제거 (weighted sampling)
3d3c136 per-shape quantile normalize (Opt-D) — shape-conditional bias 근본 제거
58cb846 compat v1 엔진 전면 재설계 — 五行·十二宮·五官·三停·陰陽·情性 4-layer hybrid
8e8637d update attribute md
f5b1159 update pdf generation logic
22b8843 engine v2.8 + narrative v3 섹션 재설계
5896024 engine v2.5 sync + 다음 작업 handoff 정리
```

---

## 문서 규칙 (이 세션에서 Claude 가 지켜야 할 룰)

### 금지어 (절대 답변·커밋·문서에 쓰지 말 것)

레거시 / 예전 / 구 엔진 / 기존 구현 / 이전에는 / legacy / 마이그레이션 / 호환성 / 참조만 / 참고만

근거 제시는 세 가지로만:

1. **현재 엔진의 구조적 특성** (row 합 = 1.00, stage firing rate, 등)
2. **Monte Carlo 측정** (20,000 샘플, seed=42, input z ~ N(0.2, 0.85))
3. **UX 판단** (bar chart 가독성, 사용자 해석 난이도, 점수 saturation 등)

과거 상태를 비교 기준으로 제시하는 순간 트리거. 설계 제안에 "nullable 로 optional", "기존 호환" 같은 safety hook 금지. 데이터·Hive·스키마 전부 drop-recreate 자유.

### 깊이 있는 레퍼런스

모든 상세 문서는 `docs/` 하위. 진입점은 `docs/README.md` (인덱스). 이 파일(CLAUDE.md)은 현재 상태의 스냅샷과 프로젝트 규칙만 유지 — 수치 표나 연구 인용은 docs/runtime/OUTPUT_SAMPLES.md 로 위임.

---

## Tech Stack

- **Flutter** (Dart SDK ^3.11.0)
- **camera** ^0.11.1 — 카메라 preview + frame streaming
- **mediapipe_face_mesh** ^1.2.4 — face mesh 추론 (FFI + TFLite)
- **Hive** — demographics prefs + history persist
- **Supabase** — metric 원격 저장

## File Structure

```
lib/
├── main.dart
├── core/                                      # Theme, Hive init, shared utils
├── data/
│   ├── constants/
│   │   ├── face_reference_data.dart           # 17 frontal + 8 lateral 기준값 (6 ethnicity × 2 gender) — SSOT
│   │   ├── archetype_text_blocks.dart         # Archetype intro / special archetype 본문
│   │   ├── rule_text_blocks.dart              # Rule ID → 본문 매핑
│   ├── enums/                                 # Attribute, Gender, AgeGroup, Ethnicity, MetricType
│   ├── repositories/metaphor_repository.dart  # Rule → 은유 텍스트 매칭
│   └── services/
│       ├── face_shape_classifier.dart         # TFLite 28-feature MLP (76.9% test acc)
│       └── supabase_service.dart
├── domain/
│   ├── models/
│   │   ├── physiognomy_tree.dart              # 14 node 구조 SSOT (docs/engine/TAXONOMY.md)
│   │   ├── face_analysis.dart                 # analyzeFaceReading() — 엔드투엔드 파이프라인
│   │   ├── face_reading_report.dart           # rich evidence schema (아래 참조)
│   └── services/
│       ├── face_metrics.dart                  # 17 frontal ratio/angle/shape
│       ├── face_metrics_lateral.dart          # 8 lateral 3/4-view + yaw classify
│       ├── metric_score.dart                  # z → 0-100 정수 메트릭 점수
│       ├── physiognomy_scoring.dart           # 삼정/오관 node tree + scoreTree()
│       ├── attribute_derivation.dart          # 5-stage pipeline → 10 raw attribute
│       ├── attribute_normalize.dart           # 성별 quantile → 5.0~10.0 normalize
│       ├── score_calibration.dart             # Monte Carlo 기반 quantile table 생성
│       ├── archetype.dart                     # 10 attribute → top-2 기반 archetype
│       ├── mc_fixtures.dart                   # 공용 6 face template (physiognomy MC 테스트)
│       ├── report_assembler.dart              # 본문 조립 래퍼 (intro/closing + life questions)
│       ├── life_question_narrative.dart       # 인생 질문 8섹션 서술 v2 (Beat-Fragment Grammar, face-hash seed)
│       └── age_adjustment.dart                # 50+ 보정
└── presentation/
    ├── providers/                             # Riverpod: gender, ageGroup, ethnicity(Hive persist), history, auth, tab
    ├── screens/
    │   ├── home/
    │   │   ├── home_screen.dart               # Demographic pickers + 진입
    │   │   ├── face_mesh_page.dart            # 카메라 + mesh overlay + 2단계 캡처
    │   │   ├── album_preview_page.dart        # 앨범 모드 preview/confirm
    │   │   └── report_page.dart               # 리포트 UI + 속성 expand + 14-node tree
    │   ├── compatibility/                     # compat 탭 stub (신규 엔진은 docs/compat/FRAMEWORK.md P2~P7 에서 제작)
    │   └── physiognomy/                       # 관상 설명 스크린
    └── widgets/

docs/                                           # 모든 문서 — 진입은 README.md
test/                                           # 102 tests (calibration, fairness, spread, invariant snapshots, …)
```

## Report Schema (rich evidence)

```
FaceReadingReport
├── metrics           : Map<String, MetricResult>          17 frontal
├── lateralMetrics    : Map<String, MetricResult>?         8 lateral (있을 때만)
├── lateralFlags      : Map<String, bool>?                 aquilineNose 등
├── nodeScores        : Map<String, NodeEvidence>          14 node own/rollUp z
├── attributes        : Map<Attribute, AttributeEvidence>  raw+정규화+기여 리스트
│       └── contributors: List<Contributor>                |v|>0.05 전부, |v| desc
├── rules             : List<RuleEvidence>                 stage 태그 포함
├── archetype         : ArchetypeResult                    top-2 + special
├── faceShapeLabel    : String?                            ML classifier 결과
└── faceShapeConfidence: double?

shortcut: report.attributeScores  → Map<Attribute, double>  normalized 5~10 값
```

각 Contributor.id 예: `node:nose`, `distinctiveness`, `Z-03`, `O-NM1`, `P-06`, `A-5X`, `L-AQ`.

## Pipeline at a glance

```
MediaPipe landmarks (468)
  ↓ FaceMetrics / LateralFaceMetrics
17 frontal + 8 lateral raw
  ↓ reference (ethnicity × gender) 대비 z-score
  ↓ age adjustment (50+)
  ↓ scoreTree(z)
14 NodeScore (own + rollUp stats)
  ↓ 5-stage derivation
  │   1. base linear (per node weight)
  │   1b. distinctiveness (abs-z 보정)
  │   2. zone rules  Z-##   (삼정 조화/불균형)
  │   3. organ rules O-##   (오관 쌍)
  │   4. palace rules P-##  (십이궁 overlay)
  │   5. age A-## + lateral L-## + gender delta
10 raw attribute
  ↓ normalizeAllScores (성별 quantile → rank 60% + globalPct 40% → 5.0~10.0)
10 normalized attribute
  ↓ classifyArchetype (top-2 기반)
ArchetypeResult
  ↓ report_assembler  (intro / closing wrapper)
  ↓ life_question_narrative (Beat-Fragment 엔진 · face-hash seed)
본문 텍스트 — 7 인생 질문 섹션 (재능/건강/재물/대인/연애/관능도*/조언)
```

\* 관능도 ≥ 30대. 바람기는 독립 섹션이 아니라 연애운 Shadow 의 1-line 특성(libido 고 & stability 비고 조건)으로 통합됨. 서술 엔진 상세: `docs/runtime/NARRATIVE.md`.

## 3/4 측면 측정·스코어링

측면 캡처는 정면과 **완전히 분리된 두 번째 이미지**. yaw ∈ [0.70, 0.88] (약 45~60° 회전) 구간에서만 수락 — dorsal convexity 같은 sagittal-plane signal 이 2D 에 신뢰성 있게 투영되는 구간. `classifyYaw()` 가 `YawClass.threeQuarter` 반환해야 녹색 overlay + 캡처 버튼 활성.

### 8 연속 lateral metric (`face_metrics_lateral.dart::computeAll()`)

| id | 한국어 | 의미 | 참고 mean |
|---|---|---|---|
| `nasofrontalAngle` | 비전두각 | 168(nasion) 각도, 이마-코 꺾임 | M 131° / F 141° |
| `nasolabialAngle` | 비순각(프록시) | 94(subnasale) 각도, 94→0 ref — tip rotation | 130~140° (클리니컬 NLA 아님) |
| `facialConvexity` | 안면 돌출각 | 180° − ∠10-94-152. 양수=볼록 프로파일 | ~7.7° |
| `upperLipEline` | 상순 E-line | 0 → (1-152) E-line 수직거리 / faceHeight | ~−1mm 근방 |
| `lowerLipEline` | 하순 E-line | 17 → (1-152) E-line 수직거리 | 동일 규약 |
| `mentolabialAngle` | 순이각 | 17(lowerLipBottom) 각도, 14·152 ray | 동아시아 ~134° |
| `noseTipProjection` | 코끝 돌출 | dist(168, 1) / faceHeight — Goode 유사 |  |
| `dorsalConvexity` | 코 등선 | 195 의 168→1 line 수직거리 abs / faceHeight |  |

reference mean/sd: `face_reference_data.dart::lateralMetricInfoList`. 6 ethnicity × 2 gender fallback 동일.

### 5 lateral flag (정면+측면 z 기반, `face_analysis.dart`)

z-score (정수 `metricScore`) 임계로 산출 — 절대 mm 임계는 mesh noise·projection geometry 로 불안정해 사용하지 않음.

| flag | 조건 | 의미 |
|---|---|---|
| `aquilineNose` | `dorsalConvexity` z ≥ 3 | 매부리코 |
| `snubNose` | `nasolabialAngle` z ≥ 2 **and** raw ≥ 115° | 들창코 |
| `droopingTip` | `nasolabialAngle` z ≤ −2 **and** raw ≤ 112° | 처진 코끝 |
| `saddleNose` | `dorsalConvexity` z ≤ −3 | 안장코 |
| `flatNose` | `noseTipProjection` z ≤ −3 | 납작코 |

### Lateral rule (Stage 5, `attribute_derivation.dart::_lateralFlagRules`)

| rule | 트리거 | attribute delta |
|---|---|---|
| `L-AQ` | `aquilineNose == true` | leadership +1.5, wealth +0.5, stability −0.3 |
| `L-SN` | `snubNose == true` | sociability +1.0, attractiveness +0.5 |
| `L-EL` | mouth.ownZ 의 `upperLipEline` ≥ 1 **and** `lowerLipEline` ≥ 1 | sensuality +0.5, libido +0.5 |

L-AQ/L-SN 은 binary flag 만 소비, L-EL 은 mouth 노드의 직계 lateral z 를 직접 탐색. 측면 없으면 `hasLateral == false` 로 전 stage skip (delta 0, 정면 파이프라인만 돈다).

### dark metric 경보

`dorsalConvexity` 의 z ∈ [1, 3) "살짝 매부리" 는 현재 연속 rule 없음 — aquiline flag 임계(z≥3) 이상에서만 해석 발동. `nasofrontalAngle` 도 직접 rule 희소 → 산근(질액궁) 해석 여지 남음. 추후 연속 대역 rule 도입 시 이 둘이 1순위.

---

## Frame Processing (카메라 모드)

```
CameraController.startImageStream()
  → 플랫폼 분기
    Android: NV21 (yPlane + vuPlane split) → processNv21()
    iOS:     BGRA → process()
  → FaceMeshResult (468 landmarks, triangles, score)
  → 추적 품질 체크 → overlay 색 (Red/Green)
  → CustomPainter 오버레이
```

### Key Design Decisions (까먹지 말 것)

- **Android NV21**: camera 가 `planes[0]` 에 단일 버퍼로 delivery → Y (width×height bytes) 와 VU (나머지) 로 분리해야 `FaceMeshNv21Image` 로 넘길 수 있음
- **Portrait aspect**: `controller.value.previewSize` 는 센서 orientation(landscape) → portrait 에선 width/height swap
- **Overlay 정렬**: camera preview + mesh overlay 를 같은 `SizedBox` in `FittedBox(fit: BoxFit.cover)` 에 배치 → 좌표 자동 매치
- **Frame throttling**: `_isProcessing` flag 로 이전 frame 처리 중이면 skip
- **ROI tracking**: `enableRoiTracking: true` — 별도 face detector 불필요
- **Ratios over absolute**: normalized landmarks (0~1) → 비율이 scale-invariant

### Overlay 색 기준

- **Red** (기본): 평범 tracking
- **Green**: accurate tracking — 4가지 동시 만족
  1. confidence ≥ 0.85
  2. 프레임 간 안정성 (landmark 평균 이동 < 0.005)
  3. face width > 프레임 25%
  4. yaw class 가 현재 캡처 단계와 일치 (frontal → `YawClass.frontal`, lateral → `YawClass.threeQuarter`)

## Album Analysis Flow (`home_screen.dart::_openAlbum`)

```
1. 스낵바 "정면 사진을 올려주세요" → pickImage (single)
2. MediaPipe 추론 → AlbumPreviewPage(phase=frontal) 모달
   - "정면 분석" 버튼 → pop(true)
3. 스낵바 "측면(3/4) 사진을 올려주세요" → pickImage (single)
4. MediaPipe 추론 → AlbumPreviewPage(phase=lateral) 모달
   - "측면 분석" 버튼 → pop(true) → _runAnalysis()
5. analyzeFaceReading() — 17 frontal + 8 lateral + rich evidence 전부 채움
6. Thumbnail 생성 (flutter_image_compress, 128px WebP) → Documents/{uuid}.webp
7. historyProvider.add(report) → Hive 저장 (thumbnailPath 포함)
8. 히스토리 탭 전환 → SupabaseService().saveMetrics(report) 비동기
```

- Demographics (gender / ageGroup / ethnicity) 는 Hive `prefs` box 에 persist
- 셋 중 하나라도 미선택이면 홈 화면의 카메라/앨범 버튼 비활성
- 리포트 Hive box 는 schema 변경 시 drop-recreate — `fromJsonString` 실패 시 history_provider 가 `_box.clear()` 호출

## Gender-Specific Analysis

현 파이프라인에서 성별이 분기되는 지점:

1. **Weight matrix delta** (`attribute_derivation.dart::_genderDelta`): attribute별 base 노드 가중치가 남/여 다르게 (예: attractiveness 의 nose 남 +0.05 / 여 −0.05). Row 합은 1.00 유지.
2. **Quantile normalize** (`attribute_normalize.dart`): 성별별 21-point quantile 테이블로 raw → 5~10 변환. 남/여 attribute 분포 차이(특히 sensuality/libido)를 흡수.
3. **Archetype intro** (`report_assembler.dart`): archetype 소개 문구가 `report.gender` 로 분기.
4. **Age adjustment** (`age_adjustment.dart`): 50+ 보정이 성별마다 다른 값.

## 테스트 · 빌드

```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter test                         # 현 baseline 73 pass
flutter run                          # 실기 (카메라는 simulator 불가)
```

### Monte Carlo 재보정 (weight matrix / rule / reference 건드린 뒤)

```bash
flutter test test/calibration_test.dart
```

출력된 21-point map 을 `attribute_normalize.dart` 의 `_attrQuantilesMale` / `_attrQuantilesFemale` 에 붙여 넣고, 하위 테스트 green 확인:

- `archetype_fairness_test.dart` — archetype 분포 공정성
- `archetype_template_sanity_test.dart` — 6 template 별 ≥55% hit
- `score_distribution_test.dart` — spread ≥ 3.0, saturation < 5%

## Platform Setup

- **Android**: `CAMERA` permission in `AndroidManifest.xml`
- **iOS**: `NSCameraUsageDescription` in `Info.plist`
- 실기기 필수 (simulator/emulator 는 camera 불가)
