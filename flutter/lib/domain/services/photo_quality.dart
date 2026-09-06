/// 앨범 사진 품질 검사 (APPLE.md §60) — 순수 함수. 문제가 있으면 점수를 만들지
/// 않고 사용자 문구를 돌려준다. 흐림 판정은 보정 데이터가 없어 v1 에서 뺐다.
library;

import 'dart:typed_data';
import 'dart:ui';

/// 얼굴 상자의 짧은 변이 사진 짧은 변의 이 비율보다 작으면 "너무 작음".
/// picker 가 1024px 로 줄이므로 약 120px 아래를 거른다.
const double kMinFaceFraction = 0.12;

/// 얼굴 상자 평균 밝기(0~255)가 이보다 어두우면 "너무 어두움".
const double kMinFaceLuma = 40;

/// 얼굴 상자 안 평균 밝기 — RGBA 버퍼를 [stride] 픽셀 간격으로 표본.
double meanLumaInRect(
  Uint8List rgba,
  int imageW,
  int imageH,
  Rect r, {
  int stride = 4,
}) {
  final x0 = r.left.floor().clamp(0, imageW - 1);
  final y0 = r.top.floor().clamp(0, imageH - 1);
  final x1 = r.right.ceil().clamp(x0 + 1, imageW);
  final y1 = r.bottom.ceil().clamp(y0 + 1, imageH);
  var sum = 0.0;
  var n = 0;
  for (var y = y0; y < y1; y += stride) {
    for (var x = x0; x < x1; x += stride) {
      final i = (y * imageW + x) * 4;
      sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// null = 통과. 아니면 화면에 그대로 보여줄 문구.
String? photoQualityIssue({
  required Rect face,
  required int imageW,
  required int imageH,
  required double meanLuma,
}) {
  final shortSide = face.width < face.height ? face.width : face.height;
  final imageShort = imageW < imageH ? imageW : imageH;
  if (shortSide < kMinFaceFraction * imageShort) {
    return '얼굴이 너무 작게 나왔습니다.\n얼굴이 크게 보이는 사진을 선택해 주세요.';
  }
  if (meanLuma < kMinFaceLuma) {
    return '사진이 너무 어둡습니다.\n밝은 곳에서 찍은 사진을 선택해 주세요.';
  }
  return null;
}

/// 여러 얼굴 사진에서 고른 얼굴만 성별·연령 추정에 보내기 위한 자르기 영역 —
/// 상자를 [scale] 배로 키우고 사진 안으로 자른다.
Rect expandedCropRect(Rect face, int imageW, int imageH, {double scale = 1.6}) {
  final cx = face.center.dx;
  final cy = face.center.dy;
  final hw = face.width * scale / 2;
  final hh = face.height * scale / 2;
  return Rect.fromLTRB(
    (cx - hw).clamp(0.0, imageW.toDouble()),
    (cy - hh).clamp(0.0, imageH.toDouble()),
    (cx + hw).clamp(0.0, imageW.toDouble()),
    (cy + hh).clamp(0.0, imageH.toDouble()),
  );
}
