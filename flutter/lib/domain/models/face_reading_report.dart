import 'dart:convert';
import 'dart:developer' as dev;

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/age_adjustment.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/metric_score.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

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

/// Hive capture 스키마 버전. metric 리스트·포맷이 바뀔 때만 증가.
///
/// 엔진(weight matrix · rule · calibration) 변경은 이 버전을 건드리지 않는다 —
/// 해석은 Hive 에 저장하지 않고 load 시 현재 엔진으로 재계산되므로 자동으로
/// 최신 값이 반영된다.
const int kReportSchemaVersion = 1;

/// fromJsonString 의 각 rehydrate 단계를 trace — parse 실패 시 마지막 로그의
/// 다음 단계가 범인. `print` 는 rate-limit 없어 반드시 찍힘.
void _trace(String step) {
  // ignore: avoid_print
  print('[Report.rehydrate] $step');
  dev.log(step, name: 'Report.rehydrate');
}

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

  /// v3 (2026-04-18): capture-only serialization. 저장하는 것은 **metric rawValue
  /// 와 camera meta(ethnicity/gender/ageGroup/faceShape…) 뿐**이다. z-score,
  /// zAdjusted, metricScore, lateralFlags, nodeScores, attributes, rules,
  /// archetype — 전부 엔진에서 파생되는 값이므로 저장하지 않는다. load 시 현재
  /// reference·age adjustment·rule·quantile 로 100% 재계산된다. 엔진·ref 가
  /// 바뀌면 기존 리포트가 자동으로 새 공식의 결과를 받는다.
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
        // rawValue 만 저장 — id → double. 현재 ref 에 의존하는 z/zAdjusted/
        // metricScore 는 절대 저장 금지 (저장하면 ref 변경이 기존 리포트에
        // 반영되지 않는 stale-z 버그 발생).
        'metrics': {
          for (final e in metrics.entries) e.key: e.value.rawValue,
        },
        if (lateralMetrics != null)
          'lateralMetrics': {
            for (final e in lateralMetrics!.entries) e.key: e.value.rawValue,
          },
        // lateralFlags 는 lateral z + 현재 metricScore 임계로 load 시 재계산.
        if (faceShapeLabel != null) 'faceShapeLabel': faceShapeLabel,
        if (faceShapeConfidence != null)
          'faceShapeConfidence': faceShapeConfidence,
        'faceShape': faceShape.name,
      });

  /// v3: capture 만 역직렬화하고 derived (nodeScores·attributes·rules·
  /// archetype) 는 현재 엔진으로 **load 시 재계산**한다. 구 버전(v1/v2) 은
  /// 폐기.
  factory FaceReadingReport.fromJsonString(String jsonStr) {
    _trace('enter len=${jsonStr.length}');
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    _trace('jsonDecode OK keys=${j.keys.toList()}');
    final version = (j['schemaVersion'] as num?)?.toInt() ?? 0;
    _trace('schemaVersion=$version (expected $kReportSchemaVersion)');
    if (version != kReportSchemaVersion) {
      throw FormatException(
          'FaceReadingReport schemaVersion mismatch: $version != $kReportSchemaVersion');
    }

    // ─── capture 필드 파싱 ───
    _trace('enum decode: ethnicity=${j['ethnicity']} gender=${j['gender']} '
        'ageGroup=${j['ageGroup']} source=${j['source']}');
    final ethnicity = Ethnicity.values.byName(j['ethnicity'] as String);
    final gender = Gender.values.byName(j['gender'] as String);
    final ageGroup = AgeGroup.values.byName(j['ageGroup'] as String);
    final isOver50 = ageGroup.isOver50;
    _trace('enums OK: $ethnicity/$gender/$ageGroup isOver50=$isOver50');
    final rawMetrics = _extractRawMap(j['metrics']);
    _trace('rawMetrics: ${rawMetrics.length} keys=${rawMetrics.keys.toList()}');
    final rawLateral = j['lateralMetrics'] == null
        ? null
        : _extractRawMap(j['lateralMetrics']);
    _trace('rawLateral: ${rawLateral?.length ?? "null"} '
        '${rawLateral?.keys.toList() ?? ""}');
    final faceShapeLabel = j['faceShapeLabel'] as String?;
    final faceShapeConfidence = (j['faceShapeConfidence'] as num?)?.toDouble();
    _trace('faceShapeLabel=$faceShapeLabel conf=$faceShapeConfidence '
        'faceShapeRaw=${j['faceShape']}');
    final faceShape = j['faceShape'] is String
        ? FaceShape.values.byName(j['faceShape'] as String)
        : FaceShapeLabel.fromEnglish(faceShapeLabel);
    _trace('faceShape=$faceShape');

    // ─── rawValue → 현재 reference 로 재 z-score ───
    // 저장은 rawValue 만. z/zAdjusted/metricScore 는 현재 ref·age adjustment 로
    // 여기서 100% 재계산된다. reference 를 바꾸면 기존 리포트도 새 ref 기준의
    // 해석을 받는다 — stale-z 고착 버그 차단.
    _trace('frontalRefs lookup: referenceData[$ethnicity]?=${referenceData[ethnicity] != null} '
        '[gender]?=${referenceData[ethnicity]?[gender] != null}');
    final frontalRefs = referenceData[ethnicity]![gender]!;
    _trace('frontalRefs ${frontalRefs.length} keys=${frontalRefs.keys.toList()}');
    final metrics = <String, MetricResult>{};
    final zAdjustedMap = <String, double>{};
    for (final info in metricInfoList) {
      final raw = rawMetrics[info.id];
      if (raw == null) continue; // 구 리포트 누락 metric 은 skip
      if (frontalRefs[info.id] == null) {
        _trace('MISS frontalRefs[${info.id}] — throw');
      }
      final ref = frontalRefs[info.id]!;
      final z = (raw - ref.mean) / ref.sd;
      final zAdj = adjustForAge(info.id, z, gender, isOver50);
      zAdjustedMap[info.id] = zAdj;
      metrics[info.id] = MetricResult(
        id: info.id,
        rawValue: raw,
        zScore: z,
        zAdjusted: zAdj,
        metricScore: convertToScore(zAdj, info.type),
      );
    }
    _trace('frontal z done: ${metrics.length} metrics');

    Map<String, MetricResult>? lateralMetrics;
    Map<String, bool>? lateralFlags;
    final lateralZMap = <String, double>{};
    if (rawLateral != null) {
      _trace('lateralRefs lookup: lateralReferenceData[$ethnicity]?='
          '${lateralReferenceData[ethnicity] != null} '
          '[gender]?=${lateralReferenceData[ethnicity]?[gender] != null}');
      final lateralRefs = lateralReferenceData[ethnicity]![gender]!;
      lateralMetrics = <String, MetricResult>{};
      final lateralScores = <String, int>{};
      for (final info in lateralMetricInfoList) {
        final raw = rawLateral[info.id];
        if (raw == null) continue;
        if (lateralRefs[info.id] == null) {
          _trace('MISS lateralRefs[${info.id}] — throw');
        }
        final ref = lateralRefs[info.id]!;
        final z = (raw - ref.mean) / ref.sd;
        final score = convertToScore(z, info.type);
        lateralZMap[info.id] = z;
        lateralScores[info.id] = score;
        lateralMetrics[info.id] = MetricResult(
          id: info.id,
          rawValue: raw,
          zScore: z,
          zAdjusted: z,
          metricScore: score,
        );
      }
      _trace('lateral z done: ${lateralMetrics.length} metrics');
      // Lateral flags — 현재 z 기준으로 재계산 (face_analysis.dart 의 동일 로직).
      final dorsalScore = lateralScores['dorsalConvexity'] ?? 0;
      final nasoLabScore = lateralScores['nasolabialAngle'] ?? 0;
      final nasoLabRaw = rawLateral['nasolabialAngle'] ?? 0.0;
      final tipProjScore = lateralScores['noseTipProjection'] ?? 0;
      lateralFlags = {
        'aquilineNose': dorsalScore >= 3,
        'snubNose': nasoLabScore >= 2 && nasoLabRaw >= 115.0,
        'droopingTip': nasoLabScore <= -2 && nasoLabRaw <= 112.0,
        'saddleNose': dorsalScore <= -3,
        'flatNose': tipProjScore <= -3,
      };
      _trace('lateralFlags=$lateralFlags');
    }

    // ─── derived 재계산 (현재 엔진) ───
    final zForTree = <String, double>{...zAdjustedMap, ...lateralZMap};
    _trace('scoreTree input ${zForTree.length} z');
    final tree = scoreTree(zForTree);
    _trace('scoreTree OK');
    final breakdown = deriveAttributeScoresDetailed(
      tree: tree,
      gender: gender,
      isOver50: ageGroup.isOver50,
      hasLateral: lateralMetrics != null,
      lateralFlags: lateralFlags ?? const {},
      faceShape: faceShape,
      shapeConfidence: faceShapeConfidence ?? 0.0,
    );
    _trace('deriveAttributeScoresDetailed OK');
    final normalizedScores = normalizeAllScores(breakdown.total, gender);
    _trace('normalizeAllScores OK');
    final archetype = classifyArchetype(normalizedScores, shape: faceShape);
    _trace('classifyArchetype OK → ${archetype.runtimeType}');

    final nodeScores = _rehydrateNodeScores(tree);
    final attributes = _rehydrateAttributeEvidence(breakdown, normalizedScores);
    final rules = _rehydrateRuleEvidence(breakdown);
    _trace('rehydrate evidence done: nodes=${nodeScores.length} '
        'attrs=${attributes.length} rules=${rules.length}');

    return FaceReadingReport(
      ethnicity: ethnicity,
      gender: gender,
      ageGroup: ageGroup,
      timestamp: DateTime.parse(j['timestamp'] as String),
      source: AnalysisSource.values.byName(j['source'] as String),
      supabaseId: j['supabaseId'] as String?,
      alias: j['alias'] as String?,
      isMyFace: j['isMyFace'] as bool? ?? false,
      thumbnailPath: j['thumbnailPath'] as String?,
      expiresAt: j['expiresAt'] != null
          ? DateTime.parse(j['expiresAt'] as String)
          : null,
      metrics: metrics,
      lateralMetrics: lateralMetrics,
      lateralFlags: lateralFlags,
      nodeScores: nodeScores,
      attributes: attributes,
      rules: rules,
      archetype: archetype,
      faceShapeLabel: faceShapeLabel,
      faceShapeConfidence: faceShapeConfidence,
      faceShape: faceShape,
      schemaVersion: version,
    );
  }
}

// ─── 직렬화 호환 헬퍼 ─────────────────────────────────────────────────
//
// `metrics` / `lateralMetrics` 는 v3 에서 `{id: rawValue(double)}` 로 슬림화.
// 과거 payload 는 `{id: {rawValue, zScore, …}}` 였는데 그 경우에도 rawValue 만
// 꺼내 쓴다 — 저장된 z 는 신뢰하지 않는다 (stale-z 버그 차단).
Map<String, double> _extractRawMap(Object? raw) {
  final map = raw as Map<String, dynamic>;
  final out = <String, double>{};
  for (final e in map.entries) {
    final v = e.value;
    if (v is num) {
      out[e.key] = v.toDouble();
    } else if (v is Map<String, dynamic>) {
      final r = v['rawValue'];
      if (r is num) out[e.key] = r.toDouble();
    }
  }
  return out;
}

// ─── 재계산 헬퍼 (capture → derived) ──────────────────────────────────
//
// face_analysis.dart 의 _collectNodeScores / _buildAttributeEvidence /
// _buildRuleEvidence 와 동일 로직. fresh capture 경로와 rehydrate 경로가
// 동일한 derived 필드를 만들어야 하므로 두 곳이 일치해야 한다.

Map<String, NodeEvidence> _rehydrateNodeScores(NodeScore root) {
  final out = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    out[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final c in node.children) {
      walk(c);
    }
  }
  walk(root);
  return out;
}

Map<Attribute, AttributeEvidence> _rehydrateAttributeEvidence(
  AttributeBreakdown breakdown,
  Map<Attribute, double> normalizedScores,
) {
  final out = <Attribute, AttributeEvidence>{};
  for (final attr in Attribute.values) {
    final base = breakdown.basePerNode[attr] ?? const <String, double>{};
    final dist = breakdown.distinctiveness[attr] ?? 0.0;
    final raw = breakdown.total[attr] ?? 0.0;
    final normalized = normalizedScores[attr] ?? 5.0;

    final bag = <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
    final sh = breakdown.shapePreset[attr] ?? 0.0;
    if (sh.abs() > 0.05) bag['shape'] = sh;
    if (dist.abs() > 0.05) bag['distinctiveness'] = dist;
    for (final r in breakdown.zoneRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.organRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.palaceRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.ageRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }
    for (final r in breakdown.lateralRules) {
      final v = r.effects[attr];
      if (v != null && v.abs() > 0.05) bag[r.id] = v;
    }

    final sorted = bag.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final contributors = sorted
        .map((e) => Contributor(id: e.key, value: e.value))
        .toList();

    out[attr] = AttributeEvidence(
      rawTotal: raw,
      normalizedScore: normalized,
      basePerNode: Map<String, double>.from(base),
      distinctiveness: dist,
      contributors: contributors,
    );
  }
  return out;
}

List<RuleEvidence> _rehydrateRuleEvidence(AttributeBreakdown breakdown) {
  final out = <RuleEvidence>[];
  for (final r in breakdown.zoneRules) {
    out.add(RuleEvidence(id: r.id, stage: 'zone', effects: r.effects));
  }
  for (final r in breakdown.organRules) {
    out.add(RuleEvidence(id: r.id, stage: 'organ', effects: r.effects));
  }
  for (final r in breakdown.palaceRules) {
    out.add(RuleEvidence(id: r.id, stage: 'palace', effects: r.effects));
  }
  for (final r in breakdown.ageRules) {
    out.add(RuleEvidence(id: r.id, stage: 'age', effects: r.effects));
  }
  for (final r in breakdown.lateralRules) {
    out.add(RuleEvidence(id: r.id, stage: 'lateral', effects: r.effects));
  }
  return out;
}
