import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/auth_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;
  static const _uuid = Uuid();

  /// Insert a face reading report into the metrics table.
  ///
  /// UUID 정책 — "1 face capture = 1 UUID":
  ///   * 정상 경로: analyze 시점에 [FaceMetadataClient] 가 발급한 uuid 가 이미
  ///     report.supabaseId 로 흘러들어와 있어야 한다 (temp/·thumbnails/·
  ///     metrics.id·/r/{uuid} 가 동일 trace id 로 묶임).
  ///   * fallback v4: analyze 미경유 케이스 한정 — 라이브 mesh-only 캡처
  ///     (R2 업로드 없이 메타만), legacy entry, compat 페어링의 보조 슬롯 등.
  /// 결과 UUID 를 반환.
  ///
  /// **[report] 를 바꾸지 않는다.** 넘어오는 카드는 Hive 가 이미 저장을 끝낸
  /// 객체라, 여기서 필드를 손대면 메모리와 Hive 가 갈린다 (갈린 카드는 다음
  /// 당김 동기화에서 서버와 어긋난 것으로 취급돼 썸네일·심하면 카드 자체를
  /// 잃는다). 최종 id 는 **반환값**으로만 알린다 — 로컬 카드에 반영할지는
  /// 호출부가 정하고, 반영했으면 호출부가 Hive 에 다시 쓴다.
  Future<String> saveMetrics(FaceReadingReport report) async {
    final uid = _client.auth.currentUser?.id;

    // 내 관상 고정 row — 서버에 기존 my-face row 가 있으면 새 row 를 만들지
    // 않고 그 id 에 덮어쓴다 (row id 영구 고정 · 웹 saveCapture 와 동일 모델.
    // 케미 슬롯 FK·/r/{id} 링크가 항상 유효하고 최신 관상을 가리킴).
    ({String id, String? thumbnailKey})? existing;
    // 새 썸네일이 없으면(crop 실패 등) body 가 계속 옛 키를 가리키게 둔다 —
    // 살아있는 R2 객체를 가리켜야 아바타가 안 깨진다 (웹 saveCapture 와 동일).
    //
    // 교체된 옛 객체를 여기서 지우지 않는다. body 를 새 키로 upsert 하면
    // metrics_thumbnail_gc 트리거가 옛 키를 아웃박스에 넣고, cron 이 참조를
    // 확인한 뒤 지운다 — 실패해도 재시도되고 순서 제약도 없다.
    String? bodyKey = report.thumbnailKey;
    if (report.isMyFace && uid != null) {
      existing = await myFaceRow();
      bodyKey ??= existing?.thumbnailKey;
    }

    final id = existing?.id ?? report.supabaseId ?? _uuid.v4();

    // alias 컬럼 = 소유자 지정 이름 (RLS 는 body 안의 alias 만 금지 — 컬럼 OK).
    // 내 관상의 로컬 전용 표기 '나' 는 서버 밖에선 무의미 — 설정에서 수정
    // 가능한 프로필 nickname 을 fallback 으로 올린다. 상대방 row 는 내가
    // 지정한 이름 그대로 (nickname 은 내 이름이라 fallback 대상 아님).
    final alias = report.isMyFace &&
            (report.alias == null || report.alias == '나')
        ? AuthService().currentUser?.nickname
        : report.alias;

    final data = {
      'id': id,
      'user_id': uid,
      'body': bodyWithThumbnailKey(report, bodyKey),
      'alias': alias,
      'is_my_face': report.isMyFace,
    };

    // 내 관상 불변식 안전망 — is_my_face=true 는 사용자당 최대 1행. 새 my-face
    // 를 올리기 직전에 서버의 다른 true 행을 일반 카드로 강등해, 멀티 기기 등록
    // 이나 과거에 쌓인 중복을 등록 시점마다 자동 치유한다. 옛 행은 삭제가 아닌
    // 강등 — 팀 슬롯(team_members.metrics_id) 참조와 공유 링크를 살린다.
    if (report.isMyFace && uid != null) {
      try {
        await _client
            .from('metrics')
            .update({'is_my_face': false})
            .eq('user_id', uid)
            .eq('is_my_face', true)
            .neq('id', id);
      } catch (e) {
        debugPrint('[Supabase.saveMetrics] my-face demote error (계속 진행): $e');
      }
    }

    // upsert — analyze 시점에 발급된 UUID 가 이미 row 로 들어가 있을 수도
    // (재시도 / pull-to-refresh). insert 면 PK 충돌, 무엇보다 RLS reject 가
    // 조용히 묻혀 /r/{uuid} 가 404 로 빠지는 사고가 없도록 명시 upsert.
    debugPrint('[Supabase.saveMetrics] start id=$id user_id=${data['user_id']} '
        'body_len=${(data['body'] as String).length}');
    try {
      // select() 를 붙여 실제 written row 가 돌아오게 한다. RLS 거부 시
      // PostgrestException 으로 throw → catch 에서 상세 로그.
      final res = await _client
          .from('metrics')
          .upsert(data, onConflict: 'id')
          .select('id, views');
      debugPrint('[Supabase.saveMetrics] OK id=$id response=$res');
    } catch (e, st) {
      debugPrint('[Supabase.saveMetrics] FAIL id=$id error=$e');
      debugPrint('[Supabase.saveMetrics] stacktrace:\n$st');
      rethrow;
    }
    return id;
  }

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

  /// 저장 전에 호출해 재촬영 카드가 처음부터 고정 row id 와 서버가 들고 있는
  /// 썸네일 키를 갖게 한다 — 로컬 히스토리의 supabaseId 교체(add)와 saveMetrics
  /// 덮어쓰기가 같은 row 를 가리키고, Hive 에 들어가는 카드가 서버 body 와 같은
  /// 썸네일을 가리키게 하는 전제. 비로그인·행 없음·조회 실패면 null.
  Future<({String id, String? thumbnailKey})?> myFaceRow() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    return _myFaceRow(uid);
  }

  /// body 직렬화 + thumbnailKey 만 [key] 로 교체. report 를 건드리지 않고
  /// 서버에 실을 값만 바꾸기 위한 것 (body-override 파싱과 같은 문법).
  @visibleForTesting
  static String bodyWithThumbnailKey(FaceReadingReport report, String? key) {
    if (key == report.thumbnailKey) return report.toBodyJson();
    final body = jsonDecode(report.toBodyJson()) as Map<String, dynamic>;
    if (key == null) {
      body.remove('thumbnailKey');
    } else {
      body['thumbnailKey'] = key;
    }
    return jsonEncode(body);
  }

  /// 로그인 사용자 소유 metrics 전체 — 로그인 rehydrate(새 기기 복원)용.
  /// 최신 우선 정렬 (history 리스트 관례 newest-first 와 일치).
  Future<List<Map<String, dynamic>>> fetchMyMetrics() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('metrics')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Fetch a single metrics record by UUID (for shared links).
  Future<Map<String, dynamic>?> getMetrics(String uuid) async {
    final response = await _client
        .from('metrics')
        .select()
        .eq('id', uuid)
        .maybeSingle();
    return response;
  }

  /// Delete a metrics record by UUID
  Future<void> deleteMetrics(String uuid) async {
    await _client.from('metrics').delete().eq('id', uuid);
    debugPrint('[Supabase] deleted metrics id=$uuid');
  }

  /// Update alias for a metrics record
  Future<void> updateAlias(String uuid, String alias) async {
    await _client.from('metrics').update({'alias': alias}).eq('id', uuid);
    debugPrint('[Supabase] updated alias id=$uuid alias=$alias');
  }

  /// Upsert metrics payload for an existing record. pull-to-refresh 후 slim
  /// capture JSON 을 서버에 동기화하는 용도. is_my_face 는 싣지 않는다 —
  /// 로컬 플래그가 없는 기기가 서버의 내 관상 지정을 false 로 덮어쓰는 사고
  /// 방지. 플래그 쓰기는 saveMetrics(등록)와 claim 의 승격/강등 안전망 한정.
  Future<void> upsertMetricsBody(FaceReadingReport report) async {
    final id = report.supabaseId;
    if (id == null) return;
    await _client.from('metrics').upsert({
      'id': id,
      'user_id': _client.auth.currentUser?.id,
      'body': report.toBodyJson(),
    });
    debugPrint('[Supabase] upserted metrics id=$id');
  }

  /// 로그인 직후 호출 — 비로그인(user_id=null) 상태로 만들어둔 metrics row 들을
  /// 현재 사용자 소유로 한 번에 귀속한다.
  ///
  /// 범위를 [ids] (로컬 Hive history 가 보유한 supabaseId) 로 한정하는 것이
  /// 핵심: `user_id is null` 인 row 는 다른 기기의 익명 분석에도 존재하므로,
  /// id 범위 없이 갱신하면 남의 익명 카드까지 가로챈다. is null 필터까지 더해
  /// 이미 소유된 행(받은 카드 등)은 건드리지 않는다. RLS metrics_owner_update
  /// (USING user_id null|본인, WITH CHECK user_id = auth.uid) 가 이를 허용.
  Future<void> claimAnonymousMetrics(
    List<String> ids, {
    String? myFaceId,
    String? nickname,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || ids.isEmpty) return;
    await _client
        .from('metrics')
        .update({'user_id': uid})
        .inFilter('id', ids)
        .isFilter('user_id', null);
    debugPrint('[Supabase] claimed anon metrics → $uid (scope=${ids.length})');
    // 익명 시절 비어 있던 내 관상 alias 를 프로필 nickname 으로 backfill —
    // 익명 촬영 → 나중에 로그인한 시나리오. alias 가 이미 있으면(사용자 지정
    // 이름 등) 보존 (is null 가드).
    if (myFaceId != null && nickname != null && nickname.isNotEmpty) {
      await _client
          .from('metrics')
          .update({'alias': nickname})
          .eq('id', myFaceId)
          .isFilter('alias', null);
      debugPrint('[Supabase] backfilled my-face alias ← $nickname');
    }
    // 방금 귀속된 내 관상이 유일한 my-face 가 되도록 승격 + 강등을 쌍으로
    // 실행한다 (is_my_face=true 는 사용자당 최대 1행 — saveMetrics 안전망과
    // 동일 규칙). 승격이 없으면 서버 플래그가 false 인 행을 로컬이 내 관상으로
    // 기억하는 기기가 강등만 실행해 계정의 true 행이 0이 되고, 이후 새 기기
    // 로그인이 내 관상 없는 상태로 복원되는 사고가 난다 (2026-07-30 실사고).
    // 강등은 삭제가 아님 — 팀 슬롯 FK(team_members.metrics_id)·공유 링크는
    // 살아 있다. 실패해도 claim 자체는 유효 — 앱 재시작 claim 에서 재시도된다.
    if (myFaceId != null) {
      try {
        // 승격이 실제로 행을 바꿨을 때만 강등한다. myFaceId 가 이 계정 소유가
        // 아니면 승격은 매치 0 으로 조용히 지나가는데, 강등은 neq(myFaceId)
        // 라 **이 계정의 진짜 my-face 행**을 제외 대상에서 놓치고 꺼 버린다
        // (계정의 true 행이 0 → 새 기기 로그인이 내 관상 없이 복원). 승격
        // 결과를 받아 게이트를 걸면 그 경로가 구조적으로 막힌다.
        final promoted = await _client
            .from('metrics')
            .update({'is_my_face': true})
            .eq('id', myFaceId)
            .eq('user_id', uid)
            .select('id');
        if (promoted.isEmpty) {
          debugPrint('[Supabase] my-face promote 매치 0 — 강등 skip '
              '(id=$myFaceId 는 $uid 소유 아님)');
        } else {
          await _client
              .from('metrics')
              .update({'is_my_face': false})
              .eq('user_id', uid)
              .eq('is_my_face', true)
              .neq('id', myFaceId);
          debugPrint('[Supabase] promoted my-face + demoted stale rows '
              '(keep=$myFaceId)');
        }
      } catch (e) {
        debugPrint('[Supabase] my-face promote/demote error (계속 진행): $e');
      }
    }
  }
}
