// P7 smoke — FaceReadingReport → compat_adapter → analyzeCompatibility →
// buildCompatNarrative end-to-end 스모크. 실 앨범 flow 의 data shape 검증.
//
// 실행:
//   flutter test test/compat/compat_pipeline_smoke_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/compat/compat_adapter.dart';
import 'package:face_reader/domain/services/mc_fixtures.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

/// 합성 FaceReadingReport — analyzeFaceReading 은 landmarks 를 요구하므로
/// compat adapter 가 읽는 필드(metrics.zAdjusted / lateralMetrics.zAdjusted /
/// nodeScores.ownMeanZ / lateralFlags / faceShape / gender / ageGroup) 만 직접
/// 채워서 report 를 구성한다.
FaceReadingReport _fakeReport(
  Random rng, {
  required Gender gender,
  required AgeGroup age,
  required String alias,
}) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];

  // frontal z-map (18 metric) — template bias + N(0, 0.85^2).
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }

  // lateral z-map — 별도 키.
  final lateralZ = <String, double>{};
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    lateralZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }

  // 14-node tree ownMeanZ 는 scoreTree 로 채운다 — compat adapter 가
  // nodeScores 를 읽어 nodeZ 로 변환하는 경로를 그대로 재현.
  final zForTree = <String, double>{...frontalZ, ...lateralZ};
  final tree = scoreTree(zForTree);
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

  // MetricResult 는 rawValue 없어도 compat 계산엔 무관 — rawValue 를 0 으로 두고
  // zAdjusted 만 채운다. compat_adapter 는 zAdjusted 만 읽는다.
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
  final lateralMetrics = <String, MetricResult>{
    for (final info in lateralMetricInfoList)
      info.id: MetricResult(
        id: info.id,
        rawValue: 0.0,
        zScore: lateralZ[info.id]!,
        zAdjusted: lateralZ[info.id]!,
        metricScore: 0,
      ),
  };

  // lateral flag — 실 파이프라인의 기초 감지. 임계치는 단순화.
  final lateralFlags = <String, bool>{
    'aquilineNose': (lateralZ['dorsalConvexity'] ?? 0.0) >= 1.5,
    'snubNose': (lateralZ['nasolabialAngle'] ?? 0.0) >= 1.5,
    'droopingTip': (lateralZ['nasolabialAngle'] ?? 0.0) <= -1.5,
    'saddleNose': (lateralZ['dorsalConvexity'] ?? 0.0) <= -1.5,
    'flatNose': (lateralZ['noseTipProjection'] ?? 0.0) <= -1.5,
  };

  // attributes / rules 는 compat 이 읽지 않지만 FaceReadingReport 가 required.
  // 빈 구조로 채우고 archetype 은 flat score 로 분류.
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
  final archetype = classifyArchetype(flat, shape: FaceShape.oval);

  final report = FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime.now(),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: lateralMetrics,
    lateralFlags: lateralFlags,
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: archetype,
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
  report.alias = alias;
  return report;
}

void main() {
  test('P7 smoke — 두 FaceReadingReport → CompatibilityBundle', () {
    final rng = Random(99);
    final my = _fakeReport(
      rng,
      gender: Gender.male,
      age: AgeGroup.thirties,
      alias: 'me',
    );
    final album = _fakeReport(
      rng,
      gender: Gender.female,
      age: AgeGroup.forties,
      alias: 'them',
    );

    final bundle = analyzeCompatibilityFromReports(my: my, album: album);

    // report 구조 sanity.
    expect(bundle.report.total, inInclusiveRange(5.0, 99.0));
    expect(bundle.report.sub.elementScore, inInclusiveRange(5.0, 99.0));
    expect(bundle.report.sub.palaceScore, inInclusiveRange(5.0, 99.0));
    expect(bundle.report.sub.qiScore, inInclusiveRange(5.0, 99.0));
    expect(bundle.report.myPalaces.length, 12);
    expect(bundle.report.albumPalaces.length, 12);

    // narrative 구조.
    expect(bundle.narrative.overview.length, greaterThanOrEqualTo(80));
    expect(bundle.narrative.elementSection.length, greaterThanOrEqualTo(80));
    expect(bundle.narrative.palaceSection.length, greaterThanOrEqualTo(80));
    expect(bundle.narrative.qiSection.length, greaterThanOrEqualTo(80));
    expect(bundle.narrative.intimacySection, isNotNull); // 30 × 40 opposite
    expect(bundle.narrative.longTermSection.length, greaterThanOrEqualTo(40));

    // 결정적 — 동일 입력이면 동일 output.
    final b2 = analyzeCompatibilityFromReports(my: my, album: album);
    expect(b2.report.total, closeTo(bundle.report.total, 1e-6));
    expect(b2.narrative.overview, bundle.narrative.overview);
  });

  test('P7 smoke — same-sex 면 intimacy gate off', () {
    final rng = Random(100);
    final a = _fakeReport(
      rng,
      gender: Gender.female,
      age: AgeGroup.thirties,
      alias: 'a',
    );
    final b = _fakeReport(
      rng,
      gender: Gender.female,
      age: AgeGroup.thirties,
      alias: 'b',
    );
    final bundle = analyzeCompatibilityFromReports(my: a, album: b);
    expect(bundle.report.intimacy.gateActive, false);
    expect(bundle.report.sub.intimacyScore, 50.0);
    expect(bundle.narrative.intimacySection, isNull);
  });

  test('attribute/archetype 재사용 없음 — compat engine 순수성', () {
    // §8.2 #6: analyzeCompatibility 는 FaceReadingReport.attributes / rules /
    // archetype 를 읽지 않음. 간접 검증 — attributes 를 비워도 compat 은 계산됨.
    final rng = Random(101);
    final r = _fakeReport(rng,
        gender: Gender.male, age: AgeGroup.thirties, alias: 'x');
    final r2 = _fakeReport(rng,
        gender: Gender.female, age: AgeGroup.thirties, alias: 'y');

    // adapter 는 metrics/lateralMetrics/nodeScores/lateralFlags/faceShape 만
    // 읽는다. attribute 계층이 비어도 adapter 결과는 같아야 한다.
    final emptyAttrs = <Attribute, AttributeEvidence>{};
    final stripped = FaceReadingReport(
      ethnicity: r.ethnicity,
      gender: r.gender,
      ageGroup: r.ageGroup,
      timestamp: r.timestamp,
      source: r.source,
      metrics: r.metrics,
      lateralMetrics: r.lateralMetrics,
      lateralFlags: r.lateralFlags,
      nodeScores: r.nodeScores,
      attributes: emptyAttrs, // 비움.
      rules: const [], // 비움.
      archetype: r.archetype,
      faceShape: r.faceShape,
      faceShapeConfidence: r.faceShapeConfidence,
    );
    final full = analyzeCompatibilityFromReports(my: r, album: r2);
    final light = analyzeCompatibilityFromReports(my: stripped, album: r2);
    expect(light.report.total, closeTo(full.report.total, 1e-6));
  });
}
