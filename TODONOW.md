# TODONOW — 남은 일

> 이번 세션 완료분(metrics 슬림화 · 궁합 유료-소유 · expiry 폐기 · DTO 키 camelCase 통일 ·
> unlocks.body · RLS claim 수정)은 git history 참조. 아래는 **아직 안 된 것만**.

---

## A. 클라이언트 배포 (서버·DB·worker 는 이미 반영됨)

- [ ] **flutter 앱 재빌드/스토어 배포** — 만기 제거 · upload-on-share · 받은카드 궁합 CTA ·
      thumbnail gender fallback · unlocks.body 복원 등 Dart 변경 반영
- [ ] **refine admin 재빌드/배포** — demographics body 파싱 · "90일+ 미활동 정리" 버튼 ·
      email 컬럼 · nickname 링크 · 사용자 라벨

---

## B. 멀티디바이스 (로그인 기반 — anon-auth 불필요) — ✅ 핵심 완료

> 멀티디바이스 = email/password 로그인. unlocks(+unlocks.body 상대 스냅샷)는 user_id 로
> 가져와지고, 본인 얼굴은 로그인 시 rehydrate 로 복원. anon-auth 불필요.

- [x] **로그인 시 본인 관상 server 복원** (rehydrate): `metrics where user_id=나` →
      로컬 Hive 복원 (`historyRehydrateProvider`). 커밋 `232d5a9`.
- [x] **unlock 시점 본인 카드 업로드 보장**: isMyFace 카드는 궁합 진입 시 항상 upsert. 커밋 `940da56`.
- [ ] (검증) device B 실기에서 로그인 → myFace 복원 + unlocks.body 상대 → 궁합 렌더 e2e 확인
- [ ] 받은 북마크(미결제 received) server 테이블화 — 필요 시 (낮은 우선순위)

---

## C. 향후 — 채팅 / 본인 인증

- [ ] 원격 채팅 (양쪽 본인 얼굴 = 실 유저일 때만)
- [ ] **liveness 본인 인증** — isMyFace 는 현재 self-asserted. 채팅 출시 전 catfishing 방지용 검증 필요

---

## 참고 (옵션, 급하지 않음)

- refine dashboard 의 source/gender 집계 — 이번에 제거함. body 파싱 기반으로 살릴지 미정
- R2 thumbnail orphan 정리 — "90일+ 삭제" 버튼은 DB row 만 지움. R2 객체 정리는 별도(추후)
