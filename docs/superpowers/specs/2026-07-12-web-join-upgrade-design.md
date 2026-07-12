# 웹 풀 참여 (web join) — /g/:id react 앱 업그레이드 설계

**날짜**: 2026-07-12 · **승인**: C안 (웹 풀 참여) 확정

## 1. 문제

앱 미설치자가 케미 그룹 초대 링크(`facely.kr/g/{id}`)를 열었을 때:

1. **"나를 알려주세요" 선택 UI 불가시** — 칩 배경 `#f7f7f8` = 페이지 배경 `#f7f7f8`.
   선택 상태도 1px 테두리뿐. 그냥 텍스트 나열로 보인다.
2. **"카메라 켜기" 무반응** — 성별+나이 미선택 시 disabled 인데 disabled 스타일이
   배경에 녹아 텍스트로 보임 → 눌러도 무반응으로 인지. 부가적으로 `<video>` 가
   camera 단계에서만 마운트되는 ref race + MediaPipe CDN 로딩 무표시.
3. **카카오 로그인 부재** — 웹 캡처가 어디에도 귀속되지 않아 앱 설치 후 rehydrate
   불가. 그룹 참여도 앱 설치 전엔 불가능 → "전원 등록 시에만 결과표 생성" 규칙과
   결합해 전원 앱 설치가 결과표의 병목.

## 2. 결정 (C안): 웹에서 그룹 참여를 끝까지 완성

카톡 링크를 받은 미설치자가 **브라우저에서 카카오 로그인 → 이름(슬롯) 선택 →
성별/나이 → 정면 캡처 → 그룹 참여 완료**까지 간다. 참여는 `team_members` 슬롯을
실제로 채우므로 **전원 등록 카운트에 포함** — 미설치자도 그룹을 완성시킨다.
이후 앱을 설치하고 같은 카카오 계정으로 로그인하면 기존 rehydrate
(metrics by user_id + 모집 중 초대 그룹)가 **무변경으로** 웹 캡처·참여를 복원한다.

### 기반 사실 (검증 완료)

| 항목 | 확인 내용 |
|---|---|
| 인증 | 앱 로그인 = Supabase Auth Kakao OAuth. 웹도 supabase-js 로 같은 provider → 같은 `auth.users` |
| 그룹 write RLS | `team_members_claim_slot` (빈 슬롯을 내 metrics 로) + `team_members_insert` (내 metrics 소유면 새 행) 이미 존재 |
| metrics write RLS | `metrics_insert_anon` (landmarks 금지 체크만) — authed insert 허용 |
| 썸네일 | `POST /api/r2/presign` 인증 없음 → 웹 캡처 프레임 200px 업로드 가능 |
| 닉네임 | `users_self_read` RLS 로 본인 row 읽기 가능 |
| 앱 복원 | `_rehydrateAll` (metrics by user_id → 모집 중 초대 팀) 기구현 — 앱 코드 무변경 |

### 수용한 트레이드오프

- **웹 캡처 품질**: 정면 1장 — `lateralMetrics: null`, `faceShape: "oval"` 고정,
  DeepFace 미경유 (성별/나이 수동 선택). 결과표에는 참여하되 "정밀 분석은 앱에서"
  프레이밍 유지. 앱 설치 후 내 관상 재등록 시 앱 캡처가 로컬 우선으로 대체.
- **웹 로그인 = 정식 가입**: `handle_new_user` 트리거로 users row + 가입 보너스
  발생. 의도된 동작 (같은 계정을 앱에서 이어 씀).

## 3. 아키텍처

전부 `react/` 안. 서버 스키마·RLS·Worker API 변경 0. 앱(Flutter) 변경 0.

```
app/lib/auth.ts        (신규)  supabase-js 브라우저 클라이언트 + kakao OAuth + 세션/닉네임
app/lib/join.ts        (신규)  웹 캡처 저장 파이프라인 (presign→PUT→metrics→team_members)
app/components/JoinWizard.tsx (신규, CameraTeaser 대체) 단계형 위저드
app/lib/supabase.ts    (수정)  TeamShowcase 에 슬롯 상세(members: {name, joined}) 추가
app/routes/g.$id.tsx   (수정)  supabase 공개 config 전달 + JoinWizard 렌더 + 슬롯 칩
app/app.css            (수정)  .join-* 클래스 (인라인 스타일 → css)
app/components/CameraTeaser.tsx (삭제)
```

### 3.1 auth.ts — 카카오 로그인

- `@supabase/supabase-js` 의존성 추가. 브라우저 전용 lazy singleton
  (`flowType: 'pkce'`, `detectSessionInUrl: true`).
- `SUPABASE_URL`/`SUPABASE_ANON_KEY` 는 `/g/:id` loader 가 내려준다
  (anon key 는 공개키 — 노출 무해).
- 로그인: `signInWithOAuth({ provider: 'kakao', options: { redirectTo: 현재 /g/{id} URL } })`
  → 카카오 → 같은 페이지로 복귀, supabase-js 가 `?code=` 자동 교환.
  복귀 후 URL 의 code 쿼리는 `history.replaceState` 로 정리.
- 닉네임: `users` self-read → `nickname`. 실패 시
  `auth.user.user_metadata` fallback → 그래도 없으면 빈 값 (이름 직접 입력 유도).

**운영 선행 조건 (대시보드 1회)**: Supabase Auth → URL Configuration →
Redirect URLs 에 `https://facely.kr/g/*` (+ 로컬 dev `http://localhost:*/*`) 추가.

### 3.2 JoinWizard — 단계 머신

```
entry ──[카카오로 참여하기]──► (미로그인이면 kakao redirect) ─► name
  │                                                            │
  └─[먼저 미리보기]─► info ─► camera ─► teaser-result           ▼
                                │        │[참여하기]──stash──► info(skip)…
                                │        └(비로그인 유지 가능)   │
                                ▼                              ▼
                             (오류: error)                  camera ─► saving ─► done
```

- **entry**: 주 CTA `[카카오로 참여하기]` + 부 링크 `먼저 미리보기` (저장 없음).
  카톡 인앱이면 기존 외부 브라우저 탈출 유지 (`inapp.ts` 재사용).
- **name**: 방장이 깔아둔 **빈 슬롯 목록에서 선택**(claim) 또는 직접 입력
  (기본값 = 카카오 닉네임). 점유된 이름은 비활성 표시. 그룹 내 중복은
  입력 시 차단 + 서버 unique 를 최종 방어선으로.
- **info**: 성별(2)/나이대(6) segmented 칩 — §3.5 스타일. 이 단계 진입 즉시
  MediaPipe+engine 을 백그라운드 프리로드 시작.
- **camera**: `<video>` 는 위저드 마운트 내내 존재(비표시)해 ref race 제거.
  로딩 인디케이터("얼굴 인식 준비 중…") → 검출 힌트 → 3프레임 안정 시 캡처.
  캡처 순간 video 프레임을 canvas 중앙 정방형 crop → 200×200 JPEG(q0.8).
  20초 무검출 시 재시도 안내. 실패 taxonomy: 권한 거부 / 모듈 로드 실패 /
  얼굴 미검출.
- **saving**: §3.3 파이프라인. 진행 표시.
- **done**: "참여 완료 ✓" + 방장과의 케미 티저 점수(runCompat; 방장 미등록이면
  솔로 runEngine fallback) + "전원 모이면 이 링크에서 결과표 공개" +
  "측면까지 넣은 정밀 분석은 앱에서" + 스토어 CTA.
- **teaser-result** (미리보기 경로): 점수 + `[이 결과로 그룹 참여하기]` →
  body+썸네일 dataURL 을 `sessionStorage("facely:pendingJoin", {teamId, body, thumb})`
  에 보관 → 카카오 redirect → 복귀 시 stash 감지 → name 단계로 점프(재촬영 없음).

### 3.3 join.ts — 저장 파이프라인 (앱과 동일 계약)

1. `id = crypto.randomUUID()` (1 capture = 1 uuid 원칙 유지)
2. `POST /api/r2/presign {prefix:"thumbnails", uuid:id}` → `PUT` JPEG → `key`
3. `metrics` upsert (supabase-js, authed):
   `{ id, user_id: uid, body, alias: nickname, is_my_face: true }`
   — body: `{ schemaVersion:1, ethnicity:"eastAsian", gender, ageGroup,
   timestamp, source:"camera", thumbnailKey:key, metrics:runMetrics(...),
   lateralMetrics:null, faceShape:"oval" }` (앱 body 계약과 동일 키)
4. `team_members` upsert `{ team_id, metrics_id:id, name, is_owner:false }`
   `onConflict: 'team_id,name'` — 빈 슬롯이면 claim, 새 이름이면 insert
   (앱 `joinTeam` 과 동일 형태)
5. 오류 매핑: unique/RLS 충돌 → "방금 다른 사람이 그 자리에 들어갔어요.
   다른 이름으로 참여해 주세요." (name 단계로 복귀, metrics 는 재사용) /
   저장 직전 `closed_at` 재확인 → 닫혔으면 "모집이 종료된 그룹입니다."

`is_my_face: true` 근거: 웹 참여자가 등록하는 것은 본인 얼굴 — 앱 rehydrate 가
이 행을 내 관상으로 복원한다 (alias=nickname 은 앱 saveMetrics 의 my-face
컨벤션과 동일).

### 3.4 초대장 개선 (g.$id.tsx)

- `TeamShowcase.memberNames` → `members: { name, joined }[]` 로 확장
  (기존 name 배열 소비처는 파생). 초대장 칩이 등록완료(✓)/대기 를 구분 표시.
- loader 가 `supabaseUrl`/`supabaseAnonKey` 를 응답에 포함.
- `CameraTeaser` → `JoinWizard` 교체.

### 3.5 UI 재작업 (app.css)

react 4색 팔레트(`#1a1a1a`/`#666`/`#c44`/`#f7f7f8`) + 흰색 유지. 인라인 스타일을
`.join-*` 클래스로 이관:

- 칩: **흰 배경 + 1px `#ddd` 테두리**, 선택 시 `1px #1a1a1a` + `font-weight 600`.
  터치 타깃 최소 44px 높이.
- 버튼: `.cta-primary` 와 동일 크기(12px 16px, radius 12). **disabled 은닉 제거** —
  버튼은 항상 검정으로 보이고, 미선택 상태에서 탭하면 인라인 안내
  "성별과 나이대를 골라 주세요" 표시.
- 단계 전환 시 상단에 그룹명 유지, 위저드 영역만 교체.

## 4. 오류 처리 요약

| 상황 | 처리 |
|---|---|
| 카카오 로그인 취소/실패 | entry 복귀 + 안내 |
| 카메라 권한 거부 | "권한을 허용해 주세요" + 재시도 버튼 |
| MediaPipe/엔진 로드 실패 | "잠시 후 다시 시도" + 앱 유도 |
| 20s 무검출 | 힌트 갱신 + 재시도 |
| 이름 충돌 (동시 claim) | name 단계 복귀, metrics 재사용 |
| 저장 중 그룹 마감 | 종료 안내 (write 중단) |
| 인앱 브라우저 | 기존 외부 브라우저 탈출 흐름 유지 |

## 5. 검증

1. `pnpm typecheck` 통과 (기존 contact.tsx WEB3FORMS 이슈는 기왕 결함 — 무관).
2. 로컬 dev: 데모 그룹으로 entry→미리보기→로그인→참여 전 단계 통과.
3. 실기기: 카톡 링크 → 외부 브라우저 → 카카오 로그인 → 참여 → 방장 앱
   pull-to-refresh 합류 확인 → 참여자가 앱 설치+로그인 → rehydrate 복원 확인.
4. 문서 현행화: `KAKAO.md`(앱 미설치 흐름), `react/docs/HOW-IT-WORKS.md`,
   `PRD.md` 해당 절.

## 6. 명시적 비범위

- 앱(Flutter) 코드 변경 — rehydrate·병합 기구현 그대로.
- 서버 스키마·RLS·Worker API 변경.
- 웹에서 측면 캡처·faceShape 분류·DeepFace 연동.
- deferred deep link (설치 직후 자동 입장) — 기존 의도적 제외 유지.
