# PLAN — 썸네일 저장 구조 정리 (내용 주소 키 + 참조 기반 회수)

관상 카드의 얼굴 사진이 아이콘으로 떨어지는 사고가 났다. 직접 원인은
`syncFromServer` 의 병합 규칙이었지만, 그 규칙이 존재한 이유는 **한 장의 사진에
주인이 둘(로컬 파일 포인터 `thumbnailPath` / R2 키 `thumbnailKey`)이고, 어느 쪽이
진실인지 동기화 코드가 매번 판정**해야 했기 때문이다.

원인 자체는 이미 막혀 있다(아래 "현재 트리 상태"). 이 문서는 그 이중 소유를
구조적으로 없애고, 점검 중 드러난 **두 개의 실제 문제**를 함께 처리하는 계획이다.

> 🔴 **점검에서 나온 두 문제 — 이 리팩터링과 무관하게 지금 존재한다.**
>
> 1. **남의 썸네일 덮어쓰기가 가능하다.** `/api/r2/presign` 에 인증이 없고
>    (`api.r2.presign.ts:23~52`) 키를 클라이언트가 지정한다. 피해자 키는 공유
>    링크 `/r/{uuid}` 의 og:image 에 그대로 노출된다. 같은 달 안이면 그 키에 대한
>    PUT URL 을 누구나 발급받아 임의 이미지로 바꿔치기할 수 있다.
> 2. **주인 없는 얼굴 이미지가 영구히 쌓인다.** `analyze()` 는 정면 캡처 직후
>    썸네일을 R2 에 올린다(`face_metadata_client.dart:85~99`). 사용자가 그 다음
>    "정보 확인" 화면에서 취소하면 행이 생기지 않는다. **분석을 중도 포기할
>    때마다 200×200 얼굴 이미지가 소유자 없이 남고**, 소유자가 없으니 탈퇴에도
>    90일 정리에도 안 걸린다. 개인정보 방침과 어긋난다.

---

## 결정

### D1. 카드의 사진 필드는 하나, 로컬 파일은 그 필드의 함수

`metrics.body.thumbnailKey` 가 사진의 유일한 필드다.
`FaceReadingReport.thumbnailPath` 는 제거한다. 로컬 파일은 **키에서 이름이
파생되는 캐시**가 된다.

```
로컬 파일 = documents/{basename(thumbnailKey)}
```

키가 바뀌면 파일명도 바뀐다. 그래서 "이 사진의 주인이 누구인가" 라는 질문이
성립하지 않는다 — 파일은 키를 따라갈 뿐이다. 동기화가 조건 없이 서버 승이어도
로컬 파일을 그대로 찾는다.

**이관 비용이 없다.** 지금 로컬 파일은 `{A}.jpg`, 키는 `thumbnails/YYYYMM/{A}.jpg`
로 이미 basename 이 같다(둘 다 분석 uuid A 에서 나왔다). 키만 남겨도 기존 파일이
그대로 잡힌다.

렌더는 **로컬 파일 → CDN → 아이콘** 순서를 유지한다. 예전과 글자는 같지만 의미가
다르다 — 로컬이 "또 하나의 진실"이 아니라 키의 캐시라서 우선해도 모호함이 없다.

### D2. 키는 내용 주소, 클라이언트가 계산한다

```
클라이언트: h = sha256(200×200 jpeg bytes) → hex
키:         thumbnails/{h[0:2]}/{h}.jpg
presign:    { prefix: "thumbnails", hash: h } → 서버가 같은 규칙으로 조립
```

- **같은 바이트 → 같은 키.** 재시도·백필이 멱등해진다. 같은 바이트를 덮어쓰는
  것이라 PUT 은 언제나 안전하다 — **존재 확인 후 생략은 하지 않는다.** HEAD 가
  200 을 준 직후 회수 잡이 그 객체를 지우면 뒤이어 저장된 행이 빈 곳을 가리킨다.
- **다른 바이트 → 다른 URL.** 캐시 무효화 문제가 생기지 않는다. 그래서
  `Cache-Control: public, max-age=31536000, immutable` 이 비로소 정당해진다.
- **클라이언트가 키를 계산할 수 있다는 점이 D1 을 성립시킨다.** 업로드 응답을
  기다리지 않고 파일명을 정할 수 있어 별도 대기열이 필요 없다.

**presign 은 `thumbnails/` 에 대해 이미 존재하는 객체면 PUT URL 을 발급하지 않고
409 + `{key, publicUrl}` 을 돌려준다.** 위 문제 ①의 차단이다. 내용 주소에서
"이미 있다"는 곧 "같은 바이트가 저장돼 있다"는 뜻이므로 클라이언트는 이를 성공으로
취급한다. 내용 주소로 가면 현재의 월 단위 장벽이 사라지므로 이 검사는 **선택이
아니라 필수**이며, `uuid` 형태 요청에도 똑같이 적용해야 한다 — 공격자는 어느
형태든 골라 쓸 수 있기 때문이다.

**presign 은 `hash` 없는 요청도 계속 받는다.** 배포된 앱은 `{prefix, uuid}` 를
보낸다(`r2_uploader.dart:63`). 400 으로 막으면 그 버전 사용자들의 새 카드가 서버
썸네일 없이 남아 공유 og:image 와 다른 기기 아바타가 깨진다. `hash` 가 오면 내용
주소로, 안 오면 `thumbnails/{YYYYMM}/{uuid}.jpg` 로 조립한다. 강제 업그레이드를
태운 뒤 uuid 분기를 걷어낸다.

> 순수 sha256 이라 같은 바이트를 가진 제3자가 키를 계산해 존재를 확인할 수 있다.
> 우리 파이프라인이 만든 crop 바이트와 정확히 일치해야 해서(ML Kit bbox + Flutter
> 인코더) 재현이 사실상 어렵고, 덮어쓰기는 위 존재 검사로 막힌다. 이 약점을 감수하는
> 대신 대기열·이관 단계가 통째로 사라진다.

**트레이스 규칙 갱신**: `web/docs/HOW-IT-WORKS.md:68` 의 "1 face capture = 1 UUID"
는 `temp/{uuid}` · `metrics.id` · `/r/{uuid}` 에 대해 그대로 유지한다. 문서 문장을
다음으로 고친다:

> 1 capture = 1 trace uuid (temp·metrics.id·/r), 1 image = 1 content key.

### D3. 고아를 줍지 말고 만들지 않는다

문제 ②의 처방은 회수 잡이 아니라 **업로드 시점 이동**이다.

```
지금:  정면 캡처 → 크롭 → R2 PUT → (사용자 확인) → 행 저장
                     ↑ 여기서 취소하면 객체만 남는다

이후:  정면 캡처 → (사용자 확인) → 행 저장 → 크롭 → R2 PUT
```

썸네일 업로드를 `analyze()` 에서 떼어 **저장 경로로 옮긴다.** 중도 포기 시
남는 것은 `temp/` 뿐이고 그건 이미 lifecycle 1일로 사라진다.

부수 효과가 크다. 지금은 `analyze()` 가 R2 용으로 한 번, `info_confirm` 이 로컬
파일용으로 한 번, **촬영마다 얼굴 검출 + 200×200 crop 을 두 번** 한다. 업로드를
저장 경로로 옮기면 한 번의 crop 결과를 로컬 파일과 업로드가 함께 쓴다.

업로드 실패는 `pending_uploads`(prefs 의 키 Set — 카드 필드가 아니다)에 남기고
앱 시작 시 재시도한다. 키가 내용 주소라 재시도가 멱등하다.

### D4. 참조가 끊긴 객체는 아웃박스가 회수한다

지금 R2 삭제 코드는 **네 곳**에 흩어져 있다 — `saveMetrics`(재촬영 교체),
`api.r2.delete.ts`(클라이언트 호출), `api.account.delete.ts`(탈퇴),
`cron.ts cleanupStaleMetrics`(익명 90일). 전부 "행을 지우기 전에 키를 챙겨야
한다"는 순서 제약을 각자 지키고, 클라이언트 경로는 재시도가 없다.

**transactional outbox** 하나로 모은다.

```sql
metrics AFTER DELETE                    ─┐
metrics AFTER UPDATE OF body (키 변경)   ─┴─► thumbnail_gc(key, queued_at, attempts)

cron drain:
  다른 행이 이 key 를 참조     → 큐에서만 제거 (공유 객체)
  객체 mtime > queued_at       → 큐에서만 제거 (그 사이 새로 올라옴)
  그 외                        → R2 DELETE + 캐시 퍼지 → 큐에서 제거
```

- 행 삭제와 **같은 트랜잭션**에서 적재된다 → 유실이 없다. 외부 큐로는 못 하는 것.
- 실패하면 다음 실행이 재시도한다.
- 참조 검사가 곧 refcount → 두 행이 한 객체를 가리켜도 안전.
- 클라이언트는 R2 를 지우지 않는다 → 소유 검증·토큰 왕복이 사라진다.

D3 로 신규 고아가 멈추므로 **상시 전수 스캔 잡은 만들지 않는다.** 이미 쌓인
고아는 1회 정리 스크립트로 처리한다(P3).

### D5. 동기화 병합은 서버 승

`thumbnailPath` 가 모델에서 빠지면 비교할 로컬 사실이 없다.
`mergeServerRow` 의 이월 규칙을 지운다.

---

## 현재 트리 상태 (선행 완료분)

사고를 멈춘 변경이 이미 들어가 있다 — **되돌리지 않는다.**

| 파일 | 내용 |
| --- | --- |
| `history_provider.dart` | 병합이 로컬 `thumbnailPath` 를 항상 이월 + `mergeServerRow` 분리 |
| `physiognomy_screen.dart` | 폴백 아이콘 `Center` 정렬 (`FaIcon` 은 SizedBox·Center 가 없는 위젯) |
| `supabase_service.dart` | `saveMetrics` 가 `report` 를 변형하지 않음. body 의 키만 교체 |
| `info_confirm_screen.dart` | 저장 전에 `myFaceRow()` 로 row id + 썸네일 키를 함께 물려받음 |
| `compatibility_unlock_action.dart` | 주석 정정 |
| `test/history_merge_thumbnail_test.dart` | 회귀 테스트 5개 |

P4 에서 첫 줄과 마지막 줄이 함께 정리된다.

---

## 진행 상태 (2026-08-22)

| 단계 | 상태 |
| --- | --- |
| P1 presign | ✅ 코드 완료·로컬 워커로 실측. **배포 대기** |
| P2 클라이언트 | ✅ 코드 완료. 실기기 촬영 미검증 |
| P3 아웃박스 | ⚠️ 코드 완료. **마이그레이션 미적용** (로컬에 psql·supabase CLI 없음 → Supabase SQL 에디터에서 실행 필요) |
| P3-4 1회 정리 | ✅ 실행함 — 객체 98개 중 **고아 28개 삭제**, 재스캔 0개 (2026-08-22) |
| P4 thumbnailPath 제거 | ✅ 코드 완료 |
| P5 문서 | ✅ 3 SSOT 갱신 |

**계획에서 틀렸던 것**: `main.dart` 의 `ThumbnailPaths.initCache()` 는 그대로 둔다.
로컬 캐시 파일을 계속 쓰므로 documents 경로 해석이 여전히 필요하다 —
`thumbnail_paths.dart` 는 줄지 않고 오히려 늘었다(`contentKey`·`cacheFileSync`·
`sweepCache`). 줄어든 것은 카드가 들고 다니던 필드와 그 필드를 지키던 규칙이다.

**추가된 것**: 사진 필드가 하나가 되기 전에 저장된 키 없는 카드는 파일명이 Hive
JSON 의 `thumbnailPath` 에만 남아 있다. `_rememberFileToAdopt` 가 로드 중 그
이름을 건지고 `retryPendingUploads` 가 파일을 해시해 키로 바꾼 뒤 파일명을
키에 맞춰 옮긴다. 이 회수가 없으면 아직 못 올린 사진이 이름을 잃는다.

---

## 단계

**단계 간 의존은 P2 → P4 하나뿐이다.** P3(아웃박스)는 키 형태와 무관하게 body 에서
키를 읽으므로 언제 넣어도 된다. 아래 순서는 위험이 큰 것부터다.

### P1 — presign: 덮어쓰기 차단 + 내용 주소 + 캐시 계약

**대상**: `web/app/routes/api.r2.presign.ts`, `api.r2.delete.ts`

1. **`prefix === "thumbnails"` 이면 발급 전에 객체 존재를 확인하고, 있으면
   409 + `{key, publicUrl}`.** (문제 ① 차단. `temp/` 는 대상 아님.)
2. `parseBody` 가 `hash`(64자 hex)를 **선택 필드로** 받는다. 있으면
   `thumbnails/{h[0:2]}/{h}.jpg`, 없으면 `thumbnails/{YYYYMM}/{uuid}.jpg`.
3. 응답에 `cacheControl: "public, max-age=31536000, immutable"` 을 실어 클라이언트가
   PUT 헤더로 보내게 한다. SigV4 query signing 은 host 만 서명하므로 헤더 추가에
   서명 변경이 없다.
4. `api.r2.delete.ts:34` 정규식에 새 키 형태를 추가한다. (P3 에서 이 라우트 자체를
   걷어낸다.)

**검증**: 같은 hash 로 두 번 presign → 두 번째 409. 다른 hash → 정상 발급.
`uuid` 만 보내는 요청이 여전히 200 인지(배포된 앱 경로).

**되돌리기**: 라우트 단독 롤백. 저장된 키에 영향 없음.

### P2 — 클라이언트: 크롭 1회, 저장 후 업로드, 내용 주소 키

**대상**: `r2_uploader.dart`, `face_metadata_client.dart`, `info_confirm_screen.dart`,
`history_provider.dart`, `web/app/lib/join.ts`

1. `analyze()` 에서 **썸네일 crop + 업로드를 들어낸다.** `/analyze` 호출까지만
   책임진다 (temp/ 업로드는 분석 입력이므로 그대로). `FaceMetadata` 의
   `thumbnailUrl`·`thumbnailKey` 는 소비처가 없어지므로 함께 제거.
2. `info_confirm` 의 저장 경로가 crop 을 한 번 수행하고, 그 바이트로
   - `h = sha256(bytes)` → `report.thumbnailKey = thumbnails/{h[0:2]}/{h}.jpg`
   - `documents/{h}.jpg` 로 로컬 파일 저장
   - 행 저장 후 백그라운드 업로드. 실패하면 `pending_uploads` 에 키 적재.
3. `R2Uploader.presign/upload` 가 `hash` 를 받는다. `crypto: ^3.0.7` 이 이미
   의존성에 있다 — `sha256.convert(bytes).toString()`. **409 는 성공으로 취급.**
   `putBytes` 가 `Cache-Control` 헤더를 함께 보낸다.
4. `backfillThumbnailIfMissing` → `retryPendingUploads` 로 성격을 바꾼다.
   **여기서 기존 키 결함이 해소된다** — 지금은 `uuid: report.supabaseId`(행 id)로
   올려서, 같은 달에 두 번 백필하면 동일 키를 덮어써 CDN 이 옛 이미지를 계속
   서빙한다. 내용 주소에서는 구조적으로 불가능하다.
5. `web/app/lib/join.ts:24` 도 같은 방식으로 (행 id → 해시).

**검증**: 정보 확인 화면에서 취소 → `thumbnails/` 에 아무것도 안 생기는지(문제 ②).
같은 사진 두 번 등록 → 객체 1개. 재촬영 → 다른 키. 촬영 1회당 얼굴 검출 1회인지
로그 확인. `flutter analyze` 0, `flutter test` 통과.

**되돌리기**: 클라이언트 롤백. 올라간 해시 키 객체는 그대로 유효.

### P3 — 삭제 경로를 아웃박스 하나로

**대상**: `web/db/migrations/0004_thumbnail_gc.sql`(신규), `web/workers/cron.ts`,
`api.account.delete.ts`, `api.r2.delete.ts`, `supabase_service.dart`

1. 마이그레이션 — 새 테이블 하나. 기존 테이블에 컬럼 추가는 없다.
   ```sql
   create table public.thumbnail_gc (
     key       text        primary key,
     queued_at timestamptz not null default now(),
     attempts  smallint    not null default 0
   );
   ```
   `after delete or update of body on metrics` 트리거 + `security definer` 함수.
   **`body` 는 `text` 다**(`0001_baseline.sql:164`) — `::jsonb` 캐스팅이
   깨진 body 에서 예외를 던지면 **그 행의 DELETE 자체가 실패한다.** 반드시
   예외를 삼켜 회수 실패가 행 삭제를 막지 않게 한다.
   `anon`·`authenticated` 는 전면 차단, `service_role` 만 접근. 0003 의 grant
   누락 사고를 반복하지 않도록 **파일 끝에 세 롤 권한 확인 쿼리**를 둔다.
2. cron 에 `drainThumbnailGc` 추가 — D4 의 세 갈래 판정. 배치 상한을 두고 남으면
   다음 실행이 잇는다. Cloudflare purge-by-URL 호출 한도에 배치 크기를 맞춘다.
3. 다음을 걷어낸다:
   - `supabase_service.dart` 의 R2 삭제 분기 + accessToken 왕복
   - `r2_uploader.dart:130` `deleteObject`
   - `api.r2.delete.ts` 라우트 전체
   - `api.account.delete.ts` 의 R2 루프 (행 삭제만 남김 — 트리거가 받는다)
   - `cron.ts cleanupStaleMetrics` 의 R2 루프 (같은 이유)
4. **1회 정리 스크립트** — 이미 쌓인 고아(중도 포기분)를 처리한다. service_role 로
   `metrics` 를 페이지 단위로 훑어 참조 키 집합을 만들고, `thumbnails/` 를 LIST 해
   미참조 + 7일 경과 객체를 지운다. 상시 잡이 아니라 1회 실행 도구다 (D3 로 신규
   고아가 멈추므로).

**검증**: 카드 1장 삭제 → `thumbnail_gc` 적재 확인 →
`curl "localhost:8787/__scheduled?cron=0+18+*+*+*"` → 객체 404.
공유받은 카드가 같은 키를 참조 중이면 객체가 살아남는지.
body 가 깨진 행을 하나 심어두고 DELETE 가 정상 동작하는지.

**되돌리기**: cron 잡 비활성화. 트리거는 남겨도 무해(큐만 쌓임).

### P4 — `thumbnailPath` 제거

**선행 조건**: P2 가 배포되어 신규 카드가 내용 주소 키를 갖고, `pending_uploads`
재시도가 돌고 있을 것.

**서버 `metrics.body` 는 무관하다** — `toBodyJson` 이 처음부터 제외해 왔다
(`face_reading_report.dart:278~284`). 지우는 대상은 앱 안쪽 4종뿐이다.

1. `face_reading_report.dart:210` 필드, `:258` 생성자 파라미터
2. `:323` `toJsonString()`(Hive 저장용), `:493` `fromJsonString()` 파싱
3. `'thumbnailPath': null` override 4곳 — `compatibility_service:106,165` ·
   `share_receive_service:51` · `history_provider:39`. 필드가 사라지면 방어할
   대상 자체가 없어진다.
4. 로컬 파일 조회를 `documents/{basename(thumbnailKey)}` 파생으로 교체 (D1).
   기존 파일은 이름이 이미 일치하므로 별도 이관이 없다.
5. 키가 없고 로컬 파일만 있는 카드(오래 오프라인이던 기기) — 파일을 sha256 해
   키를 만들고 `pending_uploads` 에 넣는다. **재시도 잡이 곧 이관이다.**
6. `mergeServerRow` 의 이월 규칙 제거 (D5).
7. 렌더 7곳을 공용 위젯으로 통일 — `physiognomy_screen:328`, `detail_avatar:35`,
   `my_face_header:138`, `team_reveal_screen:197`, `report_page:1728`,
   `compatibility_screen:1435`, `compatibility_detail_screen:822`.
   CDN 경로는 `CachedNetworkImage`(이미 의존성에 있음).
8. `thumbnail_paths.dart` 68줄 → `cdnUrl` + basename 파생만 남김.
9. 어떤 카드의 키와도 이름이 맞지 않는 Documents 의 `*.jpg` 정리 (캐시 축출).

**검증**: 오프라인 상태에서 앱 재시작 → 로컬 캐시로 렌더되는지. 키만 있고 파일이
없는 카드(서버 복원분) → CDN 렌더. 5번 경로를 재현해 사진이 살아남는지.
`flutter test` 전체 통과.

**되돌리기**: 단독 롤백이 껄끄럽다. P2 배포 후 재시도가 안정된 뒤 시작한다.

### P5 — 문서

- `flutter/docs/ARCHITECTURE.md` — 213줄 3단 설명, 228줄 R2 키 형태
- `flutter/docs/HOW-IT-WORKS.md` — 236줄 `thumbnailPath` 행 제거
- `web/docs/HOW-IT-WORKS.md` — 39줄 키 경로, 65줄 unguessable 성질,
  68줄 trace 규칙, 12줄 cron 잡 목록, 업로드 시점 이동(D3)
- 이 문서에 적용일과 1회 정리 스크립트가 지운 고아 개수를 기록

---

## 이 계획으로 사라지는 것

| 대상 | 지금 |
| --- | --- |
| 얼굴 검출 + crop | 촬영마다 2회 → 1회 |
| 중도 포기 시 남는 얼굴 이미지 | 영구 → 없음 |
| 남의 썸네일 덮어쓰기 | 같은 달 안에서 가능 → 불가 |
| R2 삭제 경로 | 4곳 → 1곳(cron drain) |
| 클라이언트 R2 삭제 + 소유 검증 | 전부 |
| 렌더 분기 | 7곳 제각각 → 공용 위젯 1개 |
| `FaceReadingReport.thumbnailPath` | 필드 + 직렬화 2곳 + override 4곳 |
| `thumbnail_paths.dart` | 68줄 → ~20줄 |
| 병합 소유권 판정 | 전부 |

---

## 배포된 앱에 미치는 영향

| 단계 | 배포된 앱 | 저장된 데이터 | 사용자 체감 |
| --- | --- | --- | --- |
| P1 | `uuid` 요청을 계속 받으므로 정상. 단 **백필 재시도가 409 를 받는 경우**가 생긴다(같은 달에 이미 올린 키) — 예외로 잡혀 로그만 남고, 원래 하던 "같은 이미지 덮어쓰기"가 안 될 뿐이다 | 무영향 | 없음 |
| P2 | 무영향 (자기 버전만) | 무영향 | 없음 |
| P3 | `api.r2.delete.ts` 제거 시 구버전 호출이 404 → fire-and-forget 이라 로그만. 회수는 트리거가 대신함 | 무영향 | 없음 |
| P4 | 무영향 | Hive 의 옛 `thumbnailPath` 키는 안 읽으면 그만 | 없음 (파일명이 키 basename 과 일치) |

---

## 판단이 필요한 것

1. **공유받은 카드**: 원 소유자가 카드를 지우면 아웃박스가 객체를 회수하고,
   북마크한 사람 화면에서 그 얼굴이 아이콘이 된다. 개인정보 방침("사용자가
   직접 삭제") 상 맞는 동작이라고 보지만 제품 결정이다.
2. **`temp/` 는 uuid 유지**: 1일 lifecycle 로 사라지고 분석 추적에 uuid 가
   필요하므로 내용 주소로 바꾸지 않는다.
3. **캐시 퍼지 한도**: Cloudflare purge-by-URL 은 요금제별 호출 한도가 있다.
   drain 배치 크기를 여기에 맞춘다.
