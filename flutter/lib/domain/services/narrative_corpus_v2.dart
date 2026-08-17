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
// 재현하거나 관상 문헌을 반박해야 한다.
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

// ─────────────────────────────────────────────────────────────────────
// 재력 — 세 박자: 결론 / 전통 해석 / 조언
//
// v2 초판은 도입·삽화·강점·그늘·조언 다섯 조각을 따로 뽑아 이어 붙였다.
// 조각마다 홀로 서야 해서 전통을 다시 소개하고 부위를 다시 설명했고,
// 결과가 지식 나열이 됐다. 세 박자로 줄이고 역할을 나눈다.
//
//   Lead     결론 먼저. 근거는 한두 개만. 전통은 언급하지 않는다.
//   Reading  전통 해석을 여기서 한 번만. 이어서 요즘 말로 풀고, 주의를 붙인다.
//   Advice   짧게. 오늘 할 수 있는 행동 하나.
// ─────────────────────────────────────────────────────────────────────

final List<_Frag> _v2WealthLead = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '@{verdict:wealth} 코와 턱이 함께 두툼합니다. 버는 힘과 지키는 힘 중 한쪽만 도드라지지 않았습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 콧대가 곧고 콧방울이 도톰합니다. 기회를 먼저 알아보는 얼굴입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '@{verdict:wealth} 다만 턱이 얇습니다. 들어오는 폭이 큰 만큼 나가는 폭도 큽니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '@{verdict:stability} 코보다 턱이 발달했습니다. 새로 만드는 쪽보다 이미 가진 것을 지키는 쪽이 강합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 코와 턱이 어느 쪽으로도 치우치지 않았습니다.',
    '@{verdict:wealth} 얼굴에서 돈과 관련된 자리가 고르게 나왔습니다. 한 번에 크게 갈리는 구성은 아닙니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '@{verdict:stability} 턱이 얇은 편입니다. 마음이 자주 옮겨 앉습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '@{verdict:wealth} 대신 턱이 단단합니다. 크게 벌지는 못해도 잃지도 않는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '@{verdict:wealth} 콧방울이 얇습니다. 돈보다 다른 데 무게가 실린 얼굴입니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '@{verdict:wealth} 코도 턱도 두드러지지 않았습니다. 돈이 이 얼굴의 중심축은 아닙니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:wealth} 판단의 근거는 콧대의 곧기와 콧방울의 두께입니다.',
    '@{verdict:wealth} 코 하나가 아니라 이마·광대·턱까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2WealthReading = [
  _Frag.hard((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '전통 관상에서 코는 재물이 드나드는 자리입니다. 콧대가 곧고 콧방울이 두툼하면 들어온 것이 쉽게 빠져나가지 않는다고 봤습니다. '
        '요즘 말로 하면 버는 재주보다 관리하는 습관이 성과를 만드는 쪽입니다. '
        '다만 쥐는 힘이 세면 내놓아야 할 때를 놓치기 쉽습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대가 평균보다 섰습니다. 옛사람들은 이 자리를 사람을 움직이는 힘으로 봤습니다. '
        '혼자 벌기보다 사람을 통해 판을 넓히는 쪽이라는 이야기입니다. '
        '다만 나서는 힘이 앞서면 정작 챙길 것을 놓칩니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '턱이 두툼합니다. 전통 관상은 이 자리를 한번 잡은 것을 놓지 않는 힘으로 읽었습니다. '
        '오래 다니고, 오래 모으고, 오래 버티는 쪽에 유리합니다. '
        '대신 판을 갈아타야 할 때 늦습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입이 함께 발달했습니다. 옛 관상에서는 코를 들어오는 자리, 입을 나가는 자리로 나눠 봤습니다. '
        '둘 다 크면 수입도 지출도 큽니다. '
        '문제는 액수가 아니라 두 폭의 차이입니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '콧방울이 얇은 편입니다. 전통 관상은 이런 얼굴을 두고 재물이 머무는 자리가 헐겁다고 했습니다. '
        '다만 같은 문헌이 코 하나로 돈을 판단하지 말라고도 적어 뒀습니다. '
        '이마·광대·턱이 받쳐 주면 이야기가 달라집니다.',
  ]),
  _Frag.hard((f) => true, [
    '전통 관상은 돈을 이마·코·광대·턱 네 자리로 나눠 봤습니다. 총점을 매기는 대신 어느 자리가 실한지를 따로 본 것입니다. '
        '이 얼굴에서는 그중 코가 기준선이 됩니다.',
    '옛사람들은 코가 홀로 큰 얼굴보다 이마와 턱이 받쳐 주는 얼굴을 높게 봤습니다. '
        '한 군데가 튀는 것보다 여러 군데가 고른 쪽이 오래간다고 본 것입니다.',
    '전통 관상에서 코는 재물을 보는 자리이면서 판단을 보는 자리이기도 합니다. '
        '돈이 걸린 일에서 사람을 가려내는 눈이 함께 움직인다고 본 셈입니다.',
  ]),
];

final List<_Frag> _v2WealthAdvice = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '불리는 것보다 흩어지지 않게 두는 쪽이 맞습니다. 매달 자동으로 쌓이는 액수를 기준으로 삼으세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '좋을 때 규모를 키우지 않는 것이 이 구성의 핵심입니다. 발을 빼는 시점을 미리 정해 두세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '버는 자리보다 담는 자리를 먼저 손봐야 합니다. 손이 닿지 않는 계좌로 자동 이체를 걸어 두세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '짧게 끊기보다 길게 묶는 쪽이 맞습니다. 5년 단위로 설계를 잡아 두세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '이 구성에서는 습관이 곧 결과입니다. 고정 저축을 수입의 25% 이상으로 자동화해 두세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '큰 결정은 하루 묵히세요. 24시간 규칙 하나면 대부분의 낙차가 줄어듭니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '한자리를 오래 지키는 쪽이 유리합니다. 버는 기술보다 안 쓰는 기준에 시간을 들이세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '이 구성에서는 자동 이체 저축의 효과가 가장 단순하게 나타납니다. 액수보다 끊기지 않는 것이 중요합니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '돈을 중심에 두지 않는 편이 낫습니다. 재능·관계·경험 쪽을 먼저 쌓고 돈은 따라오게 두세요.',
  ]),
  _Frag.hard((f) => true, [
    '값이 가장 낮은 자리부터 손보는 순서가 가장 단순합니다.',
    '감정이 올라온 구간의 결정을 미루는 규칙 하나가 가장 크게 작동합니다.',
    '큰 베팅 한 번보다 매달 도는 고정 저축이 이 구성에 맞습니다.',
    '집·직업·혼사 앞에서는 평소의 열 배쯤 시간을 들여 알아보세요.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 수입원을 한 갈래로 좁히지 마세요. 두세 갈래를 겪어 본 사람이 30대에 자기 기울기를 먼저 찾습니다.',
    '20대에 자동 저축을 수입의 30% 이상으로 잡아 두면 30대 초반에 복리가 작동합니다.',
    '20대의 돈은 버는 기술보다 안 쓰는 기준에서 갈립니다. 카테고리별 한도를 먼저 정해 두세요.',
  ]),
  _Frag.hard(_isMid, [
    '한 분야에서 충분히 깊어진 뒤 그 깊이로 다른 분야에 발판을 만드세요. 순서가 반대면 둘 다 얕아집니다.',
    '한 번의 성과를 그대로 두 번째 베팅으로 가져가면 낙차가 커집니다. 이 구간에서는 보수적인 배분이 낫습니다.',
    '자기 노동으로만 버는 구조에서 시스템이 버는 구조로 옮겨 갈 준비를 시작할 때입니다.',
  ]),
  _Frag.hard(_isLate, [
    '쌓는 쪽보다 흘려보내는 쪽의 설계가 중요해집니다. 증여·기부·투자 비율을 미리 정해 두세요.',
    '수익률보다 분산·유동성·상속 구조를 정비할 때입니다. 큰 결정은 가족·전문가와 공유하세요.',
    '이 나이의 돈은 건강·관계와 함께 볼 때만 의미가 있습니다.',
  ]),
];

final List<_BeatPool> _v2WealthBeats = [
  _v2WealthLead,
  _v2WealthReading,
  _v2WealthAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 건강 — stability × emotionality
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2HealthLead = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '@{verdict:stability} 콧대 위쪽이 곧고 눈에 물기가 돕니다. 몸의 기운이 잘 도는 얼굴입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 콧대 위쪽이 곧게 섰습니다. 컨디션이 크게 오르내리지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '@{verdict:stability} 표정의 진폭이 작습니다. 힘든 것을 안으로 눌러 두는 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '@{verdict:emotionality} 눈의 기운이 셉니다. 몸보다 마음이 먼저 반응합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 몸과 관련된 자리가 어느 쪽으로도 치우치지 않았습니다.',
    '@{verdict:stability} 크게 앓지도, 크게 넘치지도 않는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '@{verdict:emotionality} 표정의 움직임이 적습니다. 속을 밖으로 잘 내지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '@{verdict:stability} 대신 눈의 기운은 셉니다. 기복이 몸에 먼저 나타납니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '@{verdict:stability} 턱과 콧대 위쪽이 얇습니다. 버티는 힘보다 흐르는 힘이 앞섭니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '@{verdict:stability} 몸과 관련된 자리가 전반적으로 낮게 나왔습니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:stability} 판단의 근거는 콧대 위쪽의 곧기와 턱의 두께입니다.',
    '@{verdict:stability} 코 하나가 아니라 눈·눈썹·턱까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2HealthReading = [
  _Frag.hard((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '전통 관상에서 코는 재물뿐 아니라 몸을 보는 자리이기도 합니다. 콧대 위쪽이 곧으면 기운이 막히지 않는다고 봤습니다. '
        '요즘 말로 하면 회복이 빠른 쪽입니다. '
        '다만 버틸 수 있다는 감각 때문에 쉬어야 할 때를 놓칩니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '눈과 눈썹이 함께 강합니다. 옛사람들은 몸 상태가 얼굴빛과 눈에 먼저 드러난다고 봤고, 그래서 이 자리를 진찰의 일부로 여겼습니다. '
        '실제로도 이런 구성은 피로가 표정에 먼저 나타납니다. '
        '몸이 아니라 기분이 먼저 무너지는 순서입니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '턱이 두툼합니다. 전통 관상은 이 자리를 오래 버티는 힘으로 읽었습니다. '
        '체력의 바닥이 깊은 쪽이라는 이야기입니다. '
        '대신 한 번 무너지면 회복이 더딥니다.',
  ]),
  _Frag.hard((f) => f.fired('P-05') || f.nodeZ('glabella') >= 0.5, [
    '두 눈썹 사이가 넓고 맑습니다. 옛 관상에서 이 자리는 마음이 모이는 곳입니다. '
        '생각이 정리되면 몸도 같이 가라앉는 구성입니다. '
        '스트레스 관리 하나가 다른 지표를 전부 끌고 다닙니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '콧대 위쪽이 얕은 편입니다. 전통 관상은 이런 얼굴을 두고 한 번 무너지면 되돌리는 데 시간이 걸린다고 했습니다. '
        '평소보다 회복 구간을 길게 잡아야 한다는 뜻입니다. '
        '다만 같은 문헌이 몸을 코 하나로 판단하지 말라고도 적어 뒀습니다.',
  ]),
  _Frag.hard((f) => true, [
    '옛사람들은 몸을 한 자리로 보지 않았습니다. 이마·콧대 위쪽·눈·턱이 서로 받쳐 준다고 봤고, 이 얼굴은 그 네 곳이 비슷한 높이에 있습니다.',
    '옛사람들은 병을 얻은 뒤보다 얻기 전을 보려 했습니다. 자리의 모양보다 그날의 얼굴빛을 먼저 살핀 이유입니다. '
        '거울에서 낯빛이 달라졌다고 느낀 날이 곧 신호입니다.',
    '전통 관상에서 몸은 한 자리로 정해지지 않습니다. 크기보다 흐트러짐이 없는지를 먼저 봤습니다.',
  ]),
];
final List<_Frag> _v2HealthAdvice = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '버틸 수 있다는 감각이 회복 시점을 늦추니, 피로를 느낀 날짜를 적어 두는 정도면 충분합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '수면 시각을 고정하는 것 하나가 가장 단순한 유지법이에요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '몸을 쓰는 운동이 그 통로 역할을 합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '기상과 취침 시각을 고정하는 것이 그에 해당합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '수면·식사 시각을 일정하게 두는 것만으로 대부분이 정리됩니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '어디가 어떻게 불편한지 적어 두면 진료에서 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '몰아서 쉬는 것보다 매일 조금씩 끊어 쉬는 쪽이 이 조언에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '몇 시 이후에는 일을 잡지 않는 규칙 하나면 됩니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '몸을 밀어붙이는 방식보다 회복 시간을 먼저 확보하는 순서가 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '지금 가장 불편한 곳부터 살피는 순서가 가장 단순합니다.',
    '거울에서 낯빛이 달라졌다고 느낀 날을 적어 두면 그 자체가 기록이 됩니다.',
    '몸의 자리도 생활에 따라 달라진다고 본 것이고, 수면이 그 가운데 가장 크게 작동합니다.',
    '건강은 한 번의 결심보다 반복되는 습관에서 갈립니다. 수면 시각 고정, 주 3회 이상의 몸 쓰기, 정기 검진 세 가지면 충분합니다.',
    '증상이 없을 때 받는 검진이 그 뜻에 가장 가깝습니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 회복이 빨라 무리의 대가가 늦게 옵니다. 이 시기에 만든 수면·식사 습관이 이후 20년의 기준선이 됩니다.',
    '20대에는 체력의 상한보다 회복의 속도를 기준으로 삼는 편이 낫습니다. 다음 날 남는 피로가 신호입니다.',
    '20대에 시작한 흡연·과음은 30대 후반에 값이 청구됩니다. 지금 끊는 비용이 가장 쌉니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 회복 속도가 눈에 띄게 달라지는 구간입니다. 같은 강도로 밀어붙이면 남는 피로가 쌓여요.',
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
  _v2HealthLead,
  _v2HealthReading,
  _v2HealthAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 연애 — attractiveness × emotionality
//
// v1 은 opening·advice 도 남/여로 나눠 뒀지만 조건 집합이 완전히 같다.
// 측정 서술에서 성별로 문장이 달라질 근거가 없으므로 공용 풀로 합쳤고,
// 조건이 실제로 다른 strength·shadow 만 분리를 유지한다.
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2RomanceLead = [
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.high), [
    '@{verdict:attractiveness} 눈꼬리에 기운이 실리고 표정의 폭도 넓습니다. 사람이 모이는 얼굴입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 눈꼬리 자리가 도톰합니다. 인연이 늦게 오는 구성은 아닙니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '@{verdict:attractiveness} 다만 표정의 움직임이 적습니다. 다가오기는 쉬워도 가까워지기는 더딥니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '@{verdict:emotionality} 눈의 기운이 셉니다. 마음을 깊게 쓰는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 인연과 관련된 자리가 어느 쪽으로도 치우치지 않았습니다.',
    '@{verdict:attractiveness} 관계가 급하게 오르내리지 않는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '@{verdict:emotionality} 표정의 결이 잔잔합니다. 속을 늦게 내보입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '@{verdict:attractiveness} 대신 마음의 폭은 넓습니다. 첫눈보다 오래 볼수록 달라 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '@{verdict:attractiveness} 눈에 띄는 쪽보다 흐트러지지 않는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '@{verdict:attractiveness} 인연과 관련된 자리가 전반적으로 낮게 나왔습니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:attractiveness} 판단의 근거는 눈꼬리 자리와 표정의 폭입니다.',
    '@{verdict:attractiveness} 눈 하나가 아니라 눈썹·입·턱까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2RomanceReading = [
  _Frag.hard((f) => f.fired('P-08') || f.nodeZ('eye') >= 0.5, [
    '전통 관상에서 눈꼬리 바깥은 배우자를 보는 자리입니다. 이 자리에 기운이 실리면 인연이 끊기지 않는다고 봤습니다. '
        '요즘 말로 하면 관계를 시작하는 문턱이 낮은 쪽입니다. '
        '다만 문턱이 낮은 만큼 깊어지는 데는 따로 시간이 듭니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.5, [
    '입가의 결이 살아 있습니다. 옛사람들은 이 자리를 정이 드나드는 곳으로 봤습니다. '
        '표현이 늦지 않은 구성입니다. '
        '대신 표현이 빠른 만큼 식는 것도 빠를 수 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '이마가 곧게 섰습니다. 전통 관상은 이 자리를 말과 행동이 어긋나지 않는 힘으로 읽었습니다. '
        '연애에서 이 자리는 설렘보다 안심을 만듭니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '눈의 기운이 셉니다. 옛 관상에서는 정이 흐르는 자리로 봤습니다. '
        '마음을 깊게 쓰는 쪽이라는 이야기입니다. '
        '다만 없는 기색까지 읽어 혼자 지치기 쉽습니다.',
  ]),
  _Frag(_lowOf(Attribute.attractiveness), [
    '눈꼬리 자리가 두드러지지 않습니다. 전통 관상은 첫눈보다 오래 볼수록 달라 보이는 상을 따로 뒀습니다. '
        '이 구성이 그쪽입니다. '
        '먼저 다가가지 않으면 지나가는 인연이 생깁니다.',
  ]),
  _Frag.hard((f) => true, [
    '옛 문헌은 인연이 눈 하나로 정해지지 않는다고 봤습니다. 눈썹·입·턱까지 같이 봤고, 이 얼굴은 어느 한 곳이 앞서 나가지 않습니다.',
    '옛사람들은 눈꼬리가 좋아도 두 눈썹 사이가 흐리면 그 자리만으로 읽지 않았습니다. '
        '인연은 얼굴 한 곳으로 정해지지 않는다고 본 것입니다.',
    '전통 관상에서 눈은 짝을 보는 자리이면서 사는 자리를 보는 곳이기도 합니다. '
        '연애와 살림을 같은 자리에서 읽은 셈입니다.',
  ]),
];

final List<_Frag> _v2RomanceAdvice = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '만나는 수를 늘리는 것보다 한 관계에 들이는 시간을 늘리는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '상대를 고르는 기준을 미리 적어 두면 그 조언이 실제로 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '표정보다 말이 빠른 통로입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '상대의 기색을 읽는 만큼 자기 상태도 적어 두세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '짧게 여럿을 보는 것보다 길게 겪는 자리가 이 구성에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '상대는 표정만으로 알아채지 못합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '한 번에 결정되는 자리보다 여러 번 마주치는 자리에서 값이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '꾸준히 나가는 모임 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '처첩궁이 아니라면 형제궁 쪽, 곧 곁에 오래 남는 관계부터 넓히는 편이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '어느 자리가 실한지에 맞춰 만나는 방식을 고르는 편이 낫습니다.',
    '관계에서 가장 먼저 손볼 것은 상대가 아니라 자기 상태입니다.',
    '관계에서도 같은 기준이 적용됩니다.',
    '상이 마음에서 나온다는 말이 관상 문헌 안에 함께 적혀 있어요.',
    '그 앞에서는 평소의 열 배쯤 시간을 들여 겪어 보는 편이 낫습니다.',
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
  _v2RomanceLead,
  _v2RomanceReading,
  _v2RomanceAdvice,
];

final List<_BeatPool> _v2RomanceBeatsMale = [
  _v2RomanceLead,
  _v2RomanceReading,
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

final List<_Frag> _v2VitalityLead = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '@{verdict:libido} 눈썹이 짙고 인중이 또렷합니다. 기운과 결이 함께 섰습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 눈썹이 짙고 인중이 또렷합니다. 기운이 안에서 잘 돕니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '@{verdict:libido} 다만 밖으로 드러나는 결은 적습니다. 안에서 도는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '@{verdict:sensuality} 눈꼬리와 입가의 결이 뚜렷합니다. 사람의 눈이 머무는 얼굴입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 기운과 관련된 자리가 어느 쪽으로도 치우치지 않았습니다.',
    '@{verdict:libido} 크게 타오르지도, 쉽게 꺼지지도 않는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '@{verdict:sensuality} 결이 잔잔합니다. 밖으로 내기보다 안으로 두는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '@{verdict:libido} 대신 드러나는 결은 뚜렷합니다. 세기와 결이 다른 자리에 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '@{verdict:libido} 눈썹과 인중의 결이 옅습니다. 기운을 아껴 쓰는 얼굴입니다.',
  ]),
  _Frag(_lowPair(Attribute.libido, Attribute.sensuality), [
    '@{verdict:libido} 기운과 관련된 자리가 전반적으로 낮게 나왔습니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:libido} 판단의 근거는 눈썹의 짙기와 인중의 또렷함입니다.',
    '@{verdict:libido} 눈 하나가 아니라 눈썹·인중·입까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2VitalityReading = [
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '전통 관상에서 인중은 기운이 지나는 길목입니다. 이 자리가 또렷하면 정기가 성하다고 봤습니다. '
        '요즘 말로 하면 회복이 빠르고 체력의 바닥이 깊은 쪽입니다. '
        '다만 쓰는 속도가 채우는 속도를 앞지르면 그때부터 빠르게 무너집니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL') || f.nodeZ('mouth') >= 0.5, [
    '입가의 결이 살아 있습니다. 옛사람들은 이 자리를 밖으로 드러나는 기운으로 봤습니다. '
        '가만히 있어도 눈길이 머무는 구성입니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹이 짙습니다. 전통 관상은 눈썹의 결로 기운의 성쇠를 함께 읽었습니다. '
        '한번 붙으면 오래 가는 쪽입니다.',
  ]),
  _Frag(_lowOf(Attribute.libido), [
    '눈썹과 인중의 결이 옅은 편입니다. 전통 관상은 이런 얼굴을 두고 기운을 아껴 쓰는 상이라 했습니다. '
        '적게 쓰는 대신 오래 쓰는 구성입니다. '
        '몰아쓰는 방식이 가장 안 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '전통 관상은 기운이 눈·눈썹·인중·입에 나뉘어 있다고 봤습니다. 한 곳만 세게 도는 것보다 네 곳이 같이 도는 쪽을 좋게 여겼고, 이 얼굴이 그 구성에 가깝습니다.',
    '옛사람들은 자리의 모양보다 그날의 얼굴빛이 기운을 먼저 알린다고 했습니다. '
        '생활이 어지러우면 좋은 자리도 흐려진다고 본 것입니다.',
    '전통 관상에서 눈썹은 곁에 두는 사람의 자리이면서 기운의 성쇠를 보는 자리이기도 합니다.',
  ]),
];

final List<_Frag> _v2VitalityAdvice = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '수면과 운동이 그 채우는 자리에 해당합니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.sensuality) != _Band.high,
    [
      '몸을 쓰는 일과가 그 통로 역할을 합니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '밖에서 보이는 것과 안이 다를 수 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '수면 시각을 고정하는 것이 가장 단순한 유지법입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '기다리면 지나가는 자리가 있어요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '보이는 쪽보다 버티는 쪽이 먼저입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '무엇에 쓸지 정하지 않으면 아낀 것이 남지 않습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) != _Band.low,
    [
      '사람을 오래 겪는 자리에서 값이 올라갑니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '몸을 먼저 채우면 나머지가 따라온다고 했어요.',
    ],
  ),
  _Frag.hard((f) => true, [
    '어느 자리가 실한지에 맞춰 쓰는 곳을 고르는 편이 낫습니다.',
    '수면이 가장 크게 작동합니다.',
    '상이 마음에서 나온다는 말이 관상 문헌 안에 함께 적혀 있습니다.',
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
  _v2VitalityLead,
  _v2VitalityReading,
  _v2VitalityAdvice,
];

final List<_BeatPool> _v2VitalityBeatsMale = [
  _v2VitalityLead,
  _v2VitalityReading,
  _v2VitalityAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 대인관계 — sociability × trustworthiness
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2SocialLead = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '@{verdict:sociability} 입이 단정하고 이마가 곧습니다. 말수와 신뢰가 같이 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 입이 큰 편입니다. 자리에 사람이 잘 모입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '@{verdict:sociability} 다만 이마가 받쳐 주지 않습니다. 말이 행동보다 먼저 나갑니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '@{verdict:trustworthiness} 이마가 곧게 섰습니다. 한 말을 지키는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 사람과 관련된 자리가 어느 쪽으로도 치우치지 않았습니다.',
    '@{verdict:sociability} 관계의 온도가 급하게 오르내리지 않는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '@{verdict:trustworthiness} 이마가 좁은 편입니다. 신뢰를 얻는 데 시간이 걸립니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '@{verdict:sociability} 대신 이마는 곧습니다. 적게 말하되 그 말이 남습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '@{verdict:sociability} 넓게 트기보다 깊게 두는 얼굴입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '@{verdict:sociability} 사람과 관련된 자리가 전반적으로 낮게 나왔습니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:sociability} 판단의 근거는 입의 크기와 이마의 곧기입니다.',
    '@{verdict:sociability} 입 하나가 아니라 이마·눈썹·눈까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2SocialReading = [
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.8, [
    '전통 관상에서 입은 말이 드나드는 자리입니다. 이 자리가 크면 사람이 모인다고 봤습니다. '
        '요즘 말로 하면 첫 대화의 문턱이 낮은 쪽입니다. '
        '다만 옛사람들은 말의 양보다 그 말이 지켜지는지를 먼저 봤습니다.',
  ]),
  _Frag.hard((f) => f.fired('P-10') || f.nodeZ('eye') >= 0.8, [
    '눈에 기운이 실렸습니다. 옛 관상에서는 이런 얼굴이 상대의 기색을 먼저 알아본다고 했습니다. '
        '분위기가 바뀌는 순간을 남보다 빨리 감지하는 쪽입니다. '
        '대신 없는 기색까지 읽어 혼자 지치기도 합니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹이 또렷합니다. 전통 관상은 이 자리를 곁에 두는 사람의 자리로 읽었습니다. '
        '오래 가는 관계가 몇 개 남는 구성입니다. '
        '넓이보다 깊이 쪽에 무게가 실립니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입과 인중이 함께 뚜렷합니다. 옛사람들은 이 조합을 두고 말에 힘이 실린다고 봤습니다. '
        '설득이 필요한 자리에서 유리합니다. '
        '다만 힘이 실린 말일수록 되돌리기 어렵습니다.',
  ]),
  _Frag(_lowOf(Attribute.trustworthiness), [
    '이마가 좁은 편입니다. 전통 관상은 이런 얼굴을 두고 이름이 늦게 선다고 했습니다. '
        '평판이 쌓이는 속도가 느리다는 뜻이지, 신뢰가 없다는 뜻은 아닙니다. '
        '작은 약속이 쌓여야 판이 열리는 구성입니다.',
  ]),
  _Frag.hard((f) => true, [
    '전통 관상학에서는 사람됨이 이마·눈썹·눈·입에 나뉘어 드러난다고 봤습니다. 한 곳이 튀는 얼굴보다 네 곳이 고른 얼굴을 관계에서 높게 여겼고, 이 얼굴이 그쪽입니다.',
    '옛사람들은 입이 좋아도 마음이 흐트러지면 그 자리가 흐려진다고 했습니다. '
        '관계에서 먼저 손볼 것은 상대가 아니라 자기 상태라는 이야기입니다.',
    '전통 관상에서 이마는 이름이 서는 자리, 눈썹은 곁에 남는 사람의 자리입니다. '
        '두 곳이 같이 서면 이름과 사람을 한 길에서 얻는다고 봤습니다.',
  ]),
];

final List<_Frag> _v2SocialAdvice = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '아는 사람을 늘리는 것보다 이미 있는 관계에 시간을 들이는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '약속한 것을 적어 두는 습관 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '자리에서 말하는 양을 절반으로 줄이는 것만으로 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '여러 자리보다 한 자리에서 오래 쌓는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '치우치지 않은 상을 두고 전통 관상은 시간이 쌓이는 만큼 드러난다고 했어요. 꾸준히 나가는 모임 하나가 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '큰 말보다 지킨 횟수가 자리를 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '넓히려 애쓰기보다 몇 사람에게 깊게 두는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사람 수보다 겪는 시간을 기준으로 삼으세요.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '출납관이 아니라면 일이나 재능으로 먼저 알려지는 쪽이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '어느 자리가 실한지에 맞춰 관계를 넓히는 방식을 고르는 편이 낫습니다.',
    '관계에서 먼저 손볼 것은 상대가 아니라 자기 상태예요.',
    '약속의 크기를 줄이고 지킨 횟수를 늘리는 쪽이 맞습니다.',
    '상이 마음에서 나온다는 말이 관상 문헌 안에 함께 적혀 있어요.',
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
  _v2SocialLead,
  _v2SocialReading,
  _v2SocialAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 타고난 재능 — intelligence × leadership
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2TalentLead = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '@{verdict:intelligence} 이마가 넓고 턱이 받쳐 줍니다. 헤아리는 힘과 이끄는 힘이 같이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 이마가 넓고 반듯합니다. 먼저 헤아리는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '@{verdict:intelligence} 다만 턱이 얇습니다. 헤아리되 앞에 나서지는 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '@{verdict:leadership} 턱과 광대가 함께 섰습니다. 사람을 끌고 가는 힘이 실렸습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 재주와 관련된 자리가 한쪽으로 몰리지 않았습니다.',
    '@{verdict:intelligence} 한 분야에 몰아넣기보다 여러 곳을 잇는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '@{verdict:leadership} 턱이 얇은 편입니다. 뒤에서 받치는 자리가 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '@{verdict:intelligence} 대신 턱과 광대가 섰습니다. 재기보다 밀고 나가는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '@{verdict:intelligence} 이마보다 아래쪽이 발달했습니다. 머리보다 손발이 앞섭니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '@{verdict:intelligence} 재주와 관련된 자리가 전반적으로 낮게 나왔습니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{verdict:intelligence} 판단의 근거는 이마의 넓이와 턱의 받침입니다.',
    '@{verdict:intelligence} 이마 하나가 아니라 눈썹·눈·턱까지 함께 본 결과입니다.',
  ]),
];

final List<_Frag> _v2TalentReading = [
  _Frag.hard((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '전통 관상에서 이마는 이름과 자리가 서는 곳입니다. 넓고 반듯하면 타고난 바탕이 두껍다고 봤습니다. '
        '요즘 말로 하면 새로운 판을 빨리 이해하는 쪽입니다. '
        '다만 이해가 빠른 만큼 남의 속도를 기다리기 어렵습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 짙고 결이 분명합니다. 옛사람들은 이 자리를 뜻을 세우는 힘으로 읽었습니다. '
        '한번 정한 방향을 오래 끌고 가는 구성입니다. '
        '대신 방향이 틀렸을 때 되돌리는 데도 그만큼 걸립니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대가 평균보다 섰습니다. 전통 관상은 이 자리를 사람을 움직이는 힘으로 봤습니다. '
        '혼자 하는 일보다 사람을 데리고 하는 일에서 값이 올라갑니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM'), [
    '눈썹과 눈 사이가 넓습니다. 옛 관상에서는 이 여백을 여유로 봤습니다. '
        '급한 판단을 미루고 한 박자 뒤에 움직이는 쪽입니다.',
  ]),
  _Frag(_lowOf(Attribute.leadership), [
    '턱이 얇은 편입니다. 전통 관상은 이런 얼굴을 두고 시작한 것을 끝까지 두기 어렵다고 했습니다. '
        '앞에 서는 자리보다 뒤에서 받치는 자리가 맞는다는 이야기입니다. '
        '받치는 힘을 낮게 본 것은 아닙니다.',
  ]),
  _Frag.hard((f) => true, [
    '옛사람들은 재주가 한 자리에 몰려 있다고 보지 않았습니다. 이마·눈썹·눈·턱을 함께 봤고, 이 얼굴은 그 네 곳이 비슷한 높이에 있습니다.',
    '옛사람들은 타고난 바탕보다 그것을 쓰는 결을 먼저 봤습니다. '
        '무엇을 아느냐보다 무엇에 오래 매달렸느냐가 남는다는 이야기입니다.',
    '전통 관상에서 이마는 바탕을 보는 자리이면서 자리 옮김을 보는 자리이기도 합니다. '
        '한곳에 머물지 않는 재주로도 읽었습니다.',
  ]),
];

final List<_Frag> _v2TalentAdvice = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '혼자 하는 일보다 사람을 데리고 하는 일에서 값이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '여러 갈래보다 한 갈래에서 오래 쌓는 편이 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '쌓은 것을 글이나 말로 정리해 두는 일이 그에 해당합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '결정 전에 반대 의견을 하나 이상 듣는 규칙이 그 역할을 합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '치우치지 않은 상을 두고 전통 관상은 무엇을 잡느냐가 그대로 드러난다고 했어요. 한 분야를 3년 단위로 잡아 두세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '앞에 서는 자리를 억지로 잡기보다 대체 불가한 기술을 하나 두는 편이 낫습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '헤아리는 사람을 곁에 두면 그 자리가 채워집니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '책보다 현장에서 값이 올라갑니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '관록궁이 아니라면 손재주나 관계 쪽을 중심에 두는 편이 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '어느 자리가 실한지에 맞춰 일을 고르는 편이 낫습니다.',
    '무엇을 아느냐보다 무엇에 오래 매달렸느냐가 남습니다.',
    '상이 마음에서 나온다는 말이 관상 문헌 안에 함께 적혀 있습니다.',
    '재능은 한 번의 성취보다 반복되는 시간에서 드러납니다. 한 분야에 3년을 넣어 보면 대부분 답이 나옵니다.',
    '그 앞에서는 평소의 열 배쯤 시간을 들여 알아보는 편이 낫습니다.',
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
  _v2TalentLead,
  _v2TalentReading,
  _v2TalentAdvice,
];

// ═══════════════════════════════════════════════════════════════════════
// 종합 조언
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2ConcludeOpening = [
  _Frag.hard(_yangStrong, [
    "'@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 얼굴에 겹칩니다. 밖으로 뻗는 축이 뚜렷하게 앞섭니다.",
  ]),
  _Frag.hard(_yinStrong, [
    "'@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 얼굴에 겹칩니다. 안으로 모으는 축이 뚜렷하게 앞섭니다.",
  ]),
  _Frag.hard(_yyHarmony, [
    "'@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 얼굴에 겹칩니다. 어느 축도 크게 앞서지 않습니다.",
  ]),
  _Frag.hard((f) => f.specialArchetype != null, [
    "'@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 흐르고, 여기에 '@__SPECIAL_ARCHETYPE__'까지 같이 측정됩니다. 같은 성별·얼굴형 분포에서 흔한 조합은 아닙니다.",
  ]),
  _Frag.hard((f) => true, [
    "'@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐릅니다.",
  ]),
];

final List<_Frag> _v2ConcludeStage = [
  _Frag.hard((f) => f.age.isOver50, [
    '전통 관상은 열두 자리를 다 본 뒤 두 눈썹 사이를 마지막으로 한 번 더 봤습니다. 자리 하나가 아니라 자리들이 서로 어떻게 놓였는지를 보려던 것입니다. '
        '지금은 쌓는 일보다 남길 것과 흘려보낼 것을 가르는 판단이 중심에 놓입니다.',
  ]),
  _Frag.hard((f) => f.age.isOver30 && !f.age.isOver50, [
    '전통 관상은 열두 자리를 다 본 뒤 두 눈썹 사이를 마지막으로 한 번 더 봤습니다. 한 자리의 값보다 자리들이 서로 어떻게 놓였는지를 보려던 것입니다. '
        '지금은 드러난 재주를 어떤 구조 위에 올리느냐가 갈림길입니다.',
  ]),
  _Frag.hard((f) => f.age.isOver20 && !f.age.isOver30, [
    '전통 관상은 두 눈썹 사이를 그 사람의 중심을 보는 자리로 뒀습니다. '
        '지금은 답을 서둘러 찾기보다 자기 질문을 또렷이 세우는 일이 먼저입니다.',
  ]),
  _Frag.hard((f) => !f.age.isOver20, [
    '옛사람들은 어린 얼굴을 두고 아직 자리가 굳지 않았다고 봤습니다. '
        '지금 겪는 폭이 그대로 다음 구간의 깊이가 됩니다.',
  ]),
];

final List<_Frag> _v2ConcludeAdvice = [
  _Frag.hard((f) => true, [
    '이 리포트가 말하는 것은 두 가지입니다. 얼굴 계측값이 같은 성별·얼굴형 11,800명 가운데 어디에 놓이는가, 그리고 전통 관상이 그 자리를 어떻게 읽어 왔는가. '
        '앞일을 맞히려 한 것이 아니고, 전통의 해석이 옳다고 주장하지도 않습니다. '
        '옛사람들도 얼굴을 한 번 정해지면 끝나는 것으로 보지 않았습니다.',
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
