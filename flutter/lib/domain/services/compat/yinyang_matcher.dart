/// 陰陽 剛柔 pair matcher — §6.
///
/// 기존 `YinYangBalance` 재활용. pair rule:
/// - yang_strong × yin_strong → +18 (古典 理想)
/// - 둘 다 yang_strong → -12
/// - 둘 다 yin_strong → -8
/// - 중앙 × 중앙 → +2
/// - 한 쪽 중앙, 다른 쪽 기울 → +6
/// - 성별 정합 (남陽 / 여陰 기대) 어긋남 → -4 (낙인 아닌 현대적 교차)
library;

import '../../../data/enums/gender.dart';
import '../yin_yang.dart';

enum YinYangPatternKind {
  yangYinIdeal, // 陽 × 陰
  yangYang,
  yinYin,
  balancedBoth,
  oneBalanced,
  modernCross, // 성별 기대 역전
}

class YinYangMatch {
  /// -14 ~ +20 range. qi sub-score 에 주입.
  final double delta;
  final YinYangPatternKind kind;
  final String verdict;
  final YinYangBalance my;
  final YinYangBalance album;

  const YinYangMatch({
    required this.delta,
    required this.kind,
    required this.verdict,
    required this.my,
    required this.album,
  });
}

const double _strongGate = 0.6;
const double _balancedGate = 0.2;

YinYangMatch matchYinYang({
  required YinYangBalance my,
  required YinYangBalance album,
  required Gender myGender,
  required Gender albumGender,
}) {
  final myYang = my.skew >= _strongGate;
  final myYin = my.skew <= -_strongGate;
  final myBal = my.skew.abs() < _balancedGate;
  final aYang = album.skew >= _strongGate;
  final aYin = album.skew <= -_strongGate;
  final aBal = album.skew.abs() < _balancedGate;

  double delta;
  YinYangPatternKind kind;
  String verdict;

  if ((myYang && aYin) || (myYin && aYang)) {
    delta = 18;
    kind = YinYangPatternKind.yangYinIdeal;
    verdict = '剛柔相濟 — 강한 양과 부드러운 음이 만난 고전적 이상형.';
  } else if (myYang && aYang) {
    delta = -12;
    kind = YinYangPatternKind.yangYang;
    verdict = '雙陽相抗 — 둘 다 강한 기세라 충돌이 잦을 수 있습니다.';
  } else if (myYin && aYin) {
    delta = -8;
    kind = YinYangPatternKind.yinYin;
    verdict = '雙陰相依 — 서로 기대는 힘은 좋으나 추진력이 느슨해집니다.';
  } else if (myBal && aBal) {
    delta = 2;
    kind = YinYangPatternKind.balancedBoth;
    verdict = '中和雙臨 — 두 사람 모두 음양 중용, 잔잔한 조화.';
  } else {
    delta = 2;
    kind = YinYangPatternKind.oneBalanced;
    verdict = '一中一偏 — 한 쪽 중용이 다른 쪽의 기운을 살짝 고릅니다.';
  }

  // 성별 기대 어긋남 overlay (남陰 · 여陽 조합). modern cross — 낙인 아닌 서술.
  final myExpectedYin = myGender == Gender.female;
  final albumExpectedYin = albumGender == Gender.female;
  final myReversed = (myExpectedYin && myYang) || (!myExpectedYin && myYin);
  final albumReversed =
      (albumExpectedYin && aYang) || (!albumExpectedYin && aYin);
  if (myReversed && albumReversed) {
    delta -= 4;
    kind = YinYangPatternKind.modernCross;
    verdict = '陰陽倒置 — 전통 기대와 역전된 조합, 역할을 현대적으로 재정의하게 됩니다.';
  }

  return YinYangMatch(
    delta: delta,
    kind: kind,
    verdict: verdict,
    my: my,
    album: album,
  );
}
