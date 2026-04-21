// 대부님 리뷰용 sample demo.
//
// 엔진을 실행해 3 종의 대표 상황(이상적 조합 / 충돌형 / 중간형) 에 대해
// 5-섹션 분석가 리포트를 print 한다. 테스트 자체는 기본 sanity 만 검사.
//
// 실행:
//   flutter test test/compat/compat_narrative_sample_demo_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_narrative.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

double _normal(Random rng) {
  double u1, u2;
  do {
    u1 = rng.nextDouble();
  } while (u1 == 0.0);
  u2 = rng.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

/// z-map 합성기. biasMap 으로 특정 metric 을 특정 z 방향으로 밀어
/// 시나리오별 rule 이 잘 발동하도록 유도.
CompatPersonInput _person(
  Random rng, {
  required Map<String, double> biasMap,
  required FaceShape shape,
  required Gender gender,
  required AgeGroup age,
  double sigma = 0.6,
}) {
  final z = <String, double>{};
  for (final info in metricInfoList) {
    final bias = biasMap[info.id] ?? 0.0;
    z[info.id] = (bias + _normal(rng) * sigma).clamp(-3.0, 3.0).toDouble();
  }
  for (final info in lateralMetricInfoList) {
    final bias = biasMap[info.id] ?? 0.0;
    z[info.id] = (bias + _normal(rng) * sigma).clamp(-3.0, 3.0).toDouble();
  }
  final tree = scoreTree(z);
  final nodeZ = <String, double>{};
  void walk(NodeScore n) {
    nodeZ[n.nodeId] = n.ownMeanZ ?? 0.0;
    for (final c in n.children) {
      walk(c);
    }
  }
  walk(tree);
  return CompatPersonInput(
    zMap: z,
    nodeZ: nodeZ,
    lateralFlags: {
      'aquilineNose': (z['dorsalConvexity'] ?? 0.0) >= 1.5,
      'snubNose': (z['nasolabialAngle'] ?? 0.0) >= 1.5,
      'droopingTip': (z['nasolabialAngle'] ?? 0.0) <= -1.5,
      'saddleNose': (z['dorsalConvexity'] ?? 0.0) <= -1.5,
      'flatNose': (z['noseTipProjection'] ?? 0.0) <= -1.5,
    },
    faceShape: shape,
    shapeConfidence: 0.8,
    gender: gender,
    ageGroup: age,
  );
}

void _printNarrative(String label, CompatibilityReport r, CompatNarrative n) {
  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('=' * 72);
  // ignore: avoid_print
  print('■ 샘플: $label');
  // ignore: avoid_print
  print('  오행: ${r.myElement.primary.korean} × ${r.albumElement.primary.korean}  ·  '
      '라벨: ${r.label.korean}  ·  총점: ${r.total.toStringAsFixed(1)}');
  // ignore: avoid_print
  print('=' * 72);

  // ignore: avoid_print
  print('\n[1] 한줄 요약');
  // ignore: avoid_print
  print(n.summary);

  // ignore: avoid_print
  print('\n[2] 핵심 궁합 3가지');
  // ignore: avoid_print
  print(n.corePoints);

  // ignore: avoid_print
  print('\n[3] 현실 갈등 시나리오');
  // ignore: avoid_print
  print(n.conflictScenarios);

  // ignore: avoid_print
  print('\n[4] 관계 운영 전략');
  // ignore: avoid_print
  print(n.strategy);

  // ignore: avoid_print
  print('\n[5] 궁합 점수와 이유');
  // ignore: avoid_print
  print(n.scoreReason);
  // ignore: avoid_print
  print('');
}

void main() {
  // MC bias map — 각 시나리오에서 특정 rule 이 확실히 발동하도록 강제.
  const idealMy = <String, double>{
    // 부부궁 double strong + 와잠 두툼 + 명궁 밝음.
    'eyeFissureRatio': 1.0,
    'browEyeDistance': 1.0,
    'lipFullnessRatio': 1.2,
    'lowerFaceFullness': 1.0,
    'upperFaceRatio': 0.8,
  };
  const idealAlbum = <String, double>{
    'eyeFissureRatio': 1.0,
    'browEyeDistance': 1.0,
    'lipFullnessRatio': 1.2,
    'lowerFaceFullness': 1.2,
    'upperFaceRatio': 0.8,
  };

  const conflictMy = <String, double>{
    // 매부리 × 매부리 + 이마 약 + 눈썹 진함.
    'dorsalConvexity': 2.0,
    'browThickness': 1.6,
    'upperFaceRatio': -1.2,
    'midFaceRatio': 1.4,
    'cheekboneWidth': 1.5,
  };
  const conflictAlbum = <String, double>{
    'dorsalConvexity': 2.0,
    'browThickness': 1.6,
    'upperFaceRatio': -1.2,
    'midFaceRatio': 1.4,
    'cheekboneWidth': 1.5,
  };

  const averageMy = <String, double>{};
  const averageAlbum = <String, double>{};

  test('■ 샘플 1 — 이상적 조합 (부부궁 튼튼 × 와잠 두툼 × 이마 밝음)', () {
    final rng = Random(1001);
    final my = _person(rng,
        biasMap: idealMy,
        shape: FaceShape.round,
        gender: Gender.male,
        age: AgeGroup.thirties);
    final al = _person(rng,
        biasMap: idealAlbum,
        shape: FaceShape.oval,
        gender: Gender.female,
        age: AgeGroup.thirties);
    final r = analyzeCompatibility(my: my, album: al);
    final n = buildCompatNarrative(report: r, pairSeed: 1);
    _printNarrative('이상적 조합', r, n);
    expect(n.sectionsInOrder.length, 5);
  });

  test('■ 샘플 2 — 충돌형 (매부리×매부리 · 강추진×강추진 · 이마 약)', () {
    final rng = Random(2002);
    final my = _person(rng,
        biasMap: conflictMy,
        shape: FaceShape.square,
        gender: Gender.male,
        age: AgeGroup.forties);
    final al = _person(rng,
        biasMap: conflictAlbum,
        shape: FaceShape.square,
        gender: Gender.female,
        age: AgeGroup.forties);
    final r = analyzeCompatibility(my: my, album: al);
    final n = buildCompatNarrative(report: r, pairSeed: 2);
    _printNarrative('충돌형 (강 대 강)', r, n);
    expect(n.sectionsInOrder.length, 5);
  });

  test('■ 샘플 3 — 평범한 중간형 (bias 없이 random z)', () {
    final rng = Random(3003);
    final my = _person(rng,
        biasMap: averageMy,
        shape: FaceShape.oval,
        gender: Gender.male,
        age: AgeGroup.thirties,
        sigma: 0.85);
    final al = _person(rng,
        biasMap: averageAlbum,
        shape: FaceShape.oval,
        gender: Gender.female,
        age: AgeGroup.thirties,
        sigma: 0.85);
    final r = analyzeCompatibility(my: my, album: al);
    final n = buildCompatNarrative(report: r, pairSeed: 3);
    _printNarrative('평범한 중간형', r, n);
    expect(n.sectionsInOrder.length, 5);
  });
}
