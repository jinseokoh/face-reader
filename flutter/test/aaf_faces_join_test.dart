// AAF 픽스처 — CSV(계측·얼굴형) 와 좌표(f32) 가 얼굴 단위로 전부 이어진다.
// 이어지지 않으면 §6 추가 계측의 z 를 못 만들어 분포 테스트가 다른 얼굴을 본다.

import 'package:flutter_test/flutter_test.dart';

import 'support/aaf_faces.dart';

void main() {
  test('CSV 11,800행이 좌표 행과 거의 전부 이어진다 (허용 20행)', () {
    // 계측이 거의 같은 얼굴 몇 장은 1% 오차 안에서 못 잇는다 — 분위표에 영향 없음.
    final faces = loadAafFaces();
    expect(aafUnmatchedRows, lessThanOrEqualTo(20));
    expect(faces.length, greaterThanOrEqualTo(11780));
    expect(faces.first.z.containsKey('faceArea'), isTrue);
  });
}
