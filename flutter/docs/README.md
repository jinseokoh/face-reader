# Documentation Index

**마지막 업데이트**: 2026-04-18

Face Reader 관상 앱의 전체 문서 인덱스. 모든 기술 문서는 이 디렉토리(`docs/`)에 통합 관리한다.

---

## Architecture

| 문서 | 목적 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 상위 설계: 3 Track 구조 (얼굴형 MLP / 관상 트리 엔진 / 측면 관상), 모듈 경계, 데이터 흐름 |
| [PROJECT_SETUP.md](PROJECT_SETUP.md) | Flutter 프로젝트 구조 패턴 (Riverpod, Repository, DataSource, DI) |

## Attribute Engine

| 문서 | 목적 |
|---|---|
| [ATTRIBUTE_NODE_MAPPING.md](ATTRIBUTE_NODE_MAPPING.md) | 14-node x 10-attribute weight matrix, 5-stage derivation pipeline (zone/organ/palace rules) |
| [NORMALIZATION.md](NORMALIZATION.md) | raw attribute score → 5.0~10.0 정규화 (60% rank + 40% global quantile blend, Monte Carlo 20,000 샘플) |

## Taxonomy

| 문서 | 목적 |
|---|---|
| [PHYSIOGNOMY_TAXONOMY.md](PHYSIOGNOMY_TAXONOMY.md) | 14-node 관상 트리 SSOT + 노드별 metric/rule 매칭: 삼정(三停) + 오관/오악/사독/십이궁 메타데이터 오버레이 |

## Compatibility

| 문서 | 목적 |
|---|---|
| [COMPATIBILITY.md](COMPATIBILITY.md) | 궁합 엔진 구조: attribute harmony, archetype matrix, special interaction, 개선 방향 |

## Analysis Pipeline

| 문서 | 목적 |
|---|---|
| [ANALYSIS.md](ANALYSIS.md) | 분석 파이프라인 출력 예시: metric 샘플, FaceReadingReport 스키마, Supabase 저장 형태 |
| [BUSINESS.md](BUSINESS.md) | 비즈니스 로직: metric 선정 근거, 10 attribute 도출 구조, archetype 분류 |

## Supabase

| 문서 | 목적 |
|---|---|
| [SUPABASE_PLAN.md](SUPABASE_PLAN.md) | Supabase 연동 계획: Phase 1 (Flutter + metrics 테이블) ~ Phase 3 (카카오 로그인 + 유료 기능) |
| [SUPABASE_SQL.md](SUPABASE_SQL.md) | SQL 스키마: metrics 테이블, RLS 정책, pg_cron 만료 정리, Phase 3 users 테이블 |

---

## 코드 내 문서 (docs/ 밖)

| 파일 | 위치 | 목적 |
|---|---|---|
| `CLAUDE.md` | `flutter/CLAUDE.md` | Claude Code 지시서: 파일 구조, 파이프라인, metric 공식, reference data |
| `README.md` | `flutter/README.md` | Flutter 표준 README |
