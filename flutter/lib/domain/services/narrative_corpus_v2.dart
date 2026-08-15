part of 'life_question_narrative.dart';

// ═══════════════════════════════════════════════════════════════════════
// 인생 질문 서술 코퍼스 v2 — 현재 시제 + 백분위 근거
//
// 문장 규칙 (D안):
//   [백분위 사실]  재력이 같은 성별·얼굴형 분포에서 @{pct:wealth} 구간입니다.
//   [경향 서술]    한 번의 큰 결정보다 같은 선택을 반복하는 쪽에 값이 몰려
//                  있습니다.
//
// 금지 → 대신
//   미래 시제 (`말년`·`평생`·`노년`·`수명`)  → 전부 현재형
//   은유 (`돈이 머물고 싶어하는 얼굴`)        → 제거
//   단정 (`~합니다`)                          → 관찰 (`~더 자주 관찰됩니다`)
//   외부 연구 인용                            → 자체 분포만
//   결과 예측                                 → 성향 서술
//
// 백분위의 출처는 `attributePercentile()` — 같은 성별·얼굴형 quantile
// 테이블에서의 위치다. 외부 연구가 아니라 **자체 분포**라서 문장이 참임이
// 구조적으로 보장된다.
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

/// 백분위(0..1) → 한국어 구절. `@{pct:attr}` 슬롯이 이걸 부른다.
/// 1% 미만·99% 초과는 과장으로 읽히므로 1~50 으로 clamp 한다.
String _v2PctPhrase(double p) {
  if (p >= 0.5) return '상위 ${((1 - p) * 100).round().clamp(1, 50)}%';
  return '하위 ${(p * 100).round().clamp(1, 50)}%';
}

// ═══════════════════════════════════════════════════════════════════════
// 재력 — wealth × stability
// ═══════════════════════════════════════════════════════════════════════

final List<_Frag> _v2WealthOpening = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '재력이 같은 성별·얼굴형 분포에서 @{pct:wealth}, 안정성도 함께 높은 구간입니다. 벌어들이는 항목과 유지하는 항목이 같이 높게 나오는 조합은 흔하지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '재력이 @{pct:wealth} 구간이고 안정성은 평균대입니다. 기회를 알아보는 항목의 값이 높고, 손실을 감당하는 항목은 평균에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '재력은 @{pct:wealth} 구간인데 안정성이 낮은 쪽입니다. 이 조합에서는 들어오는 흐름과 나가는 흐름이 함께 커지는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '재력은 평균대이고 안정성이 @{pct:stability} 구간입니다. 크게 움직이는 쪽보다 유지하는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '재력과 안정성이 모두 평균대에 놓여 있습니다. 한쪽으로 치우친 값이 없어서, 돈에 대한 판단이 상황마다 크게 흔들리는 일이 적은 편입니다.',
    '재력이 @{pct:wealth} 구간으로 분포 가운데에 있습니다. 위험을 크게 걸지도, 지나치게 움츠러들지도 않는 쪽이 많습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '재력은 평균대인데 안정성이 @{pct:stability} 구간입니다. 판단 자체보다 판단하는 시점이 흔들리는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '재력은 @{pct:wealth} 구간이고 안정성이 높은 쪽입니다. 새로 만드는 항목보다 유지하는 항목에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '재력이 @{pct:wealth} 구간이고 안정성은 평균대입니다. 두 항목 모두 큰 변동을 만드는 쪽은 아닙니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재력과 안정성이 모두 분포 아래쪽에 있습니다. 측정값이 돈 쪽보다 다른 항목에 몰려 있다는 뜻이고, 이 구성에서는 재능·관계 항목이 상대적으로 높게 나오는 경우가 많습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재력이 같은 성별·얼굴형 분포에서 @{pct:wealth} 구간입니다. 한 번의 큰 결정보다 같은 선택을 반복하는 쪽에 값이 몰려 있습니다.',
    '재력 항목이 @{pct:wealth} 구간에 놓여 있습니다. 변화를 만드는 힘보다 유지하는 힘이 더 크게 측정됩니다.',
    '재력이 @{pct:wealth} 구간으로 측정됩니다. 결과가 예측되는 선택에서 값이 높게 나오는 구성입니다.',
  ]),
];

final List<_Frag> _v2WealthVignette = [
  _Frag(_highOf(Attribute.wealth), [
    '돈이 될 만한 신호를 남보다 먼저 감지한다는 평을 듣는 경우가 이 구간에서 더 자주 관찰됩니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '주변이 함께 움직이는 자리에서 혼자 판단을 보류하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '기분이 올라온 구간에서 지출 결정이 커지는 패턴이 더 자주 관찰됩니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '들어온 돈의 사용처를 나중에 되짚기 어려운 경우가 이 구간에서 상대적으로 많습니다.',
  ]),
  _Frag.hard((f) => true, [
    '큰 지출 앞에서 결정을 여러 날 미루는 쪽에 값이 몰려 있습니다.',
    '남의 돈 문제는 잘 짚으면서 자기 지출 기록은 뒤로 미루는 경우가 자주 관찰됩니다.',
    '돈 관리를 잘할 것 같다는 인상을 주는 쪽에 값이 실려 있습니다.',
  ]),
];

final List<_Frag> _v2WealthStrength = [
  _Frag.hard((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '코 항목의 측정값이 같은 성별·얼굴형 평균보다 뚜렷하게 높습니다. 수입 구조를 스스로 설계하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균 위에 있습니다. 혼자 벌어들이는 형태보다 사람을 통해 규모를 키우는 쪽의 값이 더 높게 나옵니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '턱 항목의 값이 높게 측정됩니다. 짧은 구간의 성과보다 오래 유지되는 형태에 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-11'), [
    '얼굴 중간 영역의 항목들이 고르게 높습니다. 여러 항목이 동시에 평균을 넘는 구성이라 한 항목의 약점이 전체를 끌어내리지 않습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입 항목의 값이 함께 높습니다. 들어오는 쪽과 나가는 쪽을 같이 통제하는 구성이 더 자주 관찰됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '재력이 단기 구간보다 누적 구간에서 값이 높게 나옵니다. 짧게 끊어 보는 것보다 길게 묶어 보는 쪽이 이 구성에 맞습니다.',
    '한 항목에 몰린 값보다 여러 항목에 나뉜 값이 더 큽니다. 수입원이 하나로 좁혀지지 않는 쪽이 많습니다.',
    '재력과 대인관계 항목이 같은 방향으로 움직입니다. 혼자 세운 계획보다 함께 세운 계획에서 값이 더 높게 나옵니다.',
    '충동 지출 쪽 값이 낮은 편입니다. 쓸 곳의 우선순위가 먼저 정해져 있는 쪽에 값이 몰려 있습니다.',
    '남들이 쓰는 자리에서 쓰지 않고 자기 기준의 자리에 몰아 쓰는 쪽에 값이 실려 있습니다. 눈에 잘 안 띄지만 이 항목의 차이가 가장 크게 벌어집니다.',
  ]),
];

final List<_Frag> _v2WealthShadow = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '다만 두 항목이 함께 높은 구성에서는 지출 자체를 줄이는 쪽으로 값이 치우치기 쉽습니다. 모으는 항목만 높고 쓰는 항목이 낮으면 자산 크기와 체감이 어긋납니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '다만 들어오는 항목보다 나가는 항목의 값이 큽니다. 수입을 늘리는 것보다 새는 항목을 먼저 찾는 쪽이 효과가 큽니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '다만 감정 항목의 값이 금전 판단에 함께 실립니다. 분위기에 따라 결정이 달라지는 경우가 더 자주 관찰되니, 큰 결정은 하루 묵히는 쪽이 안전합니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 안정성 항목의 값이 낮아 좋은 구간에서 규모를 키우는 쪽으로 기울기 쉽습니다. 오르는 구간과 내리는 구간의 낙차가 이 구성에서 더 크게 나타납니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 특정 시기에 지출 항목의 값이 몰려 올라갑니다. 그 구간에 미리 이름을 붙여 두는 것만으로 같은 상황에서 결정이 달라지는 경우가 많습니다.',
    '다만 돈 결정의 값이 혼자 있을 때보다 함께 있을 때 더 크게 흔들립니다. 체면과 관계가 얹히는 자리에서 지출 항목이 가장 크게 벌어집니다.',
    '다만 들어오는 폭보다 빠져나가는 폭이 넓게 측정됩니다. 작은 항목 여럿이 합쳐져 한 해 순유입을 줄이는 구조가 더 자주 관찰됩니다.',
    '다만 한 번 크게 잃으면 설계 자체를 접는 쪽으로 값이 기웁니다. 실패 한 번을 기질로 읽지 않고 규칙만 고치는 편이 이 구성에 맞습니다.',
    '다만 성과 직후에 규모를 키우려는 항목의 값이 가장 높게 올라갑니다. 가장 많이 잃는 구간이 가장 많이 번 직후라는 점이 이 구성의 약한 고리입니다.',
  ]),
];

final List<_Frag> _v2WealthAdvice = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '버는 항목과 지키는 항목이 함께 높습니다. 월 소득보다 매달 자동으로 쌓이는 액수를 기준으로 삼고, 남의 돈과 시간을 다루는 경험을 일찍 넣어 두는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '기회를 읽는 항목의 값은 높고 지키는 항목은 평균대입니다. 좋은 구간에 규모를 키우지 않는 규칙 하나가 이 구성에서 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '버는 항목의 값은 높은데 담는 항목이 그 속도를 따라가지 않습니다. 버는 기술보다 손을 안 타는 자동 저축 구조에 먼저 투자하세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '지키는 항목의 값이 받쳐 줍니다. 짧게 끊는 방식보다 길게 묶는 방식에서 값이 높게 나오니, 5년 단위로 설계를 잡아 두세요.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '두 항목 모두 평균대입니다. 생활 습관이 자산에 가장 정직하게 반영되는 구성이라, 고정 저축을 수입의 25% 이상으로 자동화해 두는 것만으로 값이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '버는 항목은 평균대인데 감정 항목이 금전 결정에 자주 끼어듭니다. 큰 금전 결정을 24시간 묵히는 규칙 하나로 결과의 절반이 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '만드는 항목의 값은 낮고 지키는 항목이 높습니다. 근로·전문직·장기 근속 쪽이 맞고, 버는 기술보다 안 쓰는 기준에 시간을 들이는 편이 효율이 큽니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '만드는 항목도 지키는 항목도 평균 아래에서 가운데 사이에 있습니다. 대신 생활 습관이 자산에 가장 크게 반영되는 구성이라 자동 이체 저축의 효과가 남보다 큽니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재력 항목이 다른 항목보다 낮게 측정됩니다. 이 축을 억지로 가운데 두면 소모가 크니, 재능·관계·경험 항목을 중심에 두고 돈은 따라오게 설계하는 쪽이 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재력 항목의 상한을 여는 건 셋입니다. 고정 저축 자동화, 남의 돈과 시간을 다루는 경험, 감정이 올라온 구간의 결정 보류.',
    '재력은 한 번의 큰 결정보다 반복되는 작은 결정에서 값이 쌓입니다. 큰 베팅 한 번보다 매달 도는 고정 저축이 이 구성에 맞습니다.',
    '핵심은 들어온 돈이 머무는 시간입니다. 먼저 고칠 항목은 버는 기술이 아니라 쓰는 기준이고, 월별 카테고리 한도 하나가 가장 크게 작동합니다.',
    '돈은 유입·유지·증식 세 항목입니다. 값이 가장 낮은 항목부터 보세요. 유입이 낮으면 수입원을, 유지가 낮으면 규율을, 증식이 낮으면 시간을 들이면 됩니다.',
    '큰 결정 서너 번이 재력 항목의 값을 가장 크게 움직입니다. 집·직업·동업 같은 결정 앞에서는 평소의 열 배쯤 시간을 들여 조사하세요.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 한 직업에 일찍 갇히지 않는 쪽에서 값이 높게 나옵니다. 20대 후반까지 두세 갈래의 수입원을 시도해 본 경우가 30대에 자기 기울기를 먼저 찾습니다.',
    '20대에 자동 저축을 수입의 30% 이상으로 잡아 두면 30대 초반에 복리가 작동합니다. 재력 항목의 값이 실제로 벌어지는 구간은 20대가 아니라 30~40대입니다.',
    '20대의 재력은 버는 기술보다 안 쓰는 기준에서 갈립니다. 또래의 소비 압력에 휘둘리지 말고 카테고리별 한도를 먼저 정해 두세요.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대의 5~7년 구간에서 자산 항목의 값이 가장 빠르게 움직입니다. 한 분야에서 충분히 깊어진 뒤 그 깊이로 다른 분야에 발판을 만드는 순서가 이 구간에 맞습니다.',
    '35~45세에 자산이 가장 빠르게 늘어나는 구간이 관찰됩니다. 다만 한 번의 성과를 두 번째 베팅으로 그대로 가져가면 낙차가 커지니, 이 구간에서는 오히려 보수적인 배분이 맞습니다.',
    '40대에는 남의 돈과 시간을 다루는 경험이 자산 항목의 값을 가장 크게 바꿉니다. 자기 노동으로만 버는 구조에서 시스템과 조직이 버는 구조로 옮겨 가는 구간입니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 쌓는 쪽보다 흘려보내는 쪽의 설계가 중요해집니다. 증여·기부·투자 비율을 미리 정하고, 한 번의 큰 손실이 회복 구간을 갉아먹지 않도록 방어선을 두텁게 두세요.',
    '50대 이후에는 수익률보다 자산 분산·유동성·상속 구조를 정비하는 쪽이 맞습니다. 큰 결정은 가족·전문가와 공유하고 혼자 판단하는 영역을 의식적으로 줄이세요.',
    '60대 이후의 재력은 건강·관계 항목과 함께 볼 때만 의미가 있습니다. 자산 항목만 높고 나머지가 낮으면 체감이 빠르게 떨어집니다.',
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
    '안정성이 같은 성별·얼굴형 분포에서 @{pct:stability} 구간이고, 감정성도 함께 높습니다. 몸의 기본 값이 두터운데 신호를 잡아내는 항목도 같이 높은, 흔치 않은 조합입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '안정성이 @{pct:stability} 구간이고 감정성은 평균대입니다. 큰 진폭 없이 유지되는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '안정성은 @{pct:stability} 구간인데 감정성이 낮은 쪽입니다. 잔병 쪽 값은 낮은 대신, 약한 신호를 늦게 알아채는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '안정성은 평균대이고 감정성이 @{pct:emotionality} 구간입니다. 컨디션 항목이 감정 항목을 따라 움직이는 패턴이 이 구성에서 더 자주 나타납니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '안정성과 감정성이 모두 평균대에 놓여 있습니다. 치우친 값이 없어서 생활 습관이 그대로 몸에 반영되는 구조입니다.',
    '건강 관련 항목이 @{pct:stability} 구간으로 분포 가운데에 있습니다. 관리하면 평균 위로, 두면 평균 아래로 갈리는 쪽이 많습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '안정성은 평균대이고 감정성이 @{pct:emotionality} 구간입니다. 기복이 적은 대신 서서히 변하는 신호를 잡아내기 어려운 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '안정성이 @{pct:stability} 구간이고 감정성은 높은 쪽입니다. 약하다기보다 반응이 예민하게 측정되는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '안정성이 @{pct:stability} 구간이고 감정성은 평균대입니다. 저점이 남보다 낮은 구간을 자주 지나가는 대신, 몸이 신호를 일찍 보내는 쪽입니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '안정성과 감정성이 모두 분포 아래쪽에 있습니다. 얇다기보다 반응 폭이 좁게 측정되는 구성이라, 규칙적인 환경에서 값이 가장 안정적으로 유지됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '건강 관련 항목이 평균대를 따라갑니다. 약한 고리 하나를 일찍 찾는 쪽에서 값이 가장 크게 벌어집니다.',
    '큰 변동보다 잔잔한 누적이 두드러지는 구성입니다. 매일의 작은 루틴 하나가 체감 상태를 가장 크게 바꿉니다.',
    '급격한 상승도 하락도 없는 구간입니다. 회복 항목의 평균값이 남보다 반 박자 안정적으로 측정됩니다.',
  ]),
];

final List<_Frag> _v2HealthVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '스트레스가 수면이나 소화 쪽으로 먼저 나타나는 경우가 이 구간에서 더 자주 관찰됩니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '주변이 함께 앓는 시기에 혼자 컨디션이 유지되는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.high,
    [
      '큰 원인이 없는데 몸이 먼저 반응하는 패턴이 이 구성에서 자주 나타납니다.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '무리한 다음 날 회복이 더디게 측정되는 쪽입니다.',
  ]),
  _Frag.hard((f) => true, [
    '바쁜 구간에서 자기 몸 챙기는 순서가 가장 뒤로 밀리는 쪽에 값이 몰려 있습니다.',
    '쉬어야겠다는 판단과 실제로 쉬는 행동 사이의 간격이 넓게 측정됩니다.',
    '검진을 뒤로 미루는 쪽에 값이 실려 있습니다.',
  ]),
];

final List<_Frag> _v2HealthStrength = [
  _Frag.hard((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '코 항목의 측정값이 평균을 크게 넘습니다. 호흡기·순환기 쪽을 미리 점검해 두는 편이 이 구성에 맞습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09'), [
    '이마 항목의 값이 높게 나옵니다. 머리를 많이 쓰는 구성이라 수면의 질이 가장 먼저 흔들립니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '턱 항목의 값이 높게 측정됩니다. 체력 항목이 동년배 평균보다 느리게 떨어지는 쪽입니다.',
  ]),
  _Frag.hard((f) => f.fired('P-05') || f.nodeZ('glabella') >= 0.5, [
    '미간 항목의 값이 평균 위에 있습니다. 정신적 피로의 회복 항목이 높게 나오는 구성입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04'), [
    '턱 부근 항목의 값이 두텁게 나옵니다. 소화·대사 쪽 값이 높게 측정되고, 식습관의 누적이 가장 정직하게 반영됩니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정 항목의 해상도가 높게 측정됩니다. 불안으로만 두지 않으면 이 항목이 몸 상태의 조기 신호로 작동합니다.',
  ]),
  _Frag.hard((f) => true, [
    '평균대의 체질 값에 약한 고리 하나가 섞여 있습니다. 그 고리를 일찍 찾는 쪽에서 값이 가장 크게 벌어집니다.',
    '기운과 혈색 쪽 항목이 고르게 측정됩니다. 큰 진폭이 없는 대신 섬세한 유지가 필요한 구성입니다.',
    '한 항목의 강점보다 전체 균형에서 값이 나옵니다. 한 군데가 무너져도 나머지가 보완하는 분산형 구조입니다.',
    '정신 항목과 활력 항목이 같은 방향으로 움직입니다. 스트레스 관리 하나가 다른 지표를 함께 끌어올립니다.',
    '휴식 항목의 값이 다른 항목을 가장 크게 좌우합니다. 정서가 안정되면 몸 상태가 곧바로 따라오는 구성입니다.',
  ]),
];

final List<_Frag> _v2HealthShadow = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '다만 두 항목이 함께 높으면 자신감 자체가 약한 고리가 됩니다. 경고 신호를 낙관으로 덮는 경우가 이 구성에서 더 자주 관찰됩니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 과로와 감정 소모를 견디는 쪽 값이 낮게 나옵니다. 남이 버티는 강도를 자기 기준으로 삼지 않는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 기본 항목의 값이 높을수록 경고 신호를 넘기고 밀어붙이는 쪽으로 기웁니다. 아직 괜찮다는 판단이 이 구성의 약한 고리입니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 감정 항목의 진폭이 크면 몸의 진폭도 같이 커집니다. 좋은 날과 무너지는 날의 컨디션 격차가 또래보다 넓게 측정됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 몸 상태를 갉는 건 과로 항목보다 풀리지 않은 감정 항목의 누적입니다. 감정 배수로 하나를 정해 두는 쪽이 이 구성에 맞습니다.',
    '다만 작은 이상을 넘겨도 된다는 판단이 쉽게 나옵니다. 잔증상이 석 달 이어지는데 버틸 수 있음으로 해석하면 값이 한꺼번에 벌어집니다.',
    '다만 중년 구간에 누적이 한꺼번에 드러나는 시점이 옵니다. 미리 알고 설계한 쪽과 모르고 맞는 쪽의 회복 속도가 다르게 측정됩니다.',
    '다만 피곤하지 않다는 자각과 실제 회복력 사이의 간격이 넓습니다. 그 간격을 메우는 건 자각 증상보다 검진 숫자를 앞에 두는 습관 하나입니다.',
    '다만 비교에서 오는 피로가 가장 크게 작동합니다. 남의 리듬에 맞출수록 소모가 빨라지니 자기 속도의 기준선을 먼저 정해야 합니다.',
  ]),
];

final List<_Frag> _v2HealthAdvice = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '기본 항목과 감정 항목이 함께 높습니다. 과신이 가장 큰 위험이니 증상이 없을 때 점검을 넣어 두고, 감정이 몸으로 옮겨 가는 통로인 수면·심박·소화를 매달 기록해 두세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '기본 항목은 높고 감정 항목의 진폭은 크지 않습니다. 관리 난도가 가장 낮은 구성이라 3년에 한 번 검진 루틴만 고정해 두면 충분합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '기본 항목이 높고 감정 항목의 값도 낮습니다. 꾸준함이 강점이고 약한 신호를 놓치는 게 약점이니, 검진 주기를 1.5년으로 짧게 잡는 것만으로 위험이 크게 줄어듭니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '체질 항목은 평균대인데 감정 항목의 진폭이 큽니다. 몸 상태를 가장 크게 갉는 건 과로가 아니라 풀리지 않은 감정의 누적이니, 일기·상담·운동 중 하나를 배수로로 고정하세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '두 항목 모두 평균대입니다. 수면·식사·운동 중 값이 가장 낮은 하나만 먼저 표준화하는 쪽이 효율이 가장 큽니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '기복 항목의 값이 낮아 컨디션은 안정적인데, 서서히 나빠지는 변화를 감지하기 어려운 구성입니다. 체중·혈압·수면을 숫자로 재는 습관이 가장 든든한 방어선입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '체질 항목의 값이 낮고 감정 항목의 진폭은 큽니다. 남이 버티는 강도를 기준 삼지 말고, 감정이 몸으로 번지기 전에 끊는 루틴인 명상·산책·상담 중 하나를 두세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '예민한 만큼 몸의 신호를 남보다 일찍 받는 쪽입니다. 그 신호를 불안이 아니라 정보로 번역하는 훈련이 이 구성의 핵심입니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '두 항목 모두 분포 아래쪽에 있는데, 약하다기보다 반응 폭이 좁게 측정되는 구성입니다. 거친 환경만 피하면 되니 과격한 운동보다 규칙적 수면과 예측 가능한 일상이 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '건강을 지키는 건 셋입니다. 수면·식사·운동 중 값이 가장 낮은 하나를 먼저 표준화하기, 증상 없을 때 정기 점검 넣어 두기, 감정 피로가 몸으로 옮겨 가는 통로를 알아 두기.',
    '몸은 한 해가 아니라 십 년 단위로 값이 쌓입니다. 지금 반복하는 한 가지를 10년 뒤 기준으로 삼으세요.',
    '정신·기운·체력 세 항목은 따로 채워집니다. 잠은 정신을, 호흡은 기운을, 식사는 체력을 채우니 가장 먼저 흐려지는 축을 알아채는 쪽이 유리합니다.',
    '첫 원칙은 단순합니다. 내 몸을 남의 잣대로 재지 않는 것 — 버티는 강도도, 회복 속도도, 먹는 양도 사람마다 다르게 측정됩니다.',
    '@__STRONGEST_NODE__ 항목이 이 구성의 중심축입니다. 이 부위가 지치면 전체가 흔들리고, 살아나면 다른 약점도 같이 회복됩니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 무리해도 다음 날 회복되기 때문에 손상이 값으로 드러나지 않습니다. 30세 전에 수면 7시간, 주 3회 운동, 금연·금주 중 하나를 규칙으로 고정해 두는 쪽이 40대 의료비를 크게 줄입니다.',
    '20대에 만든 습관 하나가 35세 이후 만성 질환 쪽 값을 가장 크게 좌우합니다. 정기 검진을 뒤로 미루지 말고 첫 종합 검진을 일찍 받아 두세요.',
    '20대의 정신 건강은 자기 휴식 리듬을 만드는 구간입니다. 비교 압력에 밀려 달리기만 하면 30대에 소진이 옵니다. 지금 필요한 건 더 노력하는 게 아니라 자기 속도를 정해 두는 일입니다.',
  ]),
  _Frag.hard(_isMid, [
    '35~45세 사이에 20대에 쌓인 습관의 값이 처음으로 드러납니다. 가장 낮은 항목부터 표준화하고 검진 주기를 1년으로 잡으세요.',
    '일·가족·자산이 동시에 확장되는 구간이라 자기 건강이 가장 마지막으로 밀립니다. 매일 30분 운동과 연 1회 검진, 이 둘만 지켜도 충분합니다.',
    '30~40대는 스트레스가 몸으로 곧장 가는 구간입니다. 해소되지 않은 감정이 위장·관절·수면으로 옮겨 가는 패턴이 굳어지니, 명상·상담·운동 중 하나는 배출 통로로 만들어 두세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 작은 신호를 일찍 잡느냐에서 값이 갈립니다. 회복력 항목이 더는 받쳐 주지 않으므로, 자각 증상이 없을 때 정기 검진을 받는 쪽이 유리합니다.',
    '아직 멀쩡하다는 자신감이 이 구간의 약한 고리입니다. 60대 이후로는 검진 주기를 6개월로 줄이고, 남이 늙는 속도가 아니라 자기 속도를 기준 삼으세요.',
    '50대 이후에는 인간관계의 두께가 회복력 항목의 절반을 차지합니다. 가족과 오랜 친구를 정기적으로 만나는 쪽에서 면역 관련 값이 높게 나오니, 운동도 혼자보다 함께하는 형태가 낫습니다.',
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
    '매력도가 같은 성별·얼굴형 분포에서 @{pct:attractiveness} 구간이고, 감정성도 함께 높습니다. 고를 폭이 넓은 만큼 확인 단계가 길어지는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '매력도가 @{pct:attractiveness} 구간이고 감정성은 평균대입니다. 호감은 먼저 들어오는데 상대를 미화하는 쪽 값은 낮은 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '매력도는 @{pct:attractiveness} 구간이고 감정성이 낮은 쪽입니다. 들어오는 호감을 담담하게 골라내는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '매력도는 평균대이고 감정성이 @{pct:emotionality} 구간입니다. 첫인상보다 여러 번 겹친 대화에서 관계가 시작되는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '매력도와 감정성이 모두 평균대에 놓여 있습니다. 한쪽으로 치우친 값이 없어서 상대 속도에 맞춰 관계의 이름이 정해지는 쪽이 많습니다.',
    '매력도가 @{pct:attractiveness} 구간으로 분포 가운데에 있습니다. 화력도 집요함도 한쪽으로 쏠리지 않은 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '매력도는 평균대이고 감정성이 @{pct:emotionality} 구간입니다. 감정의 강도보다 조건과 생활이 겹치는지를 먼저 보는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '매력도는 @{pct:attractiveness} 구간이고 감정성이 높은 쪽입니다. 첫눈의 값은 낮은데 여운 쪽 값이 높아, 상대가 알게 된 뒤 관심이 올라가는 경우가 많습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '매력도가 @{pct:attractiveness} 구간이고 감정성은 평균대입니다. 우연히 마주치는 경로보다 같은 일·같은 모임에서 겹친 상대와 이어지는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '매력도와 감정성이 모두 분포 아래쪽에 있습니다. 뜨거운 구애보다 같은 방향을 확인한 상대와 나란히 걷는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '매력도가 @{pct:attractiveness} 구간으로 측정됩니다. 시작은 느리고 한 번 시작하면 깊게 들어가는 쪽이 많습니다.',
  ]),
];

final List<_Frag> _v2RomanceVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '상대의 말투나 표정 변화를 먼저 알아채는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_highOf(Attribute.attractiveness), [
    '애쓰지 않아도 호감이 들어오는 쪽인데, 정작 마음이 가는 상대 앞에서는 표현 쪽 값이 떨어지는 경우가 많습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '타오르는 관계보다 같이 있어도 피로가 적은 관계 쪽에 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '마음에 드는 상대일수록 표현보다 관찰이 먼저 나오는 쪽입니다.',
    '표현은 적고 챙기는 행동으로 마음을 보이는 쪽에 값이 몰려 있습니다.',
    '관계가 끝난 뒤에야 상대에 대한 판단이 또렷해지는 경우가 더 자주 관찰됩니다.',
  ]),
];

final List<_Frag> _v2RomanceStrengthFemale = [
  _Frag.hard((f) => f.fired('P-08'), [
    '눈 밑 항목의 값이 높게 측정됩니다. 매력 항목이 올라가는 구간이 규칙적으로 반복되는 구성입니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '옆면 입술 항목의 값이 평균을 넘습니다. 상대의 시선이 입매에 오래 머무는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '신뢰성 항목의 값이 높습니다. 말과 행동의 일치도가 높게 측정돼 장기 관계 쪽 값이 함께 올라갑니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정성 항목의 값이 높습니다. 갈등의 초기 신호를 일찍 잡아내는 쪽이 많습니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.5, [
    '입 항목의 값이 평균 위에 있습니다. 말로 관계를 조정하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eye') >= 0.5, [
    '눈 항목의 값이 평균 위에 있습니다. 짧은 순간에도 상대에게 기억을 남기는 쪽입니다.',
  ]),
  _Frag.hard((f) => true, [
    '관계의 수보다 밀도 쪽에 값이 실려 있습니다. 맞는 상대 한 명을 만났을 때의 값이 평균을 크게 넘습니다.',
  ]),
];

final List<_Frag> _v2RomanceStrengthMale = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹 항목의 값이 높게 측정됩니다. 관계의 성격을 일찍 정리하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균을 넘습니다. 자리에 들어설 때 시선이 모이는 쪽입니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '옆면 코 항목의 값이 높게 나옵니다. 상대가 결정에 기대는 쪽으로 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '신뢰성 항목의 값이 높습니다. 약속과 실행의 일치도가 높게 측정돼 시간이 갈수록 값이 올라갑니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.wealth) == _Band.high || f.nodeZ('nose') >= 0.8, [
    '재력 항목이나 코 항목의 값이 높게 나옵니다. 막연한 약속보다 구체적인 생활 기반이 매력 항목으로 작동합니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('chin') >= 0.5, [
    '턱 항목의 값이 평균 위에 있습니다. 한 번 정한 것을 유지하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '순간의 분위기보다 누적된 인상 쪽에 값이 실려 있습니다. 여러 장면을 겹쳐 각인시키는 구성입니다.',
  ]),
];

final List<_Frag> _v2RomanceShadowFemale = [
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 활력 항목이 높고 안정성이 받쳐 주지 않는 구성입니다. 지금 관계에서 채워지지 않는 공감을 다른 관계에서 구하는 경우가 더 자주 관찰됩니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.high,
    [
      '다만 활력 항목이 높은데 안정성으로 눌려 있는 구성입니다. 평소에는 선이 유지되지만 만족도가 길게 떨어지는 구간을 방치하면 낙차가 커집니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 시작 구간의 값이 높은 만큼 권태 구간이 먼저 옵니다. 그 공백을 다음 상대로 메우려는 패턴이 이 구성에서 자주 관찰됩니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.emotionality) == _Band.high &&
        f.bandOf(Attribute.trustworthiness) != _Band.high,
    [
      '다만 상대 신호를 깊게 읽다 보니 신호가 아닌 것까지 신호로 읽는 경우가 많습니다. 두 사람의 속도 차이가 여기서 생깁니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.high &&
        f.bandOf(Attribute.sociability) == _Band.low,
    [
      '다만 만날 자리 자체의 값이 낮습니다. 검증 항목은 높은데 새 접점을 만드는 항목이 낮아 기회가 지나가기 쉽습니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 결정을 미루는 쪽에 값이 몰려 있습니다. 확인을 더 하려다 자리를 내주는 경우가 자주 관찰되는데, 완전한 확신은 어느 시점에도 오지 않습니다.',
  ]),
];

final List<_Frag> _v2RomanceShadowMale = [
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 활력 항목이 높고 안정성이 받쳐 주지 않는 구성입니다. 스스로 찾아 나서기보다 경계가 흐려지는 환경에서 값이 흔들리는 경우가 더 자주 관찰됩니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.high,
    [
      '다만 활력 항목이 높은데 안정성으로 눌려 있는 구성입니다. 평소에는 선이 유지되지만 만족도가 길게 떨어지는 구간을 방치하면 낙차가 커집니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 시작 구간의 값이 높은 만큼 권태 구간이 먼저 옵니다. 그 공백을 새 자극으로 메우려는 패턴이 이 구성에서 자주 관찰됩니다.',
    ],
  ),
  _Frag(_highOf(Attribute.leadership), [
    '다만 주도 쪽 값이 높은 만큼 자기 속도를 상대에게 그대로 적용하기 쉽습니다. 상대가 따라오지 못할 때 관심 항목이 빠르게 떨어지는 쪽입니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.stability) == _Band.high &&
        f.bandOf(Attribute.sociability) != _Band.high,
    [
      '다만 만날 자리 자체의 값이 낮습니다. 검증 항목은 높은데 새 접점을 만드는 항목이 낮아 기회가 지나가기 쉽습니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 한 관계에 집중되면 주변 항목의 값이 함께 떨어집니다. 가장 뜨거운 구간일수록 일·친구·건강 축을 따로 지켜야 합니다.',
  ]),
];

final List<_Frag> _v2RomanceAdvice = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '매력도와 감정성이 함께 높습니다. 세 번째 만남까지의 화력보다 3년째의 대화 밀도로 상대를 고르는 훈련이 이 구성에서 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '후보 폭이 넓은 만큼 비교하는 쪽에 값이 몰려 결정이 늦어집니다. 선택 기한을 스스로 정해 두는 게 이 구성에서 가장 효과가 큽니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '불러오는 항목의 값은 높은데 속 대화 쪽 값은 낮습니다. 겉의 열기에 휩쓸리지 말고 같이 있을 때 대화가 이어지는지를 한 축으로 더하세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '첫인상보다 여러 번 겹친 대화에서 값이 올라가는 구성입니다. 짧게 평가받는 자리보다 공동 활동·관심사·동료 관계 쪽 경로를 의식적으로 넓히세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '두 항목 모두 평균대입니다. 첫눈에 끌리는 상대보다 두 달 뒤에도 피로가 적은 상대를 알아보는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '설렘의 강도보다 안정된 리듬 쪽에 값이 실려 있습니다. 드라마틱한 관계를 기준 삼지 말고, 일상 호흡이 맞는 상대를 우선하세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '첫눈의 값은 낮고 감정의 결 쪽 값은 높습니다. 짧게 평가받는 자리보다 같은 공간을 여러 번 공유하는 경로를 만드는 편이 이 구성에 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '두 항목 모두 한쪽으로 쏠려 있지 않습니다. 화려한 서사보다 같이 있을 때 덜 피곤한 상대를 고르는 쪽이 맞습니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '연애 관련 항목의 값이 다른 항목보다 낮게 측정됩니다. 결핍이 아니라 방향이니, 같은 속도가 아니어도 같은 방향을 보는 동지형 파트너십도 충분히 고려할 만합니다.',
  ]),
  _Frag.hard((f) => true, [
    '연애를 살리는 건 셋입니다. 끌리는 상대와 일상에 맞는 상대를 따로 저울질하기, 비교하는 습관에 기한 두기, 그리고 이별의 품위.',
  ]),
  _Frag.hard(_isYoung, [
    '20대의 연애는 자기와 안 맞는 조건을 알아내는 구간입니다. 상대의 외모나 직업보다, 그 사람과 있을 때 자신이 어떤 모습이 되는지를 기준으로 삼아 보세요.',
    '20대에는 이상형의 그림을 그리되 거기 갇히지 않는 쪽이 유리합니다. 결과보다 과정에서 얻는 기준이 이 구간의 실질적인 자산입니다.',
    '20대에는 감정이 크게 흔들리는 구간이 잦습니다. 누구를 좋아하는지보다 좋아할 때 자신이 어떻게 변하는지를 관찰하고, 큰 결정은 24시간 묵히는 습관을 두세요.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대의 연애는 같이 살림·자녀·돈을 굴릴 수 있는지가 핵심이 되는 구간입니다. 감정의 정점보다 평균 상태를 보는 쪽이 맞습니다.',
    '30~40대에는 말이 화려한 상대보다 일상의 사소한 합의가 잘 되는 상대를 알아보는 눈이 가장 크게 작동합니다.',
    '30대에는 결혼·자녀·커리어 세 축이 동시에 압박해 옵니다. 한 축의 압력에 떠밀려 결정하지 말고, 세 축이 맞물리는 상대를 찾는 데 시간을 더 쓰는 쪽이 후회가 적습니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 새로 시작하는 것보다 오랜 동반자와의 관계를 다시 다듬는 쪽에서 값이 높게 나옵니다. 같이 할 취미·여행·소소한 프로젝트를 일부러 만들어 두세요.',
    '나이가 들수록 침묵이 쌓이기 쉽습니다. 매년 둘만의 작은 의례를 하나씩 새로 만드는 쪽에서 관계 항목의 값이 유지됩니다.',
    '50대 이후에는 혼자의 시간의 질이 관계의 질을 함께 좌우합니다. 자기만의 세계를 가꾼 쪽에서 동반자와의 관계 값도 높게 나옵니다.',
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
    '활력이 같은 성별·얼굴형 분포에서 @{pct:libido} 구간이고, 흡인력도 함께 높습니다. 에너지 총량과 주변을 끌어당기는 항목이 같이 높게 나오는 조합은 흔하지 않습니다.',
    '활력과 흡인력이 둘 다 분포 위쪽에 있습니다. 자리에 있는 것만으로 주변 반응이 달라지는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.mid), [
    '활력이 @{pct:libido} 구간이고 흡인력은 평균대입니다. 에너지가 굵게 측정되고, 세밀하게 조율하는 항목은 평균에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '활력은 @{pct:libido} 구간인데 흡인력이 낮은 쪽입니다. 총량은 큰데 그 에너지가 상대에게 전달되는 쪽 값은 낮게 나옵니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '활력은 평균대이고 흡인력이 @{pct:sensuality} 구간입니다. 강도보다 분위기와 감각 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '활력과 흡인력이 모두 평균대에 놓여 있습니다. 큰 기복 없이 계절과 컨디션을 따라 오르내리는 쪽이 많습니다.',
    '활력이 @{pct:libido} 구간으로 분포 가운데에 있습니다. 눈에 띄는 진폭 대신 유지되는 폭 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '활력은 평균대이고 흡인력이 @{pct:sensuality} 구간입니다. 평소 값은 낮게 유지되다가 특정 조건이 겹칠 때 올라가는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '활력이 @{pct:libido} 구간이고 흡인력은 높은 쪽입니다. 에너지의 총량보다 감각과 미적 항목에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '활력이 @{pct:libido} 구간이고 흡인력은 평균대입니다. 신뢰와 시간이 쌓인 조건에서만 값이 올라가는 구성입니다.',
  ]),
  _Frag(_lowPair(Attribute.libido, Attribute.sensuality), [
    '활력과 흡인력이 모두 분포 아래쪽에 있습니다. 부족이라기보다 값이 다른 항목에 몰려 있다는 뜻이고, 이 구성에서는 안정성·신뢰성 항목이 상대적으로 높게 나오는 경우가 많습니다.',
  ]),
  _Frag.hard((f) => true, [
    '활력 항목이 @{pct:libido} 구간으로 측정됩니다. 한쪽으로 쏠린 값이 없어 상황과 상대에 맞춰 움직이는 쪽이 많습니다.',
  ]),
];

final List<_Frag> _v2VitalityVignette = [
  _Frag(_highOf(Attribute.sensuality), [
    '분위기·향·음악 같은 요소를 또렷하게 기억하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_highOf(Attribute.libido), [
    '겉으로 보이는 차분함과 실제 에너지 총량 사이의 간격이 넓게 측정됩니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.high,
    [
      '몸보다 마음이 먼저 열리는 쪽이라, 충분히 가까워지기 전에는 값이 낮게 유지됩니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '조명이나 음악 하나로 그날의 컨디션이 달라지는 경우가 자주 관찰됩니다.',
    '외모보다 말투나 결에 먼저 반응하는 쪽에 값이 실려 있습니다.',
  ]),
];

/// 활력 strength — 부위 측정값 단서. 남녀 조건 집합이 동일하고 metric 판독에
/// 성별 차가 없어 공용 풀 하나로 둔다.
final List<_Frag> _v2VitalityStrength = [
  _Frag(_metHi('mouthCornerAngle'), [
    '입꼬리 각도가 평균보다 크게 올라가 있습니다. 기본 표정이 이미 웃는 상태로 측정돼, 긴장이 풀리는 쪽에 값이 몰려 있습니다.',
    '입꼬리 항목의 값이 높습니다. 활력이 밝은 에너지와 함께 측정되는 구성이라 주변 공기가 가벼워지는 쪽입니다.',
  ]),
  _Frag(_metMid('mouthCornerAngle'), [
    '입꼬리 각도가 수평에 가깝게 측정됩니다. 온도가 겉으로 잘 드러나지 않아 첫인상은 차분한 쪽으로 읽힙니다.',
  ]),
  _Frag(_metLo('mouthCornerAngle'), [
    '입꼬리 각도가 평균보다 내려가 있습니다. 가볍게 풀리는 빈도가 낮은 대신 한마디의 무게가 크게 측정되는 쪽입니다.',
  ]),
  _Frag(_metHi('lipFullnessRatio'), [
    '입술 두께 항목의 값이 높게 측정됩니다. 말보다 표정이 먼저 전달되는 쪽에 값이 몰려 있습니다.',
    '입술 두께가 평균을 넘습니다. 미식·향·음악 같은 감각 항목이 함께 높게 나오는 구성입니다.',
  ]),
  _Frag(_metMid('lipFullnessRatio'), [
    '입술 두께가 평균대에 있습니다. 표현과 절제가 한쪽으로 쏠리지 않아 상대에 맞춰 조율하는 쪽입니다.',
  ]),
  _Frag(_metLo('lipFullnessRatio'), [
    '입술 두께 항목의 값이 낮게 측정됩니다. 표현 빈도는 낮은 대신 한 번의 표현이 또렷하게 남는 쪽입니다.',
  ]),
  _Frag(_metHi('upperVsLowerLipRatio'), [
    '윗입술이 아랫입술보다 두껍게 측정됩니다. 받는 쪽보다 주는 쪽에서 만족이 나오는 구성입니다.',
  ]),
  _Frag(_metLo('upperVsLowerLipRatio'), [
    '아랫입술이 더 두껍게 측정됩니다. 질감과 온도 같은 감각 항목에 값이 몰려 있습니다.',
  ]),
  _Frag(_metHi('philtrumLength'), [
    '인중 길이 항목의 값이 높습니다. 짧게 몰아 쓰는 쪽보다 길게 유지하는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_metMid('philtrumLength'), [
    '인중 길이가 평균대에 있습니다. 에너지 리듬이 자연스럽게 오르내리는 안정형 구성입니다.',
  ]),
  _Frag(_metLo('philtrumLength'), [
    '인중 길이 항목의 값이 낮습니다. 정점은 또렷한데 지속 구간이 짧게 측정되는 쪽입니다.',
  ]),
  _Frag(_metHi('eyeCanthalTilt'), [
    '눈꼬리 각도가 위로 올라가 있습니다. 집중과 기세가 눈에서 먼저 측정되는 구성입니다.',
  ]),
  _Frag(_metLo('eyeCanthalTilt'), [
    '눈꼬리 각도가 아래로 내려가 있습니다. 온화함이 먼저 전달돼 상대의 긴장이 풀리는 쪽입니다.',
  ]),
  _Frag(_metHi('eyeAspect'), [
    '눈이 둥글고 크게 열린 쪽으로 측정됩니다. 호기심과 활력이 표정에 그대로 실리는 구성입니다.',
  ]),
  _Frag(_metLo('eyeAspect'), [
    '눈이 가늘고 긴 쪽으로 측정됩니다. 관찰과 절제 항목의 값이 높아 표현이 눈빛으로 먼저 나갑니다.',
  ]),
  _Frag(_metHi('eyebrowThickness'), [
    '눈썹 두께 항목의 값이 높습니다. 체력과 에너지 리듬이 함께 움직이는 구성이라 수면과 컨디션이 값을 직접 좌우합니다.',
  ]),
  _Frag(_metLo('eyebrowThickness'), [
    '눈썹 두께 항목의 값이 낮습니다. 크게 요동치지 않는 쪽이라 활력도 안정권에 머무는 편입니다.',
  ]),
  _Frag(_metHi('eyebrowCurvature'), [
    '눈썹 곡률 항목의 값이 높습니다. 감수성과 변주 쪽에 값이 몰려 있어 같은 조건에서도 다른 결과를 만드는 구성입니다.',
  ]),
  _Frag(_metLo('eyebrowCurvature'), [
    '눈썹이 직선에 가깝게 측정됩니다. 리듬이 안정적이고 예측 가능한 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_metHi('cheekboneWidth'), [
    '광대 너비 항목의 값이 높습니다. 체력 축이 골격에 실려 있어 활력의 지속 구간이 길게 측정됩니다.',
  ]),
  _Frag(_metLo('cheekboneWidth'), [
    '광대 너비 항목의 값이 낮습니다. 밀어붙이는 쪽보다 조율하는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_metHi('nasolabialAngle'), [
    '코끝 각도가 위로 들린 쪽으로 측정됩니다. 개방성과 낙천 항목의 값이 높아 새 환경에서 에너지가 잘 올라갑니다.',
  ]),
  _Frag(_metLo('nasolabialAngle'), [
    '코끝 각도가 내려간 쪽으로 측정됩니다. 안정 지향 항목의 값이 높아 익숙한 조건에서 값이 올라가는 구성입니다.',
  ]),
  _Frag(_metHi('gonialAngle'), [
    '턱 각도 항목의 값이 높습니다. 의지와 끈기 축이 실려 있어 한 번 올라간 리듬이 길게 유지됩니다.',
  ]),
  _Frag(_metLo('gonialAngle'), [
    '턱이 둥글게 측정됩니다. 강도보다 온기 쪽에 값이 몰려 있는 구성입니다.',
  ]),
  _Frag(_metHi('faceAspectRatio'), [
    '얼굴이 세로로 긴 쪽으로 측정됩니다. 몰입과 집중 항목의 값이 높아 한 대상에 에너지가 쏠리는 구성입니다.',
  ]),
  _Frag(_metLo('faceAspectRatio'), [
    '얼굴이 가로로 넓은 쪽으로 측정됩니다. 활력과 포용 항목의 값이 높아 여럿이 있는 자리에서 값이 올라갑니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '옆면에서 입술이 E-line 을 넘는 것으로 측정됩니다. 표현이 입매에서 먼저 드러나는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag.hard(_yangStrong, [
    '전체 측정에서 양의 축이 뚜렷하게 앞섭니다. 활력이 먼저 움직이는 쪽으로 기울어 있는 구성입니다.',
  ]),
  _Frag.hard(_yinStrong, [
    '전체 측정에서 음의 축이 뚜렷하게 앞섭니다. 활력이 받아들이는 쪽으로 기울어 있어 시간이 쌓일수록 값이 또렷해집니다.',
  ]),
  _Frag.hard(_yyHarmony, [
    '음과 양의 축이 고르게 측정됩니다. 주도와 수용 사이를 오가는 적응 항목의 값이 가장 높습니다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '인중 쪽 항목의 값이 유독 두드러집니다. 호르몬 리듬이 표정과 에너지에 직접 반영되는 구성이라 수면·영양이 값을 크게 좌우합니다.',
  ]),
  _Frag.hard((f) => true, [
    '활력 신호가 특정 부위에 몰리지 않고 얼굴 전체에 고르게 분포합니다. 두드러진 단서 하나는 없지만 폭이 넓고 안정적인 구성입니다.',
    '부위별 신호가 모두 평균권에서 움직입니다. 한 군데에 집중된 값 대신 여러 축이 함께 도는 구성이라 상황별 적응 항목이 가장 높습니다.',
  ]),
];

final List<_Frag> _v2VitalityShadowFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '다만 총량이 큰 만큼 쌓인 에너지가 방치되면 수면과 감정 기복 쪽 값이 먼저 흔들립니다. 주에 한 번 자기 상태를 짧게 적어 두는 것만으로 값이 유지됩니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '다만 총량은 큰데 전달 항목의 값이 낮으면 엇갈리는 구간이 쌓입니다. 혼자 해석하는 대신 직접 묻는 쪽이 이 구성에서 가장 빠른 방법입니다.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '다만 활력은 높은데 안정성 값이 낮으면 에너지가 여러 방향으로 흩어집니다. 수면·식사·운동 세 축을 먼저 잡아 두는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '다만 외부 시선이 있을 때와 없을 때의 값 차이가 크게 측정됩니다. 사람이 빠지면 온도가 함께 내려가는 구성이라, 혼자 있을 때 켜지는 자기 리듬을 따로 만들어 두는 쪽이 안정적입니다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '다만 활력이 높은데 안정성으로 강하게 눌린 구성입니다. 겉으로는 단단한데 안에서 압력이 올라가니, 운동·취미·대화 중 하나를 출구로 두세요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '다만 감각 항목의 값은 높고 실행 항목의 값은 낮습니다. 이 간격을 없앨 필요는 없고, 한 달에 하나씩 실제로 옮겨 보는 쪽이 값을 유지합니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '다만 세 항목이 함께 낮으면 관계가 생활의 편의 쪽으로만 수렴하기 쉽습니다. 같이 발견한 취향, 같이 웃은 장면 쪽으로 값을 올리는 편이 맞습니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '다만 두 항목이 평균 이하에서 섞이면 리듬이 자동으로 반복됩니다. 조명·시간대·공간 중 하나만 주기적으로 바꿔도 값이 다시 올라갑니다.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '다만 감정 항목의 진폭이 활력의 방향을 크게 흔듭니다. 감정을 점검하는 대화 루틴 하나가 이 구성의 안전판이 됩니다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '다만 인중 쪽 항목이 두드러져 호르몬 리듬이 컨디션에 직접 반영됩니다. 주기와 컨디션의 상관을 기록해 두면 자기 패턴이 보이는 구성입니다.',
  ]),
  _Frag(_lowOf(Attribute.libido), [
    '다만 이 항목이 낮으면 남들만큼 높아야 한다는 기준에서 먼저 벗어나야 합니다. 낮은 값을 결함이 아니라 방향으로 읽는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 활력은 긴 구간에 걸쳐 소리 없이 낮아집니다. 계절이 바뀔 때마다 자기 상태를 점검하는 짧은 루틴이 값을 받쳐 줍니다.',
    '다만 활력의 리듬은 업무·수면·계절 같은 외부 조건에 크게 흔들립니다. 마감 주간에 값이 떨어지는 건 결함이 아니라 정상 반응입니다.',
  ]),
];

final List<_Frag> _v2VitalityShadowMale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '다만 총량이 큰 만큼 쌓인 에너지가 방치되면 수면과 집중 쪽 값이 먼저 흔들립니다. 주에 한 번 자기 상태를 짧게 적어 두는 것만으로 값이 유지됩니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '다만 총량은 큰데 전달 항목의 값이 낮으면 엇갈리는 구간이 쌓입니다. 혼자 해석하는 대신 직접 묻는 쪽이 이 구성에서 가장 빠른 방법입니다.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '다만 활력은 높은데 안정성 값이 낮으면 에너지가 여러 방향으로 흩어집니다. 수면·식사·운동 세 축을 먼저 잡아 두는 쪽이 이 구성에 맞습니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '다만 외부 시선이 있을 때와 없을 때의 값 차이가 크게 측정됩니다. 사람이 빠지면 온도가 함께 내려가는 구성이라, 혼자 있을 때 켜지는 자기 리듬을 따로 만들어 두는 쪽이 안정적입니다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '다만 활력이 높은데 안정성으로 강하게 눌린 구성입니다. 겉으로는 단단한데 안에서 압력이 올라가니, 운동·취미·대화 중 하나를 출구로 두세요.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '다만 감각 항목의 값은 높고 실행 항목의 값은 낮습니다. 이 간격을 없앨 필요는 없고, 한 달에 하나씩 실제로 옮겨 보는 쪽이 값을 유지합니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '다만 세 항목이 함께 낮으면 관계가 생활의 편의 쪽으로만 수렴하기 쉽습니다. 같이 발견한 취향, 같이 웃은 장면 쪽으로 값을 올리는 편이 맞습니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '다만 두 항목이 평균 이하에서 섞이면 리듬이 자동으로 반복됩니다. 조명·시간대·공간 중 하나만 주기적으로 바꿔도 값이 다시 올라갑니다.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '다만 감정 항목의 진폭이 활력의 방향을 크게 흔듭니다. 감정을 점검하는 짧은 대화 루틴 하나가 이 구성의 방파제가 됩니다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '다만 인중 쪽 항목이 두드러져 호르몬 리듬이 컨디션에 직접 반영됩니다. 수면이 부족하면 얼굴부터 값이 떨어지는 구성입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 활력은 긴 구간에 걸쳐 소리 없이 낮아집니다. 계절이 바뀔 때마다 자기 상태를 점검하는 짧은 루틴이 값을 받쳐 줍니다.',
    '다만 활력의 리듬은 업무·수면·계절 같은 외부 조건에 크게 흔들립니다. 마감 주간에 값이 떨어지는 건 결함이 아니라 정상 반응입니다.',
  ]),
];

final List<_Frag> _v2VitalityAdvice = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '두 항목이 함께 높습니다. 총량이 큰 만큼 쓰는 자리를 정해 두는 게 핵심이고, 새로운 대상을 늘리기보다 같은 자리에서 각도를 바꾸는 쪽에서 값이 가장 높게 유지됩니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.sensuality) != _Band.high,
    [
      '활력 항목의 값이 높습니다. 숨길 필요는 없고, 그 에너지를 어떻게 표현하느냐에서 값이 갈리니 원하는 것을 먼저 말로 꺼내는 연습이 이 구성에 맞습니다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '값의 뿌리가 감각의 해상도 쪽에 있습니다. 향·음악·시간대 같은 조건을 매달 하나씩 바꿔 보는 작은 실험이 값을 두텁게 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '두 항목 모두 평균대입니다. 큰 진폭 없이 오래 유지되는 구성이라, 속도가 맞는 상대를 알아보는 눈이 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '규칙적이고 담담한 구성입니다. 컨디션이 유독 잘 올라오는 조건 — 계절, 환경 변화, 새 경험 — 을 기록해 두면 자기 패턴이 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '총량보다 감각과 상상 쪽에 값이 몰려 있습니다. 정서적·지적 교감이 깊은 관계에서 값이 올라가니, 짧게 평가되는 자리는 이 구성에 맞지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '조건이 겹쳐야 값이 올라가는 구성입니다. 긴 호흡의 관계를 찾는 게 곧 전략이고, 값이 올라가는 조건 — 신뢰, 공간, 반복 — 을 상대와 말로 공유해 두세요.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) != _Band.low,
    [
      '활력이 감정의 온도를 따라 움직이는 구성입니다. 반응이 느린 게 아니라 순서가 다른 것이니, 정서적 결합이 깊어질수록 값이 함께 올라갑니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '세 항목이 모두 낮게 정돈된 구성이고, 이건 결함이 아니라 방향입니다. 서로의 페이스를 존중하는 쪽이 관계 항목의 값을 가장 크게 좌우합니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '활력은 부수 항목이 아니라 컨디션 전체를 받치는 축입니다. 자기 리듬을 솔직하게 들여다보고 표현과 대화의 언어를 기르는 쪽이 값을 유지합니다.',
    '이 항목을 가꾸는 건 셋입니다. 자기 리듬을 정기적으로 관찰하고 기록할 것, 값이 올라가는 조건을 먼저 정의할 것, 숨길 것이 아니라 가꿀 것으로 대할 것.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대에는 활력이 일과 가정의 압박에 가장 먼저 밀립니다. 주 1회 자기 감각을 회복하는 시간을 의식적으로 잡아 두는 쪽에서 값이 유지됩니다.',
    '30~40대의 활력은 직접적인 강도보다 태도와 여운 쪽으로 값이 옮겨 갑니다. 자기 속도를 알고 있는 쪽에서 이 전환이 자연스럽게 일어납니다.',
    '30~40대에는 새 대상을 찾기보다 익숙한 자리에 변주를 주는 쪽에서 값이 높게 나옵니다. 익숙함을 권태로 두지 마세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 활력은 외형보다 살아온 흔적 쪽에서 값이 나옵니다. 자기를 다듬어 온 시간이 그대로 이 항목에 반영됩니다.',
    '50대 이후에는 은퇴 뒤의 역할 전환이 활력 값을 크게 좌우합니다. 사라진 자리를 새 역할로 채우지 못하면 값이 빠르게 떨어집니다.',
    '나이가 들수록 활력은 강도보다 지속에서 측정됩니다. 함께 마시는 커피, 같이 보는 풍경, 매년 가는 여행지 같은 일상의 반복이 값을 받쳐 줍니다.',
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
    '사회성이 같은 성별·얼굴형 분포에서 @{pct:sociability} 구간이고, 신뢰성도 함께 높습니다. 빨리 여는 항목과 오래 유지하는 항목이 같이 높게 나오는 조합은 흔하지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '사회성이 @{pct:sociability} 구간이고 신뢰성은 평균대입니다. 낯선 자리를 푸는 항목의 값은 높고, 마음을 다 여는 데 걸리는 시간은 평균에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '사회성은 @{pct:sociability} 구간인데 신뢰성이 낮은 쪽입니다. 사람을 모으는 항목의 값은 높고 이어 가는 항목의 값은 낮게 측정됩니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '사회성은 평균대이고 신뢰성이 @{pct:trustworthiness} 구간입니다. 화려하게 끌어당기는 쪽보다 시간이 지날수록 곁에 남는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '사회성과 신뢰성이 모두 평균대에 놓여 있습니다. 넓게 두루 지내기보다 정해 둔 몇 사람에게 값이 몰리는 쪽입니다.',
    '두 항목 모두 @{pct:sociability} 구간 근처로 분포 가운데에 있습니다. 나설 때와 빠질 때가 상황에 따라 갈리는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '사회성은 평균대이고 신뢰성이 @{pct:trustworthiness} 구간입니다. 그냥 두면 관계가 쌓이지 않고, 정기 모임 하나만 두면 유지되는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '사회성은 @{pct:sociability} 구간이고 신뢰성이 높은 쪽입니다. 새로 여는 항목의 값은 낮고 한 번 열린 관계를 유지하는 항목의 값이 높게 나옵니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사회성이 @{pct:sociability} 구간이고 신뢰성은 평균대입니다. 먼저 다가가 늘리는 쪽보다 이미 아는 사람을 꾸준히 챙기는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '사회성과 신뢰성이 모두 분포 아래쪽에 있습니다. 값이 관계 쪽보다 다른 항목에 몰려 있다는 뜻이고, 혼자 있는 시간에서 결과물이 나오는 경우가 많습니다.',
  ]),
  _Frag.hard((f) => true, [
    '사회성이 @{pct:sociability} 구간으로 측정됩니다. 한쪽으로 쏠린 값이 없어 넓이와 깊이 사이에서 균형을 잡는 쪽이 많습니다.',
    '첫인상 항목보다 몇 번 만난 뒤의 편안함 항목에 값이 몰려 있습니다. 시간이 갈수록 사람이 붙는 구성입니다.',
    '두루 지내는 항목의 값은 높은데 마음을 주는 대상의 수는 좁게 측정됩니다.',
    '말수와 무관하게 중재 자리에 놓이는 쪽에 값이 실려 있습니다.',
  ]),
];

final List<_Frag> _v2SocialVignette = [
  _Frag(_highOf(Attribute.trustworthiness), [
    '부탁을 웬만하면 들어주면서 속으로 한도를 세는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '겉으로 괜찮다고 해 놓고 뒤에 오래 곱씹는 경우가 이 구간에서 더 자주 관찰됩니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '평소에는 넘어가다가 선을 넘은 순간에 단번에 선을 긋는 쪽입니다.',
  ]),
  _Frag(_lowOf(Attribute.sociability), [
    '여럿이 모인 자리보다 한두 명과 있을 때 값이 높게 나오고, 모임 뒤 회복 시간이 필요한 쪽입니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '자리가 어색해질 때 먼저 말을 꺼내 푸는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '모두에게 좋은 사람이려다 정작 가까운 사람에게 쓸 에너지가 모자라는 패턴이 자주 관찰됩니다.',
    '연락은 늘 상대가 먼저인 것 같은데 자기가 먼저 하기는 어려워하는 쪽입니다.',
    '두루 잘 지내는 항목의 값은 높은데 속 얘기를 꺼내는 대상의 수는 좁게 측정됩니다.',
  ]),
];

final List<_Frag> _v2SocialStrength = [
  _Frag.hard((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입과 눈 항목이 함께 움직이는 것으로 측정됩니다. 대화 리듬 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '옆면 콧대 항목의 값이 높게 나옵니다. 중요한 순간에 자기 의견을 내는 쪽이라 관계가 한쪽으로 끌려가지 않습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-SN'), [
    '코끝 각도 항목의 값이 높습니다. 낯선 자리에 섞여드는 속도가 평균보다 빠르게 측정됩니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.8, [
    '입 항목의 값이 뚜렷하게 높습니다. 설득하거나 중재하는 자리에서 값이 올라가는 구성입니다.',
  ]),
  _Frag.hard((f) => f.fired('P-10') || f.nodeZ('eye') >= 0.8, [
    '눈 항목의 값이 높게 측정됩니다. 첫인상에서 경계가 풀리는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹 항목의 값이 평균 위에 있습니다. 또래나 동료 사이에서 중재 역할이 돌아오는 쪽입니다.',
  ]),
  _Frag.hard((f) => true, [
    '오래 갈 소수와 스쳐 갈 다수가 비교적 또렷하게 나뉘는 구성입니다. 시간이 지날수록 가까운 관계만 남는 쪽입니다.',
    '말수와 무관하게 가운데 자리에 놓이는 쪽에 값이 몰려 있습니다.',
    '상대 기분을 읽고 반응 온도를 맞추는 항목의 값이 평균보다 반 박자 빠릅니다. 불필요한 마찰이 적게 측정됩니다.',
    '한 번 한 약속을 지키는 항목의 값이 높습니다. 믿고 맡길 수 있다는 평이 따라오는 쪽입니다.',
  ]),
];

final List<_Frag> _v2SocialShadow = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 누구든 품으려는 쪽에 값이 몰려 먼저 지치기 쉽습니다. 주는 정이 받는 정을 오래 앞지르면 소진이 조용히 쌓입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 그냥 두면 관계가 줄어드는 방향으로 흐릅니다. 의식적으로 연락하는 장치가 없으면 중년 구간에서 값이 빠르게 떨어집니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '다만 처음의 열기가 식은 뒤 같은 사람을 챙기는 항목의 값이 낮습니다. 아는 사람 수와 깊은 얘기를 할 사람 수의 격차가 넓게 측정됩니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 거리 조절의 폭이 좁게 측정됩니다. 가까워지면 크게 들어가고 한 번 실망하면 단번에 멀어지는 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 중요한 사람에게 몰아주고 나머지를 두는 패턴이 있습니다. 정작 필요한 순간에 주변 값이 비어 있는 경우가 관찰됩니다.',
    '다만 남의 리듬에 맞추다 자기 회복 시간이 먼저 바닥납니다. 혼자 회복하는 시간을 따로 지켜야 관계의 질이 유지됩니다.',
    '다만 갈등을 피하려다 선 긋는 시점을 놓치기 쉽습니다. 싫다는 말을 제때 못 하면 손해 보는 자리에 서게 됩니다.',
    '다만 친했다가 떠난 사람에 대한 값이 가장 낮게 나옵니다. 모든 관계가 이어지지는 않는다는 걸 받아들이지 못하면 새 사람이 들어올 자리가 생기지 않습니다.',
    '다만 좋은 사람 소리를 지키려다 선택의 폭이 좁아지기 쉽습니다. 모두에게 같은 얼굴을 하면 가까운 관계의 값이 오히려 얕아집니다.',
  ]),
];

final List<_Frag> _v2SocialAdvice = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '두 항목이 함께 높습니다. 넓이는 이미 충분하니, 일 년에 한 번쯤 명단을 줄여 깊이 쪽으로 무게를 옮겨 보세요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '들어오는 항목의 값은 높고 끝까지 가는 항목의 값은 낮습니다. 처음 친해진 사람과 일 년 뒤에도 연락을 절반만 유지하는 습관 하나로 값이 크게 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '빨리 친해지고 빨리 식는 쪽에 값이 몰려 있습니다. 새 사람을 늘리기보다 이미 아는 한 명을 더 깊이 아는 쪽으로 에너지를 옮겨 보세요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '온도를 오래 유지하는 항목의 값이 높습니다. 먼저 안부 한 줄 보내는 월 1회 습관만 더하면 됩니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '두 항목 모두 평균대입니다. 석 달에 한 번 연락이 끊긴 사람 한 명을 일부러 다시 챙기는 습관이 이 구성에서 가장 크게 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '새로 섞이는 항목도 오래 가는 항목도 평균대입니다. 정기 모임 하나만 고정해 두면 관계 총량이 알아서 올라가는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '여는 항목의 값은 낮고 유지하는 항목의 값은 높습니다. 넓히려 애쓰기보다 있는 사람을 지키는 데 힘을 몰아주는 쪽이 효율이 큽니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사회성 항목의 값은 낮은데 이어 가는 항목은 평균대입니다. 새 사람을 만나는 부담은 내려놓고, 지금 있는 자리에서 역할을 한 단계 더 맡는 게 자연스러운 확장입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '관계 항목의 값이 다른 항목보다 낮게 측정됩니다. 고립을 걱정하기보다 혼자 쌓은 결과물을 보여줄 출구 하나를 만들어 두세요.',
  ]),
  _Frag.hard((f) => true, [
    '관계를 키우는 건 셋입니다. 온도를 오래 유지하기, 먼저 안부 건네기, 모두를 품으려 하지 않기.',
    '값은 한 번에 크게 친해지는 데서가 아니라 작은 연락을 놓치지 않는 데서 쌓입니다. 한 달에 한 줄이면 충분합니다.',
    '중요한 사람 다섯을 적고 이번 달 각자에게 쓴 시간을 세어 보세요. 그 숫자가 관계의 실제 지도입니다.',
    '들어오는 문과 나가는 문을 따로 두세요. 정리 없이 받기만 하면 안이 옅어지고, 받지 않고 정리만 하면 밖이 끊깁니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 깊이보다 폭 쪽에서 값이 크게 벌어집니다. 한 그룹에 일찍 굳어지면 35세 이후 관계 폭이 좁아지니, 자기와 다른 결의 사람을 일부러 만나 두세요.',
    '20대는 평판의 값이 처음 쌓이는 구간입니다. 화려한 인맥보다 지킨 약속의 누적이 실제 사회 자본으로 측정됩니다.',
    '20대에 서로의 약한 부분까지 나눌 수 있는 사람을 한 명이라도 만들어 두는 쪽에서 값이 높게 나옵니다. 같은 학교·직장 동기에 그치지 마세요.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대에는 20대에 쌓은 관계가 처음으로 자산으로 돌아옵니다. 다만 받기만 하고 흘려보내지 않으면 값이 빠르게 식습니다.',
    '30~40대에는 한 분야나 집단을 대표하는 자리에 놓이는 경우가 많아집니다. 책임을 피하지 않고 받아들이는 쪽에서 다음 단계가 열립니다.',
    '30~40대 관계의 핵심은 새 사람을 더하는 속도보다 오래 안 본 사람을 다시 만나는 빈도입니다. 분기에 한 번 세 명을 의도적으로 복원해 보세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 멘토링 쪽에서 값이 나옵니다. 쌓은 인맥과 통찰을 후배에게 흘려보내는 자리는 의식적으로 만들지 않으면 생기지 않습니다.',
    '50대 이후에는 깊은 친구 세 명이 지인 백 명보다 값이 큽니다. 새 인맥을 늘리는 욕심을 내려놓고 기존 관계를 두텁게 다지세요.',
    '50대 이후에는 의무 없는 정기 모임이 정신 건강 쪽 값을 가장 크게 받쳐 줍니다. 오래된 친구 모임, 공동 취미, 정기 산책 중 하나는 일부러 만들어 두세요.',
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
    '통찰력이 같은 성별·얼굴형 분포에서 @{pct:intelligence} 구간이고, 리더십도 함께 높습니다. 읽는 항목과 끌고 가는 항목이 같이 높게 나오는 조합은 흔하지 않습니다.',
    '통찰력과 리더십이 둘 다 분포 위쪽에 있습니다. 기획과 실행을 한 사람이 쥘 때 값이 가장 높게 나오는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '통찰력이 @{pct:intelligence} 구간이고 리더십은 평균대입니다. 앞장서는 항목보다 한 발 뒤에서 구조를 짜는 항목에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '통찰력은 @{pct:intelligence} 구간인데 리더십이 낮은 쪽입니다. 깊게 파는 항목의 값이 높고, 혼자 쌓는 시간이 길수록 결과가 커지는 구성입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '통찰력은 평균대이고 리더십이 @{pct:leadership} 구간입니다. 세부 분석보다 방향을 잡는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '통찰력과 리더십이 모두 평균대에 놓여 있습니다. 판단과 실행이 같이 가는 구성이라 시간 위에 올렸을 때 값이 정직하게 쌓입니다.',
    '두 항목 모두 @{pct:intelligence} 구간 근처로 분포 가운데에 있습니다. 어느 자리에 놓여도 그 자리의 언어를 빠르게 흡수하는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '통찰력은 평균대이고 리더십이 @{pct:leadership} 구간입니다. 그림을 그리는 쪽보다 손으로 결과를 만드는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '통찰력은 @{pct:intelligence} 구간이고 리더십이 높은 쪽입니다. 분석으로 결정을 미루기보다 먼저 움직이는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '통찰력이 @{pct:intelligence} 구간이고 리더십은 평균대입니다. 같은 일을 반복하는 중에 패턴을 잡아내는 항목의 값이 높게 나옵니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '통찰력과 리더십이 모두 분포 아래쪽에 있습니다. 값이 추상 판단 쪽보다 손끝·몸·감각 쪽에 몰려 있다는 뜻입니다.',
  ]),
  _Frag.hard((f) => true, [
    '재능 관련 항목이 한쪽으로 쏠리지 않고 여러 곳에 고루 분포합니다. 한 분야의 정점보다 서로 다른 두 세계를 잇는 쪽에서 값이 높게 나옵니다.',
    '한 번의 정점보다 3년·5년·10년 누적에서 값이 크게 나오는 구성입니다. 같은 일을 다른 각도로 반복할수록 깊이가 붙습니다.',
    '한 항목이 혼자 튀기보다 여러 항목이 같이 받쳐 주는 구성입니다. 독주보다 합주 쪽에서 값이 올라갑니다.',
  ]),
];

final List<_Frag> _v2TalentVignette = [
  _Frag(_highOf(Attribute.intelligence), [
    '남들이 상황을 파악하는 동안 결론까지 먼저 가 있는 쪽에 값이 몰려 있습니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '회의가 결론 없이 돌 때 정리를 자기가 맡는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.high &&
        f.bandOf(Attribute.leadership) == _Band.low,
    [
      '아이디어를 낸 쪽과 공을 가져가는 쪽이 갈리는 경우가 이 구성에서 자주 관찰됩니다.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '새로 배우는 항목의 값은 높은데 한 우물을 오래 파는 항목의 값은 낮게 측정됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '하나에 꽂히면 몰입하다가 관심이 식으면 단번에 손을 놓는 패턴이 자주 관찰됩니다.',
    '머리는 좋은데로 시작하는 평을 듣는 쪽에 값이 실려 있습니다.',
    '완성될 때까지 내놓지 않고 쥐고 있는 쪽에 값이 몰려 있습니다.',
  ]),
];

final List<_Frag> _v2TalentStrength = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹 항목의 값이 높게 측정됩니다. 새 지식을 흡수하는 속도와 방향을 유지하는 힘이 함께 높게 나옵니다.',
    '눈썹 항목이 짙고 정돈된 쪽으로 측정됩니다. 목표가 서면 결과까지 밀어붙이는 항목의 값이 높습니다.',
  ]),
  _Frag.hard((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '이마 항목의 값이 뚜렷하게 높습니다. 윗선의 기회가 비교적 먼저 들어오는 쪽에 값이 실려 있습니다.',
    '이마 항목이 반듯한 쪽으로 측정됩니다. 학습과 지도력의 기반 항목이 함께 열려 있는 구성입니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM'), [
    '눈과 입 항목이 함께 살아 있는 것으로 측정됩니다. 감정을 말로 옮기는 항목의 값이 높아 글·강연 쪽에서 설득력이 나옵니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대 항목의 값이 평균을 넘습니다. 혼자 해내는 쪽보다 사람을 통해 일을 키우는 쪽에서 값이 확장됩니다.',
    '광대 항목이 힘 있게 측정됩니다. 순수 전문가 자리보다 리더·관리 자리에서 값이 높게 나옵니다.',
  ]),
  _Frag.hard((f) => f.fired('O-FB'), [
    '이마와 턱 항목이 함께 단정하게 측정됩니다. 한 프로젝트를 처음부터 끝까지 맡을 때 값이 가장 높습니다.',
  ]),
  _Frag.hard((f) => f.nodeAZ('nose') >= 1.0, [
    '코 항목의 측정값이 평균을 크게 넘습니다. 자기 길에 대한 확신 항목의 값이 높아 외부 평가에 덜 흔들립니다.',
  ]),
  _Frag.hard((f) => f.fired('A-02'), [
    '이마 쪽 항목이 열린 것으로 측정됩니다. 또래보다 이른 구간에 한 번 치고 나가는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '한순간의 정점보다 시간에 정직하게 쌓이는 누적형 구성입니다. 값이 늦게 올라오는 쪽에 가깝습니다.',
    '첫 만남의 화력보다 세 번째 만남 뒤 자리 잡는 신뢰 항목에 값이 몰려 있습니다.',
    '결과만이 아니라 과정 끝까지 맡는 항목의 값이 높습니다. 마지막 20%를 물고 가는 쪽입니다.',
    '축이 두 개라 한쪽이 지치면 다른 쪽이 받칩니다. 정점은 늦게 와도 정체 구간이 짧게 측정됩니다.',
    '하나에 꽂혔을 때의 집중 항목이 값의 차이를 가장 크게 만듭니다.',
  ]),
];

final List<_Frag> _v2TalentShadow = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '다만 혼자 다 하려는 쪽에 값이 몰려 피로가 쌓이기 쉽습니다. 위임 항목의 값이 낮으면 상한이 자기 체력에 묶입니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.high &&
        f.bandOf(Attribute.leadership) == _Band.low,
    [
      '다만 앞에 나서는 항목의 값이 낮아 설계가 남의 이름으로 넘어가기 쉽습니다. 일부러 드러내는 습관 없이는 실력이 낮게 평가됩니다.',
    ],
  ),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.intelligence) == _Band.low &&
        f.bandOf(Attribute.leadership) == _Band.high,
    [
      '다만 직관 항목의 값이 높은 만큼 근거 없이 밀어붙이는 경우가 자주 관찰됩니다. 따져 주는 사람을 옆에 두지 않으면 빠른데 방향이 틀린 패턴이 반복됩니다.',
    ],
  ),
  _Frag(_lowOf(Attribute.stability), [
    '다만 흥미가 옮겨 가는 속도가 빠르게 측정됩니다. 머리가 먼저 가고 몸이 못 따라가면 값이 쌓이지 않고 흩어집니다.',
  ]),
  _Frag.hard(
    (f) =>
        f.bandOf(Attribute.emotionality) == _Band.high &&
        f.bandOf(Attribute.stability) != _Band.high,
    [
      '다만 감수성 항목의 값이 높은 만큼 비판에 흔들리는 폭도 넓게 측정됩니다. 외부 피드백을 거르는 기준이 이 구성의 핵심입니다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '다만 재능 항목의 값은 들인 시간에 정직하게 비례합니다. 남이 일찍 빛나는 데 흔들리면 값이 절반만 열린 채 흘러갑니다.',
    '다만 보여주는 항목의 값이 낮아 실력에 비해 덜 평가되는 경우가 반복됩니다. 일부러 내놓는 습관이 유일한 해법입니다.',
    '다만 완성도에 집착하는 쪽에 값이 몰려 있습니다. 70%에서 멈추지 못하고 쥐고 있다가 흐름을 놓치는 경우가 있습니다.',
    '다만 여러 분야를 얕게 건드리는 쪽으로 값이 흩어지기 쉽습니다. 호기심은 강점이지만 한 곳을 3년 파지 않으면 상한의 절반도 열리지 않습니다.',
  ]),
];

final List<_Frag> _v2TalentAdvice = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '판을 보는 항목과 앞장서는 항목이 함께 높습니다. 기획과 실행이 한 사람 안에서 도는 자리 — 창업·사업부·연구 책임 — 에서 값이 가장 높게 나옵니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '먼저 읽고 뒤에서 설계하는 쪽에 값이 몰려 있습니다. 참모·전략·아키텍트 자리에서 밀도가 가장 높습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '깊게 파는 항목의 값이 높습니다. 연구·분석·저술처럼 혼자 밀어붙이는 시간에서 값이 두꺼워지니, 앞에 서는 자리를 길게 두지 마세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '끌고 가는 항목의 값이 중심입니다. 디테일보다 방향, 논리보다 결단 쪽에서 값이 올라가니 팀·현장 지휘형으로 일찍 방향을 잡으세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '두 항목 모두 평균대입니다. 단기 폭발력은 낮아도 3·5·10년 누적 값이 평균을 확실히 넘으니, 맞는 판만 골라 두면 됩니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '말보다 손 쪽에 값이 실려 있습니다. 장인·실무·크래프트 트랙이 맞고, 3년 이상 머물면 평균을 넘는 깊이가 쌓입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '판을 직관으로 잡는 쪽에 값이 몰려 있습니다. 따져 주는 조력자를 옆에 두면 상한이 단번에 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '두 항목 모두 극단은 아닌데, 한 영역에 반복 노출되면 패턴을 잡는 항목의 값이 크게 올라갑니다. 같은 일을 3년 반복하는 환경이 가장 크게 작동합니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '값이 추상 판단 쪽보다 손끝·몸·감각 쪽에 몰려 있습니다. 숫자가 아니라 결과물의 완성도로 승부하는 쪽이 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재능을 살리는 건 셋입니다. @__STRONGEST_NODE__ 항목이 가장 잘 작동하는 환경을 일찍 고르기, 남의 속도와 비교하지 않기, 결과물을 정기적으로 바깥에 내놓기.',
    '재능은 방향과 들인 시간의 곱으로만 열립니다. 방향 잡는 항목의 값은 이미 높으니, 결정적 갈림길 서너 번에 외부 조언을 일부러 구하세요.',
    '하나를 십 년 파는 설계에 맞는 구성입니다. 여러 분야를 얕게 건드리면 상한이 오히려 낮아집니다.',
    '@__STRONGEST_NODE__ 항목을 외면하고 다른 길을 억지로 가면 같은 노력에서 값이 훨씬 낮게 나옵니다. 자기 결을 거스르지 마세요.',
    '상한을 올리는 건 피드백 빈도 하나입니다. 혼자 쌓기만 하면 자기 수준을 모르고, 작게라도 자주 내놓으면 두 배 빨리 큽니다.',
  ]),
  _Frag.hard(_isYoung, [
    '20대에는 한 길에 일찍 굳어지지 않는 쪽에서 값이 높게 나옵니다. 지금은 한 가지에 갇히지 말고 세 갈래쯤 동시에 얕게 시도해 보세요.',
    '20대는 학습 속도 항목의 값이 가장 높은 구간입니다. 지금 익히는 한 가지 기술·언어·도구가 기본 자산으로 남으니, 깊이보다 뼈대에 시간을 쓰세요.',
    '20대의 재능은 멘토·환경·동료 세 항목이 대부분을 정합니다. 자기보다 5~10년 앞선 사람 옆에 자리 잡은 쪽에서 값이 두 배 빠르게 올라갑니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 여러 시도가 한 줄기로 모이는 구간입니다. 강점을 중심으로 잔가지를 쳐내야 깊이가 생기고, 한 가지에 5,000시간을 쓰면 40대 후반에 값이 확연히 벌어집니다.',
    '30대 후반에서 40대 초반에 그동안 쌓은 값이 한꺼번에 모입니다. 다양성에서 깊이로, 실행에서 판단으로 무게 중심이 옮겨 가는 구간입니다.',
    '30~40대는 한 분야의 깊이로 다른 분야에 발판을 만드는 단계입니다. 가르치고·쓰고·연결하는 자리로 확장하지 않으면 40대 후반에 상한이 닫힙니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후에는 전수 쪽에서 값이 나옵니다. 새로 쌓는 일보다 잘 흘려보내는 설계가 이 구간의 핵심입니다.',
    '50대 이후에는 실행보다 판단으로 무게 중심이 옮겨 갑니다. 세부 실행을 후배에게 맡길 줄 알아야 값이 유지되고, 혼자 다 하려는 쪽이 가장 큰 함정입니다.',
    '50대 이후에는 쌓은 경험을 책·강의·멘토링·자문 같은 외부 자산으로 전환하는 5~10년 구간에서 값이 가장 크게 되돌아옵니다.',
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
    "전체 측정에서 양의 축이 뚜렷하게 앞섭니다. '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 얹혀 있고, 관통하는 축은 강건·진취·돌파 쪽입니다.",
  ]),
  _Frag.hard(_yinStrong, [
    "전체 측정에서 음의 축이 뚜렷하게 앞섭니다. '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 흐르고, 감싸는 축은 수렴·포용·유연 쪽입니다.",
  ]),
  _Frag.hard(_yyHarmony, [
    "음과 양의 축이 고르게 측정되는 조화형입니다. '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 겹친 위에 강함과 부드러움을 바꿔 쓰는 항목의 값이 높습니다.",
  ]),
  _Frag.hard((f) => f.specialArchetype != null, [
    "여러 영역을 한 장으로 모으면 '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 겹쳐 흐릅니다. 여기에 '@__SPECIAL_ARCHETYPE__'이 같이 측정되는데, 흔하게 나오는 조합은 아닙니다.",
  ]),
  _Frag.hard((f) => true, [
    "여러 영역을 한 장으로 모으면 '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐릅니다. 먼저 보이는 건 '@__PRIMARY_ARCHETYPE__'인데, 값이 실제로 몰려 있는 쪽은 '@__SECONDARY_ARCHETYPE__'입니다.",
    "'@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 얼굴에 겹쳐 측정됩니다. 한 방향으로만 힘이 쏠리지 않아 상황에 따라 두 결을 번갈아 쓰는 쪽이 많습니다.",
  ]),
];

final List<_Frag> _v2ConcludeStage = [
  _Frag.hard((f) => f.age.isOver50, [
    '지금 구간에서 값이 가장 크게 갈리는 건 덜어내는 쪽의 판단입니다. 쌓아 올리는 구간은 상당 부분 지나왔고, 남길 것과 흘려보낼 것을 가르는 기준이 이 구간의 중심축입니다.',
  ]),
  _Frag.hard((f) => f.age.isOver30 && !f.age.isOver50, [
    '지금 구간에서 값이 가장 크게 갈리는 건 축적의 설계입니다. 초기 재능이 드러난 구간이고, 앞으로 10년 동안 그 재능을 어떤 시스템 위에 올리느냐에서 차이가 벌어집니다.',
  ]),
  _Frag.hard((f) => f.age.isOver20 && !f.age.isOver30, [
    '지금 구간에서 값이 가장 크게 갈리는 건 자기 결을 세우는 일입니다. 윤곽은 드러났지만 아직 주변에 맞춰 깎이기 쉬운 구간이라, 답을 서둘러 찾기보다 자기 질문을 또렷이 세우는 게 먼저입니다.',
  ]),
  _Frag.hard((f) => !f.age.isOver20, [
    '지금 구간에서 값이 가장 크게 갈리는 건 가능성의 폭입니다. 아직 어느 방향으로도 굳지 않은 구간이라 경험의 폭이 그대로 다음 구간의 깊이로 이어집니다.',
  ]),
];

final List<_Frag> _v2ConcludeAdvice = [
  _Frag.hard((f) => true, [
    '마지막으로 짚어 둘 게 있습니다. 이 리포트는 얼굴 계측값이 같은 성별·얼굴형 분포에서 어디에 놓이는지를 읽은 것이지, 앞일을 맞히는 게 아닙니다. 측정값은 지형을 보여줄 뿐이고, 어느 방향으로 얼마나 걷는지는 오늘의 선택이 정합니다. 강점은 더 쓰고 약한 고리는 먼저 알아차리는 쪽에 서세요.',
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
