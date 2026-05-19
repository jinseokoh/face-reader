import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:face_engine/data/enums/face_shape.dart';

/// 28-feature face-shape classifier (MLP, TFLite FP16, ~12 KB).
///
/// Training: niten19 Kaggle FaceShape Dataset (5000 images, 5 classes).
/// Test accuracy: 76.9% (vs 20% random baseline, vs 70.4% old 18-feature MLP).
///
/// Input:  28 ratios/angles/shapes from [FaceMetrics.computeAll()], in the
///         exact order of [FaceShapeClassifier.featureNames].
/// Output: softmax over {Heart, Oblong, Oval, Round, Square}.
///
/// Preprocessing: (x − mu) / sd with per-feature mu/sd loaded from
/// `assets/ml/scaler.json` (frozen from training StandardScaler).
enum FaceShapeClass { heart, oblong, oval, round, square }

extension FaceShapeClassLabel on FaceShapeClass {
  /// Korean label shown in UI (maps 5 Kaggle classes → Korean 관상 vocabulary).
  String get korean {
    switch (this) {
      case FaceShapeClass.heart: return '하트형';
      case FaceShapeClass.oblong: return '세로로 긴 얼굴형';
      case FaceShapeClass.oval: return '계란형';
      case FaceShapeClass.round: return '둥근 얼굴형';
      case FaceShapeClass.square: return '각진 얼굴형';
    }
  }

  String get english {
    switch (this) {
      case FaceShapeClass.heart: return 'Heart';
      case FaceShapeClass.oblong: return 'Oblong';
      case FaceShapeClass.oval: return 'Oval';
      case FaceShapeClass.round: return 'Round';
      case FaceShapeClass.square: return 'Square';
    }
  }

  /// 도메인 enum 으로 승격. Stage 0 preset / archetype / 서술 엔진에서 소비.
  FaceShape get domain {
    switch (this) {
      case FaceShapeClass.heart:
        return FaceShape.heart;
      case FaceShapeClass.oblong:
        return FaceShape.oblong;
      case FaceShapeClass.oval:
        return FaceShape.oval;
      case FaceShapeClass.round:
        return FaceShape.round;
      case FaceShapeClass.square:
        return FaceShape.square;
    }
  }
}

class FaceShapePrediction {
  final FaceShapeClass label;
  final double confidence;
  final List<double> probabilities; // Heart, Oblong, Oval, Round, Square

  const FaceShapePrediction({
    required this.label,
    required this.confidence,
    required this.probabilities,
  });
}

class FaceShapeClassifier {
  static const String _modelAsset = 'assets/ml/face_shape_ratios.tflite';
  static const String _scalerAsset = 'assets/ml/scaler.json';

  /// Exact order the model was trained on. DO NOT reorder.
  static const List<String> featureNames = [
    'faceAspectRatio', 'faceTaperRatio', 'lowerFaceFullness', 'upperFaceRatio',
    'midFaceRatio', 'lowerFaceRatio', 'gonialAngle', 'intercanthalRatio',
    'eyeFissureRatio', 'eyeCanthalTilt', 'eyebrowThickness', 'browEyeDistance',
    'nasalWidthRatio', 'nasalHeightRatio', 'mouthWidthRatio', 'mouthCornerAngle',
    'lipFullnessRatio', 'philtrumLength',
    // Phase 1 additions
    'eyebrowLength', 'eyebrowTiltDirection', 'eyebrowCurvature', 'browSpacing',
    'eyeAspect', 'upperVsLowerLipRatio', 'chinAngle',
    'foreheadWidth', 'cheekboneWidth', 'noseBridgeRatio',
  ];

  /// Class-prior 보정 — 현재 모델(`face_shape_ratios.tflite`)은 niten19 4000 +
  /// 57 East Asian sample 으로 직접 학습됐다. 즉 학습 단에서 이미 deploy
  /// distribution 으로 보정 완료 → 추가 prior 적용은 이중 보정으로 정확도
  /// 하락을 부른다 (측정: prior [0.4,0.6,2.5,1.0,0.5] → 64.9% vs uniform → 75.4%).
  /// 따라서 uniform 유지. 향후 분포 시프트 데이터가 누적되면 batch retrain
  /// 으로 model weight 자체를 갱신 (prior 가 아니라).
  static const List<double> _priorRatio = [
    1.0, // heart
    1.0, // oblong
    1.0, // oval
    1.0, // round
    1.0, // square
  ];

  Interpreter? _interpreter;
  List<double>? _mu;
  List<double>? _sd;

  static FaceShapeClassifier? _instance;
  static FaceShapeClassifier get instance => _instance ??= FaceShapeClassifier._();
  FaceShapeClassifier._();

  bool get isReady => _interpreter != null && _mu != null && _sd != null;

  Future<void> load() async {
    if (isReady) return;
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      final raw = await rootBundle.loadString(_scalerAsset);
      final j = json.decode(raw) as Map<String, dynamic>;
      final mu = (j['mu'] as List).map((e) => (e as num).toDouble()).toList();
      final sd = (j['sd'] as List).map((e) => (e as num).toDouble()).toList();
      final names = (j['feature_names'] as List).cast<String>();
      if (mu.length != featureNames.length ||
          sd.length != featureNames.length ||
          !_listEq(names, featureNames)) {
        throw StateError('scaler.json shape/order mismatch with model');
      }
      _mu = mu;
      _sd = sd;
      debugPrint('[FaceShapeClassifier] loaded — 28 features × 5 classes');
    } catch (e, st) {
      debugPrint('[FaceShapeClassifier] load failed: $e\n$st');
      _interpreter = null;
      _mu = null;
      _sd = null;
      rethrow;
    }
  }

  /// Returns null if the classifier is not loaded or any required feature is
  /// missing from [metrics]. Callers should treat null as "fall back to the
  /// legacy rule-based path".
  FaceShapePrediction? predict(Map<String, double> metrics) {
    if (!isReady) return null;

    final x = Float32List(featureNames.length);
    for (var i = 0; i < featureNames.length; i++) {
      final v = metrics[featureNames[i]];
      if (v == null || !v.isFinite) {
        debugPrint('[FaceShapeClassifier] missing/non-finite metric '
            '"${featureNames[i]}" → abort');
        return null;
      }
      x[i] = ((v - _mu![i]) / _sd![i]).toDouble();
    }

    final input = [x];
    final output = List.filled(1 * 5, 0.0).reshape([1, 5]);
    _interpreter!.run(input, output);
    final rawProbs = (output[0] as List).cast<double>();
    return applyPosterior(rawProbs);
  }

  /// raw softmax [heart, oblong, oval, round, square] 에 Bayesian prior 보정 +
  /// argmax 적용. predict() 의 post-process 부분이고, TFLite 없이 단독 호출
  /// 가능 — unit test 진입점.
  static FaceShapePrediction applyPosterior(List<double> rawProbs) {
    assert(rawProbs.length == 5, 'rawProbs must have 5 elements');
    final adjusted = List<double>.filled(rawProbs.length, 0.0);
    double sum = 0;
    for (var i = 0; i < rawProbs.length; i++) {
      final v = rawProbs[i] * _priorRatio[i];
      adjusted[i] = v;
      sum += v;
    }
    if (sum <= 0 || !sum.isFinite) {
      // Degenerate posterior — raw 그대로 사용 (분류기 misfire 방어).
      for (var i = 0; i < rawProbs.length; i++) {
        adjusted[i] = rawProbs[i];
      }
    } else {
      for (var i = 0; i < adjusted.length; i++) {
        adjusted[i] /= sum;
      }
    }

    var argmax = 0;
    var best = adjusted[0];
    for (var i = 1; i < adjusted.length; i++) {
      if (adjusted[i] > best) { best = adjusted[i]; argmax = i; }
    }
    debugPrint('[FaceShapeClassifier] '
        'raw=${rawProbs.map((e) => e.toStringAsFixed(2)).join(",")} '
        '→ posterior=${adjusted.map((e) => e.toStringAsFixed(2)).join(",")} '
        '→ ${FaceShapeClass.values[argmax].english}'
        '(${best.toStringAsFixed(2)})');
    return FaceShapePrediction(
      label: FaceShapeClass.values[argmax],
      confidence: best,
      probabilities: adjusted,
    );
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
