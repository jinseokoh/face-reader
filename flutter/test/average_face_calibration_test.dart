// 기준 집단 평균 얼굴 — AAF 11,800장 정규화 좌표(§5)의 성별 평균을 생성한다.
// 얼굴 지도(§55)에서 내 얼굴 밑에 회색으로 깔린다.
// 출력 → shared/lib/data/constants/average_face.dart
// 실행: flutter test test/average_face_calibration_test.dart --plain-name generate

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/landmark_normalize.dart';

import 'support/aaf_landmarks.dart';

void main() {
  test('generate average face', () {
    final faces = loadAafLandmarks();
    final buf = StringBuffer();
    for (final g in Gender.values) {
      final sum = List.generate(468, (_) => [0.0, 0.0]);
      var n = 0;
      for (final f in faces.where((f) => f.gender == g)) {
        final norm = normalizeLandmarks(f.points);
        for (var i = 0; i < 468; i++) {
          sum[i][0] += norm[i][0];
          sum[i][1] += norm[i][1];
        }
        n++;
      }
      // 평균 뒤 한 번 더 정규화 — 평균은 RMS 가 1 보다 살짝 작아진다.
      final mean = normalizeLandmarks(
          [for (final p in sum) [p[0] / n, p[1] / n]]);
      buf.writeln('  Gender.${g.name}: [ // n=$n');
      for (final p in mean) {
        buf.writeln('    [${p[0].toStringAsFixed(4)}, ${p[1].toStringAsFixed(4)}],');
      }
      buf.writeln('  ],');
    }
    // ignore: avoid_print
    print(buf.toString());
  });
}
