/// PP (Palace-Pair) rule catalog — 두 사람 같은 궁의 state + flag 조합 → delta.
///
/// §3.3 의 catalog. 각 궁마다 strong/strong, strong/weak, weak/weak 의
/// 세 축을 커버하고 flag 조합 분화를 추가해 단조 flat 을 피한다.
/// 모든 rule 의 |delta| ≤ 25 로 §3.4 cap 에 맞춤.
///
/// 동일 (palace, pair-state) 에서 여러 rule 이 동시에 fire 하지 않도록
/// matcher 조건이 상호 배타 — narrative 에 같은 궁 comment 가 겹치지 않게.
library;

import 'palace.dart';

/// 발동 함수. 두 PalaceState 를 받아 match 여부 반환.
typedef PalaceMatcher = bool Function(PalaceState my, PalaceState album);

class PalaceRule {
  final String id;
  final Palace palace;
  final PalaceMatcher matcher;
  final double delta;
  final String verdict;

  const PalaceRule({
    required this.id,
    required this.palace,
    required this.matcher,
    required this.delta,
    required this.verdict,
  });
}

// ────────── matcher helpers ──────────

bool _bothStrong(PalaceState a, PalaceState b) => a.isStrong && b.isStrong;
bool _bothWeak(PalaceState a, PalaceState b) => a.isWeak && b.isWeak;
bool _oneStrongOneWeak(PalaceState a, PalaceState b) =>
    (a.isStrong && b.isWeak) || (a.isWeak && b.isStrong);
bool _bothHaveFlag(PalaceState a, PalaceState b, PalaceFlag f) =>
    a.hasFlag(f) && b.hasFlag(f);
bool _eitherHasFlag(PalaceState a, PalaceState b, PalaceFlag f) =>
    a.hasFlag(f) || b.hasFlag(f);

// ────────── rule catalog ──────────

/// 전체 PP rule. 순서는 가독성 위주 (palace 묶음). matcher 상호 배타.
const List<PalaceRule> palaceRules = [
  // ──── 妻妾宮 (spouse) — 최핵심 weight 0.28 ─────────────────────────
  PalaceRule(
    id: 'PP-SP-STRONG-SMOOTH',
    palace: Palace.spouse,
    matcher: _ppSpStrongSmooth,
    delta: 24,
    verdict: '두 분 모두 부부궁(妻妾宮)이 맑고 환해 결혼 생활이 오래도록 반짝입니다. 고전에서는 눈꼬리 옆이 주름 없이 매끈한 자리를 서로를 귀히 여기는 금슬의 상으로 봅니다.',
  ),
  PalaceRule(
    id: 'PP-SP-STRONG-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpStrongNoflag,
    delta: 20,
    verdict: '부부궁이 양쪽 다 단단하게 섰습니다. 결혼이 두 분 인생의 중심축으로 자리잡기 쉬운 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-SP-CROSS',
    palace: Palace.spouse,
    matcher: _ppSpCross,
    delta: 8,
    verdict: '한 분의 부부궁은 단단하고 다른 분은 여린 편입니다. 강한 쪽이 약한 쪽을 품어 주면 관계가 오히려 차분히 자리잡습니다.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-WRINKLE',
    palace: Palace.spouse,
    matcher: _ppSpWeakWrinkle,
    delta: -25,
    verdict: '두 분 모두 부부궁이 여린 데다 눈꼬리 잔주름(어미문)이 겹쳐 있어 부부의 정이 쉽게 흔들리는 조합입니다. 서로의 감정을 자주 환기해 주는 습관이 필요합니다.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpWeakNoflag,
    delta: -20,
    verdict: '부부궁이 양쪽 모두 식어 있는 편입니다. 따뜻한 말 한 마디가 평소보다 더 중요한 관계입니다.',
  ),

  // ──── 男女宮 (children) — weight 0.22 ─────────────────────────────
  PalaceRule(
    id: 'PP-CH-STRONG-PLUMP',
    palace: Palace.children,
    matcher: _ppChStrongPlump,
    delta: 22,
    verdict: '두 분 모두 남녀궁(男女宮, 눈 아래 와잠)이 통통히 살아 있어 자녀나 가까운 사람에게 쏟는 정이 서로 겹칩니다. 전통 관상학은 이 자리를 혈육의 경사가 기대되는 상으로 봅니다.',
  ),
  PalaceRule(
    id: 'PP-CH-STRONG-NOFLAG',
    palace: Palace.children,
    matcher: _ppChStrongNoflag,
    delta: 16,
    verdict: '남녀궁이 양쪽 다 풍성해 자녀·친밀함에 대한 기대가 함께 높은 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-CH-CROSS',
    palace: Palace.children,
    matcher: _ppChCross,
    delta: 6,
    verdict: '남녀궁 한 쪽은 풍성하고 다른 쪽은 얇습니다. 다정한 쪽이 먼저 내미는 손이 관계의 결핍을 채워 주는 모양입니다.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-HOLLOW',
    palace: Palace.children,
    matcher: _ppChWeakHollow,
    delta: -22,
    verdict: '두 분 모두 와잠이 얇거나 꺼진 상입니다. 가정의 따뜻함이 자연스레 우러나오기 어려워 의식적으로 정을 쌓아야 합니다.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-NOFLAG',
    palace: Palace.children,
    matcher: _ppChWeakNoflag,
    delta: -16,
    verdict: '남녀궁이 양쪽 다 조용해 자녀나 후배와의 인연이 늦게 풀리는 경향의 조합입니다.',
  ),

  // ──── 命宮 (life) — weight 0.15 ───────────────────────────────────
  PalaceRule(
    id: 'PP-LF-BRIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfBrightBoth,
    delta: 20,
    verdict: '두 분 모두 명궁(命宮, 미간)이 넓고 밝습니다. 서로의 생각이 쉽게 통해 일상의 대화에도 빛이 돕니다.',
  ),
  PalaceRule(
    id: 'PP-LF-STRONG-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfStrongNoflag,
    delta: 14,
    verdict: '명궁이 양쪽 다 든든해 삶의 고비에서 서로를 일으켜 줄 수 있는 기개가 나란히 섰습니다.',
  ),
  PalaceRule(
    id: 'PP-LF-CROSS',
    palace: Palace.life,
    matcher: _ppLfCross,
    delta: -8,
    verdict: '한 분의 기개는 강하고 다른 분은 여린 편입니다. 결단의 속도가 달라 중요한 선택 앞에서 호흡이 어긋날 수 있습니다.',
  ),
  PalaceRule(
    id: 'PP-LF-TIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfTightBoth,
    delta: -22,
    verdict: '두 분 모두 미간이 좁고 어두운 편입니다. 속을 꽉 묶는 성향이 겹쳐 답답함이 서로에게 증폭되기 쉽습니다.',
  ),
  PalaceRule(
    id: 'PP-LF-WEAK-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfWeakNoflag,
    delta: -14,
    verdict: '명궁이 양쪽 다 흐려 결단의 실이 쉽게 끊어집니다. 작은 결정부터 같이 짚어 가는 습관이 관계를 단단히 합니다.',
  ),

  // ──── 田宅宮 (property) — weight 0.13 ─────────────────────────────
  PalaceRule(
    id: 'PP-TH-STRONG',
    palace: Palace.property,
    matcher: _bothStrong,
    delta: 14,
    verdict: '두 분의 전택궁(田宅宮, 눈과 눈썹 사이)이 모두 두텁습니다. 함께 만드는 살림이 관계의 밑바탕이 되어 줄 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-TH-CROSS',
    palace: Palace.property,
    matcher: _oneStrongOneWeak,
    delta: 4,
    verdict: '전택궁에서 한 쪽은 터가 두텁고 다른 쪽은 얇습니다. 서로 다른 기반이 하나의 집을 채우는 방식이 관계의 색깔이 됩니다.',
  ),
  PalaceRule(
    id: 'PP-TH-WEAK',
    palace: Palace.property,
    matcher: _bothWeak,
    delta: -14,
    verdict: '전택궁이 양쪽 다 얇아 거처가 불안정하면 관계도 흔들리기 쉬운 조합입니다. 생활 기반을 먼저 다지는 노력이 필요합니다.',
  ),

  // ──── 福德宮 (fortune) — weight 0.12 ──────────────────────────────
  PalaceRule(
    id: 'PP-FT-CLOUDLESS',
    palace: Palace.fortune,
    matcher: _ppFtCloudless,
    delta: 18,
    verdict: '두 분 모두 복덕궁(福德宮, 이마 위 좌우)이 밝게 트여 있습니다. 복과 여유가 나란히 흘러 풍요로운 분위기를 만들기 쉬운 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-FT-STRONG-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtStrongNoflag,
    delta: 12,
    verdict: '복덕궁이 양쪽 다 든든해 가치관의 폭이 비슷합니다. 삶의 여유를 같이 즐길 수 있는 관계입니다.',
  ),
  PalaceRule(
    id: 'PP-FT-DENTED',
    palace: Palace.fortune,
    matcher: _ppFtDented,
    delta: -18,
    verdict: '두 분 모두 이마 위 좌우가 꺼진 편으로 복덕궁이 엷습니다. 사소한 일에도 여유가 빠르게 닳을 수 있어 일상에 숨구멍을 의도적으로 만들어야 합니다.',
  ),
  PalaceRule(
    id: 'PP-FT-WEAK-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtWeakNoflag,
    delta: -12,
    verdict: '복덕궁이 양쪽 다 얇은 조합입니다. 지금 누리는 것을 소중히 여기는 자세와 저축 습관이 관계에 큰 도움이 됩니다.',
  ),

  // ──── 財帛宮 (wealth) — weight 0.05 ───────────────────────────────
  PalaceRule(
    id: 'PP-WE-BULB-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeBulbBoth,
    delta: 10,
    verdict: '두 분 모두 코끝이 복스럽게 솟아 재백궁(財帛宮)의 축이 나란히 섭니다. 경제 파트너십에 유리한 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-WE-HOOK-CLASH',
    palace: Palace.wealth,
    matcher: _ppWeHookClash,
    delta: -8,
    verdict: '두 분 모두 매부리코 기운이 있어 재물 감각은 날카롭지만, 이득 계산이 사사건건 부딪힐 가능성이 큽니다.',
  ),
  PalaceRule(
    id: 'PP-WE-STRONG-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeStrongNoflag,
    delta: 5,
    verdict: '재백궁이 양쪽 다 탄탄합니다. 돈의 흐름을 놓치지 않는 감각이 함께 살아 있는 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-WE-THIN-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeThinBoth,
    delta: -6,
    verdict: '두 분 모두 콧대가 가늘고 날카롭습니다. 계산적 강박이 겹쳐 작은 돈 문제로 날 서게 다투기 쉽습니다.',
  ),
  PalaceRule(
    id: 'PP-WE-WEAK-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeWeakNoflag,
    delta: -4,
    verdict: '재백궁이 양쪽 모두 느슨한 편입니다. 기분에 휩쓸린 지출을 경계하는 습관이 관계를 지켜 줍니다.',
  ),

  // ──── 疾厄宮 (illness) — weight 0.01 ──────────────────────────────
  PalaceRule(
    id: 'PP-IL-SANGEN-LOW',
    palace: Palace.illness,
    matcher: _ppIlSangenLow,
    delta: -8,
    verdict: '두 분 모두 콧대 뿌리(산근)가 꺼진 편으로 질액궁(疾厄宮)이 약합니다. 중년 이후 건강 고비에 서로의 관심이 필요합니다.',
  ),
  PalaceRule(
    id: 'PP-IL-SANGEN-HIGH',
    palace: Palace.illness,
    matcher: _ppIlSangenHigh,
    delta: 6,
    verdict: '콧대 뿌리가 양쪽 다 높게 섰습니다. 체력 기반이 나란히 탄탄해 나이 든 후에도 함께 활동하기 좋은 조합입니다.',
  ),

  // ──── 官祿宮 (career) — weight 0.003 ──────────────────────────────
  PalaceRule(
    id: 'PP-CR-STRONG',
    palace: Palace.career,
    matcher: _bothStrong,
    delta: 6,
    verdict: '관록궁(官祿宮, 이마 한가운데)이 양쪽 다 단단합니다. 사회적 보폭이 비슷해 서로의 성취에 자부심을 느낄 수 있는 관계입니다.',
  ),
  PalaceRule(
    id: 'PP-CR-CROSS',
    palace: Palace.career,
    matcher: _oneStrongOneWeak,
    delta: -4,
    verdict: '관록궁의 높낮이가 엇갈려 사회적 위치 차이에서 자존심이 부딪힐 여지가 있습니다.',
  ),
  PalaceRule(
    id: 'PP-CR-WEAK',
    palace: Palace.career,
    matcher: _bothWeak,
    delta: -2,
    verdict: '두 분 모두 관록궁이 조용합니다. 외적 성취보다 조용한 일상을 함께 즐기는 조합입니다.',
  ),

  // ──── 奴僕宮 (slave) — weight 0.03 ────────────────────────────────
  PalaceRule(
    id: 'PP-SV-STRONG',
    palace: Palace.slave,
    matcher: _bothStrong,
    delta: 3,
    verdict: '두 분 모두 턱 양옆이 두터워 노복궁(奴僕宮)이 단단합니다. 인맥과 주변의 도움이 함께 풍성한 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-SV-WEAK',
    palace: Palace.slave,
    matcher: _bothWeak,
    delta: -3,
    verdict: '노복궁이 양쪽 다 얇아 외부 조력이 제한적인 조합입니다. 두 분이 모든 일을 직접 떠맡는 경향을 주의해야 합니다.',
  ),

  // ──── 兄弟宮 (sibling) — weight 0.003 ─────────────────────────────
  PalaceRule(
    id: 'PP-BR-STRONG',
    palace: Palace.sibling,
    matcher: _bothStrong,
    delta: 3,
    verdict: '형제궁(兄弟宮, 눈썹)이 양쪽 다 맑습니다. 주변 친우와 형제의 지원이 함께 밝은 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-BR-CROSS',
    palace: Palace.sibling,
    matcher: _oneStrongOneWeak,
    delta: -2,
    verdict: '형제궁의 결이 한 쪽만 선명합니다. 주변 관계의 온도 차가 미묘하게 드러날 수 있습니다.',
  ),

  // ──── 遷移宮 (migration) — weight 0.002 ───────────────────────────
  PalaceRule(
    id: 'PP-MV-STRONG',
    palace: Palace.migration,
    matcher: _bothStrong,
    delta: 2,
    verdict: '천이궁(遷移宮, 관자놀이)이 양쪽 다 활발합니다. 새 환경으로 함께 움직이는 흐름이 잘 맞는 조합입니다.',
  ),

  // ──── 父母宮 (parents) — weight 0.002 ─────────────────────────────
  PalaceRule(
    id: 'PP-PR-STRONG',
    palace: Palace.parents,
    matcher: _bothStrong,
    delta: 3,
    verdict: '부모궁(父母宮, 이마 윗부분)이 양쪽 다 밝습니다. 양가 부모 복이 나란히 이어질 가능성이 높은 조합입니다.',
  ),
];

// ────────── top-level matchers (const 로 참조 가능) ──────────
//
// Dart const constructor 가 instance-method 참조를 허용하지 않으므로 모든
// matcher 는 top-level 함수로 분리. palaceRules 상수 리스트가 참조 가능.

bool _ppSpStrongSmooth(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.smoothFishTail);
bool _ppSpStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.smoothFishTail);
bool _ppSpCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);
bool _ppSpWeakWrinkle(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.fishTailWrinkle);
bool _ppSpWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.fishTailWrinkle);

bool _ppChStrongPlump(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.plumpLowerEyelid);
bool _ppChStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.plumpLowerEyelid);
bool _ppChCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);
bool _ppChWeakHollow(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.hollowLowerEyelid);
bool _ppChWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.hollowLowerEyelid);

bool _ppLfBrightBoth(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.glabellaBright);
bool _ppLfStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.glabellaBright);
bool _ppLfCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);
bool _ppLfTightBoth(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.glabellaTight);
bool _ppLfWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.glabellaTight);

bool _ppFtCloudless(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.cloudlessForehead);
bool _ppFtStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.cloudlessForehead);
bool _ppFtDented(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.dentedTemple);
bool _ppFtWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.dentedTemple);

bool _ppWeBulbBoth(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) &&
    _bothHaveFlag(a, b, PalaceFlag.bulbousTip) &&
    !_eitherHasFlag(a, b, PalaceFlag.hookedNose);
bool _ppWeHookClash(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.hookedNose);
bool _ppWeStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) &&
    !_bothHaveFlag(a, b, PalaceFlag.bulbousTip) &&
    !_bothHaveFlag(a, b, PalaceFlag.hookedNose);
bool _ppWeThinBoth(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _bothHaveFlag(a, b, PalaceFlag.thinBridge);
bool _ppWeWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_bothHaveFlag(a, b, PalaceFlag.thinBridge);

bool _ppIlSangenLow(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.sanGenLow);
bool _ppIlSangenHigh(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _eitherHasFlag(a, b, PalaceFlag.sanGenHigh);
