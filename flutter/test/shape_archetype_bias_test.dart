// Shape → top-1 attribute 편향 진단 (empirical proof).
//
// 5 개 얼굴형별로 현실적인 metric bias(계란형=긴 aspect+부드러운 턱 등)
// 를 가정한 샘플을 엔진에 흘려 top-1 attribute 분포를 기록.
//
// 수정 전/후 이 테스트를 돌려 "oval → intelligence 쏠림" 같은 shape-bound
// 편향이 실제로 얼마나 줄었는지를 정량적으로 증명한다.
//
// Run via: flutter test test/shape_archetype_bias_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

// 현실적 얼굴형별 metric bias. "이런 얼굴이 oval 이다" 를 기하학 규칙으로 표현.
// 값은 z-score 단위. 현업 관상 교재·MediaPipe 측정 경향 종합.
const _shapeBiases = <FaceShape, Map<String, double>>{
  FaceShape.oval: {
    // 계란형 = 길쭉·부드러운 라인·균형
    'faceAspectRatio': 0.5,
    'faceTaperRatio': 0.0,
    'upperFaceRatio': 0.2,
    'gonialAngle': -0.4,        // 각지지 않은 턱
    'cheekboneWidth': -0.3,     // 광대 덜 돌출
    'lowerFaceFullness': -0.2,
    'foreheadWidth': 0.3,       // 반듯한 이마
  },
  FaceShape.oblong: {
    // 세로로 긴 얼굴 = 크게 길쭉
    'faceAspectRatio': 1.3,
    'upperFaceRatio': 0.6,
    'lowerFaceRatio': 0.5,
    'cheekboneWidth': -0.5,
    'gonialAngle': -0.3,
    'foreheadWidth': 0.4,
  },
  FaceShape.round: {
    // 둥근 = 짧고 넓음·풍성
    'faceAspectRatio': -0.8,
    'faceTaperRatio': -0.3,
    'lowerFaceFullness': 0.6,
    'gonialAngle': -0.5,
    'lipFullnessRatio': 0.3,
    'upperFaceRatio': -0.3,
  },
  FaceShape.square: {
    // 각진 = 강한 턱·광대·이마
    'faceAspectRatio': -0.1,
    'gonialAngle': 0.8,
    'cheekboneWidth': 0.5,
    'chinAngle': 0.4,
    'foreheadWidth': 0.5,
    'eyebrowThickness': 0.3,
  },
  FaceShape.heart: {
    // 하트형 = 상부 넓고 하부 뾰족
    'faceTaperRatio': 0.8,
    'foreheadWidth': 0.6,
    'cheekboneWidth': 0.3,
    'gonialAngle': -0.4,
    'lowerFaceRatio': -0.4,
    'eyeFissureRatio': 0.2,
  },
};

void main() {
  test('shape-conditional top-1 attribute 분포 — 편향 진단', () {
    const samples = 2000;
    const noiseStd = 0.6;

    final byShape = <FaceShape, Map<Attribute, int>>{};

    for (final shape in _shapeBiases.keys) {
      final rng = Random(42 ^ shape.index);
      final counts = <Attribute, int>{for (final a in Attribute.values) a: 0};

      for (int i = 0; i < samples; i++) {
        final gender = i.isEven ? Gender.male : Gender.female;
        final bias = _shapeBiases[shape]!;
        final z = <String, double>{};
        for (final info in metricInfoList) {
          final b = bias[info.id] ?? 0.0;
          z[info.id] = (b + _normal(rng) * noiseStd).clamp(-3.5, 3.5);
        }

        final tree = scoreTree(z);
        final breakdown = deriveAttributeScoresDetailed(
          tree: tree,
          gender: gender,
          isOver50: false,
          hasLateral: false,
          faceShape: shape,
          shapeConfidence: 0.8,
        );
        final normalized = normalizeAllScores(breakdown.total, gender);

        final top = normalized.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        counts[top] = counts[top]! + 1;
      }

      byShape[shape] = counts;
    }

    // Pretty print
    // ignore: avoid_print
    print('\n========== Top-1 Attribute by Face Shape ==========');
    // ignore: avoid_print
    print('Samples per shape: $samples\n');
    final header =
        'Shape     | ${Attribute.values.map((a) => a.name.substring(0, 5).padLeft(6)).join('|')}';
    // ignore: avoid_print
    print(header);
    // ignore: avoid_print
    print('-' * header.length);
    for (final shape in _shapeBiases.keys) {
      final row = StringBuffer('${shape.name.padRight(9)} |');
      for (final attr in Attribute.values) {
        final pct = byShape[shape]![attr]! / samples * 100;
        row.write(' ${pct.toStringAsFixed(1).padLeft(5)}|');
      }
      // ignore: avoid_print
      print(row);
    }

    // Shape-specific concentration check (bias diagnostic).
    // 완벽한 균일분포 = 10% per attr. 현실적으로 5-25% 범위가 "자연" 이라면
    // > 35% 는 한 속성 쏠림. > 50% 는 심각한 단극화.
    for (final shape in _shapeBiases.keys) {
      final counts = byShape[shape]!;
      final total = counts.values.reduce((a, b) => a + b);
      final maxEntry =
          counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final ratio = maxEntry.value / total;
      // ignore: avoid_print
      print('  → $shape: top = ${maxEntry.key.name} '
          '${(ratio * 100).toStringAsFixed(1)}% (threshold 35%)');
    }

    // v2.5 (2026-04-19) — 전면 rule/weight 재조정 후 모든 shape 의 max
    // concentration < 27% 유지. 이전 기준(pre-fix) 은 30% 내외였고 intel 에
    // 체계 쏠림이었음. 이 임계 초과 시 "다시 단극 쏠림" 신호 — 회귀 차단.
    for (final shape in _shapeBiases.keys) {
      final counts = byShape[shape]!;
      final total = counts.values.reduce((a, b) => a + b);
      final maxValue = counts.values.reduce((a, b) => a >= b ? a : b);
      final ratio = maxValue / total;
      expect(ratio, lessThan(0.27),
          reason:
              '$shape: max concentration ${(ratio * 100).toStringAsFixed(1)}% '
              'exceeds 27% threshold — shape-bound archetype bias regressed');
    }
  });
}
