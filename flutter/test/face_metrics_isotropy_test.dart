// 같은 얼굴을 종횡비가 다른 사진으로 찍어도 26개 metric 이 같아야 한다.
//
// MediaPipe 는 x 를 이미지 **폭**으로, y 를 **높이**로 각각 나눈 0~1 좌표를 준다.
// 정사각형이 아닌 사진에서는 두 축의 축척이 달라 좌표계가 비등방이 되고, 각도와
// 세로÷가로 비율이 사진 크기에 따라 달라진다. `FaceMetrics.aspect` 가 y 를
// 되돌려 이 오염을 제거한다.
//
// 이 테스트가 없던 동안 `face_metrics_web.dart` 헤더에 "전부 비율/각도라
// scale-invariant" 라는 주석이 달려 있었다. 등방 확대에는 맞지만 비등방에는
// 틀린 문장이었고, 그래서 gonialAngle · chinAngle · eyeCanthalTilt ·
// mouthCornerAngle · eyeAspect · faceAspectRatio 6개가 오염된 채로 레퍼런스까지
// 잡혔다. 주석 대신 이 테스트가 그 성질을 지킨다.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:facely/domain/services/face_metrics.dart';

/// 픽셀 공간의 합성 얼굴 — 468점. 실제 얼굴 배치를 흉내낼 필요는 없고, 각
/// 랜드마크가 서로 다른 위치에 있고 축에 정렬돼 있지 않기만 하면 된다.
/// (축 정렬된 점만 있으면 비등방 왜곡이 드러나지 않는다.)
List<List<double>> _pixelFace() {
  final pts = <List<double>>[];
  for (var i = 0; i < 468; i++) {
    // 결정적 의사난수 — seed 없는 Random 을 쓰면 테스트가 흔들린다.
    final a = (i * 2654435761) % 1000 / 1000.0;
    final b = (i * 40503) % 997 / 997.0;
    // 얼굴이 들어갈 만한 중앙 영역에 흩뿌린다 (px 단위, 400×400 기준).
    pts.add([80.0 + a * 240.0, 40.0 + b * 320.0]);
  }
  return pts;
}

/// 픽셀 좌표를 `imgW × imgH` 사진의 MediaPipe 정규화 좌표로 바꾼다.
List<FaceMeshLandmark> _normalize(List<List<double>> px, int imgW, int imgH) => [
      for (final p in px)
        FaceMeshLandmark(x: p[0] / imgW, y: p[1] / imgH, z: 0.0),
    ];

void main() {
  // 같은 픽셀 얼굴을 세 가지 사진 규격에 담는다. 픽셀 위치는 동일하므로
  // 물리적으로 완전히 같은 얼굴이다 — metric 도 같아야 한다.
  final px = _pixelFace();

  final square = FaceMetrics(_normalize(px, 400, 400), aspect: 400 / 400);
  final portrait = FaceMetrics(_normalize(px, 400, 600), aspect: 600 / 400);
  final phone = FaceMetrics(_normalize(px, 1080, 1440), aspect: 1440 / 1080);

  test('사진 종횡비가 달라도 모든 metric 이 동일하다', () {
    final a = square.computeAll();
    final b = portrait.computeAll();
    final c = phone.computeAll();

    expect(a.keys.toSet(), b.keys.toSet());

    for (final key in a.keys) {
      expect(b[key], closeTo(a[key]!, 1e-9), reason: '$key — 400×600 에서 달라짐');
      expect(c[key], closeTo(a[key]!, 1e-9), reason: '$key — 1080×1440 에서 달라짐');
    }
  });

  test('보정을 끄면 각도·세로÷가로 metric 이 실제로 오염된다', () {
    // aspect 를 1.0 으로 고정 = 보정 이전 동작. 이 6개가 사진 규격에 따라
    // 달라지는 것이 결함 1의 실체다.
    final uncorrectedSquare = FaceMetrics(_normalize(px, 400, 400));
    final uncorrectedPortrait = FaceMetrics(_normalize(px, 400, 600));

    const polluted = [
      'faceAspectRatio',
      'gonialAngle',
      'chinAngle',
      'eyeCanthalTilt',
      'mouthCornerAngle',
      'eyeAspect',
    ];

    final a = uncorrectedSquare.computeAll();
    final b = uncorrectedPortrait.computeAll();

    for (final key in polluted) {
      expect((b[key]! - a[key]!).abs(), greaterThan(1e-6),
          reason: '$key — 보정 없이도 같게 나오면 이 테스트의 전제가 틀린 것');
    }
  });
}
