/// 氣質合 (qi) sub-score — §7.
///
/// L3a organ pair + L3b zone harmony + L3c yinyang 세 sub-frame 을 가중합.
/// ```
/// qi = 50 + 0.55 * (organDelta)
///         + 0.25 * zoneDelta
///         + 0.20 * yinYangDelta
/// // clamp 5~99
/// // organDelta = organSubScore - 50 (조직 가중 평균이 baseline 50 중심)
/// ```
library;

import 'organ_pair_rules.dart';
import 'yinyang_matcher.dart';
import 'zone_harmony.dart';

class QiScoreResult {
  final double subScore;
  final double organDelta;
  final double zoneDelta;
  final double yinYangDelta;

  const QiScoreResult({
    required this.subScore,
    required this.organDelta,
    required this.zoneDelta,
    required this.yinYangDelta,
  });
}

QiScoreResult computeQiScore({
  required OrganPairResult organ,
  required ZoneHarmony zone,
  required YinYangMatch yinYang,
}) {
  final organDelta = organ.subScore - 50.0;
  final total = 50.0 +
      0.55 * organDelta +
      0.25 * zone.delta +
      0.20 * yinYang.delta;
  final sub = total.clamp(5.0, 99.0);
  return QiScoreResult(
    subScore: sub,
    organDelta: organDelta,
    zoneDelta: zone.delta,
    yinYangDelta: yinYang.delta,
  );
}
