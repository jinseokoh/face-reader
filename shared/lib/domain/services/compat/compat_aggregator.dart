/// §8 aggregator — 4 sub-score → total + CompatLabel.
///
/// ```
/// rawTotal  = 0.20 * elementScore
///           + 0.40 * palaceScore
///           + 0.25 * qiScore
///           + 0.15 * intimacyScore
/// deviation = rawTotal - 50
/// spread    = clamp(50 + deviation * 1.4, 5, 99)       // 내부 분포 유지용
/// total     = _remapToUserScale(spread)                // 0~100 UI scale
/// ```
///
/// 1.4× multiplier 는 4 sub-score 가중 평균이 CLT 로 수축(표준편차 축소)
/// 하는 것을 상쇄해 §8.2 #1 total spread 를 확보한다.
///
/// `_remapToUserScale` 은 20k-pair MC (seed=42) 분포의 p30/p60/p90 anchor
/// (50.54 / 54.44 / 59.63) 를 한국 사용자 직관에 맞는 56/78/90 에 꽂는
/// piecewise-linear 단조 변환. rank 순서와 10/30/30/30 분포를 모두 보존하면서
/// "형극난조 50 미만 / 마합가성 56+ / 상경여빈 78+ / 천작지합 90+" 경계를
/// 리터럴로 성립시킨다.
library;

import 'compat_label.dart';

const double kElementWeight = 0.20;
const double kPalaceWeight = 0.40;
const double kQiWeight = 0.25;
const double kIntimacyWeight = 0.15;

/// §7.1 deviation 배율. sub-score 가중평균 spread 감쇠 상쇄.
const double kSpreadMultiplier = 1.4;

/// UI 표시용 piecewise-linear anchor — (spread 내부값, 사용자 화면 점수).
/// spread 는 `50 + deviation * 1.4` 의 [5, 99] clamp 결과.
/// MC p30/p60/p90 이 50.54/54.44/59.63 이라 → 56/78/90 에 정확히 꽂힌다.
const List<List<double>> _kUserScaleAnchors = [
  [5.0, 0.0],
  [50.54, 56.0],
  [54.44, 78.0],
  [59.63, 90.0],
  [99.0, 100.0],
];

double _remapToUserScale(double spread) {
  if (spread <= _kUserScaleAnchors.first[0]) return _kUserScaleAnchors.first[1];
  if (spread >= _kUserScaleAnchors.last[0]) return _kUserScaleAnchors.last[1];
  for (int i = 1; i < _kUserScaleAnchors.length; i++) {
    final x1 = _kUserScaleAnchors[i - 1][0];
    final x2 = _kUserScaleAnchors[i][0];
    if (spread <= x2) {
      final y1 = _kUserScaleAnchors[i - 1][1];
      final y2 = _kUserScaleAnchors[i][1];
      final frac = (spread - x1) / (x2 - x1);
      return y1 + frac * (y2 - y1);
    }
  }
  return _kUserScaleAnchors.last[1];
}

class CompatSubScores {
  final double elementScore;
  final double palaceScore;
  final double qiScore;
  final double intimacyScore;

  const CompatSubScores({
    required this.elementScore,
    required this.palaceScore,
    required this.qiScore,
    required this.intimacyScore,
  });
}

class CompatAggregate {
  /// 가중 합 (spread 배율 전).
  final double rawTotal;

  /// 0~100 최종 점수 (UI scale, piecewise-linear remap 적용).
  final double total;
  final CompatLabel label;

  const CompatAggregate({
    required this.rawTotal,
    required this.total,
    required this.label,
  });
}

CompatAggregate aggregateCompat({
  required CompatSubScores sub,
  CompatLabelThresholds thresholds = kCompatLabelThresholds,
}) {
  final raw = kElementWeight * sub.elementScore +
      kPalaceWeight * sub.palaceScore +
      kQiWeight * sub.qiScore +
      kIntimacyWeight * sub.intimacyScore;
  final deviation = raw - 50.0;
  final spread = (50.0 + deviation * kSpreadMultiplier).clamp(5.0, 99.0);
  final total = _remapToUserScale(spread);
  final label = classifyLabel(total, thresholds: thresholds);
  return CompatAggregate(rawTotal: raw, total: total, label: label);
}
