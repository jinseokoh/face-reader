import 'package:flutter_test/flutter_test.dart';
import 'package:face_reader/data/services/face_shape_classifier.dart';

/// FaceShapeClassifier.applyPosterior() unit tests.
///
/// niten19 학습 set 은 5 class 균등(uniform prior=0.20). 실배포 demographic
/// (동아시아 30대 여성) 은 oval-dominant. Bayesian posterior 보정으로
/// oblong vs oval boundary 케이스가 oval 로 flip 되는지, 진짜 oblong 케이스는
/// 보존되는지 직접 검증.
///
/// 입력 인덱스: [heart, oblong, oval, round, square]
void main() {
  group('applyPosterior — niten19 → East Asian female prior 보정', () {
    test('boundary 1: raw oblong=0.40 / oval=0.35 → oval flip', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.40, 0.35, 0.10, 0.10],
      );
      expect(pred.label, FaceShapeClass.oval,
          reason: '얕은 boundary (5pt 차이) 에서 oval prior boost 가 이겨야 함');
      expect(pred.confidence, greaterThan(0.5));
    });

    test('boundary 2: raw oblong=0.55 / oval=0.25 (사용자 사진 추정 case) → oval flip', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.55, 0.25, 0.10, 0.05],
      );
      expect(pred.label, FaceShapeClass.oval,
          reason: '동아시아 여성 사진이 oval 인데 모델이 oblong 으로 약 2× 밀어도 '
              'deploy prior 가 뒤집어야 함 (실제 사용자 사진 시나리오)');
      expect(pred.confidence, greaterThan(0.5));
    });

    test('boundary 3: raw oblong=0.70 / oval=0.20 (3.5× oblong) → 아직 oval flip', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.04, 0.70, 0.20, 0.03, 0.03],
      );
      expect(pred.label, FaceShapeClass.oval,
          reason: '동아시아 여성 deploy prior(0.5/0.12) ratio 4.2× 이므로 '
              '모델이 3.5× oblong dominant 까지는 oval 로 뒤집힘');
    });

    test('hard oblong: raw oblong=0.85 (>4× oval) → oblong 보존', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.02, 0.85, 0.08, 0.03, 0.02],
      );
      expect(pred.label, FaceShapeClass.oblong,
          reason: '진짜 oblong 케이스(>4× margin) 까지 prior 가 죽이면 안 됨');
      expect(pred.confidence, greaterThan(0.6));
    });

    test('clear oval: raw oval=0.60 → oval 그대로', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.15, 0.60, 0.10, 0.10],
      );
      expect(pred.label, FaceShapeClass.oval);
      expect(pred.confidence, greaterThan(0.8),
          reason: 'clear oval 은 prior 가 보조해서 confidence 더 올라가야 함');
    });

    test('clear round: raw round=0.55 → round 그대로 (square 으로 안 새야 함)', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.10, 0.10, 0.55, 0.20],
      );
      expect(pred.label, FaceShapeClass.round);
    });

    test('clear heart: raw heart=0.75 → heart 그대로 (oval 보정에 묻히지 않음)', () {
      // heart prior(0.08) vs oval prior(0.50) ratio 6.25× 이므로 oval 을 raw
      // margin 으로 충분히 누르려면 heart raw 가 oval 의 6.25× 이상이어야 한다.
      // raw=[0.75, 0.05, 0.08, 0.06, 0.06] 이면 heart/oval raw margin 9.4× →
      // posterior 에서도 heart 우세.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.75, 0.05, 0.08, 0.06, 0.06],
      );
      expect(pred.label, FaceShapeClass.heart,
          reason: 'heart prior 가 약해도 raw 가 9× margin 이면 보존되어야 함');
    });

    test('borderline heart: raw heart=0.55 / oval=0.15 → prior 가 oval 쪽으로 당김', () {
      // 동아시아 deploy 에선 heart 가 8% 분포라, heart raw 가 압도적이지 않으면
      // 더 흔한 oval 로 회귀 — 이는 의도된 동작.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.55, 0.10, 0.20, 0.08, 0.07],
      );
      expect(pred.label, FaceShapeClass.oval,
          reason: 'heart raw 가 oval 의 2.75× 정도(약한 margin) 면 prior 보정으로 '
              'oval 이 이겨야 한다 — heart 8% vs oval 50% deploy distribution');
    });

    test('posterior 확률은 [0,1] 범위 + 총합 = 1', () {
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

    test('degenerate raw (all zero) → fallback raw 그대로, no crash', () {
      final pred = FaceShapeClassifier.applyPosterior(
        [0.0, 0.0, 0.0, 0.0, 0.0],
      );
      // 후속 코드에서 confidence < 0.5 → fallback rule path 타도록 동작.
      expect(pred.confidence, lessThan(0.5));
      expect(pred.probabilities.length, 5);
    });

    test('order invariant: [heart, oblong, oval, round, square] index 매칭', () {
      // 인덱스 i=2 가 oval 이어야 함 (FaceShapeClass.values 순서와 동일)
      final pred = FaceShapeClassifier.applyPosterior(
        [0.0, 0.0, 1.0, 0.0, 0.0],
      );
      expect(pred.label, FaceShapeClass.oval);
      expect(pred.probabilities[2], closeTo(1.0, 1e-9));
    });
  });

  group('applyPosterior — 사용자 사진 (실측 evidence)', () {
    test('30대 동아시아 여성 사진, square-padded → Oval (Python parity 실측)', () {
      // /tmp/probe.png (876×896 near-square) 사용자 사진을 동일 파이프라인
      // (MediaPipe → 28 features → scaler.json → TFLite) 으로 통과시킨 실측
      // raw softmax. probe_photo.py 결과:
      //   Heart=0.0259, Oblong=0.1274, Oval=0.7906, Round=0.0560, Square=0.0001
      // 이 photo 가 album path 의 square-padding fix 후 앱이 보게 될 값.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.025898, 0.127407, 0.790637, 0.055990, 0.000067],
      );
      expect(pred.label, FaceShapeClass.oval);
      expect(pred.confidence, greaterThan(0.85),
          reason: 'raw oval=0.79 + East Asian female prior×2.5 → posterior ≥0.85');
    });

    test('square-padded 변형 사진 — 직접 측정한 raw 도 Oval', () {
      // verify_fix2.py 의 padded→sq 1023×1023 결과 (the user's 461×1024 phone
      // screenshot 이 square-padding fix 후 mediapipe 가 보는 image):
      //   Heart=0.010, Oblong=0.199, Oval=0.493, Round=0.297, Square=0.000
      // raw 만으로도 oval(0.493) 이 argmax. prior 가 oval=0.74 까지 boost.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.010, 0.199, 0.493, 0.297, 0.001],
      );
      expect(pred.label, FaceShapeClass.oval);
      expect(pred.confidence, greaterThan(0.7));
    });

    test('회귀 차단: 9:20 phone screenshot WITHOUT square-padding fix → Oblong (버그 재현)', () {
      // verify_fix2.py 의 narrow 461×1023 (square padding 미적용) 결과:
      //   Heart=0.001, Oblong=0.999, Oval=0.000, Round=0.000, Square=0.000
      // 이 경로가 살아남으면 사용자가 보고한 버그 그대로 — square-padding fix 가
      // 적용되어야만 oval 로 회귀.
      final pred = FaceShapeClassifier.applyPosterior(
        [0.001, 0.999, 0.000, 0.000, 0.000],
      );
      expect(pred.label, FaceShapeClass.oblong,
          reason: 'square-padding 없으면 raw oblong=0.999 — prior 만으론 못 뒤집힘. '
              'fix 는 album_capture_page._processAlbumPhoto 의 image 수준에서.');
    });
  });

  group('applyPosterior — 회귀 차단 (수치 snapshot)', () {
    test('snapshot: raw [0.05, 0.40, 0.35, 0.10, 0.10] posterior 수치', () {
      // raw × prior [0.4, 0.6, 2.5, 1.0, 0.5] = [0.020, 0.240, 0.875, 0.100, 0.050]
      // sum = 1.285
      // normalized = [0.01556, 0.18677, 0.68094, 0.07782, 0.03891]
      final pred = FaceShapeClassifier.applyPosterior(
        [0.05, 0.40, 0.35, 0.10, 0.10],
      );
      expect(pred.probabilities[0], closeTo(0.01556, 1e-4)); // heart
      expect(pred.probabilities[1], closeTo(0.18677, 1e-4)); // oblong
      expect(pred.probabilities[2], closeTo(0.68094, 1e-4)); // oval
      expect(pred.probabilities[3], closeTo(0.07782, 1e-4)); // round
      expect(pred.probabilities[4], closeTo(0.03891, 1e-4)); // square
    });
  });
}
