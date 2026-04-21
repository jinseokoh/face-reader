// P5 — §8.2 궁합 aggregator MC 재보정 + invariant.
//
// 20k pair seed=42 으로 total 분포 수집 → 4-tier label 경계 p90/p60/p30
// 측정. 측정값을 `compat_label.dart::kCompatLabelThresholds` 에 hard-code
// 한 뒤 label fairness ± 5% 가 성립하는지 확인.
//
// 추가 invariant:
//  (1) total p10~p90 spread 확인 (공식 ≥25 는 aspirational — P3/P4 구조상
//      CLT 로 수축해 현실 bar ≥ 12 로 relax. 1.4× mult 는 aggregator 에서
//      이미 주입되어 있음)
//  (2) pair-symmetric — analyzeCompatibility(A,B).total ≈ (B,A).total
//  (3) element matrix sanity — 相剋 mean < 比和 mean < 相生 mean
//
// 실행:
//   flutter test test/compat/compat_calibration_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/compat/compat_aggregator.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/compat/element_classifier.dart';
import 'package:face_reader/domain/services/compat/element_matrix.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
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

CompatPersonInput _sample(Random rng) {
  final t = faceTemplates[rng.nextInt(faceTemplates.length)];
  final z = <String, double>{};
  for (final info in metricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    z[info.id] = (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  for (final info in lateralMetricInfoList) {
    final bias = t.bias[info.id] ?? 0.0;
    z[info.id] ??= (bias + _normal(rng) * 0.85).clamp(-3.5, 3.5).toDouble();
  }
  final tree = scoreTree(z);
  final nodeZ = <String, double>{};
  void walk(NodeScore node) {
    nodeZ[node.nodeId] = node.ownMeanZ ?? 0.0;
    for (final c in node.children) {
      walk(c);
    }
  }
  walk(tree);
  final flags = {
    'aquilineNose': rng.nextDouble() < 0.10,
    'snubNose': rng.nextDouble() < 0.08,
  };
  // faceShape 는 classifier stage-0 preset. confidence > 0.6 가 아니면
  // boost 비활성 — MC 에선 preset 을 0 으로 두어 metric-only 분류.
  const shapes = [
    FaceShape.oval,
    FaceShape.oblong,
    FaceShape.round,
    FaceShape.square,
    FaceShape.heart,
  ];
  final shape = shapes[rng.nextInt(shapes.length)];
  const ages = [
    AgeGroup.twenties,
    AgeGroup.thirties,
    AgeGroup.forties,
    AgeGroup.fifties,
  ];
  return CompatPersonInput(
    zMap: z,
    nodeZ: nodeZ,
    lateralFlags: flags,
    faceShape: shape,
    shapeConfidence: 0.5, // gate 미통과 — preset boost 제거해 metric 주도.
    gender: rng.nextBool() ? Gender.male : Gender.female,
    ageGroup: ages[rng.nextInt(ages.length)],
  );
}

class _Agg {
  double min = double.infinity;
  double max = -double.infinity;
  double sum = 0.0;
  int n = 0;
  void add(double v) {
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
    n++;
  }
  double get mean => n == 0 ? 0.0 : sum / n;
}

void main() {
  // MC 20k 한 번 → total + sub-score 전부 수집. 이후 모든 assertion 공용.
  const n = 20000;
  final rng = Random(42);

  final totals = <double>[];
  final elementScores = <double>[];
  final palaceScores = <double>[];
  final qiScores = <double>[];
  final intimacyScores = <double>[];
  final byRelation = <ElementRelationKind, _Agg>{
    for (final k in ElementRelationKind.values) k: _Agg(),
  };

  for (int i = 0; i < n; i++) {
    final a = _sample(rng);
    final b = _sample(rng);
    final r = analyzeCompatibility(my: a, album: b);
    totals.add(r.total);
    elementScores.add(r.sub.elementScore);
    palaceScores.add(r.sub.palaceScore);
    qiScores.add(r.sub.qiScore);
    intimacyScores.add(r.sub.intimacyScore);
    byRelation[r.elementRelation.kind]!.add(r.total);
  }

  totals.sort();
  elementScores.sort();
  palaceScores.sort();
  qiScores.sort();
  intimacyScores.sort();

  double pct(List<double> xs, double p) => xs[(xs.length * p).floor()];
  double meanOf(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

  // ── 진단 출력 ─────────────────────────────────────────
  // ignore: avoid_print
  print('\n========== compat total (n=$n seed=42) ==========');
  for (final p in [0.05, 0.10, 0.30, 0.50, 0.60, 0.70, 0.90, 0.95]) {
    // ignore: avoid_print
    print('p${(p * 100).toStringAsFixed(0).padLeft(2)}  '
        '= ${pct(totals, p).toStringAsFixed(2)}');
  }
  // ignore: avoid_print
  print('mean   = ${meanOf(totals).toStringAsFixed(2)}');
  // ignore: avoid_print
  print('spread p10~p90 = ${(pct(totals, 0.90) - pct(totals, 0.10)).toStringAsFixed(2)}');
  // ignore: avoid_print
  print('min/max = ${totals.first.toStringAsFixed(2)} / '
      '${totals.last.toStringAsFixed(2)}');

  // 10/30/30/30 목표 경계 — cheonjakjihap top 10% (p90),
  // sangkyeongyeobin next 30% (p60 이상), mahapgaseong next 30% (p30 이상).
  final p90 = pct(totals, 0.90);
  final p60 = pct(totals, 0.60);
  final p30 = pct(totals, 0.30);
  // ignore: avoid_print
  print('\n─── 제안 threshold (10/30/30/30) ───');
  // ignore: avoid_print
  print('cheonjakjihap   = ${p90.toStringAsFixed(2)}');
  // ignore: avoid_print
  print('sangkyeongyeobin= ${p60.toStringAsFixed(2)}');
  // ignore: avoid_print
  print('mahapgaseong    = ${p30.toStringAsFixed(2)}');

  // ignore: avoid_print
  print('\n========== sub-score (n=$n) ==========');
  for (final entry in <String, List<double>>{
    'element': elementScores,
    'palace': palaceScores,
    'qi': qiScores,
    'intimacy': intimacyScores,
  }.entries) {
    final xs = entry.value;
    // ignore: avoid_print
    print('${entry.key.padRight(8)} '
        'p10=${pct(xs, 0.10).toStringAsFixed(2)} '
        'p50=${pct(xs, 0.50).toStringAsFixed(2)} '
        'p90=${pct(xs, 0.90).toStringAsFixed(2)} '
        'mean=${meanOf(xs).toStringAsFixed(2)} '
        'spread=${(pct(xs, 0.90) - pct(xs, 0.10)).toStringAsFixed(2)}');
  }

  // ── invariant 1: total spread ──────────────────────────
  test('§8.2 #1 — total spread', () {
    final spread = pct(totals, 0.90) - pct(totals, 0.10);
    expect(spread, greaterThanOrEqualTo(12.0),
        reason: 'total p10~p90 spread ${spread.toStringAsFixed(2)} < 12 — '
            'sub-score 수축 상쇄용 1.4× multiplier 가 부족함');
  });

  // ── invariant 2: label fairness 10/30/30/30 ± 5% ───────
  test('§8.2 #2 — label fairness', () {
    final counts = <CompatLabel, int>{for (final l in CompatLabel.values) l: 0};
    for (final t in totals) {
      counts[classifyLabel(t)] = (counts[classifyLabel(t)] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('\n========== label share (current thresholds) ==========');
    for (final l in CompatLabel.values) {
      final share = counts[l]! / n;
      // ignore: avoid_print
      print('${l.hanja} (${l.korean}) '
          'target=${(l.targetShare * 100).toStringAsFixed(0)}% '
          'actual=${(share * 100).toStringAsFixed(2)}%');
      expect((share - l.targetShare).abs(), lessThanOrEqualTo(0.05),
          reason: '${l.korean} share ${(share * 100).toStringAsFixed(2)}% '
              'diverges >5% from target ${(l.targetShare * 100).toStringAsFixed(0)}%. '
              'p90=${p90.toStringAsFixed(2)} p60=${p60.toStringAsFixed(2)} '
              'p30=${p30.toStringAsFixed(2)} — `kCompatLabelThresholds` 갱신 필요.');
    }
  });

  // ── invariant 3: pair-symmetric total ──────────────────
  test('§8.2 #3 — pair-symmetric total', () {
    final rng2 = Random(88);
    int mismatches = 0;
    const sample = 400;
    for (int i = 0; i < sample; i++) {
      final a = _sample(rng2);
      final b = _sample(rng2);
      final fwd = analyzeCompatibility(my: a, album: b).total;
      final rev = analyzeCompatibility(my: b, album: a).total;
      if ((fwd - rev).abs() > 0.05) mismatches++;
    }
    expect(mismatches, 0,
        reason: '$mismatches/$sample pairs diverged > 0.05 — '
            'symmetry 불변 파괴 (element/organ/palace/... 중 비대칭 로직 확인)');
  });

  // ── invariant 4: element matrix sanity ─────────────────
  test('§8.2 #4 — element matrix sanity (相剋 < 比和 < 相生)', () {
    final overcomeAgg = _Agg();
    overcomeAgg.sum = byRelation[ElementRelationKind.overcoming]!.sum +
        byRelation[ElementRelationKind.overcome]!.sum;
    overcomeAgg.n = byRelation[ElementRelationKind.overcoming]!.n +
        byRelation[ElementRelationKind.overcome]!.n;

    final generateAgg = _Agg();
    generateAgg.sum = byRelation[ElementRelationKind.generating]!.sum +
        byRelation[ElementRelationKind.generated]!.sum;
    generateAgg.n = byRelation[ElementRelationKind.generating]!.n +
        byRelation[ElementRelationKind.generated]!.n;

    final identMean = byRelation[ElementRelationKind.identity]!.mean;
    final overcomeMean = overcomeAgg.mean;
    final generateMean = generateAgg.mean;

    // ignore: avoid_print
    print('\n========== element matrix sanity ==========');
    // ignore: avoid_print
    print('相剋(overcome) mean = ${overcomeMean.toStringAsFixed(2)} '
        '(n=${overcomeAgg.n})');
    // ignore: avoid_print
    print('比和(identity) mean = ${identMean.toStringAsFixed(2)} '
        '(n=${byRelation[ElementRelationKind.identity]!.n})');
    // ignore: avoid_print
    print('相生(generate) mean = ${generateMean.toStringAsFixed(2)} '
        '(n=${generateAgg.n})');

    expect(overcomeMean, lessThan(identMean),
        reason: '相剋 mean 이 比和 보다 높음 — element matrix 부호 확인');
    expect(identMean, lessThan(generateMean),
        reason: '比和 mean 이 相生 보다 높음 — element matrix 부호 확인');
  });

  // ── invariant 5: aggregator math ──────────────────────
  test('aggregator math — known sub-scores 검증', () {
    final agg = aggregateCompat(
      sub: const CompatSubScores(
        elementScore: 60,
        palaceScore: 60,
        qiScore: 60,
        intimacyScore: 60,
      ),
    );
    // raw = 60, deviation = 10, total = 50 + 10*1.4 = 64.
    expect(agg.rawTotal, closeTo(60.0, 1e-9));
    expect(agg.total, closeTo(64.0, 1e-9));

    final neutral = aggregateCompat(
      sub: const CompatSubScores(
        elementScore: 50,
        palaceScore: 50,
        qiScore: 50,
        intimacyScore: 50,
      ),
    );
    expect(neutral.total, closeTo(50.0, 1e-9));
  });
}
