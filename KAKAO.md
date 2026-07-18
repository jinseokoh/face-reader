# 카카오 초대 — 케미 배틀 원격 참여

방장이 배틀 방을 만들면 방은 즉시 서버에 존재한다. 방장이 `facely.kr/g/{방ID}` 링크를
카톡으로 보내면, 받은 사람이 링크를 눌러 앱 상세 페이지(`BattleDetailScreen`)에서 로그인
+ 내 관상 확인(+ 비밀방이면 PIN) + 사진 공개 계약 확인을 마치는 순간 셀프 조인된다.

## 설계 결정

1. **서버 우선** — 방은 생성 즉시 서버에 존재한다. 로컬에만 머무는 단계가 없다.
2. **방의 주인 = 로그인 계정** (익명 소유 불가) — 방 생성 자체가 로그인 게이트.
3. **점수 계산은 클라이언트, 서버는 동결·보관만** — 정원 충족 시 서버가 `chemistry_snapshot`(입력)을 동결하고, 클라이언트가 계산한 `result_payload`(출력)를 1회 기록해 보관한다.
4. **링크 = 콘텐츠** — "우리 팀 케미표"는 혼자 못 만든다. 초대가 바이럴 루프.

## 동작 흐름

- **방장**: 배틀 생성(방 유형·제목 프리셋·인원·연령대·공개/비밀·썸네일 공개) → 상세 페이지 진입 → QR 코드·
  [카톡 초대]·[링크 공유]·[복사]가 상시 공존. 카톡 초대는 FeedTemplate 카드
  ([참여하기] 버튼, hero = `cdn.facely.kr/assets/og.png`). 카톡 미설치면 OS 공유
  시트 fallback (문구+링크 텍스트).
- **합류자 (앱 설치)**: 링크 탭 → 유니버설/앱 링크로 앱 직행 → `BattleDetailScreen`
  이 방 정보(n/N명·연령대, match 방은 남은 성별 자리) 미리보기 표시 → 로그인 →
  내 관상 확인(없으면 촬영) → (비밀방) PIN 입력 → 사진 공개 계약 확인 →
  `join_battle` RPC 로 셀프 조인 → 화면 전환 없이 같은 상세 페이지가 참가자 뷰로
  전환. 이름 슬롯·빈 슬롯 claim 은 없다 — 정체성은 로그인 계정 하나뿐.
- **방장 반영**: 상세 페이지는 Supabase Realtime(`teams` UPDATE + `team_members`
  INSERT/DELETE) 구독 + 10초 백업 폴링을 상시 병행해 반영된다 — 이탈(`team_members`
  DELETE)은 filter 매칭 한계로 폴링이 커버한다. 정원이 차면 그 조인 트랜잭션이
  곧바로 결과 계산 단계(`revealing`)로 전이한다 —
  방장이 별도로 "결과표 생성"을 누르는 액션은 없다.
- **앱 미설치 (웹 참여)**: 브라우저로 `/g/{id}` — 모집 중 = 초대장 + **웹 참여
  위저드**(카카오 로그인(supabase-js, 앱과 같은 auth.users) → (비밀방) PIN →
  사진 공개 계약 → 정면 캡처 → metrics+R2 썸네일 저장 → `join_battle` RPC 로 셀프
  조인) / 결과 공개 = `result_payload` 있으면 쇼케이스, 없으면 클라이언트가
  `runBattle` 로 즉석 계산 / 종료 = 안내. 웹 참여자가 나중에 앱 설치 후 같은
  카카오 계정으로 로그인하면 rehydrate 가 캡처를 자동 복원하고, 조인한 방은
  `team_members` 로 이미 서버에 귀속돼 있어 별도 복원 없이 "내 배틀" 목록에
  그대로 뜬다. 설치 직후 자동 입장(deferred deep link)은 의도적 제외 — 설치 후
  카톡에서 링크 재탭.

## 전제 조건

- 서버: `0001_baseline.sql` §11-2~11-6 적용(teams·team_members·battle_matches·
  battle_messages + RLS + RPC 상태 머신 + view + Realtime), AASA·assetlinks 에 `/g/*`.
- 방장: 로그인 + 내 관상 등록. 합류자: 앱(로그인 + 내 관상) 또는 웹(카카오 로그인
  + 웹 캡처). 웹 로그인 복귀에는 Supabase Auth Redirect URLs 에
  `https://facely.kr/g/*` 등록 필요.

## 현행 한계 (의도된 트레이드오프 포함)

| 한계 | 내용 |
|---|---|
| deferred deep link 없음 | 설치 직후 자동 입장 불가 — 카톡 재탭 패턴 (외부 SDK 회피, 의도적) |
| 링크 = 누구나 읽기 | UUID 아는 사람은 방 제목·참가자 닉네임 열람 (링크 공유 모델, 인지된 설계) |
| 카카오 오픈채팅 미사용 | 오픈링크 자동 발행 API 는 도메인 ID 발급이 제휴 게이트 — 매칭 성사 후 대화는 인앱 1:1 채팅(`battle_messages`)이 담당 (rev2, 공약·`chat_url` 폐기) |

## 코드 위치

| 역할 | 파일 |
|---|---|
| 서버 접점 (create/join/leave/submit/fetch/watch) | `flutter/lib/data/services/battle_service.dart` |
| 방 목록·상태 | `flutter/lib/presentation/providers/battle_provider.dart` |
| 카톡 메시지·링크 | `flutter/lib/domain/services/share/share_publisher.dart` |
| 상세(참가+대기 통합) / 결과 화면 | `battle_detail_screen.dart` / `team_reveal_screen.dart` |
| 매칭 성사 / 인앱 채팅 | `battle_match_card.dart` / `battle_chat_screen.dart` |
| DB 스키마 + RPC 상태 머신 | `react/db/migrations/0001_baseline.sql` §11-2~11-6 |
| 웹 `/g/:id` | `react/app/routes/g.$id.tsx` |
