// P2 — 五行 classifier + 5×5 matrix sanity.
//
// Goal: verify that
//  (1) MC 체형 샘플에서 5 element primary 분포가 고르게 나온다
//      (no element 가 한쪽으로 몰려 실질 matrix 가 3×3 로 붕괴하지 않음).
//  (2) FRAMEWORK §8.2 invariant #4 — 相剋 평균 < 比和 평균 < 相生 평균.
//      (5×5 matrix 레벨 sanity. aggregator 단계가 아닌 L1 itself 에서 이미
//      이 순서가 유지되어야 함.)
//
// 실행:
//   flutter test test/compat/element_distribution_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_reader/domain/services/compat/element_classifier.dart';
import 'package:face_reader/domain/services/compat/element_matrix.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
import 'package:face_reader/domain/services/mc_fixtures.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

const double _noiseStd = 0.85;
const double _baseBias = 0.0;

/// 얼굴 샘플 하나 생성 — `faceTemplates` 중 하나를 랜덤 선택 후 z 에 bias+noise.
/// faceShape 은 `koreanShapeDistribution` 로부터 draw, confidence 는 0.5~0.9
/// uniform (절반 이상에서 preset boost 발동).
({Map<String, double> z, FaceShape shape, double shapeConfidence}) _sample(
    Random rng) {
  final template = faceTemplates[rng.nextInt(faceTemplates.length)];
  final z = <String, double>{};
  for (final info in metricInfoList) {
    final bias = template.bias[info.id] ?? _baseBias;
    z[info.id] = (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5).toDouble();
  }
  // lateral metric 은 기본 N(0, _noiseStd) — template 이 lateral 까지 가진
  // 경우는 `noseTipProjection`·`nasofrontalAngle` 만 있으므로 나머지는 기본값.
  for (final info in lateralMetricInfoList) {
    final bias = template.bias[info.id] ?? _baseBias;
    z[info.id] ??=
        (bias + _normal(rng) * _noiseStd).clamp(-3.5, 3.5).toDouble();
  }

  final shape = drawShape(rng);
  final conf = 0.5 + rng.nextDouble() * 0.4; // 0.5 ~ 0.9
  return (z: z, shape: shape, shapeConfidence: conf);
}

void main() {
  group('L1 五行 classifier + matrix', () {
    test('primary 분포가 5 element 모두 [5%, 50%] 범위', () {
      const n = 10000;
      final rng = Random(42);
      final counts = <FiveElement, int>{for (final e in FiveElement.values) e: 0};

      for (int i = 0; i < n; i++) {
        final s = _sample(rng);
        final fe = classifyFiveElements(
          zMap: s.z,
          faceShape: s.shape,
          shapeConfidence: s.shapeConfidence,
        );
        counts[fe.primary] = counts[fe.primary]! + 1;
      }

      // ignore: avoid_print
      print('\n========== L1 primary distribution (n=$n) ==========');
      for (final e in FiveElement.values) {
        final pct = counts[e]! * 100.0 / n;
        // ignore: avoid_print
        print('${e.hanja} ${e.korean.padRight(4)} ${pct.toStringAsFixed(1)}%');
      }

      for (final e in FiveElement.values) {
        final frac = counts[e]! / n;
        expect(frac, greaterThanOrEqualTo(0.05),
            reason: '${e.korean} primary frequency $frac < 0.05 — classifier '
                'weight/preset 재설계 필요');
        expect(frac, lessThanOrEqualTo(0.50),
            reason: '${e.korean} primary frequency $frac > 0.50 — 한 형이 '
                '지나치게 쏠림');
      }
    });

    test('§8.2 #4 — 相剋 avg < 比和 avg < 相生 avg (matrix sanity)', () {
      // matrix 자체의 sanity 를 직접 검증 (분포 가중 아님).
      // FRAMEWORK 의 상생·상극 정의에 따라 25 cell 을 3 bucket 으로 나눠 평균.
      final scores = <ElementRelationKind, List<double>>{
        for (final k in ElementRelationKind.values) k: <double>[],
      };

      for (final a in FiveElement.values) {
        for (final b in FiveElement.values) {
          final k = relationKind(a, b);
          scores[k]!.add(matrixScore(a, b));
        }
      }

      double avg(List<double> xs) =>
          xs.isEmpty ? 0.0 : xs.reduce((x, y) => x + y) / xs.length;

      final identityAvg = avg(scores[ElementRelationKind.identity]!);
      final overcomingAvg = avg(scores[ElementRelationKind.overcoming]!);
      final overcomeAvg = avg(scores[ElementRelationKind.overcome]!);
      final generatingAvg = avg(scores[ElementRelationKind.generating]!);
      final generatedAvg = avg(scores[ElementRelationKind.generated]!);

      // 相剋 = overcoming + overcome 평균 (양방향 모두 충돌).
      final keukAvg =
          (scores[ElementRelationKind.overcoming]! + scores[ElementRelationKind.overcome]!)
                  .reduce((x, y) => x + y) /
              (scores[ElementRelationKind.overcoming]!.length +
                  scores[ElementRelationKind.overcome]!.length);
      // 相生 = generating + generated.
      final saengAvg =
          (scores[ElementRelationKind.generating]! + scores[ElementRelationKind.generated]!)
                  .reduce((x, y) => x + y) /
              (scores[ElementRelationKind.generating]!.length +
                  scores[ElementRelationKind.generated]!.length);

      // ignore: avoid_print
      print('\n========== matrix bucket avg ==========');
      // ignore: avoid_print
      print('相剋   ${keukAvg.toStringAsFixed(2)}  '
          '(overcoming ${overcomingAvg.toStringAsFixed(2)} / '
          'overcome ${overcomeAvg.toStringAsFixed(2)})');
      // ignore: avoid_print
      print('比和   ${identityAvg.toStringAsFixed(2)}');
      // ignore: avoid_print
      print('相生   ${saengAvg.toStringAsFixed(2)}  '
          '(generating ${generatingAvg.toStringAsFixed(2)} / '
          'generated ${generatedAvg.toStringAsFixed(2)})');

      expect(keukAvg, lessThan(identityAvg),
          reason: '相剋 평균 ${keukAvg.toStringAsFixed(2)} '
              '>= 比和 평균 ${identityAvg.toStringAsFixed(2)} — matrix 재조정 필요');
      expect(identityAvg, lessThan(saengAvg),
          reason: '比和 평균 ${identityAvg.toStringAsFixed(2)} '
              '>= 相生 평균 ${saengAvg.toStringAsFixed(2)} — matrix 재조정 필요');
    });

    test('blended elementRelationScore — 相剋 pair 평균 < 相生 pair 평균', () {
      // blend 공식 (§2.5) 적용 후에도 invariant 유지. MC 샘플로 검증.
      const n = 4000;
      final rng = Random(7);
      final byKind = <ElementRelationKind, List<double>>{
        for (final k in ElementRelationKind.values) k: <double>[],
      };

      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final my = classifyFiveElements(
          zMap: a.z,
          faceShape: a.shape,
          shapeConfidence: a.shapeConfidence,
        );
        final album = classifyFiveElements(
          zMap: b.z,
          faceShape: b.shape,
          shapeConfidence: b.shapeConfidence,
        );
        final rel = elementRelationScore(my: my, album: album);
        byKind[rel.kind]!.add(rel.score);
      }

      double avg(List<double> xs) =>
          xs.isEmpty ? 0.0 : xs.reduce((x, y) => x + y) / xs.length;

      final keukAvg =
          (byKind[ElementRelationKind.overcoming]! + byKind[ElementRelationKind.overcome]!)
                  .reduce((x, y) => x + y) /
              (byKind[ElementRelationKind.overcoming]!.length +
                  byKind[ElementRelationKind.overcome]!.length);
      final identityAvg = avg(byKind[ElementRelationKind.identity]!);
      final saengAvg =
          (byKind[ElementRelationKind.generating]! + byKind[ElementRelationKind.generated]!)
                  .reduce((x, y) => x + y) /
              (byKind[ElementRelationKind.generating]!.length +
                  byKind[ElementRelationKind.generated]!.length);

      // ignore: avoid_print
      print('\n========== blended elementScore avg by relation (n=$n pairs) ==========');
      // ignore: avoid_print
      print('相剋  ${keukAvg.toStringAsFixed(2)}');
      // ignore: avoid_print
      print('比和  ${identityAvg.toStringAsFixed(2)}');
      // ignore: avoid_print
      print('相生  ${saengAvg.toStringAsFixed(2)}');

      expect(keukAvg, lessThan(saengAvg),
          reason: '相剋 blended 평균 ${keukAvg.toStringAsFixed(2)} '
              '>= 相生 blended 평균 ${saengAvg.toStringAsFixed(2)} — '
              'secondary overlay 가중 과다 의심');
    });

    test('score clamp [5, 99] + kind-swap invariant', () {
      // L1 elementScore 는 asymmetric by design — 生/被生 방향 차이가 있어
      // primary × primary 항 (M[aP][bP] ≠ M[bP][aP]) 이 swap 시 달라진다.
      // 그래서 total-level symmetry (§8.2 #3) 는 aggregator 에서 보장하고,
      // L1 에서는 (a) clamp 범위, (b) kind 가 swap 시 올바르게 inverse
      // (generating↔generated, overcoming↔overcome, identity=identity) 인지
      // 확인한다.
      const n = 200;
      final rng = Random(101);
      const inverseKind = <ElementRelationKind, ElementRelationKind>{
        ElementRelationKind.identity: ElementRelationKind.identity,
        ElementRelationKind.generating: ElementRelationKind.generated,
        ElementRelationKind.generated: ElementRelationKind.generating,
        ElementRelationKind.overcoming: ElementRelationKind.overcome,
        ElementRelationKind.overcome: ElementRelationKind.overcoming,
      };
      for (int i = 0; i < n; i++) {
        final a = _sample(rng);
        final b = _sample(rng);
        final feA = classifyFiveElements(
          zMap: a.z,
          faceShape: a.shape,
          shapeConfidence: a.shapeConfidence,
        );
        final feB = classifyFiveElements(
          zMap: b.z,
          faceShape: b.shape,
          shapeConfidence: b.shapeConfidence,
        );
        final ab = elementRelationScore(my: feA, album: feB);
        final ba = elementRelationScore(my: feB, album: feA);

        expect(ab.score, greaterThanOrEqualTo(5.0));
        expect(ab.score, lessThanOrEqualTo(99.0));
        expect(ba.score, greaterThanOrEqualTo(5.0));
        expect(ba.score, lessThanOrEqualTo(99.0));
        expect(ba.kind, equals(inverseKind[ab.kind]),
            reason: 'swap 후 kind 가 inverse 와 다름: '
                'ab=${ab.kind} ba=${ba.kind}');
      }
    });
  });
}
