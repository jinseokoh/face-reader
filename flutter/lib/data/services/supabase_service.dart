import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/r2_uploader.dart';

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
  Future<String> saveMetrics(FaceReadingReport report) async {
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
      'body': report.toBodyJson(),
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

  /// 저장 전에 호출해 재촬영 카드가 처음부터 고정 row id 를 갖게 한다 —
  /// 로컬 히스토리의 supabaseId 교체(add)와 saveMetrics 덮어쓰기가 같은
  /// row 를 가리키는 전제. 비로그인·행 없음·조회 실패면 null.
  Future<String?> myFaceRowId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    return (await _myFaceRow(uid))?.id;
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
  /// capture JSON 을 서버에 동기화하는 용도.
  Future<void> upsertMetricsBody(FaceReadingReport report) async {
    final id = report.supabaseId;
    if (id == null) return;
    await _client.from('metrics').upsert({
      'id': id,
      'user_id': _client.auth.currentUser?.id,
      'body': report.toBodyJson(),
      'is_my_face': report.isMyFace,
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
  }
}
