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

import 'package:face_engine/data/enums/gender.dart';
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
    verdict = '한 분은 앞장서 밀고 나가고 다른 분은 한발 물러나 받쳐 주는 구도라, 서로 부딪힐 일이 적은 안정된 짝입니다.';
  } else if (myYang && aYang) {
    delta = -12;
    kind = YinYangPatternKind.yangYang;
    verdict = '두 분 다 앞장서 밀고 나가는 성향이라, 같은 자리를 놓고 부딪히는 일이 잦을 수 있습니다.';
  } else if (myYin && aYin) {
    delta = -8;
    kind = YinYangPatternKind.yinYin;
    verdict = '두 분 다 한발 물러나 받아 주는 성향이라 서로 편하게 기대지만, 먼저 나서는 사람이 없어 결정이 자꾸 미뤄집니다.';
  } else if (myBal && aBal) {
    delta = 2;
    kind = YinYangPatternKind.balancedBoth;
    verdict = '두 분 다 밀고 받는 힘이 한쪽으로 치우치지 않아, 큰 마찰 없이 잔잔하게 흘러갑니다.';
  } else {
    delta = 2;
    kind = YinYangPatternKind.oneBalanced;
    verdict = '한 분은 균형이 잡혀 있고 다른 분은 한쪽으로 살짝 치우친 구도라, 중심 잡힌 쪽이 완충 역할을 합니다.';
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
    verdict = '전통적인 성별 기대와 음양이 반대로 맞물린 구도라, 역할 분담을 두 분이 직접 현대적으로 다시 정의하게 됩니다.';
  }

  return YinYangMatch(
    delta: delta,
    kind: kind,
    verdict: verdict,
    my: my,
    album: album,
  );
}
