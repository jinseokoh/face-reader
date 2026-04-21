/// §8 aggregator — 4 sub-score → total + CompatLabel.
///
/// ```
/// rawTotal = 0.20 * elementScore
///          + 0.40 * palaceScore
///          + 0.25 * qiScore
///          + 0.15 * intimacyScore
/// deviation = rawTotal - 50
/// total = clamp(50 + deviation * 1.4, 5, 99)
/// ```
///
/// 1.4× multiplier 는 4 sub-score 가중 평균이 CLT 로 수축(표준편차 축소)
/// 하는 것을 상쇄해 §8.2 #1 total spread 를 확보한다.
library;

import 'compat_label.dart';

const double kElementWeight = 0.20;
const double kPalaceWeight = 0.40;
const double kQiWeight = 0.25;
const double kIntimacyWeight = 0.15;

/// §7.1 deviation 배율. sub-score 가중평균 spread 감쇠 상쇄.
const double kSpreadMultiplier = 1.4;

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

  /// 5~99 최종 점수.
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
  final total = (50.0 + deviation * kSpreadMultiplier).clamp(5.0, 99.0);
  final label = classifyLabel(total, thresholds: thresholds);
  return CompatAggregate(rawTotal: raw, total: total, label: label);
}
