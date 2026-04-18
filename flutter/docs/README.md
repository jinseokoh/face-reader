# Documentation Index

**마지막 업데이트**: 2026-04-18

Face Reader 관상 앱의 전체 문서 인덱스. **큰 그림 → 엔진 내부 → 실행 결과 → 외부 인프라** 순으로 계층화.

```
docs/
├── architecture/   ① 시스템 큰 그림
├── engine/         ② 관상 스코어링 엔진 (프로젝트의 핵심 IP)
├── runtime/        ③ 실행 시점 산출물
└── supabase/       ④ 외부 인프라
```

---

## ① architecture — 시스템 큰 그림

앱이 전체적으로 어떻게 조립되는가. **engine 을 감싸는 상위 컨텍스트**.

| 문서 | 내용 |
|---|---|
| [architecture/OVERVIEW.md](architecture/OVERVIEW.md) | 3 Track 구조 (얼굴형 MLP / 관상 트리 엔진 / 측면 관상), 모듈 경계, 데이터 흐름 |
| [architecture/PROJECT_SETUP.md](architecture/PROJECT_SETUP.md) | Flutter 프로젝트 구조 패턴 (Riverpod, Repository, DataSource, DI) |

## ② engine — 관상 스코어링 엔진

**프로젝트의 핵심 IP**. 파이프라인 순서(landmark → tree → attribute → normalize → compat) 그대로 배치.

| 문서 | 파이프라인 위치 |
|---|---|
| [engine/TAXONOMY.md](engine/TAXONOMY.md) | **1. 14-node tree SSOT** + 노드별 전통 의미·metric/rule 매칭. 삼정(三停) + 오관/오악/사독/십이궁 오버레이 |
| [engine/ATTRIBUTES.md](engine/ATTRIBUTES.md) | **2. 10-attribute weight matrix** + 5-stage derivation pipeline (base · distinctiveness · zone · organ · palace · age/lateral) |
| [engine/NORMALIZATION.md](engine/NORMALIZATION.md) | **3. raw → 5.0~10.0 정규화** (60% within-face rank + 40% global quantile, Monte Carlo 20,000 샘플) |
| [engine/COMPATIBILITY.md](engine/COMPATIBILITY.md) | **4. 궁합 엔진** — attribute harmony · archetype matrix · special interaction |
| [engine/RATIONALE.md](engine/RATIONALE.md) | **설계 근거** — metric 선정, 10 attribute 도출, archetype 분류의 research/관상 전통 뿌리 |

## ③ runtime — 실행 산출물

엔진이 실제로 돌았을 때 어떤 출력이 나오는가. **reference / 샘플** 성격.

| 문서 | 내용 |
|---|---|
| [runtime/OUTPUT_SAMPLES.md](runtime/OUTPUT_SAMPLES.md) | 분석 파이프라인 출력 예시: metric 샘플, FaceReadingReport 스키마, Supabase 저장 형태 |
| [runtime/NARRATIVE.md](runtime/NARRATIVE.md) | 인생 질문 서술 엔진 v2 — Beat-Fragment Grammar + Face Hash Seed · 8 섹션 구조 · 연령 게이팅 · 슬롯 풀 |
| [runtime/NARRATIVE_GENDER_REDESIGN.md](runtime/NARRATIVE_GENDER_REDESIGN.md) | **📋 작업 대기** — 서술 엔진 성별 분기 전면 재설계 계획 (Phase 1 버그픽스 · Phase 2 슬롯 확장 · Phase 3 연애/바람기/색기 pool 분리) |
| [runtime/NODE_EXPANDABLE_UI.md](runtime/NODE_EXPANDABLE_UI.md) | **📋 작업 대기** — 14-node 부위별 expandable UI 계획 (정적 NodeTextBlock SSOT + `_ExpandableNodeBar` 위젯 + band/gender 분기) |

## ④ supabase — 외부 인프라

metric 원격 저장 + 향후 로그인/유료화.

| 문서 | 내용 |
|---|---|
| [supabase/PLAN.md](supabase/PLAN.md) | 연동 계획: Phase 1 (Flutter + metrics 테이블) ~ Phase 3 (카카오 로그인 + 유료 기능) |
| [supabase/SQL.md](supabase/SQL.md) | SQL 스키마: metrics 테이블, RLS 정책, pg_cron 만료 정리, Phase 3 users 테이블 |

---

## 읽기 루트 가이드

- **처음 오면**: `architecture/OVERVIEW.md` → `engine/TAXONOMY.md` → `engine/ATTRIBUTES.md`
- **수치·보정 건드리면**: `engine/NORMALIZATION.md` → `../CLAUDE.md` 의 Monte Carlo 재보정 섹션
- **궁합 로직 건드리면**: `engine/COMPATIBILITY.md`
- **파이프라인 output 포맷 궁금**: `runtime/OUTPUT_SAMPLES.md`
- **리포트 본문 서술 엔진 수정**: `runtime/NARRATIVE.md`
- **전통 관상 근거·metric 선정 이유 궁금**: `engine/RATIONALE.md`

---

## 코드 내 문서 (docs/ 밖)

| 파일 | 목적 |
|---|---|
| `flutter/CLAUDE.md` | Claude Code 오리엔테이션: 문서 규칙, 파일 구조, 파이프라인 스냅샷, 측면 측정 |
| `flutter/README.md` | Flutter 표준 README |
