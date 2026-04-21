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
    verdict: '魚尾清潤 — 부부궁이 거울처럼 밝아 금슬이 종신토록 빛납니다.',
  ),
  PalaceRule(
    id: 'PP-SP-STRONG-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpStrongNoflag,
    delta: 20,
    verdict: '妻妾雙旺 — 부부궁이 함께 단단해 결혼의 축이 굳게 섭니다.',
  ),
  PalaceRule(
    id: 'PP-SP-CROSS',
    palace: Palace.spouse,
    matcher: _ppSpCross,
    delta: 8,
    verdict: '一強一柔 — 강한 쪽이 약한 쪽을 품어 균형을 찾는 결혼.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-WRINKLE',
    palace: Palace.spouse,
    matcher: _ppSpWeakWrinkle,
    delta: -25,
    verdict: '魚尾紋交 — 눈꼬리 잔주름이 서로를 스쳐 부부의 정이 스칩니다.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpWeakNoflag,
    delta: -20,
    verdict: '妻妾俱寒 — 부부궁이 모두 차가워 따뜻한 말 한 마디가 귀해집니다.',
  ),

  // ──── 男女宮 (children) — weight 0.22 ─────────────────────────────
  PalaceRule(
    id: 'PP-CH-STRONG-PLUMP',
    palace: Palace.children,
    matcher: _ppChStrongPlump,
    delta: 22,
    verdict: '淚堂飽滿 — 자녀운이 겹쳐 혈육의 경사가 기대됩니다.',
  ),
  PalaceRule(
    id: 'PP-CH-STRONG-NOFLAG',
    palace: Palace.children,
    matcher: _ppChStrongNoflag,
    delta: 16,
    verdict: '子女宮和 — 자녀에 대한 기대와 여력이 함께 풍성합니다.',
  ),
  PalaceRule(
    id: 'PP-CH-CROSS',
    palace: Palace.children,
    matcher: _ppChCross,
    delta: 6,
    verdict: '子宮互補 — 한 쪽의 다정함이 다른 쪽의 결핍을 메웁니다.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-HOLLOW',
    palace: Palace.children,
    matcher: _ppChWeakHollow,
    delta: -22,
    verdict: '淚堂皆陷 — 가정의 따뜻함이 엷어 자녀·친밀의 인연이 박합니다.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-NOFLAG',
    palace: Palace.children,
    matcher: _ppChWeakNoflag,
    delta: -16,
    verdict: '子女宮寒 — 자녀나 후배 인연이 늦게 풀리는 조합.',
  ),

  // ──── 命宮 (life) — weight 0.15 ───────────────────────────────────
  PalaceRule(
    id: 'PP-LF-BRIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfBrightBoth,
    delta: 20,
    verdict: '印堂雙明 — 사상이 통해 일상의 대화에서도 빛이 납니다.',
  ),
  PalaceRule(
    id: 'PP-LF-STRONG-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfStrongNoflag,
    delta: 14,
    verdict: '命宮雙旺 — 기개가 나란해 고비마다 서로를 일으킵니다.',
  ),
  PalaceRule(
    id: 'PP-LF-CROSS',
    palace: Palace.life,
    matcher: _ppLfCross,
    delta: -8,
    verdict: '命宮高低 — 기개의 차이가 크면 결단의 속도도 달라집니다.',
  ),
  PalaceRule(
    id: 'PP-LF-TIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfTightBoth,
    delta: -22,
    verdict: '印堂雙結 — 두 사람 모두 속을 꽉 묶어 답답함이 증폭됩니다.',
  ),
  PalaceRule(
    id: 'PP-LF-WEAK-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfWeakNoflag,
    delta: -14,
    verdict: '命宮雙虛 — 기개가 함께 흐려 결단의 실이 잘 끊어집니다.',
  ),

  // ──── 田宅宮 (property) — weight 0.13 ─────────────────────────────
  PalaceRule(
    id: 'PP-TH-STRONG',
    palace: Palace.property,
    matcher: _bothStrong,
    delta: 14,
    verdict: '田宅厚潤 — 사는 공간이 두 사람의 바탕이 됩니다.',
  ),
  PalaceRule(
    id: 'PP-TH-CROSS',
    palace: Palace.property,
    matcher: _oneStrongOneWeak,
    delta: 4,
    verdict: '田宅互助 — 기반이 다른 둘이 집의 그릇을 나눠 채웁니다.',
  ),
  PalaceRule(
    id: 'PP-TH-WEAK',
    palace: Palace.property,
    matcher: _bothWeak,
    delta: -14,
    verdict: '田宅雙薄 — 거처가 함께 얇아 외부 변동에 흔들리기 쉽습니다.',
  ),

  // ──── 福德宮 (fortune) — weight 0.12 ──────────────────────────────
  PalaceRule(
    id: 'PP-FT-CLOUDLESS',
    palace: Palace.fortune,
    matcher: _ppFtCloudless,
    delta: 18,
    verdict: '天倉雙開 — 복과 덕이 나란히 흘러 풍요로운 공간을 만듭니다.',
  ),
  PalaceRule(
    id: 'PP-FT-STRONG-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtStrongNoflag,
    delta: 12,
    verdict: '福德雙全 — 가치관의 폭이 비슷해 삶의 여유를 공유합니다.',
  ),
  PalaceRule(
    id: 'PP-FT-DENTED',
    palace: Palace.fortune,
    matcher: _ppFtDented,
    delta: -18,
    verdict: '天倉俱陷 — 가정의 여유가 메말라 사소한 일이 크게 닳습니다.',
  ),
  PalaceRule(
    id: 'PP-FT-WEAK-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtWeakNoflag,
    delta: -12,
    verdict: '福德雙薄 — 두 사람 모두 복근이 얇아 저축의 습관이 중요합니다.',
  ),

  // ──── 財帛宮 (wealth) — weight 0.05 ───────────────────────────────
  PalaceRule(
    id: 'PP-WE-BULB-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeBulbBoth,
    delta: 10,
    verdict: '準頭齊豊 — 재운의 축이 나란히 서 경제 파트너십에 유리.',
  ),
  PalaceRule(
    id: 'PP-WE-HOOK-CLASH',
    palace: Palace.wealth,
    matcher: _ppWeHookClash,
    delta: -8,
    verdict: '雙鉤相照 — 재운은 강하나 사람을 향한 이득 계산이 충돌.',
  ),
  PalaceRule(
    id: 'PP-WE-STRONG-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeStrongNoflag,
    delta: 5,
    verdict: '財帛雙立 — 재물 감각이 함께 야물어 돈의 흐름을 놓치지 않습니다.',
  ),
  PalaceRule(
    id: 'PP-WE-THIN-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeThinBoth,
    delta: -6,
    verdict: '雙刀鼻 — 계산적 강박이 겹쳐 푼돈까지 날 서게 다투기 쉽습니다.',
  ),
  PalaceRule(
    id: 'PP-WE-WEAK-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeWeakNoflag,
    delta: -4,
    verdict: '財帛雙薄 — 재운 축이 느슨해 감정 지출을 경계해야 합니다.',
  ),

  // ──── 疾厄宮 (illness) — weight 0.01 ──────────────────────────────
  PalaceRule(
    id: 'PP-IL-SANGEN-LOW',
    palace: Palace.illness,
    matcher: _ppIlSangenLow,
    delta: -8,
    verdict: '山根雙陷 — 건강·중년 고비에 동시 약점, 서로를 염려해야.',
  ),
  PalaceRule(
    id: 'PP-IL-SANGEN-HIGH',
    palace: Palace.illness,
    matcher: _ppIlSangenHigh,
    delta: 6,
    verdict: '山根雙聳 — 체력 기반이 함께 탄탄해 중년 고비를 나란히 넘깁니다.',
  ),

  // ──── 官祿宮 (career) — weight 0.003 ──────────────────────────────
  PalaceRule(
    id: 'PP-CR-STRONG',
    palace: Palace.career,
    matcher: _bothStrong,
    delta: 6,
    verdict: '中正朗朗 — 사회적 보폭이 비슷해 자부심이 교차.',
  ),
  PalaceRule(
    id: 'PP-CR-CROSS',
    palace: Palace.career,
    matcher: _oneStrongOneWeak,
    delta: -4,
    verdict: '官祿高低 — 사회적 높낮이 차로 자존심 대립 여지.',
  ),
  PalaceRule(
    id: 'PP-CR-WEAK',
    palace: Palace.career,
    matcher: _bothWeak,
    delta: -2,
    verdict: '中正俱低 — 외적 성취를 함께 작게 두는 조용한 궁합.',
  ),

  // ──── 奴僕宮 (slave) — weight 0.03 ────────────────────────────────
  PalaceRule(
    id: 'PP-SV-STRONG',
    palace: Palace.slave,
    matcher: _bothStrong,
    delta: 3,
    verdict: '地閣雙厚 — 인맥과 아랫사람 복이 함께 든든합니다.',
  ),
  PalaceRule(
    id: 'PP-SV-WEAK',
    palace: Palace.slave,
    matcher: _bothWeak,
    delta: -3,
    verdict: '地閣俱薄 — 주변 조력이 얇아 둘이 모든 일을 떠맡는 경향.',
  ),

  // ──── 兄弟宮 (sibling) — weight 0.003 ─────────────────────────────
  PalaceRule(
    id: 'PP-BR-STRONG',
    palace: Palace.sibling,
    matcher: _bothStrong,
    delta: 3,
    verdict: '眉宇雙軒 — 형제·친우의 지원이 함께 밝습니다.',
  ),
  PalaceRule(
    id: 'PP-BR-CROSS',
    palace: Palace.sibling,
    matcher: _oneStrongOneWeak,
    delta: -2,
    verdict: '眉宇高低 — 주변 관계 온도차가 미묘하게 드러납니다.',
  ),

  // ──── 遷移宮 (migration) — weight 0.002 ───────────────────────────
  PalaceRule(
    id: 'PP-MV-STRONG',
    palace: Palace.migration,
    matcher: _bothStrong,
    delta: 2,
    verdict: '驛馬雙動 — 새 환경으로 함께 움직이는 기운이 강합니다.',
  ),

  // ──── 父母宮 (parents) — weight 0.002 ─────────────────────────────
  PalaceRule(
    id: 'PP-PR-STRONG',
    palace: Palace.parents,
    matcher: _bothStrong,
    delta: 3,
    verdict: '日月雙明 — 부모 복이 양쪽 집에서 나란히 이어집니다.',
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
