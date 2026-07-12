# 문서 경량화 (react 제외) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** react 를 제외한 전 문서를 "현재 로직의 핵심"만 남기고 약 3,100줄 → 약 1,000줄로 감축.

**Architecture:** 파일 1개 = 태스크 1개. 각 태스크는 [읽기 → 삭제 기준 적용 rewrite → 코드 대조 검증 → 커밋] 사이클. 참조 표(metric·토큰·스키마)는 보존, 서사·이력·계획은 삭제.

**Tech Stack:** Markdown 편집만. 코드 무변경 (`flutter analyze` 7건·`flutter test` 151개 기준선 불변이 전역 검증).

## Global Constraints

- 삭제 3규칙: ① 구현됐는데 "예정/미구현" 표기 ② 바뀌어 안 맞는 내용 ③ 미구현 future 계획·로드맵
- 참조 표 보존: 26+8 metric 표, 14 node, 10 attribute, 디자인 토큰 표, DB 스키마 요약, API 계약
- CLAUDE.md 2종·react/* 은 건드리지 않는다
- 한자 단독 표기 금지, "레거시/마이그레이션" 금지어 (flutter/CLAUDE.md 준수)
- 각 태스크 커밋 message prefix: `docs:`

## Stale 판별 기준표 (2026-07-12 시점 사실 — 문서 내용이 이와 다르면 규칙 ② 적용)

- 제품 용어: 교감도 → **케미** (탭·문서·카피 전부). "발표/마감" 언어 폐기 → **"결과표 생성"**. 결과표는 **전원 등록 시에만** 생성 (조기 마감 ≥3 버튼 폐기)
- 구현 완료 (더 이상 "예정" 아님): 48h 자동 마감 cron·30일 teams 정리·90일 anon metrics 정리 (`react/workers/cron.ts`, Cloudflare Cron Triggers) / 로그인 rehydrate (metrics 전체 + **모집 중** 케미 방, closed 방 부활 금지) / nickname↔metrics.alias 파이프라인 (claim backfill·이름변경 전파·saveMetrics fallback) / 탈퇴 시 metrics FK cascade + open teams 삭제 / 대기 명단 원격 삭제 (pushTeam 유령 행 제거)
- 파일·폴더: `home_screen.dart` → `chemistry_screen.dart` (`ChemistryScreen`), `screens/home/` → `screens/chemistry/`
- UI 규칙: CTA = 흰 배경 + 1px textPrimary border (검정 invert 전면 폐기, 카카오 브랜드 버튼만 예외) / 내부 탭 = 내 관상 등록 시 3화면 모두 상시 노출, 관상 3탭 고정(카메라·앨범·**북마크**), 최초 노출 시 개수 많은 탭 기본 선택 / 공용 위젯: DetailAvatar(56 원형 ring)·SortSelector·EmotionEmptyState(84)·CoinChip·OtherFaceScanPill / 리스트 좌우 padding lg(16) 통일
- 인프라: R2 키 `thumbnails/{YYYYMM}/{uuid}.jpg` (일 단위 폐기) / og 배너 `cdn.facely.kr/assets/og.png` 800×420
- 미구현 계획 (규칙 ③ 삭제 대상): 웹 티저 데이터 재사용(React 카카오 로그인·DeepFace 웹 연동·capture 귀속)·매트릭스 batch 조회·슬롯 키 (team_id, slot_id) 전환·폴링 개선·신고/차단·시즌 템플릿·스토어 재제출 패키지·홈 "보관" 이동

---

### Task 1: flutter/README.md (62 → ~15줄)

**Files:** Modify: `flutter/README.md`

- [ ] 전체가 4단계 로드맵(출시차단/퍼널/운영/문서) — 규칙 ③으로 로드맵 전부 삭제
- [ ] 남길 것: 프로젝트 한 줄 소개 + 빌드/테스트 명령 (`flutter/CLAUDE.md` 의 빌드 절과 중복이면 포인터만)
- [ ] 검증: `wc -l flutter/README.md` ≤ 20
- [ ] 커밋: `docs: flutter README 로드맵 제거 — 빌드 안내만`

### Task 2: PRD.md (259 → ~60줄)

**Files:** Modify: `PRD.md`

- [ ] 삭제: §2.2 출시 게이트 체크리스트, §4.1 웹 티저 재사용(미구현), 로드맵 §(🔴🟠🟡⚪ 전부), 완료 기준 체크박스류
- [ ] 유지·현행화: 제품 정의(관상/궁합/케미 3층), 코인 경제, §5.1 프라이버시·데이터 수명주기(현행 사실), §5.3 아키텍처 요약도
- [ ] Stale 기준표 대조 (발표→결과표, 조기 마감 폐기 반영)
- [ ] 검증: `grep -c "\- \[ \]" PRD.md` = 0, `wc -l` ≤ 80
- [ ] 커밋: `docs: PRD 로드맵·미구현 계획 제거 — 현행 제품 스펙만`

### Task 3: flutter/docs/HOW-IT-WORKS.md (615 → ~250줄)

**Files:** Modify: `flutter/docs/HOW-IT-WORKS.md`

- [ ] 보존: 26+8 metric 표, 14-node tree, 10 attribute, 5-stage pipeline 요약, normalize 21-point, 궁합 5 frame, face shape classifier 요약
- [ ] 삭제: 설계 배경 서사, 과거 비교, Monte Carlo 절차의 중복 설명(표만), 예시 과잉
- [ ] 검증: 표 개수 before/after 동일 (`grep -c "^|"` 로 표 행 수 비교, 감소 시 사유 명시), `wc -l` ≤ 280
- [ ] 커밋: `docs: HOW-IT-WORKS 서사 제거 — 표·계약 중심 경량화`

### Task 4: flutter/docs/ARCHITECTURE.md (533 → ~200줄)

**Files:** Modify: `flutter/docs/ARCHITECTURE.md`

- [ ] Stale 현행화: 탭 순서(관상0/궁합1/케미2/설정3), ChemistryScreen 명칭, screens/chemistry 경로, rehydrate "구현됨" 사실화, cron 3종 사실화
- [ ] 보존: 패키지 구조도, 4-tab IndexedStack, Riverpod 패턴 목록, 데이터 흐름도, 외부 인프라 표, 빌드 명령
- [ ] 삭제: 화면별 상세 서사, 결정 배경 스토리
- [ ] 검증: `grep -n "HomeScreen\|screens/home\|교감도" flutter/docs/ARCHITECTURE.md` = 0건, `wc -l` ≤ 220
- [ ] 커밋: `docs: ARCHITECTURE 현행화 + 경량화`

### Task 5: flutter/docs/DESIGN.md (419 → ~200줄)

**Files:** Modify: `flutter/docs/DESIGN.md`

- [ ] 보존: §0.0 통일성 절대 규칙, AppText/AppColors/AppSpacing/AppRadius 토큰 표, 컴포넌트 레시피(§3.x 위젯별 스펙 표), §2.5 공용 승격 규칙
- [ ] 삭제: 마이그레이션 가이드, 변경 이력 서사("~였는데 ~로 바꿈"), 사용처 나열의 과잉 (위젯 파일이 SSOT)
- [ ] 신규 공용 위젯 반영: DetailAvatar·SortSelector 레시피 1줄씩
- [ ] 검증: 토큰 표 무손실 (`grep -c "^|"` 비교), `wc -l` ≤ 220
- [ ] 커밋: `docs: DESIGN 토큰·레시피만 — 이력·가이드 제거`

### Task 6: python/README.md (322 → ~80줄)

**Files:** Modify: `python/README.md`

- [ ] 보존: /analyze API 계약(요청/응답/인증 토큰), 실행·배포 명령, 환경변수 표
- [ ] 삭제: DeepFace 배경 설명, 실험/튜닝 이력, future 계획(웹 CORS 연동 등)
- [ ] 검증: `wc -l` ≤ 100
- [ ] 커밋: `docs: python README API 계약 중심 경량화`

### Task 7: tools/face_shape_ml/README.md (474 → ~100줄) + RECALIBRATION-metrics-spec.md (75 → ~40줄)

**Files:** Modify: `tools/face_shape_ml/README.md`, `tools/face_shape_ml/RECALIBRATION-metrics-spec.md`

- [ ] README 보존: 재학습 절차(데이터→학습→TFLite 배포 명령 순서), 현재 모델 스펙
- [ ] README 삭제: 실험 이력·비교 표·폐기된 접근
- [ ] RECALIBRATION: 현행 재보정 절차만
- [ ] 검증: README `wc -l` ≤ 120, spec ≤ 50
- [ ] 커밋: `docs: face_shape_ml 절차 중심 경량화`

### Task 8: KAKAO.md (152 → ~50줄) + shared/README.md (55 → ~30줄)

**Files:** Modify: `KAKAO.md`, `shared/README.md`

- [ ] KAKAO 보존: 현재 연동 계약(로그인·FeedTemplate·executionParams·딥링크 스킴), 개발자 콘솔 설정 요점
- [ ] KAKAO 삭제: 실사용 마찰 목록(§5 → README 로드맵과 함께 폐기), 검토했다 버린 대안
- [ ] shared/README: 패키지 목적 + export 3개(runEngine/runCompat/runMetrics) + 빌드 명령만
- [ ] 검증: KAKAO ≤ 60, shared ≤ 35
- [ ] 커밋: `docs: KAKAO·shared README 경량화`

### Task 9: 전체 검증 + 마무리

- [ ] `find . -name "*.md" -not -path "./react/*" -not -path "*/.venv/*" -not -path "*/node_modules/*" | xargs wc -l` — 합계 ≈1,000±200 확인, 스펙 표와 대조해 보고
- [ ] flutter/CLAUDE.md 의 SSOT 포인터 문단이 깨진 참조 없는지 확인 (파일명 불변이라 무영향 예상)
- [ ] `cd flutter && flutter analyze`(7건)·`flutter test`(151) 기준선 확인
- [ ] 커밋 잔여분 정리 + push
