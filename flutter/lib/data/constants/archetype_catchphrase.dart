import 'package:face_reader/data/enums/attribute.dart';

/// Archetype × 한 줄 catchphrase. hero 카드 / 공유 카드 / TL;DR 표지.
///
/// 본문이 길어 안 읽히는 유저를 위해 "스크롤 0"에서 끝나는 임팩트 한 줄.
const archetypeCatchphrase = <Attribute, String>{
  Attribute.wealth: '돈이 자연스럽게 모이는 손 — 흐름을 읽는다',
  Attribute.leadership: '앞에 서면 무리가 따라온다 — 결정의 무게를 진다',
  Attribute.intelligence: '답이 먼저 보이는 머리 — 복잡한 걸 단순하게 본다',
  Attribute.sociability: '어디서나 5분이면 자기 자리 — 모두를 자기편으로 만든다',
  Attribute.emotionality: '분위기를 가장 먼저 읽는다 — 말 안 해도 안다',
  Attribute.stability: '큰일에도 흔들리지 않는 닻 — 폭풍 속에서 더 또렷하다',
  Attribute.sensuality: '곁에 있으면 자꾸 끌린다 — 시선이 머무는 자리',
  Attribute.trustworthiness: '한 번 한 약속을 끝까지 지킨다 — 등을 맡길 수 있는 사람',
  Attribute.attractiveness: '보기만 해도 호감이 간다 — 첫인상이 곧 답이다',
  Attribute.libido: '에너지가 넘쳐 주변까지 깨운다 — 살아있음을 누린다',
};

/// Attribute 강할 때 한 줄 강점 문장 (hero 카드 STRENGTH 줄).
const attributeStrengthLine = <Attribute, String>{
  Attribute.wealth: '돈의 흐름이 자연스럽게 모인다',
  Attribute.leadership: '결정의 무게를 자기가 진다',
  Attribute.intelligence: '복잡한 것을 단순하게 본다',
  Attribute.sociability: '낯선 자리도 5분이면 자기 자리',
  Attribute.emotionality: '말 안 해도 분위기를 읽는다',
  Attribute.stability: '큰일에도 호흡이 흐트러지지 않는다',
  Attribute.sensuality: '존재만으로 공기가 따뜻해진다',
  Attribute.trustworthiness: '한 번 한 약속은 끝까지 간다',
  Attribute.attractiveness: '첫인상이 곧 호감이다',
  Attribute.libido: '에너지가 넘쳐 주변까지 깨운다',
};

/// Attribute 약할 때 한 줄 단점 문장 (hero 카드 단점 줄).
const attributeShadowLine = <Attribute, String>{
  Attribute.wealth: '돈보다 가치가 먼저인 타입',
  Attribute.leadership: '앞보다 옆에서 더 잘 빛나는 타입',
  Attribute.intelligence: '머리보다 가슴이 먼저 움직이는 타입',
  Attribute.sociability: '많은 자리보다 깊은 한 자리가 편한 타입',
  Attribute.emotionality: '감정보다 사실을 먼저 보는 타입',
  Attribute.stability: '파도처럼 출렁이며 살아있음을 느끼는 타입',
  Attribute.sensuality: '담백하게 거리를 지키는 타입',
  Attribute.trustworthiness: '얽매이지 않는 자유로운 타입',
  Attribute.attractiveness: '시선보다 내공이 먼저인 타입',
  Attribute.libido: '차분히 자기 속도를 지키는 타입',
};

/// Attribute 강할 때 chip 키워드 (TL;DR 칩 그리드).
const attributeChipHigh = <Attribute, String>{
  Attribute.wealth: '#재물복',
  Attribute.leadership: '#리더감',
  Attribute.intelligence: '#명석함',
  Attribute.sociability: '#인싸기운',
  Attribute.emotionality: '#감수성',
  Attribute.stability: '#멘탈갑',
  Attribute.sensuality: '#끌림',
  Attribute.trustworthiness: '#신뢰감',
  Attribute.attractiveness: '#미모',
  Attribute.libido: '#뜨거움',
};

/// Attribute 약할 때 chip 키워드 (단점이 아닌 캐릭터 한 면).
const attributeChipLow = <Attribute, String>{
  Attribute.wealth: '#가치우선',
  Attribute.leadership: '#서포터형',
  Attribute.intelligence: '#직관파',
  Attribute.sociability: '#1대1형',
  Attribute.emotionality: '#이성파',
  Attribute.stability: '#감정파도',
  Attribute.sensuality: '#담백파',
  Attribute.trustworthiness: '#자유영혼',
  Attribute.attractiveness: '#개성파',
  Attribute.libido: '#쿨한타입',
};
