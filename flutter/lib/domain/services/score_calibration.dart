/// Monte Carlo calibration — 상관 bone-structure + shape 분포 반영.
///
/// `flutter test test/calibration_test.dart` 를 돌리면 attribute_normalize.dart
/// 의 21-point quantile table 이 이 sampler 로 재생성된다.
///
/// Sampler 구조:
///   z[i] = μ + σ · (ε_idio + β_bone · z_bone + β_mid · z_mid)
/// 여기서
///   z_bone, z_mid ~ N(0, 1)  — 얼굴 단위 공통 성분 (bone structure, 중정 축)
///   ε_idio ~ N(0, 1)         — metric 별 독립 성분
///   β_bone, β_mid            — 해당 metric 의 bone/mid 로딩 (0~0.7)
/// 독립 가정을 풀어 실제 얼굴의 "여러 부위 동시 큼/작음" 양상을 반영.
///
/// Shape 분포:
///   계란형 35%, 긴형 18%, 둥근 15%, 각진 12%, 하트 10%, unknown 10%.
///   각 샘플에 얼굴형을 드로우 → 그 얼굴형의 bone 편향을 μ 에 얹는다.
library;

import 'dart:math';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

/// 21-point quantile array per attribute (p0, p5, …, p100).
Map<Attribute, List<double>> calibrateQuantiles({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final raws = _simulateRaws(samples: samples, seed: seed, gender: gender);
  final result = <Attribute, List<double>>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!..sort();
    result[attr] = List<double>.generate(21, (i) {
      final idx = ((list.length - 1) * (i / 20)).round();
      return list[idx];
    });
  }
  return result;
}

/// Per-attribute (mean, std) of raw scores — for distribution-health checks.
Map<Attribute, ({double mean, double std})> calibrateMeanStd({
  int samples = 20000,
  int seed = 42,
  Gender gender = Gender.male,
}) {
  final raws = _simulateRaws(samples: samples, seed: seed, gender: gender);
  final result = <Attribute, ({double mean, double std})>{};
  for (final attr in Attribute.values) {
    final list = raws[attr]!;
    final mean = list.reduce((a, b) => a + b) / list.length;
    final variance =
        list.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            list.length;
    result[attr] = (mean: mean, std: sqrt(variance));
  }
  return result;
}

// ───────── sampler internals ─────────

/// bone-structure 공통 성분이 얼마나 실리는지 per-metric. 0.6 = 강한 bone
/// 신호(뼈대·광대·턱 등), 0.3 = 중간(이마·코 shape), 0.0 = 무관(눈 fissure 등).
const _boneLoadings = <String, double>{
  'faceAspectRatio': 0.55,
  'faceTaperRatio': 0.45,
  'upperFaceRatio': 0.45,
  'foreheadWidth': 0.55,
  'cheekboneWidth': 0.60,
  'gonialAngle': 0.55,
  'lowerFaceRatio': 0.55,
  'lowerFaceFullness': 0.45,
  'chinAngle': 0.50,
  'nasalWidthRatio': 0.35,
  'nasalHeightRatio': 0.30,
  'eyebrowThickness': 0.25,
  'browEyeDistance': 0.25,
  // 아래는 bone 연동 약함(눈 shape, 입 등)
  'intercanthalRatio': 0.10,
  'eyeFissureRatio': 0.10,
  'eyeCanthalTilt': 0.05,
  'eyeAspect': 0.10,
  'mouthWidthRatio': 0.20,
  'mouthCornerAngle': 0.05,
  'lipFullnessRatio': 0.10,
  'upperVsLowerLipRatio': 0.05,
  'philtrumLength': 0.15,
  'browSpacing': 0.15,
  'eyebrowTiltDirection': 0.05,
  'eyebrowCurvature': 0.05,
  // lateral
  'nasofrontalAngle': 0.25,
  'nasolabialAngle': 0.05,
  'noseTipProjection': 0.20,
  'dorsalConvexity': 0.10,
  'upperLipEline': 0.10,
  'lowerLipEline': 0.10,
  'mentolabialAngle': 0.20,
  'facialConvexity': 0.40,
};

/// 중정 축(midFace) 공통 성분 로딩. 중정 비율·광대·코 높이가 함께 움직이는 양상.
const _midLoadings = <String, double>{
  'midFaceRatio': 0.70,
  'nasalHeightRatio': 0.35,
  'cheekboneWidth': 0.30,
  'eyeFissureRatio': 0.15,
  'intercanthalRatio': 0.10,
  'nasalWidthRatio': 0.15,
  'noseTipProjection': 0.15,
};

/// 얼굴형별 base-metric bias — sampler μ 에 얹어 "이 얼굴형이면 이 metric 이
/// 보통 이 방향" 을 모사. z-score 기준 shift(단위: 표준편차).
const _shapeMetricBias = <FaceShape, Map<String, double>>{
  FaceShape.oval: {
    'faceAspectRatio': 0.10,
    'faceTaperRatio': 0.00,
  },
  FaceShape.oblong: {
    'faceAspectRatio': 0.80,
    'upperFaceRatio': 0.35,
    'lowerFaceRatio': 0.30,
    'cheekboneWidth': -0.25,
  },
  FaceShape.round: {
    'faceAspectRatio': -0.70,
    'faceTaperRatio': -0.20,
    'lowerFaceFullness': 0.40,
    'gonialAngle': -0.30,
  },
  FaceShape.square: {
    'faceAspectRatio': -0.10,
    'gonialAngle': 0.70,
    'cheekboneWidth': 0.45,
    'foreheadWidth': 0.35,
    'chinAngle': 0.40,
  },
  FaceShape.heart: {
    'faceAspectRatio': 0.20,
    'faceTaperRatio': 0.70,
    'foreheadWidth': 0.35,
    'cheekboneWidth': 0.20,
    'lowerFaceRatio': -0.30,
    'gonialAngle': -0.30,
  },
  FaceShape.unknown: {},
};

Map<Attribute, List<double>> _simulateRaws({
  required int samples,
  required int seed,
  required Gender gender,
}) {
  final rng = Random(seed);
  final raws = {for (final a in Attribute.values) a: <double>[]};

  double normal() {
    double u1, u2;
    do {
      u1 = rng.nextDouble();
    } while (u1 == 0.0);
    u2 = rng.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  for (int i = 0; i < samples; i++) {
    // 샘플 단위 공통 성분 2 개.
    final zBone = normal();
    final zMid = normal();
    final shape = drawShape(rng);
    final bias = _shapeMetricBias[shape] ?? const <String, double>{};

    final z = <String, double>{};
    for (final info in metricInfoList) {
      final bLoad = _boneLoadings[info.id] ?? 0.0;
      final mLoad = _midLoadings[info.id] ?? 0.0;
      // 분산 보존: σ_idio² + σ_bone² + σ_mid² = 1 이 되도록 idio 를 축소.
      final idioW = sqrt((1 - bLoad * bLoad - mLoad * mLoad).clamp(0.05, 1.0));
      final shapeBias = bias[info.id] ?? 0.0;
      final raw =
          _inputMean + shapeBias + _inputStd *
              (bLoad * zBone + mLoad * zMid + idioW * normal());
      z[info.id] = raw.clamp(-3.5, 3.5);
    }

    final tree = scoreTree(z);
    final scores = deriveAttributeScores(
      tree: tree,
      gender: gender,
      isOver50: false,
      hasLateral: false,
      faceShape: shape,
      shapeConfidence: shape == FaceShape.unknown ? 0.0 : 0.8,
    );
    for (final attr in Attribute.values) {
      raws[attr]!.add(scores[attr] ?? 0.0);
    }
  }
  return raws;
}

/// Format quantiles as a drop-in Dart const block for attribute_normalize.dart.
String formatQuantiles(
    Map<Attribute, List<double>> male, Map<Attribute, List<double>> female) {
  String fmtArr(List<double> q) =>
      '[${q.map((v) => v.toStringAsFixed(3)).join(', ')}]';

  final buf = StringBuffer();
  buf.writeln('const _attrQuantilesMale = <Attribute, List<double>>{');
  for (final attr in Attribute.values) {
    buf.writeln('  Attribute.${attr.name}: ${fmtArr(male[attr]!)},');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln('const _attrQuantilesFemale = <Attribute, List<double>>{');
  for (final attr in Attribute.values) {
    buf.writeln('  Attribute.${attr.name}: ${fmtArr(female[attr]!)},');
  }
  buf.writeln('};');
  return buf.toString();
}

String formatMeanStd(Map<Attribute, ({double mean, double std})> male,
    Map<Attribute, ({double mean, double std})> female) {
  final buf = StringBuffer();
  buf.writeln(
      'const _attrCalibrationMale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = male[attr]!;
    buf.writeln(
        '  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  buf.writeln();
  buf.writeln(
      'const _attrCalibrationFemale = <Attribute, ({double mean, double std})>{');
  for (final attr in Attribute.values) {
    final r = female[attr]!;
    buf.writeln(
        '  Attribute.${attr.name}: (mean: ${r.mean.toStringAsFixed(3)}, std: ${r.std.toStringAsFixed(3)}),');
  }
  buf.writeln('};');
  return buf.toString();
}

const double _inputMean = 0.0;
const double _inputStd = 0.85;
