import 'package:flutter/foundation.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/services/face_shape_classifier.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/age_adjustment.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/face_metrics.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:face_reader/domain/services/metric_score.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

/// Full face-reading pipeline (see docs/ARCHITECTURE.md §4)
///
/// [lateralLandmarks] is OPTIONAL. When provided (a separate 3/4-view capture),
/// lateral metrics are computed and z-scored against lateral reference data,
/// and lateral binary flags (e.g. aquilineNose) are populated. Lateral rules
/// in the rule engine then become eligible to fire.
FaceReadingReport analyzeFaceReading({
  required List<FaceMeshLandmark> landmarks,
  required Ethnicity ethnicity,
  required Gender gender,
  required AgeGroup ageGroup,
  required AnalysisSource source,
  required int imageWidth,
  required int imageHeight,
  List<FaceMeshLandmark>? lateralLandmarks,
}) {
  final isOver50 = ageGroup.isOver50;

  // Step 1: Compute 15 raw metrics
  final faceMetrics = FaceMetrics(landmarks);
  final measured = faceMetrics.computeAll();

  // Correct faceAspectRatio:
  // 1) Non-square image: landmarks normalized 0~1 independently per axis
  // 2) Landmark 10 (foreheadTop) sits below actual hairline
  //    → Adjust this single value to fine-tune face shape classification
  const kLandmark10Correction = 1.05; // > 1.0 = 더 길게 보정
  final aspectCorrection = imageHeight / imageWidth;
  final faceAspectRaw = measured['faceAspectRatio']!; // pre-correction
  measured['faceAspectRatio'] =
      faceAspectRaw * aspectCorrection * kLandmark10Correction;

  debugPrint('[Analysis] faceAspectRatio raw=${measured['faceAspectRatio']?.toStringAsFixed(4)} '
      'faceH=${faceMetrics.faceHeight.toStringAsFixed(4)} '
      'faceW=${faceMetrics.faceWidth.toStringAsFixed(4)} '
      'aspectCorrection=${aspectCorrection.toStringAsFixed(4)} '
      'landmark10Correction=$kLandmark10Correction');

  // Step 2: Z-score with gender-specific reference
  // Iterate metricInfoList (not measured.entries) — computeAll() now returns
  // 28 metrics but referenceData only covers the 18 with population stats.
  // New Phase 1 metrics (eyebrowLength, chinAngle, etc.) are consumed only
  // by the ML face-shape classifier, which does its own standardization.
  final refs = referenceData[ethnicity]![gender]!;
  final zScores = <String, double>{};
  for (final info in metricInfoList) {
    final ref = refs[info.id]!;
    zScores[info.id] = (measured[info.id]! - ref.mean) / ref.sd;
  }

  debugPrint('[Analysis] faceAspectRatio z=${zScores['faceAspectRatio']?.toStringAsFixed(4)} '
      'ref mean=${refs['faceAspectRatio']!.mean} sd=${refs['faceAspectRatio']!.sd}');

  // ─── [CALIB] Calibration dump ────────────────────────────────────────────
  // Grep-friendly, one metric per line. Use `grep '\[CALIB\]' logs.txt` to
  // extract and feed to spreadsheet/pandas. sid groups lines belonging to
  // the same sample. Retained for metric-level debugging only.
  final sid = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  debugPrint('[CALIB] BEGIN sid=$sid t=${DateTime.now().toIso8601String()} '
      'source=${source.name} gender=${gender.name} ethnicity=${ethnicity.name} '
      'age=${ageGroup.name} imgW=$imageWidth imgH=$imageHeight '
      'aspectCorr=${aspectCorrection.toStringAsFixed(4)} '
      'lm10Corr=$kLandmark10Correction');
  debugPrint('[CALIB] sid=$sid base faceH=${faceMetrics.faceHeight.toStringAsFixed(5)} '
      'faceW=${faceMetrics.faceWidth.toStringAsFixed(5)} '
      'faceAspectRaw=${faceAspectRaw.toStringAsFixed(5)} '
      'faceAspectCorrected=${measured['faceAspectRatio']!.toStringAsFixed(5)}');
  for (final info in metricInfoList) {
    final ref = refs[info.id]!;
    final raw = measured[info.id]!;
    final z = zScores[info.id]!;
    debugPrint('[CALIB] sid=$sid metric id=${info.id} '
        'raw=${raw.toStringAsFixed(5)} '
        'refMean=${ref.mean} refSd=${ref.sd} '
        'z=${z.toStringAsFixed(4)}');
  }
  // Face-shape is now produced by the TFLite classifier
  // (FaceShapeClassifier) — no longer derived from faceAspectRatio z-score.
  // ─────────────────────────────────────────────────────────────────────────

  // Step 3: Age adjustment (over50 only)
  final zAdjusted = <String, double>{};
  for (final entry in zScores.entries) {
    zAdjusted[entry.key] =
        adjustForAge(entry.key, entry.value, gender, isOver50);
  }

  // Step 4: Z-adjusted → integer Metric Score (rules + UI display).
  // Integer scores drive the legacy nose-type flag thresholds below and the
  // per-metric UI chart; the tree-based attribute engine consumes continuous
  // z directly, so no continuous conversion is needed here.
  final metricScores = <String, int>{};
  final adjustedMetricScores = <String, int>{};
  for (final info in metricInfoList) {
    metricScores[info.id] = convertToScore(zScores[info.id]!, info.type);
    adjustedMetricScores[info.id] =
        convertToScore(zAdjusted[info.id]!, info.type);
  }

  // Step 5: Lateral metrics (optional — only when 3/4-view capture provided)
  Map<String, MetricResult>? lateralMetricResults;
  Map<String, double>? lateralZMap;
  Map<String, bool>? lateralFlags;
  if (lateralLandmarks != null) {
    final lateral = LateralFaceMetrics(lateralLandmarks);
    final lateralMeasured = lateral.computeAll();
    final lateralRefs = lateralReferenceData[ethnicity]![gender]!;
    final lateralZ = <String, double>{};
    final scores = <String, int>{};
    final results = <String, MetricResult>{};
    for (final info in lateralMetricInfoList) {
      final raw = lateralMeasured[info.id]!;
      final ref = lateralRefs[info.id]!;
      final z = (raw - ref.mean) / ref.sd;
      final s = convertToScore(z, info.type);
      lateralZ[info.id] = z;
      scores[info.id] = s;
      results[info.id] = MetricResult(
        id: info.id,
        rawValue: raw,
        zScore: z,
        zAdjusted: z,
        metricScore: s,
      );
    }
    lateralMetricResults = results;
    lateralZMap = lateralZ;

    // [CALIB] lateral metrics — same sid grouping is not possible here
    // (sid is scoped to the block above); emit a fresh lateral block so
    // post-hoc scripts can pair it by timestamp proximity.
    final lsid = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    debugPrint('[CALIB] LATERAL_BEGIN lsid=$lsid '
        't=${DateTime.now().toIso8601String()} '
        'gender=${gender.name} ethnicity=${ethnicity.name}');
    for (final info in lateralMetricInfoList) {
      final ref = lateralRefs[info.id]!;
      final raw = lateralMeasured[info.id]!;
      final z = lateralZ[info.id]!;
      debugPrint('[CALIB] lsid=$lsid lateral id=${info.id} '
          'raw=${raw.toStringAsFixed(5)} '
          'refMean=${ref.mean} refSd=${ref.sd} '
          'z=${z.toStringAsFixed(4)}');
    }
    debugPrint('[CALIB] LATERAL_END lsid=$lsid');

    // Population-relative flag derivation — see comment block below for every
    // nose-type flag, its condition, raw value, z-score (integer metricScore),
    // and pass/fail. Logged separately so calibration is transparent.
    final dorsalRaw = lateralMeasured['dorsalConvexity'] ?? 0;
    final dorsalScore = scores['dorsalConvexity'] ?? 0;
    final nasoLabRaw = lateralMeasured['nasolabialAngle'] ?? 0;
    final nasoLabScore = scores['nasolabialAngle'] ?? 0;
    final nasoFrontRaw = lateralMeasured['nasofrontalAngle'] ?? 0;
    final tipProjScore = scores['noseTipProjection'] ?? 0;

    final aquiline = dorsalScore >= 3;
    final snub = nasoLabScore >= 2 && nasoLabRaw >= 115.0;
    final droopingTip = nasoLabScore <= -2 && nasoLabRaw <= 112.0;
    final saddleNose = dorsalScore <= -3;
    final flatNose = tipProjScore <= -3;
    // Frontal-only nose types. Thresholds moderated to catch genuinely
    // noticeable (not just extreme) features: individual dimension flag
    // at score>=2 (z>=1.0, top ~16%), composite bigNose/smallNose when
    // both width and height agree at score>=1 (z>=0.5).
    final nasalWScore = metricScores['nasalWidthRatio'] ?? 0;
    final nasalHScore = metricScores['nasalHeightRatio'] ?? 0;
    final wideNose = nasalWScore >= 2;
    final narrowNose = nasalWScore <= -2;
    final longNose = nasalHScore >= 2;
    final shortNose = nasalHScore <= -2;
    final bigNose = nasalWScore >= 1 && nasalHScore >= 1;
    final smallNose = nasalWScore <= -1 && nasalHScore <= -1;

    lateralFlags = {
      'aquilineNose': aquiline,
      'snubNose': snub,
      'droopingTip': droopingTip,
      'saddleNose': saddleNose,
      'flatNose': flatNose,
    };

    debugPrint('══════════ [NOSE CLASSIFICATION] ══════════');
    debugPrint('  frontal.nasalWidth  score=$nasalWScore  '
        'wideNose=$wideNose  narrowNose=$narrowNose');
    debugPrint('  frontal.nasalHeight score=$nasalHScore  '
        'longNose=$longNose  shortNose=$shortNose');
    debugPrint('  lateral.dorsalConvexity  raw=${dorsalRaw.toStringAsFixed(4)}  '
        'score=$dorsalScore  aquiline=$aquiline  saddle=$saddleNose');
    debugPrint('  lateral.nasolabialAngle  raw=${nasoLabRaw.toStringAsFixed(1)}°  '
        'score=$nasoLabScore  snub=$snub  drooping=$droopingTip');
    debugPrint('  lateral.nasofrontalAngle raw=${nasoFrontRaw.toStringAsFixed(1)}°');
    debugPrint('  lateral.noseTipProjection score=$tipProjScore  '
        'flatNose=$flatNose');
    final active = [
      if (aquiline) '매부리코',
      if (snub) '들창코',
      if (droopingTip) '처진 코끝',
      if (saddleNose) '안장코',
      if (flatNose) '납작코',
      if (longNose) '긴 코',
      if (shortNose) '짧은 코',
      if (wideNose) '넓은 코',
      if (narrowNose) '좁은 코',
      if (bigNose) '큰 코',
      if (smallNose) '작은 코',
    ];
    debugPrint('  → detected: ${active.isEmpty ? "평범형" : active.join(", ")}');
    debugPrint('═══════════════════════════════════════════');
  }

  // Step 6: Hierarchical attribute derivation.
  // Build a unified z-map (frontal adjusted + lateral raw-z) and run it
  // through the 14-node physiognomy tree, then the 5-stage pipeline
  // (base / distinctiveness / zone / organ / palace / age+lateral).
  final zForTree = <String, double>{...zAdjusted};
  if (lateralZMap != null) zForTree.addAll(lateralZMap);

  final tree = scoreTree(zForTree);
  final breakdown = deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: isOver50,
    hasLateral: lateralLandmarks != null,
    lateralFlags: lateralFlags ?? const {},
  );
  final rawScores = breakdown.total;

  // Step 7: Rank-aware normalization → 5~10 with within-face spread
  final normalizedScores = normalizeAllScores(rawScores, gender);

  // Step 8: Archetype classification
  final archetype = classifyArchetype(normalizedScores);

  // Step 8.5: ML face-shape classifier (28-feature TFLite MLP, 76.9% test acc).
  // Feeds raw measured metrics (not z-scored) — the classifier does its own
  // standardization with scaler.json. Null-safe: if the classifier is not
  // loaded or a metric is missing, faceShapeLabel stays null and UI falls
  // back to the legacy rule-based classifier.
  final pred = FaceShapeClassifier.instance.predict(measured);
  if (pred != null) {
    debugPrint('[FACE SHAPE CNN] label=${pred.label.english} '
        'conf=${pred.confidence.toStringAsFixed(3)} '
        'probs=${pred.probabilities.map((p) => p.toStringAsFixed(2)).join(",")}');
  } else {
    debugPrint('[FACE SHAPE CNN] classifier unavailable → UI uses LDA fallback');
  }

  // Build metric results
  final metricResults = <String, MetricResult>{};
  for (final info in metricInfoList) {
    metricResults[info.id] = MetricResult(
      id: info.id,
      rawValue: measured[info.id]!,
      zScore: zScores[info.id]!,
      zAdjusted: zAdjusted[info.id]!,
      metricScore: adjustedMetricScores[info.id]!,
    );
  }

  // Build rich evidence — nodeScores, attributes, rules
  final nodeScores = _collectNodeScores(tree);
  final attributes = _buildAttributeEvidence(breakdown, normalizedScores);
  final rules = _buildRuleEvidence(breakdown);

  return FaceReadingReport(
    ethnicity: ethnicity,
    gender: gender,
    ageGroup: ageGroup,
    timestamp: DateTime.now(),
    source: source,
    metrics: metricResults,
    nodeScores: nodeScores,
    attributes: attributes,
    rules: rules,
    archetype: archetype,
    faceShapeLabel: pred?.label.english,
    faceShapeConfidence: pred?.confidence,
    lateralMetrics: lateralMetricResults,
    lateralFlags: lateralFlags,
  );
}

/// Walk the 14-node tree and collect NodeEvidence for every node.
Map<String, NodeEvidence> _collectNodeScores(NodeScore root) {
  final out = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    out[node.nodeId] = NodeEvidence(
      nodeId: node.nodeId,
      ownMeanZ: node.ownMeanZ ?? 0.0,
      ownMeanAbsZ: node.ownMeanAbsZ ?? 0.0,
      rollUpMeanZ: node.rollUpMeanZ ?? 0.0,
      rollUpMeanAbsZ: node.rollUpMeanAbsZ ?? 0.0,
    );
    for (final child in node.children) {
      walk(child);
    }
  }
  walk(root);
  return out;
}

/// Build AttributeEvidence for each attribute from the breakdown.
Map<Attribute, AttributeEvidence> _buildAttributeEvidence(
  AttributeBreakdown breakdown,
  Map<Attribute, double> normalizedScores,
) {
  final out = <Attribute, AttributeEvidence>{};
  for (final attr in Attribute.values) {
    final base = breakdown.basePerNode[attr] ?? const <String, double>{};
    final dist = breakdown.distinctiveness[attr] ?? 0.0;
    final raw = breakdown.total[attr] ?? 0.0;
    final normalized = normalizedScores[attr] ?? 5.0;

    // Collect ALL contributors with |value| > 0.05, sorted by |value| desc
    final bag = <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
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

/// Flatten the 5 rule lists into List<RuleEvidence> with stage tags.
List<RuleEvidence> _buildRuleEvidence(AttributeBreakdown breakdown) {
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

/// Average multiple landmark frames to reduce noise
List<FaceMeshLandmark> averageLandmarks(List<List<FaceMeshLandmark>> samples) {
  if (samples.length == 1) return samples.first;

  final count = samples.first.length;
  final n = samples.length.toDouble();

  return List.generate(count, (i) {
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final sample in samples) {
      sumX += sample[i].x;
      sumY += sample[i].y;
      sumZ += sample[i].z;
    }
    return FaceMeshLandmark(x: sumX / n, y: sumY / n, z: sumZ / n);
  });
}
