import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:face_reader/domain/models/face_reading_report.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;
  static const _uuid = Uuid();

  /// Insert a face reading report into the metrics table.
  /// Uses the report's existing supabaseId if set (UUID-first architecture),
  /// otherwise generates a new one. Returns the UUID either way.
  Future<String> saveMetrics(FaceReadingReport report) async {
    final id = report.supabaseId ?? _uuid.v4();

    final data = {
      'id': id,
      'metrics_json': report.toJsonString(),
      'source': report.source.name,
      'ethnicity': report.ethnicity.name,
      'gender': report.gender.name,
      'age_group': report.ageGroup.name,
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

  /// Fetch two metrics records for compatibility reports.
  Future<List<Map<String, dynamic>>> getMetricsPair(
      String uuid1, String uuid2) async {
    final response = await _client
        .from('metrics')
        .select()
        .inFilter('id', [uuid1, uuid2]);
    return List<Map<String, dynamic>>.from(response);
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
}
