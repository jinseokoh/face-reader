# 웹 참여 위저드 UI 전면 개선 (2차) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.
> 스펙: docs/superpowers/specs/2026-07-12-web-join-ui-overhaul-design.md (문구 원문 SSOT)

**Goal:** 화면별 지적 5건을 스펙 문구 그대로 반영 — subtitle 3상태, entry 정비, already 가로 레이아웃, 정보 확인 3-select 폼, 카메라 영역 사전 확보, 로스터 빈 슬롯.

**Tech:** react/ 단독 (JoinWizard.tsx · g.$id.tsx · join.ts · app.css). 검증 = typecheck 신규 0 + build + deploy + prod chunk grep.

### Task 1: 데이터 계약 (join.ts)
- [ ] fetchRoster → 전 멤버 `{name, joined, thumbnailKey}` (joined 필터 제거, joined 플래그)

### Task 2: 헤더 3상태 (g.$id.tsx)
- [ ] `joinedInfo: {joined,total}|null` + `wizardActive` 로 3상태 subtitle, 카운트 `{total}명 중 {joined}명 등록`
- [ ] Invite 칩 정렬 등록✓ 우선

### Task 3: JoinWizard 단계별
- [ ] entry: 카피 교체, 카카오 버튼 광폭
- [ ] already: `등록 완료` + 아바타(56)+닉네임 | 우측 `관상 다시 촬영` 가로 행 + 나머지 n명 카피
- [ ] info: `정보 확인` + 인종/성별/나이대 3-select 폼 (defaults: eastAsian/male/20s), localStorage 에 ethnicity 포함, body.ethnicity 반영, 카메라 켜기 = line 버튼
- [ ] done: 로스터 빈 슬롯(점선 원) + 나머지 n명 카피
- [ ] onJoined 시그니처 {joined,total}

### Task 4: CSS
- [ ] .join-camera-wrap aspect-ratio 4/3 + video absolute cover (점핑 제거)
- [ ] .join-form (라벨+select 단일 컬럼 280), .join-me-row, .join-slot-empty(점선 원), 카카오 광폭

### Task 5: 검증·배포
- [ ] typecheck 신규 0 → build → deploy → prod chunk grep → commit/push
