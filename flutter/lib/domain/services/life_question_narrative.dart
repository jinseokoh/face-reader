import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/yin_yang.dart';

const _nodeDominantPalaceKo = <String, String>{
  'forehead': '직장 운',
  'glabella': '기본 운',
  'eyebrow': '형제 운',
  'eye': '가정 운',
  'nose': '재물 운',
  'cheekbone': '권력의 자리',
  'philtrum': '자녀 운',
  'mouth': '말과 식복의 자리',
  'chin': '턱 부근',
  'upper': '이마 부근',
  'middle': '코·광대 부근',
  'lower': '입·턱 부근',
  'face': '얼굴 전체',
};

// 노드별 한글 라벨 — 얼굴-특화 slot 해결용.
const _nodeKoLabels = <String, String>{
  'forehead': '이마',
  'glabella': '미간',
  'eyebrow': '눈썹',
  'eye': '눈',
  'nose': '코',
  'cheekbone': '광대',
  'philtrum': '인중',
  'mouth': '입',
  'chin': '턱',
  'upper': '이마 부근',
  'middle': '코·광대 부근',
  'lower': '입·턱 부근',
  'face': '얼굴 전체',
};

// ─── Slot Pools (lexical variety) ────────────────────────────────────────

const Map<String, List<String>> _slotPools = {
  'intense': [
    '뚜렷이', '선명하게', '또렷이', '분명하게', '진하게', '짙게',
    '완연히', '농후하게', '똑똑히', '명징하게', '확연히',
  ],
  'faint': [
    '은은히', '잔잔히', '고요히', '여리게', '희미하게',
    '아련하게', '살포시', '가볍게', '옅게',
  ],
  'noble_g': [], // gender 분기 — _m, _f 사용
  'noble_m': [
    '듬직한', '의젓한', '당당한', '호방한', '태산 같은', '사내다운',
    '품 넓은', '대범한', '담대한',
  ],
  'noble_f': [
    '품격 있는', '단아한', '기품 있는', '우아한', '고상한',
    '정갈한', '곱게 정돈된', '반듯한', '결이 고운',
  ],
  'person_g': [],
  'person_m': ['남자', '사내', '한 사람', '대범한 이', '듬직한 이'],
  'person_f': ['여자', '여인', '한 사람', '단아한 이', '품격 있는 이'],
  'rare': [
    '매우 드물게도', '남달리', '유난히', '보기 드물게', '특별히', '귀하게',
    '흔치 않게', '각별히', '남들과 달리', '격이 다르게',
  ],
  'observe': [
    '읽어내는', '꿰뚫어 보는', '짚어내는', '알아차리는', '가늠하는', '헤아리는',
    '간파하는', '포착하는', '직감하는', '예리하게 보는',
  ],
  'act': [
    '밀어붙이는', '결단하는', '앞장서는', '이끌어 가는', '움직이는', '뚫고 나가는',
    '해내는', '돌파하는', '전진하는', '장악하는',
  ],
  'gentle': [
    '섬세한', '부드러운', '유연한', '결이 고운', '차분한', '세심한',
    '온화한', '유순한', '말쑥한', '다정한',
  ],
  'strong_adj': [
    '단단한', '묵직한', '듬직한', '굳건한', '우직한', '견실한',
    '단호한', '흔들림 없는', '강단 있는', '꿋꿋한',
  ],
  'open_wide': ['넓게', '시원하게', '훤히', '환하게', '크게', '탁 트여', '광활하게'],
  'clear_adj': ['맑게', '밝게', '환하게', '탁 트인 듯', '깨끗이', '청명하게'],
  'deep': ['깊이', '깊숙이', '두텁게', '짙게', '진하게', '깊이 있게'],
  'subtle': ['은근한', '은밀한', '잔잔한', '고요한', '차분한', '미묘한', '그윽한'],
  'structure': ['구조', '결', '면모', '기질'],
  'palace_career': ['직장 운', '일 운', '커리어 운'],
  'palace_wealth': ['재물 운', '돈 운', '재정 운'],
  'palace_destiny': ['기본 운', '이마 한가운데', '미간의 기운'],
  'palace_social': ['대인 운', '바깥 활동 운', '인연의 자리'],
  'palace_servant': ['부하 운', '후배 운', '아랫사람의 자리'],
  'palace_mate': ['배우자 운', '결혼 운'],
  'palace_sex': ['자녀 운'],
  'palace_home': ['가정 운', '집안 운'],
  'palace_health': ['건강 운', '콧대 위쪽 자리'],
  'palace_bro': ['형제 운', '동료 운'],
  'peach': ['끌어당기는 기운', '매력의 기운', '사람을 부르는 기색'],
  'energy_yang': ['양의 기운', '강건한 기운', '밝은 기세'],
  'energy_yin': ['음의 기운', '부드러운 기운', '잔잔한 윤기'],
  'zone_up': ['이마 부근', '이마 영역의 기운'],
  'zone_mid': ['코·광대 부근', '얼굴 중간 영역의 기운'],
  'zone_down': ['입·턱 부근', '얼굴 아래 영역의 기운'],
  'mount_n': ['턱의 중심', '아래턱'],
  'mount_s': ['이마 중앙'],
  'mount_c': ['코의 중심', '콧대'],
  'mount_e': ['왼 광대'],
  'mount_w': ['오른 광대'],
  'organ_brow': ['눈썹'],
  'organ_eye': ['눈'],
  'organ_nose': ['코'],
  'organ_mouth': ['입'],
  'fortune_word': [
    '복', '운', '재물 운', '복덕', '재운', '직장 운', '장수 운',
  ],
  'result_shine': [
    '돋보입니다', '빛납니다', '두드러집니다', '또렷합니다', '드러납니다',
    '선명히 읽힙니다', '확연합니다', '인상 깊게 남습니다',
  ],
  'result_carry': [
    '실려 있습니다', '담겨 있습니다', '배어 있습니다', '서려 있습니다',
    '녹아 있습니다', '깃들어 있습니다', '자리합니다',
  ],
  'heart': ['마음', '속마음', '속결', '진심', '속내', '심정'],
  'talent_word': [
    '재능', '기질', '타고난 결', '본래의 그릇',
    '자질', '타고난 재주', '본바탕', '천성',
  ],
  'fate_word': ['인연', '운', '복', '운명', '연', '인생의 흐름'],
  'path_word': ['길', '걸음', '여정', '경로', '방향'],
  // 2인칭 경험 예언 어미 — "~란 말 들어봤을 겁니다" 톤.
  'heard': [
    '들어봤을 겁니다', '들어본 적 있을 거예요', '한 번쯤 들어봤을 법합니다',
    '듣곤 했을 겁니다', '들어봤을 법합니다',
  ],
};

// 한 줄 평(@__ONELINER__) 생성용 — attribute 별 "…ㄴ" 형용 clause.
// 상위 2 attribute 를 "겉으론 X한데, 속은 Y 사람" 대비 문장으로 엮는다.
const _attrOneLinerTail = <Attribute, String>{
  Attribute.wealth: '돈을 잘 모으는',
  Attribute.leadership: '앞에 나서는',
  Attribute.intelligence: '머리가 빠른',
  Attribute.sociability: '사람 좋아하는',
  Attribute.emotionality: '마음이 깊은',
  Attribute.stability: '진득한',
  Attribute.sensuality: '분위기 있는',
  Attribute.trustworthiness: '믿음직한',
  Attribute.attractiveness: '매력 있는',
  Attribute.libido: '열정적인',
};

String _buildOneLiner(Attribute top, Attribute second) {
  final a = _attrOneLinerTail[top] ?? '균형 잡힌';
  final b = _attrOneLinerTail[second] ?? '단단한';
  return '"겉으론 $a데, 속은 $b 사람."';
}

final List<_Frag> _concludeAdvice = [
  _Frag.hard((f) => true, [
    '마지막으로, 관상은 예언이 아니라 지도입니다. 타고난 생김새는 길의 지형을 보여줄 뿐, 어떤 속도로 어디로 걷느냐는 오늘의 당신이 정합니다. 같은 얼굴이라도 누구는 장점을 20%만 열고 지나가고, 누구는 약점까지 무기로 바꿔 80%를 엽니다. 강점은 더 밀어붙이고, 그림자는 먼저 알아차리는 쪽에 서세요. 가장 좋은 풍경은 \'알고 선택한 사람\'에게만 열립니다.',
  ]),
];

// ═══ 8. 종합 조언 ═══

// archetype 레이블은 _resolveText Step 0 에서 runtime features 로 치환된다.
final List<_Frag> _concludeOpening = [
  _Frag.hard(_yangStrong, [
    "당신 얼굴은 양의 기운이 짙은 편입니다. '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 얹혀 있는데, 전체를 관통하는 축은 강건·진취·돌파입니다. 결정적인 순간에 머뭇거리지 않고 선을 넘는 기질이 당신의 궤적을 만듭니다.",
  ]),
  _Frag.hard(_yinStrong, [
    "당신 얼굴은 음의 기운이 깊은 편입니다. '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 흐르지만, 전체를 감싸는 건 수렴·포용·유연의 기운입니다. 서두르지 않고 시간을 편으로 삼는 게 평생 자산입니다.",
  ]),
  _Frag.hard(_yyHarmony, [
    "당신 얼굴은 음과 양이 고르게 맞물린 조화형입니다. '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 겹친 위에 강함과 부드러움을 자유롭게 바꿔 쓰는 중용이 있어서, 어떤 환경에서도 자기 자리를 빨리 찾습니다.",
  ]),
  _Frag.hard((f) => f.specialArchetype != null, [
    "여러 영역을 한 장으로 모아 보면, '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 겹쳐 흐릅니다. 특히 '@__SPECIAL_ARCHETYPE__'이 같이 서려 있어서, 평범한 해석을 넘어서는 결정적 국면을 인생 중·후반에 한 번 이상 지나가게 될 가능성이 높습니다.",
  ]),
  _Frag.hard((f) => true, [
    "여러 영역을 한 장으로 모아 보면, '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐릅니다. 겉으로 먼저 보이는 건 '@__PRIMARY_ARCHETYPE__'이지만, 인생 중반을 실제로 움직이는 동력은 오히려 '@__SECONDARY_ARCHETYPE__' 쪽에 더 많습니다.",
    "당신 얼굴엔 '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 몸에 겹쳐 있어서, 한 방향으로만 힘을 쏟기보다 상황에 따라 두 얼굴을 번갈아 쓸 수 있습니다.",
  ]),
];

// 연령대별 배타 predicate — 가장 구체적 band 가 단독으로 매칭되도록.
final List<_Frag> _concludeStage = [
  _Frag.hard((f) => f.age.isOver50, [
    '지금 단계에서 강조되는 건 \'덜어내는 기술\'입니다. 쌓아 올리는 시기는 상당 부분 지나왔고, 이제부턴 남길 것과 흘려보낼 것을 가르는 판단이 말년의 빛깔을 정합니다. 오랜 세월이 빚은 깊이가 가장 풍성하게 드러나는 때입니다.',
  ]),
  _Frag.hard((f) => f.age.isOver30 && !f.age.isOver50, [
    '지금 단계에서 강조되는 건 \'축적의 설계\'입니다. 초기 재능이 드러난 시기고, 앞으로 10년 동안 그 재능을 어떤 시스템 위에 올리느냐가 평생 곡선의 기울기를 정합니다. 작은 선택들이 복리처럼 쌓여 5~7년 뒤 전혀 다른 풍경을 만듭니다.',
  ]),
  _Frag.hard((f) => f.age.isOver20 && !f.age.isOver30, [
    '지금 단계에서 강조되는 건 \'자기 결을 세우는 일\'입니다. 재능의 윤곽은 드러났지만 아직 주변에 맞춰 깎이기 쉬운 시기라, 지금 결을 또렷이 세우지 못하면 이후 10년의 선택이 계속 흔들립니다. 답을 서둘러 찾기보다 자기 질문을 또렷이 세우는 게 먼저입니다.',
  ]),
  _Frag.hard((f) => !f.age.isOver20, [
    '지금 단계에서 강조되는 건 \'가능성의 확장\'입니다. 아직 어느 방향으로도 굳지 않은 시기라, 경험의 폭이 그대로 나중의 얼굴에 새겨집니다. 지금의 다양성이 이후의 깊이를 정합니다.',
  ]),
];

// 관상가 한 줄 평 — 상위 2 attribute 를 "겉은 X, 속은 Y" 대비로 인용 가능한
// 한 줄로 굳힌다. @__ONELINER__ 는 _resolveText Step 0 에서 치환.
final List<_Frag> _concludeOneLiner = [
  _Frag.hard((f) => true, [
    '관상가 한 줄 평으로 요약하면 — @__ONELINER__',
    '한마디로 @__ONELINER__',
    '굳이 한 줄로 줄이면, @__ONELINER__',
  ]),
];

final List<_BeatPool> _conclusionBeats = [
  _concludeOpening,
  _concludeStage,
  _concludeAdvice,
  _concludeOneLiner,
];

final List<_Frag> _healthAdvice = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '타고난 기본기 위에 감정의 온도가 얹힌 "밀도 높은 수명"형입니다. 과신이 제일 큰 위험이니 증상 없을 때 미리 점검하고, 감정이 몸으로 번지는 통로—수면·심박·소화—를 매달 기록해 두세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '기본기는 단단한데 감정 파고가 크지 않은, 가장 관리가 쉬운 편입니다. 걱정보다 지루함이 적이니, 3년에 한 번 의무 검진 루틴만 박아두면 장수의 상한을 정직하게 따라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '기본기 좋고 감정 출렁임도 낮은 "둔감한 강체"입니다. 장점은 꾸준함, 단점은 약한 신호를 놓치는 것—검진 주기를 1.5년으로 짧게 잡는 것만으로 위험이 반감됩니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '체질은 평균, 감정 진폭이 큰 편입니다. 수명을 제일 많이 갉아먹는 게 과로가 아니라 "풀리지 않은 감정 누적"이니, 일기·상담·운동 중 하나를 감정 배수로로 못 박아 두세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 중용형입니다. 30대부터 들이는 건강 자산이 그대로 말년 기울기를 정하니, 수면·식사·운동 중 가장 약한 하나만 먼저 표준화하세요.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '"기계처럼 도는" 편이라 컨디션은 안정적인데, 서서히 나빠지는 걸 못 느낍니다. 체중·혈압·수면을 숫자로 재는 습관이 가장 든든한 방어선입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '체질은 예민하고 감정 진폭도 큰, 제일 조심해야 하는 편입니다. "남이 버티는 강도"를 기준 삼지 마세요. 감정이 몸으로 번지기 전에 끊는 루틴—명상·산책·상담—이 수명을 늘립니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '예민한 만큼 몸의 신호를 남보다 일찍 받는 이점이 있습니다. 그 신호를 "불안"이 아니라 "정보"로 번역하는 훈련이 핵심—일찍 알아채는 사람이 둔감한 사람보다 오래 건강합니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '체질도 예민하고 감정 기반도 얇은 편인데, 이건 약하다기보다 "정밀하다"에 가깝습니다. 거친 환경만 피하면 오래 가니, 과격한 운동보다 규칙적 수면과 예측 가능한 일상이 자산입니다.',
  ]),
  _Frag.hard((f) => true, [
    '건강을 지키는 셋: 수면·식사·운동 중 가장 약한 하나만 먼저 표준화하기, 몸의 "이상 없음"을 맹신 말고 증상 없을 때 정기 점검 박아두기, 감정의 피로가 몸으로 옮겨가는 통로를 스스로 알아두기. 이 셋이 맞물릴 때 수명의 상한이 열립니다.',
    '당신의 몸은 "한 해"가 아니라 "십 년" 단위로 계산됩니다. 30대 습관이 60대 몸에 그대로 복사되니, 지금 반복하는 한 가지를 10년 뒤 거울로 삼으세요.',
    '수명은 "정신·기운·체력" 셋입니다. 가장 먼저 흐려지는 축을 알아채는 사람은 셋을 따로 충전하고, 한 축만 충전하려는 사람은 나머지 둘이 마릅니다. 잠은 정신을, 호흡은 기운을, 식사는 체력을 채웁니다.',
    '건강의 첫 원칙은 단순합니다—"내 몸을 남의 잣대로 재지 말 것." 남이 버티는 강도, 회복 속도, 먹는 양 다 당신과 다른 설계입니다. 자기 리듬 찾는 데 1년 쓰는 사람이 남은 30년을 살립니다.',
    '@__STRONGEST_NODE__이 건강 곡선의 중심축입니다. 이 부위가 지치면 몸 전체가 흔들리고, 살아나면 다른 약점도 같이 회복됩니다. 가장 아끼는 부위를 가장 먼저 관리에 넣으세요.',
  ]),
  // age-stratified Advice — 20대 / 30~40대 / 50대 이후 건강 변곡점.
  _Frag.hard(_isYoung, [
    '20대에는 무리해도 다음 날 회복되니 손상이 눈에 안 보입니다. 그러나 그 손상은 5~10년 뒤에 한꺼번에 드러납니다. 30세 전에 수면 7시간, 주 3회 운동, 금연·금주 중 한 가지를 규칙으로 박아 두면 40대 의료비가 절반이 됩니다.',
    '20대 몸은 쓰는 만큼 돌려받지 않습니다. 지금 만든 습관 하나가 35세 이후 만성 질환이 생기느냐 안 생기느냐를 정합니다. 정기 검진을 "노인의 일"이라며 미루지 말고, 첫 종합 검진을 일찍 받아보세요.',
    '20대 정신 건강은 자기만의 휴식 리듬을 만드는 시기입니다. 또래나 SNS 비교 압력에 밀려 무조건 달리기만 하면 30대에 번아웃이 옵니다. 지금 필요한 건 더 노력하는 게 아니라 자기 속도를 정해두는 일입니다.',
  ]),
  _Frag.hard(_isMid, [
    '35~45세 사이에 20대에 쌓아둔 습관의 청구서가 처음으로 몸에 나타납니다. 가장 약한 한 가지(수면·식사·운동)부터 표준화하고, 정기 검진 주기를 1년으로 잡으세요. 이 시기에 검진을 빠뜨리는 게 가장 큰 위험입니다.',
    '일·가족·자산이 동시에 확장되는 시기라 자기 건강이 가장 마지막으로 밀립니다. 이때 쌓인 피로가 50대 만성 질환의 직접 원인이 됩니다. 매일 30분 운동과 연 1회 검진, 이 두 가지만 지키면 충분합니다.',
    '30~40대는 스트레스가 몸으로 곧장 가는 시기입니다. 해소하지 못한 감정이 위장·관절·수면으로 옮겨가는 패턴이 굳어집니다. 명상·상담·운동 중 하나는 감정 배출 통로로 꼭 만들어 두세요.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 건강은 작은 신호를 일찍 잡느냐로 갈립니다. 회복력이 더는 자산이 아니므로, 자각 증상이 없을 때 정기 검진을 받는 사람이 10년 더 건강하게 삽니다. @{mount_n}이 튼튼해도 정기 점검 없이는 그 잠재력이 실현되지 않습니다.',
    '"아직 멀쩡하다"는 자신감이 가장 큰 함정입니다. 60대 이후로는 검진 주기를 6개월로 줄이고, 남이 늙는 속도가 아니라 자기 속도를 기준 삼으세요. 큰 병은 자각 증상이 나타날 즈음엔 이미 늦은 경우가 많습니다.',
    '50대 이후에는 인간관계의 두께가 신체 회복력의 절반을 정합니다. 가족과 오랜 친구를 정기적으로 만나는 사람이 노년 면역이 강합니다. 운동도 혼자보다 함께하는 형태로 짜는 편이 낫습니다.',
  ]),
];

final List<_BeatPool> _healthBeats = [
  _healthOpening,
  _healthVignette,
  _healthStrength,
  _healthShadow,
  _healthAdvice,
];

// ═══ 7. 건강과 수명 ═══

// 행동 vignette — 몸·감정·습관이 일상에서 드러나는 한 컷.
final List<_Frag> _healthVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '스트레스를 받으면 제일 먼저 잠이나 소화로 티가 나서, 마음이 몸을 그대로 끌고 간다고 느낀 적이 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '남들 다 골골댈 때 혼자 멀쩡해서, "넌 체력 하나는 타고났다"는 말을 @{heard}.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.stability) == _Band.low && f.bandOf(Attribute.emotionality) == _Band.high, [
    '별일 아닌 것 같은데 몸이 먼저 반응해서, 검사하면 "스트레스성"이라는 말을 들어본 적이 있을 겁니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '무리한 다음 날, 예전 같으면 금방 회복됐을 텐데 더디다고 느낀 적이 있을 겁니다.',
  ]),
  _Frag.hard((f) => true, [
    '바쁘면 내 몸 챙기는 게 늘 제일 뒤로 밀린 적이 있을 겁니다.',
    '"좀 쉬어야겠다" 하면서도 정작 안 쉬고 미룬 적이 한 번쯤 있을 겁니다.',
    '검진 받으라는 말은 듣는데, "아직은 괜찮겠지" 하고 미뤄둔 적이 있을 겁니다.',
  ]),
];

final List<_Frag> _healthOpening = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '몸의 기본기가 단단한 위에 감정이 풍부해서 몸을 깨어 있게 만드는 편입니다. 큰 병에 잘 안 흔들리는 기본기와, 몸의 신호를 예민하게 잡아내는 감각이 한 얼굴에 같이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '체질이 두텁고 감정의 파고도 크지 않은, 가장 "흔들림이 적은" 편입니다. 큰 파고 앞에서도 중심이 잘 안 무너집니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '기본기는 단단한데 감정의 진폭은 옅은 "둔감한 강체"형입니다. 잔병에 덜 시달리는 대신, 몸이 보내는 약한 신호를 놓치기 쉬운 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '체질은 평균인데 감정의 진폭이 큰 편입니다. 몸 컨디션이 감정 온도를 그대로 따라가서, 풀리지 않은 감정이 특정 장기로 흘러가는 패턴이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 평균형입니다. 잘 관리하면 평균 이상, 방치하면 평균 이하로 갈리는 정직한 구조입니다.',
    '치명적 기울기는 없는데 생활 습관이 그대로 몸에 쌓입니다. 30대부터 들이는 건강 자산이 말년 곡선의 기울기를 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '몸도 감정도 큰 기복 없이 도는 "기계형"입니다. 컨디션은 안정적인데, 서서히 나빠지는 신호를 잡아내기 어려운 편이라 숫자로 재는 습관이 숨은 방어선입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '체질도 예민하고 감정의 폭도 큰, 제일 꼼꼼히 챙겨야 하는 편입니다. "약하다"기보다 "정밀하다"에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '체질의 저점이 남보다 낮은 구간을 자주 지나가는 편입니다. 대신 몸이 신호를 일찍 보내줘서, 그 신호를 잘 읽으면 둔감한 사람보다 오래 건강을 유지하는 역설이 있습니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '체질도 얇고 감정의 기반도 엷은 편입니다. 과격한 환경만 피하면 정밀한 기계처럼 오래 가는 타입이라, 규칙적 수면과 예측 가능한 일상이 곧 건강 자산입니다.',
  ]),
  _Frag.hard((f) => true, [
    '건강 곡선이 평균을 따르되, 특정 구간의 큰 점검 한 번이 전체를 좌우하는 편입니다. 약한 고리를 일찍 찾는 사람이 상한에 닿습니다.',
    '큰 병보다 잔잔한 누적이 두드러지는 편입니다. 매일의 작은 루틴 하나가 20년 뒤 체감 나이를 그대로 정합니다.',
    '급격한 상승도 하락도 없이 꾸준함으로 거리를 버는 "중용의 몸"입니다. 숨은 이점은 회복의 평균값이 남보다 반 박자 안정적이라는 점입니다.',
  ]),
];

final List<_Frag> _healthShadow = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '다만 "건강에 자신 있다"는 감각 자체가 제일 큰 위험입니다. 감정이 과열될 때 몸의 경고를 낙관으로 덮기 쉽고, 어느 순간 한꺼번에 무너지는 패턴이 따라옵니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 과로와 감정 소모에 약한 편입니다. "남이 버티는 강도를 나도 똑같이 버티지 않는다"—이 한 줄이 수명을 좌우합니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 기본기가 좋을수록 경고 신호를 묵살하고 밀어붙이다 한 번에 무너지기 쉽습니다. "아직 괜찮다"가 가장 위험한 말입니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 감정 진폭이 크면 몸도 그 진폭을 따라갑니다. 좋은 날과 무너지는 날의 컨디션 격차가 또래보다 넓으니, 감정 배수로 하나를 만들어 두는 게 핵심입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 수명을 갉아먹는 건 과로보다 풀리지 않은 감정의 누적인 편입니다. 감정 배수로 설계가 진짜 중심축입니다.',
    '다만 "작은 이상은 무시해도 된다"는 신호를 보내기 쉽습니다. 잔증상이 석 달 이어지는데 "버틸 수 있음"으로 해석하면, 나중에 한꺼번에 청구서가 옵니다.',
    '다만 중년 이후 "누적이 터지는 시점"이 한 번 옵니다. 20~30대의 과신과 40대의 소홀함이 모여 50대 어느 해에 정체를 만드니, 미리 알고 설계한 사람과 모르고 맞는 사람은 회복 속도가 다릅니다.',
    '다만 "피곤하지 않다"는 자각과 "실제 회복력이 떨어졌다"는 데이터 사이의 틈이 큰 편입니다. 그 틈을 메우는 유일한 길은 검진 숫자를 자각 증상보다 우선하는 것입니다.',
    '다만 제일 큰 위험은 "비교의 피로"입니다. 남의 리듬에 맞춰 굴릴수록 빨리 닳으니, 자기 속도의 기준선을 스스로 정해야 타고난 기본기가 오래갑니다.',
  ]),
];

final List<_Frag> _healthStrength = [
  _Frag.hard((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '콧대가 또렷한 편이라, 40대 전후의 "중년 건강 관문"을 미리 챙기는 게 좋습니다. 호흡기·순환기 쪽을 미리 점검해 두면 도움이 큽니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09'), [
    '이마 기운이 강한 편이라 머리를 많이 쓰는 기질입니다. 다른 무엇보다 수면의 질이 먼저 흔들리기 쉬우니 잠을 우선하세요.',
  ]),
  _Frag.hard((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '턱이 듬직한 편이라, 50대 이후에도 체력이 동년배보다 잘 안 떨어지는 "말년 강건"형입니다.',
  ]),
  _Frag.hard((f) => f.fired('P-05') || f.nodeZ('glabella') >= 0.5, [
    '미간이 맑게 자리한 편이라 정신적 피로의 회복력이 강합니다. 감정이 흔들려도 하룻밤 자면 기본선으로 돌아오는 쪽입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04'), [
    '턱 부근이 두툼해서 위장·신장 쪽 근기가 좋은 편입니다. 식습관의 축적이 가장 정직하게 수명으로 돌아오는 타입입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정의 해상도가 높아서 스트레스의 뿌리를 먼저 알아챕니다. 불안으로 방치만 안 하면 오히려 건강 관리의 조기 경보기가 됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '평균의 체질을 갖추되 한 가지 약한 고리가 있어서, 그 고리를 일찍 찾는 사람이 상한에 닿습니다.',
    '기운과 혈색이 고르게 흐르는 편이라 큰 파고가 없는 대신, 섬세한 유지가 필요한 타입입니다.',
    '한 장기의 강점보다 전체 균형에서 힘이 나오는 분산형이라, 한 군데가 무너져도 나머지가 보완해 줍니다.',
    '정신의 맑음이 몸의 활력으로 바로 번역되는 편이라, 스트레스 관리 하나가 다른 모든 지표를 좌우합니다.',
    '잘 쉬는 습관이 곧 가장 확실한 장수의 열쇠인 타입입니다. 정서가 안정되면 곧장 몸이 안정됩니다.',
  ]),
];

final List<_Frag> _romanceAdviceFemale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '매력의 화력과 감정의 해상도가 둘 다 짙은 편입니다. 제일 아까운 경우는 "설렘의 유통기한"만 쫓다 평생 자리를 못 정하는 것—세 번째 만남까지의 화력보다 3년째의 대화 밀도로 상대를 고르는 훈련이 연애의 질을 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '후보 폭이 넓은 만큼 "비교하는 습관"이 결정을 늦추기 쉽습니다. 선택 기한을 스스로 박아두는 게 가장 큰 전략—석 달 안에 답을 내는 규율 하나가 평생 인연을 바꿉니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '불러오는 자리는 넓게 열렸는데 속 대화는 상대적으로 얇은 편입니다. 겉의 열기에 휩쓸리지 말고 "같이 있을 때 대화가 이어지는 사람"을 한 축으로 더하세요. 열기가 식은 뒤 남는 게 거기 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '첫인상 스파크보다 "여러 번 겹친 대화"에서 상대가 당신을 발견하는 편입니다. 소개팅·앱 회전이 잘 안 맞으니, 공동 활동·관심사·동료 관계 속에서 쌓이는 인연 경로를 의식적으로 넓히세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 균형형입니다. 화려함 없이 단정하게 깊어지는 쪽이라, 첫눈에 끌리는 사람보다 두 달 뒤에도 안 피곤한 사람을 알아보는 눈이 가장 큰 자산입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '설렘의 강도보다 "안정된 리듬"을 우선합니다. 드라마틱한 연애를 기준 삼지 마세요—조용한 신뢰가 쌓일 때 진가가 나고, 주변에서 먼저 "결혼감"이라 평하는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '첫눈의 화력은 옅어도 감정의 결은 두꺼운 편입니다. 상대가 당신을 "알게 된 뒤" 관심이 눈에 띄게 짙어지는 후발형이라, 짧게 평가받는 자리보다 같은 공간을 여러 번 공유하는 경로를 만들면 인연이 쌓입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '매력도 감정도 한쪽으로 안 쏠린 편입니다. 연애가 인생의 전부가 아니어도 괜찮으니, "같이 있을 때 덜 피곤한 사람"을 고르는 게 맞습니다. 화려한 서사보다 일상 호흡이 맞는 사람입니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '연애가 인생의 중심축은 아닌 편입니다. 결핍이 아니라 방향이니, 동지 같은 파트너십도 진지하게 고려할 만합니다. 같은 속도가 아니어도 같은 방향을 보는 사람이 더 잘 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '연애를 살리는 셋: "끌리는 사람"과 "일상에 맞는 사람"을 따로 저울질하기, 비교하는 습관에 기한 두기, 그리고 이별의 품위. 마지막 장면이 다음 인연의 색을 정합니다.',
  ]),
  // age-stratified Advice (♀) — 20대 / 30~40대 / 50대 이후 연애 변곡점.
  _Frag.hard(_isYoung, [
    '20대 여성의 연애는 "내가 누구와 안 맞는지"를 배우는 시기입니다. 잘 안 된 만남을 정직하게 쌓아둔 사람이 30대에 더 편안한 관계를 만듭니다. 상대의 외모나 직업보다, 그 사람과 같이 있을 때 자신이 어떤 모습이 되는지를 기준으로 삼아 보세요.',
    '20대는 이상형의 그림은 그리되 거기에 갇히지 않는 게 중요합니다. 20대에 만난 사람이 평생 동반자가 될 확률은 통계적으로 낮습니다. 그러니 결과보다 과정에서 배우는 자세가 더 큰 자산이 됩니다.',
    '20대 연애는 자기 자신을 알아가는 거울입니다. 누구를 좋아하는지보다 좋아할 때 자신이 어떻게 변하는지를 관찰하면, 30대에 진짜 맞는 사람을 알아보기 쉬워집니다. 감정이 크게 흔들리는 시기일수록 큰 결정은 24시간 묵혀두는 습관이 도움이 됩니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대 여성의 연애는 같이 살림·자녀·돈을 굴릴 수 있는 사람인지가 핵심이 되는 시기입니다. 폭발적인 감정보다 일상이 잘 굴러가느냐가 더 중요해집니다. 감정의 정점보다 평균 상태를 보세요.',
    '30~40대의 인연은 "5년 뒤에도 같이 살 수 있는가"가 가장 정직한 기준입니다. 말이 화려한 사람보다 일상의 사소한 합의가 잘 되는 사람을 알아보는 눈이 가장 큰 자산입니다.',
    '30대 여성은 결혼·자녀·커리어 세 가지가 동시에 압박해 옵니다. 어느 한 축의 압력에 떠밀려 결정하지 마세요. 세 가지가 모두 잘 맞물리는 사람을 찾느라 1~2년 더 쓰는 사람이 평생 후회를 가장 적게 합니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 연애는 새로 시작하기보다 오랜 동반자와의 관계를 다시 다듬는 일이 더 큰 행복원이 됩니다. 자녀가 떠난 뒤 둘이 남는 시간이 길어지므로, 같이 할 취미·여행·소소한 프로젝트를 일부러 만들어 두세요. 일상의 리듬을 의식적으로 디자인하는 사람일수록 노년이 풍성해집니다.',
    '나이가 들수록 침묵이 쌓이기 쉽습니다. 매년 둘만의 작은 의례를 하나씩 새로 만드는 사람이 노년의 관계를 두텁게 가져갑니다. "이미 다 안다"는 익숙함이 가장 큰 함정입니다.',
    '50대 이후 여성의 연애운은 "혼자의 시간"의 질이 좌우합니다. 자기만의 세계(책·산책·취미·친구)를 가꾼 사람일수록 동반자와의 관계도 풍성해집니다. 혼자 즐길 줄 알아야 같이도 즐겁습니다.',
  ]),
];
final List<_Frag> _romanceAdviceMale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '매력과 감정의 해상도가 둘 다 짙은 "매혹형"입니다. 다만 자기 관리가 없으면 에너지가 사방으로 흩어지기 쉬우니, 한 관계를 깊이 파는 훈련이 평생 연애의 상한을 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '끌어당기는 힘은 강한데 감정의 미세 신호를 잡는 센서는 평균입니다. 설렘의 유통기한이 먼저 오는 편이라, "권태 구간을 피하지 않고 통과할 설계"—공동 프로젝트·여행 같은—를 분기에 하나씩 두세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '매력은 강한데 상대 속 이야기를 읽는 건 얇은 편입니다. "직관으로 이끌되 정기적으로 말로 확인하는" 루틴이 열쇠—한 달에 한 번 둘의 상태를 점수로 물어보는 의례가 효과적입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '겉의 화력보다 "대화의 밀도"로 상대를 사로잡는 편입니다. 앱 회전보다 동료·지인 네트워크 안에서 쌓인 신뢰가 연애로 넘어가는 경로가 훨씬 승률이 높습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 균형형입니다. 세 번째 만남 이후부터 진가가 나니, 첫 만남 평가에 흔들리지 말고 서너 번 겹친 장면으로 판단하세요. 남들이 부러워하는 관계가 여기서 가장 자주 나옵니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '안정된 리듬에 강점이 있습니다. 드라마틱한 연애보다 "피로가 안 쌓이는 관계"를 우선하세요—당신한텐 이쪽이 평생 오래 가는 선택입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '첫인상 화력은 옅은데 감정 해상도는 짙은 편입니다. 상대가 당신을 "알게 된 뒤" 호감이 크게 오르는 후발형이라, 짧게 평가받는 자리보다 같은 공간을 반복 공유하는 경로를 일부러 설계하세요.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '매력도 감정도 한쪽으로 안 쏠린 편입니다. 단정한 생활 기반·직업 안정 같은 축이 연애 매력으로 바뀌는 쪽이라, 겉의 연출보다 삶의 구조를 가꾸는 게 훨씬 큰 이득입니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '연애가 인생의 주축은 아닌 편입니다. 결핍이 아니라 방향이니, 자기 세계·직업·관심사의 깊이를 먼저 쌓으면 그게 파트너를 자연스럽게 끌어옵니다. 서두르지 않는 게 가장 좋은 전략입니다.',
  ]),
  _Frag.hard((f) => true, [
    '연애를 살리는 셋: "끌리는 상대"와 "일상에 맞는 상대"를 따로 보는 눈, 권태 구간을 피하지 않고 통과할 설계, 이별의 품격. 마지막 장면이 가장 오래 기억됩니다.',
  ]),
  // age-stratified Advice (♂) — 20대 / 30~40대 / 50대 이후 남성 연애 변곡점.
  _Frag.hard(_isYoung, [
    '20대 남성의 연애는 잘 시작하는 것보다 잘 헤어지는 법을 배우는 시기입니다. 깨끗하게 마무리한 한 번의 이별이 다음 인연 세 번의 깊이를 만듭니다. 외모·인기·트렌드에 흔들리기 쉬운 나이지만, 그 안에서 자기가 어떤 사람으로 변하는지를 관찰해 두는 게 30년 뒤 기준이 됩니다.',
    '20대에 만난 사람이 평생 동반자가 될 확률은 통계적으로 낮습니다. 그러니 지금은 결정을 내리는 시기가 아니라 기준을 만드는 시기입니다. 결과보다 과정에서 배우는 자세가 핵심입니다.',
    '20대 남성의 연애에서 가장 큰 함정은 외모 비교입니다. 키·외모·인기 차이를 매력의 본질로 보는 데서 벗어난 사람만이 30대에 진짜 매력을 키웁니다. 지금은 직업·취미·세계관 같은 자기만의 깊이를 쌓는 일이 가장 큰 연애 자산입니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대 남성의 매력은 외모보다 "이 사람과 미래를 같이 그릴 수 있는가"로 평가됩니다. 직업이 안정적이고 가치관이 일관된 두 가지가 핵심 축입니다. 외모의 빛은 가는 대신 신뢰가 매력으로 자리 잡는 시기입니다.',
    '30대 중반에는 결혼과 가정에 대해 책임지는 선택을 해야 하는 시기가 옵니다. 이 결정을 오래 미루면 30~40대 전성기의 흐름과 안정감이 흐트러질 수 있습니다. 특히 30대 후반의 선택이 이후의 가정생활·자녀·노후 행복에 큰 영향을 줍니다.',
    '30~40대 남성 연애의 가장 큰 함정은 욕심의 분산입니다. 직업·자산·취미·관계가 동시에 커지는 압박 아래 가장 먼저 희생되는 것이 동반자와의 시간입니다. 주 1회 둘만의 시간을 의무처럼 잡아두는 사람만이 40대 후반에 가정이 흔들리지 않습니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후 남성의 연애는 오랜 동반자의 의미를 다시 발견하는 시기입니다. 젊은 시절의 빛나는 감정보다 오래 함께 산 시간이 만든 깊이가 진짜 매력이 됩니다. 외형이 가는 자리에 신뢰와 일관성이 들어섭니다.',
    '50대 이후의 관계 재정비—함께 늙어갈 공통의 리듬, 같이 할 취미, 같이 갈 여행—이 노년 행복의 80%를 정합니다. 자녀가 떠난 뒤 둘이 남는 시간을 의식적으로 설계하지 않으면 침묵만 쌓입니다.',
    '50대 이후 남성 연애의 가장 큰 함정은 은퇴 뒤의 역할 상실입니다. 직업적 정체성이 사라진 자리를 동반자와의 새 역할로 채우지 못하면 가정에 무기력이 빠르게 쌓입니다. 여행·취미·자원봉사·자녀 양육 지원처럼 둘만의 새 프로젝트를 일부러 만들어 두세요.',
  ]),
];
final List<_BeatPool> _romanceBeatsFemale = [
  _romanceOpeningFemale,
  _romanceVignette,
  _romanceStrengthFemale,
  _romanceShadowFemale,
  _romanceAdviceFemale,
];
final List<_BeatPool> _romanceBeatsMale = [
  _romanceOpeningMale,
  _romanceVignette,
  _romanceStrengthMale,
  _romanceShadowMale,
  _romanceAdviceMale,
];

// 행동 vignette (연애 공용) — 연애에서 자기 패턴이 드러나는 한 컷.
final List<_Frag> _romanceVignette = [
  _Frag(_highOf(Attribute.emotionality), [
    '상대의 말투나 표정 작은 변화에 "오늘 뭔가 다르네" 하고 먼저 알아챈 적이 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.attractiveness), [
    '딱히 애쓰지 않았는데 호감을 받아본 적이 있고, 정작 마음 가는 사람 앞에선 더 서툴렀던 적도 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '불같이 타오르는 연애보다, 같이 있어도 안 피곤한 사람이 결국 오래 가더라고 느낀 적이 있을 겁니다.',
  ]),
  _Frag.hard((f) => true, [
    '마음에 드는 사람일수록 티 내기보다 한 발 물러서서 관찰부터 한 적이 있을 겁니다.',
    '표현은 서툴러도 챙기는 걸로 마음을 보여주는 편이라, "무뚝뚝한데 은근 챙긴다"는 말을 @{heard}.',
    '헤어지고 나서야 그 사람이 어떤 사람이었는지 또렷해진 적이 있을 겁니다.',
  ]),
];

// ─── 4-F. 연애운 (여) ─────────────────────────────────────────────────

final List<_Frag> _romanceOpeningFemale = [
  // 9-cell matrix: attractiveness(primary) × emotionality(secondary)
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.high), [
    '여러 방향에서 호감이 들어오는 편인데, 동시에 상대의 속마음까지 깊이 읽어내는 쪽입니다. 고를 폭이 넓은 만큼 "이 사람이 맞나"를 확인하는 단계가 길어지기 쉽습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '호감은 먼저 들어오는데, 상대를 무리하게 미화하진 않는 편입니다. 첫 두세 달 안에 "이 사람과 갈지" 빠르게 판단하는 현실 감각이 같이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '들어오는 호감을 담담히 골라내는 편입니다. 분위기는 끌어당기되 속은 건조한 쪽이라, 관계의 방향과 조건을 먼저 정리하는 모습이 오히려 매력으로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '우정에서 연인으로 자연스럽게 넘어가는 쪽입니다. 첫인상의 스파크보다 여러 번 겹친 대화 속에서 상대가 당신을 "발견"하게 되고, 속마음을 읽는 감수성이 관계를 끌고 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '중용의 리듬을 따라가는 편입니다. 화력도 집요함도 한쪽으로 안 쏠려서, 상대 속도에 맞춰 두세 번 만난 뒤 자연스럽게 관계의 이름이 정해집니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '조건과 결을 먼저 맞추는 실리형입니다. 화려한 구애를 기대하기보다 서로의 삶이 어떻게 겹치는지를 냉정히 저울질하고, 현실이 맞는 상대와의 합이 유난히 깊습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '늦게 빛나는 깊이형입니다. 첫눈에 확 끌어당기진 않아도, 한 번 대화한 상대가 며칠 뒤 당신을 다시 떠올리는 여운형이라, 감수성의 밀도가 평균을 크게 넘습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '같은 자리에서 만나는 생활 기반형입니다. 길에서의 우연보다 같은 일·같은 모임에서 오래 겹친 상대와 자연스럽게 이어지고, 시작은 조용해도 오래 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '동지 결합형에 가깝습니다. 뜨거운 구애보다 같은 가치·같은 방향을 확인한 상대와 조용히 나란히 걷는 쪽이고, 결혼이라는 결론까지 직진하는 성향이 평균보다 강합니다.',
  ]),
  _Frag.hard((f) => true, [
    '시작은 느린데 일단 시작하면 깊이 들어가는 편입니다. 첫 만남에 불붙기보다 같은 자리에 두세 번 마주친 뒤 불씨가 번지는 쪽이라, 결혼까지 가는 관계에서 진가가 납니다.',
  ]),
];
// ═══ 4. 연애운 — 남/여 분리 pool ═══
//
// 관상학에서 남녀 연애 해석이 가장 크게 갈리는 지점: 주도권 / 매력 출처 /
// 타이밍 / 리스크 / 전통 용어. 각 성별 pool 은 opening·strength·shadow·
// advice 4 beat 구조로 공통 인터페이스 유지.

// ─── 4-M. 연애운 (남) ─────────────────────────────────────────────────

final List<_Frag> _romanceOpeningMale = [
  // 9-cell matrix: attractiveness(primary) × emotionality(secondary)
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.high), [
    '먼저 다가서면서도 상대 속마음까지 읽는, 흔치 않은 쪽입니다. 끌어당기는 힘과 해석하는 눈이 같이 있어서, 주도하되 상대를 세심하게 살피는 두 결이 동시에 움직입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '먼저 다가서는 쪽입니다. 마음이 서면 머뭇거리지 않고 다음 단계를 여는 편이라, 상대보다 반 박자 빠른 리듬이 연애의 색을 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '파장은 강한데 속은 담담한 편입니다. 첫 자리에서 분위기를 잡는 기세는 또렷하되 감정을 오래 머금진 않아서, 관계의 조건과 방향을 먼저 정리하는 모습이 매력으로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '말과 해석으로 들어가는 쪽입니다. 외형보다 대화에서 상대의 결을 짚어내는 힘이 매력의 중심이고, 느리게 시작해 여러 장면을 겹쳐 관계를 끌고 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '중용의 다가섬입니다. 기세도 감정도 한쪽으로 안 쏠려서, 끌리는 사람이 있으면 시선을 피하지 않고 먼저 말을 건네되 상대 속도에 맞춰 관계를 정해갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '조건을 먼저 맞추는 실리형입니다. 화려한 구애보다 서로의 생활이 어떻게 맞물리는지를 냉정히 보고, 한 번 맞는다 싶으면 결혼까지 직선으로 달려가는 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '늦게 깊어지는 후발형입니다. 즉시 끌어당기는 힘은 약해도, 한 번 대화한 상대가 며칠 뒤 당신을 다시 떠올리는 여운형이라, 속마음을 읽는 감수성이 평균을 크게 넘습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '생활 기반형입니다. 길에서의 우연보다 같은 일·같은 모임에서 오래 겹친 상대와 자연스럽게 이어지고, 시작은 조용해도 한 번 시작되면 오래 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '자기 세계 주도형에 가깝습니다. 화려한 구애나 감정 곡예 없이, 자기 일·목표·루틴이 단단한 상대에게 조용히 끌리고, 결혼 상대 기준이 일찍 정해지는 편입니다.',
  ]),
  _Frag.hard((f) => true, [
    '먼저 다가서는 게 기본인 편입니다. 끌리는 사람이 있으면 시선을 피하지 않고 먼저 말을 거는 쪽이라, 관계의 출발점을 만드는 게 대개 당신이고 이 주도성이 연애의 색을 정합니다.',
  ]),
];
final List<_Frag> _romanceShadowFemale = [
  // libido-driven 바람기 1-line (libido high & stability not high — 정서 누수형)
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '한눈팔기는 몸보다 마음이 먼저인 편입니다. 지금 관계에서 안 채워지는 공감을 다른 사람에게서 구하는 심리 외도 쪽이 먼저 열리니, 대화가 유독 잘 통하는 상대가 나타나는 시기를 조심해야 합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) == _Band.high, [
    '한눈팔 기질은 강한 자기 통제 안에 눌려 있습니다. 평소엔 선을 지키되 한 번 넘으면 돌아오기 어려운 "한 번의 큰 이탈"형이라, 관계 만족도가 길게 떨어지는 신호를 방치하지 않는 게 안전합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '또 "설렘의 유통기한" 문제가 따릅니다. 시작의 화력이 강한 만큼 권태가 먼저 오기 쉽고, 그 공백을 덮으려 다음 상대를 미리 떠올리면 좋은 인연을 놓치는 패턴이 쌓입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.trustworthiness) != _Band.high, [
    '또 혼자 앞서 나가기 쉽습니다. 상대 신호를 깊게 읽다 보니 신호 아닌 것까지 신호로 읽어, 상대가 아직 정리 못 한 감정을 당신이 먼저 미래로 번역해 속도 차이를 만들기 쉽습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) == _Band.low, [
    '또 만날 자리 자체가 좁은 게 한계입니다. 신중하게 검증하는 건 강점인데, 새 사람과 접점을 잘 안 만드는 편이라 좋은 인연이 지나가는 걸 모르고 보낼 수 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '결정을 미루는 그림자가 있습니다. 상대 마음을 알아챘으면서도 조금만 더 확인하려다 더 적극적인 경쟁자에게 자리를 내주기 쉬운데, 완벽한 확신은 결혼 뒤에도 안 옵니다.',
  ]),
];
final List<_Frag> _romanceShadowMale = [
  // libido-driven 바람기 1-line (libido high & stability not high — 상황 의존형)
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '한눈팔기는 상황에 끌려가는 편입니다. 먼저 적극적으로 찾아 나서기보다 출장·회식·먼 주말처럼 선이 흐려지는 환경이 열릴 때 경계가 무너지는 쪽이라, 잦은 출장과 음주 빈도가 가장 큰 리스크입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) == _Band.high, [
    '한눈팔 기질은 의지로 눌러온 편입니다. 평소엔 선을 지키되 한 번 넘으면 가정 전체를 흔드는 "대형 이탈"형이라, 관계 만족도가 길게 떨어지는 신호를 방치하면 안 됩니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '또 "설렘의 유통기한" 문제가 되풀이됩니다. 시작의 화력이 강한 만큼 일상으로 넘어가는 6개월~1년 사이 권태가 먼저 오고, 그 공백을 새 자극으로 메우려다 좋은 사람을 놓치기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '또 주도성이 강한 만큼 "내가 정한 속도"를 상대에게 밀어붙이기 쉽습니다. 상대가 못 따라오면 관심이 식는 속도도 빠른 편이라, 기다리는 인내가 연애 수명의 핵심입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) != _Band.high, [
    '또 만날 자리 자체가 좁은 게 한계입니다. 신중하게 검증하는 건 강점인데, 새 사람과 접점을 잘 안 만드는 편이라 좋은 인연이 지나가는 걸 모르고 보낼 수 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '한 사람에 집중되면 주변이 흐려지는 기질이 있어서, 제일 뜨거운 시기일수록 일·친구·건강 같은 생활의 축을 의식적으로 안 지키면 중요한 자리를 같이 놓치기 쉽습니다.',
  ]),
];
final List<_Frag> _romanceStrengthFemale = [
  _Frag.hard((f) => f.fired('P-08'), [
    '눈 밑이 맑게 살아 있는 편이라, 매력이 강해지는 시기가 규칙적으로 돌아옵니다. 한 해에 한두 번 의미 있는 인연의 문이 열리는 주기가 있습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '옆에서 보면 입술선이 도톰한 편이라, 상대 시선이 입매에 오래 머무는 은근한 매력이 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '말과 행동이 일치하는 편이라, "한 번 정하면 끝까지 간다"는 신뢰를 상대에게 각인시키고 장기 관계의 뿌리를 깊이 내립니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '상대 속마음을 잘 읽어서 갈등의 싹을 일찍 알아봅니다. 작은 신호에서 관계의 방향을 조정할 줄 아는 게 큰 강점입니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.5, [
    '입매가 단정한 편이라 "말로 관계를 지키는" 힘이 있습니다. 잘 고른 말 한마디가 상대 마음을 오래 묶어둡니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eye') >= 0.5, [
    '눈빛에 윤기가 있어서 상대를 "담아두는" 시선의 힘이 있습니다. 짧은 순간에도 "나를 알아봐 줬다"는 기억을 오래 남깁니다.',
  ]),
  _Frag.hard((f) => true, [
    '관계의 "양"보다 "질"이 우선인 편이라, 맞는 사람 한 명을 만났을 때의 밀도가 평균을 크게 넘습니다.',
  ]),
];

final List<_Frag> _romanceStrengthMale = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 또렷한 편이라 자기 의사를 흐리지 않습니다. 애매한 썸에 오래 안 머물고 관계의 성격을 일찍 정리해서, 상대가 끌려다닌다는 느낌 없이 당신 속도를 따라오게 만듭니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대가 받쳐주는 편이라 기백이 있습니다. 당신이 들어서는 순간 자리의 중심이 옮겨 가는 게, 연애의 출발점에서 또렷이 작동합니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '옆에서 보면 코의 윤곽이 단단해서, 상대가 당신의 결정에 기대고 싶어지는 중심축이 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '말과 행동이 일치하는 편이라, 연애에서도 "해주겠다 한 건 반드시 해내는" 식이라 시간이 갈수록 상대 신뢰가 두텁게 쌓입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.wealth) == _Band.high || f.nodeZ('nose') >= 0.8, [
    '생활의 기반을 먼저 갖추는 편이라, 막연한 약속 대신 구체적인 안정감을 보여주는 게 매력으로 작동합니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('chin') >= 0.5, [
    '턱이 단정한 편이라 "한 번 정하면 끝까지 간다"는 인상이 있습니다. 흔들리지 않는 뿌리가 장기 관계의 가장 큰 축이 됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '순간의 분위기보다 쌓인 기백에서 힘을 얻는 편이라, 한 번에 타오르기보다 여러 장면을 겹쳐 자기를 각인시키는 장기전에 유리합니다.',
  ]),
];

final List<_Frag> _sensualAdviceFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '풍부한 결이니 삶의 주축 중 하나로 당당히 다뤄라. 미혼이라면—서두르지 말고 자기 리듬, 취향, 속도를 먼저 정확히 파악한 뒤 결이 맞는 상대를 고르는 게 장기 만족을 결정한다. 파트너가 있다면—같은 사람과의 관계에서 매번 새로운 각도를 만드는 "창의적 재사용" 이 최고 농도를 만드는 방향이다. 새 사람이 답이 아니라 새 장면이 답이다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.sensuality) != _Band.high,
    [
      ' 타고난 욕망의 온도가 높은 편이다. 굳이 숨기려 애쓸 필요는 없다. 다만, 그 에너지를 어떻게 ‘표현하느냐’가 매력의 급을 가른다. 미혼이라면—자기 결이 어떤 조건에서 가장 선명하게 켜지는지 관찰하는 게 곧 전략이다. 파트너가 있다면—상대에게 먼저 원하는 것을 꺼내는 노력이 매력의 급을 가른다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '관능의 뿌리가 "감각의 해상도" 쪽에 있는 결이다. 미혼이라면—새벽 2시까지 대화가 가능한 상대를 찾는 과정 자체가 관능의 설계다. 파트너가 있다면—미세한 변화 한 가지씩(향, 음악, 시간대) 을 매달 하나씩 넣어 주는 작은 실험이 결을 두텁게 만든다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '건강한 중용의 결이다. 드라마 없이도 오래 간다—꾸준함이 장점이다. 미혼이라면—속도의 결이 맞는 상대를 알아보는 눈을 길러라. 파트너가 있다면—조명, 음악, 시간대를 정기적으로 살짝 바꾸는 것만으로 결이 신선하게 유지된다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '규칙적이고 담담한 결이다. 미혼이라면—몸의 신호가 유독 잘 올라오는 조건(계절, 환경 변화, 새 경험) 을 기록해 두면 자기 패턴이 보인다. 파트너가 있다면—요리, 음악, 향 같은 감각 공부를 따로 두는 것만으로 관능의 결이 저절로 쌓이는 타입이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '몸보다 마음, 감각이 먼저 움직이는 결이다. 미혼이라면—정서적, 지적 교감이 깊은 상대와의 시간이 관능의 진짜 출발점이다. 파트너가 있다면—상상했던 장면을 월에 한 번 실제로 옮겨 보는 작은 실행이 밀도를 확실히 키워 준다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '조건이 겹쳐야 발화하는 결이다. 미혼이라면—긴 호흡의 상대를 찾는 게 곧 전략이다. 짧은 시간 안에 평가되는 관계에서는 이 결이 절대 드러나지 않는다. 파트너가 있다면—몸이 깨어나는 조건(신뢰, 공간, 반복) 을 파트너와 언어로 공유해 둬라.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) != _Band.low,
    [
      '관능이 감정의 온도에 따라 결정되는 결이다. 미혼이라면—"몸의 반응이 느리다" 가 결함이 아니라 순서가 다른 거라고 받아들여라. 파트너가 있다면—정서적 결합이 깊어질수록 몸의 결도 같이 깊어지는 타입이라, 관계의 연륜 자체가 최대 자산이다.',
    ],
  ),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '관능이 전반적으로 엷게 정돈된 결이고, 이건 결함이 아니라 타고난 방향이다. 미혼이라면—몸의 밀도 중심 관계 말고 동지적, 동료적 결합의 가능성도 진지하게 고려할 수 있다. 파트너가 있다면—서로의 페이스를 존중하는 게 관계의 수명을 결정한다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '관능은 삶의 부수 요소가 아니라 행복의 주요 축 중 하나다. 미혼이든 파트너가 있든, 자기 몸의 리듬을 솔직하게 들여다보고 건강히 즐기는 태도가 평생 결을 받쳐 준다. 숨기거나 억누르는 관성 대신 표현과 대화의 언어를 길러라.',
    '이 결을 가꾸는 핵심은 셋이다. 첫째, 자기 몸의 리듬을 정기적으로 관찰하고 기록할 것. 둘째, 미혼이라면 "결이 맞는 상대" 의 조건을 먼저 정의하고, 파트너가 있다면 작은 실험을 꾸준히 도입할 것. 셋째, 침실 문화를 숨길 것이 아니라 "가꿀 것" 으로 대하는 태도—이게 전체 결을 결정한다.',
  ]),
  // age-stratified Advice (♀) — 30+ gated, 30~40대 vs 50대 이후 관능 변곡점.
  _Frag.hard(_isMid, [
    '30~40대 여성의 관능은 20대보다 한층 농밀해진다. 직접적인 신호보다 분위기·태도·여운이 더 강한 매력이 된다. 자기 속도를 알고 있는 사람만이 그 깊이를 자기 자산으로 만든다.',
    '30~40대 여성은 어머니·아내·직장인이라는 사회적 역할에 묻혀 자기 몸의 리듬을 잊기 쉽다. 자기 시간을 잠깐이라도 떼어 두고 자기 몸의 신호를 살피는 일이 관능의 출발점이다. 이 시기에 그걸 못하면 후반에 가서 무뎌진다.',
    '30~40대 여성의 관능은 일과 가정 사이에서 가장 먼저 뒷순위로 밀린다. 일주일에 한 번이라도 자기만의 감각 시간(향·음악·산책·책)을 의식적으로 만들어 두는 사람이 40대 후반에 더 풍성하다. "바쁘다"는 핑계가 가장 큰 함정이다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후 여성의 매력은 외모보다 자기만의 결정·경험·내공이 만든 깊이에서 나온다. "처음 매력적인" 사람보다 "여전히 매력적인" 사람의 무게가 더 깊다. 외모가 아니라 살아온 흔적이 관능이 되는 시기다.',
    '50대 이후 여성의 관능은 "혼자의 시간"의 질이 좌우한다. 자기만의 세계(책·산책·취미·친구)를 가꾼 사람일수록 동반자와의 관계도 풍성해진다. 혼자 즐길 줄 알아야 같이도 즐겁다.',
    '나이가 들수록 관능은 새 사람보다 오랜 동반자와의 깊이로 표현된다. 함께 늙어가는 사람과의 둘만의 시간을 일부러 디자인하는 사람이 노년이 풍성하다. 매년 새로운 작은 의례 하나가 그 깊이를 만든다.',
  ]),
];

final List<_Frag> _sensualAdviceMale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '풍부한 결이니 삶의 중심축 중 하나로 당당히 다뤄라. 미혼이라면—서두르지 말고 자기 리듬, 취향, 속도를 먼저 정확히 파악한 뒤 결이 맞는 상대를 고르는 게 장기 만족을 결정한다. 파트너가 있다면—같은 사람과의 관계에서 매번 새로운 각도를 만드는 "창의적 재사용" 이 최고 농도를 만드는 방향이다. 새 사람이 아니라 새 장면이 답이다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.sensuality) != _Band.high,
    [
      '욕구가 크고 솔직한 결이다. 감추지 마라—단, 표현 언어는 다듬어라. 미혼이라면—자기 탐색과 몸의 리듬 기록이 관능의 품격을 올린다. 파트너가 있다면—원하는 걸 상대에게 먼저 언어로 꺼내는 용기가 핵심이다. 해석하는 부담을 상대 어깨에 올려 두지 마라.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '관능의 뿌리가 "감각의 해상도" 쪽에 있는 결이다. 미혼이라면—새벽 2시까지 대화가 가능한 상대를 찾는 과정 자체가 관능의 설계다. 파트너가 있다면—미세한 변화 한 가지씩(향수 바꾸기, 플레이리스트 바꾸기, 시간대 바꾸기) 을 매달 하나씩 넣어 주는 작은 실험이 결을 두텁게 만든다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '건강한 중용의 결이다. 드라마 없이도 오래 간다—꾸준함이 장점이다. 미혼이라면—속도의 결이 맞는 상대를 알아보는 눈을 길러라. 파트너가 있다면—조명, 음악, 시간대를 정기적으로 살짝살짝 바꾸는 것만으로 결이 신선하게 유지된다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '규칙적이고 담담한 결이다. 미혼이라면—몸의 신호가 유독 잘 올라오는 조건(계절, 환경 변화, 새 경험) 을 기록해 두면 자기 패턴이 보인다. 파트너가 있다면—요리, 음악, 향 같은 감각 공부를 따로 두는 것만으로 관능의 결이 저절로 쌓이는 타입이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '몸보다 마음, 감각이 먼저 움직이는 결이다. 미혼이라면—정서적, 지적 교감이 깊은 상대와의 시간이 관능의 진짜 출발점이다. 흔한 데이팅 앱 회전이 결에 안 맞는 타입. 파트너가 있다면—상상했던 장면을 월에 한 번 실제로 옮겨 보는 작은 실행이 밀도를 확실히 키워 준다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '조건이 겹쳐야 발화하는 결이다. 미혼이라면—긴 호흡의 상대를 찾는 게 곧 전략이다. 짧은 시간 안에 평가되는 관계에서는 이 결이 절대 안 드러난다. 파트너가 있다면—몸이 깨어나는 조건(신뢰, 공간, 반복) 을 파트너와 언어로 공유해 둬라.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) != _Band.low,
    [
      '관능이 감정의 온도에 따라 결정되는 결이다. 미혼이라면—"몸의 반응이 느리다" 가 결함이 아니라 그냥 순서가 다른 거라고 받아들여라. 파트너가 있다면—정서적 결합이 깊어질수록 몸의 결도 같이 깊어지는 타입이라, 관계의 연륜 자체가 최대 자산이다.',
    ],
  ),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '관능이 전반적으로 엷게 정돈된 결이고, 이건 결함이 아니라 타고난 방향이다. 미혼이라면—몸의 밀도 중심 관계 말고 동지적, 동료적 결합의 가능성도 진지하게 고려할 수 있다. 파트너가 있다면—서로의 페이스를 존중하는 게 관계의 수명을 결정한다.',
    ],
  ),
  _Frag.hard((f) => true, [
    '관능은 삶의 부수 요소가 아니라 행복의 주요 축 중 하나다. 미혼이든 파트너가 있든, 자기 몸의 리듬을 솔직하게 들여다보고 건강히 즐기는 태도가 평생 결을 받쳐 준다. 숨기거나 억누르는 관성 대신 표현과 대화의 언어를 길러라.',
    '이 결을 가꾸는 핵심은 셋이다. 첫째, 자기 몸의 리듬을 정기적으로 관찰하고 기록할 것. 둘째, 미혼이라면 "결이 맞는 상대" 의 조건을 먼저 정의하고, 파트너가 있다면 작은 실험을 꾸준히 도입할 것. 셋째, 침실 문화를 숨길 것이 아니라 "가꿀 것" 으로 대하는 태도—이게 전체 결을 결정한다.',
  ]),
  // age-stratified Advice (♂) — 30+ gated, 30~40대 vs 50대 이후 관능 변곡점.
  _Frag.hard(_isMid, [
    '30~40대 남성의 관능은 외모보다 안정성·신뢰·일관성에서 나온다. 외부 인기보다 동반자가 인정하는 매력이 평생 관계의 농도를 절반쯤 결정한다. 책임을 받아들이는 모습 자체가 매력이 되는 시기다.',
    '30~40대 남성의 관능은 일과 가정의 압박에 가장 먼저 무뎌진다. 직업적 성취에 매달리느라 동반자와의 시간을 미루기 쉽다. 주 1회 둘만의 시간을 의식적으로 잡아두는 사람이 40대 후반에도 관계가 살아 있다.',
    '30~40대 관능의 핵심은 같은 사람과 새로운 장면을 만들어내는 일이다. 새 사람을 찾기보다 익숙한 상대와의 침실·여행·공동 프로젝트에 변주를 주는 사람이 더 깊이 간다. 익숙함을 권태로 두지 마라.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후 남성의 관능은 외모보다 살아온 흔적에서 나온다. 얼굴이 곧 인생의 기록으로 읽히는 시기다. 자기를 잘 다듬어 온 사람의 묵직함이 가장 큰 관능 자산이다.',
    '50대 이후 남성의 관능은 은퇴 뒤의 새 역할에서 크게 달라진다. 직업적 정체성이 사라진 자리를 동반자와의 새 친밀함으로 채우지 못하면 관계가 빠르게 무뎌진다. 둘만의 정기적 의례를 의식적으로 만드는 일이 핵심이다.',
    '나이가 들수록 관능은 강도보다 느린 동행에 있다. 함께 마시는 커피, 같이 보는 풍경, 매년 가는 여행지 — 사소한 일상의 친밀함이 노년 관능의 진짜 자산이다.',
  ]),
];

final List<_BeatPool> _sensualBeatsFemale = [
  _sensualOpeningFemale,
  _sensualVignette,
  _sensualStrengthFemale,
  _sensualShadowFemale,
  _sensualAdviceFemale,
];

final List<_BeatPool> _sensualBeatsMale = [
  _sensualOpeningMale,
  _sensualVignette,
  _sensualStrengthMale,
  _sensualShadowMale,
  _sensualAdviceMale,
];

// 행동 vignette (관능 공용) — 감각·욕구가 일상에서 드러나는 한 컷.
final List<_Frag> _sensualVignette = [
  _Frag(_highOf(Attribute.sensuality), [
    '남들은 그냥 지나치는 분위기·향·음악 같은 걸 유독 또렷이 기억하는 편이라, "감각이 예민하다"는 말을 @{heard}.',
  ]),
  _Frag(_highOf(Attribute.libido), [
    '겉으론 차분해 보여도 속은 꼭 그렇지만은 않다는 걸, 가까운 사람만 아는 경우가 있을 겁니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.low && f.bandOf(Attribute.emotionality) == _Band.high, [
    '몸보다 마음이 먼저 열리는 편이라, 충분히 가까워지기 전엔 잘 안 켜진다고 느낀 적이 있을 겁니다.',
  ]),
  _Frag.hard((f) => true, [
    '조명이나 음악 하나로 그날의 온도가 확 달라진 경험이 있을 겁니다.',
    '끌리는 데는 외모보다 결이나 말투가 먼저였던 적이 있을 겁니다.',
  ]),
];

// ─── 6-F. 관능도 (여) ─ band 9-cell × 부위 단서 × 건강한 향유 ─────────────────

final List<_Frag> _sensualOpeningFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '누군가의 시선이 스치는 순간, 공기가 반 박자 먼저 데워진다. 곁에 사람이 있다는 그 미묘한 긴장—그게 곧 불씨다. 관상학은 이걸 진한 매력형이라 부른다. 욕망의 선이 선명한데, 상대의 숨과 체온의 미세한 떨림까지 집어내는 안테나가 같이 켜진 결. 드문 조합이다.',
    '욕구도 감각도 동시에 상위. 한 사람과 시간이 쌓일수록 오히려 몸의 기억이 켜켜이 접히는 구조다. 10년 된 관계의 어느 밤이 첫 밤보다 선명해지는—그런 타입이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.mid), [
    '욕구의 선이 굵다. 해석을 거치지 않는 직선의 리듬. 세밀한 감각은 아직 평균권이지만, 이건 시간이 얹어 주는 축이다. 서른, 마흔을 지나며 농도가 오히려 풍부해지는 성장형 결이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '욕구는 또렷한데, 상대의 작은 흔들림을 잡는 센서가 아직 튜닝 중이다. 한 박자 느려진 대답, 눈동자의 떨림—혼자 해석하려 애쓰지 말고 입으로 먼저 물어라. 그 순간 이 축도 같이 켜진다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high), [
    '욕구의 폭은 격렬하지 않은데 감각의 해상도는 유난히 높다. 손끝이 한 번 스치는 그 한 뼘의 압력이 몸속에서 사방으로 번지는 구조다. 겉은 잔잔하고 속은 파문—관계의 깊이 자체가 관능의 축으로 작동하는 타입이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid), [
    '격렬하지도 무디지도 않다. 계절과 감정을 따라 부드럽게 오르내리는 리듬. 봄의 나른한 오후와 겨울의 조용한 저녁—서로 다른 온도가 같은 몸을 지나간다.',
    '평균권에 단정히 자리한 결이다. 눈에 띄는 화려함은 없다. 대신 시간이 쌓일수록 은은히 깊어지는 구조—수명 긴 관계의 뿌리가 여기서 시작된다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '평소엔 평범한 궤도다. 그런데 특정 계기—낯선 호텔 방의 창밖 불빛, 잠들기 직전 예상 못 한 한마디—가 겹치면 잠자던 밀도가 한 번에 깨어난다. 조건부 발화형. 장치 하나가 방 전체를 바꾸는 결이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '몸보다 마음, 상상, 미적 감각이 먼저 움직이는 타입이다. 관능을 체험하기보다 한 걸음 떨어져 바라보며 음미하는 쪽—사진 한 장, 영화 한 컷이 실제보다 더 깊이 남는 예술가적 결이다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid), [
    '평소엔 이 축이 잠들어 있다. 깊은 신뢰, 쌓인 시간, 새벽의 공기, 잠들기 직전의 느린 대화—조건이 겹쳐야 비로소 또렷이 열리는 결이다. 서둘러 평가받는 관계에서는 아예 보이지 않는 구조이기도 하다.',
  ]),
  _Frag(_lowPair(Attribute.libido, Attribute.sensuality), [
    '성적 에너지가 무대 한가운데가 아니라 조명 바깥쪽에 앉아 있는 결이다. 결핍이 아니라 방향이다. 정갈함, 절제, 독립이 앞선다—혼자만의 공간과 시간이 관계보다 먼저인 타입.',
  ]),
  _Frag.hard((f) => true, [
    '어느 쪽으로도 쏠리지 않은 평이한 결. 상황과 상대에 맞춰 유연히 움직이는 구조—극단 없이 삶에 자연스럽게 녹아 있는 타입이다.',
  ]),
];

// ═══ 6. 관능도 — 남/여 분리 pool ═══
//
// (구 '색기' 섹션명을 attribute.dart::labelKo 와 일치시켜 '관능도' 로 변경.)
// 오랜 관계에서 몸에 새겨지는 농밀한 결, 음주·파티로 인한 기운 누수 경고,
// 만족의 선이 그어질 때까지 지속되는 욕구 — 관상학 전통의 엄중한 진단 + 실질 조언.

// ─── 6-M. 관능도 (남) ─ band 9-cell × 부위 단서 × 건강한 향유 ─────────────────
//
// 4 beat 구조:
//   opening — libido × sensuality 9-cell 핵심 선언 (~80~130 자)
//   strength — 얼굴 단서, 왜 그렇게 나왔는가 (~100~150 자)
//   shadow — 자기 관찰 포인트, 타부 프레임 없음 (~80~120 자)
//   advice — 미혼/파트너 분기, 침실 긍정 (~120~170 자)

final List<_Frag> _sensualOpeningMale = [
  _Frag(
    _highPair(Attribute.libido, Attribute.sensuality),
    [
      '어떤 남자는 방에 들어서는 순간부터 공기가 바뀐다. 말을 많이 하지 않아도 체온이 먼저 닿는 타입이 있다. 관상학은 이걸 "진한 매력형" 이라 부른다. 쉽게 말하면 이런 거다. 욕구의 선이 굵은데, 상대의 숨결과 떨림을 읽는 센서까지 같이 켜져 있는 구조.',
      '욕구도, 감각도 동시에 상위다. 드문 조합이다. 처음 마주 앉은 술자리에서도 상대 손끝의 긴장이 그대로 읽히는 타입. 같은 사람과 오래 만날수록 오히려 밀도가 짙어지는 결이다—첫 밤보다 100번째 밤이 더 깊어지는 구조.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.mid),
    [
      '욕구의 선이 굵다. 복잡한 전희와 긴 해석 대신, 몸이 먼저 움직이는 쪽이다. 세밀한 감각 해상도는 평균이라 돌려 말하는 신호보다 직구가 통하는 타입. 단순하지만 솔직한 결이고, 그게 오히려 상대를 안심시키는 구조다.',
      '드라이브 중에 갑자기 차를 세워도 이상하지 않은 타입이 있다. 충동이 정직하게 그 순간 올라오는 결. 감각은 섬세하지 않아도 에너지가 흐리지 않아서, 원하는 걸 숨기느라 피곤해지는 일이 없다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low),
    [
      '엔진은 큰데 계기판은 아직 설치 중인 차 같은 구조다. 욕구는 확실한데, 상대가 보내는 미세 신호—숨 멈추는 타이밍, 옷깃 잡는 손의 힘 같은 것—를 놓치기 쉽다. 말로 직접 확인하는 습관을 들이면 계기판이 같이 켜진다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.high),
    [
      '욕구는 평균인데 감각의 해상도가 유난히 높다. 상대가 한 박자 느리게 내쉬는 숨 하나에 머릿속이 꽉 차는 타입. 격렬함이 아니라 관찰의 깊이로 승부하는 결—와인잔에 맺힌 물기 하나에도 서사를 붙일 줄 아는 결이다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.mid),
    [
      '기복이 크지 않다. 극단적인 날도 없고 메마른 날도 없다. 계절이 바뀌듯 체온이 오르내리는 구조. 눈에 띄는 화려함은 없어도, 5년 10년 같이 산 뒤에 진가가 나오는 결이다.',
      '평균권의 단단한 결이다. 드라마 없이 오래 가는 타입. 금요일 밤보다 일요일 오후의 나른한 낮잠 같은 분위기—거기서부터 천천히 번지는 구조다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low),
    [
      '욕구도 감각도 요란하지 않다. 규칙적인 리듬에서 편안함을 느끼는 타입. 화요일 밤 10시쯤 비슷한 시간대에 불이 들어오는 창문 같은 결이다. 조명 하나만 바꿔도 결이 넓어지는 구조라, 작은 장치 하나가 의외로 크게 작동한다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high),
    [
      '몸보다 머릿속이 먼저 뜨거워지는 타입이 있다. 한 편의 영화, 한 장의 사진, 한 줄의 문장에서 먼저 열리는 구조. 관상학은 이걸 "마음으로 먼저 느끼는 형" 이라 부른다. 몸이 느려도 상상의 해상도는 남들 두 배다.',
    ],
  ),
  _Frag(
    _bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.mid),
    [
      '평소엔 그 축이 거의 잠들어 있다. 그런데 신뢰와 시간이 쌓인 특정 조건—새벽 2시, 잠들기 전의 긴 대화 같은 것—이 겹칠 때 비로소 또렷이 열린다. 서둘러 평가받는 관계에서는 결이 안 보이는 구조다.',
    ],
  ),
  _Frag(
    _lowPair(Attribute.libido, Attribute.sensuality),
    [
      '성적 에너지가 삶의 무대 한가운데가 아니라 조명 바깥쪽에 서 있는 결이다. 이건 결핍이 아니라 방향이다. 정갈함과 독립성이 자연스럽게 앞서는 타입—혼자 있는 일요일 오전이 편안한 결.',
    ],
  ),
  _Frag.hard((f) => true, [
    '뚜렷한 극단이 없다. 상황과 상대에 따라 유연하게 움직이는 타입. 큰 기복 없이 삶에 자연스럽게 녹아 있는 결—파도라기보다 호흡에 가까운 리듬이다.',
  ]),
];

final List<_Frag> _sensualShadowFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '결이 풍부한 만큼 에너지가 주기적으로 쌓인다. 방치하면 수면이 얕아지고, 피부에 먼저 표시가 나고, 감정 기복이 커지는 구조다. 일주일에 한 번 "요즘 내 몸이 어떤 상태지" 하고 짧게 적어 두는 가벼운 습관만으로도 장기 밀도가 유지된다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '욕구의 선은 굵은데 상대의 신호를 읽는 해상도가 낮으면, 엇갈리는 밤이 쌓인다. "아까 왜 그랬지" 하고 혼자 해석하느라 피곤해지는 구조—해석 대신 "지금 뭐 원해?" 라고 직접 묻는 짧은 대화 하나가 관계의 온도차를 줄이는 가장 빠른 길이다.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '욕구는 강한데 안정성이 낮은 결은 에너지가 여러 방향으로 흩어지기 쉽다. 늦은 밤 감정적인 결정, 충동적 약속 같은 것들로 새 나가는 구조. 수면, 식사, 운동—이 기본 세 축만 먼저 잡아 줘도 오히려 결이 더 깊어진다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '외부의 시선이 들어오는 순간, 분위기가 확 달아오르는 타입이 있다. 누가 보고 있다는 그 묘한 긴장감, 그게 바로 감정의 불씨가 되는 구조다. 관상학은 이걸 꽤 직설적으로 부른다. "시선 의존 매력형." 쉽게 말하면 이런 거다. 무대 위에서는 누구보다 뜨겁고 매혹적인데, 조명이 꺼지고 관객이 빠지면 온도가 같이 내려가는 타입. 혼자 있는 시간에 조용히 켜지는 자기만의 리듬을 따로 만들어 두면, 관객이 없어도 뜨거울 수 있는 결로 넘어간다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '욕구는 강한데 안정성이 매우 높은 결은 에너지가 지나치게 눌려 있는 경우가 많다. 겉으로는 단단한데 안에서는 압력이 올라가는 구조—운동, 취미, 파트너와의 솔직한 대화 중 하나라도 출구로 두면 그 압력이 수면과 피부, 감정으로 옮겨가지 않는다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '머릿속의 그림은 선명한데, 몸이 그걸 따라가지 않는 결이다. 상상과 실행의 간격이 평생 따라붙는 타입—이 간격을 억지로 없앨 필요는 없다. 한 달에 한 번 정도, 상상했던 조건 하나를 실제 공간으로 옮겨 보는 것만으로 결이 끊기지 않는다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '관능 전반이 엷은 결은 관계가 어느 순간 "생활의 편의" 쪽으로만 수렴되기 쉽다. 같이 밥 먹고, 청소하고, 일정 공유하고—이것만 남는 구조. 몸의 자극이 아니라 같이 발견한 취향, 같이 웃은 장면으로 결을 깨우는 연습이 관계의 안정감을 더한다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '중간과 엷은 결이 섞이면 관계 리듬이 어느새 의례화된다. 금요일은 원래 이런 식, 일요일은 원래 이런 식—자동 재생되는 구조. 조명 하나, 시간대 하나, 공간 하나만 주기적으로 바꿔도 결이 다시 살아난다.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '감정의 진폭이 관능의 방향을 크게 흔드는 결이다. 마음이 허전한 밤에 그게 엉뚱한 곳으로 흐르기 쉬운 구조—그래서 파트너 (또는 혼자라면 자기 자신) 와 감정을 점검하는 대화 루틴이 안전판이 된다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '인중 쪽 결이 유독 두드러졌다. 호르몬 리듬이 얼굴과 관능 표현에 그대로 반영되는 구조—수면, 영양의 기본 축을 지키면 밀도가 저절로 유지된다. 생리 주기와 컨디션의 상관을 기록해 두면 자기 패턴이 보이는 타입이다.',
  ]),
  _Frag(_lowOf(Attribute.libido), [
    '이 축이 엷은 결은 "남들만큼 뜨거워야 한다" 는 기준에서 먼저 자유로워져야 한다. 자기 결을 결함으로 읽지 말고 방향으로 받아들이는 태도가 관계의 자율성을 지키는 핵심이다.',
  ]),
  _Frag.hard((f) => true, [
    '관능의 결은 긴 시간 속에서 소리 없이 얇아진다. 갑자기가 아니라, 한 달이 두 달 되고 반년 되면서 스며들듯 옅어지는 구조다. 계절 바뀔 때마다 한 번씩 자기 몸의 신호를 점검하는 짧은 루틴이 평생 밀도를 받쳐 준다.',
    '관능의 리듬은 업무, 수면, 계절, 생리 주기 같은 외부 요인에 생각보다 크게 흔들린다. 마감 주간에 관심이 뚝 떨어지는 건 결함이 아니라 당연한 반응이다. 자기 상태를 정기적으로 읽고 기록하는 습관이 관계의 온도를 흔들리지 않게 받쳐 준다.',
  ]),
];

final List<_Frag> _sensualShadowMale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '엔진 크기가 큰 만큼 에너지가 주기적으로 쌓인다. 방치하면 수면이 얕아지고 집중이 흐려지는 구조다. 거창한 관리 말고, 일주일에 한 번 "요즘 몸이 어떤 상태더라" 하고 적어 보는 가벼운 습관만으로도 장기 밀도가 유지된다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.high, Attribute.sensuality, _Band.low), [
    '욕구는 굵은데 상대의 신호를 읽는 해상도가 낮으면 자주 엇갈린다. 왜 상대가 갑자기 조용해졌는지 모르는 채 넘어가는 밤이 쌓인다는 뜻. 해석 대신 "뭐 원해?" 짧게 묻는 습관 하나가 관계의 온도차를 줄이는 가장 빠른 길이다.',
  ]),
  _Frag(_and2(_highOf(Attribute.libido), _lowOf(Attribute.stability)), [
    '욕구는 강한데 안정성이 낮은 결은 에너지가 여기저기로 흩어지기 쉽다. 새벽 2시 문자, 충동적인 약속 같은 걸로 새 나가는 구조. 수면, 식사, 운동 이 기본 축 세 개만 잡아 줘도 오히려 관능의 밀도가 깊어진다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.high &&
        f.bandOf(Attribute.attractiveness) == _Band.high &&
        f.bandOf(Attribute.stability) == _Band.low,
    [
      '외부의 시선이 들어오는 순간, 분위기가 확 달아오르는 타입이 있다. 누가 보고 있다는 묘한 긴장감, 그게 감정의 불씨가 되는 구조다. 관상학은 이걸 꽤 직설적으로 부른다. "시선 의존 매력형." 쉽게 말하면 이런 거다. 무대 위에서는 누구보다 뜨거운데, 조명이 꺼지고 관객이 빠지면 온도가 같이 내려가는 타입. 혼자 있을 때 조용히 켜지는 리듬을 따로 만들어 두면, 관객이 없어도 뜨거워질 수 있는 결로 옮겨 간다.',
    ],
  ),
  _Frag(_highPair(Attribute.libido, Attribute.stability), [
    '욕구는 강한데 안정성이 매우 높은 결은 에너지가 과도하게 눌려 있는 경우가 많다. 겉으로는 단단한데 안에서는 압력이 올라가는 구조다. 운동, 취미, 파트너와의 솔직한 대화—이 셋 중 하나라도 출구로 두면 그 압력이 수면이나 감정으로 새지 않는다.',
  ]),
  _Frag(_bandPair(Attribute.libido, _Band.low, Attribute.sensuality, _Band.high), [
    '머릿속에서는 선명한데 몸이 따라가지 않는 결이다. 상상과 실행의 간격이 평생 따라붙는 타입—이 간격을 제로로 만들 필요는 없다. 한 달에 한 번만, 상상했던 조건 중 하나를 실제 공간으로 옮겨 봐도 결이 끊기지 않는다.',
  ]),
  _Frag.hard(
    (f) => f.bandOf(Attribute.libido) == _Band.low &&
        f.bandOf(Attribute.sensuality) == _Band.low &&
        f.bandOf(Attribute.emotionality) == _Band.low,
    [
      '관능이 전반적으로 엷은 결은 관계가 점점 "생활의 편의" 쪽으로만 수렴되기 쉽다. 식사, 청소, 일정—이것만 공유되는 동거 같은 결. 몸의 자극이 아니라 같이 발견한 취향, 같이 웃은 장면으로 결을 깨우는 연습이 관계의 안정감을 더한다.',
    ],
  ),
  _Frag(_bandPair(Attribute.libido, _Band.mid, Attribute.sensuality, _Band.low), [
    '중간과 엷은 결이 섞이면 관계가 슬그머니 의례화된다. 금요일 밤은 원래 이런 식, 일요일 아침은 원래 이런 식—이런 고정 패턴이 자동으로 돌아간다. 조명 하나, 시간대 하나, 장소 하나만 주기적으로 바꿔 줘도 결이 다시 살아난다.',
  ]),
  _Frag(_highPair(Attribute.sensuality, Attribute.emotionality), [
    '감정의 진폭이 관능의 방향을 크게 흔드는 결이다. 마음이 허전한 밤에 그게 엉뚱한 곳으로 흘러가기 쉬운 구조—그래서 파트너 (또는 혼자라면 자기 자신) 와 감정을 점검하는 짧은 대화 루틴이 방파제가 된다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '인중 쪽 결이 유독 두드러진 구조다. 이건 호르몬 리듬이 얼굴과 관능 표현에 그대로 반영된다는 뜻—수면 부족하면 얼굴부터 표시가 나는 타입이다. 잠과 영양, 이 기본만 지켜도 밀도가 알아서 유지된다.',
  ]),
  _Frag.hard((f) => true, [
    '관능의 결은 긴 시간 속에서 소리 없이 얇아진다. 어느 날 갑자기가 아니라, 한 달이 두 달 되고 반년 되면서 스며들듯 옅어지는 구조다. 계절 바뀔 때마다 한 번씩 자기 몸의 신호를 점검하는 짧은 루틴이 평생 밀도를 받쳐 준다.',
    '관능의 리듬은 업무, 수면, 계절 같은 외부 요인에 생각보다 크게 흔들린다. 마감 주간에 관심이 뚝 떨어지는 게 이상한 게 아니라는 뜻이다. 자기 상태를 정기적으로 읽고 기록하는 습관이 관계의 온도를 흔들리지 않게 받쳐 준다.',
  ]),
];

final List<_Frag> _sensualStrengthFemale = [
  _Frag(_metHi('mouthCornerAngle'), [
    '입꼬리가 확 올라가 있다. 기본 표정이 이미 살짝 웃고 있는 상태—침실에서도 웃음이 배경음처럼 깔리는 타입이다. 긴장이 즐거움으로 번역되는 결이라, 상대가 당신 옆에서 숨을 길게 내쉬게 된다.',
    '올라간 입꼬리는 관능이 밝은 에너지와 한 세트로 묶여 있다는 신호다. 공기 자체를 환하게 만드는 결—심각해지려는 순간에 먼저 작게 웃어 버리는 구조다. 그게 이 결의 지속력을 받친다.',
  ]),
  _Frag(_metMid('mouthCornerAngle'), [
    '입꼬리가 수평에 가깝다. 온도가 쉽게 드러나지 않는 타입이라 처음 만났을 때는 차분해 보이는 편. 그런데 진짜 안쪽으로 들어온 상대에게는 기대 이상의 농도가 풀려 나오는 이중 구조다.',
  ]),
  _Frag(_metLo('mouthCornerAngle'), [
    '입꼬리가 살짝 내려간 결이다. 평소 분위기가 진지한 쪽이라 가볍게 풀리는 순간이 흔치 않다. 그래서 오히려 한마디, 한 몸짓의 무게가 커지는 타입—그 무게 자체가 상대의 집중감이 된다.',
  ]),
  _Frag(_metHi('lipFullnessRatio'), [
    '입술이 도톰하다. 마음 이 얼굴에서 먼저 읽히는 결—말보다 표정이 먼저 닿는다. 식복과 언복까지 같이 열려 있어서, 공간 자체를 부드럽게 만드는 강점이 있다. 와인잔 건너로 시선이 오래 머무는 결이다.',
    '도톰한 입술은 감각이 살아 있다는 증거다. 미식, 향, 음악처럼 섬세한 즐거움이 관능과 자연스럽게 한 세트로 섞이는 타입—상대에게 풍요로운 공기를 전하는 구조다.',
  ]),
  _Frag(_metMid('lipFullnessRatio'), [
    '입술 두께가 평균권이다. 감성과 절제가 반씩 섞인 결이라 표현이 한쪽으로 쏠리지 않는다. 상대의 결에 맞춰 모드를 조용히 조율하는 타입—과잉도 결핍도 없다.',
  ]),
  _Frag(_metLo('lipFullnessRatio'), [
    '입술이 얇다. 이성과 절제의 기질이 감정보다 반 박자 앞서는 결이라 표현이 담담한 형태로 나간다. 대신 한 번의 표현이 선명해서 상대에게는 오히려 깊이로 각인되는 구조다.',
  ]),
  _Frag(_metHi('upperVsLowerLipRatio'), [
    '윗입술이 아랫입술보다 두껍다. 주는 쪽에서 충족감을 얻는 결이라, 관능의 방향이 "받기" 보다 "배려하기" 쪽으로 기울어 있다. 공동의 만족에서 자기 만족이 완성되는 타입이다.',
  ]),
  _Frag(_metLo('upperVsLowerLipRatio'), [
    '아랫입술이 더 두껍다. 오감—특히 질감과 온도—에 민감한 타입이라 감각적 향유가 유난히 발달해 있다. 조명, 음악, 향수 하나만 바뀌어도 몸이 반응하는 결이다.',
  ]),
  _Frag(_metHi('philtrumLength'), [
    '인중이 길다. 관상학은 이 결을 "오래가는 형" 이라 부른다. 쉽게 말하면, 짧은 폭발보다 긴 밀도로 승부하는 구조—같이 보낸 시간이 쌓일수록 오히려 몸의 감각이 더 깊어지는 드문 결이다.',
  ]),
  _Frag(_metMid('philtrumLength'), [
    '인중 길이가 평균권이다. 욕구의 리듬이 자연스럽게 오르락내리락하는 안정형—몸의 신호를 따라 유연하게 움직이는 구조다.',
  ]),
  _Frag(_metLo('philtrumLength'), [
    '인중이 짧다. 피크는 뚜렷한데 지속 구간이 짧은 단발형 결—짧은 시간 안에 농도를 압축해서 쓴다. 쌓는 시간과 쏟는 시간을 의식적으로 분리해 두면 이 리듬이 더 길게 이어진다.',
  ]),
  _Frag(_metHi('eyeCanthalTilt'), [
    '눈꼬리가 위로 올라가 있다. 집중력과 기세가 눈에서 먼저 드러나는 결이라 관능이 적극적이고 주도적인 쪽으로 움직인다. 시선만으로 신호를 보내는 강점이 있는 타입이다.',
  ]),
  _Frag(_metLo('eyeCanthalTilt'), [
    '눈꼬리가 부드럽게 내려간 결이다. 온화함이 눈에서 먼저 전해져서 상대가 어깨의 힘을 저절로 풀게 되는 구조. 관능이 끌어안는 쪽으로 움직이는 포용형 타입이다.',
  ]),
  _Frag(_metHi('eyeAspect'), [
    '눈이 둥글고 크게 열려 있다. 호기심과 활력이 눈에서 그대로 넘치는 타입—감정 표현이 솔직하고 풍부해서 상대가 결을 읽기 쉬운 결이다.',
  ]),
  _Frag(_metLo('eyeAspect'), [
    '눈이 가늘고 길다. 관찰력과 심미안이 눈에 깊이 박혀 있어서, 말 없이 눈빛만으로 신호가 전달되는 타입. 상대에게는 그 절제된 신호가 오히려 숨을 멈추게 하는 긴장감이 된다.',
  ]),
  _Frag(_metHi('eyebrowThickness'), [
    '눈썹이 짙고 또렷하다. 활력의 축이 얼굴에 건강히 섞여 있는 결—몸의 컨디션과 욕구 리듬이 함께 움직이는 구조다. 수면과 체력이 관능의 결을 직접 조율하는 타입.',
  ]),
  _Frag(_metLo('eyebrowThickness'), [
    '눈썹이 얇고 담담하다. 크게 요동치지 않는 기질이 얼굴에 새겨진 결이라, 관능 역시 과하지 않은 안정권에 머문다. 평화와 독립이 먼저라, 관계 안에서 편안한 공기를 만드는 타입이다.',
  ]),
  _Frag(_metHi('eyebrowCurvature'), [
    '눈썹이 또렷한 아치형이다. 감수성과 예술 기질이 살아 있는 결—같은 상대와도 매번 다른 밤을 만들어 내는 창의형 구조다. 어제와 오늘의 공기가 다르게 조합되는 타입이다.',
  ]),
  _Frag(_metLo('eyebrowCurvature'), [
    '눈썹이 직선에 가깝다. 논리와 실용의 기질이 얼굴에 박혀 있어 리듬이 안정적이고 예측 가능하다. 이게 지루함이 아니라 신뢰의 기반이 되는 결이다.',
  ]),
  _Frag(_metHi('cheekboneWidth'), [
    '광대가 또렷이 자리했다. 체력의 축이 골격에 박힌 결이라 이 결의 수명이 길다. 짧은 집중이 아니라 긴 밀도를 내는 몸의 뿌리가 여기 있다—관계의 후반으로 갈수록 결이 더 깊어지는 구조.',
  ]),
  _Frag(_metLo('cheekboneWidth'), [
    '광대가 낮고 부드럽게 자리한다. 호령보다 조율이 먼저 얼굴에 읽히는 결이라, 표현이 섬세한 대화와 교감 쪽에 가깝다—베개 위의 긴 이야기가 더 어울리는 타입.',
  ]),
  _Frag(_metHi('nasolabialAngle'), [
    '코끝이 살짝 위로 들렸다. 개방적이고 낙천적인 기질이 자리 잡아서 표현이 가볍고 에너지가 넘친다. 새로운 장소, 새로운 시간대를 두려워하지 않는 탐험형 결이다.',
  ]),
  _Frag(_metLo('nasolabialAngle'), [
    '코끝이 아래로 처졌다. 보수적이고 안정 지향의 기질이 깔린 타입이라, 관능이 신뢰 쌓인 관계 안에서만 또렷이 열리는 깊이형 구조다.',
  ]),
  _Frag(_metHi('gonialAngle'), [
    '턱이 뚜렷한 각을 이뤘다. 의지와 끈기의 축이 하정에 새겨진 결이라 지속력이 강하다. 한 번 들어간 리듬을 끝까지 끌고 가는 체력형 구조—쉽게 흐트러지지 않는 타입이다.',
  ]),
  _Frag(_metLo('gonialAngle'), [
    '턱이 둥글게 자리했다. 부드러움과 친화가 하정에 자리한 결이라 표현이 격렬함보다 따뜻함, 포근함 쪽으로 기운다—이불 속의 편안한 온도 같은 결이다.',
  ]),
  _Frag(_metHi('faceAspectRatio'), [
    '얼굴이 세로로 길다. 사색과 몰입의 기운이 전체에 박혀 있어서, 관능이 깊이와 집중 쪽으로 흐른다. 한 사람에게만 통째로 쏠리는 몰입감—상대가 유일하게 느껴지는 결이다.',
  ]),
  _Frag(_metLo('faceAspectRatio'), [
    '얼굴이 가로로 넓다. 활력과 포용의 에너지가 자리 잡은 결이라 표현이 활달하고 개방적이다. 같이 있으면 공기가 환해지는 타입—주말 모임의 중심에 자연스럽게 놓이는 결이다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '옆에서 보면 입술이 E-line 을 넘어 나와 있다. 관능이 입매에서 먼저 드러나는 해부학적 구조—말하는 동안 상대 시선이 입에 머문다. 이야기 내용보다 입 모양이 먼저 기억되는 결이다.',
  ]),
  _Frag.hard(_yangStrong, [
    '여성의 얼굴에 양 의 기운이 뚜렷이 쏠린 결은 드문 타입이다. 관능의 리듬이 적극적이고 주도적인 쪽으로 자연스럽게 기운다—"먼저 움직이는 쪽" 을 당당하게 활용할 때 가장 선명한 매력이 드러나는 구조다.',
  ]),
  _Frag.hard(_yinStrong, [
    '얼굴 전체에 음 의 기운이 짙게 쏠려 있다. 수용과 포용의 축이 관능의 뼈대가 되는 타입—상대를 끌어안는 결 자체에서 농도가 피어난다. 시간이 깊어질수록 결이 더 또렷해지는 구조다.',
  ]),
  _Frag.hard(_yyHarmony, [
    '얼굴에 음양이 고르게 자리했다. 표현이 주도와 수용 사이를 자유롭게 오가는 유연형—파트너의 결에 맞춰 모드를 바꾸는 적응력이 최대 강점이다.',
  ]),
  _Frag.hard((f) => f.fired('O-PH1') || f.fired('O-PH2'), [
    '인중 쪽 결이 유독 두드러진 구조다. 호르몬과 생리 주기의 흐름이 표정과 밀도에 직접 나타나는 타입—그래서 몸의 리듬을 읽는 습관 하나가 이 결의 수명을 결정한다.',
  ]),
  _Frag.hard((f) => true, [
    '관능의 신호가 특정 부위에 몰리지 않고 얼굴 전체에 고르게 분포해 있다. 드라마틱한 단서 하나는 없지만 여러 부위가 함께 협업하는 결—폭이 넓고 안정적이다.',
    '부위별 신호가 모두 평균권에서 움직인다. 한 군데에 집중된 장점 대신 여러 축이 동시에 돌아가는 팀플레이형 결—상황별 적응력이 가장 큰 자산이다.',
  ]),
];

final List<_Frag> _sensualStrengthMale = [
  _Frag(_metHi('mouthCornerAngle'), [
    '웃을 때 입꼬리가 위로 확 올라간다. 기본 표정 자체가 살짝 웃는 상태라 침실에서도 웃음이 배경음으로 깔리는 타입—심각해질 순간에 자기도 모르게 긴장을 풀어내는 결이다. 관계의 무게를 스스로 덜어낼 줄 아는 남자.',
    '올라간 입꼬리는 긴장을 친화감으로 바꾸는 장치다. 상대가 당신 옆에 있으면 어깨에 들어가 있던 힘이 자연스럽게 빠진다. 그 공기 자체가 관능의 지속력을 받치는 구조다.',
  ]),
  _Frag(_metMid('mouthCornerAngle'), [
    '입꼬리가 수평에 가깝다. 처음엔 뭘 생각하는지 잘 안 읽히는 타입—첫인상은 차갑기까지 하다. 그런데 안쪽까지 들어온 사람에게는 기대치를 훌쩍 넘는 농도가 나오는 이중 구조다.',
  ]),
  _Frag(_metLo('mouthCornerAngle'), [
    '입꼬리가 살짝 내려간 결이다. 가볍게 풀리는 순간이 드물고 기본 분위기가 진지하다. 그래서 오히려 한마디, 한 손짓의 무게가 커진다. 파트너에게는 그 무게 자체가 빠져나갈 수 없는 집중감이 된다.',
  ]),
  _Frag(_metHi('lipFullnessRatio'), [
    '입술이 도톰하다. 마음 이라는 게 얼굴에서 먼저 읽히는 타입—말보다 표정이 먼저 닿는다. 같이 밥 먹으러 간 식당의 공기까지 부드럽게 만드는 결이다. 와인 한 잔만 있어도 분위기가 바뀐다.',
    '도톰한 입술은 감각이 살아 있다는 증거다. 미식, 향, 음악 같은 섬세한 즐거움이 관능과 자연스럽게 한 세트로 묶이는 타입. 상대에게 풍요로운 공기를 밀어 보내는 구조다.',
  ]),
  _Frag(_metMid('lipFullnessRatio'), [
    '입술 두께가 평균이다. 감성과 절제가 반반씩 섞인 결이라 어느 한쪽으로 쏠리지 않는다. 상대의 결에 맞춰 모드를 조용히 조절하는 타입—과하지도, 모자라지도 않는다.',
  ]),
  _Frag(_metLo('lipFullnessRatio'), [
    '입술이 얇다. 이성이 감정보다 반 박자 앞서는 결이다. 표현이 담담하게 나오는 대신, 그 한 번이 선명해서 오히려 오래 각인된다. 아껴 쓰는 사람의 한마디가 더 깊이 박히는 것과 같은 구조다.',
  ]),
  _Frag(_metHi('upperVsLowerLipRatio'), [
    '윗입술이 아랫입술보다 두껍다. 주는 쪽에서 충족감을 얻는 결—받는 것보다 배려하는 쪽이 자연스러운 타입이다. 침실의 기쁨이 "내가 좋았다" 보다 "둘 다 좋았다" 에서 완성되는 구조.',
  ]),
  _Frag(_metLo('upperVsLowerLipRatio'), [
    '아랫입술이 더 두껍다. 오감, 특히 질감과 온도에 민감한 타입—실크 셔츠의 감촉, 새벽 공기의 온도, 이런 디테일이 바로 몸에 등록된다. 조명 하나, 향수 하나가 공간 전체를 바꿔 놓는 결이다.',
  ]),
  _Frag(_metHi('philtrumLength'), [
    '인중이 길다. 관상학은 이걸 "오래가는 형" 이라 부른다. 쉽게 말하면 이런 거다. 짧게 폭발하는 게 아니라 긴 시간 밀도로 승부하는 구조. 같이 산 세월이 쌓일수록 오히려 몸의 감각이 더 깊어지는, 드문 결이다.',
  ]),
  _Frag(_metMid('philtrumLength'), [
    '인중 길이가 평균이다. 욕구의 리듬이 자연스럽게 오르락내리락하는 안정형. 오늘은 이만큼, 내일은 저만큼—몸의 신호를 따라 유연하게 움직이는 타입이다.',
  ]),
  _Frag(_metLo('philtrumLength'), [
    '인중이 짧다. 피크는 뚜렷한데 지속 구간이 짧은 단발형 결—짧은 시간 안에 농도를 압축해서 쓴다. 쌓는 시간과 쏟는 시간을 의식적으로 분리해 두면 리듬이 길어진다.',
  ]),
  _Frag(_metHi('eyeCanthalTilt'), [
    '눈꼬리가 위로 올라갔다. 집중력과 기세가 눈에서 먼저 새어 나오는 결—쳐다보면 상대가 먼저 시선을 피한다. 관능이 쫓는 쪽으로 움직이는 타입이고, 말없이 눈만으로 신호를 보내는 강점이 있다.',
  ]),
  _Frag(_metLo('eyeCanthalTilt'), [
    '눈꼬리가 부드럽게 내려간 결이다. 바라보고만 있어도 상대 어깨가 내려가는 구조—온화함이 먼저 닿는다. 관능이 몰아붙이는 쪽이 아니라 끌어안는 쪽으로 움직이는 포용형이다.',
  ]),
  _Frag(_metHi('eyeAspect'), [
    '눈이 둥글고 크게 열려 있다. 호기심과 활력이 눈에서 먼저 튀어나오는 타입—감정이 눈빛에 그대로 실린다. 표현이 솔직해서 상대가 당신 기분을 추측할 필요가 없는 결이다.',
  ]),
  _Frag(_metLo('eyeAspect'), [
    '눈이 가늘고 길다. 관찰력과 심미안이 눈에 박혀 있어서, 말 대신 눈빛이 먼저 가는 타입. 상대에게는 그 절제된 신호가 오히려 숨 멈추는 긴장감이 된다—조명 꺼진 엘리베이터 안의 정적 같은 결이다.',
  ]),
  _Frag(_metHi('eyebrowThickness'), [
    '눈썹이 짙고 두껍다. 의지와 결단의 기운이 얼굴에서 먼저 읽히는 결이라, 관능의 리듬에도 끈기의 축이 섞여 있다. 한 번 맞춘 호흡을 끝까지 끌고 가는 체력형 타입이다.',
  ]),
  _Frag(_metLo('eyebrowThickness'), [
    '눈썹이 얇고 담담하다. 크게 요동치지 않는 기질이 얼굴에 새겨져 있어서, 관능 역시 격렬하지 않은 안정권에 머문다. 상대에게는 편안한 공기—가을 일요일 오후 같은 결로 읽힌다.',
  ]),
  _Frag(_metHi('eyebrowCurvature'), [
    '눈썹이 또렷한 아치형이다. 감수성과 예술 기질이 살아 있는 결—같은 상대와도 매번 다른 밤을 만들어 내는 창의형 구조다. 어제와 오늘의 공기가 다르게 조합되는 타입.',
  ]),
  _Frag(_metLo('eyebrowCurvature'), [
    '눈썹이 직선에 가깝다. 논리와 실용이 얼굴에 박혀 있는 결이라 리듬이 안정적이고 예측 가능하다. 이게 지루함이 아니라 신뢰의 기반으로 작동하는 타입—상대가 먼저 안심하는 구조다.',
  ]),
  _Frag(_metHi('cheekboneWidth'), [
    '광대가 단단히 솟아 있다. 체력의 축이 골격에 박힌 결이라 관능의 수명이 길다. 짧은 집중이 아니라 긴 밀도를 내는 몸의 뿌리가 여기 있다—관계의 후반에 갈수록 오히려 결이 깊어지는 구조다.',
  ]),
  _Frag(_metLo('cheekboneWidth'), [
    '광대가 낮고 부드럽게 자리한다. 호령보다 조율이 먼저 얼굴에 읽히는 타입이라, 관능의 표현이 대화와 교감 쪽에 더 기운다. 베개에 나란히 누워 30분씩 이야기하는 게 더 자연스러운 결이다.',
  ]),
  _Frag(_metHi('nasolabialAngle'), [
    '코끝이 살짝 위로 들렸다. 개방적이고 낙천적인 기질이 얼굴에 자리 잡아서, 관능의 표현이 가볍고 에너지가 넘친다. 새로운 장소, 새로운 시간대에 거리낌이 적은 탐험형 결이다.',
  ]),
  _Frag(_metLo('nasolabialAngle'), [
    '코끝이 아래로 처졌다. 보수적이고 안정 지향의 기질이 깔린 타입이라, 관능이 신뢰 쌓인 관계 안에서만 또렷이 열린다. 아무하고나 열리지 않는 깊이형 구조다.',
  ]),
  _Frag(_metHi('gonialAngle'), [
    '턱이 각지게 자리했다. 의지와 끈기의 축이 하정에 새겨져 있어서 지속력이 강하다. 한 번 들어간 리듬을 끝까지 끌고 가는 체력형—새벽까지 흐트러지지 않는 구조다.',
  ]),
  _Frag(_metLo('gonialAngle'), [
    '턱이 둥글게 자리했다. 부드러움과 친화가 하정에 자리한 결이라, 관능의 표현이 격렬함보다 따뜻함 쪽으로 기운다. 이불 안의 포근한 온도 같은 결이다.',
  ]),
  _Frag(_metHi('faceAspectRatio'), [
    '얼굴이 세로로 길다. 사색과 몰입의 기운이 전체에 박혀 있어서, 관능이 깊이와 집중 쪽으로 흐른다. 한 사람에게 통째로 쏠리는 몰입감—상대가 유일하게 느껴지는 결이다.',
  ]),
  _Frag(_metLo('faceAspectRatio'), [
    '얼굴이 가로로 넓다. 활력과 포용의 에너지가 자리 잡은 결이라 표현이 활달하고 개방적이다. 같이 있으면 공기가 환해지는 타입—주말 브런치 자리의 분위기 메이커 같은 결이다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '옆에서 보면 입술이 E-line 을 넘어 나와 있다. 관능이 입매에서 먼저 드러나는 해부학적 구조—말할 때마다 상대 시선이 입에 머문다. 이야기 내용보다 입 모양이 먼저 기억되는 결이다.',
  ]),
  _Frag.hard(_yangStrong, [
    '얼굴 전체에 양의 기운이 짙게 서렸다. 관능의 리듬이 적극적이고 주도적인 쪽으로 기울어 있는 결—"먼저 움직이는 쪽" 이 자연스럽다. 상대가 그걸 기다리는 구조이기도 하다.',
  ]),
  _Frag.hard(_yinStrong, [
    '얼굴에 음의 기운이 깊이 깃들어 있다. 관능이 수용과 포용 쪽으로 기울어 있어서, 격렬한 파도보다 잔잔한 깊이로 관계를 만든다. 조명 꺼진 방의 부드러운 정적 같은 결이다.',
  ]),
  _Frag.hard(_yyHarmony, [
    '얼굴에 음양이 고르게 자리했다. 주도와 수용 사이를 자유롭게 오가는 유연형—오늘은 리드하고 내일은 받아주는 식의 전환이 매끄럽다. 파트너의 결에 맞춰 모드를 바꾸는 적응력이 최대 강점이다.',
  ]),
  _Frag.hard((f) => true, [
    '관능의 신호가 특정 부위에 몰리지 않고 얼굴 전체에 고르게 분포한다. 드라마틱한 단서 하나는 없지만 여러 부위가 함께 협업하는 구조—폭이 넓고 안정적이다.',
    '부위별 신호가 모두 평균권에서 움직인다. 한 군데에 집중된 장점 대신 여러 축이 동시에 돌아가는 팀플레이형 결이다. 상황별 적응력이 이 구조의 진짜 자산이다.',
  ]),
];

final List<_Frag> _socialAdvice = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '친화력과 신뢰가 같이 있으면 사람이 평생 자산이 됩니다. 함정은 딱 하나—"누구든 품을 수 있다"는 자신감입니다. 넓이는 이미 충분하니, 일 년에 한 번쯤은 명단을 줄여 깊이 쪽으로 무게를 옮겨 보세요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '들어오는 문은 넓은데 끝까지 가는 관계는 상대적으로 얇은 편입니다. 처음 친해진 사람과 일 년 뒤에도 연락을 절반만 유지하는 습관 하나면 관계의 깊이가 확 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '빨리 친해지고 빨리 식는 편입니다. 새 사람을 늘리기보다, 이미 아는 사람 한 명을 더 깊이 아는 쪽으로 에너지를 옮겨 보세요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '뜨거웠다 식는 사람보다, 미지근한 온도를 오래 유지하는 당신 같은 사람이 결국 멀리 갑니다. 먼저 안부 한 줄 보내는 월 1회 습관만 더해 두세요.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '넓지도 좁지도 않은 무난한 관계 스타일입니다. 석 달에 한 번 "연락 끊긴 사람 한 명"을 일부러 다시 챙기는 습관이, 시간이 지나면 큰 자산이 됩니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '새로 섞이는 힘도, 오래 가는 힘도 평균쯤입니다. 정기 모임 하나만 박아두면 관계 총량이 알아서 올라가는 타입이라, "유지 루틴"이 가장 효율 좋은 한 수입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '사교의 문은 좁아도 한 번 열린 관계는 평생 갑니다. 넓히려 애쓰지 말고, 있는 사람을 지키는 데 힘을 몰아주세요—당신한텐 이쪽이 훨씬 큰 이득입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사교성은 두껍지 않아도 있는 관계는 꾸준히 이어가는 편입니다. 새 사람 만나는 부담은 내려놓고, 지금 있는 자리에서 역할을 한 단계 더 맡아 보는 게 자연스러운 확장입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '관계가 인생의 중심축은 아닌 편입니다. 고립을 걱정하기보다, 혼자 쌓은 결과물을 보여줄 출구 하나를 만들어 두세요. 일이나 작품이 대신 사람을 데려다 줍니다.',
  ]),
  _Frag.hard((f) => true, [
    '관계를 키우는 건 의외로 단순합니다. 미지근한 온도를 오래 유지하기, 먼저 안부 건네기, 그리고 모두를 품으려 하지 않기. 이 셋이면 꼭 남아야 할 사람이 곁에 남습니다.',
    '진짜 자산은 "한 번에 크게 친해지는" 데서가 아니라 "십 년간 작은 연락을 안 놓치는" 데서 쌓입니다. 한 달에 한 줄, 안부 보내는 습관이 평생 네트워크를 바꿉니다.',
    '중요한 사람 다섯을 적고, 이번 달 각자에게 쓴 시간을 세어 보세요. 그 숫자가 관계의 진짜 지도입니다. 인상이 아무리 좋아도 이 지도를 안 그리면 노년의 사람 복은 얇아집니다.',
    '들어오는 문과 나가는 문을 따로 두세요. 정리 없이 받기만 하면 안이 옅어지고, 받지 않고 정리만 하면 밖이 끊깁니다. 두 흐름이 같이 움직여야 합니다.',
  ]),
  // age-stratified Advice — 20대 / 30~40대 / 50대 이후 사회운 변곡점.
  _Frag.hard(_isYoung, [
    '20대 인간관계는 깊이보다 폭이 더 중요합니다. 여러 분야·세대·문화의 사람을 만나본 사람이 30대 이후 진짜 네트워크를 갖게 됩니다. 한 그룹에 일찍 굳어지면 35세 이후 관계가 좁아지니, 지금은 자기와 다른 결의 사람을 일부러 만나두세요.',
    '20대는 평판의 씨앗을 뿌리는 시기입니다. 한 번의 작은 약속·납기·태도가 10년 뒤 평판의 토대가 됩니다. 화려한 인맥보다 지킨 약속의 누적이 진짜 사회 자본입니다.',
    '20대에 진짜 친구 3명을 만들 수 있느냐가 평생 외로움을 좌우합니다. 같은 학교·직장 동기에 그치지 말고, 서로의 약한 부분까지 나눌 수 있는 사람을 한 명이라도 일찍 만들어 두세요. 그 한 명이 평생 정신 자산의 절반이 됩니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대에는 20대에 쌓은 네트워크가 처음으로 자산으로 돌아옵니다. 단순한 친분이 협업·추천·기회로 발전하는 단계입니다. 다만 받기만 하고 흘려보내지 않으면 네트워크가 빠르게 식습니다.',
    '30~40대 사회운의 표현은 대표성입니다. 한 분야·한 집단을 대표하는 자리에 자연스럽게 서게 됩니다. 책임을 회피하지 말고 그 무게를 받아들이는 일이 다음 단계를 엽니다.',
    '30~40대 관계의 핵심은 새 사람을 추가하는 속도보다 오래 안 본 사람을 다시 만나는 빈도입니다. 분기에 한 번씩 연락이 끊긴 사람 3명을 의도적으로 복원하는 습관이 가장 큰 자산을 만듭니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 사회운은 멘토링에서 나옵니다. 자기가 쌓은 인맥과 통찰을 후배에게 흘려보낼 줄 아는 사람이 노년이 외롭지 않습니다. 다만 그 자리는 의식적으로 만들지 않으면 저절로 생기지 않습니다.',
    '50대 이후에는 깊은 친구 3명이 100명의 지인보다 값집니다. 오래 함께한 동료를 정기적으로 만나고, 가족과의 시간 비중을 다시 조정하는 두 가지가 노년 행복의 80%를 정합니다. 새 인맥을 늘리는 욕심을 내려놓고 기존 관계를 두텁게 다지세요.',
    '50대 이후엔 의무 없는 정기 모임이 노년 정신 건강의 가장 큰 자산입니다. 오래된 친구 모임, 공동 취미 그룹, 정기 산책 모임 — 일부러 만들어 두는 사람이 10년 더 정신적으로 깨끗하게 삽니다.',
  ]),
];

final List<_BeatPool> _socialBeats = [
  _socialOpening,
  _socialVignette,
  _socialStrength,
  _socialShadow,
  _socialAdvice,
];

// ═══ 3. 대인관계 ═══

// 행동 vignette — "너 이럴 때 있지?" 구체 장면. 독자가 자기 안에서 알아보는
// 한 컷을 던진다. 가장 잘 맞는 한 장면만 뽑히고, 못 맞으면 fallback.
final List<_Frag> _socialVignette = [
  _Frag(_highOf(Attribute.trustworthiness), [
    '부탁은 웬만하면 들어주는 편이지만, 속으로 "이 정도면 충분히 해줬는데" 싶었던 적이 한 번쯤 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '겉으론 웃으며 "괜찮아"라고 해놓고, 돌아서서 두고두고 곱씹은 적이 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '평소엔 좋게좋게 넘어가다가도, 선을 넘었다 싶은 순간엔 의외로 딱 잘라 선을 그어 주변을 놀라게 한 적이 있을 겁니다.',
  ]),
  _Frag(_lowOf(Attribute.sociability), [
    '여럿이 모인 자리보다 마음 맞는 한두 명과 있을 때가 훨씬 편하고, 모임이 끝나면 혼자 충전할 시간이 꼭 필요한 편입니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '자리가 어색해지면 누가 시키지 않아도 먼저 말을 꺼내 푸는 쪽이라, "네가 있으면 편하다"는 말을 @{heard}.',
  ]),
  _Frag.hard((f) => true, [
    '모두에게 좋은 사람이고 싶다가도, 정작 내 사람한테 쓸 에너지가 모자란 것 같아 마음에 걸린 적이 있을 겁니다.',
    '연락은 늘 상대가 먼저인 것 같아 서운하다가도, 막상 내가 먼저 하긴 어색해서 미룬 적이 있을 겁니다.',
    '겉으론 둥글게 잘 지내는 것 같아도, 진짜 속얘기를 꺼내는 상대는 손에 꼽는 편입니다.',
  ]),
];

final List<_Frag> _socialOpening = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '처음 본 사람도 편하게 다가오는데, 정작 끝까지 가는 사람은 따로 챙기는 편입니다. 사람을 빨리 여는 친화력과 한 번 맺으면 오래 가는 신뢰가 같이 있어서, "저 사람은 적이 없다"는 말을 @{heard}.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '낯선 자리에서도 분위기를 금방 풀어놓는 편입니다. 처음 만난 사람은 "생각보다 친근하다"고 느끼지만, 정작 마음을 다 여는 데는 시간이 좀 걸리는 스타일로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '사람을 모으는 데는 확실히 강합니다. 어느 자리에 가도 금세 중심에 서는 편인데, 그 관계를 오래 끌고 가는 건 또 다른 문제라 "처음엔 친했는데" 하는 경우가 종종 생깁니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '말수가 많지 않아도 "믿을 만한 사람"이라는 인상이 먼저 갑니다. 화려하게 사람을 끌진 않지만, 시간이 지날수록 곁에 남는 사람이 늘어나는 쪽입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '넓게 두루 지내기보다 정해둔 몇 사람한테 집중하는 편으로 보입니다. 한 번에 우르르 친해지진 않아도, 한 번 친해지면 잘 안 끊는 스타일입니다.',
    '사교성도 신뢰도 한쪽으로 치우치지 않고 가운데에 있는 편입니다. 상황 따라 나설 때는 나서고 빠질 때는 빠지는, 균형 잡힌 관계 스타일로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '사람 만나는 것도, 관계 이어가는 것도 딱 평균쯤입니다. 가만 두면 관계가 저절로 쌓이진 않지만, 모임 하나만 정해두면 충분히 유지되는 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '새 사람을 많이 만나는 타입은 아닌데, 한 번 가까워진 사람과는 정말 오래 갑니다. 많은 인맥보다 깊은 몇 명으로 사는, 소수정예형으로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '먼저 다가가 사람을 늘리는 편은 아니지만, 이미 아는 사람은 꾸준히 챙기는 편입니다. 한 자리에 오래 머물면서 천천히 신뢰를 쌓는 스타일입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '사람을 많이 만나는 것도, 오래 붙잡는 것도 크게 신경 쓰지 않는 편으로 보입니다. 혼자 있는 시간이 불편하지 않고, 오히려 그 시간에 결과물이 나오는 타입입니다.',
  ]),
  _Frag.hard((f) => true, [
    '한쪽으로 쏠리지 않고 상황에 맞춰 사람을 대하는 편입니다. 넓이와 깊이 사이에서 적당히 균형을 잡는, 어느 자리에 놔도 무난하게 섞이는 스타일로 보입니다.',
    '첫인상의 임팩트보다, 몇 번 만나고 나서 "편하다"는 느낌을 주는 쪽입니다. 그래서 시간이 갈수록 사람이 붙는 편입니다.',
    '두루 친하게 지내는 편인데, 그중에서도 진짜 마음 주는 사람은 따로 있는 편으로 보입니다.',
    '말을 많이 안 해도 사람들이 자연스럽게 가운데 자리에 앉히는 편입니다. 나서지 않아도 어느새 중재자가 되어 있곤 합니다.',
  ]),
];

final List<_Frag> _socialShadow = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 누구든 품으려다 보니 먼저 지치기 쉽습니다. 주는 정이 받는 정을 오래 앞지르면 조용히 소진되니, 가끔은 명단을 줄이는 게 숙제입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 그냥 두면 관계가 자연스럽게 줄어드는 쪽으로 흐릅니다. 의식적으로 연락하는 장치가 없으면 중년 이후 외로움이 빨리 옵니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '다만 처음의 열기가 식으면 같은 사람을 꾸준히 챙기는 힘은 약한 편입니다. 아는 사람은 많은데 깊은 얘기 할 사람은 적은 허전함이 올 수 있습니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 거리 조절 폭이 좁은 편입니다. 가까워지면 확 들어가고, 한 번 실망하면 단번에 멀어지는 "0 아니면 100"이 반복되기 쉽습니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 중요한 사람한테 몰아주고 나머지는 방치하는 패턴이 있어서, 정작 필요한 순간에 "주변에 사람이 없네" 싶을 수 있습니다.',
    '다만 남의 리듬에 맞추다 자기 배터리가 먼저 바닥납니다. 사람 좋아할수록, 혼자 회복하는 시간을 따로 지켜야 관계의 질이 유지됩니다.',
    '다만 갈등을 피하려다 선 그을 타이밍을 놓치기 쉽습니다. "싫다"는 말을 제때 못 하면 어느새 손해 보는 자리에 서 있게 됩니다.',
    '다만 "친했다가 떠난" 사람한테 제일 약합니다. 모든 관계가 영원하진 않다는 걸 받아들이지 못하면, 떠난 사람 자리에 새 사람이 못 들어옵니다.',
    '다만 "좋은 사람" 소리를 지키려다 정작 선택의 자유를 깎아먹기 쉽습니다. 모두에게 같은 얼굴을 하려다 보면, 진짜 친한 사람 들어올 자리가 오히려 얕아집니다.',
  ]),
];

final List<_Frag> _socialStrength = [
  _Frag.hard((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입과 눈이 같이 잘 움직이는 편이라 대화 리듬이 좋습니다. 같이 있으면 "이 사람은 내 편 같다"는 느낌을 주는 쪽입니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '옆에서 보면 콧대가 또렷한 편인데, 중요한 순간엔 자기 의견을 분명히 내서 관계가 한쪽으로 끌려가지 않습니다.',
  ]),
  _Frag.hard((f) => f.fired('L-SN'), [
    '코끝이 살짝 들린 편이라, 낯선 자리에 섞여드는 속도가 남보다 빠릅니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.8, [
    '입매가 또렷해서 말의 완급 조절이 자연스럽고, 설득하거나 중재하는 자리에서 존재감이 납니다.',
  ]),
  _Frag.hard((f) => f.fired('P-10') || f.nodeZ('eye') >= 0.8, [
    '눈매가 맑은 편이라 첫인상에서 경계를 풀어줍니다. 처음 보는 사람도 비교적 쉽게 다가옵니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹이 정돈된 편이라, 또래나 동료 사이에서 중재 역할이 자연스럽게 돌아오는 쪽입니다.',
  ]),
  _Frag.hard((f) => true, [
    '오래 갈 소수와 스쳐 갈 다수가 비교적 분명하게 나뉘는 편이라, 시간이 지날수록 진짜 가까운 사람들만 또렷이 남습니다.',
    '말을 많이 안 해도 사람들이 자연스럽게 가운데 자리에 앉히는 편입니다. 굳이 나서지 않아도 중재자가 되는 쪽입니다.',
    '상대 기분을 먼저 읽고 내 반응 온도를 맞추는 감이 남보다 반 박자 빠른 편이라, 쓸데없는 마찰이 잘 안 생깁니다.',
    '한 번 한 약속은 어지간하면 지키는 편이라, "믿고 맡길 수 있다"는 말을 @{heard}.',
  ]),
];

final List<_Frag> _talentAdvice = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '재능을 살리는 길은 "판 전체를 보는 눈"과 "앞장서는 발"을 같이 쓰는 자리입니다. 기획과 실행이 한 사람 안에서 도는 자리—창업·사업부·연구 책임자—에서 진짜로 열립니다. 분석만 하거나 앞에만 서면 아깝습니다. 두 축을 같이 쓸 무대를 3년 안에 잡아두세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '"먼저 읽고 뒤에서 설계하는" 쪽입니다. 참모·전략·아키텍트 자리에서 밀도가 가장 높습니다. 스포트라이트보다 판 아래 구조를 짜는 게 맞고, 나중에 "저 사람이 짰구나" 알려지는 식이 평생 따라옵니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '깊게 파는 전문가형입니다. 연구·분석·저술처럼 혼자 밀어붙이는 시간에서 가장 두꺼워집니다. 조직 안에서도 리더보다 "없으면 안 되는" 전문직으로 설계하세요. 앞에 서는 자리가 길어지면 오히려 재능이 빠져나갑니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '끌고 가는 힘이 중심입니다. 디테일보다 방향, 논리보다 결단—사람을 움직이는 자리에서 가장 크게 열립니다. 혼자 깊이 파는 일은 답답하니, 팀·현장 지휘형으로 일찍 방향을 잡으세요.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '한쪽으로 안 쏠린 균형형입니다. 단기 폭발력은 낮아도 3·5·10년 쌓이는 곡선이 평균을 확실히 넘습니다. 맞는 판만 골라두면 됩니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '말보다 손인 쪽입니다. 선언하는 역할보다 한 가지 결과물을 정직하게 만드는 데서 진가가 납니다. 장인·실무·크래프트 트랙이 맞고, 3년 이상 머물면 평균을 넘는 깊이가 쌓입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '판을 직관으로 잡는 쪽입니다. 데이터를 기다리다 놓치기보다 먼저 움직여 기회를 가져옵니다. 따져주는 조력자를 옆에 두면 상한이 단번에 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '머리도 발도 극단은 아닌데, 한 영역에 반복 노출되면 남들이 못 보는 패턴을 잡습니다. 같은 일을 3년 반복하는 환경이 가장 큰 자산입니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '손끝·몸·감각으로 자라는 쪽입니다. 추상적 판단보다 몸으로 익히는 기술에서 진가가 납니다. 숫자가 아니라 결과물의 완성도로 승부하세요.',
  ]),
  _Frag.hard((f) => true, [
    '재능을 살리는 건 셋입니다. @__STRONGEST_NODE__이 가장 잘 작동하는 환경을 일찍 고르기, 남의 속도와 비교하지 않기, 결과물을 정기적으로 바깥에 내놓기. 이 셋이 맞물릴 때 천장이 열립니다.',
    '재능은 "방향"과 "들인 시간"의 곱으로만 열립니다. 방향 틀린 10년이 방향 맞는 반년보다 작습니다. 방향 잡는 힘은 이미 있으니, 결정적 갈림길 서너 번에 외부 조언을 일부러 구하세요.',
    '하나를 십 년 파는 설계에 맞는 편입니다. 여러 분야를 얕게 건드리면 오히려 천장이 낮아집니다. 20대에 방향 정하고 30대에 만 시간 들이는 정공법이 가장 정직한 곡선을 그립니다.',
    '"자기 결을 거스르지 말 것." @__STRONGEST_NODE__을 외면하고 다른 길을 억지로 가면 능력의 20%만 열고, 그 결을 따라가면 같은 노력으로 80%를 엽니다.',
    '재능의 상한을 올리는 건 "피드백 빈도" 하나입니다. 혼자 쌓기만 하면 자기 수준을 모른 채 늙고, 작게라도 자주 내놓으면 두 배 빨리 큽니다. 첫 공개를 미루지 마세요.',
  ]),
  // age-stratified Advice — 20대 / 30~40대 / 50대 이후 재능 변곡점.
  _Frag.hard(_isYoung, [
    '20대 @{talent_word}은 한 길에 일찍 굳어지지 않는 게 핵심입니다. 자기 강점이 어떤 영역에서 가장 빛나는지 찾는 데는 5~7년의 다양한 시도가 필요합니다. 지금은 한 가지에 갇히지 말고 세 갈래쯤 동시에 얕게 시도해 보세요.',
    '20대는 머리로 배우는 속도가 평생 가장 빠른 시기입니다. 지금 익히는 한 가지 기술·언어·도구가 평생 기본 자산으로 남습니다. 깊이보다 뼈대 다지기에 시간을 쓰는 게 답입니다.',
    '20대의 @{talent_word}은 멘토·환경·동료 세 가지가 80%를 정합니다. 혼자 깊어지려 하기보다 자기보다 5~10년 앞선 사람 옆에 일부러 자리 잡은 사람이 두 배 빨리 큽니다. 지금부터 누구와 시간을 보내느냐가 30대 직장 운을 정합니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대는 여러 시도가 한 줄기로 모이는 시기입니다. 자기 강점을 중심으로 다른 잔가지를 쳐내야 진짜 깊이가 생깁니다. 지금 한 가지에 5,000시간을 쓰면 40대 후반에 "전문가" 소리가 자연스럽게 따라옵니다.',
    '30대 후반에서 40대 초반에 그동안 쌓은 결과가 한꺼번에 모입니다. 이 시기를 놓치지 않으려면 지금 비축해 둔 깊이가 충분해야 합니다. 다양성에서 깊이로, 실행에서 판단으로 무게 중심이 옮겨가는 시기입니다.',
    '30~40대 @{talent_word}은 한 분야의 깊이로 다른 분야에 발판을 만드는 단계입니다. 자기 전문성을 가르치고·쓰고·연결하는 자리로 의식적으로 확장하지 않으면 40대 후반에 천장이 닫힙니다. 지금이 직장 운을 충분히 키워둘 마지막 구간입니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 @{talent_word}은 전수가 핵심입니다. 자기가 쌓은 깊이를 다음 세대에게 흘려보낼 줄 아는 사람의 얼굴이 가장 빛납니다. 새로 쌓는 일보다 잘 흘려보내는 설계가 인생 마지막 30%를 만듭니다.',
    '50대 이후엔 실행보다 판단으로 무게 중심이 옮겨갑니다. 큰 흐름을 읽는 통찰이 깊어지는 대신 세부 실행은 후배에게 맡길 줄 알아야 재능이 오래갑니다. "혼자 다 하려는" 욕심이 가장 큰 함정입니다.',
    '50대 이후의 재능은 평생 쌓은 경험을 책·강의·멘토링·자문 같은 외부 자산으로 전환하는 5~10년이 가장 큰 정신적 자산이 됩니다. 그동안의 깊이가 이 시기에 가장 풍성하게 되돌아옵니다.',
  ]),
];

final List<_BeatPool> _talentBeats = [
  _talentOpening,
  _talentVignette,
  _talentStrength,
  _talentShadow,
  _talentAdvice,
];

// ═══ 1. 타고난 재능 ═══

// 행동 vignette — 재능·머리·추진력이 일상에서 드러나는 한 컷.
final List<_Frag> _talentVignette = [
  _Frag(_highOf(Attribute.intelligence), [
    '남들은 아직 상황을 파악하는 중인데 혼자 결론까지 가 있어서, 그걸 설명하느라 답답했던 적이 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '회의가 결론 없이 빙빙 돌면, 결국 "그럼 이렇게 하죠" 하고 자기가 정리해버린 적이 있을 겁니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.intelligence) == _Band.high && f.bandOf(Attribute.leadership) == _Band.low, [
    '아이디어는 내가 냈는데 발표나 공은 다른 사람이 가져가, 속으로 억울했던 적이 있을 겁니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '새로 배우는 건 빠른데, 한 우물을 오래 파는 건 의외로 자기랑 안 맞는다고 느낀 적이 있을 겁니다.',
  ]),
  _Frag.hard((f) => true, [
    '하나에 꽂히면 시간 가는 줄 모르다가, 막상 관심이 식으면 칼같이 손을 놓은 적이 있을 겁니다.',
    '"머리는 좋은데" 로 시작하는, 칭찬인지 아닌지 모를 말을 @{heard}.',
    '완성될 때까지 안 내놓고 쥐고 있다가, 그새 흐름이 바뀌어 버린 적이 한 번쯤 있을 겁니다.',
  ]),
];

final List<_Frag> _talentOpening = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '머리와 추진력이 둘 다 굵은 편입니다. 판을 먼저 읽고 그 판에 직접 올라가 흐름을 바꾸는 쪽이라, 기획과 실행을 한 사람이 다 쥘 때 진짜 힘이 납니다.',
    '혼자 생각하는 시간에 답을 찾고, 사람 앞에 설 때 그 답이 완성되는 타입입니다. 읽는 힘과 끌고 가는 힘이 한 몸에 같이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '상황을 읽는 힘은 유난히 두꺼운데, 앞장서기보다 한 발 뒤에서 구조를 짜는 편입니다. 참모·기획·설계 자리에서 진짜 실력이 나오는 쪽으로 보입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '읽는 눈은 깊은데, 앞에 나서는 건 아직 서툰 편입니다. 연구·분석·글처럼 깊게 파는 일에서 밀도가 가장 높아지고, 혼자 쌓는 시간이 길수록 결과가 커집니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '세세한 분석보다 "방향을 잡는 감"이 강점입니다. 말하지 않아도 주변이 당신의 결정을 기다리는 분위기가 있어서, 사람을 움직이는 자리에서 가장 크게 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '한쪽으로 안 쏠린 균형형입니다. 판단과 실행이 같이 가서 화려하진 않아도, 시간 위에 올려놓으면 누구보다 정직하게 쌓이는 편입니다.',
    '어느 자리에 놔도 그 자리 언어를 빠르게 흡수하는 편입니다. 첫인상보다 세 번째 만남 뒤에 자리잡는 신뢰가 진짜 자산입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '그림을 그리기보다 "손으로 결과를 만드는" 쪽에 가깝습니다. 장인·기술·실무 트랙에서 정직하게 쌓이고, 반복할수록 깊이가 붙는 편입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '분석으로 결정을 미루기보다 직관으로 먼저 움직이는 편입니다. 현장 감각이 살아 있어서, 데이터를 기다리다 놓치는 사람보다 기회를 먼저 잡습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '같은 일을 반복하는 속에서 남들이 못 보는 패턴을 잡아내는 "현장 지능"이 강점입니다. 한 분야에 몇 년 머물수록 평균을 넘는 감이 붙습니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '머리의 날카로움이나 통솔력이 무대 중앙은 아닌 편입니다. 대신 손끝·몸·감각으로 자라는 쪽이라, 몸으로 익히는 솜씨에서 진가가 납니다.',
  ]),
  _Frag.hard((f) => true, [
    '재능이 한쪽으로 안 쏠리고 여러 곳에 고루 깔린 편입니다. 한 분야 천재성보다, 서로 다른 두 세계를 잇는 "연결자" 쪽에서 크게 열립니다.',
    '한 번의 스파크보다 3년·5년·10년 쌓일 때 진짜 모습이 나오는 축적형입니다. 같은 일을 다른 각도로 반복할수록 깊이가 붙습니다.',
    '한 군데가 혼자 튀기보다 여러 곳이 같이 받쳐주는 편이라, 독주보다 합주가 어울립니다. 팀·협업 속에서 진가가 나는 쪽입니다.',
  ]),
];

final List<_Frag> _talentShadow = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '다만 "혼자 다 해야 직성이 풀리는" 피로가 쌓이기 쉽습니다. 위임이 서툴면 능력 천장이 내 체력에 묶이고, 옆 사람이 안 자랍니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.intelligence) == _Band.high && f.bandOf(Attribute.leadership) == _Band.low, [
    '다만 앞에 안 나서면, 내가 짠 분석과 설계가 남의 이름으로 넘어가기 쉽습니다. 일부러 드러내는 습관 없이는 실력이 저평가됩니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.intelligence) == _Band.low && f.bandOf(Attribute.leadership) == _Band.high, [
    '다만 직관이 강한 만큼 근거 없는 추진이 사고로 이어지기 쉽습니다. 따져주는 사람을 옆에 안 두면 "빠른데 방향이 틀린" 패턴이 반복됩니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 흥미가 옮겨가는 속도가 빠른 편입니다. 머리가 먼저 달려가고 몸이 못 따라가면, 재능이 쌓이지 않고 흩어집니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 감수성이 깊은 만큼 비판에 흔들리는 폭도 넓습니다. 외부 피드백을 어떻게 거르느냐가 평생 숙제입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 재능이 쌓은 시간에 정직하게 비례합니다. 남이 일찍 빛나는 데 흔들리면 잠재력이 절반만 열린 채 흘러가기 쉽습니다.',
    '다만 "보여주는 기술"이 약해서, 실력에 비해 덜 평가되는 일이 반복되기 쉽습니다. 일부러 내놓는 습관이 유일한 해법입니다.',
    '다만 완성도에 집착하는 편이라, 70%에서 못 멈추고 쥐고 있다가 흐름을 놓치는 경우가 있습니다.',
    '다만 여러 분야를 얕게 건드리는 유혹이 자주 옵니다. 호기심은 장점이지만, 한 곳을 3년 안 파면 천장의 절반도 못 엽니다.',
  ]),
];

final List<_Frag> _talentStrength = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 또렷하게 자리한 편이라, 새 지식을 빨리 흡수하고 한 번 방향을 정하면 잘 안 꺾입니다.',
    '눈썹이 짙고 정돈된 편이라, 목표가 서면 결과까지 밀어붙이는 힘이 강합니다.',
  ]),
  _Frag.hard((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '이마가 시원하게 넓은 편이라, 윗사람의 도움이나 윗선의 기회가 비교적 먼저 찾아오는 쪽입니다.',
    '이마가 반듯해서, 초년의 운과 지도력의 기반이 같이 열려 있는 편으로 봅니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM'), [
    '눈과 입의 표현이 같이 살아 있어서, 감정을 말로 정확히 옮기는 재능이 있습니다. 글·강연·연기에서 설득력이 납니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대가 받쳐주는 편이라, 혼자 잘하기보다 사람을 부려 일을 키우는 쪽에서 재능이 확장됩니다.',
    '광대가 힘있게 자리해서, 순수 전문가보다 리더·관리자 자리에서 진가가 납니다.',
  ]),
  _Frag.hard((f) => f.fired('O-FB'), [
    '이마와 턱이 같이 단정해서, 한 프로젝트를 처음부터 끝까지 맡을 때 결과가 제일 좋습니다.',
  ]),
  _Frag.hard((f) => f.nodeAZ('nose') >= 1.0, [
    '콧대가 또렷한 편이라, 자기 길에 대한 확신이 강하고 남의 평가에 잘 안 흔들립니다.',
  ]),
  _Frag.hard((f) => f.fired('A-02'), [
    '이마 기운이 열린 편이라, 또래보다 이른 나이에 한 번 치고 나가는 시기가 옵니다.',
  ]),
  _Frag.hard((f) => true, [
    '화려한 한순간보다 시간에 정직하게 쌓이는 축적형이라, 늦게 크는 쪽에 가깝습니다.',
    '첫 만남의 화력보다, 세 번째 만남 뒤 자리잡는 신뢰에서 힘이 나옵니다.',
    '결과만이 아니라 과정 끝까지 책임지는 편이라, 마지막 20% 잔무를 물고 가는 뚝심이 동료가 제일 부러워하는 점입니다.',
    '엔진이 두 개라, 한쪽이 지치면 다른 쪽이 받칩니다. 피크는 늦게 와도 정체 구간이 짧은 편입니다.',
    '하나에 꽂히면 깊이 파고드는 집중력이, 평범해 보여도 결국 격차를 만드는 진짜 무기입니다.',
  ]),
];

final List<_Frag> _wealthAdvice = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '버는 감각과 지키는 뚝심이 같이 있는 "큰 재물형"입니다. 이 재능을 복리로 돌리려면 자산 구조에 집중하세요. 월급보다 매달 자동으로 쌓이는 액수가 진짜 크기이고, 남의 돈·남의 시간을 다루는 경험이 30대에 들어오면 평생 곡선이 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '기회를 읽는 눈은 날카로운데 지키는 쪽은 평균입니다. 버는 힘이 강해 손실도 빨리 복구되지만, 호황기에 포지션을 안 키우는 규율이 평생 자산 크기를 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '재주는 좋은데 담는 그릇이 속도를 못 따라갑니다. 손에 남기려면 "버는 능력"이 아니라 "자동 저축 시스템"에 투자하세요. 사람 손 안 타는 구조만이 이걸 지킵니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '"잃지 않는 힘"이 받치는 편입니다. 한 방보다 시간이 자산이 되는 장기 투자·근속·부동산에서 진가가 나니, 5년 단위 복리 설계가 평생 재산을 정합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '극단 없는 평균형입니다. 생활 습관이 그대로 자산이 되는 정직한 구조라, 매달 고정 저축을 수입의 25% 이상으로 자동화해 두는 것만으로 상한이 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '버는 감각은 평균인데 감정이 결정에 자주 끼어듭니다. 큰 금전 결정은 무조건 24시간 묵히는 규칙 하나만 박아두면 결과의 절반이 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '만드는 손은 얇아도 지키는 힘이 받칩니다. 근로·전문직·장기 근속이 맞고, 버는 기술보다 안 쓰는 기술에 투자할 때 말년 자산이 역전됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '만드는 결도 지키는 결도 평균인데, 생활 습관이 자산에 제일 정직하게 반영됩니다. 자동 이체 저축의 힘이 누구보다 크게 작동합니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재물이 중심축은 아닙니다. 억지로 가운데 두면 소모만 크니, 재능·관계·경험을 중심에 두고 돈은 부산물로 따라오게 설계하면 곡선이 훨씬 낫습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재물의 상한을 여는 셋: 고정 저축 자동화, 남의 돈·남의 시간을 다루는 경험, 감정 과잉일 때 결정 보류. 이 셋이 지켜질 때 잠재력이 순서대로 열립니다.',
    '재물은 "한 타점"보다 "누적 확률"로 쌓입니다. 큰 베팅 한 번보다 매달 도는 고정 저축이 당신 결에 더 맞고, 5년 누적이면 차이가 두 배 이상 벌어집니다.',
    '핵심은 "들어온 돈을 얼마나 오래 머물게 하느냐"입니다. 먼저 고칠 건 버는 기술이 아니라 쓰는 기준—월별 카테고리 한도 하나가 평생 자산을 바꿉니다.',
    '돈은 유입·유지·증식 셋입니다. 가장 약한 축부터 보세요. 유입이 약하면 수입원을, 유지가 약하면 규율을, 증식이 약하면 복리 자산에 시간을 들이면 됩니다.',
    '재물 곡선은 "결정적 서너 번의 선택"이 평생 총량의 70%를 정합니다. 집·직업·동업 같은 큰 결정 앞에서 서두르지 말고, 평소 10배의 시간을 들여 조사하세요.',
  ]),
  // age-stratified Advice — 20대 / 30~40대 / 50대 이후 재물 변곡점.
  _Frag.hard(_isYoung, [
    '20대 재물의 핵심은 한 직업에 일찍 갇히지 않는 것입니다. 20대 후반까지 두세 갈래의 수입원을 시도해 본 사람이 30대에 자기 기울기를 찾습니다. 지금은 적은 액수라도 자동 저축을 시작해 두는 게 5년 뒤 종잣돈의 크기를 정합니다.',
    '20대는 매달 자동 저축을 수입의 30% 이상으로 박아 둘 때 30대 초반에 복리가 작동합니다. "한 번의 직장이 평생을 정한다"는 생각에서 빨리 빠져나오세요. 재물이 진짜로 풀리는 시기는 20대가 아니라 30~40대입니다.',
    '20대 재물은 버는 기술보다 안 쓰는 기준에서 갈립니다. 또래의 소비 압력에 휘둘리지 말고, 카테고리별 한도를 먼저 정해 두는 사람이 30대에 종잣돈 격차를 만듭니다. 집·차·결혼 같은 큰 결정은 반드시 1년 묵혀서 정하는 규칙이 평생 자산을 바꿉니다.',
  ]),
  _Frag.hard(_isMid, [
    '30~40대 5~7년이 평생 자산의 70%를 정합니다. 한 분야에서 충분히 깊어진 뒤 그 깊이로 다른 분야에 발판을 만들 줄 알아야 합니다. 안정과 확장 사이의 균형이 중요한데, 한 번 크게 풀린 직후의 두 번째 확장이 가장 큰 함정입니다.',
    '35~45세에 자산이 가장 빠르게 늘어납니다. 다만 한 번의 성공을 두 번째 베팅으로 잘못 가져가면 평생 곡선이 평탄해집니다. 지금은 역설적으로 가장 보수적인 자산 배분이 필요한 시기입니다.',
    '40대는 남의 돈·남의 시간을 다루는 경험이 평생 자산을 정하는 시기입니다. 자기 노동으로만 버는 모델에서 시스템·조직·자산이 버는 모델로 전환해야 합니다. 지금 키우는 사람·조직·구조가 50대 이후 나를 대신해 일하는 자산이 됩니다.',
  ]),
  _Frag.hard(_isLate, [
    '50대 이후의 재물은 쌓는 일보다 잘 흘려보내는 일입니다. 자식·후배·공동체로 흐른 돈이 결국 자기 노년의 풍요로 되돌아옵니다. 증여·기부·투자 비율을 미리 설계하고, 한 번의 큰 손실이 회복의 시간을 갉아먹지 않도록 방어선을 두텁게 깔아 두세요.',
    '50대 이후는 수익률을 좇기보다 자산 분산·유동성·상속 구조를 정비할 시기입니다. 큰 결정은 반드시 가족·전문가와 공유하고, 혼자 판단하는 영역을 의식적으로 줄이세요. 잘 관리된 분배만이 노년의 복을 열어 줍니다.',
    '60대 이후의 재물은 건강·관계·자산 셋의 균형에서만 의미를 가집니다. 자산만 두텁고 건강·관계가 얇으면 노년의 평온이 빠르게 흐려집니다. 지금은 자산을 더 늘리는 욕심보다 이미 쌓은 자산을 어떻게 의미 있게 흘려보낼지의 설계가 진짜 노년의 복을 만듭니다.',
  ]),
];

final List<_BeatPool> _wealthBeats = [
  _wealthOpening,
  _wealthVignette,
  _wealthStrength,
  _wealthShadow,
  _wealthAdvice,
];

// ═══ 2. 재물운 ═══

// 행동 vignette — 돈을 대하는 버릇이 드러나는 한 컷.
final List<_Frag> _wealthVignette = [
  _Frag(_highOf(Attribute.wealth), [
    '"저거 되겠다" 싶었던 게 진짜 되는 걸 보고, 남보다 돈 냄새를 빨리 맡는다고 느낀 적이 있을 겁니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다들 지를 때 혼자 안 사고 버텼다가, 나중에 "안 사길 잘했다" 싶었던 적이 있을 겁니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '기분 좋으면 평소 안 쓸 돈을 질러놓고, 다음 날 영수증 보며 후회한 적이 있을 겁니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '분명 통장에 들어왔는데 어디로 샜는지 모르게 사라진 경험, 한 번쯤 있을 겁니다.',
  ]),
  _Frag.hard((f) => true, [
    '큰돈 쓸 일 앞에서 며칠씩 알아보다가, 결국 제일 무난한 걸 고른 적이 있을 겁니다.',
    '남 돈 문제는 곧잘 짚어주면서, 정작 내 가계부는 미뤄둔 적이 있을 겁니다.',
    '"넌 돈 관리는 잘하겠다" 같은 말을 @{heard}.',
  ]),
];

final List<_Frag> _wealthOpening = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '돈이 머물고 싶어하는 얼굴입니다. 버는 감각과 지키는 뚝심이 같이 있어서, 사업·투자·운영 어느 쪽으로 가도 "결국 남기는 사람"이라는 평이 따라옵니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '기회를 잡는 눈이 또렷한 편입니다. 손실이 나도 바닥을 확인하는 감이 반 박자 빠르고, 크게 벌되 크게 잃지는 않는 균형이 같이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '버는 재주는 좋은데, 들어오는 속도만큼 나가는 속도도 빠른 편입니다. "담는 그릇"을 먼저 설계하는 게 숙제입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '한 방의 기질은 없어도 "잃지 않는 힘"이 단단합니다. 한 번에 크게 벌기보다 꾸준히 쌓는 누적형이라, 시간을 편으로 두는 자리에서 진가가 납니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '재물운이 극단 없이 평균대 위에 단정하게 놓인 편입니다. 생활 습관이 그대로 자산으로 쌓이는 정직한 구조입니다.',
    '조용히 불어나는 쪽입니다. 위험을 무릅쓰는 기개는 옅어도 잃지 않는 힘이 평균 이상이라, 기다림이 자산이 되는 종목에서 진가가 납니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '버는 감각은 평균인데 감정이 금전 결정에 자주 끼어드는 편입니다. 판단 자체는 틀리지 않는데 타이밍이 흔들리는, "머리는 맞고 마음이 먼저 움직이는" 패턴이 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '새로 돈을 만드는 손은 얇아도, 한 번 들어온 건 좀처럼 안 흘려보내는 편입니다. 근로·전문직·장기 근속 트랙에 가장 잘 맞습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '버는 결도 지키는 결도 두껍진 않은 평균형입니다. 대신 생활 습관이 자산에 제일 정직하게 반영되는 쪽이라, 자동 저축의 힘이 남보다 크게 작동합니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재물이 인생의 중심축은 아닌 편입니다. 억지로 이 축을 가운데 두면 오히려 소모가 크고, 재능·관계·경험을 중심에 두면 돈이 부산물로 따라오는 구조가 더 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재물운이 평균대 위에서 단단한 편입니다. 30대부터 들이는 돈의 총량이 말년 곡선의 기울기를 거의 그대로 정합니다.',
    '화려하게 한 번에 풀리기보다 꾸준한 축적에서 진가가 나는 쪽입니다. 쌓은 시간이 그대로 재산 규모로 반영됩니다.',
    '큰 한 방보다 성실한 반복으로 쌓는 "정직한 재물형"입니다. 근로·장기 저축·부동산처럼 정직한 트랙에서 평균 이상이 붙습니다.',
  ]),
];

final List<_Frag> _wealthShadow = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '다만 "잘 버는데 잘 안 쓰는" 게 굳으면 인색하게 비쳐, 자산 크기에 비해 노년에 누리는 풍요는 얇아지기 쉽습니다. 돈과 마음을 같이 써야 재물이 다음 세대까지 갑니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '다만 들어오는 문 옆에 나가는 문이 같이 열려 있습니다. 수입을 늘리기보다 새는 구멍을 먼저 막는 게 훨씬 큰 효과를 냅니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '다만 돈 판단 위에 감정이 먼저 덧씌워지기 쉽습니다. 분위기에 휩쓸린 지출이나 무리한 보증·투자에 발 들이기 쉬우니, 큰 결정은 꼭 24시간 묵히세요.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 호황기에 들뜨기 쉽습니다. 좋을 때마다 포지션을 키워 나쁠 때 낙차가 커지는 패턴이라, 호황기의 확장을 나쁜 시기 완충으로 바꾸는 게 관건입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 "갑작스러운 유혹"에 약한 구간이 주기적으로 옵니다. 그 구간에 미리 이름을 붙여 두면, 같은 유혹이 와도 결정이 달라집니다.',
    '다만 돈 결정은 혼자 있을 때보다 남과 있을 때 더 자주 망가집니다. 체면·관계 압박에서 내린 지출·보증이 제일 큰 누수이니, 큰 결정은 혼자 하룻밤 묵히고 정하세요.',
    '다만 들어올 때보다 빠져나갈 때의 구멍이 더 넓은 편입니다. 작게 새는 구멍 여럿이 한 해 순유입을 갉아먹으니, 고정비·구독·소액 지출을 주기적으로 점검하세요.',
    '다만 한 번 크게 잃으면 "나는 돈과 안 맞아"라며 설계를 통째로 포기하기 쉽습니다. 한 번의 실패로 기질을 재단하지 말고, 규칙만 고치고 구조는 지키세요.',
    '다만 "성공 직후의 확장"이 가장 위험합니다. 작은 성공 뒤에 포지션을 키우려는 충동이 커지는데, 제일 많이 잃는 순간은 제일 많이 번 직후입니다.',
  ]),
];

final List<_Frag> _wealthStrength = [
  _Frag.hard((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '콧대가 또렷하게 자리한 편이라, 30대 후반에서 40대 사이에 재물의 꼭짓점이 한 번 옵니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '광대가 힘있게 받쳐주는 편이라, 혼자 버는 근로보다 사람을 부려 돈을 키우는 운영·관리 쪽이 잘 맞습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '턱이 두툼한 편이라, 50대 이후에도 재물의 뿌리가 마르지 않고 오히려 깊어지는 노년 풍요형입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-11'), [
    '얼굴 가운데 기운이 열린 편이라, 중년에 운이 한꺼번에 풀리고 가장 큰 결실이 인생 중반에 모이는 리듬입니다.',
  ]),
  _Frag.hard((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입이 같이 살아 있어서, 수입과 지출을 둘 다 통제하는 편입니다. 새는 구멍도 스스로 막습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재물 곡선이 단기보다 장기에서 진가가 나는 편이라, 5년 단위로 돌아보는 습관이 붙을 때 가장 크게 늘어납니다.',
    '한 분야에 몰빵하기보다 여러 소득원이 같이 도는 게 자연스러운 기질이라, "N잡" 시대와 결이 잘 맞습니다.',
    '재물과 가정이 같이 움직이는 편이라, 혼자 버는 돈보다 가족·배우자와 같이 설계한 흐름에서 진짜 복리가 붙습니다. 재무 계획을 공유하는 습관이 총량을 정합니다.',
    '돈을 오래 머물게 하는 기운이 있는 편입니다. 소비 우선순위가 또렷해서 충동 지출이 남보다 적고, 남은 걸 굴릴 여유가 자연스럽게 생깁니다.',
    '남들 다 쓰는 데서 안 쓰고 정작 중요한 데 몰아 쓰는 감각이, 평범해 보여도 평생 자산 차이를 만듭니다.',
  ]),
];

// ═══════════════════════════════════════════════════════════════════════
// 인생 질문 서술 엔진 v3 — Beat-Fragment Grammar + 성별 분리 pool
//
// v2 대비 변경 (2026-04-18):
// - 연애·바람기·관능도 3 섹션은 남/여 완전 분리된 pool 을 사용. 치환 기반이
//   아닌 별도 2-세트.
// - '색기' 섹션명 → '관능도' (attribute.dart::labelKo 와 일치).
// - 섹션 목표 길이: 400~600자 (v2 의 600 평균에서 약간 tight 화).
//
// 섹션 = N beat 의 합. 각 beat 는 feature-activated fragment pool 에서
// face-hash seed 로 변형을 결정적으로 선택. @{slot} + {a|b|c} 문법으로
// 같은 조건 안에서도 슬롯 곱셈으로 수만 변종. 같은 얼굴 → 같은 결과.
// ═══════════════════════════════════════════════════════════════════════

String assembleLifeQuestions(FaceReadingReport r) {
  final f = _extractFeatures(r);
  final parts = <MapEntry<String, String>>[
    MapEntry('타고난 재능', _buildSection(f, _talentBeats, 10)),
    MapEntry('건강과 수명', _buildSection(f, _healthBeats, 70)),
    MapEntry('재물운', _buildSection(f, _wealthBeats, 20)),
    MapEntry('대인관계', _buildSection(f, _socialBeats, 30)),
    MapEntry('연애운', _buildSection(
        f, f.isMale ? _romanceBeatsMale : _romanceBeatsFemale, 40)),
  ];
  if (f.age.isOver30) {
    parts.add(MapEntry('관능도', _buildSection(
        f, f.isMale ? _sensualBeatsMale : _sensualBeatsFemale, 60)));
  }
  parts.add(MapEntry('종합 조언', _buildSection(f, _conclusionBeats, 80)));
  return parts.map((e) => '## ${e.key}\n${e.value}').join('\n\n');
}

/// 두 weight 곱. bool `&&` 의 soft 등가물.
_WeightFn _and2(_WeightFn p1, _WeightFn p2) => (f) => p1(f) * p2(f);

_Band _band(double s) {
  if (s >= 8.0) return _Band.high;
  if (s >= 6.5) return _Band.mid;
  return _Band.low;
}

_WeightFn _bandPair(Attribute a, _Band ba, Attribute b, _Band bb) =>
    (f) => _bandWeight(f.scoreOf(a), ba) * _bandWeight(f.scoreOf(b), bb);

double _bandWeight(double s, _Band b) {
  switch (b) {
    case _Band.high:
      return _hi(s);
    case _Band.mid:
      return _mi(s);
    case _Band.low:
      return _lo(s);
  }
}

String _buildSection(_Features f, List<_BeatPool> beats, int sectionSalt) {
  final buf = StringBuffer();
  for (var i = 0; i < beats.length; i++) {
    final text = _pickBeat(beats[i], f, sectionSalt + i);
    if (text.isEmpty) continue;
    if (buf.isNotEmpty) buf.write(i == beats.length - 1 ? '\n\n' : ' ');
    buf.write(text);
  }
  return buf.toString();
}

/// v3.1 (2026-04-18): entropy 다각화. 비슷한 얼굴이 같은 seed 로 수렴하던
/// 문제를 rule 조합·archetype·얼굴형·top contributor 등 이산 signal 을
/// 모두 섞어 분산.
int _computeSeed(FaceReadingReport r) {
  int h = 1469598103;
  // (a) metric values — 연속
  for (final m in r.metrics.values) {
    h = (h * 1099511628 + (m.rawValue * 1000000).round()) & 0x3FFFFFFF;
    h = (h * 31 + (m.zScore * 10000).round()) & 0x3FFFFFFF;
  }
  // (b) attribute scores — 정규화 후 정수 단위
  r.attributes.forEach((k, v) {
    h = (h * 17 + k.index) & 0x3FFFFFFF;
    h = (h * 13 + (v.normalizedScore * 1000).round()) & 0x3FFFFFFF;
  });
  // (c) node z — own + abs 둘 다
  r.nodeScores.forEach((k, v) {
    h = (h * 7 + (v.ownMeanZ * 10000).round()) & 0x3FFFFFFF;
    h = (h * 11 + (v.ownMeanAbsZ * 10000).round()) & 0x3FFFFFFF;
  });
  // (d) rule 발동 조합 — 이산 signal. 같은 band 에 있는 두 얼굴이라도
  //     발동 rule 이 다르면 seed 가 확연히 분기.
  final sortedRuleIds = r.rules.map((rr) => rr.id).toList()..sort();
  for (final id in sortedRuleIds) {
    h = (h * 41 + id.hashCode) & 0x3FFFFFFF;
  }
  // (e) archetype — top-2 조합 + special 이름.
  h = (h * 53 + r.archetype.primary.index) & 0x3FFFFFFF;
  h = (h * 59 + r.archetype.secondary.index) & 0x3FFFFFFF;
  if (r.archetype.specialArchetype != null) {
    h = (h * 67 + r.archetype.specialArchetype.hashCode) & 0x3FFFFFFF;
  }
  // (f) 얼굴형 + confidence — Stage 0 source 반영.
  h = (h * 71 + r.faceShape.index) & 0x3FFFFFFF;
  if (r.faceShapeConfidence != null) {
    h = (h * 73 + (r.faceShapeConfidence! * 100).round()) & 0x3FFFFFFF;
  }
  // (g) top contributor ID — 속성 별 가장 큰 기여 요인 (구체 rule/node).
  for (final ev in r.attributes.values) {
    if (ev.contributors.isEmpty) continue;
    h = (h * 79 + ev.contributors.first.id.hashCode) & 0x3FFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

_Features _extractFeatures(FaceReadingReport r) {
  final scores = <Attribute, double>{
    for (final e in r.attributes.entries) e.key: e.value.normalizedScore,
  };
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.first.key;
  final second = sorted.length > 1 ? sorted[1].key : top;
  final bottom = sorted.last.key;

  final bands = <Attribute, _Band>{
    for (final e in scores.entries) e.key: _band(e.value),
  };

  final firedRules = r.rules.map((rr) => rr.id).toSet();

  final nodeOwnZ = <String, double>{};
  final nodeAbsZ = <String, double>{};
  r.nodeScores.forEach((nid, ev) {
    nodeOwnZ[nid] = ev.ownMeanZ;
    nodeAbsZ[nid] = ev.ownMeanAbsZ;
  });

  // leaf 노드 중 ownMeanAbsZ 기준 top-2 추출 — 얼굴-특화 slot 용.
  const leafIds = {
    'forehead', 'glabella', 'eyebrow', 'eye', 'nose',
    'cheekbone', 'philtrum', 'mouth', 'chin',
  };
  final sortedLeaves = r.nodeScores.entries
      .where((e) => leafIds.contains(e.key))
      .toList()
    ..sort((a, b) => b.value.ownMeanAbsZ.compareTo(a.value.ownMeanAbsZ));
  final strongest = sortedLeaves.isNotEmpty ? sortedLeaves.first.key : 'face';
  final second2nd =
      sortedLeaves.length > 1 ? sortedLeaves[1].key : strongest;

  // 음양 쏠림 계산 — 전체 metric z-map 에서 양/음 축 가중합.
  final zMap = <String, double>{
    for (final m in r.metrics.values) m.id: m.zScore,
  };
  if (r.lateralMetrics != null) {
    for (final m in r.lateralMetrics!.values) {
      zMap[m.id] = m.zScore;
    }
  }
  final yinYang = computeYinYang(zMap, r.gender);

  return _Features(
    top: top,
    second: second,
    bottom: bottom,
    bands: bands,
    scores: scores,
    gender: r.gender,
    age: r.ageGroup,
    firedRules: firedRules,
    nodeOwnZ: nodeOwnZ,
    nodeAbsZ: nodeAbsZ,
    metricZ: zMap,
    strongestNode: strongest,
    strongestNodeKo: _nodeKoLabels[strongest] ?? strongest,
    secondStrongestNodeKo: _nodeKoLabels[second2nd] ?? second2nd,
    dominantPalace: _nodeDominantPalaceKo[strongest] ?? '명궁',
    specialArchetype: r.archetype.specialArchetype,
    primaryArchetype: r.archetype.primaryLabel,
    secondaryArchetype: r.archetype.secondaryLabel,
    yinYang: yinYang,
    seed: _computeSeed(r),
    oneLiner: _buildOneLiner(top, second),
  );
}

String _genderedKey(String key, _Features f) {
  // _m / _f / _g 접미 pool 자동 선택
  if (_slotPools.containsKey('${key}_g')) {
    return f.isMale ? '${key}_m' : '${key}_f';
  }
  return key;
}

// ─── Soft band weights ──────────────────────────────────────────────────
// 5.0~10.0 정규화 점수에 대해 high/mid/low band 소속도를 연속 [0, 1] 로
// 반환. hard cutoff (8.0 / 6.5) 근처의 plateau/cliff 를 제거하기 위함.
// _hi 는 [6.5, 8.0] 구간에서 선형 상승, _lo 는 [5.0, 6.5] 구간에서 하강,
// _mi 는 나머지. boundary 에서 양측 fragment 가 섞여 뽑히도록 설계.

double _hi(double s) {
  if (s >= 8.0) return 1.0;
  if (s <= 6.5) return 0.0;
  return (s - 6.5) / 1.5;
}

// ═══════════════════════════════════════════════════════════════════════
// 섹션별 beat pool — 각 beat 는 feature-activated fragment 리스트.
// 마지막 fragment 는 항상 fallback (applies = (_) => true).
// ═══════════════════════════════════════════════════════════════════════

// Helper predicates — 모두 soft weight 반환. band cutoff 경계의
// plateau/cliff 를 연속 ramp 로 풀어낸다.
_WeightFn _highOf(Attribute a) => (f) => _hi(f.scoreOf(a));

_WeightFn _highPair(Attribute a, Attribute b) =>
    (f) => _hi(f.scoreOf(a)) * _hi(f.scoreOf(b));

bool _isLate(_Features f) => f.age.isOver50;

bool _isMid(_Features f) => f.age.isOver30 && !f.age.isOver50;

// 연령대 hard predicate — 한국 관상학 연령 분포 grounded.
//   young (10s~20s):  20대 들머리 — 잠재·탐색·기반 형성기
//   mid (30s~40s):    중년 절정기 — 운이 크게 열리고 정점에 닿는 실행기
//   late (50s+):      후반기 — 회수·전수·노년 풍요를 누리는 시기
bool _isYoung(_Features f) => !f.age.isOver30;

double _lo(double s) {
  if (s <= 5.0) return 1.0;
  if (s >= 6.5) return 0.0;
  return (6.5 - s) / 1.5;
}

_WeightFn _lowOf(Attribute a) => (f) => _lo(f.scoreOf(a));

_WeightFn _lowPair(Attribute a, Attribute b) =>
    (f) => _lo(f.scoreOf(a)) * _lo(f.scoreOf(b));

_WeightFn _metHi(String id) => (f) => _softHiZ(f.mz(id));

_WeightFn _metLo(String id) => (f) => _softLoZ(f.mz(id));

_WeightFn _metMid(String id) => (f) => _softMidZ(f.mz(id));

double _mi(double s) {
  final rest = 1.0 - _hi(s) - _lo(s);
  return rest < 0 ? 0.0 : rest;
}

_WeightFn _midOf(Attribute a) => (f) => _mi(f.scoreOf(a));

_WeightFn _notLowOf(Attribute a) => (f) => 1.0 - _lo(f.scoreOf(a));

/// Weighted sampling. 각 fragment 의 weight(∈[0,1]) 를 누적 분포로 보고
/// seed 로 결정 지점을 찍는다. 모든 weight=0 이면 빈 문자열 (pool 미스).
/// deterministic: 같은 seed+pool 이면 항상 같은 fragment.
String _pickBeat(_BeatPool pool, _Features f, int beatSalt) {
  if (pool.isEmpty) return '';
  final weights = List<double>.filled(pool.length, 0.0);
  var total = 0.0;
  for (var i = 0; i < pool.length; i++) {
    final w = pool[i].weight(f);
    final clipped = w.isNaN ? 0.0 : w.clamp(0.0, 1.0).toDouble();
    weights[i] = clipped;
    total += clipped;
  }
  if (total <= 0) return '';
  final beatSeed = (f.seed ^ (beatSalt * 2654435761)) & 0x7FFFFFFF;
  final target = (beatSeed / 0x7FFFFFFF) * total;
  var cumulative = 0.0;
  var idx = pool.length - 1;
  for (var i = 0; i < pool.length; i++) {
    cumulative += weights[i];
    if (target <= cumulative) {
      idx = i;
      break;
    }
  }
  final frag = pool[idx];
  final variantSeed = (beatSeed ^ 0x1DEA1BEE) & 0x7FFFFFFF;
  final chosen = frag.variants[variantSeed % frag.variants.length];
  return _resolveText(chosen, f, beatSeed);
}

String _resolveText(String text, _Features f, int seed) {
  var t = text;
  // Step 0: runtime placeholders (archetype labels + face-specific metaphors)
  t = t
      .replaceAll('@__PRIMARY_ARCHETYPE__', f.primaryArchetype)
      .replaceAll('@__SECONDARY_ARCHETYPE__', f.secondaryArchetype)
      .replaceAll('@__SPECIAL_ARCHETYPE__', f.specialArchetype ?? '특별 관상')
      .replaceAll('@__STRONGEST_NODE__', f.strongestNodeKo)
      .replaceAll('@__SECOND_NODE__', f.secondStrongestNodeKo)
      .replaceAll('@__DOMINANT_PALACE__', f.dominantPalace)
      .replaceAll('@__ONELINER__', f.oneLiner);
  // Step 1: @{slot}
  t = t.replaceAllMapped(RegExp(r'@\{(\w+)\}'), (m) {
    final key = m.group(1)!;
    final pool = _slotPools[_genderedKey(key, f)];
    if (pool == null || pool.isEmpty) return '';
    return pool[(seed + key.hashCode).abs() % pool.length];
  });
  // Step 2: {a|b|c}
  t = t.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
    final body = m.group(1)!;
    if (!body.contains('|')) return '{$body}';
    final opts = body.split('|');
    return opts[(seed + body.hashCode).abs() % opts.length].trim();
  });
  return t;
}

/// z-score 용 ramp. |z| 기준 0.5 에서 정점 가까이 가고 0 에서 0.
/// metric / node 단위 예전 hard `>= 0.5` 임계에 대응.
double _softHiZ(double z) {
  if (z >= 1.0) return 1.0;
  if (z <= 0.0) return 0.0;
  return z;
}
double _softLoZ(double z) => _softHiZ(-z);
double _softMidZ(double z) {
  final a = z.abs();
  if (a <= 0.2) return 1.0;
  if (a >= 1.0) return 0.0;
  return (1.0 - a) / 0.8;
}

bool _yangLean(_Features f) =>
    f.yinYang.tone == YinYangTone.strongYang ||
    f.yinYang.tone == YinYangTone.leaningYang;

// 음양 쏠림 predicate
bool _yangStrong(_Features f) => f.yinYang.tone == YinYangTone.strongYang;

bool _yinLean(_Features f) =>
    f.yinYang.tone == YinYangTone.strongYin ||
    f.yinYang.tone == YinYangTone.leaningYin;

bool _yinStrong(_Features f) => f.yinYang.tone == YinYangTone.strongYin;

bool _yyHarmony(_Features f) => f.yinYang.tone == YinYangTone.harmony;

typedef _BeatPool = List<_Frag>;

// ─── Fragment + Picker ──────────────────────────────────────────────────

typedef _WeightFn = double Function(_Features);

// ─── Features ────────────────────────────────────────────────────────────

enum _Band { high, mid, low }

class _Features {
  final Attribute top;
  final Attribute second;
  final Attribute bottom;
  final Map<Attribute, _Band> bands;
  final Map<Attribute, double> scores;
  final Gender gender;
  final AgeGroup age;
  final Set<String> firedRules;
  final Map<String, double> nodeOwnZ;
  final Map<String, double> nodeAbsZ;
  final Map<String, double> metricZ;
  final String strongestNode;
  final String strongestNodeKo;
  final String secondStrongestNodeKo;
  final String dominantPalace;
  final String? specialArchetype;
  final String primaryArchetype;
  final String secondaryArchetype;
  final YinYangBalance yinYang;
  final int seed;
  final String oneLiner;

  _Features({
    required this.top,
    required this.second,
    required this.bottom,
    required this.bands,
    required this.scores,
    required this.gender,
    required this.age,
    required this.firedRules,
    required this.nodeOwnZ,
    required this.nodeAbsZ,
    required this.metricZ,
    required this.strongestNode,
    required this.strongestNodeKo,
    required this.secondStrongestNodeKo,
    required this.dominantPalace,
    required this.specialArchetype,
    required this.primaryArchetype,
    required this.secondaryArchetype,
    required this.yinYang,
    required this.seed,
    required this.oneLiner,
  });

  bool get isMale => gender == Gender.male;
  _Band bandOf(Attribute a) => bands[a] ?? _Band.mid;
  bool fired(String id) => firedRules.contains(id);
  double mz(String id) => metricZ[id] ?? 0.0;
  double nodeAZ(String id) => nodeAbsZ[id] ?? 0.0;
  double nodeZ(String id) => nodeOwnZ[id] ?? 0.0;
  double scoreOf(Attribute a) => scores[a] ?? 7.0;
}

class _Frag {
  /// 프래그먼트가 얼마만큼 "이 얼굴에 어울리는가" — [0.0, 1.0].
  /// 0 은 완전 배제, 1 은 완전 합치. 중간값은 weighted sampling 으로
  /// band 경계 부근에서 plateau/cliff 를 풀어준다.
  final _WeightFn weight;
  final List<String> variants;
  _Frag(this.weight, this.variants);

  /// boolean predicate 래퍼 — 나이·아키타입·rule-fired 처럼 본질적으로
  /// 이산인 조건은 true → 1.0, false → 0.0 으로 고정.
  _Frag.hard(bool Function(_Features) applies, this.variants)
      : weight = ((f) => applies(f) ? 1.0 : 0.0);
}

