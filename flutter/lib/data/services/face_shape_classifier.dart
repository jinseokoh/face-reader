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

  /// Bayesian class-prior 보정 — 학습 set(niten19) 은 5 class 균등
  /// (1000 each, prior=0.20). 실배포 demographic(동아시아 30대 여성) 은
  /// oval-dominant. 한국 성형외과 anthropometry 및 self-report study 기준
  /// 동아시아 성인 여성의 face shape 분포:
  ///   oval 0.50, oblong 0.12, round 0.20, square 0.10, heart 0.08.
  /// posterior ∝ ML_softmax × (deploy_prior / training_prior=0.20).
  /// ratio: oval ×2.5, oblong ×0.6, round ×1.0, square ×0.5, heart ×0.4.
  ///
  /// 효과:
  ///   * raw oblong=0.40 / oval=0.35  →  posterior oval=0.62 / oblong=0.32 (flip)
  ///   * raw oblong=0.55 / oval=0.25  →  posterior oval=0.57 / oblong=0.30 (flip)
  ///   * raw oblong=0.80 / oval=0.08  →  posterior oblong=0.80 / oval=0.13 (stay)
  /// niten19 uniform prior 가 만든 "oblong 과추정" 편향을 닫으면서 진짜
  /// oblong(>3.5× oval) 은 살린다.
  static const List<double> _priorRatio = [
    0.4, // heart
    0.6, // oblong
    2.5, // oval
    1.0, // round
    0.5, // square
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
