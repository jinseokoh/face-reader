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

/// Attribute 약할 때 한 줄 약점 문장 (hero 카드 약점 줄).
/// 솔직한 약점 평가 톤 — 미화·완곡 금지, strength line 과 대칭 구조.
const attributeShadowLine = <Attribute, String>{
  Attribute.wealth: '돈을 모으고 굴리는 자장이 약하다',
  Attribute.leadership: '결정의 무게를 짊어지면 호흡이 흔들린다',
  Attribute.intelligence: '복잡한 정보를 정리하는 회로가 약하다',
  Attribute.sociability: '낯선 자리에서 자기 자리를 못 찾는다',
  Attribute.emotionality: '분위기와 감정을 한 박자 늦게 읽는다',
  Attribute.stability: '작은 일에도 출렁이고 회복이 느리다',
  Attribute.sensuality: '곁에 있어도 끌림이 잘 만들어지지 않는다',
  Attribute.trustworthiness: '한 약속을 끝까지 지키는 결이 약하다',
  Attribute.attractiveness: '첫인상에서 호감이 잘 만들어지지 않는다',
  Attribute.libido: '에너지의 총량이 부족해 주변을 못 깨운다',
};

/// Attribute 강할 때 chip 키워드 (TL;DR 칩 그리드).
const attributeChipHigh = <Attribute, String>{
  Attribute.wealth: '#재물복',
  Attribute.leadership: '#리더감',
  Attribute.intelligence: '#명석함',
  Attribute.sociability: '#인싸기운',
  Attribute.emotionality: '#감수성',
  Attribute.stability: '#멘탈갑',
  Attribute.sensuality: '#끌림강함',
  Attribute.trustworthiness: '#신뢰감',
  Attribute.attractiveness: '#미모',
  Attribute.libido: '#뜨거움',
};

/// Attribute 약할 때 chip 키워드 (TL;DR 약점 칩).
/// 솔직한 약점 평가 톤 — 애둘러 미화하지 않음.
const attributeChipLow = <Attribute, String>{
  Attribute.wealth: '#재물복약함',
  Attribute.leadership: '#결단력약함',
  Attribute.intelligence: '#판단력약함',
  Attribute.sociability: '#사교성약함',
  Attribute.emotionality: '#공감둔감',
  Attribute.stability: '#멘탈약함',
  Attribute.sensuality: '#끌림약함',
  Attribute.trustworthiness: '#신뢰약함',
  Attribute.attractiveness: '#호감약함',
  Attribute.libido: '#기력약함',
};
