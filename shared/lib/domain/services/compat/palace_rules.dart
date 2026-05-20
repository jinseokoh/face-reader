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

/// 전체 PP rule. 순서는 가독성 위주 (palace 묶음). matcher 상호 배타.
const List<PalaceRule> palaceRules = [
  // ──── 배우자 영역 (spouse) — 최핵심 weight 0.28 ─────────────────────
  PalaceRule(
    id: 'PP-SP-STRONG-SMOOTH',
    palace: Palace.spouse,
    matcher: _ppSpStrongSmooth,
    delta: 24,
    verdict:
        '두 분 모두 눈꼬리 바깥(배우자 자리)이 매끈하고 환합니다. '
        '결혼 생활에서 서로를 귀하게 여기는 태도가 자연스럽게 배어 있는 조합이에요. '
        '오래 함께해도 첫 만남의 존중이 남아 있을 가능성이 높습니다.',
  ),
  PalaceRule(
    id: 'PP-SP-STRONG-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpStrongNoflag,
    delta: 20,
    verdict:
        '배우자 자리가 양쪽 다 단단하게 섰습니다. '
        '결혼이 두 분 인생의 중심축으로 자리잡기 쉬운 조합이에요. '
        '연애보다 정식 관계에서 더 안정감을 느끼는 쪽에 가깝습니다.',
  ),
  PalaceRule(
    id: 'PP-SP-CROSS',
    palace: Palace.spouse,
    matcher: _ppSpCross,
    delta: 8,
    verdict:
        '한 분의 배우자 자리는 단단하고 다른 분은 여린 편입니다. '
        '강한 쪽이 약한 쪽을 품어 주면 관계가 차분히 자리잡는 모양이에요. '
        '다만 기대치 차이를 주기적으로 확인하는 대화가 필요합니다.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-WRINKLE',
    palace: Palace.spouse,
    matcher: _ppSpWeakWrinkle,
    delta: -25,
    verdict:
        '두 분 모두 배우자 자리가 여린 데다 눈꼬리 잔주름이 겹쳐 있습니다. '
        '부부 사이의 정이 쉽게 흔들릴 수 있는 조합이에요. '
        '서로의 감정을 자주 꺼내 환기해 주는 습관이 꼭 필요합니다.',
  ),
  PalaceRule(
    id: 'PP-SP-WEAK-NOFLAG',
    palace: Palace.spouse,
    matcher: _ppSpWeakNoflag,
    delta: -20,
    verdict:
        '배우자 자리가 양쪽 모두 식어 있는 편입니다. '
        '관계에 대한 기대가 낮아 "함께 사는 룸메이트"처럼 되기 쉬워요. '
        '따뜻한 말 한 마디가 평소보다 훨씬 큰 힘을 발휘하는 관계입니다.',
  ),

  // ──── 자녀·다정함 영역 (children) — weight 0.22 ─────────────────────
  PalaceRule(
    id: 'PP-CH-STRONG-PLUMP',
    palace: Palace.children,
    matcher: _ppChStrongPlump,
    delta: 22,
    verdict:
        '두 분 모두 눈 아래 애교살이 통통히 살아 있습니다. '
        '자녀나 가까운 사람에게 쏟는 정이 풍부하고, 서로의 다정함이 겹치는 조합이에요. '
        '가정에 온기가 자연스럽게 채워질 가능성이 높습니다.',
  ),
  PalaceRule(
    id: 'PP-CH-STRONG-NOFLAG',
    palace: Palace.children,
    matcher: _ppChStrongNoflag,
    delta: 16,
    verdict:
        '자녀·다정함 자리가 양쪽 다 풍성합니다. '
        '가까운 사람을 돌보는 태도가 비슷해, 자녀나 반려동물을 키우는 데도 호흡이 잘 맞아요. '
        '다만 애정이 한쪽에만 쏠리지 않도록 균형을 챙겨 주세요.',
  ),
  PalaceRule(
    id: 'PP-CH-CROSS',
    palace: Palace.children,
    matcher: _ppChCross,
    delta: 6,
    verdict:
        '자녀·다정함 자리가 한쪽은 풍성하고 다른 쪽은 얇습니다. '
        '다정한 쪽이 먼저 내미는 손이 관계의 부족함을 채워 주는 모양이에요. '
        '얇은 쪽도 의식적으로 애정 표현을 연습하면 균형이 잡힙니다.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-HOLLOW',
    palace: Palace.children,
    matcher: _ppChWeakHollow,
    delta: -22,
    verdict:
        '두 분 모두 눈 아래 애교살이 얇거나 꺼진 편입니다. '
        '가정의 따뜻함이 저절로 우러나오기 어려워, 의식적으로 정을 쌓아야 해요. '
        '하루 한 번 "고마워"를 직접 말하는 것부터 시작해 보세요.',
  ),
  PalaceRule(
    id: 'PP-CH-WEAK-NOFLAG',
    palace: Palace.children,
    matcher: _ppChWeakNoflag,
    delta: -16,
    verdict:
        '자녀·다정함 자리가 양쪽 다 조용합니다. '
        '자녀나 후배와의 인연이 늦게 풀리는 경향이 있는 조합이에요. '
        '조급해하지 말고 때가 오면 자연스럽게 열리는 인연을 기다려 보세요.',
  ),

  // ──── 자기다움 영역 (life) — weight 0.15 ────────────────────────────
  PalaceRule(
    id: 'PP-LF-BRIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfBrightBoth,
    delta: 20,
    verdict:
        '두 분 모두 미간이 넓고 밝습니다. '
        '인생의 큰 결정을 직접 밀고 나갈 기개가 나란히 서 있는 조합이에요. '
        '서로의 생각이 쉽게 통해 일상 대화에도 활기가 돕니다.',
  ),
  PalaceRule(
    id: 'PP-LF-STRONG-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfStrongNoflag,
    delta: 14,
    verdict:
        '자기다움 자리가 양쪽 다 든든합니다. '
        '삶의 고비에서 서로를 일으켜 줄 수 있는 의지가 나란히 섰어요. '
        '위기 상황에 함께 있으면 더 강해지는 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-LF-CROSS',
    palace: Palace.life,
    matcher: _ppLfCross,
    delta: -8,
    verdict:
        '한 분의 결단력은 강하고 다른 분은 여린 편입니다. '
        '결단의 속도가 달라 중요한 선택 앞에서 호흡이 어긋날 수 있어요. '
        '빠른 쪽이 잠시 멈추고, 느린 쪽이 한 발 앞으로 나오면 균형이 잡힙니다.',
  ),
  PalaceRule(
    id: 'PP-LF-TIGHT-BOTH',
    palace: Palace.life,
    matcher: _ppLfTightBoth,
    delta: -22,
    verdict:
        '두 분 모두 미간이 좁고 어두운 편입니다. '
        '속에 쌓인 감정을 바깥으로 꺼내는 습관이 없어 답답함이 서로에게 증폭되기 쉬워요. '
        '매주 정해진 시간에 "이번 주에 마음에 걸린 일"을 하나씩 꺼내는 연습을 해 보세요.',
  ),
  PalaceRule(
    id: 'PP-LF-WEAK-NOFLAG',
    palace: Palace.life,
    matcher: _ppLfWeakNoflag,
    delta: -14,
    verdict:
        '자기다움 자리가 양쪽 다 흐립니다. '
        '결단의 실이 쉽게 끊어져, 작은 결정조차 서로 미루게 되기 쉬워요. '
        '작은 결정부터 같이 짚어 가는 습관이 관계를 단단히 해 줍니다.',
  ),

  // ──── 집·생활 영역 (property) — weight 0.13 ─────────────────────────
  PalaceRule(
    id: 'PP-TH-STRONG',
    palace: Palace.property,
    matcher: _bothStrong,
    delta: 14,
    verdict:
        '두 분의 눈과 눈썹 사이(집·생활 자리)가 모두 두텁습니다. '
        '함께 만드는 살림이 관계의 밑바탕이 되어 줄 조합이에요. '
        '집 마련이나 정착 시점을 비슷하게 설정하기 쉽습니다.',
  ),
  PalaceRule(
    id: 'PP-TH-CROSS',
    palace: Palace.property,
    matcher: _oneStrongOneWeak,
    delta: 4,
    verdict:
        '집·생활 자리에서 한 쪽은 터가 두텁고 다른 쪽은 얇습니다. '
        '서로 다른 기반이 하나의 집을 채우는 방식이 관계의 색깔이 돼요. '
        '생활 방식의 차이를 존중하면 오히려 풍성해지는 조합입니다.',
  ),
  PalaceRule(
    id: 'PP-TH-WEAK',
    palace: Palace.property,
    matcher: _bothWeak,
    delta: -14,
    verdict:
        '집·생활 자리가 양쪽 다 얇습니다. '
        '거처가 불안정하면 관계도 흔들리기 쉬운 조합이에요. '
        '비상자금과 주거 계획을 먼저 다져 두면 관계까지 안정됩니다.',
  ),

  // ──── 행복·여유 영역 (fortune) — weight 0.12 ────────────────────────
  PalaceRule(
    id: 'PP-FT-CLOUDLESS',
    palace: Palace.fortune,
    matcher: _ppFtCloudless,
    delta: 18,
    verdict:
        '두 분 모두 이마 위 좌우(행복·여유 자리)가 밝게 트여 있습니다. '
        '일상에서 여유를 느끼는 감각이 살아 있어, 작은 일에도 같이 웃는 시간이 많아요. '
        '여행이나 취미를 함께하면 관계가 더 풍요로워집니다.',
  ),
  PalaceRule(
    id: 'PP-FT-STRONG-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtStrongNoflag,
    delta: 12,
    verdict:
        '행복·여유 자리가 양쪽 다 든든합니다. '
        '가치관의 폭이 비슷해 삶의 여유를 같이 즐길 수 있는 관계예요. '
        '무엇을 하며 쉴지에 대한 취향도 크게 다르지 않을 가능성이 높습니다.',
  ),
  PalaceRule(
    id: 'PP-FT-DENTED',
    palace: Palace.fortune,
    matcher: _ppFtDented,
    delta: -18,
    verdict:
        '두 분 모두 이마 위 좌우가 꺼진 편입니다. '
        '사소한 일에도 여유가 빠르게 닳아, 지친 상태에서 서로에게 짜증이 튀기 쉬워요. '
        '일주일에 하루는 아무것도 안 하는 "회복일"을 꼭 정해 두세요.',
  ),
  PalaceRule(
    id: 'PP-FT-WEAK-NOFLAG',
    palace: Palace.fortune,
    matcher: _ppFtWeakNoflag,
    delta: -12,
    verdict:
        '행복·여유 자리가 양쪽 다 얇은 조합입니다. '
        '지금 누리는 것을 소중히 여기는 자세가 관계에 큰 도움이 돼요. '
        '저축 습관과 함께 "즐기기 위한 예산"도 따로 잡아 두면 좋습니다.',
  ),

  // ──── 재물 영역 (wealth) — weight 0.05 ──────────────────────────────
  PalaceRule(
    id: 'PP-WE-BULB-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeBulbBoth,
    delta: 10,
    verdict:
        '두 분 모두 코끝이 복스럽게 솟아 있습니다. '
        '돈을 모으고 관리하는 감각이 비슷해 경제 파트너십에 유리한 조합이에요. '
        '공동 목표를 숫자로 정해 두면 속도가 더 빨라집니다.',
  ),
  PalaceRule(
    id: 'PP-WE-HOOK-CLASH',
    palace: Palace.wealth,
    matcher: _ppWeHookClash,
    delta: -8,
    verdict:
        '두 분 모두 매부리코 기운이 있어 재물 감각은 날카롭습니다. '
        '다만 이득 계산이 사사건건 부딪힐 가능성이 커요. '
        '큰 지출은 제3자 기준을 먼저 받아와 숫자로 합의하세요.',
  ),
  PalaceRule(
    id: 'PP-WE-STRONG-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeStrongNoflag,
    delta: 5,
    verdict:
        '재물 자리가 양쪽 다 탄탄합니다. '
        '돈 감각이 함께 살아 있어 경제적 결정에서 호흡이 잘 맞아요. '
        '다만 모으는 데만 집중하면 삶이 건조해지니 여가 예산도 챙겨 주세요.',
  ),
  PalaceRule(
    id: 'PP-WE-THIN-BOTH',
    palace: Palace.wealth,
    matcher: _ppWeThinBoth,
    delta: -6,
    verdict:
        '두 분 모두 콧대가 가늘고 날카롭습니다. '
        '돈 앞에서 예민하고 계산적인 성향이 겹쳐, 작은 금액으로도 날이 서기 쉬워요. '
        '1만 원 이하는 따지지 않는 규칙을 미리 정해 두세요.',
  ),
  PalaceRule(
    id: 'PP-WE-WEAK-NOFLAG',
    palace: Palace.wealth,
    matcher: _ppWeWeakNoflag,
    delta: -4,
    verdict:
        '재물 자리가 양쪽 모두 느슨한 편입니다. '
        '기분에 따라 지출이 흔들리기 쉬운 조합이에요. '
        '공동 카드 하나로 지출을 모으고 월 1회 자동 정산하면 다툼이 줄어듭니다.',
  ),

  // ──── 건강 영역 (illness) — weight 0.01 ─────────────────────────────
  PalaceRule(
    id: 'PP-IL-SANGEN-LOW',
    palace: Palace.illness,
    matcher: _ppIlSangenLow,
    delta: -8,
    verdict:
        '두 분 모두 콧대 뿌리가 꺼진 편입니다. '
        '40대 이후 체력 저하가 관계에 영향을 주기 쉬운 조합이에요. '
        '매년 종합검진을 같이 받고, 보험·의료비 계획을 공동으로 관리하세요.',
  ),
  PalaceRule(
    id: 'PP-IL-SANGEN-HIGH',
    palace: Palace.illness,
    matcher: _ppIlSangenHigh,
    delta: 6,
    verdict:
        '콧대 뿌리가 양쪽 다 높게 섰습니다. '
        '체력 기반이 나란히 탄탄해, 나이 들어서도 함께 활동하기 좋은 조합이에요. '
        '다만 자신감이 있어도 기본 건강검진은 빠뜨리지 마세요.',
  ),

  // ──── 커리어 영역 (career) — weight 0.003 ───────────────────────────
  PalaceRule(
    id: 'PP-CR-STRONG',
    palace: Palace.career,
    matcher: _bothStrong,
    delta: 6,
    verdict:
        '커리어 자리(이마 한가운데)가 양쪽 다 단단합니다. '
        '사회적 보폭이 비슷해 서로의 성취에 자부심을 느낄 수 있는 관계예요. '
        '각자의 커리어 이벤트를 축하해 주면 관계도 같이 올라갑니다.',
  ),
  PalaceRule(
    id: 'PP-CR-CROSS',
    palace: Palace.career,
    matcher: _oneStrongOneWeak,
    delta: -4,
    verdict:
        '커리어 자리의 높낮이가 엇갈립니다. '
        '사회적 위치 차이에서 자존심이 부딪힐 여지가 있어요. '
        '상대의 속도를 존중하고, 비교 대신 응원에 집중하면 마찰이 줄어듭니다.',
  ),
  PalaceRule(
    id: 'PP-CR-WEAK',
    palace: Palace.career,
    matcher: _bothWeak,
    delta: -2,
    verdict:
        '두 분 모두 커리어 자리가 조용합니다. '
        '외적 성취보다 조용한 일상을 함께 즐기는 조합이에요. '
        '다만 경제적 기반은 꾸준히 다져 둬야 관계의 안정감이 유지됩니다.',
  ),

  // ──── 사람 관계 영역 (slave) — weight 0.03 ──────────────────────────
  PalaceRule(
    id: 'PP-SV-STRONG',
    palace: Palace.slave,
    matcher: _bothStrong,
    delta: 3,
    verdict:
        '두 분 모두 턱 양옆이 두터워 사람 관계 자리가 단단합니다. '
        '인맥과 주변의 도움이 함께 풍성한 조합이에요. '
        '주변 사람들의 지지가 두 분의 관계를 더 든든하게 받쳐 줍니다.',
  ),
  PalaceRule(
    id: 'PP-SV-WEAK',
    palace: Palace.slave,
    matcher: _bothWeak,
    delta: -3,
    verdict:
        '사람 관계 자리가 양쪽 다 얇습니다. '
        '외부 조력이 제한적이라 두 분이 모든 일을 직접 떠맡는 경향이 있어요. '
        '가까운 사람 한두 명에게는 도움을 요청하는 연습이 필요합니다.',
  ),

  // ──── 친구·동료 영역 (sibling) — weight 0.003 ──────────────────────
  PalaceRule(
    id: 'PP-BR-STRONG',
    palace: Palace.sibling,
    matcher: _bothStrong,
    delta: 3,
    verdict:
        '친구·동료 자리(눈썹)가 양쪽 다 맑습니다. '
        '주변 친구와 동료의 지원이 함께 밝은 조합이에요. '
        '서로의 인맥을 자연스럽게 공유하면 관계의 폭이 넓어집니다.',
  ),
  PalaceRule(
    id: 'PP-BR-CROSS',
    palace: Palace.sibling,
    matcher: _oneStrongOneWeak,
    delta: -2,
    verdict:
        '친구·동료 자리가 한 쪽만 선명합니다. '
        '주변 관계의 온도 차이가 미묘하게 드러날 수 있어요. '
        '각자의 친구 영역을 존중하면서 겹치는 부분을 천천히 만들어 가세요.',
  ),

  // ──── 변화·이동 영역 (migration) — weight 0.002 ────────────────────
  PalaceRule(
    id: 'PP-MV-STRONG',
    palace: Palace.migration,
    matcher: _bothStrong,
    delta: 2,
    verdict:
        '변화·이동 자리(관자놀이)가 양쪽 다 활발합니다. '
        '새 환경으로 함께 움직이는 호흡이 잘 맞는 조합이에요. '
        '이사나 여행 같은 변화를 함께 겪으면 관계가 더 단단해집니다.',
  ),

  // ──── 부모·가족 영역 (parents) — weight 0.002 ──────────────────────
  PalaceRule(
    id: 'PP-PR-STRONG',
    palace: Palace.parents,
    matcher: _bothStrong,
    delta: 3,
    verdict:
        '부모·가족 자리(이마 윗부분)가 양쪽 다 밝습니다. '
        '양가 부모와의 관계가 나란히 좋을 가능성이 높은 조합이에요. '
        '가족 행사를 함께 챙기면 양가 모두에서 환영받는 커플이 됩니다.',
  ),

];

bool _bothHaveFlag(PalaceState a, PalaceState b, PalaceFlag f) =>
    a.hasFlag(f) && b.hasFlag(f);

// ────────── matcher helpers ──────────

bool _bothStrong(PalaceState a, PalaceState b) => a.isStrong && b.isStrong;
bool _bothWeak(PalaceState a, PalaceState b) => a.isWeak && b.isWeak;
bool _eitherHasFlag(PalaceState a, PalaceState b, PalaceFlag f) =>
    a.hasFlag(f) || b.hasFlag(f);
bool _oneStrongOneWeak(PalaceState a, PalaceState b) =>
    (a.isStrong && b.isWeak) || (a.isWeak && b.isStrong);
bool _ppChCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);

// ────────── rule catalog ──────────

bool _ppChStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.plumpLowerEyelid);

bool _ppChStrongPlump(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.plumpLowerEyelid);
bool _ppChWeakHollow(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.hollowLowerEyelid);
bool _ppChWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.hollowLowerEyelid);
bool _ppFtCloudless(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.cloudlessForehead);
bool _ppFtDented(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.dentedTemple);

bool _ppFtStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.cloudlessForehead);
bool _ppFtWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.dentedTemple);
bool _ppIlSangenHigh(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _eitherHasFlag(a, b, PalaceFlag.sanGenHigh);
bool _ppIlSangenLow(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.sanGenLow);
bool _ppLfBrightBoth(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.glabellaBright);

bool _ppLfCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);
bool _ppLfStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.glabellaBright);
bool _ppLfTightBoth(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.glabellaTight);
bool _ppLfWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.glabellaTight);
bool _ppSpCross(PalaceState a, PalaceState b) => _oneStrongOneWeak(a, b);

bool _ppSpStrongNoflag(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && !_bothHaveFlag(a, b, PalaceFlag.smoothFishTail);
// ────────── top-level matchers (const 로 참조 가능) ──────────
//
// Dart const constructor 가 instance-method 참조를 허용하지 않으므로 모든
// matcher 는 top-level 함수로 분리. palaceRules 상수 리스트가 참조 가능.

bool _ppSpStrongSmooth(PalaceState a, PalaceState b) =>
    _bothStrong(a, b) && _bothHaveFlag(a, b, PalaceFlag.smoothFishTail);
bool _ppSpWeakNoflag(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && !_eitherHasFlag(a, b, PalaceFlag.fishTailWrinkle);
bool _ppSpWeakWrinkle(PalaceState a, PalaceState b) =>
    _bothWeak(a, b) && _eitherHasFlag(a, b, PalaceFlag.fishTailWrinkle);

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
