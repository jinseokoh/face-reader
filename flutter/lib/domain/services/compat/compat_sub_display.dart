/// sub-score UI scale — element/palace/qi/intimacy 를 각자의 MC p30/p60/p90
/// (20k pair seed=42, `compat_calibration_test.dart` 출력) 에 맞춰
/// piecewise-linear 로 0~100 에 꽂는 **display-only** remap.
///
/// 총점과 같은 "상위 10%=90 / 40%=78 / 70%=56" 문법을 sub 에도 적용해
/// 시각적 parity 확보. 내부 가중합 계산은 raw 값 그대로 돌아가므로 aggregator
/// 와 총점 calibration 은 무변.
///
/// 친밀(intimacy) 은 gate off 시 raw 50 에 대량 점결되어 percentile remap 이
/// degenerate — gate on 인 경우만 자체 anchor (n=5,591, gate-on 분포 기준)
/// 로 remap, gate off 는 null 반환 → UI 에서 "—" 표시.
library;

enum CompatSubKind { element, palace, qi, intimacy }

/// raw sub-score → 0~100 display.
/// [gateOff] 은 intimacy 에서만 의미 있음 — true 면 null 반환 (UI "—").
double? subScoreToDisplay(
  CompatSubKind kind,
  double raw, {
  bool gateOff = false,
}) {
  if (kind == CompatSubKind.intimacy && gateOff) return null;
  return _piecewise(raw, _anchors[kind]!);
}

/// 20k MC 측정값 (seed=42). `compat_calibration_test.dart` 의 sub-score 섹션
/// 출력을 직접 복사. 갱신 시 두 곳 모두 손대야 함.
const Map<CompatSubKind, List<List<double>>> _anchors = {
  CompatSubKind.element: [
    [5.0, 0.0],
    [35.62, 56.0],
    [49.50, 78.0],
    [60.17, 90.0],
    [99.0, 100.0],
  ],
  CompatSubKind.palace: [
    [5.0, 0.0],
    [52.18, 56.0],
    [55.64, 78.0],
    [60.95, 90.0],
    [99.0, 100.0],
  ],
  CompatSubKind.qi: [
    [5.0, 0.0],
    [53.20, 56.0],
    [55.83, 78.0],
    [59.88, 90.0],
    [99.0, 100.0],
  ],
  CompatSubKind.intimacy: [
    [5.0, 0.0],
    [54.0, 56.0],
    [60.0, 78.0],
    [69.0, 90.0],
    [99.0, 100.0],
  ],
};

double _piecewise(double x, List<List<double>> anchors) {
  if (x <= anchors.first[0]) return anchors.first[1];
  if (x >= anchors.last[0]) return anchors.last[1];
  for (int i = 1; i < anchors.length; i++) {
    final x1 = anchors[i - 1][0];
    final x2 = anchors[i][0];
    if (x <= x2) {
      final y1 = anchors[i - 1][1];
      final y2 = anchors[i][1];
      final frac = (x - x1) / (x2 - x1);
      return y1 + frac * (y2 - y1);
    }
  }
  return anchors.last[1];
}
