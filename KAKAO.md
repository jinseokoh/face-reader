# 카카오 초대 — 케미 그룹 원격 참여

방장이 그룹을 서버에 올리고 `facely.kr/g/{그룹ID}` 링크를 카톡으로 보낸다.
받은 사람이 링크를 누르면 앱 참여 화면(TeamJoinScreen)이 열리고, 얼굴을 등록하면
그룹 멤버가 된다.

## 설계 결정

1. **lazy sync** — 그룹은 평소 로컬(Hive)에만. [카톡 초대] 첫 탭 시점에 서버 push.
2. **원격 그룹의 주인 = 로그인 계정** (익명 소유 불가) — 초대 시 로그인 게이트.
3. **점수 계산은 앱, 서버는 보관만** — 서버는 명단 + (결과표 생성 시) `matrix_payload`.
4. **링크 = 콘텐츠** — "우리 팀 궁합표"는 혼자 못 만든다. 초대가 바이럴 루프.

## 동작 흐름

- **방장**: [카톡 초대] → (로그인) → push (`teams` 1행 + 등록 멤버 + 대기 이름 슬롯,
  push 는 서버 diff 로 유령 슬롯 제거 — claim 된 행은 보존) → FeedTemplate 카드
  ([참여하기] 버튼, hero = `cdn.facely.kr/assets/og.png`). 카톡 미설치면 OS 공유
  시트 fallback (문구+링크 텍스트).
- **합류자 (앱 설치)**: 링크 탭 → 유니버설/앱 링크로 앱 직행 → 참여 화면이 서버
  미리보기(참여자 칩 + 빈 슬롯 칩) 표시 → (A) 빈 슬롯 claim — 키 `(team_id, name)`
  으로 같은 이름 행을 채움, 또는 (B) 내 이름(nickname)으로 새로 참여. 점유된
  이름·중복 참여는 RLS 가 차단.
- **방장 반영**: 재입장(자동 폴링) 또는 pull-to-refresh → `refreshFromServer` 가
  합류를 이름 매칭으로 병합. 결과표는 **전원 등록 시에만 생성**.
- **앱 미설치 (웹 참여)**: 브라우저로 `/g/{id}` — 모집 중 = 초대장 + **웹 참여
  위저드** (카카오 로그인(supabase-js, 앱과 같은 auth.users) → 빈 슬롯 claim 또는
  새 이름 → 성별/나이 → 정면 캡처 → metrics+R2 썸네일 저장 → team_members 합류.
  **전원 등록 카운트에 포함**) / 완성 = 결과표 쇼케이스 / 종료 = 안내. 웹 참여자가
  나중에 앱 설치 후 같은 카카오 계정으로 로그인하면 rehydrate 가 캡처·그룹을 자동
  복원. 설치 직후 자동 입장(deferred deep link)은 의도적 제외 — 설치 후 카톡에서
  링크 재탭.

## 전제 조건

- 서버: `0001_baseline.sql` 적용(teams·team_members+RLS), AASA·assetlinks 에 `/g/*`.
- 방장: 로그인 + 내 관상 등록. 합류자: 앱(로그인 + 내 관상) 또는 웹(카카오 로그인
  + 웹 캡처). 웹 로그인 복귀에는 Supabase Auth Redirect URLs 에
  `https://facely.kr/g/*` 등록 필요.

## 현행 한계 (의도된 트레이드오프 포함)

| 한계 | 내용 |
|---|---|
| deferred deep link 없음 | 설치 직후 자동 입장 불가 — 카톡 재탭 패턴 (외부 SDK 회피, 의도적) |
| 폴링 | 합류가 방장 화면에 즉시 안 뜸 — 재입장/당겨서 새로고침 |
| 이름 = 슬롯 키 | 같은 그룹 내 동명 불가(입력 시 차단), 합류 후 방장이 그 이름을 바꾸면 매칭 훼손 가능 |
| 링크 = 누구나 읽기 | UUID 아는 사람은 그룹명·멤버 이름 열람 (링크 공유 모델, 인지된 설계) |
| 멤버별 개별 fetch | 매트릭스 렌더 시 멤버 수만큼 metrics 왕복 — 인원 많으면 로딩 지연 |

## 코드 위치

| 역할 | 파일 |
|---|---|
| 서버 동기화 (push/join/close/fetch/rehydrate) | `flutter/lib/data/services/team_sync_service.dart` |
| 그룹 상태·병합 | `flutter/lib/presentation/providers/team_provider.dart` |
| 카톡 메시지·링크 | `flutter/lib/domain/services/share/share_publisher.dart` |
| 참여 화면 / 딥링크 수신 | `team_join_screen.dart` / `deep_link_service.dart` |
| DB 스키마 | `react/db/migrations/0001_baseline.sql` §11-2/11-3 |
| 웹 `/g/:id` | `react/app/routes/g.$id.tsx` |
