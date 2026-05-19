import 'package:flutter_test/flutter_test.dart';
import 'package:face_reader/data/services/face_shape_classifier.dart';

/// `FaceShapeClassifier.applyPosterior()` unit tests.
///
/// 현재 모델(`assets/ml/face_shape_ratios.tflite`)은 niten19 4000 + 57 East
/// Asian sample 으로 함께 학습됐다. 학습 단에서 이미 deploy distribution 보정
/// 완료이므로 prior 는 uniform [1,1,1,1,1]. applyPosterior() 는 사실상
/// normalize + argmax 의 항등 변환.
///
/// 입력 인덱스: [heart, oblong, oval, round, square]
void main() {
  group('applyPosterior — uniform prior (모델이 East Asian 보정 내장)', () {
    test('argmax 가 raw softmax 의 argmax 와 동일', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.40, 0.35, 0.10, 0.10],
      );
      expect(pred.label, FaceShapeClass.oblong,
          reason: 'uniform prior 에선 raw argmax 가 그대로 유지');
    });

    test('확률 분포 모양 유지: 합 = 1, 각 값 [0,1]', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.55, 0.25, 0.10, 0.05],
      );
      double sum = 0;
      for (final p in pred.probabilities) {
        expect(p, inInclusiveRange(0.0, 1.0));
        sum += p;
      }
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('one-hot input → 그대로 보존', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.0, 0.0, 1.0, 0.0, 0.0],
      );
      expect(pred.label, FaceShapeClass.oval);
      expect(pred.probabilities[2], closeTo(1.0, 1e-9));
    });

    test('order invariant: [heart, oblong, oval, round, square] index 매칭', () {
      // 1.0 위치를 바꿔서 각 클래스 매핑 확인
      final pH = FaceShapeClassifier.applyPosterior([1, 0, 0, 0, 0]);
      final pOb = FaceShapeClassifier.applyPosterior([0, 1, 0, 0, 0]);
      final pOv = FaceShapeClassifier.applyPosterior([0, 0, 1, 0, 0]);
      final pR = FaceShapeClassifier.applyPosterior([0, 0, 0, 1, 0]);
      final pSq = FaceShapeClassifier.applyPosterior([0, 0, 0, 0, 1]);
      expect(pH.label, FaceShapeClass.heart);
      expect(pOb.label, FaceShapeClass.oblong);
      expect(pOv.label, FaceShapeClass.oval);
      expect(pR.label, FaceShapeClass.round);
      expect(pSq.label, FaceShapeClass.square);
    });

    test('degenerate raw (all zero) → fallback raw 그대로, no crash', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.0, 0.0, 0.0, 0.0, 0.0],
      );
      // 후속 코드에서 confidence < 0.5 → fallback rule path 타도록 동작.
      expect(pred.confidence, lessThan(0.5));
      expect(pred.probabilities.length, 5);
    });
  });

  group('applyPosterior — 회귀 차단 (수치 snapshot)', () {
    test('snapshot: uniform prior 는 raw 를 변형 없이 유지', () {
      // uniform prior → 입력 raw 가 그대로 출력. 합이 1.0 가까우면 거의 그대로.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.40, 0.35, 0.10, 0.10],
      );
      // raw sum = 1.0 이므로 normalize 후 동일
      expect(pred.probabilities[0], closeTo(0.05, 1e-6));
      expect(pred.probabilities[1], closeTo(0.40, 1e-6));
      expect(pred.probabilities[2], closeTo(0.35, 1e-6));
      expect(pred.probabilities[3], closeTo(0.10, 1e-6));
      expect(pred.probabilities[4], closeTo(0.10, 1e-6));
    });

    test('snapshot: 비정규화 raw 도 합=1로 정규화', () {
      // raw 합이 1.0 이 아닐 때 — 정규화 일관성 확인
      final pred = FaceShapeClassifier.applyPosterior(
        [0.1, 0.2, 0.3, 0.4, 0.5], // sum = 1.5
      );
      // / 1.5
      expect(pred.probabilities[0], closeTo(0.0667, 1e-3));
      expect(pred.probabilities[1], closeTo(0.1333, 1e-3));
      expect(pred.probabilities[2], closeTo(0.2000, 1e-3));
      expect(pred.probabilities[3], closeTo(0.2667, 1e-3));
      expect(pred.probabilities[4], closeTo(0.3333, 1e-3));
      expect(pred.label, FaceShapeClass.square);
    });
  });
}
