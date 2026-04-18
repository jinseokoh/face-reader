import 'package:face_reader/domain/services/physiognomy_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaf own stats: signed + abs mean from input z', () {
    final s = scoreTree({
      'upperFaceRatio': 1.5,
      'foreheadWidth': -0.5,
    });
    final forehead = s.descendantById('forehead')!;
    expect(forehead.ownMetricCount, 2);
    expect(forehead.ownMeanZ, closeTo(0.5, 1e-9));
    expect(forehead.ownMeanAbsZ, closeTo(1.0, 1e-9));
  });

  test('missing metric excluded from stats', () {
    final s = scoreTree({'upperFaceRatio': 1.0}); // foreheadWidth missing
    final forehead = s.descendantById('forehead')!;
    expect(forehead.ownMetricCount, 1);
    expect(forehead.ownMeanZ, 1.0);
  });

  test('zone roll-up aggregates descendants', () {
    // upper zone has no own metrics; roll-up combines 이마·미간·눈썹
    final s = scoreTree({
      'upperFaceRatio': 1.0, // forehead
      'foreheadWidth': 1.0, // forehead
      'eyebrowThickness': 2.0, // eyebrow
    });
    final upper = s.descendantById('upper')!;
    expect(upper.ownMetricCount, 0);
    expect(upper.ownMeanZ, isNull);
    expect(upper.rollUpMetricCount, 3);
    expect(upper.rollUpMeanZ, closeTo(4.0 / 3, 1e-9));
    expect(upper.rollUpMeanAbsZ, closeTo(4.0 / 3, 1e-9));
  });

  test('unsupported ear node contributes nothing', () {
    final s = scoreTree({'intercanthalRatio': 1.0});
    final ear = s.descendantById('ear')!;
    expect(ear.ownMetricCount, 0);
    expect(ear.rollUpMetricCount, 0);
    expect(ear.ownMeanZ, isNull);
  });

  test('empty glabella returns null stats', () {
    final s = scoreTree({});
    final glabella = s.descendantById('glabella')!;
    expect(glabella.ownMeanZ, isNull);
    expect(glabella.rollUpMeanZ, isNull);
  });

  test('root has own metrics (faceAspectRatio etc)', () {
    final s = scoreTree({
      'faceAspectRatio': 2.0,
      'faceTaperRatio': -1.0,
      'midFaceRatio': 0.0,
    });
    expect(s.nodeId, 'face');
    expect(s.ownMetricCount, 3);
    expect(s.ownMeanZ, closeTo(1.0 / 3, 1e-9));
    expect(s.ownMeanAbsZ, closeTo(1.0, 1e-9));
  });

  test('root roll-up covers all present metrics across entire tree', () {
    final s = scoreTree({
      'faceAspectRatio': 1.0, // root
      'upperFaceRatio': 1.0, // forehead
      'intercanthalRatio': 1.0, // eye
      'gonialAngle': 1.0, // chin
    });
    expect(s.rollUpMetricCount, 4);
    expect(s.rollUpMeanZ, closeTo(1.0, 1e-9));
  });

  test('signed mean cancels positive and negative', () {
    final s = scoreTree({
      'mouthWidthRatio': 1.0,
      'mouthCornerAngle': -1.0,
      'lipFullnessRatio': 1.0,
      'upperVsLowerLipRatio': -1.0,
    });
    final mouth = s.descendantById('mouth')!;
    expect(mouth.ownMeanZ, closeTo(0.0, 1e-9));
    expect(mouth.ownMeanAbsZ, closeTo(1.0, 1e-9));
  });

  test('tree topology preserved in score mirror', () {
    final s = scoreTree({});
    expect(s.children.length, 3); // upper, middle, lower
    final middle = s.descendantById('middle')!;
    expect(middle.children.length, 4); // eye, nose, cheekbone, ear
  });
}
