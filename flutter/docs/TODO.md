# TODO — 해야 할 일

**최종 업데이트**: 2026-05-23
**역할**: 우선순위가 살아있는 단일 작업 큐. 완료 항목은 §완료 이력 으로 내림. 새 작업은 우선순위 표 안에 추가.

---

## 우선순위 표

| 우선 | 작업 | 근거 | 재개 지시 |
|---|---|---|---|
| **P0** | **받은-카드 저장 + 앨범탭 section UI** (Phase A — 진행중) | 카톡 share link 수신자가 SSR 페이지에서 "앱에서 전체 결과 보기" 했을 때, 본문 + appbar `bookmark_add` 로 내 Hive 에 저장. history 앨범탭 안에 "받은 카드" section 노출. 미래 궁합 picker 에서 selectable. RLS·Supabase metrics row 는 손대지 않음 (B방안 = reference only). 본문은 저장 시점에 Supabase fetch 후 Hive 영구 박음 (만료 후에도 view). 결정 사항: AnalysisSource enum 에 `received` 추가 (별도 origin flag 안 쓰고 한 enum 으로). default alias 는 null → display fallback "카톡으로 전달받은 카드". 사용자가 기존 alias dialog 로 자유 rename. | `1) shared/lib/domain/models/face_reading_report.dart: AnalysisSource enum 에 received 추가 + FaceReadingReport.receivedAt(DateTime?) 추가 + toJsonString/fromJsonString 갱신. 2) flutter/lib/domain/services/share/share_receive_service.dart 신규 — Future<FaceReadingReport?> fetchByUuid(String uuid): Supabase metrics body 받아 fromJsonString → source=received override + receivedAt=now. 3) flutter/lib/presentation/screens/share/received_card_screen.dart 신규 — appbar bookmark 토글 (이미 저장이면 filled bookmark). 저장 시 historyProvider.add(report). 본문은 기존 report_page 의 solo card 위젯 재사용. 4) physiognomy_screen.dart _buildList 의 album tab: source ∈ {album, received} 두 그룹 split, "앨범사진" + "받은 카드" 두 section (count 0 hidden). 받은 카드엔 작은 chip "받음". _RecentListHeader source label 매핑 + alias fallback "카톡으로 전달받은 카드" wiring. 5) 임시 진입로 — 앨범탭 "받은 카드" section header 옆 paste IconButton: dialog 에 https://facely.kr/r/{uuid} 붙여넣기 → UUID 추출 → ShareReceiveService → ReceivedCardScreen push. Phase B 의 universal link 완성 시 자동 deep link 로 승격되고 이 진입로는 backup 으로 유지. 6) flutter analyze 0 issues 확인 후 commit per-step.` |
| **P0** | **AASA / assetlinks 실값 + iOS entitlements + Android intent-filter** (Phase B — Phase A 완료 후) | universal link / app link 가 정상이면 카톡 link 클릭 시 Worker SSR 페이지 거치지 않고 앱이 바로 열림. 현재는 `react/public/.well-known/` 두 파일 placeholder. iOS Runner.entitlements + AndroidManifest 양쪽 domain 박기. Phase A 의 paste UI 가 자동 deep link 로 승격됨. | `react/docs/HOW-IT-WORKS.md §4 + TO-DO.md P0 체크리스트 따라 TEAMID + Play SHA256 실값 박기. ios/Runner/Runner.entitlements 에 applinks:facely.kr, AndroidManifest 에 autoVerify intent-filter (https/facely.kr/r/) 추가. app_links 플러그인 의존성 확인 후 main.dart 에서 initialLink + uriLinkStream 구독 → ReceivedCardScreen 으로 라우팅. 검증: TestFlight·debug APK 에서 카톡 link 탭 → 앱 자동 열림 + ReceivedCardScreen 도착.` |
| **P0** | **pull-to-refresh state 증발 root-cause 고정** | 진단 로그 삽입 완료. 실기 재현 후 stacktrace 확보 필요. `fromJsonString` 이 rawValue→엔진 재계산 중 어느 라인에서 터지는지 확정. | `실기 → 관상 tab pull-to-refresh → 콘솔 [History] reload FAIL entry N + stacktrace + raw head 수집. reloadFromHive 의 parse 실패 entry 가 state 에서 소멸하지 않도록 보수적 업데이트 (Hive raw 보존은 OK)` |
| **P0** | **실사용자 N 확장** (현 N=14 eastAsian female 30s → ≥100 전 demographic) | engine v2.8 은 단일 demographic 14 명으로 ref 재보정. 남·타 ethnicity·age 는 idealized MC 기반. | `test/fixtures/real_users_*.json 에 male/caucasian/40s 등 추가 수집 후 real_users_recalibration_test.dart 로 per-demographic 재보정` |
| **P1** | **face_shape East Asian 데이터 확장 200+** | 현 user 57 sample 로 5-fold CV 47.6% 천장. 클래스당 40-50장 확보 시 55-65%, 100-200장 시 65-75% 도달 가능. | `사용자가 East Asian 라벨된 사진을 /tmp/{gender}-{type}-{n}.{ext} 또는 tools/face_shape_ml/labeled_samples/ 에 추가 → tools/face_shape_ml/README.md §4 procedure 따라 재학습 + TFLite 자동 배포` |
| P2 | **Instagram Story 공유 추가** (카카오 P0 이후 보류) | AppBar 에 `FA.squareInstagram` 두 번째 버튼 추가. `social_share.shareInstagramStory(image, attributionURL)` 직딜. iOS Info.plist 의 LSApplicationQueriesSchemes 에 `instagram-stories` 추가. | `카카오 P0 끝난 후 ios/Runner/Info.plist scheme 추가 + share_publisher 에 publishToInstagramStory 메소드 추가 + AppBar 두 번째 IconButton wire. social_share 패키지 의존성 점검.` |
| P2 | **궁합 narrative 6 섹션 phrase pool 채우기** | `compat_phrase_pool.dart` 에 elementRelationPhrases · palaceRulePhrases · organPairPhrases · zonePatternPhrases · yinYangPhrases · intimacyPhrases · labelOverviewPhrases · longTermAdvicePhrases. 각 1~5 variant. | 코드 SSOT 와 HOW-IT-WORKS.md §7 따라 점진 채우기 |
| P2 | **DEV ONLY — Hive box 자동 reset hook** | 개발 중 schema mismatch 시 수동 `Hive.box(history).clear()`. dev-mode 자동 reset hook 도입 검토. | `core/hive/hive_setup.dart 의 dev guard 분기` |

---

## 향후 로드맵 (대형 작업)

### Roadmap-A · face shape classifier 강화 (장기)

- **단기**: P1 의 East Asian 200+ 데이터 확장 → 47% → 65-75%
- **중기**: 28 feature 보강 (temple-cheekbone ratio, jawline gradient 등) → 5-10pt 추가
- **장기**: server-side CNN (DeepFace endpoint 에 face_shape action 추가) — 데이터 1000+ 도달 후. on-device 는 fallback.

### Roadmap-B · 궁합 엔진 v1 완성

P2~P7 phase 가 HOW-IT-WORKS.md §7 + 기존 compat/ 코드 안에서 SSOT. 남은 phase:
- P2 element_classifier (P1 위 우선순위표)
- P3 palace_state + palace_pair_matcher + ~40 PalacePair rule
- P4 organ_pair_rules + zone_harmony + yinyang_matcher + intimacy
- P5 compat_pipeline + compat_aggregator + compat_calibration (MC label fairness 10/30/30/30 ±5%)
- P6 compat_narrative + compat_phrase_pool
- P7 UI — `compatibility_report_page.dart` rewrite

### Roadmap-C · Phase 3 유료화

`docs.bak/supabase/PLAN.md` 의 Phase 3 — 카카오 로그인 + `users` 테이블 + 인앱 결제. 현재 metrics 테이블만 운영 중. coin RPC (`spend_coins`, `unlock_compat`) 은 react/db migration 에 이미 정의됨.

### Roadmap-D · narrative engine 확장

- 8 섹션 fallback variant 1→5 확장 완료. 남은 영역: 종합 조언 stage 가 연령대별 더 풍성하게.
- 색기·관능도 섹션 슬롯 풀 추가 확장 (현 8 archetype × 남/여).

---

## 완료 이력

| 날짜 | 작업 | 결과 |
|---|---|---|
| 2026-05-22 | 궁합 detail UI 통일 + intimacy chapter 분량 복구 | (1) 섹션 순서 — 한줄요약→핵심3가지→갈등→전략→이성적 끌림의 결→점수와 이유. (2) flirty/spicy 도 4 axis 산문체 출력 — pure 와 동등 분량. 톤 분기는 opener/closer 어휘만. 이전 인스타 카피 분량으로 줄였던 결정 폐기. (3) Scaffold 배경 Colors.white 로 관상 detail 과 통일. (4) _NarrativeCard 의 magic number 를 AppSpacing/AppRadius 토큰으로 정렬. |
| 2026-05-22 | 카카오 공유 — share_publisher.publishSoloViaKakao / publishCompatViaKakao | KakaoLink Feed template. report_page · compatibility_detail_screen 의 `_shareViaKakao` 두 곳 → SharePublisher 호출. R2 thumbnailKey 가 metadata 로부터 FaceReadingReport 에 자동 채워짐 (demographic_confirm_screen). Worker SSR 의 og:image = `cdn.facely.kr/{thumbnailKey}` 로 박힘. R2 path prefix 는 `thumbnails/YYYYMM` → `thumbnails/YYYYMMDD` 로 분산. Cloudflare Worker (`facely.kr`) 배포 완료 — version `a131d3e6-e382-40c8-9a22-34de21f974b6`. |
| 2026-05-21 | Material/Cupertino Icons 완전 제거 → FontAwesome 통일 | 14 파일 50+ 아이콘 전부 FA migration. DESIGN.md §1.5 에 "icon 은 오직 FontAwesome" 컨벤션 박음. font_awesome_flutter 가 단일 icon source. 0 analyze new issue. |
| 2026-05-21 | metrics.metrics_json → metrics.body rename + RLS PII check 완화 | column rename (codebase 일괄). RLS `metrics_insert_anon` 의 alias/username/birthday 검사를 "key 존재" 에서 "value 존재" 로 완화 (null 값은 PII 아님). landmarks 만 key 존재 자체로 차단 유지. baseline.sql 에 최신 SSOT 반영, 0002/0003 누적 폐기. |
| 2026-05-21 | 친밀 narrative gender 분기 강화 (flirty/spicy female) | 직전 작업의 flirty/spicy female pool 이 male 과 거의 동일 → "그 남자" 3인칭 시점 + 본인 자기관찰 톤으로 재작성. opener·closer 총 24 variants 다듬음. pure pool 은 이미 분기 OK 라 미변경. 145/145 green. |
| 2026-05-21 | 五行 element_classifier (TODO stale 정리) | 이미 `element_classifier.dart` + `element_distribution_test.dart` 존재. TODO P1 #6 항목 stale → 완료 이력으로 이동. |
| 2026-05-21 | intimacy gate 폐기 + 3-tone narrative (pure/flirty/spicy) | 모든 페어에서 intimacy score 항상 계산·노출. 동성/10대/70+ → pure(현재), 20대·60대 → flirty(릴스 톤), 30~50 이성 양쪽 → spicy(들킴 분위기). label threshold 새 분포(90.5/81.5/61.5)로 재calibrate. |
| 2026-05-19 | face_shape 28-feat MLP East Asian 재학습 + TFLite 배포 | 47.4% → 75.4% (train) / 47.6% (5-fold CV). uniform prior 로 단순화. user case oblong→oval flip 확인. |
| 2026-05-18 | album path square-padding fix | 9:20 phone screenshot 의 MediaPipe distortion 차단. oval 오분류 해소. |
| 2026-05-17 | UX 정리 — illustration asset + popup modal 일관화 + 256 face-center thumbnail | home.png 사용. frontal/lateral popup 통일. 썸네일 R2 업로드. |
| 2026-04-21 | engine v2.9 美人相 rule 7개 도입 + 매력도 narrowing | 麻衣相法·神相全編 grounded. compat threshold 85/72/64 재보정. |
| 2026-04-20 | per-shape quantile (Opt-D) + narrative soft predicate + 음양 bar UI | shape-conditional bias 근본 제거. band cliff 제거. 부위별 상세 해석 섹션 추가. |
| 2026-04-19 | engine v2.7 dominant decorrelation + v2.8 실사용자 ref re-centering | 10 attribute 가 서로 다른 top node. N=14 empirical z N(0,1) 수렴. archetype cluster 편향 해소. |
| 2026-04-18 | engine v2.5 weight matrix 재설계 + Z-01/12 rule 축소 | shape-bound stab/trust 쏠림 해소. shape × attr concentration 29.8% → 25.4%. |
| 2026-04-18 | narrative v3 성별 분기 (연애·바람기·관능도 남/여 별도 pool) | 동일 fixture 남/여 본문 85%+ 상이. 색기 → 관능도 rename. |
| 2026-04-18 | 14-node expandable UI + node_text_blocks.dart SSOT | 42~66 block. 성별 분기 4 node (eye/nose/mouth/cheekbone). |
| 2026-04-17 | nasalHeightRatio 버그 수정 + mouthCornerAngle midLipX 버그 수정 | nasalHeightRatio = bridge(nasion→noseTip). mouthCornerAngle Pearson r=1.0 중복 해소. |

---

## 작업 추가 규칙

- **우선순위**: P0 (이번 주) → P1 (이번 달) → P2 (다음 분기 이후)
- **재개 지시**: 다른 사람(또는 다른 세션) 이 그 한 줄만 보고 작업 재개 가능하도록.
- **완료 시**: 우선순위 표에서 제거 → §완료 이력 에 한 줄 추가.
- **장기 로드맵**: §향후 로드맵 으로 분리. P2 보다 큰 단위.
