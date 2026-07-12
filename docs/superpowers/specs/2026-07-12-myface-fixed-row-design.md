# 내 관상 고정 row 덮어쓰기 설계 (재촬영 route)

2026-07-12 승인. 불변식: **내 관상은 서버에 사용자당 정확히 1행이며, 그 row id 는 영구 고정**. 재촬영은 새 row 생성이 아니라 기존 row 덮어쓰기 — 웹 참여(`react/app/lib/join.ts` saveCapture)가 이미 쓰는 모델을 앱에 대칭 적용한다.

## 배경 (확인된 사실)

- 신규 캡처는 "1 capture = 1 uuid": 분석 uuid = `temp/`·`thumbnails/{YYYYMM}/{uuid}.jpg`·`metrics.id`·`/r/{uuid}` 단일 trace (face_metadata_client.dart).
- 웹 재촬영은 이미 예외: row 는 기존 id 로 upsert, 썸네일은 **무관한 새 uuid 키** (join.ts:237 — 같은 키 재업로드는 CDN 캐시가 옛 사진을 서빙하므로 금지).
- `/api/r2/delete` 소유 검증: 요청자의 metrics.body 중 하나가 **아직 그 key 를 참조할 때만** 삭제 허용 → **옛 키 삭제는 body upsert 이전에 호출**해야 한다 (웹과 동일 순서).
- 케미 결과표: 마감 방은 `teams.matrix_payload` 스냅샷이라 불변, 모집 중 방만 슬롯 metrics 를 live 로 읽음 → row 덮어쓰기 시 모집 중 방에 새 관상이 자동 반영 (개선).
- 관상 카드 ⋮ 메뉴에는 현재 '제목 변경 / 삭제' 만 있음 (지정/해제는 2026-07-12 제거).
- 앱 재촬영도 새 분석이므로 파이프라인이 이미 새 trace uuid 로 썸네일을 올려둠 → 저장 단계에서 row 만 옛 id 로 upsert 하면 "row id 고정 + 썸네일 키 교체"가 자연 성립.

## 동작

### 1. 재촬영 진입점

관상 탭 **내 관상 카드의 ⋮ 메뉴**에 '내 관상 다시 찍기' 항목 추가 — `report.isMyFace` 카드에만 표시. 탭 시 기존 `startMyFaceCapture` 플로우 그대로 (전면 카메라 + 앨범 숏컷 + InfoConfirm). 신규 UI 없음.

### 2. 저장 — saveMetrics 의 my-face 고정 id 규칙

`SupabaseService.saveMetrics` 에서 `report.isMyFace && 로그인` 이면:

1. 서버에서 기존 my-face row 조회: `metrics?user_id=eq.나&is_my_face=eq.true` → `id` + body 의 `thumbnailKey`.
2. **기존 row 가 있으면 그 id 를 저장 대상 id 로 사용** (분석 uuid 는 row id 로 쓰지 않고 썸네일 키로만 남음). 없으면 현행대로 `report.supabaseId ?? 새 uuid`.
3. 옛 `thumbnailKey` 가 새 body 의 키와 다르면, **upsert 이전에** `/api/r2/delete` 호출 (Bearer = Supabase 세션 access token). 실패해도 저장 흐름 계속 (고아 1개 감수 — 웹과 동일).
4. upsert 후 반환된 최종 id 로 `report.supabaseId` 갱신 (호출부가 Hive 에 반영).
5. 기존 demote 안전망(다른 `is_my_face=true` 행 강등)은 유지 — 익명→로그인 귀속 등 엣지 방어.

비로그인: user_id 로 조회 불가 → 현행 신규 생성 유지.

### 3. 로컬 히스토리 — 같은 supabaseId 카드 교체

고정 id 덕에 재촬영 카드의 `supabaseId` 가 옛 카드와 동일해진다. `HistoryNotifier.add()` 는 **같은 `supabaseId` 를 가진 기존 카드를 제거**한 뒤 새 카드를 삽입 (옛 내 관상 카드가 일반 카드로 남지 않음 — 깔끔 route). 기존 my-face 강등 루프는 유지 (supabaseId 없는 로컬 전용 카드 방어).

### 4. 변경 없는 것

- 웹(`saveCapture`): 이미 동일 모델 — 변경 없음.
- refine: 변경 없음.
- 카드 **삭제** 경로: 진짜 삭제 의도로 유지 — row delete 로 케미 슬롯이 대기로 풀리는 것 수용 (교체 목적 삭제는 '다시 찍기' 메뉴가 흡수).
- `/r/{id}` 공유 링크: id 고정이라 영구 — 항상 최신 내 관상 표시.

## 검증

- flutter analyze 변경 파일 0 issue, flutter test green.
- 실기: 내 관상 카드 ⋮ → 다시 찍기 → 저장 후 (a) 서버 my-face 1행·id 불변 (b) body thumbnailKey 새 키 (c) R2 옛 키 404 (d) 로컬 히스토리에 내 관상 1장 (e) 모집 중 케미 방에 새 사진.
