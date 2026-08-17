part of 'life_question_narrative.dart';

// ═══════════════════════════════════════════════════════════════════════
// 인생 질문 서술 코퍼스 v2 — 측정 + 전통 귀속
//
// 문장 규칙 — 두 문장, 각각 주어가 다르다.
//   [1 판정]      우리가 잰 값이 어느 부류인가. `@{verdict:attr}` 슬롯이
//                 문장 하나를 통째로 뱉는다.
//                 "재물을 상당히 모을 가능성이 높은 부류로 판단했습니다."
//   [2 전통 귀속]  전통이 그 부위를 무엇으로 보고 어떻게 읽었는지.
//                 주어는 반드시 **전통**이다.
//                 "전통 관상은 코를 재백궁이라 부르고 재물이 드나드는
//                  자리로 보았습니다."
//
// 왜 이 형식인가 — 두 문장 다 참이기 때문이다. 1번은 우리가 쟀으니 참이고,
// 2번은 전통이 실제로 그렇게 말했으니 참이다. 반박하려면 우리 측정을
// 재현하거나 관상서를 반박해야 한다.
//
// 반대로 "돈 판단이 흔들리는 일이 적은 편입니다" 같은 문장은 측정처럼
// 생겼지만 그 사람에 대한 행동 주장이고 근거가 없다. 계측의 권위를 빌려
// 검증 안 된 주장을 하는 셈이라 가장 나쁜 형태다. 전부 제거한다.
//
// 절대 금지
//   그 사람에 대한 단정      "당신은 ~입니다" · "~하는 편입니다"
//   미래·운명               "말년" · "평생" · "운이 트인다" · "~하게 됩니다"
//   측정을 가장한 행동 주장   "~쪽에 값이 몰려 있습니다"(행동 서술일 때)
//   외부 연구 인용           자체 분포와 전통 문헌만
//
// 전통 귀속의 근거는 `physiognomy_tree.dart` 의 십이궁·오관 태그다. 점수를
// 내는 그 메타데이터로 문장도 만들기 때문에 "왜 코를 재물이라 했나"에
// "재백궁이라서"라고 코드로 답할 수 있다. 지어낸 귀속은 하나도 없다.
//   이마 = 관록궁·천이궁   미간 = 명궁       눈썹 = 형제궁
//   눈  = 전택·남녀·처첩궁  코  = 재백·질액궁  턱  = 노복궁
//   입  = 출납관(오관)     광대 = 오악        코  = 심변관(오관)
//
// 조언 풀의 연령 조건(_isYoung·_isMid·_isLate)은 전통에 귀속하지 않는다.
// 전통의 유년운기는 미래를 말하는 층이라 쓰지 않기로 했고, 그 자리에는
// 얼굴과 무관한 일반 조언만 둔다.
//
// 부류(상위권·중위권·하위권)의 출처는 `_band()` — 같은 성별·얼굴형 quantile
// 테이블 위에서 매긴 정규화 점수의 구간이고, 그 테이블은 AAF 11,800장
// 실측이다. 숫자 백분위를 쓰지 않는 이유는 "상위 27%"가 읽는 사람에게
// 아무 의미도 주지 않기 때문이다. 알아야 할 것은 어느 부류이고 전통이
// 그 부류를 무엇으로 보았는가다.
//
// 부류 판정은 문장을 고르는 조건(`_bandPair`·`_highPair`)과 **같은 함수**를
// 쓴다. 다른 기준을 쓰면 "중위권이고, 함께 높습니다" 같은 자기모순이 난다.
//
// 조건 구조는 v1 풀과 1:1 대응한다. 조건 로직·가중치·엔트로피는 건드리지
// 않고 문장만 새로 썼다. 각 풀의 마지막은 반드시 `_Frag.hard((f) => true)`
// fallback 이라 조건 커버리지에 구멍이 없다.
//
// 성별 분리 — v1 은 연애·활력 두 섹션을 남/여 별도 풀로 뒀다. v2 에서는
// **조건 집합이 실제로 다른 풀만** 분리를 유지한다 (연애 strength·shadow).
// 조건이 동일한 풀(연애 opening·advice, 활력 opening·strength·advice)은
// 측정 서술이 성별에 따라 달라질 근거가 없으므로 공용 풀 하나로 합쳤다.
// ═══════════════════════════════════════════════════════════════════════

/// 항목 × 부류 → 판정 문장. `@{verdict:attr}` 슬롯이 이걸 부른다.
///
/// "상위 27%" 같은 숫자는 쓰지 않는다. 읽는 사람이 알고 싶은 것은 자기가
/// 어느 부류이고 그게 무슨 뜻인가지, 소수점이 아니다. 부류 판정은 문장을
/// 고르는 조건(`_band`)과 같은 함수를 쓰므로 뒤따르는 서술과 어긋나지 않는다.
/// 종결이 30개 모두 "…부류로 판단했습니다" 면 섹션마다 같은 소리로 시작한다.
/// 판단·읽힘·봄·들어감·나옴 다섯 틀을 돌려 쓴다. 뜻은 같고 어조만 다르다.
const _v2Verdicts = <Attribute, Map<_Band, String>>{
  Attribute.wealth: {
    _Band.high: '재물을 상당히 모을 가능성이 높은 부류로 판단했습니다.',
    _Band.mid: '재물을 충분히 모을 가능성이 높은 쪽으로 읽힙니다.',
    _Band.low: '재물을 아쉬워할 가능성이 높은 부류에 들어갑니다.',
  },
  Attribute.stability: {
    _Band.high: '큰 일에도 좀처럼 흔들리지 않을 쪽으로 봅니다.',
    _Band.mid: '웬만한 일에는 흔들리지 않을 가능성이 높은 부류예요.',
    _Band.low: '기복을 자주 겪을 가능성이 높은 쪽으로 나왔습니다.',
  },
  Attribute.attractiveness: {
    _Band.high: '첫인상에서 호감을 크게 얻을 부류로 판단됩니다.',
    _Band.mid: '첫인상에서 무난히 호감을 얻는 쪽에 가깝습니다.',
    _Band.low: '첫인상보다 겪어 봐야 알아지는 부류로 읽힙니다.',
  },
  Attribute.emotionality: {
    _Band.high: '감정을 깊고 세게 느끼는 쪽으로 봅니다.',
    _Band.mid: '감정을 고르게 다루는 부류에 들어갑니다.',
    _Band.low: '감정보다 사실을 앞세우는 쪽으로 판단했습니다.',
  },
  Attribute.libido: {
    _Band.high: '기운이 왕성한 부류예요.',
    _Band.mid: '기운이 꾸준한 쪽으로 읽힙니다.',
    _Band.low: '기운을 아껴 쓰는 부류로 봅니다.',
  },
  Attribute.sensuality: {
    _Band.high: '이성의 눈길을 크게 끄는 쪽으로 판단됩니다.',
    _Band.mid: '이성의 눈길을 무난히 끄는 부류입니다.',
    _Band.low: '눈길을 끄는 쪽보다 오래 두고 볼수록 좋아지는 부류로 읽힙니다.',
  },
  Attribute.sociability: {
    _Band.high: '사람을 널리 모으는 쪽으로 봅니다.',
    _Band.mid: '사람과 무난히 어울리는 부류예요.',
    _Band.low: '넓게 사귀기보다 좁고 깊게 사귀는 쪽으로 판단했습니다.',
  },
  Attribute.trustworthiness: {
    _Band.high: '남에게 크게 신뢰받을 부류에 들어갑니다.',
    _Band.mid: '남에게 무난히 신뢰받는 쪽으로 읽힙니다.',
    _Band.low: '신뢰를 얻는 데 시간이 걸리는 부류로 판단됩니다.',
  },
  Attribute.intelligence: {
    _Band.high: '상황을 남보다 빨리 읽어내는 쪽입니다.',
    _Band.mid: '상황을 무난히 읽어내는 부류로 봅니다.',
    _Band.low: '머리로 재기보다 몸으로 먼저 부딪치는 쪽으로 나왔어요.',
  },
  Attribute.leadership: {
    _Band.high: '무리를 이끄는 자리에 설 가능성이 높은 부류입니다.',
    _Band.mid: '무리 안에서 제 몫을 해내는 쪽으로 읽힙니다.',
    _Band.low: '앞에 서기보다 뒤에서 받쳐 주는 부류로 판단했습니다.',
  },
};

String _v2Verdict(Attribute a, _Band b) => _v2Verdicts[a]?[b] ?? '';

// ═══════════════════════════════════════════════════════════════════════
// 재력 — wealth × stability
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2WealthOpening = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '@{verdict:wealth} 안정성 항목도 함께 높게 나왔습니다. 전통 관상은 코를 재백궁, 턱을 노복궁으로 두고 두 자리가 같이 실한 얼굴을 재물이 들어오고 또 머무는 상으로 읽었습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 안정성은 평균대입니다. 코는 관상에서 재백궁이라 하여 재물이 드나드는 자리로 보았고, 이 자리가 실한 얼굴을 기회가 먼저 눈에 들어오는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '@{verdict:wealth} 다만 안정성은 낮은 쪽입니다. 코가 실하고 턱이 얇은 얼굴을 두고 전통 관상은 들어오는 폭과 나가는 폭이 함께 큰 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '@{verdict:stability} 재력 항목은 평균대예요. 옛 관상서는 턱을 노복궁으로 두고, 이 자리가 두터운 얼굴을 지키는 힘이 앞선 상으로 읽었어요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 안정성도 비슷한 자리에 있습니다. 관상서는 어느 한 자리가 유독 튀지 않고 고른 얼굴을 두고 균형이 잡힌 상이라 합니다.',
    '@{verdict:wealth} 전통 관상은 코가 지나치게 크지도 작지도 않은 얼굴을 재백궁이 순한 상으로 보았습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '@{verdict:stability} 재력 항목은 평균대입니다. 턱이 얇은 얼굴을 두고 전통 관상은 마음이 자주 옮겨 앉는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '@{verdict:wealth} 대신 안정성은 높은 쪽입니다. 관상 전통은 코보다 턱이 발달한 얼굴을 두고 만드는 쪽보다 지키는 쪽이 강한 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 안정성은 평균대예요. 전통 관상에서 재백궁이 크게 두드러지지 않는 얼굴은 재물보다 다른 자리에 무게가 실린 상으로 읽혔습니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '@{verdict:wealth} 안정성도 함께 아래쪽입니다. 예로부터 관상에서는 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 재백궁이 아닌 다른 자리에 무게가 실린 상입니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:wealth} 전통 관상은 코를 재백궁이라 부르고 재물이 드나드는 자리로 봤어요.',
    '@{verdict:wealth} 전통 관상은 콧대의 곧기와 콧방울의 두께를 재백궁의 두께로 읽습니다.',
    '@{verdict:wealth} 전통 관상에서 이 자리는 열두 궁 가운데 재물을 맡은 자리예요.',
  ]),
];

final List<_Frag> _v2WealthVignette = [
  _Frag(_highOf(Attribute.wealth), [
    '재백궁이 실한 얼굴을 두고 옛 관상서는 재물이 들어오는 길이 열려 있다고 읽어 왔어요.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '전통 관상은 턱이 두터운 얼굴을 두고 자리를 오래 지키는 힘이 있다고 봅니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '관상서에서는 턱이 얇은 얼굴을 두고 마음이 먼저 움직이는 상이라 합니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '콧방울이 얇은 얼굴을 두고 옛 관상서는 재백궁이 헐거운 상으로 읽었습니다.',
  ]),
  _Frag.hard((f) => true, [
    '관상에서 코는 재백궁이면서 오관 가운데 심변관이기도 합니다. 살피고 가려내는 자리라는 뜻입니다.',
    '옛 관상서는 재물을 코 하나로 보지 않고 이마·광대·턱을 함께 놓고 읽었어요.',
    '관상서는 재백궁이 실해도 다른 자리가 헐거우면 그 자리만으로 읽지 않았습니다.',
  ]),
];

final List<_Frag> _v2WealthStrength = [
  _Frag.hard((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '코 항목의 측정값이 같은 성별·얼굴형 평균보다 뚜렷하게 높습니다. 관상서에서는 이 자리를 재백궁이라 하고, 콧대가 곧고 콧방울이 두툼한 얼굴을 재물이 머무는 상으로 읽습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균 위에 있어요. 관상서에서 광대는 오악의 하나이고, 이 자리가 선 얼굴을 사람을 움직이는 힘이 있는 상이라 했습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '턱 항목의 값이 높게 측정됩니다. 관상서에서 턱은 노복궁이고, 이 자리가 두터운 얼굴을 아랫사람과 자리를 함께 지키는 상으로 읽어 왔어요.',
  ]),
  _Frag.hard((f) => f.fired('Z-11'), [
    '얼굴 가운데 구역의 항목들이 고르게 높습니다. 관상 전통은 얼굴을 위·가운데·아래 세 구역으로 나누어 보았고, 가운데가 고른 얼굴을 힘이 실린 상이라 했어요.',
  ]),
  _Frag.hard((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입 항목의 값이 함께 높습니다. 관상서에서는 코를 재백궁, 입을 출납관이라 하여 들어오는 자리와 나가는 자리로 나누어 보았어요.',
  ]),
  _Frag.hard((f) => true, [
    '예로부터 관상에서는 재물을 이마·코·광대·턱 네 자리로 나누어 보았습니다. 총합을 매기지 않고 어느 자리가 실한지를 따로 보았다는 뜻입니다.',
    '전통 관상은 코가 홀로 큰 얼굴보다 이마와 턱이 받쳐 주는 얼굴을 더 높게 봤어요.',
    '관상서에서는 광대와 코가 함께 선 얼굴을 두고 혼자보다 사람을 통해 넓히는 상이라 합니다.',
    '관상서에서 이마는 관록궁, 코는 재백궁이에요. 두 자리가 함께 서 있으면 이름과 재물을 같은 길에서 얻는 상으로 읽었습니다.',
    '옛 관상서는 재백궁의 크기보다 그 자리가 흐트러지지 않았는지를 먼저 봅니다.',
  ]),
];

final List<_Frag> _v2WealthShadow = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '다만 관상서는 코와 턱이 모두 두터운 얼굴을 두고, 쥐는 힘이 세어 내놓는 자리가 좁아지기 쉽다고도 했습니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '다만 재백궁이 얇은 얼굴을 두고 전통 관상은 들어오는 것보다 나가는 것이 잦은 상이라 읽었어요.',
  ]),
  _Frag.hard((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '다만 눈과 눈썹 항목의 값이 함께 높습니다. 관상 전통은 이 자리가 강한 얼굴을 두고 마음이 먼저 움직이는 상이라 했고, 재물을 두고도 그 기운이 함께 실린다고 보았어요.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 턱 항목의 값이 낮은 쪽입니다. 노복궁이 얇은 얼굴을 두고 전통 관상은 얻은 것을 오래 두기 어려운 상이라 했어요.',
  ]),
  _Frag.hard((f) => true, [
    '다만 예로부터 관상에서는 재백궁 하나만 보고 판단하지 않았어요. 이마와 턱이 받쳐 주지 않으면 그 자리만으로는 읽지 않았습니다.',
    '다만 전통 관상은 콧방울이 벌어진 얼굴을 두고 들어오는 폭만큼 나가는 폭도 넓다고 합니다.',
    '다만 광대가 지나치게 선 얼굴을 두고 전통 관상은 나서는 힘이 앞선다고 보았습니다.',
    '다만 옛 관상서는 한 자리가 유독 두드러진 얼굴보다 여러 자리가 고른 얼굴을 높게 봤어요.',
    '다만 관상서는 상은 마음에서 나온다 하여, 얼굴을 고정된 것으로 보지 않았어요.',
  ]),
];

final List<_Frag> _v2WealthAdvice = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '관상 전통은 코와 턱이 함께 실한 얼굴에 재물을 불리기보다 흩어지지 않게 두라고 권했습니다. 매달 자동으로 쌓이는 액수를 기준으로 삼는 방식이 그 조언과 통합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '예로부터 관상에서는 재백궁이 실하고 노복궁이 평이한 얼굴에 기회를 좇되 발을 빼는 때를 미리 정해 두라 했어요. 좋은 구간에 규모를 키우지 않는 규칙 하나가 그 역할을 합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '전통 관상은 코가 실하고 턱이 얇은 얼굴을 두고, 버는 자리보다 담는 자리를 먼저 손보라 합니다. 손이 닿지 않는 자동 저축 구조가 그에 해당합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '옛 관상서는 턱이 두터운 얼굴에 짧게 끊기보다 길게 묶으라 했습니다. 5년 단위로 설계를 잡아 두는 방식이 그 조언과 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '어느 자리도 치우치지 않은 얼굴을 두고 전통 관상은 습관이 그대로 상이 된다고 했어요. 고정 저축을 수입의 25% 이상으로 자동화해 두는 것이 가장 단순한 적용입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '관상서는 마음이 먼저 움직이는 상에 큰일을 하루 묵히라 합니다. 큰 금전 결정을 24시간 미루는 규칙 하나면 충분합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '관상 전통은 노복궁이 실하고 재백궁이 순한 얼굴에 자리를 오래 지키는 쪽을 권했습니다. 근로·전문직·장기 근속이 그 방향이고, 버는 기술보다 안 쓰는 기준에 시간을 들이는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '예로부터 관상에서는 재백궁이 두드러지지 않은 얼굴을 낮게 보지 않았고, 다만 습관이 그대로 드러난다고 했어요. 자동 이체 저축의 효과가 이 구성에서 가장 단순하게 나타납니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '전통 관상은 열두 자리 가운데 실한 곳을 찾아 그 자리를 쓰라고 합니다. 재백궁이 아니라면 재능·관계·경험 쪽을 중심에 두고 돈은 따라오게 두는 편이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '옛 관상서는 재물을 이마·코·광대·턱 네 자리로 나누어 봅니다. 값이 가장 낮은 자리부터 손보는 순서가 가장 단순합니다.',
    '관상서는 재백궁이 실해도 마음이 흐트러지면 그 자리가 무너진다고 했습니다. 감정이 올라온 구간의 결정을 미루는 규칙이 그에 해당합니다.',
    '관상 전통은 한 번에 크게 얻는 것보다 흐트러지지 않는 쪽을 높게 보았어요. 큰 베팅 한 번보다 매달 도는 고정 저축이 그 방향이에요.',
    '예로부터 관상에서는 얼굴을 고정된 것으로 보지 않았습니다. 상은 마음에서 나온다는 말이 관상서 안에 함께 적혀 있습니다.',
    '전통 관상은 집·직업·혼사를 사람의 큰 갈림으로 보았습니다. 그 앞에서는 평소의 열 배쯤 시간을 들여 알아보는 편이 낫습니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 수입원을 한 갈래로 좁히지 않는 편이 낫습니다. 두세 갈래를 시도해 본 사람이 30대에 자기 기울기를 먼저 찾습니다.',
    '20대에 자동 저축을 수입의 30% 이상으로 잡아 두면 30대 초반에 복리가 작동하기 시작합니다.',
    '20대의 돈은 버는 기술보다 안 쓰는 기준에서 갈립니다. 또래의 소비 압력에 휘둘리지 않도록 카테고리별 한도를 먼저 정해 두세요.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 한 분야에서 충분히 깊어진 뒤 그 깊이로 다른 분야에 발판을 만드는 순서가 맞습니다.',
    '한 번의 성과를 그대로 두 번째 베팅으로 가져가면 낙차가 커집니다. 이 구간에서는 오히려 보수적인 배분이 낫습니다.',
    '40대에는 자기 노동으로만 버는 구조에서 시스템과 조직이 버는 구조로 옮겨 가는 준비가 필요합니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 쌓는 쪽보다 흘려보내는 쪽의 설계가 중요해집니다. 증여·기부·투자 비율을 미리 정해 두세요.',
    '50대 이후에는 수익률보다 자산 분산·유동성·상속 구조를 정비하는 편이 낫습니다. 큰 결정은 가족·전문가와 공유하세요.',
    '60대 이후의 돈은 건강·관계와 함께 볼 때만 의미가 있어요.',
  ]),
];

final List<_BeatPool> _v2WealthBeats = [
  _v2WealthOpening,
  _v2WealthVignette,
  _v2WealthStrength,
  _v2WealthShadow,
  _v2WealthAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 건강 — stability × emotionality
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2HealthOpening = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '@{verdict:stability} 감정성 항목도 함께 높게 나왔습니다. 옛 관상서는 코를 질액궁이라 하여 몸의 자리로도 봅니다. 산근이 곧으면서 눈에 물기가 도는 얼굴은 기운이 살아 있는 상으로 읽어요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 감정성은 평균대입니다. 코는 관상에서 질액궁이라 하여 병과 액이 드러나는 자리로 보았고, 이 자리가 곧은 얼굴을 몸이 고른 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '@{verdict:stability} 감정성은 낮은 쪽입니다. 관상서는 얼굴에 기복이 적은 상을 두고 안으로 눌러 두는 힘이 강하다고 봤어요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '@{verdict:emotionality} 안정성은 평균대예요. 관상 전통은 눈을 사독 가운데 하(河)라 하여 기운이 흐르는 자리로 봅니다. 이 자리가 강한 얼굴은 안팎의 진폭이 크다고 했어요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 감정성도 비슷한 자리에 있습니다. 어느 자리도 유독 튀지 않은 얼굴을 두고 전통 관상은 기운이 고르게 도는 상이라 했습니다.',
    '@{verdict:stability} 전통 관상은 질액궁이 순한 얼굴을 크게 앓지도 크게 넘치지도 않는 상으로 봅니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '@{verdict:emotionality} 안정성은 평균대입니다. 예로부터 관상에서는 표정의 움직임이 적은 얼굴을 두고 속을 밖으로 내지 않는 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '@{verdict:stability} 대신 감정성은 높은 쪽입니다. 산근이 얕고 눈의 기운이 센 얼굴을 두고 전통 관상은 기복이 몸에 먼저 나타나는 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 감정성은 평균대예요. 전통 관상은 턱과 산근이 얇은 얼굴을 두고 버티는 힘보다 흐르는 힘이 앞선 상으로 읽어 왔어요.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '@{verdict:stability} 감정성도 함께 아래쪽입니다. 옛 관상서는 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 질액궁보다 다른 자리에 무게가 실린 상입니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:stability} 전통 관상은 코를 질액궁이라 부르고 병과 액이 드러나는 자리로 보았어요.',
    '@{verdict:stability} 전통 관상은 콧대 위쪽 산근을 몸의 기운이 지나는 길목으로 여겼습니다.',
    '@{verdict:stability} 전통 관상에서 질액궁은 열두 궁 가운데 몸을 맡은 자리예요.',
  ]),
];

final List<_Frag> _v2HealthVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '눈에 기운이 실린 얼굴을 두고 옛 관상서는 안의 움직임이 밖으로 먼저 드러난다고 했습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '관상서는 산근이 곧은 얼굴을 두고 몸이 쉽게 흔들리지 않는다고 보았습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.high,
    [
      '관상서에서는 산근이 얕고 눈의 기운이 센 얼굴을 두고 기복이 몸에 먼저 온다고 했어요.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '산근이 얕은 얼굴을 두고 옛 관상서는 질액궁이 헐거운 상으로 읽었습니다.',
  ]),
  _Frag.hard((f) => true, [
    '관상에서 코는 재백궁이면서 질액궁이기도 합니다. 재물과 몸을 같은 자리에서 읽었다는 뜻입니다.',
    '관상 전통은 몸을 코 하나로 보지 않고 눈·눈썹·턱의 기운을 함께 놓고 읽었어요.',
    '예로부터 관상에서는 질액궁이 곧아도 얼굴에 핏기가 없으면 그 자리만으로 읽지 않았어요.',
  ]),
];

final List<_Frag> _v2HealthStrength = [
  _Frag.hard((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '코 항목의 측정값이 같은 성별·얼굴형 평균에서 뚜렷하게 벗어나 있어요. 관상서에서는 이 자리를 질액궁이라 하고, 산근이 곧게 선 얼굴을 몸의 기운이 막히지 않는 상으로 읽습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09'), [
    '눈 주변 항목의 값이 높게 측정됩니다. 관상서에서 눈은 사독 가운데 하(河)이고, 이 자리를 기운이 흐르는 통로로 봤어요.',
  ]),
  _Frag.hard((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '턱 항목의 값이 평균 위에 있습니다. 관상서에서 턱은 노복궁이고, 이 자리가 두터운 얼굴을 오래 버티는 힘이 있는 상이라 합니다.',
  ]),
  _Frag.hard((f) => f.fired('P-05') || f.nodeZ('glabella') >= 0.5, [
    '미간 항목의 값이 평균 위에 있어요. 관상서에서 미간은 명궁이라 하여 열두 자리 가운데 가장 먼저 보는 곳이고, 이 자리가 트인 얼굴을 기운이 맺히지 않은 상으로 읽어 왔어요.',
  ]),
  _Frag.hard((f) => f.fired('Z-04'), [
    '얼굴 아래 구역의 항목들이 고르게 높습니다. 전통 관상은 얼굴을 위·가운데·아래 세 구역으로 나누어 보았고, 아래가 두터운 얼굴을 뿌리가 있는 상이라 했습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정성 항목의 값이 높은 쪽입니다. 관상서에서는 얼굴빛과 눈의 기운이 몸 상태를 먼저 알린다고 보아, 이 자리를 살피는 것을 진찰의 일부로 여겼어요.',
  ]),
  _Frag.hard((f) => true, [
    '옛 관상서는 몸을 이마·산근·눈·턱 네 자리로 나누어 봅니다. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있습니다.',
    '관상서는 한 자리가 유독 튀는 얼굴보다 네 자리가 고른 얼굴을 몸에서는 더 좋게 보았어요.',
    '관상서에서는 얼굴빛을 자리의 모양보다 먼저 보았습니다. 모양은 타고나지만 빛은 그때그때 달라진다고 여겼기 때문이에요.',
    '관상서에서 미간은 명궁, 코는 질액궁입니다. 두 자리가 함께 트여 있으면 기운이 위아래로 통하는 상으로 읽었습니다.',
    '관상 전통은 질액궁의 크기보다 그 자리에 흠이 없는지를 먼저 봤어요.',
  ]),
];

final List<_Frag> _v2HealthShadow = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '다만 예로부터 관상에서는 버티는 힘과 감정의 기운이 함께 센 얼굴을 두고, 지쳐도 티가 늦게 난다고 했어요.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 산근이 얕은 얼굴을 두고 전통 관상은 한 번 무너지면 회복이 더디다고 봅니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 전통 관상은 버티는 힘이 센 상을 두고, 참는 것이 길어져 때를 놓치기 쉽다고도 합니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 눈의 기운이 센 얼굴을 두고 전통 관상은 마음의 기복이 몸으로 먼저 내려간다고 했습니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 옛 관상서는 질액궁 하나만 보고 판단하지 않았습니다. 얼굴빛과 눈의 기운을 함께 보지 않으면 그 자리만으로는 읽지 않았어요.',
    '다만 관상서는 얼굴의 모양보다 그날의 빛이 몸을 먼저 알린다고 했어요.',
    '다만 관상 전통은 자리가 좋아도 생활이 어지러우면 그 자리가 흐려진다고 보았어요.',
    '다만 예로부터 관상에서는 상은 마음에서 나온다 하여, 몸의 자리도 고정된 것으로 보지 않았습니다.',
    '다만 전통 관상은 몸을 한 시점으로 읽지 않고 늘 달라지는 것으로 보았습니다. 이 측정도 오늘의 값입니다.',
  ]),
];

final List<_Frag> _v2HealthAdvice = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '옛 관상서는 기운이 센 상에 오히려 덜어내는 쪽을 권합니다. 버틸 수 있다는 감각이 회복 시점을 늦추니, 피로를 느낀 날짜를 적어 두는 정도면 충분합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '관상서는 질액궁이 곧은 얼굴에 지금의 상태를 유지하는 쪽을 권했습니다. 수면 시각을 고정하는 것 하나가 가장 단순한 유지법이에요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '관상 전통은 안으로 눌러 두는 상에 밖으로 내보내는 통로를 하나 두라 했어요. 몸을 쓰는 운동이 그 통로 역할을 합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '예로부터 관상에서는 기운의 진폭이 큰 상에 하루의 시작과 끝을 같게 두라 합니다. 기상과 취침 시각을 고정하는 것이 그에 해당합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '전통 관상은 치우치지 않은 상을 두고 생활이 그대로 얼굴빛에 나타난다고 했습니다. 수면·식사 시각을 일정하게 두는 것만으로 대부분이 정리됩니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '옛 관상서는 표정이 적은 상에 몸의 신호를 말로 옮겨 두라 했어요. 어디가 어떻게 불편한지 적어 두면 진료에서 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '관상서는 산근이 얕고 기운이 센 상에 무리를 짧게 끊으라 합니다. 몰아서 쉬는 것보다 매일 조금씩 끊어 쉬는 쪽이 이 조언에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '관상 전통은 버티는 힘이 약한 상에 미리 정한 선을 두라 했습니다. 몇 시 이후에는 일을 잡지 않는 규칙 하나면 됩니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '예로부터 관상에서는 열두 자리 가운데 실한 곳을 찾아 그 자리를 쓰라고 했어요. 몸을 밀어붙이는 방식보다 회복 시간을 먼저 확보하는 순서가 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '전통 관상은 몸을 이마·산근·눈·턱 네 자리로 나누어 봤어요. 지금 가장 불편한 곳부터 살피는 순서가 가장 단순합니다.',
    '옛 관상서는 얼굴빛이 모양보다 먼저 달라진다고 합니다. 거울에서 낯빛이 달라졌다고 느낀 날을 적어 두면 그 자체가 기록이 됩니다.',
    '관상서는 상은 마음에서 나온다고 했습니다. 몸의 자리도 생활에 따라 달라진다고 본 것이고, 수면이 그 가운데 가장 크게 작동합니다.',
    '건강은 한 번의 결심보다 반복되는 습관에서 갈립니다. 수면 시각 고정, 주 3회 이상의 몸 쓰기, 정기 검진 세 가지면 충분합니다.',
    '관상 전통은 병을 얻은 뒤보다 얻기 전을 보려 했어요. 증상이 없을 때 받는 검진이 그 뜻에 가장 가깝습니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 회복이 빨라 무리의 대가가 늦게 옵니다. 이 시기에 만든 수면·식사 습관이 이후 20년의 기준선이 됩니다.',
    '20대에는 체력의 상한보다 회복의 속도를 기준으로 삼는 편이 낫습니다. 다음 날 남는 피로가 신호입니다.',
    '20대에 시작한 흡연·과음은 30대 후반에 값이 청구됩니다. 지금 끊는 비용이 가장 쌉니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 회복 속도가 눈에 띄게 달라지는 구간입니다. 같은 강도로 밀어붙이면 남는 피로가 쌓이에요.',
    '40대에는 정기 검진의 간격을 좁히는 편이 낫습니다. 이 구간부터는 증상보다 수치가 먼저 움직입니다.',
    '30~40대의 건강은 일의 총량보다 끊는 시각에서 갈립니다. 몇 시 이후에는 일을 잡지 않는 선을 정해 두세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 강도보다 꾸준함이 중요해집니다. 주 3회 이상 걷는 것이 대부분의 운동을 대신합니다.',
    '50대 이후에는 근육량과 균형 감각이 생활의 질을 크게 가릅니다. 가벼운 저항 운동을 일과에 넣어 두세요.',
    '60대 이후의 건강은 관계와 함께 볼 때만 유지됩니다. 사람을 만나는 일정이 곧 건강 일정입니다.',
  ]),
];

final List<_BeatPool> _v2HealthBeats = [
  _v2HealthOpening,
  _v2HealthVignette,
  _v2HealthStrength,
  _v2HealthShadow,
  _v2HealthAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 연애 — attractiveness × emotionality
//
// v1 은 opening·advice 도 남/여로 나눠 뒀지만 조건 집합이 완전히 같다.
// 측정 서술에서 성별로 문장이 달라질 근거가 없으므로 공용 풀로 합쳤고,
// 조건이 실제로 다른 strength·shadow 만 분리를 유지한다.
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2RomanceOpening = [
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.high), [
    '@{verdict:attractiveness} 감정성 항목도 함께 높게 나왔습니다. 예로부터 관상에서는 눈꼬리 자리를 처첩궁이라 하여 배우자 인연을 보는 곳으로 여겼고, 이 자리에 기운이 실린 얼굴을 사람이 모이는 상으로 읽었어요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 감정성은 평균대예요. 처첩궁이 도톰한 얼굴을 두고 전통 관상은 인연이 늦지 않은 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '@{verdict:attractiveness} 감정성은 낮은 쪽입니다. 전통 관상은 얼굴은 서 있으나 표정의 움직임이 적은 상을 두고, 다가오기는 쉬워도 가까워지기는 더디다고 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '@{verdict:emotionality} 매력도는 평균대입니다. 옛 관상서는 눈을 사독 가운데 하(河)라 하여 정이 흐르는 자리로 보았고, 이 자리가 강한 얼굴을 마음을 깊게 쓰는 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 감정성도 비슷한 자리에 있어요. 어느 자리도 유독 튀지 않은 얼굴을 두고 전통 관상은 관계가 급하게 오르내리지 않는 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '@{verdict:emotionality} 매력도는 평균대예요. 관상서는 표정의 결이 잔잔한 얼굴을 두고 속을 늦게 내보이는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '@{verdict:attractiveness} 대신 감정성은 높은 쪽입니다. 관상 전통은 첫눈보다 오래 볼수록 달라 보이는 상을 따로 두었고, 처첩궁은 시간이 지나며 드러난다고 했어요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 감정성은 평균대입니다. 예로부터 관상에서는 눈에 띄는 자리보다 흐트러지지 않은 자리를 관계에서 더 높게 봅니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '@{verdict:attractiveness} 감정성도 함께 아래쪽이에요. 전통 관상은 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 처첩궁보다 다른 자리에 무게가 실린 상입니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:attractiveness} 전통 관상은 눈꼬리 자리를 처첩궁이라 부르고 배우자 인연을 보는 곳으로 여깁니다.',
    '@{verdict:attractiveness} 전통 관상에서 눈은 처첩궁이면서 남녀궁이기도 하여, 짝과 자식을 같은 자리에서 읽습니다.',
    '@{verdict:attractiveness} 전통 관상은 눈썹을 형제궁이라 하여 곁에 두는 사람의 자리로 보았어요.',
  ]),
];

final List<_Frag> _v2RomanceVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '눈에 물기가 도는 얼굴을 두고 옛 관상서는 정이 오래 간다고 합니다.',
  ]),
  _Frag(_highOf(Attribute.attractiveness), [
    '옛 관상서는 처첩궁이 도톰한 얼굴을 두고 인연이 끊이지 않는다고 보았습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '관상서에서는 턱이 두터운 얼굴을 두고 한 사람 곁에 오래 머문다고 했습니다.',
  ]),
  _Frag.hard((f) => true, [
    '관상에서 눈은 처첩궁이면서 전택궁이기도 합니다. 짝과 사는 자리를 같은 곳에서 읽었다는 뜻입니다.',
    '관상서는 인연을 눈 하나로 보지 않고 눈썹·입·턱을 함께 놓고 읽어 왔어요.',
    '관상 전통은 처첩궁이 좋아도 명궁이 흐리면 그 자리만으로 읽지 않았어요.',
  ]),
];

final List<_Frag> _v2RomanceStrengthFemale = [
  _Frag.hard((f) => f.fired('P-08'), [
    '눈꼬리 자리의 측정값이 평균 위에 있습니다. 관상서에서는 이 자리를 처첩궁이라 하고, 어미가 매끄러운 얼굴을 인연이 순한 상으로 읽었습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '눈 항목의 값이 뚜렷하게 높습니다. 관상서에서 눈은 사독 가운데 하(河)이고, 이 자리를 정이 흐르는 통로로 봤어요.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '신뢰성 항목의 값이 높은 쪽이에요. 관상서에서는 이마와 눈이 함께 곧은 얼굴을 말과 행동이 어긋나지 않는 상으로 봅니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정성 항목의 값이 높게 측정됩니다. 눈의 기운이 센 얼굴을 두고 관상서는 상대의 기색을 먼저 알아본다고 했어요.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.5, [
    '입 항목의 값이 평균 위에 있어요. 관상서에서 입은 오관 가운데 출납관이고, 이 자리가 단정한 얼굴을 말이 새지 않는 상으로 읽었어요.',
  ]),
  _Frag.hard((f) => f.nodeZ('eye') >= 0.5, [
    '눈 항목의 값이 평균 위에 있습니다. 관상서에서는 눈을 감찰관이라 하여 살피고 가려내는 자리로도 보았어요.',
  ]),
  _Frag.hard((f) => true, [
    '예로부터 관상에서는 인연을 눈·눈썹·입·턱 네 자리로 나누어 보았습니다. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있어요.',
    '전통 관상은 처첩궁이 크게 두드러진 얼굴보다 네 자리가 고른 얼굴을 관계에서 더 좋게 봤어요.',
    '관상서에서 눈썹은 형제궁입니다. 이 자리가 고른 얼굴을 곁에 사람이 남는 상으로 읽습니다.',
  ]),
];

final List<_Frag> _v2RomanceStrengthMale = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹 항목의 측정값이 평균 위에 있습니다. 관상서에서는 눈썹을 형제궁이라 하고, 이 자리가 고른 얼굴을 곁에 사람이 남는 상으로 읽어 왔어요.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균 위에 있어요. 관상서에서 광대는 오악의 하나이고, 이 자리가 선 얼굴을 사람을 이끄는 힘이 있는 상이라 합니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '콧대 항목의 값이 뚜렷하게 높습니다. 관상서에서는 코를 심변관이라 하여 가려내는 자리로 보았고, 이 자리가 곧은 얼굴을 기준이 분명한 상으로 읽었습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '신뢰성 항목의 값이 높은 쪽입니다. 관상서에서는 이마와 눈이 함께 곧은 얼굴을 말과 행동이 어긋나지 않는 상으로 봅니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.wealth) == _Band.high || f.nodeZ('nose') >= 0.8, [
    '코 항목의 값이 평균 위에 있습니다. 관상서에서 코는 재백궁이고, 이 자리가 실한 얼굴을 살림을 맡을 만한 상으로 보았어요.',
  ]),
  _Frag.hard((f) => f.nodeZ('chin') >= 0.5, [
    '턱 항목의 값이 평균 위에 있어요. 관상서에서 턱은 노복궁이고, 이 자리가 두터운 얼굴을 한자리에 오래 머무는 상으로 읽었어요.',
  ]),
  _Frag.hard((f) => true, [
    '옛 관상서는 인연을 눈·눈썹·코·턱 네 자리로 나누어 보았습니다. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있습니다.',
    '관상서는 한 자리가 유독 튀는 얼굴보다 네 자리가 고른 얼굴을 관계에서 더 좋게 봤어요.',
    '관상서에서 눈은 처첩궁이면서 남녀궁이에요. 짝과 자식을 같은 자리에서 읽습니다.',
  ]),
];

final List<_Frag> _v2RomanceShadowFemale = [
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 관상 전통은 기운이 세고 턱이 받쳐 주지 않는 상을 두고, 마음이 한자리에 머물기 어렵다고 했습니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.high,
    [
      '다만 기운이 세면서 눌러 두는 상을 두고, 옛 관상서는 눌린 것이 한 번에 터지는 때가 있다고 봅니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 예로부터 관상에서는 처첩궁이 실하고 노복궁이 얇은 상을 두고, 인연이 잦되 오래 두기 어렵다고 했어요.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.emotionality) == _Band.high &&
        f.bandOf(Attribute.trustworthiness) != _Band.high,
    [
      '다만 눈의 기운이 센 상을 두고, 옛 관상서는 없는 기색까지 읽어 스스로를 지치게 한다고 합니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.high &&
        f.bandOf(Attribute.sociability) == _Band.low,
    [
      '다만 전통 관상은 지키는 힘은 세고 나서는 자리가 좁은 상을 두고, 좋은 인연이 곁을 지나가기 쉽다고 했습니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 옛 관상서는 처첩궁 하나만 보고 판단하지 않았습니다. 명궁과 노복궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았어요.',
    '다만 관상서는 인연을 자리의 모양보다 그때의 기색으로 먼저 보았어요.',
    '다만 관상 전통은 상은 마음에서 나온다 하여, 인연의 자리도 고정된 것으로 보지 않았습니다.',
  ]),
];

final List<_Frag> _v2RomanceShadowMale = [
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 기운이 세고 턱이 받쳐 주지 않는 상을 두고, 전통 관상은 마음이 한자리에 머물기 어렵다고 했어요.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.high,
    [
      '다만 예로부터 관상에서는 기운이 세면서 눌러 두는 상을 두고, 눌린 것이 한 번에 터지는 때가 있다고 보았습니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 처첩궁이 실하고 노복궁이 얇은 상을 두고, 전통 관상은 인연이 잦되 오래 두기 어렵다고 합니다.',
    ],
  ),
  _Frag(_highOf(Attribute.leadership), [
    '다만 전통 관상은 이끄는 힘이 센 상을 두고, 집 안에서까지 그 힘을 쓰면 곁이 멀어진다고 했습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.high &&
        f.bandOf(Attribute.sociability) != _Band.high,
    [
      '다만 지키는 힘은 세고 나서는 자리가 좁은 상을 두고, 전통 관상은 좋은 인연이 곁을 지나가기 쉽다고 했어요.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 옛 관상서는 처첩궁 하나만 보고 판단하지 않았어요. 명궁과 노복궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았습니다.',
    '다만 관상서는 인연을 자리의 모양보다 그때의 기색으로 먼저 봤어요.',
    '다만 관상 전통은 상은 마음에서 나온다 하여, 인연의 자리도 고정된 것으로 보지 않았어요.',
  ]),
];

final List<_Frag> _v2RomanceAdvice = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '예로부터 관상에서는 처첩궁이 실한 상에 시작보다 지키는 쪽을 권합니다. 만나는 수를 늘리는 것보다 한 관계에 들이는 시간을 늘리는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '전통 관상은 인연이 늦지 않은 상에 서두르지 말라 했습니다. 상대를 고르는 기준을 미리 적어 두면 그 조언이 실제로 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '옛 관상서는 다가오기는 쉬워도 가까워지기는 더딘 상에 먼저 말을 꺼내라 했어요. 표정보다 말이 빠른 통로입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '관상서는 정을 깊게 쓰는 상에 자기 몫을 남겨 두라 합니다. 상대의 기색을 읽는 만큼 자기 상태도 적어 두세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '관상 전통은 치우치지 않은 상을 두고 시간이 쌓이는 만큼 드러난다고 했습니다. 짧게 여럿을 보는 것보다 길게 겪는 자리가 이 구성에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '예로부터 관상에서는 속을 늦게 내보이는 상에 말로 옮기는 연습을 권했어요. 상대는 표정만으로 알아채지 못합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '전통 관상은 오래 볼수록 달라 보이는 상을 따로 두었습니다. 한 번에 결정되는 자리보다 여러 번 마주치는 자리에서 값이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '옛 관상서는 눈에 띄는 자리보다 흐트러지지 않은 자리를 관계에서 더 높게 봅니다. 꾸준히 나가는 모임 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '관상서는 열두 자리 가운데 실한 곳을 찾아 그 자리를 쓰라고 합니다. 처첩궁이 아니라면 형제궁 쪽, 곧 곁에 오래 남는 관계부터 넓히는 편이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '관상 전통은 인연을 눈·눈썹·입·턱 네 자리로 나누어 보았어요. 어느 자리가 실한지에 맞춰 만나는 방식을 고르는 편이 낫습니다.',
    '예로부터 관상에서는 처첩궁이 실해도 마음이 흐트러지면 그 자리가 흐려진다고 했습니다. 관계에서 가장 먼저 손볼 것은 상대가 아니라 자기 상태입니다.',
    '전통 관상은 한 번에 크게 얻는 것보다 흐트러지지 않는 쪽을 높게 보았습니다. 관계에서도 같은 기준이 적용됩니다.',
    '옛 관상서는 얼굴을 고정된 것으로 보지 않았습니다. 상은 마음에서 나온다는 말이 관상서 안에 함께 적혀 있어요.',
    '관상서는 혼사를 사람의 큰 갈림으로 봤어요. 그 앞에서는 평소의 열 배쯤 시간을 들여 겪어 보는 편이 낫습니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 사람을 고르는 기준 자체가 아직 만들어지는 중이에요. 맞지 않았던 이유를 적어 두면 그것이 기준이 됩니다.',
    '20대의 관계는 수보다 겪는 깊이에서 갈립니다. 짧게 여럿보다 한 번을 끝까지 겪어 보는 편이 남습니다.',
    '20대에는 상대의 조건보다 다투는 방식을 보세요. 그 방식이 오래 가는 쪽을 결정합니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대의 관계는 시간을 어떻게 쪼개는가에서 갈립니다. 일정에 먼저 자리를 잡아 두지 않으면 관계가 뒤로 밀립니다.',
    '이 구간에서는 새로 만나는 자리보다 이미 있는 관계의 밀도가 더 크게 작동합니다.',
    '30~40대에는 서로의 생활 습관이 감정보다 오래 갑니다. 함께 사는 방식을 먼저 맞춰 두세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 관계는 새로 만드는 것보다 남아 있는 것을 지키는 쪽이 중요합니다.',
    '50대 이후에는 말수보다 함께 보내는 시간의 총량이 관계를 결정합니다.',
    '60대 이후에는 관계가 곧 건강 조건이 됩니다. 사람을 만나는 일정을 비워 두지 마세요.',
  ]),
];

final List<_BeatPool> _v2RomanceBeatsFemale = [
  _v2RomanceOpening,
  _v2RomanceVignette,
  _v2RomanceStrengthFemale,
  _v2RomanceShadowFemale,
  _v2RomanceAdvice,
];

final List<_BeatPool> _v2RomanceBeatsMale = [
  _v2RomanceOpening,
  _v2RomanceVignette,
  _v2RomanceStrengthMale,
  _v2RomanceShadowMale,
  _v2RomanceAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 활력 — libido × sensuality
//
// v1 의 '관능도' 코퍼스를 엔진이 실제로 재는 것으로 되돌린다.
//   libido      = 9노드 가중합 = 에너지 총량  → 활력
//   sensuality  = 곁에 있으면 끌린다          → 흡인력
// 라벨만 바꾸고 본문이 성적 서사로 남으면 이름과 내용이 다시 어긋나므로,
// 문장을 에너지·흡인력 측정 서술로 다시 썼다. 조건은 v1 과 1:1.
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2VitalityOpening = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '@{verdict:libido} 흡인력 항목도 함께 높게 나왔습니다. 관상 전통은 눈을 남녀궁이라 하여 기운이 도는 자리로 보았고, 눈썹과 인중이 함께 뚜렷한 얼굴을 정기가 성한 상으로 읽어 왔어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 흡인력은 평균대입니다. 예로부터 관상에서는 눈썹이 짙고 인중이 또렷한 얼굴을 기운이 안에서 도는 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '@{verdict:libido} 흡인력은 낮은 쪽입니다. 전통 관상은 기운은 성한데 밖으로 드러나는 결이 적은 상을 따로 두었어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '@{verdict:sensuality} 활력은 평균대예요. 옛 관상서는 눈꼬리와 입가의 결이 뚜렷한 얼굴을 사람의 눈이 머무는 상으로 봅니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 흡인력도 비슷한 자리에 있습니다. 어느 자리도 유독 튀지 않은 얼굴을 두고 전통 관상은 기운이 고르게 도는 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '@{verdict:sensuality} 활력은 평균대입니다. 관상서는 결이 잔잔한 얼굴을 두고 안으로 두는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '@{verdict:libido} 대신 흡인력은 높은 쪽입니다. 관상 전통은 기운의 세기와 밖으로 드러나는 결을 다른 자리에서 읽었습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 흡인력은 평균대예요. 눈썹과 인중의 결이 옅은 얼굴을 두고 전통 관상은 기운을 아껴 쓰는 상이라 했어요.',
  ]),
  _Frag(_lowPair(Attribute.libido, Attribute.sensuality), [
    '@{verdict:libido} 흡인력도 함께 아래쪽입니다. 예로부터 관상에서는 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 남녀궁보다 다른 자리에 무게가 실린 상입니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:libido} 전통 관상은 눈을 남녀궁이라 부르고 기운이 도는 자리로 보았어요.',
    '@{verdict:libido} 전통 관상은 인중을 정기가 지나는 길목으로 여겼습니다.',
    '@{verdict:libido} 전통 관상에서 눈썹은 형제궁이면서 기운의 성쇠를 보는 자리이기도 합니다.',
  ]),
];

final List<_Frag> _v2VitalityVignette = [
  _Frag(_highOf(Attribute.sensuality), [
    '전통 관상은 눈꼬리와 입가의 결이 살아 있는 얼굴을 두고 사람의 눈이 오래 머문다고 했습니다.',
  ]),
  _Frag(_highOf(Attribute.libido), [
    '눈썹이 짙고 인중이 또렷한 얼굴을 두고 옛 관상서는 정기가 성하다고 보았습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.high,
    [
      '관상서에서는 기운은 잔잔한데 눈의 결이 깊은 얼굴을 두고 안으로 쓰는 상이라 했어요.',
    ],
  ),
  _Frag.hard((f) => true, [
    '관상에서 눈은 남녀궁이면서 처첩궁이기도 합니다. 기운과 인연을 같은 자리에서 읽었다는 뜻이에요.',
    '옛 관상서는 기운을 눈 하나로 보지 않고 눈썹·인중·입을 함께 놓고 읽었어요.',
    '관상서는 남녀궁이 성해도 얼굴빛이 흐리면 그 자리만으로 읽지 않았어요.',
  ]),
];

final List<_Frag> _v2VitalityStrength = [
  _Frag(_metHi('mouthCornerAngle'), [
    '입꼬리 항목의 값이 평균 위에 있어요. 관상서에서는 입꼬리가 올라간 입을 앙월구라 하여 기운이 밖으로 도는 상으로 읽습니다.',
  ]),
  _Frag(_metMid('mouthCornerAngle'), [
    '입꼬리 항목의 값이 평균대에 있습니다. 관상 전통은 입꼬리가 평평한 입을 두고 기색을 쉽게 드러내지 않는 상이라 합니다.',
  ]),
  _Frag(_metLo('mouthCornerAngle'), [
    '입꼬리 항목의 값이 평균 아래에 있어요. 관상서에서는 입꼬리가 내려간 입을 부월구라 하여 안으로 눌러 두는 상으로 봤어요.',
  ]),
  _Frag(_metHi('lipFullnessRatio'), [
    '입술 두께 항목의 값이 평균 위에 있습니다. 입술이 도톰한 얼굴을 두고 관상서는 정이 두터운 상이라 했습니다.',
  ]),
  _Frag(_metMid('lipFullnessRatio'), [
    '입술 두께 항목의 값이 평균대에 있어요. 관상서에서는 입술이 지나치지 않은 얼굴을 두고 절제가 서 있는 상으로 봅니다.',
  ]),
  _Frag(_metLo('lipFullnessRatio'), [
    '입술 두께 항목의 값이 평균 아래에 있습니다. 예로부터 관상에서는 입술이 얇은 얼굴을 두고 말과 정을 아껴 쓰는 상이라 했어요.',
  ]),
  _Frag(_metHi('upperVsLowerLipRatio'), [
    '윗입술이 아랫입술보다 두툼하게 측정됩니다. 관상서에서는 이런 입을 두고 먼저 마음을 내는 상이라 합니다.',
  ]),
  _Frag(_metLo('upperVsLowerLipRatio'), [
    '아랫입술이 윗입술보다 두툼하게 측정됩니다. 관상서에서는 이런 입을 두고 받는 쪽에 무게가 실린 상이라 했습니다.',
  ]),
  _Frag(_metHi('philtrumLength'), [
    '인중 항목의 값이 평균 위에 있어요. 인중이 길고 골이 뚜렷한 얼굴을 두고 관상서는 정기가 곧게 지난다고 보았어요.',
  ]),
  _Frag(_metMid('philtrumLength'), [
    '인중 항목의 값이 평균대에 있습니다. 관상서에서는 인중이 고른 얼굴을 두고 기운이 막히지 않은 상이라 했어요.',
  ]),
  _Frag(_metLo('philtrumLength'), [
    '인중 항목의 값이 평균 아래에 있어요. 전통 관상은 인중이 짧은 얼굴을 두고 기운이 빠르게 도는 상이라 합니다.',
  ]),
  _Frag(_metHi('eyeCanthalTilt'), [
    '눈꼬리 각도 항목의 값이 평균 위에 있습니다. 관상서에서는 눈꼬리가 올라간 눈을 기운이 선 상으로 읽어 왔어요.',
  ]),
  _Frag(_metLo('eyeCanthalTilt'), [
    '눈꼬리 각도 항목의 값이 평균 아래에 있어요. 눈꼬리가 내려간 눈을 두고 관상서는 사람을 눅이는 상이라 했습니다.',
  ]),
  _Frag(_metHi('eyeAspect'), [
    '눈의 세로 대 가로 비율이 평균 위에 있습니다. 관상서에서는 이런 눈을 원안이라 하여 마음이 밖으로 잘 드러나는 상으로 보았습니다.',
  ]),
  _Frag(_metLo('eyeAspect'), [
    '눈의 세로 대 가로 비율이 평균 아래에 있어요. 관상서에서는 이런 눈을 봉안이라 하여 속을 늦게 내보이는 상으로 읽었습니다.',
  ]),
  _Frag(_metHi('eyebrowThickness'), [
    '눈썹 두께 항목의 값이 평균 위에 있습니다. 관상서에서 눈썹은 형제궁이고, 짙은 눈썹을 기운이 성한 상으로 봤어요.',
  ]),
  _Frag(_metLo('eyebrowThickness'), [
    '눈썹 두께 항목의 값이 평균 아래에 있어요. 옛 관상서는 옅은 눈썹을 두고 기운을 안으로 두는 상이라 했어요.',
  ]),
  _Frag(_metHi('eyebrowCurvature'), [
    '눈썹 곡률 항목의 값이 평균 위에 있습니다. 관상서에서는 활처럼 굽은 눈썹을 만미라 하여 부드러운 결로 읽었어요.',
  ]),
  _Frag(_metLo('eyebrowCurvature'), [
    '눈썹 곡률 항목의 값이 평균 아래에 있어요. 관상서에서는 곧게 뻗은 눈썹을 직미라 하여 결이 굳은 상으로 봅니다.',
  ]),
  _Frag(_metHi('cheekboneWidth'), [
    '광대 폭 항목의 값이 평균 위에 있습니다. 관상서에서 광대는 오악의 하나이고, 이 자리가 선 얼굴을 기운이 밖으로 뻗는 상이라 합니다.',
  ]),
  _Frag(_metLo('cheekboneWidth'), [
    '광대 폭 항목의 값이 평균 아래에 있어요. 광대가 낮은 얼굴을 두고 관상서는 나서기보다 머무는 상이라 했습니다.',
  ]),
  _Frag(_metHi('nasolabialAngle'), [
    '코끝 각도 항목의 값이 평균 위에 있습니다. 관상서에서는 코끝이 들린 얼굴을 두고 기운이 위로 도는 상이라 했어요.',
  ]),
  _Frag(_metLo('nasolabialAngle'), [
    '코끝 각도 항목의 값이 평균 아래에 있어요. 관상서는 코끝이 내려앉은 얼굴을 두고 기운을 안으로 모으는 상이라 합니다.',
  ]),
  _Frag(_metHi('gonialAngle'), [
    '하악각 항목의 값이 평균 위에 있습니다. 관상서에서는 턱이 각진 얼굴을 두고 버티는 힘이 실린 상으로 보았어요.',
  ]),
  _Frag(_metLo('gonialAngle'), [
    '하악각 항목의 값이 평균 아래에 있어요. 턱선이 둥근 얼굴을 두고 관상서는 결이 부드러운 상이라 했습니다.',
  ]),
  _Frag(_metHi('faceAspectRatio'), [
    '얼굴 종횡비 항목의 값이 평균 위에 있습니다. 관상 전통은 세로로 긴 얼굴을 두고 기운이 위아래로 길게 도는 상이라 했어요.',
  ]),
  _Frag(_metLo('faceAspectRatio'), [
    '얼굴 종횡비 항목의 값이 평균 아래에 있어요. 관상서에서는 가로로 넓은 얼굴을 두고 기운이 옆으로 퍼지는 상으로 읽습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '눈 항목의 값이 뚜렷하게 높습니다. 관상서에서 눈은 사독 가운데 하(河)이고, 기운이 흐르는 통로로 보았습니다.',
  ]),
  _Frag.hard(_yangStrong, [
    '얼굴 전반의 결이 양 쪽으로 기울어 측정됩니다. 양의 결이 강한 얼굴을 두고 관상서는 밖으로 뻗는 기운이 앞선다고 합니다.',
  ]),
  _Frag.hard(_yinStrong, [
    '얼굴 전반의 결이 음 쪽으로 기울어 측정됩니다. 예로부터 관상에서는 음의 결이 강한 얼굴을 두고 안으로 모으는 기운이 앞선다고 했습니다.',
  ]),
  _Frag.hard(_yyHarmony, [
    '음과 양의 결이 고르게 측정됩니다. 두 결이 맞물린 얼굴을 두고 관상서는 기운이 한쪽으로 쏠리지 않는 상이라 했어요.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '인중 항목의 값이 평균에서 뚜렷하게 벗어나 있습니다. 전통 관상은 인중을 남녀궁과 이어진 자리로 보아 기운의 성쇠를 여기서 읽어 왔어요.',
  ]),
  _Frag.hard((f) => true, [
    '옛 관상서는 기운을 눈·눈썹·인중·입 네 자리로 나누어 봤어요. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있어요.',
    '관상서는 한 자리가 유독 튀는 얼굴보다 네 자리가 고른 얼굴을 기운에서는 더 좋게 봅니다.',
    '관상서에서는 자리의 모양보다 그날의 얼굴빛이 기운을 먼저 알린다고 합니다.',
  ]),
];

final List<_Frag> _v2VitalityShadowFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '다만 관상 전통은 기운과 결이 함께 성한 상을 두고, 밖으로 도는 만큼 안이 비기 쉽다고 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '다만 기운은 성한데 결이 드러나지 않는 상을 두고, 옛 관상서는 안에서 쌓이는 것이 있다고 보았어요.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '다만 예로부터 관상에서는 기운이 세고 턱이 받쳐 주지 않는 상을 두고, 쓰는 속도가 채우는 속도를 앞선다고 했어요.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '다만 기운과 결이 함께 서고 노복궁이 얇은 상을 두고, 옛 관상서는 자리가 자주 바뀐다고 보았습니다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '다만 전통 관상은 기운이 세면서 눌러 두는 상을 두고, 눌린 것이 한 번에 터지는 때가 있다고 합니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '다만 결은 뚜렷한데 기운이 잔잔한 상을 두고, 옛 관상서는 밖에서 보는 것과 안이 다르다고 했습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '다만 옛 관상서는 세 자리가 함께 잔잔한 상을 두고, 기운을 아껴 두었다가 늦게 쓰는 상이라 했어요.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '다만 기운은 고른데 결이 옅은 상을 두고, 옛 관상서는 먼저 다가가지 않으면 지나친다고 합니다.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '다만 관상서는 결과 정이 함께 깊은 상을 두고, 마음을 먼저 열어 자기가 지치기 쉽다고 했습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '다만 인중이 평균에서 크게 벗어난 상을 두고, 옛 관상서는 기운의 오르내림이 잦다고 봤어요.',
  ]),
  _Frag(_lowOf(Attribute.libido), [
    '다만 관상 전통은 기운이 잔잔한 상을 낮게 보지 않았고, 다만 몸을 돌보는 일이 뒤로 밀리기 쉽다고 했어요.',
  ]),
  _Frag.hard((f) => true, [
    '다만 예로부터 관상에서는 남녀궁 하나만 보고 판단하지 않았습니다. 명궁과 질액궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았어요.',
    '다만 전통 관상은 기운을 자리의 모양보다 그날의 빛으로 먼저 봅니다.',
    '다만 옛 관상서는 상은 마음에서 나온다 하여, 기운의 자리도 고정된 것으로 보지 않았습니다.',
  ]),
];

final List<_Frag> _v2VitalityShadowMale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '다만 관상서는 기운과 결이 함께 성한 상을 두고, 밖으로 도는 만큼 안이 비기 쉽다고 합니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '다만 기운은 성한데 결이 드러나지 않는 상을 두고, 옛 관상서는 안에서 쌓이는 것이 있다고 보았어요.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '다만 관상 전통은 기운이 세고 턱이 받쳐 주지 않는 상을 두고, 쓰는 속도가 채우는 속도를 앞선다고 했습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '다만 기운과 결이 함께 서고 노복궁이 얇은 상을 두고, 옛 관상서는 자리가 자주 바뀐다고 보았습니다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '다만 예로부터 관상에서는 기운이 세면서 눌러 두는 상을 두고, 눌린 것이 한 번에 터지는 때가 있다고 했어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '다만 결은 뚜렷한데 기운이 잔잔한 상을 두고, 옛 관상서는 밖에서 보는 것과 안이 다르다고 합니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '다만 전통 관상은 세 자리가 함께 잔잔한 상을 두고, 기운을 아껴 두었다가 늦게 쓰는 상이라 했습니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '다만 기운은 고른데 결이 옅은 상을 두고, 옛 관상서는 먼저 다가가지 않으면 지나친다고 했어요.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '다만 옛 관상서는 결과 정이 함께 깊은 상을 두고, 마음을 먼저 열어 자기가 지치기 쉽다고 합니다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '다만 인중이 평균에서 크게 벗어난 상을 두고, 옛 관상서는 기운의 오르내림이 잦다고 봤어요.',
  ]),
  _Frag.hard((f) => true, [
    '다만 관상서는 남녀궁 하나만 보고 판단하지 않았어요. 명궁과 질액궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았습니다.',
    '다만 관상 전통은 기운을 자리의 모양보다 그날의 빛으로 먼저 봅니다.',
    '다만 예로부터 관상에서는 상은 마음에서 나온다 하여, 기운의 자리도 고정된 것으로 보지 않았어요.',
  ]),
];

final List<_Frag> _v2VitalityAdvice = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '전통 관상은 기운이 성한 상에 쓰는 만큼 채우라 했습니다. 수면과 운동이 그 채우는 자리에 해당합니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.sensuality) != _Band.high,
    [
      '옛 관상서는 안에서 도는 기운이 센 상에 내보내는 통로를 두라 했어요. 몸을 쓰는 일과가 그 통로 역할을 합니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '관상서는 결이 뚜렷한 상에 스스로의 상태를 먼저 살피라 합니다. 밖에서 보이는 것과 안이 다를 수 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '관상 전통은 치우치지 않은 상을 두고 생활이 그대로 기운에 나타난다고 했습니다. 수면 시각을 고정하는 것이 가장 단순한 유지법입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '예로부터 관상에서는 결이 옅은 상에 먼저 다가가는 쪽을 권했어요. 기다리면 지나가는 자리가 있어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '전통 관상은 결은 서고 기운이 잔잔한 상에 체력을 먼저 채우라 합니다. 보이는 쪽보다 버티는 쪽이 먼저입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '옛 관상서는 기운을 아껴 쓰는 상에 쓰는 자리를 정해 두라 했습니다. 무엇에 쓸지 정하지 않으면 아낀 것이 남지 않습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) != _Band.low,
    [
      '관상서는 기운과 결은 잔잔한데 정이 깊은 상을 따로 둡니다. 사람을 오래 겪는 자리에서 값이 올라갑니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '관상 전통은 세 자리가 함께 잔잔한 상을 낮게 보지 않았습니다. 몸을 먼저 채우면 나머지가 따라온다고 했어요.',
    ],
  ),
  _Frag.hard((f) => true, [
    '예로부터 관상에서는 기운을 눈·눈썹·인중·입 네 자리로 나누어 보았어요. 어느 자리가 실한지에 맞춰 쓰는 곳을 고르는 편이 낫습니다.',
    '전통 관상은 기운이 성해도 생활이 어지러우면 그 자리가 흐려진다고 합니다. 수면이 가장 크게 작동합니다.',
    '옛 관상서는 얼굴을 고정된 것으로 보지 않았어요. 상은 마음에서 나온다는 말이 관상서 안에 함께 적혀 있습니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 회복 속도가 눈에 띄게 달라지는 구간이에요. 같은 강도로 밀어붙이면 남는 피로가 쌓입니다.',
    '이 구간의 기운은 총량보다 끊는 시각에서 갈립니다. 몇 시 이후에는 일을 잡지 않는 선을 정해 두세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 강도보다 꾸준함이 중요해집니다. 주 3회 이상 몸을 쓰는 일과가 대부분을 대신합니다.',
    '50대 이후에는 근육량과 수면의 질이 기운을 가장 크게 좌우합니다.',
  ]),
];

final List<_BeatPool> _v2VitalityBeatsFemale = [
  _v2VitalityOpening,
  _v2VitalityVignette,
  _v2VitalityStrength,
  _v2VitalityShadowFemale,
  _v2VitalityAdvice,
];

final List<_BeatPool> _v2VitalityBeatsMale = [
  _v2VitalityOpening,
  _v2VitalityVignette,
  _v2VitalityStrength,
  _v2VitalityShadowMale,
  _v2VitalityAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 대인관계 — sociability × trustworthiness
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2SocialOpening = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '@{verdict:sociability} 신뢰성 항목도 함께 높게 나왔습니다. 관상서는 입을 오관 가운데 출납관이라 하여 말이 드나드는 자리로 보았고, 이 자리가 단정하면서 이마가 곧은 얼굴을 말이 무게를 갖는 상으로 읽었습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 신뢰성은 평균대입니다. 입이 큰 얼굴을 두고 전통 관상은 사람이 모이는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '@{verdict:sociability} 신뢰성은 낮은 쪽이에요. 관상 전통은 말이 앞서고 이마가 받쳐 주지 않는 상을 따로 두었습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '@{verdict:trustworthiness} 사회성은 평균대입니다. 예로부터 관상에서는 이마를 관록궁이라 하여 이름이 서는 자리로 보았고, 이 자리가 곧은 얼굴을 말과 행동이 어긋나지 않는 상으로 읽었어요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 신뢰성도 비슷한 자리에 있어요. 전통 관상은 어느 자리도 유독 튀지 않은 얼굴을 두고 사람과의 거리가 급하게 오르내리지 않는 상이라 했어요.',
    '@{verdict:sociability} 전통 관상은 출납관이 순한 얼굴을 두고 말이 넘치지도 모자라지도 않은 상으로 보았습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '@{verdict:trustworthiness} 사회성은 평균대입니다. 이마가 좁은 얼굴을 두고 전통 관상은 말이 자리를 늦게 얻는 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '@{verdict:sociability} 대신 신뢰성은 높은 쪽이에요. 옛 관상서는 말수가 적고 이마가 곧은 얼굴을 두고 적게 말하되 그 말이 남는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 신뢰성은 평균대입니다. 관상서는 넓게 트는 자리보다 깊게 두는 자리를 따로 봤어요.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '@{verdict:sociability} 신뢰성도 함께 아래쪽입니다. 관상 전통은 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 출납관보다 다른 자리에 무게가 실린 상이에요.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:sociability} 전통 관상은 입을 출납관이라 부르고 말이 드나드는 자리로 봅니다.',
    '@{verdict:sociability} 전통 관상은 눈썹을 형제궁이라 하여 곁에 두는 사람의 자리로 여겼어요.',
    '@{verdict:sociability} 전통 관상에서 이마는 관록궁이면서 천이궁이라, 이름과 사람의 오감을 같은 자리에서 읽습니다.',
  ]),
];

final List<_Frag> _v2SocialVignette = [
  _Frag(_highOf(Attribute.trustworthiness), [
    '이마가 곧은 얼굴을 두고 옛 관상서는 말이 뒤집히지 않는다고 했어요.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '예로부터 관상에서는 눈에 기운이 실린 얼굴을 두고 상대의 기색을 먼저 알아본다고 보았어요.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '관상서에서는 턱이 두터운 얼굴을 두고 한자리에 오래 머문다고 합니다.',
  ]),
  _Frag(_lowOf(Attribute.sociability), [
    '입이 작은 얼굴을 두고 옛 관상서는 말을 아껴 쓰는 상이라 했습니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '전통 관상은 입이 큰 얼굴을 두고 사람이 모여드는 상으로 읽어 왔어요.',
  ]),
  _Frag.hard((f) => true, [
    '관상에서 입은 오관의 출납관이면서 사독 가운데 제(濟)이기도 합니다. 말과 재물이 함께 드나드는 자리로 보았다는 뜻입니다.',
    '옛 관상서는 사람됨을 입 하나로 보지 않고 이마·눈썹·눈을 함께 놓고 읽었습니다.',
    '관상서는 출납관이 좋아도 명궁이 흐리면 그 자리만으로 읽지 않았습니다.',
  ]),
];

final List<_Frag> _v2SocialStrength = [
  _Frag.hard((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입 주변 항목의 측정값이 평균 위에 있습니다. 관상서에서는 이 자리를 출납관이라 하고, 입매가 단정한 얼굴을 말이 새지 않는 상으로 읽었어요.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '콧대 항목의 값이 뚜렷하게 높습니다. 관상서에서 코는 심변관이고, 이 자리가 곧은 얼굴을 가려서 듣는 상으로 보았습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-SN'), [
    '코끝 항목의 값이 평균에서 벗어나 있어요. 코끝이 들린 얼굴을 두고 관상서는 먼저 말을 꺼내는 상이라 했어요.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.8, [
    '입 항목의 값이 높게 측정됩니다. 관상서에서 입은 사독 가운데 제(濟)이고, 이 자리가 큰 얼굴을 사람이 모이는 상으로 읽습니다.',
  ]),
  _Frag.hard((f) => f.fired('P-10') || f.nodeZ('eye') >= 0.8, [
    '눈 항목의 값이 평균 위에 있습니다. 관상서에서는 눈을 감찰관이라 하여 살피고 가려내는 자리로 봤어요.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹 항목의 값이 평균 위에 있어요. 관상서에서 눈썹은 형제궁이고, 이 자리가 고른 얼굴을 곁에 사람이 남는 상으로 읽어 왔어요.',
  ]),
  _Frag.hard((f) => true, [
    '관상 전통은 사람됨을 이마·눈썹·눈·입 네 자리로 나누어 봅니다. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있습니다.',
    '예로부터 관상에서는 한 자리가 유독 튀는 얼굴보다 네 자리가 고른 얼굴을 관계에서 더 좋게 보았어요.',
    '관상서에서 이마는 관록궁, 눈썹은 형제궁입니다. 두 자리가 함께 서 있으면 이름과 사람을 같은 길에서 얻는 상으로 읽었습니다.',
  ]),
];

final List<_Frag> _v2SocialShadow = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 전통 관상은 말이 서고 이름이 함께 선 상을 두고, 사람이 몰리는 만큼 자기 자리가 좁아진다고 합니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 옛 관상서는 두 자리가 함께 잔잔한 상을 낮게 보지 않았고, 다만 먼저 다가가지 않으면 지나친다고 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '다만 말이 앞서고 이마가 받쳐 주지 않는 상을 두고, 전통 관상은 한 말을 지키는 일이 뒤로 밀린다고 했어요.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 관상서는 눈의 기운이 센 얼굴을 두고, 없는 기색까지 읽어 스스로를 지치게 한다고 합니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 관상 전통은 출납관 하나만 보고 판단하지 않았어요. 관록궁과 형제궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았습니다.',
    '다만 예로부터 관상에서는 말의 많고 적음보다 그 말이 지켜지는지를 먼저 보았습니다.',
    '다만 전통 관상은 상은 마음에서 나온다 하여, 사람의 자리도 고정된 것으로 보지 않았어요.',
  ]),
];

final List<_Frag> _v2SocialAdvice = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '옛 관상서는 말과 이름이 함께 선 상에 넓히기보다 지키라 했습니다. 아는 사람을 늘리는 것보다 이미 있는 관계에 시간을 들이는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '관상서는 사람이 모이는 상에 한 말을 지키는 쪽을 권했어요. 약속한 것을 적어 두는 습관 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '관상 전통은 말이 앞서는 상에 먼저 듣고 뒤에 말하라 합니다. 자리에서 말하는 양을 절반으로 줄이는 것만으로 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '예로부터 관상에서는 이마가 곧은 상에 자기 이름을 걸 자리를 고르라 했습니다. 여러 자리보다 한 자리에서 오래 쌓는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '치우치지 않은 상을 두고 전통 관상은 시간이 쌓이는 만큼 드러난다고 했어요. 꾸준히 나가는 모임 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '전통 관상은 이름이 늦게 서는 상에 작은 약속부터 지키라 합니다. 큰 말보다 지킨 횟수가 자리를 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '옛 관상서는 적게 말하되 그 말이 남는 상을 따로 두었어요. 넓히려 애쓰기보다 몇 사람에게 깊게 두는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '관상서는 깊게 두는 자리를 넓게 트는 자리와 나누어 봤어요. 사람 수보다 겪는 시간을 기준으로 삼으세요.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '관상 전통은 열두 자리 가운데 실한 곳을 찾아 그 자리를 쓰라고 했습니다. 출납관이 아니라면 일이나 재능으로 먼저 알려지는 쪽이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '예로부터 관상에서는 사람됨을 이마·눈썹·눈·입 네 자리로 나누어 봅니다. 어느 자리가 실한지에 맞춰 관계를 넓히는 방식을 고르는 편이 낫습니다.',
    '전통 관상은 출납관이 좋아도 마음이 흐트러지면 그 자리가 흐려진다고 했어요. 관계에서 먼저 손볼 것은 상대가 아니라 자기 상태예요.',
    '옛 관상서는 말의 많고 적음보다 지켜지는지를 먼저 보았어요. 약속의 크기를 줄이고 지킨 횟수를 늘리는 쪽이 맞습니다.',
    '관상서는 얼굴을 고정된 것으로 보지 않았습니다. 상은 마음에서 나온다는 말이 관상서 안에 함께 적혀 있어요.',
    '관계는 한 번의 인상보다 반복되는 접촉에서 쌓입니다. 정기적으로 나가는 자리 하나를 정해 두세요.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 사람을 넓게 만나 두는 편이 낫습니다. 이때 만든 접점이 30대에 일의 통로가 됩니다.',
    '20대의 관계는 수보다 다시 만나는 횟수에서 갈립니다. 한 번 본 사람을 두 번 보는 데 시간을 쓰세요.',
    '20대에는 상대의 조건보다 곤란할 때의 태도를 보세요. 그것이 오래 갈 관계를 가릅니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대의 관계는 시간을 어떻게 쪼개는가에서 갈립니다. 일정에 먼저 자리를 잡아 두지 않으면 뒤로 밀립니다.',
    '이 구간에서는 새로 만나는 자리보다 이미 있는 관계의 밀도가 더 크게 작동합니다.',
    '30~40대에는 도움을 청하는 일이 관계를 넓힙니다. 혼자 해결하려 들수록 곁이 얇아집니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 새로 만드는 것보다 남아 있는 관계를 지키는 쪽이 중요합니다.',
    '50대 이후에는 먼저 연락하는 사람이 관계를 유지합니다. 순서를 기다리면 끊깁니다.',
    '60대 이후에는 관계가 곧 건강 조건이 됩니다. 사람을 만나는 일정을 비워 두지 마세요.',
  ]),
];

final List<_BeatPool> _v2SocialBeats = [
  _v2SocialOpening,
  _v2SocialVignette,
  _v2SocialStrength,
  _v2SocialShadow,
  _v2SocialAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 타고난 재능 — intelligence × leadership
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2TalentOpening = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '@{verdict:intelligence} 리더십 항목도 함께 높게 나왔습니다. 이마는 관상에서 관록궁이라 하여 이름과 자리가 서는 곳으로 보았고, 이 자리가 넓으면서 턱이 받쳐 주는 얼굴을 앞에 서는 상으로 읽었어요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 리더십은 평균대입니다. 관상 전통은 이마가 넓고 반듯한 얼굴을 두고 먼저 헤아리는 상이라 합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '@{verdict:intelligence} 리더십은 낮은 쪽이에요. 이마는 서고 턱이 얇은 상을 두고, 전통 관상은 헤아리기는 하되 앞에 나서지는 않는다고 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '@{verdict:leadership} 통찰력은 평균대입니다. 예로부터 관상에서는 턱과 광대가 함께 선 얼굴을 두고 사람을 이끄는 힘이 실린 상이라 했어요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 리더십도 비슷한 자리에 있습니다. 어느 자리도 유독 튀지 않은 얼굴을 두고 전통 관상은 재주가 한쪽으로 몰리지 않은 상이라 합니다.',
    '@{verdict:intelligence} 전통 관상은 관록궁이 순한 얼굴을 두고 자리가 천천히 서는 상으로 보았습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '@{verdict:leadership} 통찰력은 평균대입니다. 전통 관상은 턱이 얇은 얼굴을 두고 뒤에서 받치는 자리가 맞는 상이라 했습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '@{verdict:intelligence} 대신 리더십은 높은 쪽이에요. 옛 관상서는 헤아리는 자리와 이끄는 자리를 나누어 보았고, 이 얼굴은 뒤쪽에 무게가 실려 있어요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 리더십은 평균대입니다. 이마보다 아래 자리가 발달한 얼굴을 두고 전통 관상은 머리보다 손과 발이 앞서는 상이라 했어요.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '@{verdict:intelligence} 리더십도 함께 아래쪽입니다. 관상서는 열두 자리 가운데 어디가 실한지를 보았지 총합을 매기지 않았고, 이 얼굴은 관록궁보다 다른 자리에 무게가 실린 상이에요.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:intelligence} 전통 관상은 이마를 관록궁이라 부르고 이름과 자리가 서는 곳으로 봤어요.',
    '@{verdict:intelligence} 전통 관상은 이마를 삼정 가운데 위 구역으로 두고 타고난 바탕을 여기서 읽습니다.',
    '@{verdict:intelligence} 전통 관상에서 이마는 관록궁이면서 천이궁이라, 이름과 옮겨 다님을 같은 자리에서 봅니다.',
  ]),
];

final List<_Frag> _v2TalentVignette = [
  _Frag(_highOf(Attribute.intelligence), [
    '관상 전통은 이마가 넓고 반듯한 얼굴을 두고 배운 것이 오래 남는다고 합니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '턱과 광대가 함께 선 얼굴을 두고 옛 관상서는 사람이 따르는 상이라 보았어요.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.high &&
        f.bandOf(Attribute.leadership) == _Band.low,
    [
      '관상서에서는 이마는 서고 턱이 얇은 얼굴을 두고 헤아리는 자리가 앞선 상이라 했습니다.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '예로부터 관상에서는 턱이 얇은 얼굴을 두고 시작한 것을 끝까지 두기 어렵다고 했어요.',
  ]),
  _Frag.hard((f) => true, [
    '관상에서 이마는 관록궁이면서 천이궁이기도 합니다. 이름과 자리 옮김을 같은 곳에서 읽었다는 뜻입니다.',
    '전통 관상은 재주를 이마 하나로 보지 않고 눈썹·눈·턱을 함께 놓고 읽어 왔어요.',
    '옛 관상서는 관록궁이 넓어도 명궁이 흐리면 그 자리만으로 읽지 않았어요.',
  ]),
];

final List<_Frag> _v2TalentStrength = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹 항목의 측정값이 평균 위에 있습니다. 관상서에서 눈썹은 형제궁이면서 기운의 결을 보는 자리이고, 이 자리가 뚜렷한 얼굴을 뜻이 분명한 상으로 읽었습니다.',
  ]),
  _Frag.hard((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '이마 항목의 값이 뚜렷하게 높습니다. 관상서에서는 이 자리를 관록궁이라 하고, 넓고 반듯한 이마를 배움이 쌓이는 상으로 보았습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM'), [
    '눈과 입 항목의 값이 함께 높습니다. 관상서에서 눈은 감찰관, 입은 출납관이라 살피는 자리와 내놓는 자리로 나누어 봤어요.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균 위에 있어요. 관상서에서 광대는 오악의 하나이고, 이 자리가 선 얼굴을 사람을 움직이는 힘이 있는 상이라 합니다.',
  ]),
  _Frag.hard((f) => f.fired('O-FB'), [
    '이마와 눈썹 항목이 함께 높게 측정됩니다. 두 자리가 같이 선 얼굴을 두고 관상서는 뜻과 배움이 한 방향으로 간다고 봅니다.',
  ]),
  _Frag.hard((f) => f.nodeAZ('nose') >= 1.0, [
    '코 항목의 값이 평균에서 뚜렷하게 벗어나 있습니다. 관상서에서 코는 심변관이고, 이 자리가 두드러진 얼굴을 가려내는 힘이 강한 상으로 읽었어요.',
  ]),
  _Frag.hard((f) => f.fired('A-02'), [
    '얼굴 위 구역의 항목들이 고르게 높습니다. 관상서는 얼굴을 위·가운데·아래 세 구역으로 나누어 보았고, 위가 고른 얼굴을 바탕이 서 있는 상이라 했습니다.',
  ]),
  _Frag.hard((f) => true, [
    '관상 전통은 재주를 이마·눈썹·눈·턱 네 자리로 나누어 보았어요. 이 얼굴은 그 가운데 여러 자리가 평균 부근에 고르게 놓여 있어요.',
    '예로부터 관상에서는 한 자리가 유독 튀는 얼굴보다 네 자리가 고른 얼굴을 재주에서는 더 좋게 보았습니다.',
    '관상서에서 이마는 관록궁, 턱은 노복궁입니다. 두 자리가 함께 서 있으면 세운 뜻을 끝까지 두는 상으로 읽습니다.',
  ]),
];

final List<_Frag> _v2TalentShadow = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '다만 전통 관상은 헤아림과 이끄는 힘이 함께 센 상을 두고, 남의 속도를 기다리기 어렵다고 했어요.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.high &&
        f.bandOf(Attribute.leadership) == _Band.low,
    [
      '다만 이마는 서고 턱이 얇은 상을 두고, 옛 관상서는 아는 것이 자리로 이어지기까지 시간이 걸린다고 합니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.low &&
        f.bandOf(Attribute.leadership) == _Band.high,
    [
      '다만 옛 관상서는 이끄는 힘이 앞서고 헤아림이 뒤따르는 상을 두고, 먼저 움직이고 나중에 살핀다고 했습니다.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '다만 턱이 얇은 상을 두고 옛 관상서는 시작한 것을 끝까지 두기 어렵다고 했어요.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.emotionality) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 관상서는 눈의 기운이 세고 턱이 받쳐 주지 않는 상을 두고, 마음이 일보다 먼저 움직인다고 합니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 관상 전통은 관록궁 하나만 보고 판단하지 않았습니다. 명궁과 노복궁이 받쳐 주지 않으면 그 자리만으로는 읽지 않았어요.',
    '다만 예로부터 관상에서는 타고난 바탕보다 그것을 쓰는 결을 먼저 봤어요.',
    '다만 전통 관상은 상은 마음에서 나온다 하여, 재주의 자리도 고정된 것으로 보지 않았습니다.',
  ]),
];

final List<_Frag> _v2TalentAdvice = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '옛 관상서는 헤아림과 이끄는 힘이 함께 선 상에 자리를 맡으라 했습니다. 혼자 하는 일보다 사람을 데리고 하는 일에서 값이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '관상서는 이마가 선 상에 깊게 파는 쪽을 권했어요. 여러 갈래보다 한 갈래에서 오래 쌓는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '관상 전통은 아는 것이 자리로 늦게 이어지는 상에 밖으로 내보이라 합니다. 쌓은 것을 글이나 말로 정리해 두는 일이 그에 해당합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '예로부터 관상에서는 이끄는 힘이 앞선 상에 먼저 듣고 뒤에 정하라 했습니다. 결정 전에 반대 의견을 하나 이상 듣는 규칙이 그 역할을 합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '치우치지 않은 상을 두고 전통 관상은 무엇을 잡느냐가 그대로 드러난다고 했어요. 한 분야를 3년 단위로 잡아 두세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '전통 관상은 뒤에서 받치는 자리가 맞는 상을 따로 둡니다. 앞에 서는 자리를 억지로 잡기보다 대체 불가한 기술을 하나 두는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '옛 관상서는 먼저 움직이는 상에 사람을 두라 합니다. 헤아리는 사람을 곁에 두면 그 자리가 채워집니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '관상서는 머리보다 손과 발이 앞서는 상을 두고 몸으로 익히는 쪽을 권했습니다. 책보다 현장에서 값이 올라갑니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '관상 전통은 열두 자리 가운데 실한 곳을 찾아 그 자리를 쓰라고 했어요. 관록궁이 아니라면 손재주나 관계 쪽을 중심에 두는 편이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '예로부터 관상에서는 재주를 이마·눈썹·눈·턱 네 자리로 나누어 봅니다. 어느 자리가 실한지에 맞춰 일을 고르는 편이 낫습니다.',
    '전통 관상은 바탕보다 그것을 쓰는 결을 먼저 보았어요. 무엇을 아느냐보다 무엇에 오래 매달렸느냐가 남습니다.',
    '옛 관상서는 얼굴을 고정된 것으로 보지 않았어요. 상은 마음에서 나온다는 말이 관상서 안에 함께 적혀 있습니다.',
    '재능은 한 번의 성취보다 반복되는 시간에서 드러납니다. 한 분야에 3년을 넣어 보면 대부분 답이 나옵니다.',
    '관상서는 직업을 사람의 큰 갈림으로 보았습니다. 그 앞에서는 평소의 열 배쯤 시간을 들여 알아보는 편이 낫습니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 한 분야에 일찍 갇히지 않는 편이 낫습니다. 두세 갈래를 겪어 본 사람이 30대에 자기 기울기를 먼저 찾습니다.',
    '20대의 재능은 남과 비교해서 알 수 없습니다. 무엇에 시간을 써도 안 지치는지를 기준으로 삼으세요.',
    '20대에는 결과보다 몰입한 시간의 총량이 남습니다. 잘하는 것보다 오래 붙어 있는 것을 보세요.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 한 분야에서 충분히 깊어진 뒤 그 깊이로 다른 분야에 발판을 만드는 순서가 맞습니다.',
    '이 구간에서는 새로 배우는 것보다 아는 것을 남에게 넘겨 주는 일이 값을 키웁니다.',
    '30~40대에는 혼자 하는 일에서 사람을 데리고 하는 일로 옮겨 가는 준비가 필요합니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 새로 쌓기보다 쌓은 것을 넘겨 주는 쪽이 값이 큽니다.',
    '50대 이후에는 속도보다 판단의 정확도가 자산이 됩니다. 겪은 사례를 정리해 두세요.',
    '60대 이후의 재능은 사람을 통해서만 이어집니다. 가르치는 자리를 하나 두세요.',
  ]),
];

final List<_BeatPool> _v2TalentBeats = [
  _v2TalentOpening,
  _v2TalentVignette,
  _v2TalentStrength,
  _v2TalentShadow,
  _v2TalentAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 종합 조언
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2ConcludeOpening = [
  _Frag.hard(_yangStrong, [
    "전체 측정에서 양의 축이 뚜렷하게 앞섭니다. '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 얹혀 있고, 전통 관상은 이런 얼굴을 밖으로 뻗는 기운이 앞선 상으로 읽었습니다.",
  ]),
  _Frag.hard(_yinStrong, [
    "전체 측정에서 음의 축이 뚜렷하게 앞섭니다. '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 흐르고, 전통 관상은 이런 얼굴을 안으로 모으는 기운이 앞선 상이라 했습니다.",
  ]),
  _Frag.hard(_yyHarmony, [
    "음과 양의 축이 고르게 측정됩니다. '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 겹쳐 있고, 전통 관상은 두 결이 맞물린 얼굴을 한쪽으로 쏠리지 않는 상으로 보았습니다.",
  ]),
  _Frag.hard((f) => f.specialArchetype != null, [
    "여러 영역을 한 장으로 모으면 '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 겹쳐 흐릅니다. 여기에 '@__SPECIAL_ARCHETYPE__'이 같이 측정되는데, 같은 성별·얼굴형 분포에서 흔하게 나오는 조합은 아닙니다.",
  ]),
  _Frag.hard((f) => true, [
    "여러 영역을 한 장으로 모으면 '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐릅니다. 전통 관상은 얼굴 전체를 상모궁이라 하여 열두 자리를 다 본 뒤 마지막에 한 번 더 통으로 읽었습니다.",
    "'@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 얼굴에 겹쳐 측정됩니다. 전통 관상은 한 자리만 보고 사람을 정하지 않았고, 자리끼리의 어울림을 마지막에 보았습니다.",
  ]),
];

final List<_Frag> _v2ConcludeStage = [
  _Frag.hard((f) => f.age.isOver50, [
    '관상 전통은 미간을 명궁이라 하여 열두 자리 가운데 가장 먼저이자 마지막에 보는 곳으로 두었습니다. 지금 구간에서는 쌓는 일보다 남길 것과 흘려보낼 것을 가르는 판단이 중심에 놓이에요.',
  ]),
  _Frag.hard((f) => f.age.isOver30 && !f.age.isOver50, [
    '예로부터 관상에서는 미간을 명궁이라 하여 열두 자리를 다 본 뒤 마지막에 한 번 더 살폈습니다. 자리 하나가 아니라 자리들이 서로 어떻게 놓였는지를 마지막에 보았다는 뜻입니다.',
  ]),
  _Frag.hard((f) => f.age.isOver20 && !f.age.isOver30, [
    '전통 관상은 미간을 명궁이라 하여 그 사람의 중심을 보는 자리로 두었어요. 지금 구간에서는 답을 서둘러 찾기보다 자기 질문을 또렷이 세우는 일이 먼저입니다.',
  ]),
  _Frag.hard((f) => !f.age.isOver20, [
    '어린 얼굴을 두고 전통 관상은 아직 자리가 굳지 않았다고 봤어요. 지금 구간에서는 겪는 폭이 그대로 다음 구간의 깊이가 됩니다.',
  ]),
];

final List<_Frag> _v2ConcludeAdvice = [
  _Frag.hard((f) => true, [
    '마지막으로 짚어 둘 게 있어요. 이 리포트는 두 가지만 말합니다. 하나는 얼굴 계측값이 같은 성별·얼굴형 분포 11,800명 가운데 어디에 놓이는지이고, 다른 하나는 전통 관상이 그 자리를 어떻게 읽어 왔는지예요. 앞일을 맞히려 한 것이 아니고, 전통의 해석이 맞다고 주장하지도 않습니다. 옛 관상서도 상은 마음에서 나온다 하여 얼굴을 고정된 것으로 보지 않았습니다.',
  ]),
];

final List<_Frag> _v2ConcludeOneLiner = [
  _Frag.hard((f) => true, [
    '한 줄로 줄이면 — @__ONELINER__',
    '한마디로 @__ONELINER__',
    '굳이 한 줄로 요약하면, @__ONELINER__',
  ]),
];

final List<_BeatPool> _v2ConclusionBeats = [
  _v2ConcludeOpening,
  _v2ConcludeStage,
  _v2ConcludeAdvice,
  _v2ConcludeOneLiner,
];

// ═══════════════════════════════════════════════════════════════════════
// v2 섹션 정의 — 전 섹션 v2 코퍼스.
// ═══════════════════════════════════════════════════════════════════════

final List<_SectionDef> _v2Sections = [
  (title: '타고난 재능', salt: 10, pools: (f) => _v2TalentBeats, when: null),
  (title: '건강', salt: 70, pools: (f) => _v2HealthBeats, when: null),
  (title: '재력', salt: 20, pools: (f) => _v2WealthBeats, when: null),
  (title: '대인관계', salt: 30, pools: (f) => _v2SocialBeats, when: null),
  (
    title: '연애',
    salt: 40,
    pools: (f) => f.isMale ? _v2RomanceBeatsMale : _v2RomanceBeatsFemale,
    when: null,
  ),
  (
    title: '활력',
    salt: 60,
    pools: (f) => f.isMale ? _v2VitalityBeatsMale : _v2VitalityBeatsFemale,
    when: (f) => f.age.isOver30,
  ),
  (title: '종합 조언', salt: 80, pools: (f) => _v2ConclusionBeats, when: null),
];
