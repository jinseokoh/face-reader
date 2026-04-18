import 'dart:convert';

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/archetype.dart';

// ────────────────────────── Primitives ──────────────────────────

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

/// 14-node tree 의 개별 node 측정 snapshot.
/// UI 의 "얼굴 부위별 균형" / "roll-up vs own" 시각화 근거.
class NodeEvidence {
  final String nodeId;
  final double ownMeanZ;
  final double ownMeanAbsZ;
  final double rollUpMeanZ;
  final double rollUpMeanAbsZ;

  const NodeEvidence({
    required this.nodeId,
    required this.ownMeanZ,
    required this.ownMeanAbsZ,
    required this.rollUpMeanZ,
    required this.rollUpMeanAbsZ,
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'ownMeanZ': ownMeanZ,
        'ownMeanAbsZ': ownMeanAbsZ,
        'rollUpMeanZ': rollUpMeanZ,
        'rollUpMeanAbsZ': rollUpMeanAbsZ,
      };

  factory NodeEvidence.fromJson(Map<String, dynamic> j) => NodeEvidence(
        nodeId: j['nodeId'] as String,
        ownMeanZ: (j['ownMeanZ'] as num).toDouble(),
        ownMeanAbsZ: (j['ownMeanAbsZ'] as num).toDouble(),
        rollUpMeanZ: (j['rollUpMeanZ'] as num).toDouble(),
        rollUpMeanAbsZ: (j['rollUpMeanAbsZ'] as num).toDouble(),
      );
}

/// Rule fire record. `stage` 는 'zone' | 'organ' | 'palace' | 'age' | 'lateral'.
class RuleEvidence {
  final String id;
  final String stage;
  final Map<Attribute, double> effects;

  const RuleEvidence({
    required this.id,
    required this.stage,
    required this.effects,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'stage': stage,
        'effects': {
          for (final e in effects.entries) e.key.name: e.value,
        },
      };

  factory RuleEvidence.fromJson(Map<String, dynamic> j) => RuleEvidence(
        id: j['id'] as String,
        stage: j['stage'] as String,
        effects: (j['effects'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(Attribute.values.byName(k), (v as num).toDouble()),
        ),
      );
}

/// Attribute 당 기여 원천 한 건. UI 의 "왜 이 점수?" top-N 근거.
/// `id` 예: `node:nose`, `distinctiveness`, `Z-03`, `O-NM1`, `P-CH`, `A-5X`, `L-AQ`.
class Contributor {
  final String id;
  final double value;

  const Contributor({required this.id, required this.value});

  Map<String, dynamic> toJson() => {'id': id, 'value': value};

  factory Contributor.fromJson(Map<String, dynamic> j) => Contributor(
        id: j['id'] as String,
        value: (j['value'] as num).toDouble(),
      );
}

/// 한 Attribute 의 전체 근거 패킷.
/// raw → normalize(5~10) 이 한 눈에 드러나고 기여 원천 리스트가 따라붙음.
class AttributeEvidence {
  final double rawTotal;
  final double normalizedScore;
  final Map<String, double> basePerNode;
  final double distinctiveness;

  /// `|value| > 0.05` 인 모든 원천, 절댓값 내림차순.
  /// UI 는 상단 N개만 잘라 표시 — 갯수 정책은 소비자에서 결정.
  final List<Contributor> contributors;

  const AttributeEvidence({
    required this.rawTotal,
    required this.normalizedScore,
    required this.basePerNode,
    required this.distinctiveness,
    required this.contributors,
  });

  Map<String, dynamic> toJson() => {
        'rawTotal': rawTotal,
        'normalizedScore': normalizedScore,
        'basePerNode': basePerNode,
        'distinctiveness': distinctiveness,
        'contributors': contributors.map((c) => c.toJson()).toList(),
      };

  factory AttributeEvidence.fromJson(Map<String, dynamic> j) =>
      AttributeEvidence(
        rawTotal: (j['rawTotal'] as num).toDouble(),
        normalizedScore: (j['normalizedScore'] as num).toDouble(),
        basePerNode: (j['basePerNode'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        distinctiveness: (j['distinctiveness'] as num).toDouble(),
        contributors: (j['contributors'] as List)
            .map((c) => Contributor.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

// ────────────────────────── Report ──────────────────────────

/// 스키마 버전. 엔진(weight matrix / rule / calibration / shape preset) 이
/// 실질적으로 바뀔 때마다 증가. history_provider 가 버전 불일치 리포트를
/// 자동 폐기하여 구 엔진 점수와 신 엔진 점수가 섞이지 않게 한다.
///
/// v1: legacy engine (proximity 기반, face/ear 포함 weight).
/// v2: 2026-04-18. face/ear 제외 9-노드 + shape preset + distinctiveness bell
///     + Opt-F rank 0.40/0.60 + 상관 MC 재보정.
const int kReportSchemaVersion = 2;

class FaceReadingReport {
  final Ethnicity ethnicity;
  final Gender gender;
  final AgeGroup ageGroup;
  final DateTime timestamp;
  final AnalysisSource source;

  String? supabaseId;
  String? alias;
  bool isMyFace;
  String? thumbnailPath;
  final DateTime expiresAt;

  /// 17 frontal metric results.
  final Map<String, MetricResult> metrics;

  /// 8 lateral metric results. null = 측면 캡처 미수행.
  final Map<String, MetricResult>? lateralMetrics;

  /// Lateral binary flags (aquilineNose, snubNose, …). null = 측면 미수행.
  final Map<String, bool>? lateralFlags;

  /// 14-node tree snapshot (root + 3 zones + 10 leaves).
  final Map<String, NodeEvidence> nodeScores;

  /// 10 attribute 별 전체 근거 (raw, normalized, contributors).
  final Map<Attribute, AttributeEvidence> attributes;

  /// 발동된 모든 rule (stage 구분 포함).
  final List<RuleEvidence> rules;

  /// Top-2 attribute 기반 archetype.
  final ArchetypeResult archetype;

  /// TFLite 28-feature MLP face-shape classifier 결과.
  /// `'Heart' | 'Oblong' | 'Oval' | 'Round' | 'Square'`. null = 분류기 미사용.
  final String? faceShapeLabel;
  final double? faceShapeConfidence;

  /// 도메인 얼굴형 — Stage 0 preset / archetype overlay / 서술 엔진 key.
  /// 분류기 실패 시 FaceShape.unknown.
  final FaceShape faceShape;

  /// 엔진 스키마 버전. [kReportSchemaVersion] 와 다르면 구 엔진 산출물 → 폐기.
  final int schemaVersion;

  FaceReadingReport({
    required this.ethnicity,
    required this.gender,
    required this.ageGroup,
    required this.timestamp,
    required this.source,
    this.supabaseId,
    this.alias,
    this.isMyFace = false,
    this.thumbnailPath,
    DateTime? expiresAt,
    required this.metrics,
    this.lateralMetrics,
    this.lateralFlags,
    required this.nodeScores,
    required this.attributes,
    required this.rules,
    required this.archetype,
    this.faceShapeLabel,
    this.faceShapeConfidence,
    this.faceShape = FaceShape.unknown,
    this.schemaVersion = kReportSchemaVersion,
  }) : expiresAt = expiresAt ?? DateTime.now().add(const Duration(days: 90));

  /// UI / assembler 공용 shortcut — 정규화 점수만 빠르게.
  Map<Attribute, double> get attributeScores => {
        for (final e in attributes.entries) e.key: e.value.normalizedScore,
      };

  String toJsonString() => jsonEncode({
        'schemaVersion': schemaVersion,
        'ethnicity': ethnicity.name,
        'gender': gender.name,
        'ageGroup': ageGroup.name,
        'timestamp': timestamp.toIso8601String(),
        'source': source.name,
        'supabaseId': supabaseId,
        'alias': alias,
        'isMyFace': isMyFace,
        'thumbnailPath': thumbnailPath,
        'expiresAt': expiresAt.toIso8601String(),
        'metrics': {
          for (final e in metrics.entries) e.key: e.value.toJson(),
        },
        if (lateralMetrics != null)
          'lateralMetrics': {
            for (final e in lateralMetrics!.entries) e.key: e.value.toJson(),
          },
        if (lateralFlags != null) 'lateralFlags': lateralFlags,
        'nodeScores': {
          for (final e in nodeScores.entries) e.key: e.value.toJson(),
        },
        'attributes': {
          for (final e in attributes.entries) e.key.name: e.value.toJson(),
        },
        'rules': rules.map((r) => r.toJson()).toList(),
        'archetype': {
          'primary': archetype.primary.name,
          'secondary': archetype.secondary.name,
          'primaryLabel': archetype.primaryLabel,
          'secondaryLabel': archetype.secondaryLabel,
          'specialArchetype': archetype.specialArchetype,
        },
        if (faceShapeLabel != null) 'faceShapeLabel': faceShapeLabel,
        if (faceShapeConfidence != null)
          'faceShapeConfidence': faceShapeConfidence,
        'faceShape': faceShape.name,
      });

  factory FaceReadingReport.fromJsonString(String jsonStr) {
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    final version = (j['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version != kReportSchemaVersion) {
      throw FormatException(
          'FaceReadingReport schemaVersion mismatch: $version != $kReportSchemaVersion');
    }
    return FaceReadingReport(
      ethnicity: Ethnicity.values.byName(j['ethnicity'] as String),
      gender: Gender.values.byName(j['gender'] as String),
      ageGroup: AgeGroup.values.byName(j['ageGroup'] as String),
      timestamp: DateTime.parse(j['timestamp'] as String),
      source: AnalysisSource.values.byName(j['source'] as String),
      supabaseId: j['supabaseId'] as String?,
      alias: j['alias'] as String?,
      isMyFace: j['isMyFace'] as bool? ?? false,
      thumbnailPath: j['thumbnailPath'] as String?,
      expiresAt: j['expiresAt'] != null
          ? DateTime.parse(j['expiresAt'] as String)
          : null,
      metrics: (j['metrics'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, MetricResult.fromJson(v as Map<String, dynamic>)),
      ),
      lateralMetrics: j['lateralMetrics'] == null
          ? null
          : (j['lateralMetrics'] as Map<String, dynamic>).map(
              (k, v) =>
                  MapEntry(k, MetricResult.fromJson(v as Map<String, dynamic>)),
            ),
      lateralFlags: j['lateralFlags'] == null
          ? null
          : (j['lateralFlags'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as bool)),
      nodeScores: (j['nodeScores'] as Map<String, dynamic>).map(
        (k, v) =>
            MapEntry(k, NodeEvidence.fromJson(v as Map<String, dynamic>)),
      ),
      attributes: (j['attributes'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          Attribute.values.byName(k),
          AttributeEvidence.fromJson(v as Map<String, dynamic>),
        ),
      ),
      rules: (j['rules'] as List)
          .map((r) => RuleEvidence.fromJson(r as Map<String, dynamic>))
          .toList(),
      archetype: ArchetypeResult(
        primary:
            Attribute.values.byName(j['archetype']['primary'] as String),
        secondary:
            Attribute.values.byName(j['archetype']['secondary'] as String),
        primaryLabel: j['archetype']['primaryLabel'] as String,
        secondaryLabel: j['archetype']['secondaryLabel'] as String,
        specialArchetype: j['archetype']['specialArchetype'] as String?,
      ),
      faceShapeLabel: j['faceShapeLabel'] as String?,
      faceShapeConfidence: (j['faceShapeConfidence'] as num?)?.toDouble(),
      faceShape: j['faceShape'] is String
          ? FaceShape.values.byName(j['faceShape'] as String)
          : FaceShapeLabel.fromEnglish(j['faceShapeLabel'] as String?),
      schemaVersion: version,
    );
  }
}
