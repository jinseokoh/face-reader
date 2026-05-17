import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_engine/data/enums/age_group.dart';
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
      'metrics_json': report.toJsonString(),
      'source': report.source.name,
      'ethnicity': report.ethnicity.name,
      'gender': report.gender.name,
      'age_group': report.ageGroup.jsonValue,
      'expires_at': report.expiresAt.toUtc().toIso8601String(),
    };

    await _client.from('metrics').insert(data);
    debugPrint('[Supabase] saved metrics id=$id');
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
  Future<void> upsertMetricsJson(FaceReadingReport report) async {
    final id = report.supabaseId;
    if (id == null) return;
    await _client.from('metrics').upsert({
      'id': id,
      'user_id': _client.auth.currentUser?.id,
      'metrics_json': report.toJsonString(),
      'source': report.source.name,
      'ethnicity': report.ethnicity.name,
      'gender': report.gender.name,
      'age_group': report.ageGroup.jsonValue,
      'expires_at': report.expiresAt.toUtc().toIso8601String(),
    });
    debugPrint('[Supabase] upserted metrics id=$id');
  }
}
