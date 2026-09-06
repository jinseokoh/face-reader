/// 좌우 대칭 계측 — 정면 468 랜드마크에서 영역별 비대칭도 5개 + 전체.
///
/// 정의 (tools/face_shape_ml/extract_aaf_symmetry.py 와 1:1):
///   midline = nasion(168) → chin(152). u = 단위 방향, n = 법선.
///   점 P 의 (s, t) = ((P−nasion)·u, (P−nasion)·n), 등방 좌표(y × aspect).
///   좌우 쌍 (L, R): R 을 midline 에 대칭시킨 (s_R, −t_R) 과 L 의 거리 / faceWidth.
///   영역 값 = 그 영역 쌍들의 평균. overall = 5 영역 평균. **0 이 완전 대칭.**
///
/// 값이 작을수록 대칭이다. 화면·첫인상 feature 에서는 부호를 뒤집어
/// "대칭성" 으로 읽는다 (`symmetryFeatureSign`).
library;

import 'dart:math';

const List<String> symmetryIds = [
  'symEyes',
  'symBrows',
  'symNose',
  'symMouth',
  'symOutline',
  'symOverall',
];

const Map<String, String> symmetryNameKo = {
  'symEyes': '눈 대칭',
  'symBrows': '눈썹 대칭',
  'symNose': '코 대칭',
  'symMouth': '입 대칭',
  'symOutline': '윤곽 대칭',
  'symOverall': '얼굴 대칭',
};

const Map<String, List<List<int>>> symmetryPairs = {
  'symEyes': [
    [33, 263],
    [133, 362],
    [159, 386],
    [145, 374],
  ],
  'symBrows': [
    [46, 276],
    [52, 282],
    [55, 285],
    [70, 300],
    [105, 334],
  ],
  'symNose': [
    [98, 327],
    [48, 278],
  ],
  'symMouth': [
    [61, 291],
    [78, 308],
    [40, 270],
    [84, 314],
  ],
  'symOutline': [
    [234, 454],
    [132, 361],
    [172, 397],
    [150, 379],
    [148, 377],
    [54, 284],
    [116, 345],
  ],
};

/// [points] = 468 × [x, y(, z)] 정규화 좌표. [aspect] = imageHeight / imageWidth.
/// 반환: symmetryIds 순서의 map. 계산 불가(퇴화)면 빈 map.
Map<String, double> computeSymmetry(
  List<List<double>> points, {
  double aspect = 1.0,
}) {
  double x(int i) => points[i][0];
  double y(int i) => points[i][1] * aspect;

  final nx = x(168), ny = y(168);
  var ux = x(152) - nx, uy = y(152) - ny;
  final norm = sqrt(ux * ux + uy * uy);
  if (norm == 0) return const {};
  ux /= norm;
  uy /= norm;
  final nnx = -uy, nny = ux;
  final fw = sqrt(pow(x(454) - x(234), 2) + pow(y(454) - y(234), 2));
  if (fw == 0) return const {};

  (double, double) st(int i) {
    final dx = x(i) - nx, dy = y(i) - ny;
    return (dx * ux + dy * uy, dx * nnx + dy * nny);
  }

  final out = <String, double>{};
  var sum = 0.0;
  for (final e in symmetryPairs.entries) {
    var acc = 0.0;
    for (final p in e.value) {
      final (sa, ta) = st(p[0]);
      final (sb, tb) = st(p[1]);
      acc += sqrt(pow(sa - sb, 2) + pow(ta + tb, 2)) / fw;
    }
    final v = acc / e.value.length;
    out[e.key] = v;
    sum += v;
  }
  out['symOverall'] = sum / symmetryPairs.length;
  return out;
}
