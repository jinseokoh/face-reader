# 문서 경량화 (react 제외) — 설계

2026-07-12 승인. 목표: 문서를 "현재 로직의 핵심"만 남기고 감축.

## 삭제 기준 (사용자 지정 3규칙)

1. 이미 구현됐는데 "구현 예정/미구현"이라 쓴 내용 — 제거
2. 코드·제품이 바뀌어 더 이상 맞지 않는 내용 — 제거
3. 아직 구현 안 된 future 계획/로드맵 — 제거

## 스코프 결정

- **포함**: flutter/docs 3종(HOW-IT-WORKS·ARCHITECTURE·DESIGN), PRD.md,
  flutter/README.md, python/README.md, tools/face_shape_ml/README.md,
  RECALIBRATION-metrics-spec.md, KAKAO.md, shared/README.md
- **제외**: react/* 전체, CLAUDE.md 2종(작업 규칙 파일 — 정보 문서 아님)
- **로드맵 문서(PRD·flutter/README)**: 계획이 본체지만 규칙 3에 따라 계획도 삭제.
  PRD 는 "현재 제품이 무엇인가" 스펙만 남김
- **참조 표는 예외**: metric·node·attribute·토큰·레시피·스키마 표는 보존.
  전체 분량은 1/3~1/5 수렴 허용 (엄격 1/10 아님)

## 파일별 방침·목표

| 파일 | 현재 | 방침 | 목표 |
|---|---|---|---|
| PRD.md | 259 | 로드맵·체크리스트·미구현 퍼널 삭제, 현행 스펙만 | ~60 |
| flutter/README.md | 62 | 빌드/시작 안내만 | ~15 |
| flutter/docs/HOW-IT-WORKS.md | 615 | 표 보존, 서사·설계 배경·이력 삭제 | ~250 |
| flutter/docs/ARCHITECTURE.md | 533 | 구조도·흐름·인프라 표 보존 + drift 현행화 | ~200 |
| flutter/docs/DESIGN.md | 419 | 토큰·레시피 표 보존, 마이그레이션 가이드 삭제 | ~200 |
| python/README.md | 322 | API 계약·실행법만 | ~80 |
| tools/face_shape_ml/README.md | 474 | 재학습 절차·명령만, 실험 이력 삭제 | ~100 |
| KAKAO.md | 152 | 현재 연동 계약만 | ~50 |
| tools/face_shape_ml/RECALIBRATION-metrics-spec.md | 75 | 소폭 정리 | ~40 |
| shared/README.md | 55 | 소폭 정리 | ~30 |

합계 약 3,100 → 약 1,000줄.

## 실행 방식

접근 A(직접 순차) — 세션이 보유한 최신 제품 결정(발표→결과표 언어 폐기,
rehydrate 구현, 48h/30일/90일 cron, 내부 탭 규칙, 공용 위젯 승격 등)을
근거로 stale 판별. 파일마다 코드 대조 후 rewrite.

## 검증

- 파일별: 남은 서술이 현재 코드와 일치하는지 코드 grep 대조
- 전체: `flutter analyze`·`flutter test` 무영향 (문서만 변경) 확인
- 줄수 집계 before/after 보고
