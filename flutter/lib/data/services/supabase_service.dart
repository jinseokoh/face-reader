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
  Future<String> saveMetrics(FaceReadingReport report) async {
    final id = report.supabaseId ?? _uuid.v4();

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
      'user_id': _client.auth.currentUser?.id,
      'body': report.toBodyJson(),
      'alias': alias,
      'is_my_face': report.isMyFace,
    };

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
