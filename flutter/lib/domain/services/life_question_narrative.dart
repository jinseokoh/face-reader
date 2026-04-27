import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/yin_yang.dart';

const _nodeDominantPalaceKo = <String, String>{
  'forehead': '관록궁',
  'glabella': '명궁',
  'eyebrow': '형제궁',
  'eye': '전택궁',
  'nose': '재백궁',
  'cheekbone': '권력의 자리',
  'philtrum': '남녀궁',
  'mouth': '출납관',
  'chin': '지각(地閣)',
  'upper': '천정(天庭)',
  'middle': '중정(中停)',
  'lower': '지각(地閣)',
  'face': '명궁·삼정',
};

// 노드 한글명 · 십이궁 매핑 — 얼굴-특화 slot 해결용.
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
  'upper': '상정',
  'middle': '중정',
  'lower': '하정',
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
    '대장부(大丈夫)의', '장부의', '지장(智將)의', '군자의', '호방한', '당당한',
    '의젓한', '태산 같은', '사내다운',
  ],
  'noble_f': [
    '여중군자(女中君子)의', '품격 있는', '단아한', '기품 있는', '우아한', '고상한',
    '정갈한', '곱게 정돈된', '반듯한',
  ],
  'person_g': [],
  'person_m': ['장부', '대장부', '군자', '사내', '호걸', '태산 같은 이'],
  'person_f': ['여인', '규수', '여중군자', '안주인', '숙녀', '현숙한 이'],
  'rare': [
    '드물게도', '남달리', '유난히', '보기 드물게', '특별히', '귀하게',
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
  'structure': ['구조', '골상', '관상', '기질', '상(相)', '결', '면모'],
  'palace_career': ['관록궁(官祿宮)', '\'관록궁\'', '관록의 자리'],
  'palace_wealth': ['재백궁(財帛宮)', '\'재백궁\'', '재물의 궁', '재록의 자리'],
  'palace_destiny': ['명궁(命宮)', '\'명궁\'', '인당(印堂)', '\'인당\''],
  'palace_social': ['천이궁(遷移宮)', '\'천이궁\'', '인연의 자리'],
  'palace_servant': ['노복궁(奴僕宮)', '\'노복궁\'', '부하의 자리'],
  'palace_mate': ['처첩궁(妻妾宮)', '\'처첩궁\''],
  'palace_sex': ['남녀궁(男女宮)', '\'남녀궁\''],
  'palace_home': ['전택궁(田宅宮)', '\'전택궁\''],
  'palace_health': ['질액궁(疾厄宮)', '\'질액궁\'', '산근(山根)'],
  'palace_bro': ['형제궁(兄弟宮)', '\'형제궁\''],
  'peach': ['도화(桃花)', '\'도화\'', '복숭아꽃의 기운', '도화기(桃花氣)'],
  'energy_yang': ['양기(陽氣)', '양의 기운', '밝은 기세'],
  'energy_yin': ['음기(陰氣)', '음의 결', '어두운 윤기'],
  'zone_up': ['상정(上停)', '\'상정\'', '이마의 기운'],
  'zone_mid': ['중정(中停)', '\'중정\'', '코·광대의 자리'],
  'zone_down': ['하정(下停)', '\'하정\'', '턱의 자리'],
  'mount_n': ['항산(恒山)', '지각(地閣)', '턱의 중심'],
  'mount_s': ['형산(衡山)', '천정(天庭)', '이마 중앙'],
  'mount_c': ['숭산(嵩山)', '준두(準頭)', '코의 중심'],
  'mount_e': ['태산(泰山)', '좌 광대(左顴)'],
  'mount_w': ['화산(華山)', '우 광대(右顴)'],
  'organ_brow': ['보수관(保壽官)', '눈썹의 자리', '미관(眉官)'],
  'organ_eye': ['감찰관(監察官)', '눈의 자리'],
  'organ_nose': ['심변관(審辨官)', '코의 중심'],
  'organ_mouth': ['출납관(出納官)', '입의 자리'],
  'fortune_word': [
    '복록(福祿)', '관록(官祿)', '재록(財祿)', '복덕(福德)', '정록(正祿)',
    '덕록(德祿)', '수록(壽祿)',
  ],
  'result_shine': [
    '돋보입니다', '빛납니다', '두드러집니다', '또렷합니다', '드러납니다',
    '선명히 읽힙니다', '확연합니다', '인상 깊게 남습니다',
  ],
  'result_carry': [
    '실려 있습니다', '담겨 있습니다', '배어 있습니다', '서려 있습니다',
    '녹아 있습니다', '깃들어 있습니다', '자리합니다',
  ],
  'heart': ['마음', '심지(心志)', '속결', '정(情)', '흉중(胸中)', '속마음', '심저(心底)'],
  'talent_word': [
    '재능', '기질', '천품(天稟)', '타고난 결', '본래의 그릇',
    '자질', '타고난 재주', '고유의 격',
  ],
  'fate_word': ['인연', '운(運)', '복(福)', '명(命)', '연(緣)', '조화(造化)'],
  'path_word': ['길', '행로(行路)', '걸음', '도정(道程)', '여정', '경로', '방도'],
};

final List<_Frag> _concludeAdvice = [
  _Frag.hard((f) => true, [
    '마지막으로, 관상은 예언이 아니라 지도입니다. 타고난 골격과 기색이 길 위의 지형을 보여주지만, 그 위에서 어떤 속도로 어떤 방향으로 걷느냐는 오늘의 당신이 결정합니다. 같은 관상이라도 누군가는 타고난 장점을 20%밖에 열지 못하고 지나가고, 다른 누군가는 타고난 약점까지 무기로 바꾸며 80%를 열어냅니다. 분석이 제시한 강점은 더 @{deep} 밀어붙이고, 그림자는 먼저 알아차리는 쪽에 서십시오. 관상이 약속한 가장 좋은 풍경은 \'알고 선택한 사람\'에게만 열립니다.',
  ]),
];

// ═══ 8. 종합 조언 ═══

// archetype 레이블은 _resolveText Step 0 에서 runtime features 로 치환된다.
final List<_Frag> _concludeOpening = [
  _Frag.hard(_yangStrong, [
    "당신의 얼굴은 양기(陽氣)가 짙게 서린 상입니다. '@__PRIMARY_ARCHETYPE__' 의 골격 위에 '@__SECONDARY_ARCHETYPE__' 의 결이 얹혀 있지만, 그 모든 것을 관통하는 축은 강건·진취·돌파의 양기이며, 인생의 결정적 국면에서 머뭇거리지 않고 선을 넘어서는 기질이 당신의 궤적을 만듭니다.",
  ]),
  _Frag.hard(_yinStrong, [
    "당신의 얼굴은 음기(陰氣)가 @{deep} 깃든 상입니다. '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__' 의 결이 흐르지만, 전체를 감싸는 기운은 수렴·포용·유연의 음기이며, 서두르지 않고 시간을 동맹으로 삼는 결이 당신의 평생 자산입니다.",
  ]),
  _Frag.hard(_yyHarmony, [
    "당신의 얼굴은 음양(陰陽)이 @{rare} 고르게 맞물린 조화의 상입니다. '@__PRIMARY_ARCHETYPE__' 과 '@__SECONDARY_ARCHETYPE__' 이 겹친 위에, 강함과 부드러움을 자유롭게 교체할 수 있는 중용의 결이 자리하여, 어떤 환경에서도 자기 자리를 빨리 찾는 적응력이 최대 강점이 됩니다.",
  ]),
  _Frag.hard((f) => f.specialArchetype != null, [
    "지금까지 겹쳐본 여러 영역을 한 장으로 보면, 당신의 관상은 '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 겹쳐 흐르는 @{structure}입니다. 특히 얼굴에 '@__SPECIAL_ARCHETYPE__'이 함께 서려 있어, 평균적 해석의 범위를 넘어서는 결정적 국면을 인생 중·후반에 한 번 이상 통과하게 될 가능성이 높습니다.",
  ]),
  _Frag.hard((f) => true, [
    "지금까지 겹쳐본 여러 영역을 한 장으로 보면, 당신의 관상은 '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐르는 @{structure}입니다. 겉으로 먼저 드러나는 것은 '@__PRIMARY_ARCHETYPE__'이지만, 인생 중반을 실질적으로 움직이는 동력은 오히려 '@__SECONDARY_ARCHETYPE__' 쪽에 더 많이 담겨 있습니다.",
    "당신의 얼굴에는 '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 몸에 겹쳐 있어, 단일 방향으로 힘을 쏟는 전형보다 상황에 따라 두 얼굴을 번갈아 쓸 수 있는 @{rare} 결을 지녔습니다.",
  ]),
];

// 연령대별 배타 predicate — 가장 구체적 band 가 단독으로 매칭되도록.
final List<_Frag> _concludeStage = [
  _Frag.hard((f) => f.age.isOver50, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'덜어내는 기술\'입니다. 쌓아 올리는 시기는 이미 상당 부분 지나왔고, 지금부터는 남길 것과 흘려보낼 것을 가르는 판단이 말년의 빛깔을 결정합니다. 오랜 세월이 빚어낸 깊이가 관상을 @{intense} 풍성하게 만드는 시기이며, 타고난 골격의 좋은 기운은 오히려 지금 @{intense} 드러납니다.',
  ]),
  _Frag.hard((f) => f.age.isOver30 && !f.age.isOver50, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'축적의 설계\'입니다. 초기의 재능이 드러난 시기이고, 지금부터 10년은 그 재능을 어떤 시스템 위에 올려놓느냐가 평생 곡선의 기울기를 결정합니다. \'중년 발복\'의 기반이 만들어지는 구간이기에, 작은 선택들이 복리처럼 쌓여 5~7년 뒤 전혀 다른 풍경을 만들어냅니다.',
  ]),
  _Frag.hard((f) => f.age.isOver20 && !f.age.isOver30, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'결을 세우는 일\'입니다. 재능의 윤곽은 드러났지만 아직 주변에 맞추어 깎이기 쉬운 시기이며, 이때 결을 또렷이 세우지 못하면 이후 10년의 선택이 계속 흔들립니다. 지금 필요한 것은 답을 서둘러 찾는 일보다 당신 자신의 질문을 또렷이 세우는 일입니다.',
  ]),
  _Frag.hard((f) => !f.age.isOver20, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'가능성의 확장\'입니다. 아직 어떤 방향으로도 굳어 있지 않은 시기이기에, 경험의 폭이 그대로 나중의 얼굴에 새겨집니다. 지금의 다양성이 이후 관상의 깊이를 결정합니다.',
  ]),
];

final List<_BeatPool> _conclusionBeats = [
  _concludeOpening,
  _concludeStage,
  _concludeAdvice,
];

final List<_Frag> _healthAdvice = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '타고난 기본기 위에 감정의 온도가 얹힌 결은 "밀도 높은 수명"의 구조입니다. 과신이 가장 큰 위험이니 자각 증상이 없는 시점에 미리 점검하고, 감정의 출렁임이 몸으로 번지는 통로—수면·심박·소화—를 매달 기록해 두십시오. 관상이 약속한 상한은 이 둘의 교차점에서만 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '체질의 기본기는 단단한데 감정의 파고가 크지 않은, 가장 "관리가 쉬운" 결입니다. 걱정보다 지루함이 적인 유형이니, 3년마다 한 번씩 의무적 건강 검진 루틴만 박아 두면 관상이 약속한 장수의 상한을 정직하게 따라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '몸의 기본기는 좋고 감정의 출렁임도 낮은 "둔감한 강체"의 결입니다. 장점은 꾸준함, 단점은 몸이 보내는 약한 신호를 놓치기 쉽다는 점—정기 검진 주기를 1.5년으로 짧게 잡는 것만으로 리스크가 반감됩니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '체질은 평균권, 감정의 진폭이 큰 결입니다. 수명을 가장 많이 갉아먹는 요인이 과로가 아니라 "해소되지 않은 감정 누적"인 유형—일기·상담·운동 중 하나를 감정 배수로로 못 박아 두는 것이 장기 건강의 핵심입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 중용의 결입니다. 30대부터 들이는 건강 자산의 총량이 그대로 말년 곡선의 기울기를 결정하는 정직한 구조—수면·식사·운동 중 가장 약한 한 가지만 먼저 표준화하십시오.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '"기계처럼 도는" 결입니다. 감정의 폭이 크지 않아 컨디션이 안정적인 대신, 몸이 서서히 나빠지는 것을 느끼지 못하는 유형—숫자로 측정하는 습관(체중·혈압·수면 시간)이 가장 든든한 방어선입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '체질은 예민하고 감정의 진폭이 큰, 관상이 가장 꼼꼼히 경계하는 결입니다. "남이 버티는 강도"를 기준으로 삼지 마십시오. 감정 기복이 몸으로 번지기 전에 차단하는 루틴—명상·산책·정기 상담—이 당신의 수명을 연장합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '체질이 예민한 만큼 몸의 신호를 남보다 일찍 받는 이점이 있는 결입니다. 그 신호를 "불안"이 아니라 "정보"로 번역하는 훈련이 핵심—자각이 일찍 오는 사람은 둔감한 사람보다 @{deep} 오래 건강을 유지하는 역설적 구조입니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '체질도 예민하고 감정의 기반도 얇은 결입니다. 이는 약하다가 아니라 "정밀하다"에 가깝고, 정밀한 기계는 거친 환경을 피할 수만 있으면 오히려 오래 갑니다. 과격한 운동보다 규칙적 수면과 예측 가능한 일상이 당신의 건강 자산입니다.',
  ]),
  _Frag.hard((f) => true, [
    '건강을 지키는 길은 셋입니다. 첫째, 수면·식사·운동 중 가장 약한 한 가지만 먼저 표준화할 것. 둘째, 몸의 "이상 없음" 신호를 맹신하지 말고 자각 증상이 없는 시점에 정기 점검을 박아 둘 것. 셋째, 감정의 피로가 몸의 피로로 옮겨 가는 통로를 스스로 알아두는 것—이 셋이 맞물릴 때 관상이 약속한 수명의 상한이 열립니다.',
    '당신의 몸은 "한 해 단위"가 아니라 "십 년 단위"로 계산되는 @{structure}입니다. 30대의 습관이 60대의 @{mount_n}에 그대로 복사되는 구조라, 지금 반복하는 한 가지를 10년 뒤의 거울로 삼으십시오. @{palace_health}이 지키는 건 순간의 컨디션이 아니라 누적된 선택의 총합입니다.',
    '수명의 축을 관상학은 "신(神)·기(氣)·정(精)" 셋으로 나눕니다. 당신의 얼굴에서 가장 먼저 흐려지는 축을 알아채는 사람은 이 셋을 따로따로 충전하는 방법을 가지고, 한 축으로만 충전하려는 사람은 결국 다른 둘이 말라갑니다. 잠은 신을, 호흡은 기를, 식사는 정을 보충합니다.',
    '관상학이 건강 상담에서 가장 자주 강조하는 원칙은 단순합니다—"자기 몸을 남의 잣대로 재지 말 것". 남이 버티는 강도, 남이 회복하는 속도, 남이 먹는 양 모두 당신의 @{structure}와 다른 설계입니다. 자기 몸의 리듬을 찾는 데 1년을 쓰는 사람은 남은 30년을 번갈아 살립니다.',
    '@__STRONGEST_NODE__의 결이 당신 건강 곡선의 중심축입니다. 이 부위가 지치면 몸 전체가 연쇄적으로 흔들리고, 이 부위가 살아나면 다른 약점도 덩달아 회복되는 @{rare} 연결 구조—가장 아끼는 부위를 가장 먼저 관리에 넣으십시오.',
  ]),
];

final List<_BeatPool> _healthBeats = [
  _healthOpening,
  _healthStrength,
  _healthShadow,
  _healthAdvice,
];

// ═══ 7. 건강과 수명 ═══

final List<_Frag> _healthOpening = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '건강의 뿌리가 @{deep} 박힌 위에, 감정의 풍부함이 몸을 깨어 있게 만드는 결입니다. @{palace_health}이 막힘 없이 열리고 @{mount_n}이 @{strong_adj} 받쳐주는 상—큰 병에 쉽게 흔들리지 않는 기본기와 몸의 신호를 @{intense} 잡아내는 예민함이 한 얼굴에 공존하는 @{rare} 구조입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.mid), [
    '체질의 바닥이 두텁고 감정의 파고도 크지 않은, 가장 "흔들림이 적은" 결입니다. @{palace_health}의 깊이와 턱의 묵직함이 함께 살아 있어 큰 파고 앞에서 중심이 무너지지 않는 탄성이 골상에 박혀 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.high, Attribute.emotionality, _Band.low), [
    '기본기가 @{strong_adj} 받치고 있는 반면 감정의 진폭은 @{faint} 옅은 결입니다. "둔감한 강체"의 구조—잔병에 덜 시달리지만 몸이 보내는 약한 신호를 놓치기 쉬운 유형입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.high), [
    '체질은 평균권인데 감정의 진폭이 큰 결입니다. 몸의 컨디션이 감정의 온도를 직접 따라 움직이는 구조—해소되지 않은 감정이 그대로 특정 장기로 흘러가는 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 평균의 결입니다. @{palace_health}과 턱의 균형이 안정적으로 자리한 상—잘 관리하면 평균 이상, 방치하면 평균 이하로 떨어지는 양면성의 정직한 @{structure}입니다.',
    '치명적 기울어짐은 없되 생활 습관의 축적이 고스란히 몸에 누적되는 결입니다. 30대부터 들이는 건강 자산의 총량이 말년 곡선의 기울기를 그대로 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.mid, Attribute.emotionality, _Band.low), [
    '몸도 감정도 큰 기복 없이 도는 "기계형" 결입니다. 컨디션이 안정적인 대신 서서히 나빠지는 신호를 잡아내기 어려운 유형—숫자로 측정하는 습관이 숨은 방어선입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.high), [
    '체질도 예민하고 감정의 폭도 큰, 관상이 가장 꼼꼼히 경계하는 결입니다. @{palace_health}이 @{subtle} 약하거나 턱의 받침이 가볍게 드러나는 상—"약하다"가 아니라 "정밀하다"에 가까운 구조입니다.',
  ]),
  _Frag(_bandPair(Attribute.stability, _Band.low, Attribute.emotionality, _Band.mid), [
    '체질의 저점이 남보다 낮은 구간을 자주 지나가는 결입니다. 대신 몸이 신호를 일찍 보내주는 유형이라, 그 신호를 잘 읽는 사람은 둔감한 사람보다 @{deep} 오래 건강을 유지하는 역설적 구조를 가집니다.',
  ]),
  _Frag(_lowPair(Attribute.stability, Attribute.emotionality), [
    '체질도 얇고 감정의 기반도 엷은 결입니다. 과격한 환경을 피할 수만 있으면 정밀한 기계처럼 오래 가는 타입—규칙적 수면과 예측 가능한 일상이 당신의 건강 자산입니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 건강 곡선은 평균의 결을 따르되, 특정 구간에서 한 번의 큰 점검이 전체를 좌우하는 @{structure}입니다. 약한 고리를 일찍 발견하는 사람만이 관상이 약속한 상한에 닿습니다.',
    '얼굴 전체가 뚜렷한 편중 없이 삼정(三停)에 고루 기운을 나누어 싣고 있는 결입니다. 대병(大病)보다 잔잔한 누적이 두드러지는 유형—매일의 작은 루틴 하나가 20년 뒤의 체감 연령을 그대로 결정합니다.',
    '@{palace_health}의 자리가 @{subtle} 차분히 앉은 상. 관상학이 "중용의 몸"이라 부르는 결로, 급격한 상승도 급격한 하락도 없이 꾸준함으로 거리를 버는 @{structure}입니다. 이 유형의 숨은 이점은 "회복의 평균값"이 남보다 반걸음 안정적이라는 것.',
    '몸의 기운이 한쪽으로 쏠리지 않고 여러 축으로 분산된 결은 관상학에서 "균형의 체(體)"라 부릅니다. 한 가지 결정적 장점이 없는 대신 치명적 약점도 늦게 드러나는 유형—10년, 20년 단위의 비교에서 진가가 나오는 구조입니다.',
    '당신의 @__STRONGEST_NODE__이 몸의 컨디션을 읽는 첫 신호기입니다. 이 부위의 색·윤기·긴장도가 평소와 다르면 가장 먼저 반응해야 하는 관상학적 바로미터이며, 이 신호에 빨리 반응하는 습관이 당신의 수명을 좌우합니다.',
  ]),
];

final List<_Frag> _healthShadow = [
  _Frag(_highPair(Attribute.stability, Attribute.emotionality), [
    '다만 "건강에 자신 있다"는 감각 자체가 이 결의 가장 큰 위험입니다. 감정의 풍부함이 과열될 때 몸의 경고 신호를 낙관으로 덮기 쉽고, 어느 시점에 한꺼번에 무너지는 패턴이 따라붙기 쉽습니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 당신의 @{structure}는 과로와 감정 소모에 @{intense} 취약합니다. "남이 버티는 강도를 내가 동일하게 버티지 않는다"—이 한 줄이 당신의 수명을 좌우합니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 "건강에 자신 있다"는 그 자신감이 가장 큰 위험 요인입니다. 타고난 기본기가 좋을수록 경고 신호를 묵살하고 밀어붙이다 한 번에 무너지는 패턴이 반복되기 쉬운 구조입니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 감정의 진폭이 크면 몸도 그 진폭을 따라 움직입니다. 기쁜 날과 무너지는 날의 컨디션 격차가 또래보다 넓은 결—감정의 배수로 설계가 건강 관리의 숨은 중심축입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 당신의 수명은 육체의 과로보다 해소되지 않은 감정의 누적으로 더 많이 갉아먹히는 유형입니다. 감정의 배수로 설계가 건강 관리의 진짜 중심축입니다.',
    '다만 당신의 몸은 "작은 이상은 무시해도 괜찮다"는 신호를 보내기 쉽습니다. 관상학에서 가장 경계하는 패턴—하나의 잔증상이 세 달쯤 이어질 때 그것을 "버틸 수 있음"으로 해석하면, 나중에 한꺼번에 청구서가 돌아오는 구조입니다.',
    '다만 당신의 결은 중년 이후 "누적이 터지는 시점"이 한 번 존재합니다. 20~30대의 과신, 40대의 소홀함이 모여 50대 어느 해에 일시 정체를 만드는 @{structure}—그 시점을 미리 알고 설계하는 사람과 모르고 맞는 사람의 회복 속도는 전혀 다릅니다.',
    '다만 몸이 보내는 신호와 뇌가 해석하는 결과 사이의 간극이 큰 결입니다. "피곤하지 않다"는 자각과 "실제 회복력이 떨어졌다"는 데이터 사이의 틈—이 틈을 메우는 유일한 방법은 정기 검진의 숫자를 자각 증상보다 우선하는 것입니다.',
    '다만 당신에게 가장 큰 위험은 "비교의 피로"입니다. @{palace_health}은 남의 리듬에 맞춰 굴릴수록 빨리 닳는 자리—자기 속도의 기준선을 스스로 정하지 않으면 타고난 기본기가 10년도 못 가 깎여 나가는 구조입니다.',
  ]),
];

final List<_Frag> _healthStrength = [
  _Frag.hard((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '@{mount_c}의 구조가 @{intense} 드러나는 상은 관상학에서 40대 전후의 "중년 건강 관문"을 강조하는 신호입니다. 호흡기·순환기 쪽을 미리 점검해 두는 것이 결정적 도움이 됩니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09'), [
    '상정(上停)의 기운이 @{intense} 강한 상은 머리를 많이 쓰는 기질을 의미합니다. 수면의 질이 건강의 어떤 요소보다 먼저 흔들리기 쉬운 유형입니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '@{mount_n}이 듬직한 구조는 관상학에서 "말년 강건"의 상징으로, 50대 이후의 체력이 동년배보다 떨어지지 않는 기질을 뒷받침합니다.',
  ]),
  _Frag.hard((f) => f.fired('P-05') || f.nodeZ('glabella') >= 0.5, [
    '@{palace_destiny}이 맑게 자리한 상은 정신적 피로의 회복력이 강한 결입니다. 감정이 흔들려도 하룻밤 자면 기본선으로 되돌아오는 유형의 신호입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04'), [
    '하정(下停)이 후중한 상은 위장·신장 쪽의 근기가 좋은 결로 읽힙니다. 식습관의 축적이 가장 정직하게 수명으로 환원되는 타입입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '감정의 해상도가 높은 결은 스트레스의 뿌리를 먼저 인식하는 이점을 만듭니다. 불안으로 방치만 하지 않으면 오히려 건강 관리의 조기 경보기가 되는 구조입니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 체질은 "평균의 결"을 갖추되 한 가지 약한 고리가 있으며, 그 고리를 일찍 발견한 사람만이 관상이 약속한 상한에 도달합니다.',
    '관상학에서 "기혈(氣血)이 고르게 흐르는 상"이라 부르는 결입니다. 큰 파고가 없는 대신 섬세한 유지가 필요한 유형이며, @__STRONGEST_NODE__의 결이 건강 전반의 리드미컬한 지표가 됩니다.',
    '당신의 얼굴은 삼정 모두가 참여하는 "분산형" 건강 구조입니다. 특정 장기의 강력한 이점보다 전체 균형에서 힘이 나오는 결—한 군데가 무너지면 나머지가 보완하는 @{rare} 이점을 지닌 구조입니다.',
    '@{palace_health}과 @{palace_destiny}이 서로 견주어 흐르는 상. 정신의 맑음이 몸의 활력으로 번역되는 결이라, 스트레스 관리 하나가 다른 모든 지표를 좌우하는 @{structure}입니다.',
    '@{palace_health}과 @{mount_n}이 함께 움직이는 결은 관상학이 "몸과 뿌리가 한 호흡"이라 부르는 구조입니다. 정서의 안정이 바로 내장의 안정으로 이어지는 유형—잘 쉬는 습관이 가장 확실한 장수의 열쇠입니다.',
  ]),
];

final List<_Frag> _romanceAdviceFemale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '매력의 화력과 감정의 해상도가 함께 짙은 결입니다. 관상이 가장 아깝게 만드는 경우는 "설렘의 유통기한"만 쫓다가 평생 자리를 못 정하는 것—3번째 만남까지의 화력보다 3년째의 대화 밀도로 상대를 고르는 훈련이 평생 연애의 질을 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '후보의 폭이 넓은 결은 "비교의 습관"이 결정 타이밍을 늦추기 쉽습니다. 당신에겐 선택 기한을 스스로 박아 두는 것이 가장 큰 전략—3개월 안에 답을 내는 규율 하나가 평생의 인연 구조를 바꿉니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '불러오는 자리는 @{intense} 열려 있는데 속의 대화는 상대적으로 얇은 결입니다. 외부 열기에 휩쓸리지 말고 "같이 있을 때 대화가 이어지는 사람"을 한 축으로 더해 두십시오—겉의 열기가 식은 뒤 남는 것이 거기에 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '첫인상의 스파크보다 "여러 번 겹쳐진 대화"에서 상대가 당신을 발견하는 결입니다. 소개팅·앱 회전이 결과 안 맞는 유형이니, 공동의 활동·관심사·동료 관계 안에서 자연스럽게 쌓이는 인연 경로를 의식적으로 넓히십시오.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 균형의 연애 결입니다. 화려함 없이 단정하게 깊어지는 유형—첫눈에 끌리는 사람보다 두 달 뒤에도 피곤하지 않은 사람을 알아보는 눈이 당신의 가장 큰 자산입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '설렘의 강도보다 "안정된 리듬"을 우선하는 결입니다. 드라마틱한 연애를 욕망의 기준으로 삼지 마십시오—이 결은 조용한 신뢰가 쌓일 때 진가가 드러나고, 주변에서 먼저 "결혼감"이라 평하는 유형입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '첫눈의 화력은 @{faint} 얇지만 감정의 결은 @{deep} 두꺼운 결입니다. 상대가 당신을 "알게 된 뒤" 관심이 눈에 띄게 짙어지는 후발형—짧은 만남으로 평가받는 자리가 아니라 같은 공간을 여러 번 공유하는 경로를 만들면 인연이 쌓입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '매력과 감정 어느 쪽에도 쏠림이 없는 결입니다. 연애가 인생의 전체 축이 아니어도 괜찮다—당신에겐 "같이 있을 때 덜 피곤한 사람"이 가장 좋은 상대이며, 화려한 서사보다 일상의 호흡이 맞는 사람을 골라야 합니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '연애가 인생의 중심 축이 아닌 결입니다. 결핍이 아니라 방향—"반려"로서의 파트너십, 동지적 결합의 가능성도 진지하게 고려할 수 있습니다. 꼭 같은 속도로 가지 않아도 같은 방향을 보는 사람이 당신에겐 더 잘 맞습니다.',
  ]),
  _Frag.hard((f) => true, [
    '연애운을 살리는 세 축: "끌리는 사람"과 "일상에 맞는 사람"을 따로 저울질하는 훈련, 비교의 습관에 기한을 두는 규율, 그리고 이별의 품위. 마지막 장면의 결이 다음 @{fate_word}의 색을 결정하는 것이 여성 관상의 숨은 자산입니다.',
  ]),
];
final List<_Frag> _romanceAdviceMale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.emotionality), [
    '매력과 감정의 해상도가 동시에 짙은 결은 관상이 "염정상(艶情相)"이라 부르는 @{rare} 구조입니다. 다만 이 결은 자기 관리가 없으면 에너지가 사방으로 분산되기 쉬우니, 하나의 관계를 깊이 파는 훈련이 평생 연애의 상한을 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '끌어당기는 힘은 @{intense} 강한데 감정의 미세 신호를 잡는 센서는 평균권인 결입니다. 설렘의 유통기한이 먼저 찾아오는 유형—"권태 구간을 피하지 않고 통과할 설계"(공동 프로젝트·여행·신체 리듬 변화)를 분기에 하나씩 배치하십시오.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '매력 자체는 강한데 상대의 속 이야기를 읽는 결은 @{faint} 얇은 유형입니다. "직관으로 관계를 이끌되 정기적으로 언어로 확인하는" 루틴이 수명의 열쇠—한 달에 한 번 둘의 상태를 점수로 물어보는 의례가 효율 극대화됩니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '겉의 화력보다 "대화의 밀도"로 상대를 사로잡는 결입니다. 앱 회전보다 동료·지인 네트워크 안에서 쌓인 신뢰가 연애로 전환되는 경로가 당신에게 훨씬 높은 승률을 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '극단 없는 균형의 연애 결입니다. 3번째 만남 이후부터 진가가 드러나는 유형—첫만남 평가에 흔들리지 말고 서너 번의 누적된 장면으로 판단하십시오. 남들이 부러워하는 관계는 이 결에서 가장 자주 나옵니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '안정된 리듬에 강점이 있는 결입니다. 드라마틱한 연애보다 "피로가 쌓이지 않는 관계"를 우선하십시오—당신에겐 이쪽이 평생 수명이 긴 선택입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '첫인상 화력은 @{faint} 얇은데 감정 해상도는 짙은 결입니다. 상대가 당신을 "알게 된 뒤" 호감이 크게 올라가는 후발형—짧은 만남으로 평가받는 자리가 아닌, 같은 공간 반복 공유의 경로를 의식적으로 설계하십시오.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '매력과 감정 어느 쪽도 쏠리지 않은 결입니다. 단정한 생활의 기반·직업의 안정 같은 축이 연애의 매력으로 환원되는 유형—겉의 연출보다 삶의 구조를 가꾸는 것이 당신에겐 훨씬 큰 레버리지입니다.',
  ]),
  _Frag(_lowPair(Attribute.attractiveness, Attribute.emotionality), [
    '연애가 인생의 주축이 아닌 결입니다. 결핍이 아니라 방향—자기 세계·직업·관심사의 깊이를 먼저 쌓아 두면 그 결이 파트너를 자연스럽게 끌어옵니다. 서두르지 않는 것이 가장 좋은 전략입니다.',
  ]),
  _Frag.hard((f) => true, [
    '연애운을 살리는 세 축: "끌리는 상대"와 "일상에 맞는 상대"를 분리해 평가하는 눈, 권태 구간을 피하지 않고 통과할 설계, 이별의 품격. 마지막 장면이 가장 오래 기억되는 것이 남성 연애의 숨은 자산입니다.',
  ]),
];
final List<_BeatPool> _romanceBeatsFemale = [
  _romanceOpeningFemale,
  _romanceStrengthFemale,
  _romanceShadowFemale,
  _romanceAdviceFemale,
];
final List<_BeatPool> _romanceBeatsMale = [
  _romanceOpeningMale,
  _romanceStrengthMale,
  _romanceShadowMale,
  _romanceAdviceMale,
];

// ─── 4-F. 연애운 (여) ─────────────────────────────────────────────────

final List<_Frag> _romanceOpeningFemale = [
  // 9-cell matrix: attractiveness(primary) × emotionality(secondary)
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.high), [
    '당신의 연애는 \'불러오고, 깊게 읽는\' 이중 역학입니다. @{palace_mate}이 열려 여러 방향에서 호감이 들어오고 누당(淚堂)의 윤기가 상대의 속결까지 @{intense} 간파합니다. 선택지의 폭과 해석의 밀도가 동시에 높아 \'이 사람이 맞나\' 를 증명하려는 단계가 깊어지는 결입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'불러오는 자리\'에 단단한 현실감이 실려 있습니다. @{palace_mate}이 열려 호감이 먼저 들어오되 상대를 무리하게 미화하지 않고, 첫 세 달 안에 결을 판별해 진도를 정하는 @{noble_f} 판단이 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'들어오는 호감을 담담히 골라내는\' 결입니다. 누당의 윤기가 분위기를 끌어당기되 속결은 건조한 편이라, 관계의 방향과 조건을 먼저 정리하는 차가운 리드가 오히려 매력으로 읽힙니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '당신의 연애는 \'우정에서 연인으로\' 자연스럽게 넘어가는 전환형입니다. 첫인상의 스파크보다 여러 번 겹쳐진 대화 속에서 상대가 \'이 사람\' 을 발견하게 되며, 속결을 읽어내는 감수성이 관계를 @{deep} 끌고 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'중용의 리듬\' 을 따라갑니다. 화력도 집요함도 양극단으로 치우치지 않아, 상대의 속도와 맞추며 두세 번의 만남 뒤 자연스럽게 관계의 이름이 정해지는 균형 잡힌 진입이 특징입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'조건과 결\' 을 먼저 맞추는 실리형입니다. 화려한 구애를 기대하기보다 서로의 삶이 어떻게 겹치는지를 냉정히 저울질하며, 현실 궁합이 맞는 상대와의 합이 유난히 깊습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '당신의 연애는 \'후발(後發)형\' 깊이의 결입니다. 외형의 파장이 즉시 끌어당기는 결은 아니나 한 번 대화를 나눈 상대가 며칠 뒤 당신을 다시 떠올리는 여운형이며, 감수성의 밀도가 평균을 크게 뛰어넘는 @{noble_f} 연애를 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'자리에서 만나는\' 생활 기반형입니다. 길거리에서의 우연한 스파크보다 같은 공간·같은 일·같은 모임에서 오래 겹친 상대와 자연스럽게 이어지는 결이며, 시작은 @{subtle} 하되 관계의 지속력은 길게 갑니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'동지(同志) 결합\' 의 결에 가깝습니다. 뜨거운 구애보다 같은 가치·같은 방향을 확인한 상대와 조용히 나란히 걷는 형태이며, 결혼이라는 결론에 도달하는 직진성이 평균보다 @{intense} 강합니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 \'시작은 느리되 시작한 뒤로는 깊이 들어가는\' 결입니다. 첫 만남에서 즉시 불이 붙기보다 같은 자리에 두세 번 마주친 뒤 관심의 불씨가 번져가는 유형이며, 결혼으로 이어지는 관계에서 진가가 @{intense} 드러납니다.',
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
    '당신의 연애는 \'끌어당기고, 깊게 읽는\' 드문 이중 역학입니다. @{palace_mate}이 열리고 @{mount_c}의 기운이 받치는 상에 상대의 속결까지 간파하는 눈이 함께 실려 있어, 먼저 다가서되 상대를 @{subtle} 해석하는 두 가지 결이 동시에 움직이는 장부의 면모가 또렷합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'먼저 다가서는 쪽\'의 역학입니다. @{palace_mate}이 열리고 관심이 서면 머뭇거리지 않고 다음 장을 여는 장부의 기질이 @{intense} 드러나며, 상대의 속도보다 반 걸음 빠른 리듬이 연애의 색을 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.high, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'파장은 강하나 속은 담담한\' 결입니다. 첫 장면에서 공기를 장악하는 기세가 또렷하되 속마음은 감정을 오래 머금지 않아, 관계의 조건과 방향을 먼저 정리하는 차가운 리드가 당신의 @{noble_m} 매력을 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.high), [
    '당신의 연애는 \'말과 해석으로 들어가는\' 결입니다. 외형의 파장보다 대화에서 상대의 결을 @{intense} 짚어내는 힘이 매력의 중심이 되며, 느리게 시작해 여러 장면을 겹쳐 관계를 @{deep} 끌고 가는 장부의 기질이 자리합니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'중용의 다가섬\' 입니다. 기세도 감정도 양극단으로 치우치지 않아, 같은 공간에 끌리는 사람이 있으면 시선을 피하지 않고 먼저 말을 건네되 상대의 속도에 맞춰 관계의 이름을 정해가는 안정형 진입이 특징입니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.mid, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'조건을 먼저 맞추는\' 실리형입니다. 화려한 구애보다 서로의 생활이 어떻게 맞물리는지를 냉정히 저울질하며, 한 번 맞는다 판단한 상대와는 결혼의 종착점까지 직선으로 달려가는 장부의 결이 배어 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.high), [
    '당신의 연애는 \'후발 깊이\' 의 결입니다. 즉시 끌어당기는 파장은 약하되 한 번 대화를 나눈 상대가 며칠 뒤 당신을 다시 떠올리는 여운형이며, 속결을 읽어내는 감수성의 밀도가 평균을 크게 뛰어넘는 @{noble_m} 연애를 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.mid), [
    '당신의 연애는 \'생활 기반\' 형입니다. 길거리의 우연한 스파크보다 같은 일·같은 모임에서 오래 겹친 상대와 자연스럽게 이어지는 결이며, 시작은 @{subtle} 하되 한 번 시작된 관계의 지속력은 평균보다 @{intense} 깁니다.',
  ]),
  _Frag(_bandPair(Attribute.attractiveness, _Band.low, Attribute.emotionality, _Band.low), [
    '당신의 연애는 \'자기 세계(世界) 주도\' 형에 가깝습니다. 화려한 구애나 감정 곡예 없이 자신의 일·목표·루틴을 단단히 가진 상대에게 조용히 끌리는 결이며, 결혼 상대를 고르는 기준이 일찍 확정되는 직선성이 특징입니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 \'다가서는 자\'의 결이 기본입니다. 같은 공간에 끌리는 사람이 있으면 시선을 피하지 않고 먼저 말을 건네는 기질이어서, 관계의 출발점을 설계하는 쪽이 대개 당신이며 이 주도성이 연애의 색을 결정합니다.',
  ]),
];
final List<_Frag> _romanceShadowFemale = [
  // libido-driven 바람기 1-line (libido high & stability not high — 정서 누수형)
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '바람기의 결은 \'정서 누수형\' 입니다. 육체적 이탈보다 현재 관계에서 채워지지 않는 공감을 다른 상대에게서 구하는 심리 외도의 경로가 먼저 열리며, 대화가 깊어지는 상대가 나타나는 시기를 경계해야 합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) == _Band.high, [
    '바람기의 결은 강한 자기 통제 안에 눌려 있습니다. @{palace_mate}의 안정감이 선을 지키되, 한 번 넘으면 돌아오기 어려운 \'한 번의 큰 이탈\' 형이라 관계 만족도가 떨어지는 장기 신호를 방치하지 않는 편이 안전합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '또 \'설렘의 유통기한\' 문제가 따릅니다. 시작의 화력이 강한 만큼 권태가 먼저 찾아오기 쉬우며, 그 공백을 덮으려 다음 상대를 미리 떠올리는 결이 들어서면 좋은 인연을 놓치는 패턴이 쌓일 수 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.trustworthiness) != _Band.high, [
    '또 \'혼자 앞서 나가는\' 위험이 있습니다. 상대의 신호를 깊게 해석하는 감수성이 때로는 신호가 아닌 것까지 신호로 읽어, 상대가 아직 정리하지 못한 감정을 당신이 먼저 미래로 번역해 속도의 낙차를 만들기 쉽습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) == _Band.low, [
    '또 \'만날 자리 자체가 좁다\' 는 한계에 부딪히기 쉽습니다. 검증의 기질이 강점이지만 동시에 새 사람과의 접점에 잘 들어서지 않는 결이어서, 좋은 인연이 지나가는 시기를 모르고 보낼 수 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 \'결정 지연\' 의 그림자가 있습니다. 상대의 신호를 감지한 상태에서도 조금만 더 확인하려다 적극적 경쟁자에게 자리를 넘기는 시나리오가 되풀이되기 쉬우며, 완벽한 증거는 결혼 뒤에도 오지 않습니다.',
  ]),
];
final List<_Frag> _romanceShadowMale = [
  // libido-driven 바람기 1-line (libido high & stability not high — 상황 의존형)
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '바람기의 결은 \'상황 의존형\' 입니다. 먼저 적극적으로 찾아 나서는 결이 아니라 출장·회식·원거리 주말 등 관계의 선이 흐려지는 물리적 환경이 열릴 때 경계가 무너지는 형이라, 반복되는 출장 주기와 음주 빈도가 최대 리스크입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) == _Band.high, [
    '바람기의 결은 의지로 눌러 온 구조입니다. @{mount_n}의 단단함이 선을 지키되 한 번 넘으면 가정 전체를 흔드는 \'대형 이탈\' 형이라, 관계 만족도의 장기 하락 신호를 방치하지 않아야 합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '또 \'설렘의 유통기한\' 문제가 되풀이됩니다. 시작의 화력이 강한 만큼 일상 단계로 넘어가는 6개월에서 1년 사이 권태가 먼저 찾아오며, 그 공백을 새 자극으로 메우려 할 때 좋은 사람을 놓치는 패턴이 쌓이기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '또 주도성이 강한 만큼 \'내가 정한 속도\' 를 상대에게 강요하기 쉽습니다. 상대의 결이 따라오지 못할 때 관심이 식는 속도도 빠른 편이라, 기다릴 수 있는 인내가 연애 수명의 핵심이 됩니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) != _Band.high, [
    '또 \'만날 자리 자체가 좁다\' 는 한계에 부딪히기 쉽습니다. 검증의 기질이 강점이지만 동시에 새 사람과의 접점에 잘 들어서지 않는 결이어서, 좋은 인연이 지나가는 시기를 모르고 보낼 수 있습니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 \'한 사람에 집중되면 주변이 흐려지는\' 기질이 있어, 가장 뜨거운 시기일수록 생활의 축 — 일·친구·건강 — 을 의식적으로 유지하지 않으면 중요한 자리를 같이 놓치기 쉽습니다.',
  ]),
];
final List<_Frag> _romanceStrengthFemale = [
  _Frag.hard((f) => f.fired('P-08'), [
    '@{palace_sex} 아래 누당(淚堂)의 윤기가 살아 있는 구조는 도화기(桃花期)가 규칙적으로 돌아오는 결로, 한 해에 한두 번 의미 있는 인연의 문이 열리는 주기성이 자리합니다.',
  ]),
  _Frag.hard((f) => f.fired('L-EL'), [
    '측면에서 입술선이 도톰하게 드러나는 상은 관상학의 \'도화(桃花) 기색\' 이며, 상대의 시선이 당신의 입매에 오래 머무는 @{subtle} 매력을 만듭니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '언행이 일치하는 상은 \'한 번 정하면 끝까지 가는\' 신뢰를 상대에게 각인시키며, 장기 관계의 뿌리를 @{deep} 박게 하는 @{noble_f} 덕(德)이 서려 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high, [
    '상대의 속결을 @{observe} 감수성은 갈등의 싹을 일찍 알아보는 결로 작동하며, 작은 신호에서 관계의 방향을 조정할 수 있는 여인의 지혜가 @{result_carry}.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.5, [
    '@{organ_mouth}의 결이 단정한 구조는 \'말로 관계를 지키는\' 힘을 의미하며, 잘 다듬어진 말 한 마디가 연인의 마음을 오래 묶어두는 매력의 축이 됩니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eye') >= 0.5, [
    '눈빛에 윤기가 서린 상은 상대를 \'담아두는\' 시선의 힘이 있어, 짧은 순간에도 당신이 자신을 알아봐 주었다는 기억을 상대에게 오래 남깁니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 관계의 \'양\' 보다 \'질\' 이 우선이며, 맞는 사람 한 명을 만났을 때의 밀도가 평균을 크게 뛰어넘는 결을 가졌습니다.',
  ]),
];

final List<_Frag> _romanceStrengthMale = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 또렷한 구조는 자기 의사를 흐리지 않는 결이라, 애매한 썸에 오래 머무르지 않고 관계의 성격을 일찍 정리합니다. 상대가 \'끌려다닌다\'는 느낌 없이 당신의 속도를 따라오게 만드는 장부의 결단이 @{result_carry}.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 받쳐주는 구조는 \'기백(氣魄)\' 이 실린 결로, 당신이 들어서는 순간 공기의 중심이 옮겨 가는 결이 연애의 출발점에서 @{intense} 작동합니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '측면에서 드러나는 @{organ_nose}의 단단한 윤곽은 \'사내의 기운\' 이 실린 결로, 상대가 당신의 결정에 기대고 싶어지는 장부의 중심축을 형성합니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '말과 행동이 일치하는 상은 연애에서도 \'해 주겠다 한 것은 반드시 해내는\' 결로 작동해, 시간이 지날수록 상대의 신뢰가 두텁게 쌓이는 @{noble_m} 덕이 배어 있습니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.wealth) == _Band.high || f.nodeZ('nose') >= 0.8, [
    '@{palace_wealth}이 두터운 상은 연애에서도 \'생활의 기반\' 을 먼저 갖추는 결이며, 상대에게 막연한 약속 대신 구체적 안정감을 보여주는 @{intense} 매력을 만듭니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('chin') >= 0.5, [
    '@{mount_n}이 단정한 상은 \'한 번 정하면 끝까지 간다\' 는 지각(地閣)의 결이며, 흔들리지 않는 뿌리가 장기 관계의 가장 큰 축이 됩니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 연애는 순간의 분위기보다 누적된 기백에서 힘을 얻는 결이어서, 한 번에 타오르기보다 여러 장면을 겹쳐 당신의 결을 각인시키는 장기전에서 유리합니다.',
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
];

final List<_BeatPool> _sensualBeatsFemale = [
  _sensualOpeningFemale,
  _sensualStrengthFemale,
  _sensualShadowFemale,
  _sensualAdviceFemale,
];

final List<_BeatPool> _sensualBeatsMale = [
  _sensualOpeningMale,
  _sensualStrengthMale,
  _sensualShadowMale,
  _sensualAdviceMale,
];

// ─── 6-F. 관능도 (여) ─ band 9-cell × 부위 단서 × 건강한 향유 ─────────────────

final List<_Frag> _sensualOpeningFemale = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '누군가의 시선이 스치는 순간, 공기가 반 박자 먼저 데워진다. 곁에 사람이 있다는 그 미묘한 긴장—그게 곧 불씨다. 관상학은 이걸 농화상(濃花相)이라 부른다. 욕망의 선이 선명한데, 상대의 숨과 체온의 미세한 떨림까지 집어내는 안테나가 같이 켜진 결. 드문 조합이다.',
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
// 오랜 관계에서 몸에 새겨지는 농밀한 결, 음주·파티의 기(氣) 누수 경고,
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
      '어떤 남자는 방에 들어서는 순간부터 공기가 바뀐다. 말을 많이 하지 않아도 체온이 먼저 닿는 타입이 있다. 관상학은 이걸 "농밀상(濃密相)" 이라 부른다. 쉽게 말하면 이런 거다. 욕구의 선이 굵은데, 상대의 숨결과 떨림을 읽는 센서까지 같이 켜져 있는 구조.',
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
      '몸보다 머릿속이 먼저 뜨거워지는 타입이 있다. 한 편의 영화, 한 장의 사진, 한 줄의 문장에서 먼저 열리는 구조. 관상학은 이걸 "심감형(心感型)" 이라 부른다. 몸이 느려도 상상의 해상도는 남들 두 배다.',
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
      '외부의 시선이 들어오는 순간, 분위기가 확 달아오르는 타입이 있다. 누가 보고 있다는 그 묘한 긴장감, 그게 바로 감정의 불씨가 되는 구조다. 관상학은 이걸 꽤 직설적으로 부른다. "시선 의존 도화(桃花依存)." 쉽게 말하면 이런 거다. 무대 위에서는 누구보다 뜨겁고 매혹적인데, 조명이 꺼지고 관객이 빠지면 온도가 같이 내려가는 타입. 혼자 있는 시간에 조용히 켜지는 자기만의 리듬을 따로 만들어 두면, 관객이 없어도 뜨거울 수 있는 결로 넘어간다.',
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
      '외부의 시선이 들어오는 순간, 분위기가 확 달아오르는 타입이 있다. 누가 보고 있다는 묘한 긴장감, 그게 감정의 불씨가 되는 구조다. 관상학은 이걸 꽤 직설적으로 부른다. "도화의존상(桃花依存相)." 쉽게 말하면 이런 거다. 무대 위에서는 누구보다 뜨거운데, 조명이 꺼지고 관객이 빠지면 온도가 같이 내려가는 타입. 혼자 있을 때 조용히 켜지는 리듬을 따로 만들어 두면, 관객이 없어도 뜨거워질 수 있는 결로 옮겨 간다.',
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
    '입술이 도톰하다. 정(情) 이 얼굴에서 먼저 읽히는 결—말보다 표정이 먼저 닿는다. 식복과 언복까지 같이 열려 있어서, 공간 자체를 부드럽게 만드는 강점이 있다. 와인잔 건너로 시선이 오래 머무는 결이다.',
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
    '인중이 길다. 관상학은 이 결을 "장지상(長持相)" 이라 부른다. 쉽게 말하면, 짧은 폭발보다 긴 밀도로 승부하는 구조—같이 보낸 시간이 쌓일수록 오히려 몸의 감각이 더 깊어지는 드문 결이다.',
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
    '여성의 얼굴에 양(陽) 의 기운이 뚜렷이 쏠린 결은 드문 타입이다. 관능의 리듬이 적극적이고 주도적인 쪽으로 자연스럽게 기운다—"먼저 움직이는 쪽" 을 당당하게 활용할 때 가장 선명한 매력이 드러나는 구조다.',
  ]),
  _Frag.hard(_yinStrong, [
    '얼굴 전체에 음(陰) 의 기운이 짙게 쏠려 있다. 수용과 포용의 축이 관능의 뼈대가 되는 타입—상대를 끌어안는 결 자체에서 농도가 피어난다. 시간이 깊어질수록 결이 더 또렷해지는 구조다.',
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
    '입술이 도톰하다. 정(情) 이라는 게 얼굴에서 먼저 읽히는 타입—말보다 표정이 먼저 닿는다. 같이 밥 먹으러 간 식당의 공기까지 부드럽게 만드는 결이다. 와인 한 잔만 있어도 분위기가 바뀐다.',
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
    '인중이 길다. 관상학은 이걸 "장지상(長持相)" 이라 부른다. 쉽게 말하면 이런 거다. 짧게 폭발하는 게 아니라 긴 시간 밀도로 승부하는 구조. 같이 산 세월이 쌓일수록 오히려 몸의 감각이 더 깊어지는, 드문 결이다.',
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
    '얼굴 전체에 양(陽)의 기운이 짙게 서렸다. 관능의 리듬이 적극적이고 주도적인 쪽으로 기울어 있는 결—"먼저 움직이는 쪽" 이 자연스럽다. 상대가 그걸 기다리는 구조이기도 하다.',
  ]),
  _Frag.hard(_yinStrong, [
    '얼굴에 음(陰)의 기운이 깊이 깃들어 있다. 관능이 수용과 포용 쪽으로 기울어 있어서, 격렬한 파도보다 잔잔한 깊이로 관계를 만든다. 조명 꺼진 방의 부드러운 정적 같은 결이다.',
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
    '친화와 신의가 함께 박힌 결은 관계가 평생 자산이 되는 @{rare} 구조입니다. 다만 "모든 사람을 품을 수 있다"는 자신감이 가장 큰 함정—한 해에 한 번은 명단을 줄이는 연습을 하십시오. 넓이는 이미 충분하니 이제는 깊이의 밀도를 높이는 구간입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '진입로는 넓은데 끝까지 가는 관계가 상대적으로 얇은 결입니다. 처음 친해진 사람과 1년 뒤 연락 빈도를 절반으로라도 유지하는 루틴 하나가 관계의 상한을 통째로 바꿉니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '열기는 빠른데 식는 속도도 빠른 결입니다. "처음엔 친했는데 어느 순간 멀어진" 관계가 누적되기 쉬운 유형—새 사람을 늘리는 대신 이미 아는 사람을 깊이 파는 쪽으로 에너지를 옮기십시오.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '관계의 "가운데 온도"가 긴 시간 유지되는 결입니다. 뜨거워졌다 식는 사람보다 미지근한 온도를 오래 유지하는 당신 같은 사람이 결국 가장 멀리 갑니다—먼저 안부를 건네는 월간 루틴 하나만 더해 두십시오.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '극단 없는 중용의 관계 결입니다. 넓지도 좁지도 않은 자연스러운 네트워크—3개월마다 "연락이 끊긴 사람 한 명"을 의도적으로 복원하는 습관 하나가 평생 관계 자산을 두텁게 만듭니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '새 사람과 섞이는 힘도 오래 이어가는 힘도 평균권인 결입니다. "유지 루틴"이 가장 효율적인 개입점—월 1회 정기 모임 1개만 박아 두면 관계의 총량이 구조적으로 올라갑니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '사교의 문이 좁은 대신 열린 관계는 평생 이어지는 "정예 소수"의 결입니다. 넓히려 애쓰지 말고 있는 사람을 지키는 쪽에 자원을 몰아 주십시오—당신에겐 이쪽이 훨씬 큰 레버리지입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사교성 자체는 두껍지 않지만, 있는 관계는 꾸준히 이어가는 결입니다. 새 사람 만나는 부담을 내려놓고 기존 관계 안에서 "역할"을 한 단계 더 깊이 맡아 가는 것이 가장 자연스러운 확장 방향입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '관계가 인생의 중심축이 아닌 결입니다. 고립을 걱정하기보다 "혼자 쌓는 시간의 결과"를 세상에 보여 주는 출구 하나를 확보하십시오—일·작품·문장이 당신의 관계를 대신 열어주는 구조입니다.',
  ]),
  _Frag.hard((f) => true, [
    '관계의 운을 키우는 세 축: 미지근한 온도를 오래 유지하는 감각, 먼저 안부를 건네는 월간 루틴, 모든 사람을 품으려 하지 않는 절제. 이 셋이 지켜질 때 꼭 지켜야 할 사람이 곁에 오래 남습니다.',
    '관계의 진짜 자산은 "한 번에 크게 친해지는" 쪽이 아니라 "10년간 작은 연락을 잃지 않는" 쪽에 쌓입니다. 당신의 @{structure}에는 한 달에 한 번, 한 줄의 안부를 보내는 이 단순한 루틴이 평생 네트워크의 총량을 바꿉니다.',
    '관상학이 일러주는 관계 설계의 핵심은 "들어오는 문"과 "나가는 문"을 따로 두는 것입니다. 정리 없이 받아들이기만 하면 내부 밀도가 희석되고, 받지 않고 정리만 하면 외부 공급이 끊깁니다. @{palace_social}의 열림이 제 힘을 쓰려면 두 흐름이 함께 움직여야 합니다.',
    '당신에게 가장 중요한 사람 다섯 명을 종이에 쓰고 각각에게 이번 달 얼마의 시간을 썼는지 세어 보십시오. 그 숫자가 관계의 진짜 지도입니다. @__STRONGEST_NODE__의 기운이 아무리 좋아도 이 지도를 안 그리는 사람의 후복은 얇아지는 @{structure}입니다.',
    '관계의 상한을 여는 세 축: 먼저 안부를 건네는 규율, 오래 가져가지 못할 관계를 일찍 정리하는 단호함, 그리고 "내가 먼저 약한 부분을 보여줄 용기"—이 셋이 함께 지켜질 때 @{palace_home}과 @{palace_servant} 모두가 제 자리를 찾습니다.',
  ]),
];

final List<_BeatPool> _socialBeats = [
  _socialOpening,
  _socialStrength,
  _socialShadow,
  _socialAdvice,
];

// ═══ 3. 대인관계 ═══

final List<_Frag> _socialOpening = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '사람을 여는 호방함과 한결같은 믿음이 한 얼굴에 겹친 결입니다. @{palace_social}과 @{palace_servant}이 동시에 발달한 @{rare} 상—처음 만난 자리에선 친화력에 끌리고 오래 지나서는 의리에 남는 이중 매력이 함께 작동하는 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.mid), [
    '사람을 끌어당기는 기운이 @{intense} 드러나는 얼굴입니다. @{palace_social}이 @{open_wide} 열린 상—낯선 자리에서도 긴장을 풀어놓는 친화력이 강점이지만, 깊이 맺는 관계는 "정하고 나서야" 자리잡는 결입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '입구가 @{intense} 넓은 결입니다. 낯선 자리의 온도를 올리는 능력은 탁월한 대신, 오래 이어가는 쪽은 상대적으로 얇은 유형—허브 역할에 강하되 깊이의 밀도는 따로 관리해야 하는 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.high), [
    '화려한 사교성보다 "배신하지 않는 사람"이라는 무언의 신호가 사람들을 곁에 머물게 하는 결입니다. @{palace_home}과 @{palace_servant}이 두텁게 자리한 상—중년 이후 @{intense} 빛나는 @{noble} 구조입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.mid), [
    '넓지도 좁지도 않은 중용의 관계 결입니다. 상황에 따라 사교형과 정주형 양쪽을 자연스럽게 넘나드는 구조—쏠림 없는 균형이 평생 관계의 밀도를 안정적으로 유지하는 @{structure}입니다.',
    '"선택과 집중" 방식으로 흘러가는 결입니다. 넓은 네트워크보다 꼭 필요한 소수와의 단단한 연결을 우선하는 기질이며, 정해둔 소수에게 에너지를 몰아주는 선택적 관계 설계자에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.mid, Attribute.trustworthiness, _Band.low), [
    '사교와 신의 어느 쪽에도 뚜렷한 쏠림이 없는 결입니다. 관계가 자동으로 쌓이진 않지만, 의식적 루틴 하나만 박아두면 평균 이상의 네트워크가 유지되는 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.high), [
    '새 사람을 만나는 입구가 좁은 대신, 한 번 열린 관계는 @{deep} 깊게 이어지는 결입니다. @{palace_home}이 단단한 상—소수 정예의 우정을 평생 가져가는 "오래 가는 사람"의 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.low, Attribute.trustworthiness, _Band.mid), [
    '사교의 폭은 좁되 기존 관계는 꾸준히 이어가는 결입니다. 한 번 들어선 자리 안에서 역할이 시간과 함께 깊어지는 유형—화려함 대신 신뢰로 작동하는 @{structure}입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '사람을 여는 문도, 오래 품는 문도 @{faint} 좁은 결입니다. 관상학에서 "고립상(孤立相)"이 살짝 드러나는 유형—혼자 쌓는 시간에서 진짜 결과물이 나오는 독립형 @{structure}입니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 대인관계는 뚜렷한 쏠림 없이 상황에 맞춰 유연히 움직이는 결입니다. 넓이와 깊이 사이에서 균형을 잡는 중용의 @{structure}—어느 자리에 놓여도 그 자리의 온도에 맞춰 녹아드는 적응력이 있습니다.',
    '관계의 바퀴가 한 방향으로만 굴러가지 않고 여러 축에서 균일하게 도는 결입니다. @{palace_social}과 @{palace_home}이 서로 견주어 자리잡은 상—지인의 수가 많지는 않아도 질이 엇비슷한 수준으로 균질하게 유지되는 @{structure}입니다.',
    '"사람을 모으는 힘"과 "사람을 붙잡는 힘"이 함께 평균권에 있는 결입니다. 화려한 네트워크 대신 단단한 소수를 평생 함께 가는 유형—한 번 맺은 인연의 반감기가 남보다 유난히 긴 구조가 얼굴에 새겨져 있습니다.',
    '@{palace_social}과 @{palace_servant}이 모두 제 자리를 지키는 상. 외향과 내향의 어느 한쪽에 치우치지 않는 중용의 결이라, 큰 자리에도 작은 자리에도 자연스럽게 녹아드는 @{rare} 유연성이 있습니다.',
    '관상학에서 "정(情)이 오래 머무는 얼굴"이라 부르는 결. 첫 만남의 임팩트보다 여러 번 만난 뒤 드러나는 "편안함"이 당신 관계의 진짜 힘—중년 이후 남은 사람들이 말하는 "신뢰의 중심"에 당신이 서 있게 되는 @{structure}입니다.',
  ]),
];

final List<_Frag> _socialShadow = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 "모두를 품는다"는 자신감이 역으로 피로의 원천이 됩니다. 주는 정의 총량이 돌아오는 정을 오래 앞지르면 조용한 소진이 쌓이기 쉬운 결—정기적 관계 정리가 이 유형의 숨은 숙제입니다.',
  ]),
  _Frag(_lowPair(Attribute.sociability, Attribute.trustworthiness), [
    '다만 가만히 두면 관계가 자연스럽게 줄어드는 방향으로 흐르는 결입니다. 편해서가 아니라 유지 루틴이 약해 결과적으로 고립되는 패턴이 반복되는 유형—의식적 연결 장치 없이는 중년 이후 외로움이 가속됩니다.',
  ]),
  _Frag(_bandPair(Attribute.sociability, _Band.high, Attribute.trustworthiness, _Band.low), [
    '다만 새 관계의 열기가 식으면 같은 사람을 꾸준히 챙기는 동력은 @{faint} 얇은 편입니다. "처음엔 친했는데 어느 순간 멀어진" 관계가 누적되기 쉬우며, 관계의 수는 많지만 깊이를 나눌 사람이 부족한 공허감이 찾아오기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 관계의 거리 조절 폭이 @{subtle} 좁은 편입니다. 가까워지면 너무 깊이 들어가고 한 번 실망하면 단번에 멀어져버리는 "0 아니면 100" 패턴이 반복되기 쉬운 @{structure}입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 에너지 배분이 불균형해지기 쉬운 결입니다. 중요한 사람에게 과하게 몰아주고 나머지는 방치하는 패턴이 반복되면, 결정적 순간에 "주변에 사람이 너무 없다"는 느낌이 찾아오기 쉽습니다.',
    '다만 관계의 온도를 남의 리듬에 맞추느라 자기 배터리가 먼저 바닥나는 결입니다. @{palace_social}이 열린 사람일수록 "함께 있는 시간"의 총량보다 "회복 시간"의 확보가 더 결정적—혼자 있는 시간을 방어해야 관계의 질이 유지됩니다.',
    '다만 갈등을 피하려는 본능이 지나쳐 필요한 선긋기 타이밍을 놓치는 결입니다. @{palace_destiny}의 맑음이 오히려 단점이 되는 구간—"싫다"는 말을 제때 못 하면 관계가 자동으로 약자의 자리로 자리잡는 패턴이 반복됩니다.',
    '다만 당신에게 가장 아픈 상처는 "친했다가 떠난" 사람입니다. 관상학이 "인연의 흐름"을 말할 때 가장 많이 짚는 대목—모든 관계가 평생 지속되지 않는다는 사실을 받아들이지 못하면, 떠난 사람의 그림자가 새 사람이 올 자리를 막는 @{structure}입니다.',
    '다만 "좋은 사람"이라는 평판을 지키려는 욕망이 관계 선택의 자유를 깎아내기 쉬운 결입니다. 모두에게 같은 얼굴을 하려다 진짜 친한 사람이 들어올 깊은 자리가 얕아지는 유형—선택적 거리두기가 오히려 @{palace_home}의 밀도를 높입니다.',
  ]),
];

final List<_Frag> _socialStrength = [
  _Frag.hard((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입과 눈의 표현이 함께 살아 있는 구조는 대화의 리듬감이 좋은 결입니다. 상대가 "이 사람과 있을 때 내 편이 된 것 같다"는 인상을 받기 쉬운 유형입니다.',
  ]),
  _Frag.hard((f) => f.fired('L-AQ'), [
    '측면의 매부리형 코는 결정적 순간에 자기 주장을 또렷이 내세우는 기질이며, 관계가 한쪽으로 끌려가지 않는 자기 중심축을 가진 결입니다.',
  ]),
  _Frag.hard((f) => f.fired('L-SN'), [
    '들창코의 결은 관상학에서 "사교의 기(氣)"가 열려 있다고 보는 신호로, 낯선 자리에 섞여드는 속도가 남다르게 빠른 기질입니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('mouth') >= 0.8, [
    '입의 결이 @{intense} 살아 있는 상은 대화의 완급을 자유롭게 조절하는 기질이며, 협상·설득·중재 자리에서 유독 강한 존재감을 냅니다.',
  ]),
  _Frag.hard((f) => f.fired('P-10') || f.nodeZ('eye') >= 0.8, [
    '눈매가 맑게 자리한 상은 "첫인상의 호감"을 만드는 결입니다. 처음 보는 자리에서 경계를 풀어주는 무언의 신호가 됩니다.',
  ]),
  _Frag.hard((f) => f.nodeZ('eyebrow') >= 0.5, [
    '눈썹이 정돈된 상은 관상학에서 "형제궁(兄弟宮)"이 살아 있는 결로, 또래·동료 관계에서 중재자 역할이 자연스럽게 주어지는 기질입니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 관계는 "오래가는 소수"와 "스치듯 지나가는 다수" 사이의 분리가 또렷한 구조로, 시간이 지날수록 핵심 그룹의 밀도가 @{deep} 짙어지는 결을 가졌습니다.',
    '관상학에서 "인화(人和)의 기운"이라 부르는 결—말을 많이 하지 않아도 주변 사람들이 자연스럽게 당신을 중재자 자리에 앉히는 구조입니다. @__STRONGEST_NODE__의 결이 이 인화의 에너지를 받쳐주는 중심축입니다.',
    '당신은 "감정의 완급"을 조절하는 능력이 남보다 반걸음 앞선 결입니다. 상대의 기분을 먼저 읽고 자기 반응의 온도를 맞추는 감각이 자연스럽게 갖춰진 상—이는 사회적 마찰을 미리 줄이는 @{rare} 기질의 신호입니다.',
    '@{palace_home}의 기운이 단단하게 자리잡은 상은 "환대(歡待)의 결"로 읽힙니다. 당신의 공간·시간·정성을 다른 사람에게 열어주는 방식이 남보다 덜 인색한 구조—이것이 장기적으로 관계의 저수지를 깊게 만드는 힘입니다.',
    '당신의 얼굴에는 "약속을 지키는 사람"이라는 무언의 신호가 새겨져 있습니다. 큰 말은 하지 않아도 한 번 한 약속은 반드시 지키는 기질이 골상에 박힌 결—이 신호 하나가 평생 관계의 밀도를 천천히, 그러나 확실하게 쌓아 올립니다.',
  ]),
];

final List<_Frag> _talentAdvice = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '@{talent_word}을 살리는 길은 "판 전체를 보는 눈"과 "앞장서는 발"을 함께 쓰는 자리에 있습니다. 기획과 실행이 한 사람 안에서 도는 구조—창업·사업부·연구 PI 같은 자리—에서 진가가 열립니다. 관상이 아깝게 만드는 경우는 한 가지: 분석만 하거나 앞에만 서거나. 두 축을 같이 쓸 수 있는 무대를 3년 안에 확보해 두십시오.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '"먼저 읽고 뒤에서 설계하는" 결입니다. 참모·전략가·아키텍트 자리에서 최고 밀도. 스포트라이트보다 판 아래 구조를 짜는 쪽이 당신의 결과 맞습니다. 눈에 띄는 성과보다 뒤늦게 "저 사람이 짰구나" 알려지는 패턴이 평생을 따라붙습니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '"깊게 파는" 전문가형 결입니다. 연구·분석·저술처럼 혼자 밀어붙이는 시간에서 결이 가장 두꺼워집니다. 조직 안에서도 리더보다 "그 사람 없으면 안 되는" 전문직 자리로 설계하십시오. 앞에 서야 하는 자리가 길어지면 제 재능이 오히려 빠져나갑니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '"끌고 가는 힘"이 @{talent_word}의 중심입니다. 디테일보다 방향, 논리보다 결단—사람을 움직이는 자리에서 가장 크게 열립니다. 혼자 깊이 파는 직역은 답답함이 쌓이는 구조이므로, 팀·조직·현장 지휘형 커리어로 일찍 방향을 잡으십시오.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '한쪽으로 쏠리지 않은 중용의 결입니다. 판단과 행동 사이의 균형이 강점이라, 어느 자리에 놓여도 그 자리의 언어를 빠르게 흡수합니다. 단기 폭발력은 낮은 대신 3·5·10년의 축적 곡선이 평균을 확실히 뛰어넘습니다. 맞는 판만 골라두면 됩니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '"말보다 손"의 결입니다. 앞에 서서 선언하는 역할보다 한 가지 기술·한 가지 결과물을 정직하게 만들어내는 쪽에서 진가가 드러납니다. 장인·전문 실무·크래프트 트랙이 맞는 결이고, 그 자리에 3년 이상 머물면 평균을 뛰어넘는 깊이가 쌓입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '"판을 직관으로 잡는" 결입니다. 논리적 분석보다 현장 감각으로 결정을 내리는 유형이며, 데이터를 기다리다 놓치는 사람보다 먼저 움직여 기회를 가져옵니다. 분석형 조력자를 옆에 두면 결의 상한이 단번에 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '머리도 발도 극단이 아닌 결입니다. 대신 특정 영역에 반복 노출될 때 그 안에서 남들이 못 보는 패턴을 잡아내는 "현장 지능"이 쌓이는 유형이고, 같은 일을 3년 반복하는 환경이 당신에겐 가장 큰 자산입니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '"손끝·몸·감각"의 결로 자라는 유형입니다. 추상적 판단이나 대규모 지휘보다 몸으로 익히는 기술, 반복으로 쌓이는 솜씨에서 진가가 나옵니다. 평가 축을 바꾸면 결핍이 아니라 방향이 됩니다—숫자가 아닌 결과물의 완성도로 승부하십시오.',
  ]),
  _Frag.hard((f) => true, [
    '@{talent_word}을 살리는 길은 셋입니다. 첫째, @__STRONGEST_NODE__의 결이 가장 @{intense} 작동하는 환경을 일찍 고르십시오. 둘째, 단기 평가에 흔들리지 않는 @{heart}의 중심—남의 속도와 비교하지 않는 훈련이 3년 이후 곡선을 결정합니다. 셋째, 결과물을 외부에 내놓는 정기 루틴. 이 셋이 맞물릴 때 관상이 약속한 천장이 열립니다.',
    '@{talent_word}은 "짚은 방향"과 "들인 시간"의 곱으로만 열립니다. 방향을 잘못 잡은 10년의 근면은 반년의 올바른 방향보다 작은 결실을 만듭니다. 당신의 얼굴에는 방향을 잡는 힘이 이미 들어 있으니, 결정적 방향 선택의 3~5개 순간에 외부 조언을 의도적으로 구하십시오.',
    '당신의 @{talent_word}은 "하나를 10년 파는" 설계에 최적화된 @{structure}입니다. 여러 분야를 얕게 건드리는 방식이 오히려 천장을 낮추는 구조—20대에 방향을 고르고 30대에 10,000시간을 들이는 고전적 루트가 당신에게 가장 정직한 곡선을 그립니다.',
    '관상학이 @{talent_word}을 말할 때 가장 자주 꺼내는 문장: "자기 얼굴의 결을 거스르지 말 것." @__STRONGEST_NODE__의 결을 외면한 채 다른 길을 억지로 걷는 사람은 능력의 20%만 열고 지나가며, 그 결을 따라 길을 짜는 사람은 같은 노력으로 80%를 연다는 @{structure}입니다.',
    '@{talent_word}의 상한을 올리는 단 하나의 조건은 "피드백 루프의 빈도"입니다. 결과를 외부에 꺼내지 않고 혼자 쌓기만 하는 사람은 자기 수준을 모르는 채 늙어가고, 작게라도 자주 내놓는 사람은 평균보다 두 배 빠른 속도로 성장합니다. 첫 공개 시점을 늦추지 마십시오.',
  ]),
];

final List<_BeatPool> _talentBeats = [
  _talentOpening,
  _talentStrength,
  _talentShadow,
  _talentAdvice,
];

// ═══ 1. 타고난 재능 ═══

final List<_Frag> _talentOpening = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '머리와 발이 동시에 굵게 박힌 얼굴입니다. 관상학이 "지장(智將)의 상"이라 부르는 드문 결—판을 먼저 읽고 그 판 위에 직접 올라가 흐름을 돌리는 @{rare} 조합. @{palace_destiny}의 열림과 @{palace_career}의 묵직함이 한 얼굴 안에서 동시에 호흡합니다.',
    '읽는 힘과 끌고 가는 힘이 한 몸에 서린 상. 혼자 사유하는 시간에서 답을 얻고, 사람 앞에 설 때 그 답이 비로소 완성되는 이중 구조가 @{talent_word}의 본체로 작동합니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.mid), [
    '판을 @{observe} 힘은 유난히 두꺼운데, 앞장서는 쪽보다 한 발 뒤에서 구조를 짜는 결입니다. 참모·기획·설계의 자리에서 진짜 힘이 나오는 유형—남이 움직이는 판 위에 숨은 손을 얹어 방향을 바꾸는 @{rare} 기질입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.high, Attribute.leadership, _Band.low), [
    '읽는 눈은 @{intense} 깊고, 앞에 나서는 쪽은 서툴게 열린 결입니다. 연구·분석·저술처럼 깊게 파는 영역에서 밀도가 가장 높아지는 타입—혼자 쌓는 시간이 길수록 결실의 크기가 커집니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.high), [
    '디테일의 분석보다 "방향을 잡는 감"이 @{talent_word}의 중심입니다. @{palace_career}과 @{mount_e}·@{mount_w}이 @{strong_adj} 받쳐주는 상으로, 말하지 않아도 주변이 당신의 결정을 기다리는 무형의 장악력이 얼굴에 @{result_carry}.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.mid), [
    '@{rare} 쏠림 없는 균형의 결입니다. 판단과 실행이 한쪽으로 기울지 않고 함께 호흡하는 상—극단이 없어 화려하지 않지만, 시간의 축 위에 올려놓으면 누구보다 정직하게 쌓여 갑니다.',
    '어떤 자리에 놓여도 그 자리의 언어를 @{intense} 흡수하는 중용의 상. 첫 장면의 인상보다 세 번째 만남 이후 자리잡는 신뢰가 @{talent_word}의 진짜 자산입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.mid, Attribute.leadership, _Band.low), [
    '판의 그림을 조용히 그리는 쪽보다 "손으로 결과를 만들어내는" 쪽에 결이 쏠린 상입니다. 장인·기술·실무의 트랙에서 정직한 결이 쌓이는 타입—반복으로 깊이가 붙는 유형입니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.high), [
    '분석으로 결정을 미루는 사람과 달리 "직관으로 먼저 움직이는" 결입니다. 현장 감각·현장 판단이 살아 있는 상—데이터를 기다리다 놓치는 사람이 아닌 쪽에서 @{intense} 빛납니다.',
  ]),
  _Frag(_bandPair(Attribute.intelligence, _Band.low, Attribute.leadership, _Band.mid), [
    '반복 노출 속에서 @{subtle} 패턴을 잡아내는 "현장 지능"의 결입니다. 학문적 분석이나 대규모 지휘보다, 같은 일을 몇 년 반복하는 환경에서 평균을 넘는 감각이 붙어 오르는 타입입니다.',
  ]),
  _Frag(_lowPair(Attribute.intelligence, Attribute.leadership), [
    '머리의 날카로움이나 통솔력이 무대 중앙이 아니라 조명 바깥쪽에 앉아 있는 결입니다. 손끝·몸·감각으로 자라는 유형—추상적 판단보다 몸으로 익히는 솜씨에서 진가가 드러나는 @{structure}입니다.',
  ]),
  _Frag.hard((f) => true, [
    '@{talent_word}이 한 방향으로 쏠리지 않고 여러 영역에 고루 잠재된 형태입니다. 삼정(三停)이 균형을 이룬 상으로, @__STRONGEST_NODE__의 결이 가장 @{intense} 드러나며 이 부위가 관여하는 영역에서 또래보다 반 걸음 앞서는 감각이 붙어 있습니다.',
    '"결을 타고 쌓이는" 축적형입니다. 한 번의 스파크보다 3년·5년·10년의 결이 겹칠 때 진짜 모습이 드러나며, 같은 일을 다른 각도로 반복할수록 깊이가 @{intense} 붙는 유형입니다.',
    '@{palace_career}의 기운이 큰 쏠림 없이 고르게 퍼진 결입니다. 화려한 한 분야의 천재성보다 여러 영역을 잇는 "연결자(connector)"의 기질—서로 다른 두 세계 사이의 다리 역할에서 가장 크게 열리는 @{rare} 구조가 얼굴에 새겨져 있습니다.',
    '특정 부위가 혼자 튀지 않고 여러 기관이 함께 합주하는 결입니다. 관상학이 "중화(中和)된 기(氣)"라 부르는 상으로, 한 영역의 극단적 성취보다 여러 영역을 묶어내는 감각이 @{talent_word}의 본체로 작동하는 @{structure}입니다.',
    '@__STRONGEST_NODE__이 가장 또렷한 결이면서도 다른 부위가 뒤받쳐 주는 상. 주인공 한 사람과 조연들이 한 무대에서 같이 움직이는 구조—독주보다 합주가 어울리는 기질이 골상에 들어 있어, 팀·조직·협업 속에서 진가가 @{intense} 드러납니다.',
  ]),
];

final List<_Frag> _talentShadow = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '다만 머리와 발이 함께 뛰는 결은 "혼자 다 해야 직성이 풀리는" 피로를 낳기 쉽습니다. 위임이 서툴면 능력의 천장이 본인의 체력에 묶이고, 팀 안에서 동료가 자라나지 못하는 구조적 그림자가 따라옵니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.intelligence) == _Band.high && f.bandOf(Attribute.leadership) == _Band.low, [
    '다만 앞에 나서는 자리가 오래 비어 있으면, 당신이 쌓은 분석과 설계가 다른 사람의 이름으로 옮겨가기 쉽습니다. @{organ_mouth}이 무거운 상의 전형적 그림자로, 의도적 노출 루틴 없이는 실력이 저평가됩니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.intelligence) == _Band.low && f.bandOf(Attribute.leadership) == _Band.high, [
    '다만 직관이 강한 만큼 근거 없는 추진이 사고로 이어지기 쉽습니다. 분석형 조력자를 옆에 두지 않으면 "가는 속도는 빠른데 도착지가 틀리는" 패턴이 반복됩니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 흥미가 이동하는 속도가 빠른 편입니다. 관상학이 "상정 과강(上停過强)"이라 부르는 기질—머리가 먼저 달려가 몸이 따라잡지 못하면 재능이 쌓이지 않고 흩어지는 구조입니다.',
  ]),
  _Frag.hard((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 감수성이 @{deep} 박힌 만큼 비판에 흔들리는 폭도 넓습니다. @{palace_destiny}이 맑으면 탁기도 그대로 비치는 결—외부 피드백을 어떻게 거르는지가 평생의 숙제입니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 당신의 @{talent_word}은 쌓는 시간에 정직하게 비례합니다. 남이 일찍 빛나는 모습에 흔들리면 잠재력이 절반만 열린 채 평생이 흐르기 쉬운 @{structure}입니다.',
    '다만 @__STRONGEST_NODE__에 기운이 @{deep} 실린 만큼 이 부위에만 의지하면 전체 균형이 깨질 수 있습니다. 의식적으로 반대축을 훈련해야 하는 구조입니다.',
    '다만 "보여주는 기술"이 약한 편이라, 실력에 비해 덜 평가되는 패턴이 반복되기 쉽습니다. 의도적 노출 루틴이 이 결점의 유일한 해법입니다.',
    '다만 당신의 @{talent_word}은 "완성도에 집착하는" 결입니다. 70%에서 멈추고 내놓을 줄 모르면, 100%의 결과물이 빛을 보기 전에 유행이 바뀌거나 경쟁자에 자리를 내주는 패턴이 반복되기 쉬운 @{structure}입니다.',
    '다만 "여러 분야를 얕게 건드리는" 유혹이 자주 찾아오는 결입니다. 호기심이 큰 것이 장점이지만, 한 곳을 3년 이상 파지 않은 채 이동만 계속하면 관상이 약속한 천장의 절반도 열지 못하고 평생이 흘러갑니다.',
  ]),
];

final List<_Frag> _talentStrength = [
  _Frag.hard((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 @{intense} 자리잡은 상입니다. @{organ_brow}이 @{strong_adj} 살아 있는 결—새 지식의 초기 흡수 속도가 빠르고, 한 번 방향을 정하면 중간에 꺾이지 않는 @{noble} 집요함이 함께 박혀 있습니다.',
    '짙고 정돈된 눈썹은 "의지의 결"이 @{deep} 박힌 상입니다. 목표가 서면 결실까지 밀어붙이는 기질이 강하게 작동하는 구조입니다.',
  ]),
  _Frag.hard((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '@{open_wide} 반듯한 이마는 관상학이 "천정(天庭) 열림"이라 부르는 상으로, 윗사람의 도움과 윗선의 기회가 먼저 찾아오는 기질을 @{intense} 암시합니다.',
    '이마의 평탄함이 @{strong_adj} 드러나는 상은 초년운과 지도력의 기반이 동시에 열려 있다는 신호로 읽힙니다.',
  ]),
  _Frag.hard((f) => f.fired('O-EM'), [
    '눈과 입의 표현이 함께 살아 있는 구조는 감정을 언어로 정확히 옮기는 @{rare} 재능입니다. 글·강연·연기에서 @{intense} 설득력을 만드는 결입니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 @{strong_adj} 받쳐주는 상은 사람을 부려 일을 만드는 기질입니다. 혼자 잘하는 것보다 조직·팀을 통해 @{talent_word}이 확장되는 유형입니다.',
    '광대가 힘차게 자리한 구조는 @{noble} 호령의 기운을 담습니다. 순수 전문가보다 리더·관리자의 자리에서 진가가 @{intense} 드러납니다.',
  ]),
  _Frag.hard((f) => f.fired('O-FB'), [
    '이마와 턱이 함께 단정한 구조는 "시작과 끝이 정렬된 상"입니다. 한 프로젝트를 처음부터 끝까지 담당했을 때 가장 좋은 결과가 나오는 기질입니다.',
  ]),
  _Frag.hard((f) => f.nodeAZ('nose') >= 1.0, [
    '@{mount_c}이 또렷한 상은 자기 @{path_word}에 대한 확신이 강한 기질이며, 외부 평가에 흔들리지 않고 자기 길을 @{intense} 밀고 나가는 동력이 됩니다.',
  ]),
  _Frag.hard((f) => f.fired('A-02'), [
    '이마 기운의 열림은 "조년발(早年發)"의 신호로, 젊은 시기의 도약이 동년배보다 앞서 찾아오는 기질을 의미합니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 기질은 화려한 한순간의 폭발보다 시간에 정직하게 비례하는 축적형—관상학이 "대기만성(大器晩成)"이라 부르는 결에 가깝습니다.',
    '@__STRONGEST_NODE__의 결이 @{talent_word}의 기폭제 역할을 합니다. 이 부위가 활성화될 때 주변 공기가 당신 쪽으로 기울어지는 상입니다.',
    '"첫 만남의 인상"보다 "세 번째 만남 이후 자리잡는 신뢰"에서 힘이 나오는 유형입니다. 초면의 화력보다 축적된 시간이 자산인 @{structure}입니다.',
    '당신의 얼굴에는 "결과보다 과정을 끝까지 책임지는" 기질이 새겨져 있습니다. 관상학에서 "후덕(厚德)의 결"이라 부르는 상—한 프로젝트의 마지막 20% 잔무를 끝까지 물고 가는 뚝심이 동년배가 가장 부러워하는 자산이 됩니다.',
    '@__STRONGEST_NODE__과 @__SECOND_NODE__가 나란히 자리한 상은 "두 개의 엔진"이 동시에 도는 구조입니다. 한쪽이 지칠 때 다른 쪽이 받치는 복선(複線) 구조—단일 엔진의 사람들보다 피크가 늦게 오지만 정체 구간이 훨씬 짧은 @{rare} 기질입니다.',
  ]),
];

final List<_Frag> _wealthAdvice = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '버는 감각과 지키는 뚝심이 한 몸에 박힌 "대재상(大財相)"의 결입니다. 관상이 약속한 상한은 분명—이 재능을 복리로 돌리려면 자산의 구조에 집중하십시오. 월급보다 매달 자동으로 쌓이는 액수가 진짜 재물의 크기이며, 남의 돈·남의 시간을 다루는 경험이 30대에 들어오면 평생 곡선이 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '기회를 읽는 눈은 @{intense} 날카로운데 지키는 쪽은 평균권인 결입니다. 버는 힘이 강해 손실도 빠르게 복구되는 이점—대신 호황기에 포지션을 키우지 않는 규율이 평생 자산의 크기를 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '재주는 @{intense} 좋은데 담는 그릇이 앞서가는 속도를 따라가지 못하는 결입니다. 손에 남는 것을 늘리려면 "버는 능력"에 투자하지 말고 "자동 저축 시스템"에 투자하십시오. 사람 손을 타지 않는 구조만이 이 결을 지켜 냅니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '"잃지 않는 힘"이 @{strong_adj} 받치는 결입니다. 한 방보다 시간이 자산으로 환원되는 장기 투자·근속 축적·부동산 트랙에서 진가가 드러나는 유형—5년 단위 복리 설계가 평생 재산을 결정합니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '극단 없는 평균의 결입니다. 생활 습관의 축적이 고스란히 자산으로 환원되는 정직한 구조—매달 고정 저축 비율을 수입의 25% 이상으로 자동화해 두는 것만으로 관상이 예고한 @{palace_wealth}의 중상위 상한이 열립니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '버는 감각은 평균인데 감정이 결정에 자주 끼어드는 결입니다. 관계·분위기·충동에 휩쓸린 지출이 쌓이기 쉬운 유형—중대한 금전 결정은 반드시 24시간 묵히는 규칙만 박아 두면 결과의 절반이 달라집니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '돈을 만드는 손은 @{faint} 얇지만 지키는 힘이 @{strong_adj} 받치는 결입니다. 기질로는 근로·전문직·기관 내 장기 근속 트랙이 가장 잘 맞고, 버는 기술보다 쓰지 않는 기술에 투자할 때 말년 자산의 크기가 역전됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '돈을 만드는 결도, 지키는 결도 두껍지 않은 평균형입니다. 대신 생활 습관이 자산에 가장 정직하게 반영되는 유형이라, 자동 이체 저축의 힘이 다른 누구보다 크게 작동하는 구조입니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재물이 인생의 중심축이 아닌 결입니다. 억지로 이 축을 중심에 놓으면 오히려 소모가 크고, 자기 @{talent_word}·관계·경험을 중심에 두고 돈은 그 부산물로 따라오는 구조를 설계할 때 훨씬 나은 곡선이 그려집니다.',
  ]),
  _Frag.hard((f) => true, [
    '재물의 상한을 여는 세 축: 고정 저축의 자동화, 남의 돈·남의 시간을 다루는 경험, 감정 과잉 시점의 결정 보류. 이 셋이 지켜질 때 관상이 예고한 @{palace_wealth}의 잠재력이 순서대로 열립니다.',
    '재물은 "단일 타점"보다 "누적 확률"로 쌓이는 @{structure}입니다. 한 번의 큰 베팅보다 매달 돌아가는 고정 저축의 자동화가 당신의 얼굴 결에 더 잘 맞으며, 5년 누적 시 이 차이가 두 배 이상으로 벌어집니다.',
    '@{palace_wealth}의 본질은 "들어온 돈을 얼마나 오래 머물게 하는가"입니다. 당신의 결에서 가장 먼저 고쳐야 하는 건 버는 기술이 아니라 쓰는 기준—월별 카테고리별 소비 한도를 정하는 규칙 하나가 평생 자산의 크기를 바꿉니다.',
    '돈의 속도를 관상학은 "유입·유지·증식" 셋으로 나눕니다. 당신의 얼굴에 가장 약한 축이 무엇인지 알아내는 것이 먼저—유입이 약하면 수입원을 늘리고, 유지가 약하면 규율을 세우고, 증식이 약하면 복리 자산에 시간을 들이는 @{structure}적 접근이 필요합니다.',
    '당신의 재물 곡선은 "결정적 3~5번의 선택"이 평생 총량의 70%를 결정합니다. 집·직업·사업 파트너 같은 큰 결정 앞에서 서두르지 말고, 평소 10배의 시간을 들여 조사하는 습관 하나가 관상이 약속한 상한을 정직하게 열어 줍니다.',
  ]),
];

final List<_BeatPool> _wealthBeats = [
  _wealthOpening,
  _wealthStrength,
  _wealthShadow,
  _wealthAdvice,
];

// ═══ 2. 재물운 ═══

final List<_Frag> _wealthOpening = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '돈이 머물고 싶어하는 구조가 골상에 새겨진 "대재(大財)"의 결입니다. @{palace_wealth}이 @{strong_adj} 자리하고 @{mount_n}이 함께 받쳐주는 상—버는 감각과 지키는 뚝심이 한 얼굴에 공존하는 @{rare} 조합으로, 사업·투자·운영 어느 경로로 가도 "남기는 사람"이라는 평이 따라붙습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '기회를 잡는 눈이 @{intense} 드러나는 얼굴입니다. @{mount_c}이 또렷하고 @{palace_wealth}의 결이 살아 있는 상—손실 국면에서도 바닥을 확인하는 감각이 반 걸음 빠르고, 한 번에 크게 벌고 크게 잃지 않는 균형 감각이 함께 박혀 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '재주는 @{intense} 드러나는데 지키는 문이 함께 열린 결입니다. 돈을 만드는 눈이 날카로운 대신, 들어오는 속도만큼 나가는 속도도 빠른 유형—"담는 그릇"의 설계가 선결 과제인 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '폭발적 기질은 없되 "잃지 않는 힘"이 @{strong_adj} 받치는 결입니다. 한 방의 큰 부보다 꾸준히 쌓아 올리는 누적형—시간을 편으로 돌려세우는 영역에서 @{intense} 드러나는 @{structure}입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '재물운이 극단 없이 평균대 위에 단정하게 놓인 결입니다. @{palace_wealth}이 @{gentle} 열려 있고 턱이 적당히 받치는 상—생활 습관이 자산에 고스란히 누적되는 정직한 구조입니다.',
    '조용히 불어나는 결입니다. 위험을 무릅쓰는 기개는 @{faint} 얇아도 잃지 않는 힘이 평균 이상—근로·자영업·장기 투자처럼 기다림이 자산으로 환원되는 종목에서 진가가 드러납니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '버는 감각은 평균권인데 감정이 금전 결정에 자주 끼어드는 결입니다. 판단 자체는 틀리지 않는데 타이밍이 흔들리는 구조—"머리는 맞고 마음이 먼저 움직이는" 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '재물운의 핵심 축이 "버는" 쪽보다 "지키는" 쪽에 놓인 결입니다. 돈을 새로 만들어내는 기질은 @{faint} 얇아도 한 번 들어온 것은 좀처럼 흘려보내지 않는 구조—근로·전문직·장기 근속 트랙에 가장 잘 맞는 유형입니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '재물의 기질이 두드러지지 않고 감정의 진폭도 크지 않은 결입니다. @{palace_wealth}이 @{subtle} 가볍게 드러나는 상—기질의 한계는 분명하되 시스템으로 보완하면 전혀 다른 곡선이 그려지는 유형입니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재물이 인생의 중심축이 아닌 결입니다. 관상학에서 "입은 있되 곳간이 얇은 상"이라 부르는 유형—수양과 구조 설계로 가장 크게 바뀌는 영역이므로 기질의 경향을 인정하되 갇히지 않는 태도가 가장 중요합니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 재물운은 평균대 위에서 단단한 결을 유지하는 @{structure}입니다. 30대부터 들이는 재물 자산의 총량이 말년 곡선의 기울기를 그대로 결정하는 정직한 구조입니다.',
    '@{palace_wealth}이 쏠림 없이 차분하게 자리한 결입니다. 화려한 발복(發福)보다 꾸준한 축적에서 진가가 드러나는 유형으로, 누적 시간이 평생 재산의 규모를 그대로 반영하는 @{structure}입니다.',
    '관상학이 "정재(正財)의 결"이라 부르는 상입니다. 큰 한 방보다 성실한 반복으로 재물을 쌓는 기질—근로·장기 저축·부동산 같은 정직한 트랙에서 평균 이상의 결실이 붙는 @{rare} 구조가 얼굴에 새겨져 있습니다.',
    '@{mount_c}이 균형 있게 자리잡은 상. 재물에 대한 집착이 과하지도 얕지도 않은 중용의 결이라, 감정이 판단에 끼어드는 지점이 상대적으로 적고 장기 복리가 작동하기 좋은 구조입니다.',
    '당신의 재물 결은 "큰 행운"에 기대지 않고 "작은 정직"에 누적되는 @{structure}입니다. 관상학이 40~50대에 말하는 "중년의 발복(發福)"이 가장 자연스럽게 들어오는 유형—조급함 없이 시간을 자산으로 환원하는 훈련이 평생의 후복을 결정합니다.',
  ]),
];

final List<_Frag> _wealthShadow = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '다만 "잘 버는데 잘 안 쓰는" 결이 굳어지면 관계 안에서 인색함으로 비쳐 자산의 크기에 비해 후복이 얇아지기 쉽습니다. 돈과 정(情)을 함께 쓰는 설계가 있어야 재물운이 다음 세대까지 이어집니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '다만 들어오는 문 옆에 나가는 문이 함께 열린 형국입니다. 관상학이 "수입을 늘리는 노력보다 새는 구멍을 먼저 막는 설계가 훨씬 큰 효과를 만든다"고 일러주는 전형적 결입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '다만 재물 판단 위에 감정이 먼저 덧씌워지는 위험이 따릅니다. 관계·분위기에 휩쓸린 지출이나 무리한 보증·투자에 발을 들이기 쉬운 구조—큰 결정은 반드시 24시간 묵혀야 위험의 절반이 사라집니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '다만 호황기에 들뜨기 쉬운 결입니다. 좋은 흐름이 올 때마다 포지션을 키워 나쁜 구간의 낙차가 평균보다 넓어지는 패턴—호황기의 확장을 나쁜 시기의 완충으로 얼마나 잘 바꾸는지가 평생 재산의 크기를 결정합니다.',
  ]),
  _Frag.hard((f) => true, [
    '다만 당신의 @{structure}에는 "갑작스러운 유혹"에 취약한 구간이 주기적으로 돌아옵니다. 그 구간을 미리 이름 붙여 두면, 같은 유혹이 찾아와도 결정이 달라집니다.',
    '다만 재물에 관한 결정은 "혼자 있는 시간"보다 "남과 있는 시간"에 더 자주 망가지는 결입니다. 분위기·체면·관계의 압박 아래서 내린 지출·투자·보증이 평생 총량의 가장 큰 누수가 되기 쉬운 @{structure}—큰 결정은 반드시 혼자 하룻밤을 묵히고 내려야 합니다.',
    '다만 당신의 재물운은 "들어올 때의 크기"보다 "빠져나갈 때의 크기"가 더 넓게 열린 결입니다. 관상학이 "누기(漏氣)"라 부르는 상—작은 새는 구멍 여럿이 모여 한 해 총 순유입의 상당 부분을 갉아먹는 구조이니, 고정비·구독·소액 지출을 주기적으로 점검하는 습관이 결정적 방어선입니다.',
    '다만 재물 곡선 위에 "자신감이 꺾이는 구간"이 몇 차례 돌아오는 결입니다. 한 번의 큰 손실 뒤 "나는 돈과 안 맞는 사람"이라는 단정으로 자산 설계를 포기하기 쉬운 유형—한 번의 실패로 기질을 재단하지 말고, 규칙을 고치되 구조는 지키는 쪽으로 방향을 잡으십시오.',
    '다만 당신의 결은 "성공 뒤의 확장"이 가장 위험한 구간입니다. 작은 성공 이후 포지션을 키우려는 충동이 커지기 쉬운 유형—가장 돈을 많이 잃는 순간은 가장 돈을 많이 번 직후라는 관상학의 고전적 경고가 당신에게 특히 유효합니다.',
  ]),
];

final List<_Frag> _wealthStrength = [
  _Frag.hard((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '@{mount_c}이 @{strong_adj} 자리잡은 구조는 관상학이 "중년발복(中年發福)"이라 부르는 신호—30대 후반에서 40대 사이에 재물의 꼭짓점이 찾아오는 기질을 @{intense} 암시합니다.',
  ]),
  _Frag.hard((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 힘차게 받쳐주는 구조는 사람을 부려 돈을 만드는 기질입니다. 순수 근로보다 운영·관리·조직으로 부를 키우는 길이 @{intense} 잘 맞습니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '@{mount_n}이 @{strong_adj} 두터운 구조는 "말년재운"의 상징입니다. 50대 이후에도 재물의 뿌리가 마르지 않고 오히려 @{deep} 깊어지는 후복(後福)의 결입니다.',
  ]),
  _Frag.hard((f) => f.fired('Z-11'), [
    '중정의 기운이 @{intense} 열린 상은 중년 집중 발복의 신호로, 가장 큰 결실이 인생의 중간에 집결되는 리듬을 뜻합니다.',
  ]),
  _Frag.hard((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입의 결이 함께 살아 있는 구조는 "수입과 지출을 모두 통제하는 상"으로, 새는 구멍도 스스로 관리하는 @{rare} 기질을 뒷받침합니다.',
  ]),
  _Frag.hard((f) => true, [
    '당신의 재물 곡선은 단기보다 장기에서 진가가 드러나는 @{structure}이며, 5년 단위로 돌아보는 습관이 붙을 때 가장 크게 늘어납니다.',
    '@__STRONGEST_NODE__의 결이 재물의 흐름에 직접 개입하는 상입니다. 이 부위가 빛날 때 외부에서 들어오는 기회의 폭이 넓어지는 유형—자기 얼굴의 가장 좋은 결이 보이도록 관리하는 습관이 관상학적 재물 레버리지입니다.',
    '관상학에서 "재기(財氣)가 얼굴 전체에 고르게 깔린 상"이라 부르는 결입니다. 한 분야에 몰빵하지 않고 여러 소득원이 함께 돌아가는 구조가 자연스럽게 맞는 기질—"N잡"의 시대와 결이 일치하는 @{rare} 유형입니다.',
    '@{palace_wealth}과 @{palace_home}이 나란히 자리한 상은 "재물과 가정이 함께 움직이는" 구조입니다. 혼자 버는 돈보다 가족·배우자와 함께 설계한 자산 흐름에서 진짜 복리가 작동하는 결—재무 설계를 파트너와 공유하는 루틴이 평생 총량을 결정합니다.',
    '당신의 얼굴에는 "돈을 오래 머물게 하는" 무언의 기운이 자리합니다. 소비의 우선순위가 비교적 또렷한 기질이라, 충동적 지출이 남보다 적고, 남은 것을 복리로 굴릴 수 있는 구조가 자연스럽게 열리는 @{structure}입니다.',
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

double _lo(double s) {
  if (s <= 5.0) return 1.0;
  if (s >= 6.5) return 0.0;
  return (6.5 - s) / 1.5;
}

double _mi(double s) {
  final rest = 1.0 - _hi(s) - _lo(s);
  return rest < 0 ? 0.0 : rest;
}

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

_WeightFn _bandPair(Attribute a, _Band ba, Attribute b, _Band bb) =>
    (f) => _bandWeight(f.scoreOf(a), ba) * _bandWeight(f.scoreOf(b), bb);

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
  final yinYang = computeYinYang(zMap);

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
  );
}

String _genderedKey(String key, _Features f) {
  // _m / _f / _g 접미 pool 자동 선택
  if (_slotPools.containsKey('${key}_g')) {
    return f.isMale ? '${key}_m' : '${key}_f';
  }
  return key;
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

_WeightFn _lowOf(Attribute a) => (f) => _lo(f.scoreOf(a));

_WeightFn _lowPair(Attribute a, Attribute b) =>
    (f) => _lo(f.scoreOf(a)) * _lo(f.scoreOf(b));

_WeightFn _metHi(String id) => (f) => _softHiZ(f.mz(id));

_WeightFn _metLo(String id) => (f) => _softLoZ(f.mz(id));

_WeightFn _metMid(String id) => (f) => _softMidZ(f.mz(id));

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
      .replaceAll('@__DOMINANT_PALACE__', f.dominantPalace);
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
  });

  bool get isMale => gender == Gender.male;
  _Band bandOf(Attribute a) => bands[a] ?? _Band.mid;
  bool fired(String id) => firedRules.contains(id);
  double mz(String id) => metricZ[id] ?? 0.0;
  double nodeAZ(String id) => nodeAbsZ[id] ?? 0.0;
  double nodeZ(String id) => nodeOwnZ[id] ?? 0.0;
  double scoreOf(Attribute a) => scores[a] ?? 7.0;
}

// ─── Fragment + Picker ──────────────────────────────────────────────────

typedef _WeightFn = double Function(_Features);

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

