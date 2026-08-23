# PLAN — 사진의 주인을 사람으로 (GC 철거)

> `PLAN-THUMBNAIL.md` · `PLAN-THUMBNAIL-REGISTRY.md` 를 **대체한다.** 그 둘은
> "GC 가 참조를 반만 센다 → 참조를 더 정확히 세자" 는 같은 전제 위에 서 있었다.
> 이 문서는 그 전제를 버린다.

---

## 0. 한 문장

**썸네일 객체의 수명을 카드(metrics 행)가 아니라 사람(계정)에 묶는다.** 키에
소유자를 박아 넣으면 "누가 이 사진을 참조하는가" 라는 질문 자체가 사라지고,
refcount·아웃박스·레지스트리·고아 스캔이 전부 필요 없어진다.

---

## 1. 오진 — 왜 앞의 두 계획이 실패했나

두 계획서와 현행 코드는 모두 이 질문에 답하고 있었다:

> "누가 이 객체를 참조하는가?"

아무도 이 질문을 안 했다:

> **"애초에 왜 지워야 하는가?"**

지우는 이유는 둘뿐이다.

| 이유 | 실체 |
| --- | --- |
| **비용** | 200×200 q85 JPEG ≈ 10KB. 프로덕션 현재 98개 = **1MB**. R2 $0.015/GB·월 → 10만 장 쌓여도 **월 20원**. **비용은 존재하지 않는다.** |
| **개인정보** | 탈퇴 시 삭제(`privacy.md:24,43`), 90일 미활동 익명 정리. **이게 진짜 이유이자 유일한 이유다.** |

그런데 지금 삭제를 발화시키는 트리거는 전부 **카드 수명**에 걸려 있다 — 재촬영,
카드 삭제, `body` 키 변경. **그중 개인정보 요구인 건 하나도 없다.** 존재하지 않는
비용을 아끼려는 최적화를 위생으로 착각했고, 그 최적화를 안전하게 만들려고
아웃박스와 레지스트리를 쌓았다.

**근본 오진: 사진의 주인을 "카드" 로 봤다. 사진의 주인은 "사람" 이다.**

| 사건 | 사람 관점 | 현행 |
| --- | --- | --- |
| 재촬영 | 같은 사람 → 지울 이유 없음 | 즉시 삭제 |
| 카드 삭제 | 그 사람 여전히 존재 → 지울 이유 없음 | 즉시 삭제 |
| 결제 궁합 | 남의 얼굴 **사본** — 구매가 그 사람의 사진 수명을 연장하지 않는다 | 같은 객체를 몰래 공유 |
| **탈퇴** | 사람이 사라짐 → **전부** 삭제 | 그 사람 metrics 행의 키만 |
| 익명 90일 | 사람이 없음 → 삭제 | 행 기준 |

그리고 **내용 주소화가 공유를 의도적으로 만들어냈다.** 같은 바이트 = 같은 객체.
그 dedup 이 아끼는 건 월 몇 원인데, 대가로 "정확한 refcount 가 없으면 데이터가
죽는 모델" 로 갈아탔다. 레지스트리는 자초한 공유를 방어하는 장치였다.

> **참조를 더 잘 세지 말고, 참조를 만들지 마라.**

### 실제로 난 손실 (기록)

프로덕션 실측 2026-08-22 — 확인 쌍 13개 중 **8개 손상**, R2 404 썸네일 7개.
`purge-orphan-thumbnails.mjs` 가 `metrics` 만 참조로 세어 결제 궁합이 붙들고
있던 키를 지웠다(2026-08-22, `--apply`, 28개 삭제). 배포된 앱의
`supabase_service.dart` 재촬영 즉시 삭제도 같은 맹점을 공유한다.
**소실분은 원본이 없어 복구 불가.** 해당 쌍은 성별 실루엣으로 남는다.

---

## 2. 결정

### D1. 키에 소유자를 박는다

```
key = thumbnails/{owner}/{sha256}.jpg

owner = {user_id}          로그인 사용자 (JWT 에서 서버가 읽는다)
      = anon-{metrics_id}  익명 촬영분
```

불변식 하나: **객체는 정확히 한 소유자에게 속한다. 소유자가 사라지면 prefix 째
사라진다.** 키에 박혀 있어서 어길 방법이 없다.

내용 주소(sha256)의 이점은 전부 유지된다 — 같은 소유자 + 같은 바이트 = 같은 키라
재시도가 멱등하고, 사진이 바뀌면 URL 이 바뀌어 CDN 이 옛 얼굴을 못 내주고,
`immutable` 캐시가 정당하다. **제거되는 건 교차 소유 공유 하나뿐이다.**

### D2. 삭제 트리거는 계정 수명뿐

| 사건 | 동작 |
| --- | --- |
| 재촬영 | **아무것도 안 지운다.** 옛 객체는 같은 소유자 폴더에 남는다 (10KB) |
| 카드 삭제 | **아무것도 안 지운다** |
| 탈퇴 | `LIST thumbnails/{uid}/` → 전량 DELETE. 한 번의 연산, 증명 가능하게 완전 |
| 익명 90일 | 해당 `anon-{metrics_id}/` prefix DELETE |

### D3. 구매는 포인터가 아니라 사본을 만든다

`unlock_compat` 은 두 body 스냅샷을 얼린다. 지금 그 안엔 **사진 주소만** 들어가서
원본이 사라지면 산 사람 화면이 깨진다. 앞으로는 **결제 직후 앱이 두 장을 자기
폴더로 복사**한다.

```
결제 RPC 성공
  → 두 사진을 thumbnails/{내 uid}/{sha256}.jpg 로 PUT
  → 스냅샷 body 의 thumbnailKey 를 내 사본 키로 바꿔 저장
  → 실패하면 기존 pending 큐에 남고 다음 실행이 재시도
```

**앱이 한다.** 이유:
- `unlock_compat` 은 Postgres 함수라 R2 를 못 부른다 — 워커를 두어도 **앱이 불러야
  한다.** 워커 방식도 똑같이 앱 의존이고 실패 창도 같다.
- 앱은 결제 시점에 `aReport`·`bReport` 를 통째로 들고 있고
  (`compatibility_unlock_action.dart:114`) 그 사진을 화면에 띄우고 있다.
  바이트는 로컬 캐시이거나, 없으면 CDN 이 public read 라 GET 하면 된다.
- **재시도 큐가 이미 있다** (`history_provider` 의 `pending_uploads`). 키가 내용
  주소라 몇 번 돌아도 안전하다. 새 엔드포인트·새 인증·새 재시도 로직 0개.

**약속을 지키는 건 "서버가 한다" 가 아니라 "구매 행이 남아 있는 한 앱이 몇 번이고
다시 시도한다" 이다.** 그래서 앱 시작 시 **대조**를 한 번 돈다 — 내 구매 목록 중
사본이 없는 건 그때 복사한다. 구매 행은 `compatibilities` 에 영구히 있으니 근거가
사라지지 않는다.

### D4. presign 이 소유자를 정한다 — 클라이언트가 못 고른다

`thumbnails/` presign 은 `Authorization: Bearer <supabase jwt>` 를 받아
`GET /auth/v1/user` 로 검증하고(`api.account.delete.ts:43` 과 같은 패턴)
**서버가 owner 를 JWT 에서 읽는다.** 남의 폴더엔 쓸 수 없다.

- 토큰이 없으면 익명 경로 — `anon-{metrics_id}` 스코프. 이때만 호출자가 스코프를
  지정하고, 그 값은 unguessable uuid 다.
- 기존 409(이미 있으면 발급 안 함) 검사는 **그대로 둔다.** 익명 스코프와
  구버전 앱 경로의 backstop 이다.
- 배포된 앱은 토큰을 안 보낸다 → 익명 경로로 흘러 정상 동작. 강제 업그레이드
  뒤에 무토큰 thumbnails 분기를 걷어낸다.

### D5. GC 는 전면 철거

`thumbnail_gc` 테이블·트리거·`drainThumbnailGc`·CDN purge·`purge-orphan-thumbnails.mjs`
전부 삭제한다. 대체물을 만들지 않는다 — D1+D2 아래에선 회수할 고아가 구조적으로
생기지 않는다.

익명 prefix 는 R2 lifecycle 이 아니라 **90일 정리 cron 이 prefix DELETE 로**
처리한다. lifecycle 은 객체 나이 기준이라 활동 중인 익명 사용자의 사진까지
지운다.

### D6. 로컬 파일은 순수 캐시 — 단 아직 안 올라간 사진은 예외

서버가 항상 원본을 갖고 있으므로 로컬 캐시는 언제 지워도 안전하다. **단
하나의 예외: 아직 업로드되지 않은 사진.** 현행 스윕은 이걸 못 지킨다.

`_sweepCacheFiles` 의 keep 집합이 `state` 만 본다(`history_provider.dart:474`).
로그아웃이 Hive 를 비운 뒤 첫 부팅이면 keep = ∅ → **documents 의 `*.jpg` 를 전부
지운다.** 그 안에 아직 못 올린 사진이 있으면 다음 `retryPendingUploads` 가
"원본이 없다" 며 키를 버린다 — **그 얼굴은 어디에도 없다.** adopt 맵도 같은 이유로
state 기준 판정이라 박스가 비워진 직후 옛 파일명을 영구히 잊는다.

세 곳을 고친다: keep 에 `pending_uploads`·adopt 를 포함, state 가 비었으면 스윕
자체를 건너뜀, adopt 판정을 state 비의존으로.

---

## 3. 이 브랜치에서 살리는 것

되돌리지 않는다. 전부 이 계획의 전제다.

| 자산 | 이유 |
| --- | --- |
| 내용 주소 해싱 (`ThumbnailPaths.contentKey`) | D1 의 절반. 키 앞에 소유자만 붙인다 |
| `thumbnailPath` 제거 | 사진의 주인이 둘이던 원래 사고의 근본 수정 |
| 업로드 시점 이동 (저장 후) | 중도 포기 고아를 멈춘 유일한 수정 |
| `cdn_thumbnail` 공용 위젯 | 렌더 7곳 통일 |
| presign 409 + fail-closed | 덮어쓰기 backstop |
| 테스트 11개 | 회귀 방어 |

---

## 4. 진행 상태 (2026-08-23)

| 단계 | 상태 |
| --- | --- |
| P0 지혈 | ✅ `drainThumbnailGc` 배선·함수 제거, `purge-orphan-thumbnails.mjs` 삭제 |
| P1 presign 소유자 | ✅ 로컬 워커 실측 5경로 통과 (아래) |
| P2 클라이언트 | ✅ 소유자 키·캐시 생존·익명 재지정. `flutter test` 221 통과 |
| P3 구매 사본 | ✅ 결제 시 복사 + `pairs()` 대조. **실기기 미검증** |
| P4 탈퇴/익명 prefix 삭제 | ✅ 코드 완료. **실계정 미검증** |
| P5 GC 철거 | ✅ `0005_thumbnail_ownership.sql`. **SQL Editor 수동 적용 대기** |
| P6 문서 | ✅ 3 SSOT + `privacy.md` + 옛 PLAN 2건 폐기 |

**P1 실측** (`pnpm build && wrangler dev`, 2026-08-23):

| 요청 | 결과 |
| --- | --- |
| `{hash}` 토큰X scope X | `thumbnails/c0/{sha}.jpg` — 레거시 경로 유지 |
| `{hash, scope: anon-…}` | `thumbnails/anon-…/{sha}.jpg` |
| `{hash}` + 위조 Bearer | **401** — 익명으로 흘러내리지 않는다 |
| `{hash, scope: "{남의 uid}"}` | 스코프 무시 → 레거시 키. **남의 폴더에 못 쓴다** |
| `{uuid}` (배포된 앱) | `thumbnails/202608/{uuid}.jpg` — 정상 |

> `wrangler dev` 는 빌드를 하지 않는다 — `pnpm build` 를 먼저 돌리지 않으면
> 낡은 번들을 검증하게 된다. 처음에 이걸로 한 번 헛짚었다.

**남은 배포 순서**: `0005` SQL 수동 적용 → `pnpm build && wrangler deploy` →
앱 배포. P5 를 먼저 적용해도 무해하다 (트리거만 사라지고 아무도 안 지운다).

---

## 5. 단계

### P0 — 지혈 (먼저, 단독 커밋)

**대상**: `web/workers/app.ts`, `web/workers/cron.ts`, `web/scripts/purge-orphan-thumbnails.mjs`

1. `app.ts` 의 `drainThumbnailGc` 배선 제거 + import 제거.
2. `cron.ts` 의 `drainThumbnailGc`·`purgeCdnCache` 함수 제거, 헤더 주석 정정.
3. `purge-orphan-thumbnails.mjs` **파일째 삭제.** 이미 실제 손실 7장을 낸
   도구다 — 주석으로 막아 두는 건 다음 사람에게 지뢰를 넘기는 것.

**검증**: `grep -rn "thumbnail_gc\|purgeCdnCache" web/workers web/app` → 0건.
web 을 지금 배포해도 R2 에서 아무것도 지워지지 않는다.

### P1 — presign: 소유자 스코프

**대상**: `web/app/routes/api.r2.presign.ts`

1. `thumbnails` prefix 요청이 `Authorization` 헤더를 갖고 있으면
   `GET {SUPABASE_URL}/auth/v1/user` 로 검증해 `owner = user.id`.
2. 토큰이 없으면 요청의 `scope`(= `anon-{metrics_id}`) 를 쓴다. 형식 검증
   (`^anon-[0-9a-f-]{36}$`). 둘 다 없으면 기존 uuid/hash 경로로 폴백 —
   배포된 앱이 깨지지 않게.
3. `buildKey`: `thumbnails/{owner}/{sha256}.{ext}`.
4. 409 존재 검사는 유지.

**검증**: 토큰 있는 요청 → 키에 uid. 남의 uid 를 body 로 보내도 무시되는지.
토큰 없는 구버전 요청(`{prefix,uuid}`) 이 여전히 200 인지.

**되돌리기**: 라우트 단독 롤백. 저장된 키에 영향 없음.

### P2 — 클라이언트: 소유자 스코프 업로드 + 캐시 생존

**대상**: `r2_uploader.dart`, `thumbnail_paths.dart`, `info_confirm_screen.dart`,
`history_provider.dart`

1. `R2Uploader.presign/upload` 가 `Authorization` 헤더를 싣는다(로그인 시).
   비로그인이면 `scope: anon-{supabaseId}`.
2. 키 조립은 **서버 응답의 `key` 를 그대로 쓴다** — 클라이언트는 더 이상 최종
   키를 계산하지 않는다. `contentKey` 는 해시 계산 + 로컬 파일명 용도로 남는다.
3. 로컬 캐시 파일명은 계속 `basename(key)` = `{sha256}.jpg` — 소유자가 붙어도
   basename 이 안 바뀌므로 **기존 파일이 그대로 잡힌다. 이관 없음.**
4. D6 세 곳 수정 (keep 집합·빈 state 스윕 차단·adopt 판정).
5. 익명 → 로그인 claim 시 사진을 내 스코프로 재업로드하고 body 키를 갱신
   (`_claimAnonymousMetrics` 뒤). 로컬 캐시 파일이 원본이다.

**검증**: 로그아웃 → 로그인 왕복 후 사진 생존(신규 회귀 테스트).
비행기 모드에서 촬영 → 재부팅 → 파일·키 생존 → 온라인 복귀 시 업로드.
`flutter analyze` 0, `flutter test` 통과.

### P3 — 구매 사본

**대상**: `compatibility_unlock_action.dart`, `compatibility_service.dart`,
`history_provider.dart`

1. `unlock()` RPC 성공 직후 두 사진을 내 스코프로 복사 (로컬 캐시 → 없으면 CDN GET).
2. 복사된 키로 `a_body`/`b_body` 의 `thumbnailKey` 를 바꿔 RPC 에 넘긴다.
   **RPC 호출 전에 복사가 끝나야** 스냅샷이 처음부터 내 사본을 가리킨다.
   복사 실패 시엔 원본 키로 진행하고 대조에 맡긴다 (결제를 막지 않는다).
3. 앱 시작 시 대조 — `pairs()` 의 각 면에 대해 내 스코프 사본이 없으면 복사 +
   스냅샷 키 갱신. 기존 `retryPendingUploads` 옆에 붙인다.

**검증**: 구매 → 상대가 재촬영·카드 삭제 → 확인 탭 사진 생존.
복사 실패를 강제 주입 → 재시작 → 대조가 복구하는지.

### P4 — 탈퇴·익명 정리를 prefix 삭제로

**대상**: `web/app/routes/api.account.delete.ts`, `web/workers/cron.ts`

1. 탈퇴: metrics DELETE 전에 `LIST thumbnails/{uid}/` → 전량 DELETE.
   **추가로** 그 사용자 metrics 행의 `thumbnailKey` 중 소유자 스코프가 아닌
   레거시 키도 함께 지운다 (구키 객체가 prefix 에 안 잡힌다).
2. `cleanupStaleMetrics`: 지우는 행마다 `anon-{id}/` prefix DELETE.

**검증**: 테스트 계정 탈퇴 → `LIST thumbnails/{uid}/` 0건 + 레거시 키 404.
그 사람 얼굴을 산 다른 계정의 확인 탭은 그대로인지 (**핵심 회귀**).

### P5 — GC 스키마 철거

**대상**: `web/db/migrations/0005_drop_thumbnail_gc.sql`(신규)

`metrics_thumbnail_gc` 트리거 · `queue_thumbnail_gc()` 함수 · `thumbnail_gc`
테이블 DROP. idempotent(`if exists`), 적용은 SQL Editor 수동.
`0004_thumbnail_gc.sql` 은 **삭제하지 않는다** — 이미 적용된 이력이다.

**검증**: 트리거 목록에서 사라졌는지, 카드 삭제가 정상인지.

### P6 — 문서

- `flutter/docs/ARCHITECTURE.md` · `flutter/docs/HOW-IT-WORKS.md` ·
  `web/docs/HOW-IT-WORKS.md` — 키 형태, 삭제 모델, cron 잡 목록
- `web/public/privacy.md` — 24·43 줄에 "타인이 구매한 궁합에 포함된 사본 제외"
  한 줄. 27 줄(구매분 영구 이용)과의 모순 해소
- `PLAN-THUMBNAIL.md` · `PLAN-THUMBNAIL-REGISTRY.md` 삭제 (이 문서가 대체)

---

## 6. 사라지는 것

| 대상 | 지금 |
| --- | --- |
| `thumbnail_gc` 테이블 + 트리거 + 함수 | 3개 오브젝트 |
| `drainThumbnailGc` + `purgeCdnCache` | ~120줄 |
| `purge-orphan-thumbnails.mjs` | 128줄 (손실 유발 도구) |
| 참조 계수 (LIKE full scan) | 키당 2회 |
| `last-modified` 부활 휴리스틱 | 409 레이스 포함 |
| 레지스트리 (검토만 하고 안 만듦) | 테이블 2 + 트리거 2 + 백필 |
| CDN 퍼지 한도 관리 | 전부 |
| 고아 개념 | 구조적으로 생기지 않음 |

## 7. 남는 위험 (정직하게)

1. **결제 후 복사 전에 앱이 죽고, 그 사용자가 다시 앱을 안 켜는 동안 원본 주인이
   재촬영·탈퇴** — 창은 좁고, 워커 방식으로도 못 막는다. 대조가 유일한 방어이고
   그건 앱 실행을 전제한다. 서버측 대조 cron 은 나중에 독립적으로 얹을 수 있다.
2. **레거시 키(`YYYYMM/{uuid}` · `{2hex}/{sha256}`)** 는 소유자 prefix 에 안
   잡힌다. P4-1 의 명시 삭제로 덮지만, 그 키를 가리키는 **구매 스냅샷**은 원 주인이
   탈퇴하면 깨진다. P3 대조가 앞으로 나아가며 고쳐준다.
3. **이미 소실된 7장은 복구 불가.**
4. **저장 비용 증가** — dedup 포기 + 재촬영분 잔존. 실측 기준 무시 가능(월 20원대).
