/// 十二宮 pair matcher — 두 `Map<Palace, PalaceState>` → `PalacePairResult`.
///
/// §3.4 공식:
/// ```
/// for each palace p:
///   matched = rules[p].where((r) => r.matcher(my[p], album[p]))
///   palaceDelta[p] = clamp(Σ r.delta, -25, 25)
/// palaceTotal = 50 + Σ palaceDelta[p] * marriageWeight[p]
/// subScore = clamp(palaceTotal, 5, 99)
/// ```
///
/// rule matcher 가 상호 배타이므로 궁당 한 rule 만 fire 하지만, cap 은 혹시
/// 모를 중복 fire 에 대한 방어.
library;

import 'palace.dart';
import 'palace_rules.dart';

const double _baseline = 50.0;
const double _ruleCap = 25.0;

PalacePairResult palacePairScore({
  required Map<Palace, PalaceState> my,
  required Map<Palace, PalaceState> album,
}) {
  final evidence = <PalacePairEvidence>[];
  double weightedTotal = _baseline;

  for (final p in Palace.values) {
    final ms = my[p];
    final as = album[p];
    if (ms == null || as == null) continue;

    double palaceDelta = 0.0;
    for (final rule in palaceRules) {
      if (rule.palace != p) continue;
      if (rule.matcher(ms, as)) {
        palaceDelta += rule.delta;
        evidence.add(PalacePairEvidence(
          ruleId: rule.id,
          palace: p,
          delta: rule.delta,
          verdict: rule.verdict,
        ));
      }
    }

    final capped = palaceDelta.clamp(-_ruleCap, _ruleCap);
    final w = palaceMarriageWeight[p] ?? 0.0;
    weightedTotal += capped * w;
  }

  final sub = weightedTotal.clamp(5.0, 99.0);
  return PalacePairResult(subScore: sub, evidence: evidence);
}
