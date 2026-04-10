import 'dart:convert';

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';

class MetricResult {
  final String id;
  final double rawValue;
  final double zScore;
  final double zAdjusted;
  final int metricScore;

  const MetricResult({
    required this.id,
    required this.rawValue,
    required this.zScore,
    required this.zAdjusted,
    required this.metricScore,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawValue': rawValue,
        'zScore': zScore,
        'zAdjusted': zAdjusted,
        'metricScore': metricScore,
      };

  factory MetricResult.fromJson(Map<String, dynamic> j) => MetricResult(
        id: j['id'] as String,
        rawValue: (j['rawValue'] as num).toDouble(),
        zScore: (j['zScore'] as num).toDouble(),
        zAdjusted: (j['zAdjusted'] as num).toDouble(),
        metricScore: j['metricScore'] as int,
      );
}

enum AnalysisSource { camera, album }

class FaceReadingReport {
  final Ethnicity ethnicity;
  final Gender gender;
  final AgeGroup ageGroup;
  final DateTime timestamp;
  final AnalysisSource source;
  String? supabaseId;
  String? alias;
  bool isMyFace;
  final DateTime expiresAt;

  /// 17 metric results
  final Map<String, MetricResult> metrics;

  /// 10 attribute scores (0~10)
  final Map<Attribute, double> attributeScores;

  /// Archetype classification
  final ArchetypeResult archetype;

  /// Rules that were triggered
  final List<TriggeredRule> triggeredRules;

  FaceReadingReport({
    required this.ethnicity,
    required this.gender,
    required this.ageGroup,
    required this.timestamp,
    required this.source,
    this.supabaseId,
    this.alias,
    this.isMyFace = false,
    DateTime? expiresAt,
    required this.metrics,
    required this.attributeScores,
    required this.archetype,
    required this.triggeredRules,
  }) : expiresAt = expiresAt ?? DateTime.now().add(const Duration(days: 90));

  String toJsonString() => jsonEncode({
        'ethnicity': ethnicity.name,
        'gender': gender.name,
        'ageGroup': ageGroup.name,
        'timestamp': timestamp.toIso8601String(),
        'source': source.name,
        'supabaseId': supabaseId,
        'alias': alias,
        'isMyFace': isMyFace,
        'expiresAt': expiresAt.toIso8601String(),
        'metrics': {
          for (final e in metrics.entries) e.key: e.value.toJson(),
        },
        'attributeScores': {
          for (final e in attributeScores.entries) e.key.name: e.value,
        },
        'archetype': {
          'primary': archetype.primary.name,
          'secondary': archetype.secondary.name,
          'primaryLabel': archetype.primaryLabel,
          'secondaryLabel': archetype.secondaryLabel,
          'specialArchetype': archetype.specialArchetype,
        },
        'triggeredRules': triggeredRules
            .map((r) => {
                  'id': r.id,
                  'effects': {
                    for (final e in r.effects.entries) e.key.name: e.value,
                  },
                })
            .toList(),
      });

  factory FaceReadingReport.fromJsonString(String jsonStr) {
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    return FaceReadingReport(
      ethnicity: Ethnicity.values.byName(j['ethnicity'] as String),
      gender: Gender.values.byName(j['gender'] as String),
      ageGroup: AgeGroup.values.byName(j['ageGroup'] as String),
      timestamp: DateTime.parse(j['timestamp'] as String),
      source: AnalysisSource.values.byName(j['source'] as String),
      supabaseId: j['supabaseId'] as String?,
      alias: j['alias'] as String?,
      isMyFace: j['isMyFace'] as bool? ?? false,
      expiresAt: j['expiresAt'] != null ? DateTime.parse(j['expiresAt'] as String) : null,
      metrics: (j['metrics'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, MetricResult.fromJson(v as Map<String, dynamic>)),
      ),
      attributeScores: (j['attributeScores'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(Attribute.values.byName(k), (v as num).toDouble()),
      ),
      archetype: ArchetypeResult(
        primary: Attribute.values.byName(j['archetype']['primary'] as String),
        secondary: Attribute.values.byName(j['archetype']['secondary'] as String),
        primaryLabel: j['archetype']['primaryLabel'] as String,
        secondaryLabel: j['archetype']['secondaryLabel'] as String,
        specialArchetype: j['archetype']['specialArchetype'] as String?,
      ),
      triggeredRules: (j['triggeredRules'] as List).map((r) {
        final rMap = r as Map<String, dynamic>;
        return TriggeredRule(
          rMap['id'] as String,
          (rMap['effects'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(Attribute.values.byName(k), (v as num).toDouble()),
          ),
        );
      }).toList(),
    );
  }
}
