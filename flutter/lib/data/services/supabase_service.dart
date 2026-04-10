import 'dart:convert';

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
  /// Returns the generated UUID for sharing.
  Future<String> saveMetrics(FaceReadingReport report) async {
    final id = _uuid.v4();
    final expiresAt =
        DateTime.now().add(const Duration(days: 90)).toUtc().toIso8601String();

    final data = {
      'id': id,
      'metrics_json': _reportToJson(report),
      'source': report.source.name,
      'ethnicity': report.ethnicity.name,
      'gender': report.gender.name,
      'age_group': report.ageGroup.name,
      'expires_at': expiresAt,
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

  String _reportToJson(FaceReadingReport report) {
    final metricsMap = <String, dynamic>{};
    for (final entry in report.metrics.entries) {
      metricsMap[entry.key] = {
        'rawValue': entry.value.rawValue,
        'zScore': entry.value.zScore,
        'zAdjusted': entry.value.zAdjusted,
        'metricScore': entry.value.metricScore,
      };
    }

    final attributesMap = <String, double>{};
    for (final entry in report.attributeScores.entries) {
      attributesMap[entry.key.name] = entry.value;
    }

    final data = {
      'metrics': metricsMap,
      'attributeScores': attributesMap,
      'archetype': {
        'primary': report.archetype.primary.name,
        'secondary': report.archetype.secondary.name,
        'primaryLabel': report.archetype.primaryLabel,
        'secondaryLabel': report.archetype.secondaryLabel,
        'specialArchetype': report.archetype.specialArchetype,
      },
      'triggeredRules': report.triggeredRules
          .map((r) => {
                'id': r.id,
                'effects': {
                  for (final e in r.effects.entries) e.key.name: e.value,
                },
              })
          .toList(),
    };

    return jsonEncode(data);
  }
}
