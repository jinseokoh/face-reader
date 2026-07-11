# 관상은 과학이다

안면 계측 데이터 기반 인공지능 관상앱.

MediaPipe Face Mesh 468 landmarks → 26 frontal + 8 lateral metric → 14-node tree
→ 10 attribute → archetype → 8 인생 질문 본문. 궁합 엔진은 별도 (五行·十二宮·五官·三停·陰陽).
1차 기능은 다인 **교감도** (1인 관상 · 2인 궁합 · 다인 교감도).

상세 오리엔테이션·SSOT: [`CLAUDE.md`](CLAUDE.md) 참조.

---

# 남은 작업 로드맵 (2026-07-09 기준)

> 산출 근거: `docs/` 3종 + PIVOT.md(30c59a5d 에서 삭제, git 이력으로 확인) + `../KAKAO.md`
> + 실코드·커밋 대조. 현재 상태: `flutter test` 151개 전부 green, `flutter analyze` 7건(경미).
> 교감도 P1(홈 개편)·P2(현장 경로)·P3(원격 경로 + 웹 티저) 코드는 완료, Supabase DB·react 배포 완료.
> PIVOT.md 삭제 이후 남은 작업의 SOT 는 이 문서.

## 🔴 우선순위 1 — 출시 차단: 검증·배포 잔여

코드는 다 짜여 있는데 실기기에서 확인 안 된 것들. 여기가 끝나야 스토어 제출이 가능.

| # | 작업 | 완료 기준 |
|---|---|---|
| 1 | **앱 재빌드·설치** — Android manifest `/g/` intent-filter + 딥링크 코드가 실기기에 반영돼야 카톡 그룹 링크가 앱으로 열림 (그 전엔 웹으로만) | `flutter build appbundle` + 실기기 설치 후 카톡 `/g/{id}` 링크 탭 → 앱 TeamJoinScreen 직행 |
| 2 | **P3 2기기 검증** | A폰 그룹 생성 → [카톡 초대] → B폰 링크 탭 → 원탭 합류(또는 빈 슬롯 claim) → 양쪽 매트릭스 갱신 → A폰 마감 → `facely.kr/g/{id}` 쇼케이스 렌더(사진·점수 없음, 이름+밴드만) |
| 3 | **P2 현장 경로 기기 검증** | 그룹 생성(스텝 플로우) → 4명 연속 등록 → 매트릭스(🏆 무료·내 행 최상단 고정) → 페어 탭 → 1🪙 unlock → 상세 풀이 |
| 4 | **웹 티저 실기기 검증** (ad2f1d23 커밋이 "실기기 검증 남음" 명시) | 카톡 인앱 브라우저에서 `/g/{id}` 티저 시작 → 외부 브라우저 탈출 → getUserMedia 카메라 → runMetrics/runCompat 결과 → 앱 설치 유도 |
| 5 | **48h 자동 마감 서버 cron** — 구현됨(2026-07-11, `react/workers/cron.ts` Cloudflare Cron Triggers 매시). owner 앱이 다음 refresh 에서 `matrix_payload` backfill, 3명 미만은 웹 "인원 미달 종료" 렌더 | `pnpm run build && pnpm deploy` 후 Workers 대시보드에서 cron 실행 이력 확인 + 48h 경과 테스트 그룹의 웹 전환 확인 |

## 🟠 우선순위 2 — 초대 퍼널 완성 + 원격 경로 한계 해소

신규 요구사항(2026-07-09) 하나 + KAKAO.md §5 의 실사용 마찰 지점들.

| # | 항목 | 개선 방향 · 완료 기준 |
|---|---|---|
| 1 | **맛보기 촬영 데이터 재사용 (신규 요구사항, PRD §4.1)** — 웹 티저에서 찍은 사람이 앱 설치 후 또 찍어야 함. React 앱에 로그인 없음, CameraTeaser 는 runMetrics 결과를 화면 표시 후 버림 | ① React 카카오 로그인(Supabase Auth OAuth, 앱과 같은 프로젝트) ② **DeepFace 웹 연동** — 촬영 프레임을 R2 `temp/`(기존 `/api/r2/presign`) PUT → `analyze.facely.kr /analyze` 로 성별·연령 default 추정(자동 prefill, 수정 허용. FastAPI CORS 에 facely.kr origin 허용 필요) ③ 티저 capture(정면 26 metric + 추정 demographics, **측면 metrics 없이 — 엔진에서 옵션이라 그대로 fallback**)를 `metrics` 에 `user_id` 귀속 `is_my_face=true` upsert ④ 앱 로그인 rehydrate 가 그 capture 를 내 관상으로 복원. 검증: 웹 촬영+로그인 → 앱 설치 → 같은 계정 로그인 → **재촬영 없이** 그룹 원탭 합류 |
| 2 | **방장 대기 명단 원격 삭제 안 됨** — 구현됨(2026-07-11, `pushTeam` 이 upsert 전에 서버 diff 로 유령 행 제거: 미점유 슬롯 + 개명된 옛 방장 행. 점유(claim)된 행은 보존) | 검증: 방장이 대기 이름 삭제(또는 프로필명 변경) 후 재초대 → 웹 초대장에서 옛 슬롯 안 보임 |
| 3 | **매트릭스 멤버 metrics N회 개별 fetch** — 인원 많으면 로딩 지연, pull-to-refresh 는 그룹 수×멤버 수 호출 | `metrics` `in (...)` batch 조회 1회로 통합. 검증: 12명 그룹 새로고침 시 metrics 요청 1회 |
| 4 | **이름이 슬롯 키** — 동명이인은 한 슬롯만, 방장이 합류 후 이름 변경 시 매칭 깨짐 | 서버 키를 `(team_id, slot_id)` 로 바꾸고 name 은 표시 속성으로 격하 검토. `0001_baseline.sql` 직접 수정(신규 마이그레이션 파일 금지) |
| 5 | **폴링 반영 마찰** — 합류가 방장 화면에 즉시 안 뜨고 재입장/당겨서 새로고침 의존 | 그룹 화면 체류 중 주기 폴링(예: 15s) 또는 Supabase realtime 구독 검토. 검증: B폰 합류 후 A폰 그룹 화면이 손 안 대고 갱신 |

- deferred deep link(설치 직후 자동 입장)는 외부 SDK 필요라 **의도적 제외 유지** — "카톡 재탭" 패턴. 수요 관측 후 재검토.

## 🟡 우선순위 3 — 운영 + 스토어 재제출 (PIVOT P4, 전부 미착수)

| # | 작업 | 완료 기준 |
|---|---|---|
| 1 | **그룹 수명주기** — 서버 측 구현됨(2026-07-11, `react/workers/cron.ts` 매일: 발표 후 30일 teams 실삭제 + `metrics` 90일 미활동 anon 정리). 남은 것: 클라이언트 만료 *표시* — 홈 "보관" 이동, `/g/{id}` 만료 안내 렌더 (`closed_at+30일` 계산형) | 만료 그룹이 홈 "보관"으로 이동, `/g/{id}` 가 만료 안내 렌더 |
| 2 | **신고·차단** — 그룹 단위 신고 + 방장의 멤버 제거 + 부적절 그룹명 필터 | 신고 접수 경로 + 제거 시 매트릭스 재계산 확인 |
| 3 | **시즌 템플릿** — 신학기·명절·연말 제안 칩/이벤트 배너 (ad_images 활용) | 배너 노출·생성 플로우 연결 |
| 4 | **스토어 패키지** — 앱 이름·부제·스크린샷을 교감도 전면으로, App Review notes(온디바이스 468 landmark 측정 기술 + 데모 영상), Android 선출시 → iOS 4.3(b) 재제출 | Android 프로덕션 출시, iOS 제출 |

## ⚪ 우선순위 4 — 문서·코드 위생

| # | 항목 | 내용 |
|---|---|---|
| 1 | **ARCHITECTURE.md 에 교감도 부재** | `screens/team/` 5개 화면 · `team_provider` · `team_sync_service` · `teams`/`team_members` 테이블·RLS · `/g/:id` 라우트(GoRouter + react) · 웹 티저(`runMetrics` JS export — 문서엔 runEngine/runCompat 만 있음) · `ad_image_service` · `recent_unlock_focus_provider` · `compat_unlock_action` 전부 미기재. §1 화면 구조·§2 폴더·§4 데이터 흐름·§6 인프라 갱신 |
| 2 | **KAKAO.md 헤더 stale** | 상단 "M1~M4 완료, M5·M6 미완" 표기가 본문·코드(둘 다 구현 완료)와 모순. §4 체크박스(앱 재빌드)도 우선순위 1-1 완료 시 갱신 |
| 3 | **테스트 수 표기 불일치** | 실제 151 test green. `CLAUDE.md` 는 143, `ARCHITECTURE.md` §7.2 는 "test 24 파일" — 숫자 하드코딩 대신 "전부 green" 표기 권장 |
| 4 | **flutter analyze 7건** | `life_question_narrative.dart` 미사용 선언 4건(`_midOf`·`_notLowOf`·`_yangLean`·`_yinLean` — 서술 엔진 개편 잔여물), `face_analysis.dart` doc comment HTML 1건, test lint 2건. 0 issues 로 복귀 |
