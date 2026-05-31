import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';

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

    final data = {
      'id': id,
      'user_id': _client.auth.currentUser?.id,
      'body': report.toBodyJson(),
      'is_my_face': report.isMyFace,
      'expires_at': report.expiresAt.toUtc().toIso8601String(),
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
          .select('id, expires_at, views');
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
      'expires_at': report.expiresAt.toUtc().toIso8601String(),
    });
    debugPrint('[Supabase] upserted metrics id=$id');
  }
}
