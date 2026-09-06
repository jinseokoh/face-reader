/// 얼굴 기하학 정규화 (APPLE.md §5) — 저장된 원본 좌표에서 로드 때 계산한다.
///
/// 입력은 리포트 `landmarks` (468 × [x, y], 등방 좌표 — x 는 사진 폭 기준,
/// y 는 높이 기준 값에 높이/폭을 곱한 것). 정규화는 세 단계다.
///   1. 이동 — 무게중심을 원점으로
///   2. 크기 — 원점까지 거리의 RMS 를 1 로
///   3. 회전 — 양 눈 바깥꼬리(33 → 263)가 수평이 되게
/// 그 뒤 두 얼굴을 겹칠 때는 Procrustes 정렬(회전만 추가로 맞춤)을 쓴다.
///
/// 정규화 좌표는 저장하지 않는다. 원본 + 모델 버전 = 같은 결과(§59).
library;

import 'dart:math';

/// 얼굴 영역별 랜드마크 — MediaPipe Face Mesh 표준 윤곽 인덱스.
/// 화면 강조(§24·§55)와 영역 Procrustes 거리에 쓴다. 키는 `geometryRegions` 와 같다.
const Map<String, List<int>> landmarkRegions = {
  'outline': [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
    378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
    162, 21, 54, 103, 67, 109,
  ],
  'eyes': [
    33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246,
    263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388,
    466,
  ],
  'brows': [70, 63, 105, 66, 107, 55, 65, 52, 53, 46, 300, 293, 334, 296, 336, 285, 295, 282, 283, 276],
  'nose': [168, 6, 197, 195, 5, 4, 1, 2, 98, 327, 48, 278, 64, 294, 129, 358, 97, 326],
  'mouth': [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185],
  'jaw': [234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152, 377, 400, 378, 379, 365, 397, 288, 361, 323, 454],
};

/// 그리기용 닫힌 윤곽(polyline). 눈·눈썹·입은 좌/우 또는 위/아래 두 갈래.
const Map<String, List<List<int>>> landmarkContours = {
  'outline': [
    [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
     378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
     162, 21, 54, 103, 67, 109, 10],
  ],
  'eyes': [
    [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246, 33],
    [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466, 263],
  ],
  'brows': [
    [70, 63, 105, 66, 107, 55, 65, 52, 53, 46, 70],
    [300, 293, 334, 296, 336, 285, 295, 282, 283, 276, 300],
  ],
  'nose': [
    [168, 6, 197, 195, 5, 4],
    [98, 97, 2, 326, 327],
    [48, 64, 129, 98],
    [278, 294, 358, 327],
  ],
  'mouth': [
    [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185, 61],
  ],
};

const int _leftEyeOuter = 33;
const int _rightEyeOuter = 263;

/// 이동·크기·회전 정규화. 퇴화(점이 한 곳)면 입력을 그대로 돌려준다.
List<List<double>> normalizeLandmarks(List<List<double>> pts) {
  final n = pts.length;
  if (n == 0) return pts;
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p[0];
    cy += p[1];
  }
  cx /= n;
  cy /= n;
  var ss = 0.0;
  for (final p in pts) {
    ss += (p[0] - cx) * (p[0] - cx) + (p[1] - cy) * (p[1] - cy);
  }
  final scale = sqrt(ss / n);
  if (scale == 0) return pts;
  final ex = pts[_rightEyeOuter][0] - pts[_leftEyeOuter][0];
  final ey = pts[_rightEyeOuter][1] - pts[_leftEyeOuter][1];
  final theta = -atan2(ey, ex);
  final c = cos(theta), s = sin(theta);
  return [
    for (final p in pts)
      [
        ((p[0] - cx) * c - (p[1] - cy) * s) / scale,
        ((p[0] - cx) * s + (p[1] - cy) * c) / scale,
      ],
  ];
}

/// [source] 를 [target] 에 최소제곱으로 맞추는 회전각(라디안). 둘 다 정규화된
/// 좌표여야 한다(이동·크기는 이미 같다).
double procrustesRotation(List<List<double>> source, List<List<double>> target) {
  var num = 0.0, den = 0.0;
  for (var i = 0; i < source.length; i++) {
    final sx = source[i][0], sy = source[i][1];
    final tx = target[i][0], ty = target[i][1];
    num += sx * ty - sy * tx;
    den += sx * tx + sy * ty;
  }
  return atan2(num, den);
}

List<List<double>> rotateLandmarks(List<List<double>> pts, double theta) {
  final c = cos(theta), s = sin(theta);
  return [
    for (final p in pts) [p[0] * c - p[1] * s, p[0] * s + p[1] * c],
  ];
}

/// Procrustes 정렬 결과 — 정규화된 두 얼굴과, [b] 를 [a] 에 맞춘 좌표.
class ProcrustesAlignment {
  final List<List<double>> a;
  final List<List<double>> bAligned;

  const ProcrustesAlignment({required this.a, required this.bAligned});

  /// 전체 RMS 거리 (정규화 단위).
  double get distance => regionDistance(null);

  /// 영역 RMS 거리. [region] null 이면 468점 전체.
  double regionDistance(String? region) {
    final idx = region == null
        ? List<int>.generate(a.length, (i) => i)
        : landmarkRegions[region]!;
    var ss = 0.0;
    for (final i in idx) {
      final dx = a[i][0] - bAligned[i][0];
      final dy = a[i][1] - bAligned[i][1];
      ss += dx * dx + dy * dy;
    }
    return sqrt(ss / idx.length);
  }
}

/// 두 얼굴을 정규화하고 [b] 를 [a] 에 Procrustes 정렬한다.
ProcrustesAlignment alignFaces(List<List<double>> a, List<List<double>> b) {
  final na = normalizeLandmarks(a);
  final nb = normalizeLandmarks(b);
  final theta = procrustesRotation(nb, na);
  return ProcrustesAlignment(a: na, bAligned: rotateLandmarks(nb, theta));
}
