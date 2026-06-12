// 팀 케미 맵 매트릭스 계산기 검증 — PIVOT P2 완료 기준:
// 대칭성 · 결정론 · 쌍 수 · 베스트/의외 선정 · supabaseId 없는 멤버 제외 ·
// 밴드 표기 매핑.
//
// 실행: flutter test test/team_matrix_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';
import 'package:facely/domain/services/mc_fixtures.dart';
import 'package:facely/domain/services/team_matrix.dart';
import 'package:facely/presentation/screens/team/team_band.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

/// 합성 FaceReadingReport — compat_pipeline_smoke_test 와 동일 접근:
/// compat adapter 가 읽는 필드만 직접 채운다.
FaceReadingReport _fakeReport(
  Random rng, {
  required Gender gender,
  required AgeGroup age,
  required String? supabaseId,
}) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final frontalZ = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    frontalZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final lateralZ = <String, double>{};
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    lateralZ[info.id] =
        (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
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
  final report = FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime(2026, 6, 12),
    source: AnalysisSource.album,
    metrics: metrics,
    lateralMetrics: null,
    lateralFlags: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: const [],
    archetype: classifyArchetype(flat, gender, shape: FaceShape.oval),
    faceShape: FaceShape.oval,
    faceShapeConfidence: 0.5,
  );
  report.supabaseId = supabaseId;
  return report;
}

List<FaceReadingReport> _members(int n, {int seed = 42}) {
  final rng = Random(seed);
  return [
    for (int i = 0; i < n; i++)
      _fakeReport(
        rng,
        gender: i.isEven ? Gender.male : Gender.female,
        age: AgeGroup.values[i % 5],
        supabaseId: 'member-$i',
      ),
  ];
}

void main() {
  test('쌍 수 = N(N-1)/2, total 은 5~99 범위', () {
    final matrix = computeTeamMatrix(_members(4));
    expect(matrix.allPairs.length, 6);
    for (final p in matrix.allPairs) {
      expect(p.total, inInclusiveRange(5.0, 99.0));
    }
  });

  test('대칭 — pairOf(a,b) 와 pairOf(b,a) 는 같은 쌍·같은 total', () {
    final members = _members(5);
    final matrix = computeTeamMatrix(members);
    for (int i = 0; i < members.length; i++) {
      for (int j = 0; j < members.length; j++) {
        if (i == j) continue;
        final fwd = matrix.pairOf(members[i], members[j]);
        final rev = matrix.pairOf(members[j], members[i]);
        expect(fwd, isNotNull);
        expect(identical(fwd, rev), isTrue);
      }
    }
  });

  test('결정론 — 같은 멤버 구성은 항상 같은 매트릭스', () {
    final members = _members(6);
    final a = computeTeamMatrix(members);
    final b = computeTeamMatrix(members);
    for (final pair in a.allPairs) {
      final other = b.pairOf(pair.a, pair.b);
      expect(other, isNotNull);
      expect(other!.total, pair.total);
      expect(other.label, pair.label);
    }
    expect(b.best.total, a.best.total);
  });

  test('베스트 = 최고 총점, 의외(2위) = 두 번째 총점', () {
    final matrix = computeTeamMatrix(_members(6));
    final totals = matrix.allPairs.map((p) => p.total).toList()
      ..sort((x, y) => y.compareTo(x));
    expect(matrix.best.total, totals[0]);
    expect(matrix.surprise, isNotNull);
    expect(matrix.surprise!.total, totals[1]);
    for (final p in matrix.allPairs) {
      expect(p.total <= matrix.best.total, isTrue);
    }
  });

  test('supabaseId 없는 멤버는 매트릭스에서 제외', () {
    final rng = Random(7);
    final members = [
      ..._members(3),
      _fakeReport(rng,
          gender: Gender.female, age: AgeGroup.twenties, supabaseId: null),
    ];
    final matrix = computeTeamMatrix(members);
    expect(matrix.members.length, 3);
    expect(matrix.allPairs.length, 3);
  });

  test('밴드 표기 — 4단 라벨이 고유한 이모지·현대 한국어 라벨로 매핑', () {
    final emojis = CompatLabel.values.map((l) => l.bandEmoji).toSet();
    final labels = CompatLabel.values.map((l) => l.bandLabel).toSet();
    expect(emojis.length, 4);
    expect(labels.length, 4);
    // 하위 밴드는 "보완 조합" 프레임 (A4) — 부정 표현 금지.
    expect(CompatLabel.hyeonggeuknanjo.bandLabel, '보완 조합');
    // 라벨에 한자 표기 없음 (현대 한국어 only).
    for (final l in labels) {
      expect(RegExp(r'[一-鿿]').hasMatch(l), isFalse);
    }
  });
}
