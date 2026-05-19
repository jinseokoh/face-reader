# TODO — 해야 할 일

**최종 업데이트**: 2026-05-19
**역할**: 우선순위가 살아있는 단일 작업 큐. 완료 항목은 §완료 이력 으로 내림. 새 작업은 우선순위 표 안에 추가.

---

## 우선순위 표

| 우선 | 작업 | 근거 | 재개 지시 |
|---|---|---|---|
| **P0** | **공유 link 통합 — share_publisher 구현** | 이미지/카톡 공유 두 entry → `share_plus` 단일 [공유] 버튼. R2 thumbnails/ 에 256 JPG PUT (Worker presign) + Supabase metrics 1-row UPSERT (anon, Worker 미경유) + `share_plus(https://facely.kr/r/{uuid})`. 궁합 공유 = 두 metrics 가 publish 된 상태에서 `/r/{A}~{B}` 발송 (추가 write 0). | `react/docs/HOW-IT-WORKS.md §3.2/§4.1/§5.2 그대로 lib/domain/services/share/share_publisher.dart 작성. publishSolo / publishCompat 두 함수. main.dart 에 app_links 패키지 초기화 + /r/:id 라우팅 (PAIR_SEP("~") split → 1 UUID → ReportPage, 2 → CompatReportPage)` |
| **P0** | **AASA / assetlinks 실값 + iOS entitlements + Android intent-filter** | `react/public/.well-known/` 두 파일 placeholder. iOS Runner.entitlements + AndroidManifest 양쪽 domain 박기. | `react/docs/HOW-IT-WORKS.md §4 + TO-DO.md P0 체크리스트 따라 TEAMID + Play SHA256 실값 박기. ios/Runner/Runner.entitlements 에 applinks:facely.kr, AndroidManifest 에 autoVerify intent-filter (https/facely.kr/r/) 추가` |
| **P0** | **pull-to-refresh state 증발 root-cause 고정** | 진단 로그 삽입 완료. 실기 재현 후 stacktrace 확보 필요. `fromJsonString` 이 rawValue→엔진 재계산 중 어느 라인에서 터지는지 확정. | `실기 → 관상 tab pull-to-refresh → 콘솔 [History] reload FAIL entry N + stacktrace + raw head 수집. reloadFromHive 의 parse 실패 entry 가 state 에서 소멸하지 않도록 보수적 업데이트 (Hive raw 보존은 OK)` |
| **P0** | **실사용자 N 확장** (현 N=14 eastAsian female 30s → ≥100 전 demographic) | engine v2.8 은 단일 demographic 14 명으로 ref 재보정. 남·타 ethnicity·age 는 idealized MC 기반. | `test/fixtures/real_users_*.json 에 male/caucasian/40s 등 추가 수집 후 real_users_recalibration_test.dart 로 per-demographic 재보정` |
| **P1** | **face_shape East Asian 데이터 확장 200+** | 현 user 57 sample 로 5-fold CV 47.6% 천장. 클래스당 40-50장 확보 시 55-65%, 100-200장 시 65-75% 도달 가능. | `사용자가 East Asian 라벨된 사진을 /tmp/{gender}-{type}-{n}.{ext} 또는 tools/face_shape_ml/labeled_samples/ 에 추가 → tools/face_shape_ml/README.md §4 procedure 따라 재학습 + TFLite 자동 배포` |
| **P1** | **궁합 엔진 P2 — 五行 body classifier 구현** | `lib/domain/services/compat/` 하위 신규 파일군. HOW-IT-WORKS.md §7 + 코드 SSOT 의 五形 score 공식. distribution test 로 5 element 고르게 나오는지 검증. | `HOW-IT-WORKS.md §7 + 기존 compat/ 코드 읽고 element_classifier.dart + test/compat/element_distribution_test.dart 작성` |
| **P1** | **친밀 narrative gender 분기 컨텐츠** | `compat_phrase_pool.dart` 의 `intimacyAxisDetailsByGender` / `intimacyOpenerByBucketByGender` / `intimacyClosingByBucketByGender` 3 블록이 male/female 동일 복제 상태. male=적극·결단, female=수용·해석 톤으로 분기. | `compat_phrase_pool.dart 의 Gender.female 블록 3 곳을 수용·해석 톤으로 다듬기. 같은 fact 의 정반대 시점 (남=행동 지시 / 여=수용·해석 프레이밍)` |
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
