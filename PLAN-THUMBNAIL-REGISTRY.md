# PLAN — 썸네일 참조 레지스트리 (구매분 보존 · GC 판단 정정)

`PLAN-THUMBNAIL.md` 의 후속. 그 계획으로 관상 탭 아바타는 고쳤지만, 궁합 **확인
탭**에서 같은 증상이 다시 나왔다. 조사 결과 이건 백필 누락이 아니라 **서버측
데이터 손실**이었고, 원인은 GC 의 참조 계수가 반쪽이라는 것이었다.

이 문서는 (1) 무엇이 왜 깨졌는지, (2) 현재 GC 의 판단 로직 전체, (3) 내용 주소
전환이 만든 새 결함, (4) 참조 레지스트리 제안을 담는다.

> **상태: 진단 완료 · 설계 제안 · 구현 미착수.**
> 아래 "결정이 필요한 것" 이 정리되기 전에는 P 단계를 시작하지 않는다.

---

## 0. 한 문장 요약

**R2 썸네일 객체의 생사를 `metrics` 테이블 혼자 결정한다.** 그런데 결제된 궁합
스냅샷(`compatibilities.a_body`/`b_body`)도 같은 키를 붙들고 있고, 아무도 그걸
세어주지 않는다. 그래서 내 관상을 재등록하면 이미 팔린 궁합의 얼굴이 사라진다.

---

## 1. 증상과 실측

궁합 탭은 데이터 출처가 둘이라 탭마다 원인이 다르다.

| 탭 | 출처 | 판정 |
| --- | --- | --- |
| 미확인 | `historyProvider` (`compatibility_screen.dart:106`) — 관상 탭과 **같은 로컬 리포트** | 기기 문제. 원인·자가치유 모두 관상과 동일 |
| 확인 | `compatibilities` 스냅샷 (`compatibility_service.dart:153` `_decodeSide`) — 로컬 무의존 | **서버 데이터 손실. 버그** |

프로덕션 실측 (2026-08-22):

```
metrics 58행 → thumbnailKey 58개
compatibilities 13행 → 스냅샷 키 22개 (2면은 키 없음)

metrics 가 참조하지 않는 compat 키: 9개
  그중 R2 에 실제로 없음(404): 7개
metrics 도 함께 참조하는 compat 키 중 404: 0개
```

쌍별:

```
2026-07-18  a=404  b=404     ← 깨짐
2026-07-28  a=OK   b=404     ← 깨짐
2026-08-05  a=404  b=OK      ← 깨짐 ×4
2026-08-06  a=키없음 b=404    ← 깨짐 ×2
그 외 5쌍 정상

확인 쌍 13개 중 8개 손상
```

`a=404` 가 08-05 에 몰린 게 지배적 시나리오를 보여준다 — 삭제가 아니라 **재등록**.

```
내 관상 재등록 → 고정 row id 라 같은 행의 body 만 교체
              → 트리거가 옛 키를 큐에 넣음
              → drain 의 참조 검사: metrics 어디에도 없음  ✓ 없는 게 맞다
              → 삭제
              → 그 키를 붙들고 있던 결제 완료 궁합이 얼굴을 잃는다
```

### 누가 지웠나

같은 맹점을 세 곳이 공유했다: 옛 클라이언트 `deleteObject`, 옛
`cleanupStaleMetrics` 의 R2 루프(둘 다 `PLAN-THUMBNAIL.md` P3 에서 제거됨),
그리고 **`web/scripts/purge-orphan-thumbnails.mjs`**
(`referencedKeys()` 가 `metrics` 만 훑는다 — `scripts/purge-orphan-thumbnails.mjs:62`).

2026-08-22 에 그 스크립트를 `--apply` 로 돌려 고아 28개를 지웠다. dry-run 로그에
남은 키 중 `thumbnails/202607/6713a373-…jpg` 가 현재 404 목록의 첫 줄과 일치한다.
**최소 한 개는 이 스크립트가 지웠고, 나머지도 같은 판정 기준을 통과했다.**
`PLAN-THUMBNAIL.md` 의 "재스캔 0개" 는 "고아가 남지 않았다" 는 뜻이었을 뿐,
지운 것이 정말 고아였는지는 검증하지 않았다.

> 소실된 7개는 원본이 없어 복구 불가. 해당 궁합 8쌍은 성별 실루엣으로 남는다.
> 이 문서의 목적은 복구가 아니라 **재발 차단**이다.

---

## 2. 현재 GC 의 판단 로직 (전체)

### 2-1. 큐에 넣는 판단 — 트리거

`web/db/migrations/0004_thumbnail_gc.sql`, `queue_thumbnail_gc()`

```sql
after delete or update of body on public.metrics
for each row
```

발화 조건 자체가 첫 필터다. `update OF body` 라 `alias`·`views`·`is_my_face` 만
바뀌는 UPDATE 는 트리거가 아예 안 뜬다. (Postgres 는 컬럼이 SET 목록에 *언급*되면
값이 같아도 발화하므로, 안쪽에 값 비교가 또 있다.)

발화 후:

| 순서 | 조건 | 결정 |
| --- | --- | --- |
| ① | `old.body::jsonb` 캐스팅 실패 | `return null` — **회수 포기, DML 은 통과** |
| ② | `old_key IS NULL` | 큐에 안 넣음 |
| ③ | UPDATE 이고 `new_key IS NOT DISTINCT FROM old_key` | 큐에 안 넣음 (키 그대로) |
| ④ | 그 외 | `insert into thumbnail_gc(key) … on conflict do nothing` |

①이 예외를 삼키는 이유: body 가 깨진 행 하나가 **그 행의 DELETE 자체를 실패**시키는
게 회수 실패보다 훨씬 나쁘다.

④의 `on conflict do nothing` 은 부작용이 있다 — 같은 키가 이미 큐에 있으면
**`queued_at` 이 갱신되지 않는다.** 최초 큐잉 시각이 남는다 (§3-② 에서 작동).

트리거는 AFTER, 같은 트랜잭션이라 행 삭제가 롤백되면 큐잉도 롤백된다. 아웃박스의
핵심이고 이 부분은 정확하다.

**큐에 넣지 않는 것(설계상)**: INSERT, body 외 컬럼 UPDATE, 그리고
**`metrics` 가 아닌 모든 테이블의 변경.**

### 2-2. 큐를 비우는 판단 — drain

`web/workers/cron.ts:138` `drainThumbnailGc`. 매일 1회, `queued_at asc` 200건.

**가드 A — 아직 참조되는가** (`cron.ts:167`)

```
GET /rest/v1/metrics?body=like.*{key}*&select=id&limit=1
```

행이 하나라도 나오면 → `kept`, 객체는 두고 큐에서만 제거.

- `jsonb ->> 'thumbnailKey'` 비교가 아니라 body 전체 **부분문자열 LIKE**. 오탐은
  "안 지움" 쪽이라 방향은 안전하다.
- 내용 주소 키가 되며 서로 다른 행이 한 객체를 가리킬 수 있게 됐고, 이 가드가
  그 N:1 을 지탱한다.
- **조회 대상은 `metrics` 뿐이다.** ← 이번 사고의 지점.

**가드 B — 큐잉 뒤에 다시 올라온 객체인가** (`cron.ts:186`)

| HEAD 결과 | 결정 |
| --- | --- |
| `404` | 이미 없다 → 큐에서만 제거 |
| `!ok` (5xx 등) | 아무것도 안 함 → **큐에 남겨 다음 실행 재시도** |
| `last-modified > queued_at` | `kept` — 살아있는 객체로 보고 큐에서만 제거 |
| 그 외 | 통과 |

**실행**: `DELETE` → `purged[]` 적재 → `purgeCdnCache(purged)` → `thumbnail_gc`
에서 제거(50개씩). throw 면 큐에 남아 다음 실행이 재시도한다. `queued_at` 이
오래된 키 = 계속 실패하는 키라, 큐 자체가 진단 도구가 된다.

### 2-3. 그래서 삭제 조건은 정확히

> **어떤 `metrics` 행의 body 도 이 키를 담고 있지 않고, 객체가 큐에 들어온 뒤로
> 다시 쓰이지 않았다.**

---

## 3. 동결 로직과 어긋나는 지점

동결의 전제는 `0001_baseline.sql:267` 주석에 명시돼 있다:

```
FK 없음 — 스냅샷은 metrics 삭제를 견딘다.
a_body/b_body: 결제 시점 두 body 스냅샷 — 구매한 궁합을
               self-contained 로 보존 (방 purge·metrics 삭제 무관).
```

`unlock_compat` 은 클라이언트가 보낸 로컬 body 두 개를 그대로 얼린다
(`compatibility_service.dart:181`). 그 안에 `thumbnailKey` 가 문자열로 들어간다.

### ① 참조 계수가 반쪽이다 — 기존 결함, `PLAN-THUMBNAIL.md` 에서 안 고쳐짐

**텍스트만 self-contained 이고 사진은 아니다.** body 의 `thumbnailKey` 는
`metrics` 가 수명을 쥔 저장소로 나가는 포인터라, FK 를 일부러 안 걸어 metrics
삭제를 견디게 만든 그 순간부터 사진은 견디지 못한다. 가드 A 의 `metrics` 한 줄이
이 모순의 전부다.

### ② 내용 주소화가 노출 면적을 키웠다

uuid 키 시절에도 스냅샷은 body 복사라 같은 키를 공유했으니 원래 2:1 이었다.
내용 주소는 축을 하나 더 얹는다 — **서로 다른 사용자·카드가 같은 사진이면 같은
객체.** 참조 계수가 정확해야만 성립하는 모델로 옮겨갔는데 계수기는 반쪽 그대로다.
방향 자체는 맞다(그래서 가드 A 를 새로 넣었다). 세는 범위만 안 따라왔다.

### ③ 409 skip 이 가드 B 를 무력화한다 — **내용 주소 전환이 새로 만든 결함**

`flutter/lib/data/services/r2_uploader.dart:149`

```dart
final url = p.uploadUrl;
if (url == null) return p;   // 409 — 같은 바이트가 이미 저장돼 있다
```

409 면 **PUT 을 안 한다.** 객체도 `last-modified` 도 그대로다.

uuid 시절엔 재촬영이 항상 새 객체를 만들었으므로 "되살아난 객체 = 새
last-modified" 가 참이었다. 내용 주소에서는 **원래 사진으로 되돌리는 재등록이
객체를 전혀 건드리지 않으므로** 가드 B 가 부활을 알아볼 수 없다. `on conflict do
nothing` 이 `queued_at` 을 옛 시각으로 고정해두는 것까지 겹쳐 비교는 항상 삭제
쪽으로 기운다.

대개 가드 A 가 덮어주지만, 가드 A 와 DELETE 사이에 부활이 끼면 못 막는다:

```
t0  body: K → K'      트리거가 K 큐잉 (queued_at = t0)
t1  가드 A: metrics 에 K 없음 → 통과
t2  사용자가 원래 사진으로 재등록 → key=K → presign 409 → PUT 없음
    body: K' → K      (객체 last-modified 는 t0 이전 그대로)
t3  가드 B: last-modified < t0 → 통과
t4  DELETE K          ← 살아있는 참조를 가진 객체를 지웠다
```

창은 좁다(일 1회 cron 의 키당 처리 구간). 하지만 uuid 모델에서는 **구조적으로
불가능**했던 레이스다.

### ④ 참조 계수를 고치면 반대 방향 누수가 열린다

트리거는 `metrics` 에만 붙어 있다. `compatibilities` 는 사용자 삭제 정책
(`compatibilities_self_delete`)과 `auth.users` cascade 로 사라질 수 있는데, 그때
그 스냅샷만 참조하던 키를 **아무도 큐에 넣지 않는다.**

지금은 어차피 compat 을 안 세니 무해하다. 하지만 ①을 `or` 조건 한 줄로 고치는
순간, 그 키는 영원히 "참조됨" 으로 판정되다가 compat 행이 사라지면 아무도 모르는
고아가 된다 — **영구 누수.** ①의 수정은 반드시 compat 삭제 처리와 한 쌍이어야 한다.

### ⑤ 업로드 시점 이동 vs 즉시 동결 — 좁지만 실재

P2 로 업로드가 "행 저장 후" 로 밀렸다. 동결은 구매 시점에 즉시 body 를 복사한다.
업로드가 실패해 대기열에 남은 상태에서 그 카드로 궁합을 구매하면 스냅샷은 아직
존재하지 않는 객체를 가리킨다. 그 기기가 다시 안 켜지면 영구히 빈 포인터다.
uuid 시절엔 캡처 직후 업로드라 동결 시점엔 거의 항상 존재했다.

### 어긋나지 *않는* 것 (확인함)

- **`thumbnailPath` 제거는 확인 탭과 무관.** `_decodeSide` 는 원래부터 로컬을 안
  본다. 미확인 탭만 `historyProvider` 를 읽으므로 관상 탭과 운명을 같이한다.
- **트리거는 alias·views 갱신에 안 걸린다** (`update OF body` + `is not distinct
  from`). 동결·조회수와 간섭 없음.
- **`teams`·`team_members`·`team_roster` 는 썸네일 키를 들고 있지 않다** (실측:
  thumbnail 문자열 포함 행 0). 케미 로스터 아바타는 `fetchMyFaceThumbnailUrls`
  로 metrics 를 조회한다 — metrics 참조라 안전하다.

---

## 4. 정책 확인 — 구매분 보존은 이미 명문화돼 있다

`web/public/privacy.md:27`

> **결제한 궁합 결과**: 코인으로 해제한 궁합 분석은 구매 콘텐츠로서 이용자
> 계정에 보관되며, **상대방의 데이터 삭제 여부와 무관하게 이용할 수 있습니다.**

즉 현재 GC 는 정책을 위반하고 있다. 참조 계수 수정은 선택이 아니라 필수다.

**단, 같은 문서 안에서 충돌한다:**

- `privacy.md:24` — "얼굴 썸네일 … **탈퇴 시 삭제됩니다**"
- `privacy.md:43` — 수탁자 표, Cloudflare R2 "썸네일만 **탈퇴 전까지**"

구매분 보존을 택하면 탈퇴한 사용자의 얼굴이 R2 에 남는다. 24·43 줄에 예외
조항을 넣어야 한다 — 시스템이 어느 쪽을 따르든 문구는 지금 이미 서로 어긋나 있다.

`PLAN-THUMBNAIL.md` 의 "판단이 필요한 것 #1"(공유받은 카드)도 이 조항과 함께
다시 봐야 한다. 공유와 구매는 다른 경우지만 같은 축의 질문이다.

---

## 5. 제안 — 참조 레지스트리

### 왜 레지스트리인가

이번 사고의 근본 원인은 **"GC 가 모든 참조자를 암묵적으로 알고 있어야 한다"** 는
것이다. `compatibilities` 를 가드 A 의 LIKE 스캔에 한 줄 추가하는 수정은:

- 정책(구매분 보존)을 **표현하지 못한다** — metrics 행이 사라지면 스캔할 대상
  자체가 없다
- 불일치 ④(compat 삭제 시 누수)를 **새로 연다**
- 다음에 body 스냅샷을 저장하는 기능이 생기면 **똑같이 또 터진다**

### 레지스트리는 아웃박스의 대체가 아니라 상위 절반이다

| 층 | 질문 | 담당 |
| --- | --- | --- |
| **판단** | 이 객체를 지워도 되나 | 레지스트리 ← 지금 이게 없어서 터졌다 |
| **실행** | 실제로 지우고 CDN 퍼지, 실패 시 재시도 | 아웃박스 `thumbnail_gc` (유지) |

R2 삭제는 Postgres 트랜잭션 밖의 부수효과라 재시도 큐가 여전히 필요하다.
레지스트리가 들어오면 아웃박스는 **더 단순해진다** — drain 이 LIKE 스캔도,
테이블 목록도, `last-modified` 휴리스틱도 안 쓴다. 인덱스 조회 한 번이다.

### 정수 카운터가 아니라 간선(edge) 행

"reference 숫자" 를 컬럼으로 들면 반드시 드리프트한다. 증가 한 번 놓치면
**살아있는 사진을 지우고**(복구 불가), 감소 한 번 놓치면 영구 누수다. 백필을 두
번 돌리면 두 배가 된다.

참조를 행으로 저장하면 카운트는 `count(*)` 로 파생된다:

- **멱등** — 재시도·백필 재실행이 PK 충돌로 무시된다
- **감사 가능** — "이 사진을 누가 붙들고 있나" 가 `select` 한 줄. 이번 진단에
  스크립트 세 개가 필요했던 질문이다
- **자동 해제** — 참조 행이 사라질 때 트리거/cascade 가 간선을 지운다

### 스키마 초안

```sql
-- 객체 1개 = 1행. "우리가 아는 모든 사진" 의 목록.
create table public.thumbnails (
  key           text primary key,          -- thumbnails/{2hex}/{sha256}.jpg
  byte_size     int,
  registered_at timestamptz not null default now(),
  uploaded_at   timestamptz                -- PUT 확인 전엔 null
);

-- 참조 간선. 행 개수가 곧 refcount — 정수를 따로 들지 않는다.
create table public.thumbnail_refs (
  key      text not null references public.thumbnails(key) on delete cascade,
  ref_type text not null check (ref_type in ('metrics', 'compatibility')),
  ref_id   text not null,                  -- metrics.id | user_id:a_id:b_id
  primary key (key, ref_type, ref_id)
);
create index on public.thumbnail_refs (ref_type, ref_id);
```

간선 유지 트리거는 둘뿐이다:

- `metrics` — after insert / update of body / delete
- `compatibilities` — after insert / delete (**UPDATE 는 없다** — 동결이니까)

마지막 간선이 사라지면 그 트리거가 `thumbnail_gc` 에 넣고, drain 은
`select 1 from thumbnail_refs where key = $1` 만 확인하고 지운다.

**정책이 스키마로 표현된다.** 구매는 `('compatibility', …)` 간선을 만들고,
상대가 탈퇴해 `metrics` 간선이 사라져도 구매 간선이 남아 사진이 살아남는다.

### 덤으로 죽는 문제

- **불일치 ③(409 skip 레이스)** — 부활을 `last-modified` 로 추측하지 않고 간선이
  다시 생기는 걸 DB 안에서 본다. presign 이 키를 발급/409 할 때 `thumbnail_gc`
  의 대기 행을 지우게 하면 **부활 = 수거 취소** 가 원자적으로 성립한다.
- **불일치 ④(compat 삭제 누수)** — 간선을 트리거가 유지하니 "세기 시작했는데
  삭제는 안 챙긴다" 는 상태가 존재할 수 없다.
- **고아 탐지** — R2 전수 조사 + 모든 body 파싱이 아니라 한 줄:
  ```sql
  select t.key from thumbnails t
   where not exists (select 1 from thumbnail_refs r where r.key = t.key);
  ```

### 받아들이면 안 되는 부분

> "thumbnails 레코드가 있으면 R2 에도 이미지가 존재한다" **로 해석**

Postgres 와 R2 사이에 공유 트랜잭션이 없으므로 이 쌍방향 등가는 **강제할 수 없다.**
어느 쪽으로 틀어질지 골라야 한다:

| 등록 시점 | 틀어지는 방향 | 결과 |
| --- | --- | --- |
| presign 발급 시 (서버) | 행은 있는데 PUT 실패 | 아바타 깨짐. GC 는 정상으로 착각 |
| PUT 성공 후 (클라이언트) | 객체는 있는데 행 없음 | 아무도 모르는 고아. 게다가 presign 은 **무인증**이라 클라이언트에 레지스트리 쓰기를 맡길 수 없다 |

**단방향만 불변식으로 삼는다:**

> **간선 0개 ⟹ 지워도 된다** (GC 는 이것만 의존)
> **행 있음 ⟹ 객체 있음** 은 best-effort. 렌더러엔 이미 fallback 이 있으므로
> 여기 기대지 않는다.

구현은 presign 이 유일한 관문이니 거기서 `uploaded_at = null` 로 등록하고, PUT
확인 또는 다음 409 응답에서 채우고, 오래 미확인인 행은 주기 스윕이 HEAD 로
정리한다.

### 비용 (정직하게)

테이블 2개 + 트리거 2개 + 백필 1회 + presign 수정 + drain 단순화.
`compatibilities` 를 LIKE 스캔에 한 줄 추가하는 것보다 **훨씬 크다.** 그 한 줄이
정책을 표현하지 못하고 ④를 새로 연다는 점이 이 비용을 정당화한다.

---

## 6. 결정이 필요한 것

1. **정책 문구** — `privacy.md` 24·43 줄에 "구매된 궁합에 포함된 썸네일 제외"
   예외를 넣을 것인가. 넣지 않으면 시스템과 고지가 어긋난 채로 남는다.
2. **레지스트리 vs 최소 수정** — 위 비용을 받고 레지스트리로 갈 것인가, 아니면
   가드 A 에 compat 을 추가하고 ④를 별도로 막는 최소 수정으로 갈 것인가.
3. **`ref_type` 초기 범위** — `metrics`·`compatibility` 둘로 시작한다. 공유받은
   카드(`share_publisher.dart`)와 케미 결과표는 현재 키를 들고 있지 않으므로
   대상이 아니다. 나중에 body 스냅샷을 저장하는 기능이 생기면 그때 `ref_type`
   을 추가한다.

## 7. 그 전에 막아야 할 것 (배포 순서)

`drainThumbnailGc` 는 아직 배포 전이고 `thumbnail_gc` 큐는 0건이라 **아직 아무것도
지우지 않았다.** 지금 배포하면 재등록·카드 삭제마다 §1 의 손실이 계속 난다.

- 레지스트리든 최소 수정이든, **참조 계수를 고치기 전에는 cron 을 배포하지 않는다.**
- `purge-orphan-thumbnails.mjs` 는 **다시 실행하지 않는다.** 같은 맹점을 갖고 있다.
