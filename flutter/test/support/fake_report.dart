// 테스트 공용 가짜 리포트 — 계측 z 만 의미 있고 나머지는 빈 값.
// team_test · measure_report_test 가 같이 쓴다.

import 'dart:math';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/symmetry_reference.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/services/mc_fixtures.dart';
import 'demo_landmarks.dart';

double normalSample(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

FaceReadingReport fakeReport(
  Random rng, {
  required Gender gender,
  required AgeGroup age,
}) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] = (bias + normalSample(rng) * 0.85)
        .clamp(-3.5, 3.5)
        .toDouble();
  }
  final lateralZ = <String, double>{};
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    lateralZ[info.id] = (bias + normalSample(rng) * 0.85)
        .clamp(-3.5, 3.5)
        .toDouble();
  }
  final tree = scoreTree({...frontalZ, ...lateralZ});
  final nodeScores = <String, NodeEvidence>{};
  void walk(NodeScore node) {
    nodeScores[node.nodeId] = NodeEvidence(
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

  walk(tree);
  final metrics = <String, MetricResult>{
    for (final info in metricInfoList)
      info.id: MetricResult(
        id: info.id,
        rawValue: 0.0,
        zScore: frontalZ[info.id]!,
        zAdjusted: frontalZ[info.id]!,
        metricScore: 0,
      ),
  };
  final attributes = <Attribute, AttributeEvidence>{
    for (final a in Attribute.values)
      a: AttributeEvidence(
        rawTotal: 0.0,
        normalizedScore: 7.5,
        basePerNode: const {},
        distinctiveness: 0.0,
        contributors: const [],
      ),
  };
  final flat = {for (final a in Attribute.values) a: 7.5};
  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime(2026, 7, 16),
    source: AnalysisSource.album,
    metrics: metrics,
    landmarks: demoLandmarks(gender),
    kind: ReportKind.measure,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, gender, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
    // 대칭 6 — 성별 reference 평균 근처의 비대칭도 (0 = 완전 대칭).
    symmetry: {
      for (final e in symmetryReference[gender]!.entries)
        e.key: (e.value.mean * (0.5 + rng.nextDouble())).clamp(0.0, 1.0),
    },
  );
}

