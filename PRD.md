# PRD — 관상은 과학이다

현재 구현된 제품의 스펙. 기술 상세는 `flutter/docs/` 3종(SSOT), 작업 규칙은 `CLAUDE.md`.

## 1. 제품 정의

> **아는 사람들끼리 얼굴로 노는 관계 콘텐츠 앱.** 온디바이스 안면 계측(MediaPipe 468
> landmarks)으로 관상을 수치화하고, 그 측정값으로 1인 관상 · 2인 궁합 · 다인 케미를 제공한다.

| 제품 | 인원 | 내용 |
|---|---|---|
| **관상** | 1인 | 26+8 metric → 14-node → 10 attribute → archetype → 8 인생 질문 본문 |
| **궁합** | 2인 | 五行·十二宮·五官·三停·陰陽 5-frame 별도 엔진, 4단 라벨 |
| **케미** | 3~12인 | 지인 그룹의 N×N 케미 결과표. 초대가 전제인 콘텐츠 — 바이럴 루프 |

용어: UI·문서 = **케미**, 코드 식별자 = 영문 `team_*`. 멤버 카메라 등록 = **직접촬영**.
결과표 카피는 "생성" 언어만 사용 ("발표/마감" 표기 폐기).

## 2. 케미 (1차 기능)

- **그룹 생성**: 바텀 풀페이지 스텝 플로우 — 모임 훅 → 유형 → 나 포함 여부 → 인원(3~12, 기본 6).
- **인원**: min 3 (2명은 궁합으로) · 하드캡 12. 근거는 UX(결과표 가독성·현장 등록 시간).
- **그룹 화면**: 그룹명 + n/N 진행바 · 멤버 그리드(등록 = 얼굴 아바타 / 대기 = 이름 + 점선 원,
  방장 = gold ring + "나" 배지) · [직접촬영] + 초대 3버튼(카톡/링크 공유/복사) 상시 공존.
- **결과표 생성 규칙**: **전원 등록 시에만 자동 생성** (조기 생성 경로 없음). 미생성 상태에서
  [생성된 케미 결과표 보기] 탭 시 부족 인원 안내. 방치된 방은 48h cron 이 종료 처리.
- **결과표 화면**: 4단 밴드 이모지 셀(무료 셀에 점수 노출 금지) · 보는 사람 행 최상단 고정 ·
  🏆 베스트(점수+한 줄 무료) · 😲 버금 · 나와의 순위. 표시 이름은 방 명단(roster) 기준,
  방장 표기는 프로필 nickname. 페어 상세 = 1🪙 unlock.
- **원격 합류**: lazy sync — [카톡 초대] 첫 탭 시 서버 push (방장 로그인 필수). FeedTemplate
  카드 → `facely.kr/g/{id}`. 합류 = 빈 슬롯 claim(키 `(team_id, name)`) 또는 새 이름.
  같은 그룹 내 동일 이름 불가(입력 3지점 공통 검증). 반영은 폴링(재입장·pull-to-refresh).
- **웹 `/g/{id}`**: 모집 중 = 초대장 + 웹 티저 카메라(정면 1장 → runMetrics/runCompat 맛보기,
  카톡 인앱은 외부 브라우저 탈출) / 결과표 완성 = 이름+밴드 쇼케이스(사진·점수 없음) /
  종료(전원 미충족) = 종료 안내. 점수 계산은 앱에서만 — 서버는 명단과 `matrix_payload` 만 보관.

## 3. 관상 (1인)

- 카메라(mesh overlay, 정면 + 측면 yaw 45~80°) 또는 앨범 → 성별·연령·인종 확인(DeepFace
  자동 prefill, 상대방 관상은 optional 이름 입력) → 리포트.
- 리포트: 10 attribute bar · 음양 bar · 삼정 radar · 14-node 본문 · archetype + 8 인생 질문.
  본문 톤 = 현대 한국어 평문 (한자 단독·메타포·자기계발 jargon 금지).
- **capture-only**: raw metric 만 저장, 해석은 load 시 현재 엔진으로 재계산.
- 공유: R2 썸네일 + Supabase upsert + `facely.kr/r/{uuid}` (웹은 같은 엔진 JS 컴파일 렌더).
  공유받은 카드는 북마크 시 보관(관상 탭 북마크 탭).

## 4. 궁합 (2인)

- 총점 + 4 sub-score(五形和 0.20 / 宮位調 0.40 / 氣質合 0.25 / 性情諧 0.15) + 4단 라벨.
- intimacy 톤 3분기(pure/flirty/spicy). 전체 본문 = 1🪙 unlock — 결제 시 두 body 를
  `unlocks` 에 동결(self-contained, 서버 row 소멸과 무관하게 복원).

## 5. 계정·코인

| 항목 | 스펙 |
|---|---|
| 인증 | Kakao OAuth · email+OTP. 프로필 이름(nickname)은 설정에서 수정 — 내 관상 alias 로 전파 |
| 복원 | 로그인 rehydrate — 본인 metrics 전체 + 모집 중인 케미 방 서버→로컬 복원 (closed 방 부활 금지) |
| 코인 | 원장(coins) + RPC 단일 트랜잭션. store_transaction_id unique 중복 차단 |
| 무료 | AdMob rewarded 3편 = 1🪙 (KST 자정 reset) · 그룹 생성·등록·밴드·🏆 1쌍·관상 리포트 |
| 유료 | 앱스토어 IAP 코인 → 궁합 본문 1🪙 · 케미 페어 상세 1🪙 |

## 6. 프라이버시·데이터 수명주기

- 얼굴 사진 온디바이스 원칙 — 서버는 metrics(숫자)+썸네일만. 원본은 R2 `temp/` 1일 삭제.
- metrics = 생체인식 특징정보 — 실존 인물 비교 기능 영구 금지. 타인 등록 = 동의 전제.
- 웹 공개 뷰는 이름+밴드만. 링크 read = UUID 아는 사람 (링크 공유 모델).
- **수명주기 cron** (`react/workers/cron.ts`): 48h 방치 방 종료(매시) · 결과표 완성 후 30일
  teams 실삭제 · 90일 미활동 anon metrics+R2 삭제(매일, 로그인 유저 row 제외).
- **탈퇴**: 본인 metrics hard delete + R2 썸네일 + 모집 중 teams 삭제. metrics FK cascade.
  `unlocks.partner_body` 는 의도된 보존(구매 자산, 숫자만).

## 7. 아키텍처 제약 (요약)

```
shared/ (face_engine, 순수 Dart SSOT) ── path dep ──▶ flutter/ (앱 셸)
        └── dart compile js -O1 ──▶ react/ (facely.kr Workers — /r 카드 SSR·/g 초대장·쇼케이스·티저·cron)
python/ (DeepFace FastAPI — 성별·연령·인종 추정)     Supabase (metrics·coins·unlocks·teams·team_members)
```

- 궁합 엔진은 Flutter 에만 — react 는 `matrix_payload` 렌더만. JS export 3개(runEngine/runCompat/runMetrics).
- 실시간 아님 — 폴링 (의도된 결정). 결제는 전부 앱스토어 IAP (웹 결제 없음).
- 익명 그룹 소유 불가 — 원격 그룹 방장은 로그인 필수.
