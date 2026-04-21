/// 五行 체형 classifier — metric z-score → `FiveElements`.
///
/// 입력: 관상 엔진이 산출한 z-score map + `FaceShape` preset + confidence.
/// 출력: primary/secondary + confidence + 5-형 정규화 score map.
///
/// 공식은 `docs/compat/FRAMEWORK.md` §2.2 그대로. preset boost §2.3 동일.
library;

import 'dart:math';

import 'package:face_reader/data/enums/face_shape.dart';

import 'five_element.dart';

/// weight 계수. map key = metric id, value = z-score 계수.
/// §2.2 로부터 1:1 복사.
const Map<FiveElement, Map<String, double>> _weights = {
  FiveElement.wood: {
    'faceAspectRatio': 1.3,
    'lowerFaceRatio': -0.8,
    'foreheadWidth': 0.6,
    'cheekboneWidth': -0.7,
    'browEyeDistance': 0.4,
    'lipFullnessRatio': -0.5,
  },
  FiveElement.fire: {
    'gonialAngle': 1.1,
    'lowerFaceRatio': -0.9,
    'cheekboneWidth': 0.9,
    'faceAspectRatio': -0.6,
    'eyebrowThickness': 0.5,
    'eyeCanthalTilt': 0.4,
  },
  FiveElement.earth: {
    'faceAspectRatio': -1.1,
    'cheekboneWidth': 1.0,
    'lowerFaceRatio': 0.9,
    'nasalWidthRatio': 0.7,
    'lipFullnessRatio': 0.5,
    'gonialAngle': -0.4,
  },
  FiveElement.metal: {
    'faceAspectRatio': -0.2,
    'gonialAngle': -1.1,
    'faceTaperRatio': 0.8,
    'foreheadWidth': 0.6,
    'lipFullnessRatio': -0.4,
    'browEyeDistance': 0.5,
    'philtrumLength': 0.3,
  },
  FiveElement.water: {
    'faceAspectRatio': -1.0,
    'lowerFaceFullness': 1.0,
    'lipFullnessRatio': 0.8,
    'faceTaperRatio': -0.9,
    'eyeFissureRatio': 0.5,
    'mouthWidthRatio': 0.4,
  },
};

/// §2.3 preset boost — faceShapeConfidence ≥ 0.6 일 때만 적용.
/// element 별 추가 raw score (정규화 전에 더함).
const Map<FaceShape, Map<FiveElement, double>> _presetBoost = {
  FaceShape.oblong: {FiveElement.wood: 15, FiveElement.metal: 5},
  FaceShape.heart: {FiveElement.fire: 15, FiveElement.wood: 3},
  FaceShape.round: {FiveElement.water: 18, FiveElement.earth: 5},
  FaceShape.square: {FiveElement.metal: 20, FiveElement.earth: 3},
  FaceShape.oval: {FiveElement.earth: 8, FiveElement.water: 5},
  FaceShape.unknown: {},
};

/// preset boost gate — faceShapeConfidence 이상에서만 boost 적용.
const double _presetConfidenceGate = 0.6;

/// 분류 실행. 5-형 raw score 를 softmax → 0~100 normalize.
///
/// - `zMap`: 17 frontal + 8 lateral z-score (관상 엔진 출력).
/// - `faceShape` / `shapeConfidence`: stage-0 preset input (없으면 unknown · 0).
FiveElements classifyFiveElements({
  required Map<String, double> zMap,
  required FaceShape faceShape,
  required double shapeConfidence,
}) {
  final raw = <FiveElement, double>{};
  for (final el in FiveElement.values) {
    double s = 0.0;
    final w = _weights[el]!;
    for (final entry in w.entries) {
      final z = zMap[entry.key] ?? 0.0;
      s += entry.value * z;
    }
    raw[el] = s;
  }

  if (shapeConfidence >= _presetConfidenceGate) {
    final boost = _presetBoost[faceShape] ?? const {};
    for (final entry in boost.entries) {
      raw[entry.key] = (raw[entry.key] ?? 0.0) + entry.value;
    }
  }

  final softmax = _softmaxToPercent(raw);

  final sorted = softmax.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top1 = sorted[0];
  final top2 = sorted[1];
  final confidence =
      top1.value > 0 ? (top1.value - top2.value) / top1.value : 0.0;

  return FiveElements(
    primary: top1.key,
    secondary: top2.key,
    confidence: confidence.clamp(0.0, 1.0),
    scores: softmax,
  );
}

/// softmax with temperature 1.0, 결과를 0~100 scale 로.
/// 수치 안정을 위해 max-subtract.
Map<FiveElement, double> _softmaxToPercent(Map<FiveElement, double> raw) {
  final values = raw.values.toList();
  final maxV = values.reduce(max);
  double denom = 0.0;
  final exps = <FiveElement, double>{};
  for (final entry in raw.entries) {
    final e = exp(entry.value - maxV);
    exps[entry.key] = e;
    denom += e;
  }
  final out = <FiveElement, double>{};
  for (final entry in exps.entries) {
    out[entry.key] = (entry.value / denom) * 100.0;
  }
  return out;
}
