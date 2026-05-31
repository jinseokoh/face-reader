# TODONOW — 궁합 유료-소유 모델 + metrics 스키마 정리

> 이 phase 의 목적: **받은 카드(공유 UUID)를 관상 앨범에서 분리**하고, **궁합을 "결제=소유" 모델**로 정립하며, 이를 뒷받침하도록 **metrics 스키마/직렬화를 정리**한다.
> 작성 시점 합의 기준. 점검용. (구현 전 최종 확인 단계)

---

## 0. 대전제 (이번 phase 의 아키텍처 결정)

- **로컬 Hive = durable SOT**, **remote(Supabase metrics) = 공유용 projection(90일 TTL)** — 현 구조 유지.
- 즉 "remote=SOT, 로컬=캐시" 전환은 **이번 phase 아님** (아래 §제외 참조).
- 필드 canonical 위치 정리(아래)는 local↔remote SOT 결정과 **독립적**으로 진행.

---

## 1. 범위

### 포함 (이번 phase)
1. metrics 중복 컬럼 제거 — demographics(source/ethnicity/gender/age_group)는 **이미 body 에도 있으므로** 중복인 top-level 컬럼만 drop(body 사본을 단일 소스로). isMyFace 는 body 에서 빼고 컬럼으로 승격
2. 직렬화 분리 (`toJsonString` 로컬용 / `toBodyJson` 서버 body용)
3. flutter write/receive 경로 반영
4. refine admin 의 metrics 읽기 경로 반영 (body 파싱)
5. 관상 앨범에서 "받은 카드" 섹션 제거 → 받은 카드는 궁합 탭에만
6. 궁합 "결제=소유" 보강: unlock 된 상대 만료 제외 + thumbnail gender fallback + 로컬 스냅샷 계산
7. 받은 카드 ReportPage 에 "나와의 궁합 보기" CTA(+teaser)
8. 약관/개인정보 1줄 (결제한 궁합 결과는 상대 삭제와 무관하게 기기 보관)

### 제외 (다음 phase 로 명시 연기)
- ❌ Hive 역할 강등(remote=SOT, 로컬=캐시) — anon auth + owner-row 만료 제외 + 받은 북마크 server화 선행 필요
- ❌ Supabase anonymous auth 도입
- ❌ 원격 채팅 / liveness 본인 인증 (isMyFace 신뢰성 강화)
- ❌ Hive 라이브러리 교체

---

## 2. 최종 스키마 (확정)

```
public.metrics:
  id, user_id, body, alias, is_my_face, views, expires_at, created_at, updated_at
```

**배치 원칙 (하나의 규칙):**
- **body = 분석 결과 payload** — demographics·metrics·faceShape 등 관상 분석 데이터.
- **컬럼 = 관계/소유 메타 + 쿼리 키** — user_id, isMyFace, alias, views, expires_at, timestamps.

→ demographics→body, isMyFace·alias→컬럼은 위 규칙에서 자동 도출. (성격이 다른 분류 차이일 뿐, 비대칭 아님)

| 필드 | 위치 | canonical | 비고 |
|---|---|---|---|
| source, ethnicity, gender, age_group | **body 안에만** | body | 컬럼 drop. refine 가 body 파싱(키: `source/gender/ethnicity/ageGroup`) |
| isMyFace | **컬럼(`is_my_face`)** | 컬럼 | body 에서 제거 |
| alias | **컬럼(현행 유지)** | 컬럼 | 본인이 metrics 에 붙이는 이름 = 소유 메타. body 에 안 넣음 |
| 나머지(user_id/views/expires_at/created_at/updated_at/body) | 컬럼 | — | 변경 없음 |

- RLS `metrics_insert_anon` 의 `body->>'alias' is null` 가드: **변경 불필요** (alias 가 body 에 안 들어가므로 항상 만족).
- check constraint `source in ('camera','album')`: source 컬럼 drop 과 함께 제거.

---

## 3. Workstream 상세

### A. DB — `react/db/migrations/0001_baseline.sql`
- [ ] metrics 테이블에서 컬럼 drop: `source`, `ethnicity`, `gender`, `age_group`
- [ ] `source` check constraint 제거
- [ ] 컬럼 추가: `is_my_face boolean not null default false`
- [ ] `alias` 컬럼 유지
- [ ] metrics 관련 index 점검 (source/gender 인덱스 없음 — 영향 없음 확인)
- [ ] (확인) `metrics_insert_anon` 정책은 그대로 — alias 가드 유지해도 무해
- [ ] reset 흐름은 기존 §DEV ONLY reset 블록 그대로 (drop schema → baseline RUN)

### B. 직렬화 — `shared/lib/domain/models/face_reading_report.dart`

> 핵심: 지금은 `toJsonString()` 하나가 **로컬 Hive + 서버 body 겸용**. 이걸 둘로 쪼갠다.
> alias·isMyFace 는 **로컬엔 남기고 서버 body 에서만 뺀다** (로컬은 표시용으로 필요).

| 직렬화 | 용도 | alias | isMyFace | demographics | thumbnailPath/receivedAt |
|---|---|---|---|---|---|
| `toJsonString()` (현행 유지) | 로컬 Hive | 유지 | 유지 | 유지 | 유지 |
| `toBodyJson()` (신규) | 서버 body | **제외** | **제외** | 유지 | 제외 |

- [ ] `toJsonString()` — **로컬 Hive 전용, 현행 그대로** (alias·isMyFace 포함)
- [ ] **`toBodyJson()` 신규** — 서버 body 전용:
  - **제외**: `alias`(→컬럼), `isMyFace`(→컬럼), 로컬 전용 `thumbnailPath`·`receivedAt`
  - **포함**: `ethnicity/gender/ageGroup/source` + `metrics` rawValue + faceShape 등 분석 payload
- [ ] `fromJsonString()` — 로컬 load 경로(변경 없음, alias·isMyFace 계속 읽음)

### C. flutter write/receive
- [ ] `data/services/supabase_service.dart`
  - [ ] `saveMetrics`: `body: report.toBodyJson()`, 컬럼 payload 에서 `source/ethnicity/gender/age_group` 제거, `is_my_face: report.isMyFace` 추가
  - [ ] `upsertMetricsBody`: 동일하게 `toBodyJson()` + `is_my_face`
  - [ ] `updateAlias`: **변경 없음** (alias 컬럼 update 유지)
- [ ] `domain/services/share/share_receive_service.dart`
  - [ ] isMyFace 를 **row 의 `is_my_face` 컬럼**에서 읽기 (현재 `body['isMyFace']` → 컬럼)
  - [ ] `autoRegisterEligible`: source 는 body 에서 계속 읽음, isMyFace 만 컬럼으로

### D. 관상 앨범에서 받은 카드 분리
- [ ] `presentation/screens/physiognomy/physiognomy_screen.dart`
  - [ ] 앨범 탭 source 목록 `[album, received]` → **`[album]` 만**
  - [ ] `received` 섹션/헤더('받은 카드') 제거
- [ ] 받은 카드는 이제 **궁합 탭에서만** 노출

### E. 궁합 "결제=소유" 보강
- [ ] `presentation/providers/history_provider.dart`
  - [ ] load 시 만료 prune 예외: **나와 unlock 된 pair 의 상대 카드는 `expiresAt` 지나도 유지** (unlocked Set 기준)
- [ ] `presentation/screens/compatibility/compatibility_screen.dart`
  - [ ] 후보(`!isMyFace`) 목록 유지 — locked/unlocked 2섹션 유지
  - [ ] 궁합 계산은 **로컬 스냅샷(body rawValue)** 으로 (remote 생존 비의존) — 이미 로컬에 metrics 있음
- [ ] thumbnail 렌더 (해당 위젯)
  - [ ] received 카드 R2 thumbnail 404/missing → **gender 기반 fallback 아바타** (gender 는 body 에 있음)

### F. 받은 카드 → 궁합 전환 CTA (자동저장 없음)
- [ ] `presentation/screens/home/report_page.dart` (source==received 일 때)
  - [ ] **"나와의 궁합 보기 (N코인)" primary CTA** — **단순 버튼만** (teaser 없음)
  - [ ] unlock 후 같은 자리 "궁합 결과 보기"
- [ ] `config/router.dart` — **`_maybeAutoRegister` 제거**: 공유 링크 열람만으로 history 자동 저장 안 함
- [ ] 받은 카드는 **사용자가 CTA 를 눌러 궁합으로 진행한 시점에만** history 저장 = "주체적 추가". 열람만 하면 저장 안 됨(ephemeral)

### G. refine admin — body 파싱으로 전환
- [ ] `refine/src/types.ts` — `MetricEntry` 에서 컬럼 `source/ethnicity/gender/age_group` 제거, `is_my_face` 추가; body 파싱 헬퍼 타입
- [ ] `refine/src/pages/metrics/list.tsx`
  - [ ] source/gender/ethnicity/age_group 를 **body 파싱**으로 display (키: `source/gender/ethnicity/ageGroup`)
  - [ ] 해당 컬럼 **서버 필터/소팅 제거** (display-only, 합의됨)
  - [ ] alias 컬럼 표시 **유지**
  - [ ] (옵션) `is_my_face` 컬럼 표시 추가
- [ ] `refine/src/pages/metrics/show.tsx` — 동일 body 파싱
- [ ] `refine/src/pages/dashboard/index.tsx` — source/gender **집계 제거** (body 파싱 비용 대비 불필요)

### H. 문서 / 약관
- [ ] `react/public/privacy.md` (또는 terms) — "결제한 궁합 결과는 상대방 데이터 삭제와 무관하게 기기에 보관됨" 1줄
- [ ] 변경 후 react 재배포(`pnpm build && pnpm run deploy`) + Flutter 는 fetch 라 자동 반영

---

## 4. 결정 완료 (전부 확정)

- ✅ **궁합 후보 정의** — `!isMyFace` **전부 유지** (내가 앨범으로 분석한 타인 얼굴 + 받은 카드 모두 후보)
- ✅ **CTA** — **단순 버튼만** (blur teaser 없음)
- ✅ **dashboard 집계** — source/gender **집계 제거**
- ✅ **received 진입/저장** — **자동저장 없음. CTA 로만.** 공유 링크 열람만으론 저장 안 하고, 사용자가 "나와의 궁합 보기" CTA 를 눌러 궁합으로 진행할 때만 저장(주체적 추가). → `router.dart` `_maybeAutoRegister` 제거
- ✅ `thumbnailPath`·`receivedAt` → Hive 로컬(`toJsonString`) 유지 / 서버 body(`toBodyJson`) 제외 (device·수신자 로컬 메타. receivedAt 은 현재 미사용이나 받은-카드 UX 대비 로컬 보존)

---

## 5. 실행 순서 (제안)

1. DB baseline 수정 (§A) — reset 전제이므로 먼저 확정
2. shared `toBodyJson` (§B)
3. flutter write/receive (§C)
4. refine body 파싱 (§G) — 스키마와 동시 정합
5. 관상앨범 분리 (§D) + 궁합 보강 (§E,F)
6. 약관 1줄 (§H)
7. 검증 (§6) → reset + baseline RUN → 재배포

---

## 6. 검증 체크리스트

- [ ] `flutter analyze` 0 issues / 관련 test green
- [ ] refine `npx tsc --noEmit` 0 errors
- [ ] 신규 분석 publish → metrics row 에 `is_my_face` 채워지고 body 에 demographics 존재, body 에 isMyFace/alias **없음**
- [ ] anon publish 가 RLS 통과 (alias body 미포함 확인)
- [ ] 공유 링크 수신 → isMyFace 를 컬럼에서 정상 판독, autoRegister 정상
- [ ] 관상 앨범 탭: received 안 보임 / 궁합 탭: 받은 카드 보임
- [ ] unlock 된 상대: `expiresAt` 지나도 목록 유지, thumbnail 없으면 gender 아바타
- [ ] received ReportPage: 궁합 CTA 노출
- [ ] refine: metrics 목록에 demographics 표시(소팅 불가 허용), alias 표시
- [ ] reset 블록 단독 RUN → baseline RUN → 관리자 계정 생성 흐름 정상

---

## 7. 다음 phase 예고 (이번엔 안 함)

- anon auth 도입 → metrics 전부 user_id 보유 → "remote=SOT, 로컬=캐시" 전환
- owner 본인 row 만료 제외
- 받은 북마크 server 테이블화
- 원격 채팅 + liveness 본인 인증 (isMyFace 신뢰성)
