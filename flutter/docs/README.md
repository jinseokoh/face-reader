# Documentation Index

**마지막 업데이트**: 2026-04-19 (engine v2.5)

Face Reader 관상 앱의 전체 문서 인덱스. **큰 그림 → 관상 엔진 → 궁합 엔진 → 실행 결과 → 외부 인프라** 순으로 계층화.

```
docs/
├── architecture/   ① 시스템 큰 그림
├── engine/         ② 관상 스코어링 엔진 (프로젝트의 핵심 IP)
├── compat/         ③ 궁합 엔진 (전통 관상학 기반, 관상 엔진과 동등한 별도 엔진)
├── runtime/        ④ 실행 시점 산출물
└── supabase/       ⑤ 외부 인프라
```

---

## ① architecture — 시스템 큰 그림

앱이 전체적으로 어떻게 조립되는가. **engine 을 감싸는 상위 컨텍스트**.

| 문서 | 내용 |
|---|---|
| [architecture/OVERVIEW.md](architecture/OVERVIEW.md) | 3 Track 구조 (얼굴형 MLP / 관상 트리 엔진 / 측면 관상), 모듈 경계, 데이터 흐름 |
| [architecture/PROJECT_SETUP.md](architecture/PROJECT_SETUP.md) | Flutter 프로젝트 구조 패턴 (Riverpod, Repository, DataSource, DI) |

## ② engine — 관상 스코어링 엔진

**프로젝트의 핵심 IP**. 파이프라인 순서(landmark → tree → attribute → normalize) 그대로 배치.

| 문서 | 파이프라인 위치 |
|---|---|
| [engine/TAXONOMY.md](engine/TAXONOMY.md) | **1. 14-node tree SSOT** + 노드별 전통 의미·metric/rule 매칭. 삼정(三停) + 오관/오악/사독/십이궁 오버레이 |
| [engine/ATTRIBUTES.md](engine/ATTRIBUTES.md) | **2. 10-attribute weight matrix** (9-node, face/ear 제외) + 5-stage pipeline (base · distinctiveness · zone · organ · palace · age/lateral). Stage 0 shape preset 은 v2.2 에서 철수. |
| [engine/NORMALIZATION.md](engine/NORMALIZATION.md) | **3. raw → 5.0~10.0 정규화** (40% within-face rank + 60% global quantile, 상관 Monte Carlo 20,000 샘플) |
| [engine/RATIONALE.md](engine/RATIONALE.md) | **설계 근거** — metric 선정, 10 attribute 도출, archetype 분류의 research/관상 전통 뿌리 |

## ③ compat — 궁합 엔진 (전통 관상학 기반)

관상 엔진과 **동등한 별도 엔진**. 五行·十二宮·五官·三停·陰陽 framework grounded. 麻衣相法·神相全編·柳莊相法·水鏡集 등 전통 문헌 근거.

| 문서 | 내용 |
|---|---|
| [compat/FRAMEWORK.md](compat/FRAMEWORK.md) | **SSOT** — 4-layer hybrid (五行 body classifier + 十二宮 state engine + 五官/三停/陰陽 pair matcher) · aggregator 공식 · 6-section narrative · 재보정 절차 |

## ④ runtime — 실행 산출물

엔진이 실제로 돌았을 때 어떤 출력이 나오는가. **reference / 샘플** 성격.

| 문서 | 내용 |
|---|---|
| [runtime/OUTPUT_SAMPLES.md](runtime/OUTPUT_SAMPLES.md) | 분석 파이프라인 출력 예시: metric 샘플, FaceReadingReport 스키마, Supabase 저장 형태 |
| [runtime/HIVE_SCHEMA.md](runtime/HIVE_SCHEMA.md) | **Hive 저장 스키마 SSOT** — 4 box 목록, v3 capture-only 원칙, JSON top-level key 전체, 17 frontal + 8 lateral metric ID 완전 목록, metric × attribute × rule 의존 그래프, 확장 체크리스트, Supabase mirror |
| [runtime/NARRATIVE.md](runtime/NARRATIVE.md) | 인생 질문 서술 엔진 v3 — Beat-Fragment Grammar + Face Hash Seed · 8 섹션 구조 · 연령 게이팅 · 연애·바람기·관능도 남/여 분리 pool |
| [runtime/NARRATIVE_GENDER_REDESIGN.md](runtime/NARRATIVE_GENDER_REDESIGN.md) | ✅ **완료** — 서술 엔진 성별 분기 재설계 (2026-04-18). 연애·바람기·관능도 남/여 별도 pool, 섹션 400~600자, '색기'→'관능도' 통일 |
| [runtime/NODE_EXPANDABLE_UI.md](runtime/NODE_EXPANDABLE_UI.md) | ✅ **완료** — 14-node 부위별 expandable UI (2026-04-18). `node_text_blocks.dart` SSOT + `_ExpandableNodeBar` 위젯 + eye/nose/mouth/cheekbone 성별 분기 |

## ⑤ supabase — 외부 인프라

metric 원격 저장 + 향후 로그인/유료화.

| 문서 | 내용 |
|---|---|
| [supabase/PLAN.md](supabase/PLAN.md) | 연동 계획: Phase 1 (Flutter + metrics 테이블) ~ Phase 3 (카카오 로그인 + 유료 기능) |
| [supabase/SQL.md](supabase/SQL.md) | SQL 스키마: metrics 테이블, RLS 정책, pg_cron 만료 정리, Phase 3 users 테이블 |

---

## 읽기 루트 가이드

- **처음 오면**: `architecture/OVERVIEW.md` → `engine/TAXONOMY.md` → `engine/ATTRIBUTES.md`
- **수치·보정 건드리면**: `engine/NORMALIZATION.md` → `../CLAUDE.md` 의 Monte Carlo 재보정 섹션
- **궁합 로직 건드리면**: `compat/FRAMEWORK.md`
- **파이프라인 output 포맷 궁금**: `runtime/OUTPUT_SAMPLES.md`
- **Hive 에 뭐가 저장되는지 / 스키마 확장**: `runtime/HIVE_SCHEMA.md`
- **리포트 본문 서술 엔진 수정**: `runtime/NARRATIVE.md`
- **전통 관상 근거·metric 선정 이유 궁금**: `engine/RATIONALE.md`

---

## 코드 내 문서 (docs/ 밖)

| 파일 | 목적 |
|---|---|
| `flutter/CLAUDE.md` | Claude Code 오리엔테이션: 문서 규칙, 파일 구조, 파이프라인 스냅샷, 측면 측정 |
| `flutter/README.md` | Flutter 표준 README |
