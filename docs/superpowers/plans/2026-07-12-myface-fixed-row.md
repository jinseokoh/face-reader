# 내 관상 고정 row 덮어쓰기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 내 관상 재촬영이 새 metrics row 를 만들지 않고 기존 row 를 덮어쓰게 하여 "서버에 내 관상 1행·id 영구 고정" 불변식을 세운다.

**Architecture:** 웹 `saveCapture` 의 고정 id + 새 썸네일 키 모델을 앱에 대칭 적용. InfoConfirm 이 저장 전에 서버 my-face row id 를 물려받고(`myFaceRowId`), `saveMetrics` 가 옛 썸네일을 upsert **이전에** `/api/r2/delete` 로 지운 뒤 기존 id 에 덮어쓴다. 로컬 히스토리는 같은 supabaseId 카드를 교체. 재촬영 진입점은 내 관상 카드 ⋮ 메뉴. 스펙: `docs/superpowers/specs/2026-07-12-myface-fixed-row-design.md`.

**Tech Stack:** Flutter(Riverpod·Hive), Supabase REST, Cloudflare Worker `/api/r2/delete`.

## Global Constraints

- 옛 썸네일 삭제는 body 를 새 키로 upsert 하기 **이전** 에 호출 — `/api/r2/delete` 는 "요청자 metrics.body 가 아직 그 key 를 참조" 할 때만 허용.
- 비로그인은 현행 유지(신규 생성, user_id null). 조회·삭제 실패는 저장 흐름을 막지 않는다 (fallback: 신규 생성 / 고아 1개 감수).
- 기존 demote 안전망(saveMetrics 의 다른 `is_my_face=true` 행 강등)은 유지.
- DB·웹·refine 변경 없음 — flutter 만.
- `flutter analyze` 변경 파일 0 issue, `flutter test` 151개 green 유지.
- 신규 단위 테스트는 만들지 않는다 — Supabase/Hive mock 인프라 부재, 기존 관례(전체 스위트 + 실기 확인)를 따른다.

---

### Task 1: R2Uploader.deleteObject + SupabaseService 고정 id 저장

**Files:**
- Modify: `flutter/lib/data/services/r2_uploader.dart` (deleteObject 추가)
- Modify: `flutter/lib/data/services/supabase_service.dart` (saveMetrics 고정 id + `_myFaceRow`/`myFaceRowId` 추가)

**Interfaces:**
- Produces: `R2Uploader.deleteObject(String key, {required String accessToken}) → Future<bool>`
- Produces: `SupabaseService.myFaceRowId() → Future<String?>` (Task 2 의 InfoConfirm 이 소비)
- Produces: `saveMetrics` 는 my-face + 로그인 시 서버 기존 my-face row id 로 upsert 하고 `report.supabaseId` 를 최종 id 로 동기화

- [ ] **Step 1: R2Uploader 에 deleteObject 추가**

`r2_uploader.dart` 의 `static const _kPathPresign = '/api/r2/presign';` 아래에 상수 추가:

```dart
  static const _kPathDelete = '/api/r2/delete';
```

클래스 안(presign 메서드 아래)에 메서드 추가:

```dart
  /// 재촬영 교체로 고아가 될 옛 썸네일 즉시 삭제 — 웹 saveCapture 와 동일
  /// 계약. 서버가 "요청자의 metrics.body 가 아직 이 key 를 참조" 를 검증하므로
  /// 반드시 body 를 새 키로 upsert 하기 **전에** 호출할 것. 실패는 무해
  /// (고아 1개 감수) — false 반환.
  Future<bool> deleteObject(String key, {required String accessToken}) async {
    try {
      final res = await _client.post(
        Uri.parse('$_hostBase$_kPathDelete'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'key': key}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 2: SupabaseService — import 와 my-face row 조회 헬퍼**

`supabase_service.dart` 상단 import 에 추가:

```dart
import 'dart:convert';

import 'package:facely/data/services/r2_uploader.dart';
```

클래스 안(saveMetrics 아래 아무 곳)에 두 메서드 추가:

```dart
  /// 서버의 내 관상 row (id + body 의 thumbnailKey). 없거나 조회 실패면 null.
  Future<({String id, String? thumbnailKey})?> _myFaceRow(String uid) async {
    try {
      final row = await _client
          .from('metrics')
          .select('id, body')
          .eq('user_id', uid)
          .eq('is_my_face', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      String? key;
      try {
        key = (jsonDecode(row['body'] as String)
            as Map<String, dynamic>)['thumbnailKey'] as String?;
      } catch (_) {
        key = null;
      }
      return (id: row['id'] as String, thumbnailKey: key);
    } catch (e) {
      debugPrint('[Supabase] my-face row 조회 실패 (신규 생성 fallback): $e');
      return null;
    }
  }

  /// 저장 전에 호출해 재촬영 카드가 처음부터 고정 row id 를 갖게 한다 —
  /// 로컬 히스토리의 supabaseId 교체(add)와 saveMetrics 덮어쓰기가 같은
  /// row 를 가리키는 전제. 비로그인·행 없음·조회 실패면 null.
  Future<String?> myFaceRowId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    return (await _myFaceRow(uid))?.id;
  }
```

- [ ] **Step 3: saveMetrics 를 고정 id 규칙으로**

`saveMetrics` 의 첫 줄 `final id = report.supabaseId ?? _uuid.v4();` 와 `final uid = ...` 부분을 다음으로 교체 (demote 블록·upsert·로그는 그대로 두되, demote 블록이 참조하는 `uid`/`id` 는 이 새 코드의 것을 쓴다):

```dart
    final uid = _client.auth.currentUser?.id;

    // 내 관상 고정 row — 서버에 기존 my-face row 가 있으면 새 row 를 만들지
    // 않고 그 id 에 덮어쓴다 (row id 영구 고정 · 웹 saveCapture 와 동일 모델.
    // 케미 슬롯 FK·/r/{id} 링크가 항상 유효하고 최신 관상을 가리킴). 재촬영의
    // 분석 uuid 는 썸네일 키로만 남는다. 옛 썸네일 삭제는 body 가 아직 옛 키를
    // 참조하는 upsert **이전** 이어야 /api/r2/delete 소유 검증을 통과한다.
    ({String id, String? thumbnailKey})? existing;
    if (report.isMyFace && uid != null) {
      existing = await _myFaceRow(uid);
      final oldKey = existing?.thumbnailKey;
      if (oldKey != null && oldKey != report.thumbnailKey) {
        final token = _client.auth.currentSession?.accessToken;
        if (token != null) {
          final ok = await R2Uploader().deleteObject(oldKey, accessToken: token);
          debugPrint('[Supabase.saveMetrics] old thumbnail delete ok=$ok key=$oldKey');
        }
      }
    }
    final id = existing?.id ?? report.supabaseId ?? _uuid.v4();
    // 로컬 카드가 최종 row 를 가리키도록 동기화 — InfoConfirm 이 미리 고정 id
    // 를 물려받은 경우엔 no-op.
    report.supabaseId = id;
```

기존 코드에서 `final data = { ... 'user_id': uid, ... }` 는 이미 `uid` 변수를 쓰고 있으므로 그대로 두고, 중복된 `final uid = _client.auth.currentUser?.id;` 선언이 두 개가 되지 않도록 정리한다.

- [ ] **Step 4: 검증**

Run: `cd /Users/chuck/Code/face/flutter && flutter analyze && flutter test`
Expected: 변경 파일 0 issue (pre-existing 7건만), 151 tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/chuck/Code/face
git add flutter/lib/data/services/r2_uploader.dart flutter/lib/data/services/supabase_service.dart
git commit -m "feat(flutter): saveMetrics 내 관상 고정 row 덮어쓰기 + 옛 썸네일 즉시 삭제"
```

---

### Task 2: 로컬 히스토리 교체 + InfoConfirm 사전 고정 id

**Files:**
- Modify: `flutter/lib/presentation/providers/history_provider.dart` (`add()`)
- Modify: `flutter/lib/presentation/screens/chemistry/info_confirm_screen.dart` (저장 직전)

**Interfaces:**
- Consumes: Task 1 의 `SupabaseService.myFaceRowId() → Future<String?>`

- [ ] **Step 1: add() — 같은 supabaseId 카드 교체**

`history_provider.dart` 의 `add()` 본문을 다음으로 교체 (`_log` 줄은 그대로):

```dart
    // 재촬영(고정 row) — 같은 supabaseId 의 옛 카드는 새 카드로 교체한다.
    // 내 관상 row id 가 영구 고정이라, 교체 없이는 같은 row 를 가리키는
    // 카드가 로컬에 2장 쌓인다.
    var rest = state;
    if (report.supabaseId != null) {
      rest = rest.where((r) => r.supabaseId != report.supabaseId).toList();
    }
    // 내 관상은 항상 1장 — isMyFace 로 들어오는 카드가 기존 지정을 대체.
    if (report.isMyFace) {
      for (final r in rest) {
        r.isMyFace = false;
        _syncMyFaceAlias(r); // 자동 별칭 '나' 회수
      }
    }
    _syncMyFaceAlias(report); // 지정 카드에 기본 별칭 '나'
    state = [report, ...rest];
    await _saveToHive();
```

- [ ] **Step 2: InfoConfirm — 저장 전에 고정 id 물려받기**

`info_confirm_screen.dart` 의 `report.isMyFace = widget.asMyFace;` 줄 바로 아래(alias 처리 앞)에 추가:

```dart
      // 고정 row — 서버에 내 관상 row 가 이미 있으면 그 id 를 미리 물려받아,
      // add() 의 supabaseId 교체(옛 카드 제거)와 saveMetrics 덮어쓰기가 같은
      // row 를 가리키게 한다. 비로그인·조회 실패면 null → 현행 신규 생성.
      if (widget.asMyFace) {
        final fixedId = await SupabaseService().myFaceRowId();
        if (!mounted) return;
        if (fixedId != null) report.supabaseId = fixedId;
      }
```

- [ ] **Step 3: 검증**

Run: `cd /Users/chuck/Code/face/flutter && flutter analyze && flutter test`
Expected: 변경 파일 0 issue, 151 tests green.

- [ ] **Step 4: Commit**

```bash
cd /Users/chuck/Code/face
git add flutter/lib/presentation/providers/history_provider.dart flutter/lib/presentation/screens/chemistry/info_confirm_screen.dart
git commit -m "feat(flutter): 재촬영 시 로컬 카드 supabaseId 교체 + 저장 전 고정 id 상속"
```

---

### Task 3: 내 관상 카드 '다시 찍기' 메뉴 + SSOT 문서

**Files:**
- Modify: `flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart` (카드 ⋮ 메뉴)
- Modify: `flutter/docs/ARCHITECTURE.md` (내 관상 고정 row 규칙 1문단)

**Interfaces:**
- Consumes: `startMyFaceCapture(context, ref)` (`package:facely/presentation/widgets/my_face_capture_flow.dart` — 기존 공용 플로우)

- [ ] **Step 1: 메뉴 항목 추가**

`physiognomy_screen.dart` import 에 추가:

```dart
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
```

카드 `PopupMenuButton` 의 `onSelected` 에 분기 추가:

```dart
              onSelected: (value) {
                if (value == 'rename') {
                  _showAliasDialog(context, ref, displayName);
                } else if (value == 'recapture') {
                  startMyFaceCapture(context, ref);
                } else if (value == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
```

`itemBuilder` 리스트 맨 앞(제목 변경 위)에 추가 — 기존 "내 관상 지정/해제 메뉴 없음" 주석 블록은 아래 내용으로 대체:

```dart
              // 내 관상 지정/해제 메뉴 없음 — 로컬 전용 지정/해제는 서버
              // is_my_face 와 어긋나던 funnel 이라 제거. 교체는 [다시 찍기]
              // (고정 row 덮어쓰기 — 서버 row·케미 슬롯·공유 링크 유지).
              itemBuilder: (ctx) => [
                if (isMyFace)
                  const PopupMenuItem<String>(
                    value: 'recapture',
                    child: Text('내 관상 다시 찍기', style: AppText.body),
                  ),
```

- [ ] **Step 2: ARCHITECTURE.md 에 고정 row 규칙 기록**

`flutter/docs/ARCHITECTURE.md` 의 metrics/내 관상 저장을 설명하는 절에 다음 취지의 1문단 추가 (주변 문체에 맞춰):

> 내 관상은 서버에 사용자당 1행, row id 영구 고정. 재촬영은 기존 row 에 새 body·새 썸네일 키로 덮어쓰고(웹 saveCapture 와 동일 모델) 옛 썸네일은 upsert 전에 `/api/r2/delete` 로 즉시 삭제. 케미 슬롯 FK 와 `/r/{id}` 링크는 항상 유효하며 최신 관상을 가리킨다. 신규 캡처의 "1 capture = 1 uuid" 는 유지 — 재촬영의 분석 uuid 는 썸네일 키로만 쓰인다.

- [ ] **Step 3: 검증**

Run: `cd /Users/chuck/Code/face/flutter && flutter analyze && flutter test`
Expected: 변경 파일 0 issue, 151 tests green.

- [ ] **Step 4: Commit**

```bash
cd /Users/chuck/Code/face
git add flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart flutter/docs/ARCHITECTURE.md
git commit -m "feat(flutter): 내 관상 카드에 '다시 찍기' 메뉴 — 고정 row 재촬영 진입점"
```

---

### Task 4: 통합 검증

- [ ] **Step 1: 전체 스위트** — `cd /Users/chuck/Code/face/flutter && flutter analyze && flutter test` green.
- [ ] **Step 2: 서버 불변식 스모크** — refine `.env` 의 service key 로 `metrics?is_my_face=eq.true` 조회, 사용자당 1행 유지 확인.
- [ ] **Step 3: 실기(사용자)** — 내 관상 카드 ⋮ → 다시 찍기 → 저장 후: (a) 서버 my-face 1행·id 불변 (b) body thumbnailKey 새 키 (c) 옛 썸네일 CDN 404 (d) 로컬 히스토리 내 관상 1장 (e) 모집 중 케미 방에 새 사진.
