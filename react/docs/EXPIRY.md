# 만기(Expiry) 동작 — 관상 · 궁합 end-to-end

> 관상 reading(metrics)과 궁합(compat)에서 `expires_at`/`expiresAt` 가 어디서 set 되고,
> 누가 prune/삭제하며, 만료 시 공유링크·궁합이 어떻게 되는지 정리.
> (코드 기준 점검 결과 — 2026-05 현재)

---

## ⚑ 결정 (2026-05) — expiry 개념 폐기

아래 §1~§9 는 **변경 전(as-was)** 동작 맵이다. 점검 결과 다음으로 **단순화하기로 결정**:

1. **Remote 업로드 = 공유/궁합 시에만** — 분석 confirm 시 eager `saveMetrics`(info_confirm_screen) 제거.
   미공유 분석은 기기를 안 떠남(프라이버시·레코드 최소화). 업로드는 share_publisher/compatibility 의 lazy 경로.
2. **expiry 로직 전부 제거** — `metrics.expires_at` 컬럼 / worker 만료체크 / `FaceReadingReport.expiresAt`(필드·90일 default·body 직렬화) / `history_provider` 로컬 prune + received 예외 hack 전부 삭제. → **로컬 Hive = 영구 라이브러리**.
3. **정리 = refine "90일+ 미활동 삭제" 버튼** — `delete from metrics where updated_at < now() - interval '90 days'` (service_role). cron 불필요. `updated_at` 은 views++/재publish 로 touch → 활성 공유 생존, 방치분만 삭제.
4. R2 thumbnail orphan 정리는 별개(추후). `unlocks.body`(마지막 phase)는 metrics 삭제와 무관한 결제 궁합 보존용으로 계속 필요.

→ 멘탈 모델: 로컬 Hive=영구 SSOT / remote metrics=공유본(미활동 90일 후 수동 삭제) / expiry 로직 소멸.

---

## 0. 한 줄 요약 (변경 전 동작)

- 만기는 **report 생성 시 `now + 90일`** 로 한 번 박히고, **재publish·pull-to-refresh 해도 연장되지 않는다.**
- 적용은 **두 곳에서만 능동적**: (1) Flutter 로컬 Hive load 시 prune, (2) Worker 가 공유링크 read 시 만료행 drop(→ 404).
- **서버(Supabase)는 만기를 능동 삭제하지 않는다** — `expires_at` 은 passive 메타. 삭제 cron 은 문서상 계획만 있고 **아직 미배포**.
- **궁합은 만기 로직이 없다** — unlock 은 영구, 계산은 로컬 스냅샷.
- **받은 카드(source==received)는 로컬 prune 예외** — 만료돼도 안 지움(결제 소유 보존).

---

## 1. 만기가 SET 되는 곳

**`shared/lib/domain/models/face_reading_report.dart:291`**
```dart
}) : expiresAt = expiresAt ?? DateTime.now().add(const Duration(days: 90));
```
- 기본값 **90일**. report 생성(분석) 시점에 박힌다.
- publish 시 `toBodyJson()` 의 `expiresAt` + metrics 컬럼 `expires_at` 로 동일 값 기록 (`supabase_service.dart:88`).
- **재publish/pull-to-refresh (`upsertMetricsBody`) 는 원래 값을 그대로 보냄 → 연장 안 됨** (`history_provider.dart:162` → `supabase_service.dart:88`).

→ **만기는 "최초 생성 + 90일" 고정. 갱신 메커니즘 없음.**

---

## 2. 로컬(Hive) — load 시 prune

**`flutter/lib/presentation/providers/history_provider.dart`** (`_loadFromHive` ~189, `reloadFromHive` ~118)
```dart
final alive = report.expiresAt.isAfter(now);
final isReceived = report.source == AnalysisSource.received;
if (alive || isReceived) { /* keep */ } else { /* drop: expired */ }
```
- **본인 카드**(camera/album): `expiresAt < now` 면 load 시 drop + Hive 재기록(compaction).
- **받은 카드**(received): **만료돼도 항상 keep** (아래 §6 예외).
- 로컬 만기는 **갱신 안 됨** — JSON 의 원래 `expiresAt` 만 사용.

---

## 3. 서버(Supabase) — passive, 능동 삭제 없음

**`react/db/migrations/0001_baseline.sql`**
```sql
expires_at   timestamptz not null,          -- 컬럼 (line ~141)
create index idx_metrics_expires_at on public.metrics (expires_at);  -- line ~145
-- cron · /api/erase 는 service-role 로 직접 DELETE (RLS bypass).      -- 주석
```
- `expires_at` 컬럼 + 인덱스는 있으나, **`expires_at` 기준으로 행을 지우는 트리거/cron 은 없다.**
- 문서(`HOW-IT-WORKS.md`)상 계획: *daily cron `delete from metrics where updated_at < now() - interval '3 months'`* + R2 thumbnail 동시 삭제.
  - ⚠️ 단 이건 **`updated_at` 기준(비활성 3개월)** 이지 `expires_at` 기준이 아니며, **`wrangler.toml` 의 triggers 가 비어 있어 실제로 미배포**.
- 즉 현재 서버에서 만료행은 **사실상 영구 잔존**(누가 안 지움).

---

## 4. Worker / 공유링크 read — 만료행 drop

**`react/app/lib/supabase.ts` (fetchMetrics, ~53)**
```typescript
if (r.expires_at && new Date(r.expires_at).getTime() <= now) {
  console.warn("[fetchMetrics] drop: expired id=", r.id);
  continue;          // 만료행은 결과에서 제외
}
```
- `/r/{uuid}` SSR fetch 시 **만료행을 능동 drop** → 행 수 불일치 시 `share.tsx` 가 **404**.
- **뷰어가 보는 것**: "카드를 찾을 수 없어요 / 만료됐거나 link 가 잘못됐어요" (만료 vs 삭제 구분 안 함).

→ **서버엔 데이터가 남아 있어도, 공유링크로는 만료 후 안 보인다** (worker 가 가린다).

---

## 5. 공유 수신(Flutter) — 받은 카드의 만기

**`flutter/lib/domain/services/share/share_receive_service.dart`** (`fetchByUuid`)
- 원본 body 를 받아 override: `source=received`, `receivedAt=now`, `isMyFace=false`, `alias=null`, `thumbnailPath=null`.
- **`expiresAt` 은 원본 그대로 상속** (새 90일 부여 X). 즉 받은 카드는 보낸 사람 카드의 잔여 수명을 물려받는다.
- 원격이 만료/삭제(404)면 `getMetrics` 가 null → `router.dart` 가 "카드 없음" 에러 화면.
- 일단 로컬 저장되면(§6) 만기 prune 예외라 영구 보존.

---

## 6. 받은 카드 prune 예외 (현 정책)

**`history_provider.dart` ~190 주석:**
```dart
// 받은 카드(source==received)는 만료돼도 삭제하지 않는다.
// 궁합 unlock 된 상대 카드일 수 있으며, unlock 결제 후 데이터가 사라지면 UX 문제.
// HistoryNotifier.build() 가 sync 이므로 compatUnlocksProvider(async) 를 못 읽어
// received 전체를 보존하는 보수적 정책. TODO: AsyncNotifier 전환 후 unlocked
// pair_key set 기반 정밀 prune.
```
- 의도: **"결제=소유"** — unlock 한 궁합 상대 데이터가 상대 삭제로 사라지면 안 됨.
- 현 구현(interim): "unlock 된 것만"이 아니라 **received 전부** 로컬 보존(보수적). 자동저장 제거(CTA-only) 덕에 실제론 CTA 로 저장된 카드만 남아 차이는 작음.

> ⚠️ **결정됨 — 로컬 보관은 폐기 예정 (다중 디바이스 UX 오류).**
> 기기 로컬 스냅샷은 폰A에서 결제 → 폰B/재설치 시 못 보는 오류. 따라서 결제한 궁합의
> 상대 스냅샷을 **서버 `unlocks.body` 컬럼에 per-user 로 저장**하고, 궁합 표시는 그걸
> 읽는다 → 상대 삭제·다중 디바이스 모두 안전. (구현·baseline·raw SQL 은 **마지막 phase**,
> [[TODONOW]] §7 참조.) 이 전환 후 received 로컬 prune 예외 hack 은 불필요해진다.

---

## 7. 궁합(Compat) 과 만기

**`unlocks` 테이블** (`0001_baseline.sql:233`) — **만기 컬럼 없음.** 한번 unlock = 영구 (계정 삭제/수동 삭제 전까지).

- 궁합 계산은 **로컬 두 `FaceReadingReport` 스냅샷**으로 수행 (`compatibility_detail_screen.dart` `analyzeCompatibilityFromReports`) — 분석 시 **원격 재조회 없음**.
- 상대 metrics 가 서버에서 만료/삭제돼도, 받은 카드가 로컬에 있으면(§6) 궁합은 정상 계산.
- 둘 다 로컬에 없고 삭제되면 후보에서 사라지지만 `unlocks` ledger 행은 잔존(dormant).

→ **궁합에는 만기 개념이 없다. unlock 영구 + 로컬 스냅샷 계산.**

---

## 8. 레이어별 정리 + 불일치

| 레이어 | 만기 기준 | 능동 enforce? | 범위 | 비고 |
|---|---|---|---|---|
| Flutter 로컬(Hive) | `expiresAt`(90일) | ✅ load 시 | 본인 카드만 (received 예외) | 갱신 없음 |
| 서버 컬럼 `expires_at` | 90일 | ❌ | 전체 | passive 메타, 삭제 안 함 |
| 서버 비활성 cron | `updated_at < 3개월` | ❌ (계획·미배포) | 전체 | `expires_at` 아님 / wrangler triggers 비어있음 |
| Worker 공유 read | `expires_at <= now` | ✅ fetch 시 | 반환행 | 만료 → 404 |

**알려진 불일치 / 리스크:**
1. **클라 90일 vs 문서 cron 3개월(92일)** — 클라가 더 공격적. 게다가 cron 은 미배포.
2. **재publish 가 만기 연장 안 함** — 오래된 카드를 다시 올려도 deadline 그대로.
3. **본인 카드 90일 후 로컬 소멸 위험** — 로컬=SOT 구조에서 본인 캡처가 90일 뒤 Hive 에서 prune 되면 사라짐. 서버엔 남아있을 수 있으나 anon row 는 user_id=null 이라 앱이 재조회로 복구 못 함. → 본인 자산 보존 관점에서 재검토 필요(다음 phase 의 anon-auth + owner 만료 제외와 연결).
4. **받은 카드 ghost ref** — received 는 로컬 영구 보존이나, 서버 원본이 (장차 cron 으로) 삭제되면 thumbnail/재조회가 깨질 수 있음(현재 gender fallback 아바타로 완화).

---

## 9. TODO / 후속(다음 phase)

- **[마지막 phase] 결제 궁합 = `unlocks.body` 서버 보관** — `unlocks` 에 `body text` 추가,
  `unlock_compat` 가 unlock 시점에 상대 metrics body 를 스냅샷 저장, 궁합 표시는 `unlocks.body`
  를 read. → 다중 디바이스·상대 삭제 모두 안전. 이후 received 로컬 prune 예외 hack 제거 +
  privacy.md 에 "결제 궁합은 계정에 보관" 문구(계정 기준)로 재기재. (raw SQL + baseline 갱신 = 마지막 phase)
- 서버 만료 cron 실제 배포 여부 결정 (`updated_at` vs `expires_at` 기준 통일).
- 본인 카드 만료 정책 재검토 — anon-auth 도입 후 owner row 만료 제외(자산 보존).
- 만료 vs 삭제를 뷰어에게 구분 안내할지(현재 동일 404 문구).
