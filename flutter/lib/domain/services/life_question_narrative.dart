import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

// ═══════════════════════════════════════════════════════════════════════
// 인생 질문 서술 엔진 v2 — Beat-Fragment Grammar + Face Hash Seed
//
// 섹션 = N beat 의 합. 각 beat 는 feature-activated fragment pool 에서
// face-hash seed 로 변형을 결정적으로 선택. 각 fragment 안에는
//   @{slotName}        — lexical pool 치환
//   {a|b|c}            — 인라인 alternation
// 이 embed 되어 있어 같은 조건·같은 variant 안에서도 slot 곱셈으로
// 수만 가지 결과가 나온다. 같은 얼굴 → 같은 결과 (재현성 보장).
//
// 목표 평균 길이: 섹션당 600자 내외.
// ═══════════════════════════════════════════════════════════════════════

String assembleLifeQuestions(FaceReadingReport r) {
  final f = _extractFeatures(r);
  final parts = <MapEntry<String, String>>[
    MapEntry('타고난 재능', _buildSection(f, _talentBeats, 10)),
    MapEntry('재물운', _buildSection(f, _wealthBeats, 20)),
    MapEntry('대인관계', _buildSection(f, _socialBeats, 30)),
    MapEntry('연애운', _buildSection(f, _romanceBeats, 40)),
  ];
  if (f.age.isOver20) {
    parts.add(MapEntry('바람기', _buildSection(f, _philanBeats, 50)));
  }
  if (f.age.isOver30) {
    parts.add(MapEntry('색기', _buildSection(f, _sensualBeats, 60)));
  }
  parts.add(MapEntry('건강과 수명', _buildSection(f, _healthBeats, 70)));
  parts.add(MapEntry('종합 조언', _buildSection(f, _conclusionBeats, 80)));
  return parts.map((e) => '## ${e.key}\n${e.value}').join('\n\n');
}

// ─── Features ────────────────────────────────────────────────────────────

enum _Band { high, mid, low }

_Band _band(double s) {
  if (s >= 8.0) return _Band.high;
  if (s >= 6.5) return _Band.mid;
  return _Band.low;
}

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
  final String strongestNode;
  final String? specialArchetype;
  final String primaryArchetype;
  final String secondaryArchetype;
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
    required this.strongestNode,
    required this.specialArchetype,
    required this.primaryArchetype,
    required this.secondaryArchetype,
    required this.seed,
  });

  _Band bandOf(Attribute a) => bands[a] ?? _Band.mid;
  double scoreOf(Attribute a) => scores[a] ?? 7.0;
  double nodeZ(String id) => nodeOwnZ[id] ?? 0.0;
  double nodeAZ(String id) => nodeAbsZ[id] ?? 0.0;
  bool fired(String id) => firedRules.contains(id);
  bool get isMale => gender == Gender.male;
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
  String strongest = 'face';
  double maxZ = -1;
  r.nodeScores.forEach((nid, ev) {
    nodeOwnZ[nid] = ev.ownMeanZ;
    nodeAbsZ[nid] = ev.ownMeanAbsZ;
    if (ev.ownMeanAbsZ > maxZ) {
      maxZ = ev.ownMeanAbsZ;
      strongest = nid;
    }
  });

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
    strongestNode: strongest,
    specialArchetype: r.archetype.specialArchetype,
    primaryArchetype: r.archetype.primaryLabel,
    secondaryArchetype: r.archetype.secondaryLabel,
    seed: _computeSeed(r),
  );
}

int _computeSeed(FaceReadingReport r) {
  int h = 1469598103;
  for (final m in r.metrics.values) {
    h = (h * 1099511628 + (m.rawValue * 1000000).round()) & 0x3FFFFFFF;
    h = (h * 31 + (m.zScore * 10000).round()) & 0x3FFFFFFF;
  }
  r.attributes.forEach((k, v) {
    h = (h * 17 + k.index) & 0x3FFFFFFF;
    h = (h * 13 + (v.normalizedScore * 1000).round()) & 0x3FFFFFFF;
  });
  r.nodeScores.forEach((k, v) {
    h = (h * 7 + (v.ownMeanZ * 10000).round()) & 0x3FFFFFFF;
    h = (h * 11 + (v.ownMeanAbsZ * 10000).round()) & 0x3FFFFFFF;
  });
  return h & 0x7FFFFFFF;
}

// ─── Fragment + Picker ──────────────────────────────────────────────────

class _Frag {
  final bool Function(_Features) applies;
  final List<String> variants;
  const _Frag(this.applies, this.variants);
}

typedef _BeatPool = List<_Frag>;

String _pickBeat(_BeatPool pool, _Features f, int beatSalt) {
  final valid = pool.where((fr) => fr.applies(f)).toList();
  if (valid.isEmpty) return '';
  final beatSeed = (f.seed ^ (beatSalt * 2654435761)) & 0x7FFFFFFF;
  final frag = valid[beatSeed % valid.length];
  final variantSeed = (beatSeed ^ 0x1DEA1BEE) & 0x7FFFFFFF;
  final chosen = frag.variants[variantSeed % frag.variants.length];
  return _resolveText(chosen, f, beatSeed);
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

String _resolveText(String text, _Features f, int seed) {
  var t = text;
  // Step 0: runtime placeholders (archetype labels from report)
  t = t
      .replaceAll('@__PRIMARY_ARCHETYPE__', f.primaryArchetype)
      .replaceAll('@__SECONDARY_ARCHETYPE__', f.secondaryArchetype)
      .replaceAll('@__SPECIAL_ARCHETYPE__', f.specialArchetype ?? '특별 관상');
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

String _genderedKey(String key, _Features f) {
  // _m / _f / _g 접미 pool 자동 선택
  if (_slotPools.containsKey('${key}_g')) {
    return f.isMale ? '${key}_m' : '${key}_f';
  }
  return key;
}

// ─── Slot Pools (lexical variety) ────────────────────────────────────────

const Map<String, List<String>> _slotPools = {
  'intense': ['뚜렷이', '선명하게', '또렷이', '분명하게', '진하게', '짙게'],
  'faint': ['은은히', '잔잔히', '고요히', '여리게', '희미하게'],
  'noble_g': [], // gender 분기 — _m, _f 사용
  'noble_m': ['대장부(大丈夫)의', '장부의', '지장(智將)의', '군자의', '호방한', '당당한'],
  'noble_f': ['여중군자(女中君子)의', '품격 있는', '단아한', '기품 있는', '우아한', '고상한'],
  'person_g': [],
  'person_m': ['장부', '대장부', '군자', '사내'],
  'person_f': ['여인', '규수', '여중군자', '안주인'],
  'rare': ['드물게도', '남달리', '유난히', '보기 드물게', '특별히', '귀하게'],
  'observe': ['읽어내는', '꿰뚫어 보는', '짚어내는', '알아차리는', '가늠하는', '헤아리는'],
  'act': ['밀어붙이는', '결단하는', '앞장서는', '이끌어 가는', '움직이는', '뚫고 나가는'],
  'gentle': ['섬세한', '부드러운', '유연한', '결이 고운', '차분한', '세심한'],
  'strong_adj': ['단단한', '묵직한', '듬직한', '굳건한', '우직한', '견실한'],
  'open_wide': ['넓게', '시원하게', '훤히', '환하게', '크게'],
  'clear_adj': ['맑게', '밝게', '환하게', '탁 트인 듯'],
  'deep': ['깊이', '깊숙이', '두텁게', '짙게'],
  'subtle': ['은근한', '은밀한', '잔잔한', '고요한', '차분한'],
  'structure': ['구조', '골상', '관상', '기질', '상(相)'],
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
  'fortune_word': ['복록(福祿)', '관록(官祿)', '재록(財祿)', '복덕(福德)', '정록(正祿)'],
  'result_shine': ['돋보입니다', '빛납니다', '두드러집니다', '또렷합니다', '드러납니다'],
  'result_carry': ['실려 있습니다', '담겨 있습니다', '배어 있습니다', '서려 있습니다'],
  'heart': ['마음', '심지(心志)', '속결', '정(情)', '흉중(胸中)'],
  'talent_word': ['재능', '기질', '천품(天稟)', '타고난 결', '본래의 그릇'],
  'fate_word': ['인연', '운(運)', '복(福)', '명(命)'],
  'path_word': ['길', '행로(行路)', '걸음', '도정(道程)'],
};

// ═══════════════════════════════════════════════════════════════════════
// 섹션별 beat pool — 각 beat 는 feature-activated fragment 리스트.
// 마지막 fragment 는 항상 fallback (applies = (_) => true).
// ═══════════════════════════════════════════════════════════════════════

// Helper predicates
bool Function(_Features) _highOf(Attribute a) =>
    (f) => f.bandOf(a) == _Band.high;
bool Function(_Features) _lowOf(Attribute a) =>
    (f) => f.bandOf(a) == _Band.low;
bool Function(_Features) _highPair(Attribute a, Attribute b) =>
    (f) => f.bandOf(a) == _Band.high && f.bandOf(b) == _Band.high;

// ═══ 1. 타고난 재능 ═══

final List<_Frag> _talentOpening = [
  _Frag(_highPair(Attribute.intelligence, Attribute.leadership), [
    '당신의 얼굴에는 지략(智略)과 통솔이 한 몸에 깃든 기운이 @{intense} 흐릅니다. 관상학에서 @{palace_destiny}이 @{open_wide} 열리고 @{zone_up}이 @{strong_adj} 자리한 상으로, 머리로 @{observe} 힘과 앞장서 @{act} 힘이 한 얼굴에 공존하는 @{rare} @{structure}입니다.',
    '@{noble_m} 지략과 통솔이 겹쳐 흐르는 상입니다. 관상학에서 @{palace_destiny}이 @{clear_adj} 열리고 @{palace_career}이 @{strong_adj} 자리한 상으로, 문(文)과 무(武)의 경계를 넘나드는 @{rare} 기질이 얼굴의 중심축을 이룹니다.',
    '지장(智將)의 결이 @{intense} 드러나는 얼굴입니다. @{palace_destiny}의 열림과 @{palace_career}의 위엄이 함께 살아 있어, 혼자 사유하는 시간에서 길을 얻고 사람 앞에 설 때 비로소 완성되는 이중 동력을 타고났습니다.',
  ]),
  _Frag(_highPair(Attribute.intelligence, Attribute.emotionality), [
    '당신의 @{talent_word}은 \'꿰뚫는 머리\'와 \'읽는 마음\'이 함께 흐르는 @{rare} 결입니다. @{palace_destiny}과 눈매의 {정|수기|결}이 동시에 살아 있어, 같은 자리를 두 겹의 감각으로 @{observe} 힘이 있습니다.',
    '지성과 감수성이 한 얼굴에 겹쳐 있는 @{structure}입니다. 머리로 판단하되 결론을 감정의 온도로 다듬어 전달하는 기질로, 분석이 차갑지 않고 공감이 얕지 않은 @{rare} 균형이 @{talent_word}의 뿌리가 됩니다.',
  ]),
  _Frag(_highOf(Attribute.intelligence), [
    '당신이 타고난 가장 @{intense} 드러나는 @{talent_word}은 \'읽는 힘\'입니다. 관상학에서 @{zone_up}의 천정(天庭)과 @{palace_destiny}이 @{clear_adj} 열린 상으로, 표면을 넘어 그 뒤의 {맥락|의도|흐름}을 @{observe} 통찰이 @{deep} 자리잡았습니다.',
    '당신의 @{talent_word}은 \'꿰뚫어 보는 눈\'에 집약되어 있습니다. @{palace_destiny}이 @{clear_adj} 열려 있어, {사건|상황|국면}의 한가운데서 흐름을 먼저 @{observe} {감각|기질|결}이 또래보다 한 발 앞섭니다.',
    '당신의 @{heart}에는 \'앞을 내다보는 눈\'이 @{intense} 새겨져 있습니다. 남들이 뒤늦게 깨닫는 흐름을 당신은 그 한가운데서 이미 @{observe} 기질이며, 공부·기획·분석 어느 길로 가도 가장 믿을 만한 무기가 됩니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '당신의 @{talent_word}은 사람을 \'움직이게 하는 힘\'입니다. 관상학에서 @{palace_career}과 @{mount_e}·@{mount_w}이 @{strong_adj} 자리한 상으로, 말하지 않아도 주변이 당신의 결정을 기다리게 되는 무형의 장악력이 얼굴에 @{result_carry}.',
    '@{noble_m} 통솔의 기운이 @{intense} 서린 얼굴입니다. @{palace_career}의 위엄과 턱의 무게가 함께 살아 있어, 회의실의 침묵을 깨는 결단이나 흔들리는 팀을 한 방향으로 정렬시키는 호령이 당신 @{talent_word}의 중심이 됩니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '당신의 @{talent_word}은 감수성의 깊이에서 발화합니다. 눈매에 수기(水氣)가 흐르고 입매의 표현이 풍부한 상으로, 남이 무심코 흘리는 기색을 당신은 피부로 @{observe} 감각이 @{deep} 박혀 있습니다.',
    '감정의 결을 @{observe} 힘이 당신 @{talent_word}의 뿌리입니다. 예술·상담·디자인처럼 \'마음을 옮겨 담는\' 일에서 @{intense} 빛나는 기질이며, 머리로만 굴리는 사람이 흉내 낼 수 없는 @{gentle} 결이 진짜 자산이 됩니다.',
  ]),
  _Frag(_highOf(Attribute.attractiveness), [
    '당신의 @{talent_word}은 존재감 그 자체에 있습니다. 오관(五官)의 균형이 잡히고 골격의 비례가 정돈된 상으로, 같은 공간에 있을 때 시선의 무게 중심이 자연스럽게 당신 쪽으로 기울어지는 기질이 타고났습니다.',
    '\'있는 것만으로 기운이 모이는\' 유형입니다. 말투·자세·표정의 흐름이 한 줄기로 정렬되어 있을 때 나오는 일관된 매력이 당신의 @{talent_word}이며, 사람 앞에 서는 모든 직역에서 지렛대 하나를 더 가지고 시작합니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '당신의 @{talent_word}은 관계를 엮어내는 손끝에 있습니다. @{palace_social}이 @{open_wide} 열리고 입매가 @{gentle} 상으로, 이질적인 사람들 사이에 자연스러운 다리를 놓는 감각이 몸에 배어 있습니다.',
    '사람을 모으는 기운이 @{intense} 서린 얼굴입니다. 애써 설득하지 않아도 사람들이 당신 곁에서 무장해제되는 편안함이 최대 강점이며, 영업·중개·상담처럼 \'사람 자체가 자산\'인 영역에서 @{talent_word}이 @{intense} 확장됩니다.',
  ]),
  _Frag(_highOf(Attribute.wealth), [
    '당신의 @{talent_word}은 \'손으로 돈을 만드는 감각\'에 모여 있습니다. @{palace_wealth}이 @{strong_adj} 자리한 상으로, 같은 기회를 만나도 남기는 쪽을 먼저 짚어내는 실물 감각이 남다릅니다.',
    '수(數)를 읽는 눈이 @{intense} 드러나는 얼굴입니다. @{mount_c}과 @{palace_wealth}의 결이 함께 살아 있어, 계산·판매·운영 어디에 두어도 \'굴리면 불어난다\'는 평이 따라붙는 기질입니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '당신의 @{talent_word}은 지구력과 뚝심에 있습니다. @{mount_n}이 @{strong_adj} 받치고 @{zone_down}이 @{open_wide} 자리한 상으로, 한 우물을 끝까지 파서 결실로 만드는 @{noble_m} 기질이 골상에 박혀 있습니다.',
    '@{strong_adj} 근성이 @{intense} 서린 얼굴입니다. 화려하진 않되 중도에 꺾이지 않는 결을 타고났기에, 시간을 편으로 돌려세우는 종목에서 평균을 뛰어넘는 결과를 만들어냅니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 @{talent_word}은 \'믿음을 주는 힘\'에 있습니다. @{palace_home}과 @{palace_servant}이 @{strong_adj} 자리한 상으로, 말과 행동이 일치하는 결이 얼굴에 먼저 새겨져 있습니다.',
    '@{noble_m} 신의(信義)가 @{intense} 드러나는 얼굴입니다. 화려한 말재주가 아니라 한결같은 성품으로 사람을 움직이는 유형이며, 이는 관리직·중개·참모 역할에서 @{intense} 빛납니다.',
  ]),
  _Frag((f) => true, [
    '당신의 @{talent_word}은 한 방향으로 편중되지 않고 여러 영역에 고루 잠재된 형태입니다. 삼정(三停)이 균형을 이루고 극단적으로 치우치지 않은 상으로, 어떤 자리에 들어가도 그 자리의 언어를 @{intense} 흡수해 맞춰가는 적응력이 @{talent_word}의 본체입니다.',
    '겉보기엔 @{subtle} 평범해 보이지만, 오래 지켜본 사람일수록 진가를 알아보는 \'늦게 피는 꽃\'의 기질입니다. 중용의 결이 @{deep} 박혀 있어, 시기가 무르익을수록 @{intense} 드러나는 @{talent_word}을 가졌습니다.',
  ]),
];

final List<_Frag> _talentStrength = [
  _Frag((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 @{intense} 자리잡은 당신은 @{organ_brow}이 @{strong_adj} 살아 있는 상이라, 새 지식을 익히는 초기 속도가 또래보다 한 발 빠르고 @{heart}이 중간에 꺾이지 않는 @{noble_m} 집요함까지 갖추었습니다.',
    '짙고 정돈된 눈썹은 \'의지의 결\'이 @{deep} 박힌 상입니다. 한 번 목표를 정하면 결실까지 밀어붙이는 @{inner_stamina} 기질이 강하게 작동합니다.',
  ]),
  _Frag((f) => f.fired('P-02') || f.nodeZ('forehead') >= 1.0, [
    '@{open_wide} 반듯한 이마는 \'천정(天庭) 열림\'이라 하여 윗사람의 도움과 윗선의 기회가 먼저 찾아오는 기질을 @{intense} 암시합니다.',
    '이마의 평탄함이 @{strong_adj} 드러나는 상은 초년운과 지도력의 기반이 동시에 열려 있다는 신호로 읽힙니다.',
  ]),
  _Frag((f) => f.fired('O-EM'), [
    '눈과 입의 표현이 함께 살아 있는 구조는 감정을 언어로 정확히 옮기는 @{rare} 재능이며, 글·강연·연기에서 @{intense} 설득력을 만듭니다.',
    '표정의 결과 말의 결이 함께 움직이는 상은 \'출납관(出納官)과 감찰관(監察官)의 합작\'이라 하여, 사람을 설득하는 직역에서 특히 지렛대 역할을 해냅니다.',
  ]),
  _Frag((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 @{strong_adj} 받쳐주는 상은 사람을 부려 일을 만드는 기질을 의미하며, 혼자 잘하는 것보다 조직·팀을 통해 @{talent_word}이 확장되는 유형입니다.',
    '광대가 힘차게 자리한 구조는 @{noble_m} 호령의 기운을 담고 있어, 순수 전문가보다 리더·관리자의 자리에서 진가가 @{intense} 드러납니다.',
  ]),
  _Frag((f) => f.fired('O-FB'), [
    '이마와 턱이 함께 단정한 구조는 \'시작과 끝이 모두 정렬된 상\'으로, 한 프로젝트를 처음부터 끝까지 담당했을 때 가장 좋은 결과가 나오는 기질입니다.',
  ]),
  _Frag((f) => f.nodeAZ('nose') >= 1.0, [
    '@{mount_c}이 또렷한 상은 자기 @{path_word}에 대한 확신이 강한 기질이며, 외부 평가에 흔들리지 않고 자기 길을 @{intense} 밀고 나가는 동력이 됩니다.',
  ]),
  _Frag((f) => f.fired('A-02'), [
    '이마 기운의 열림은 관상학에서 \'조년발(早年發)\'의 신호로, 젊은 시기의 도약이 동년배보다 앞서 찾아오는 기질을 의미합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 기질은 화려한 한순간의 폭발보다 시간에 정직하게 비례하는 축적형이며, 관상학에서 \'대기만성(大器晩成)\'이라 부르는 결에 가깝습니다.',
    '특정 부위의 극단이 아니라 전체의 균형으로 작동하는 @{structure}이기에, 한 장면이 아니라 시간 전체에서 진가가 @{intense} 드러납니다.',
  ]),
];

final List<_Frag> _talentShadow = [
  _Frag(_lowOf(Attribute.stability), [
    '다만 @{talent_word}의 빛이 강한 만큼 그림자도 분명합니다. 흥미가 옮겨 붙는 속도가 빠른 대신, 한 우물을 오래 파는 뿌리 내림이 @{subtle} 약한 편입니다. 관상학에서 \'상정 과강(上停過强)\'이라 부르는 기질로, 머리가 먼저 달려 나가 몸이 따라잡지 못하면 @{talent_word}이 결정적 순간에 \'쌓이지\' 못하고 \'흩어진\' 채 흐르기 쉽습니다.',
    '다만 당신의 @{talent_word}은 집중의 지속이 가장 큰 과제입니다. 관심사가 너무 자주 이동하면 재능은 풍부해도 결실은 얇아지는 구조이며, \'폭은 넓되 깊이가 부족한\' 평이 어느 시점부터 따라붙기 쉽습니다.',
  ]),
  _Frag(_lowOf(Attribute.trustworthiness), [
    '다만 당신의 @{talent_word}은 안으로 파고드는 성질이 강해, 바깥으로 내보이는 일에 서툰 편입니다. @{organ_mouth}이 닫혀 있는 상의 결로, 속에 쌓아둔 것이 많은데도 표현의 통로가 좁아 저평가되는 경우가 종종 발생합니다.',
    '다만 \'홍보가 약해 밀리는\' 상황이 반복된다면 이는 능력의 문제가 아니라 기질의 문제이며, 관상학에서 \'출납관이 무거운 상\'의 전형적 그림자입니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 당신의 감수성은 양날의 칼입니다. 세상을 섬세하게 @{observe} 감각이 반대로 작동할 때 작은 비판에도 기운이 크게 출렁이고, 주변 분위기에 쉽게 동화되어 자기 중심을 잠깐 놓쳐버리는 일이 생깁니다. @{palace_destiny}이 맑은 만큼 탁기도 그대로 비치는 구조이기 때문입니다.',
    '다만 깊은 감수성은 상처받기 쉬운 결과 같은 뿌리에서 자랍니다. @{talent_word}의 깊이와 연약함이 함께 자라나는 유형이므로, 외부 피드백을 어떻게 거르는지가 평생의 숙제가 됩니다.',
  ]),
  _Frag(_lowOf(Attribute.sociability), [
    '다만 당신의 @{talent_word}은 혼자 쌓을수록 단단해지는 성질이라, 사람 앞에서 풀어놓는 감각이 상대적으로 약합니다. 결과물의 완성도는 높은데 그것을 \'보여주는\' 자리에서 에너지가 빠르게 고갈되는 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag(_lowOf(Attribute.leadership), [
    '다만 당신의 @{talent_word}은 앞에 서기보다 뒤에서 설계하는 쪽에 더 잘 맞습니다. 앞장서야 하는 자리에 억지로 자신을 세우면 본래의 장점이 오히려 흐려지는 구조이며, 자리를 잘못 고르면 가장 큰 기회 비용이 발생합니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 @{talent_word}은 쌓는 시간에 정직하게 비례합니다. 조급한 마음으로 빠른 결실을 기대하면 제풀에 지쳐버리기 쉬운 @{structure}이며, 남들이 일찍 빛나는 모습에 흔들리면 잠재력이 절반밖에 열리지 않는 유형입니다.',
    '다만 당신의 @{structure}은 \'한 방에 터지는 상\'이 아닙니다. 3년·5년·7년의 지점에서 한 번씩 도약이 오는 리듬을 이해하지 못하면 중간의 평탄기에 자주 흔들릴 수 있습니다.',
  ]),
];

final List<_Frag> _talentAdvice = [
  _Frag((f) => true, [
    '@{talent_word}을 살리는 @{path_word}은 셋입니다. 첫째, 당신의 강점 영역을 최소 3년 이상 한 줄기로 밀어붙일 무대를 일찍 확보하십시오. 둘째, 맞지 않는 일은 조건이 좋아 보여도 과감히 덜어내는 용기가 필요합니다. 셋째, 혼자 잘하는 것으로 끝내지 말고 반드시 결과물을 세상에 내놓는 출구 하나를 확보하십시오.',
    '@{talent_word}의 상한을 열려면 세 가지를 동시에 맞춰야 합니다. 하나, 당신의 기질이 가장 @{intense} 작동하는 환경을 일찍 알아두는 것. 둘, 자기 속도를 남의 속도와 비교하지 않는 @{heart}의 훈련. 셋, 결과물을 어떤 형태로든 외부에 노출하는 정기 루틴의 확보. 이 셋이 맞물릴 때 관상이 약속한 @{talent_word}의 천장이 열립니다.',
    '관상이 예고한 @{talent_word}의 상한에 닿으려면, 맞는 자리를 고르는 눈, 자기 리듬을 지키는 @{heart}, 결과를 바깥에 내놓는 용기 — 이 세 축이 함께 움직여야 합니다. 하나라도 무너지면 타고난 결이 절반만 열린 채 평생이 흐르는 유형입니다.',
  ]),
];

final List<_BeatPool> _talentBeats = [
  _talentOpening,
  _talentStrength,
  _talentShadow,
  _talentAdvice,
];

// ═══ 2. 재물운 ═══

final List<_Frag> _wealthOpening = [
  _Frag(_highOf(Attribute.wealth), [
    '당신의 얼굴에는 재물의 기운이 @{intense} 서려 있습니다. @{palace_wealth}이 @{strong_adj} 자리한 상으로, 돈이 당신에게 머물고 싶어하는 구조가 골상에 이미 새겨져 있습니다. 같은 기회를 만나도 남기는 감각이 @{deep} 작동하는 유형입니다.',
    '@{palace_wealth}의 충실함이 @{intense} 드러나는 얼굴입니다. 수입과 지출 사이에서 남기는 타이밍을 직관적으로 @{observe} 기질이며, 손실 국면에서도 바닥을 확인하는 감각이 동년배보다 반 걸음 빠른 편입니다.',
    '재록(財祿)의 자리가 @{strong_adj} 받치는 상입니다. 돈의 흐름을 거꾸로 @{observe} 눈을 타고났기에, 사업·투자·운영 어느 경로에서도 \'남기는 사람\'이라는 평이 자연스럽게 따라붙습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.wealth) == _Band.mid, [
    '당신의 재물운은 극단적이지 않은 대신 @{strong_adj} 결을 갖추고 있습니다. @{palace_wealth}이 거칠지 않고 @{gentle} 열린 상으로, 한 방의 큰 부보다 꾸준히 쌓아 올리는 누적형에 해당합니다. 시간을 내 편으로 돌려세우는 영역에서 @{intense} 드러나는 유형입니다.',
    '당신의 재물은 \'조용히 불어나는 결\'입니다. 위험을 무릅쓰는 기개는 @{subtle} 적어도 잃지 않는 힘이 @{strong_adj}, 근로·자영업·장기 투자처럼 기다림이 자산으로 환원되는 종목에서 진가가 @{intense} 드러납니다.',
  ]),
  _Frag(_lowOf(Attribute.wealth), [
    '당신의 재물운은 현재 구조만 놓고 보면 폭발적이지 않은 유형에 가깝습니다. @{palace_wealth}의 자리가 @{subtle} 가볍거나 골격보다 살집이 받쳐주지 못하는 상으로, 돈이 당신 손에 오래 머무르지 않고 빠르게 흘러나가는 기질입니다. 다만 재물운은 관상학 안에서도 가장 후천적 수양으로 바뀌는 영역이라, 기질의 한계를 시스템으로 보완하면 전혀 다른 곡선이 그려집니다.',
    '\'버는 힘은 있으나 담는 그릇이 작은 상\'에 해당합니다. 관상학에서 이는 수양과 구조 설계로 가장 크게 바뀌는 영역이므로, 기질의 경향을 인정하되 거기에 갇히지 않는 것이 가장 중요합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 재물운은 평균대 위에서 단단한 결을 유지하는 @{structure}입니다. 생활 습관이 고스란히 몸에 누적되는 정직한 구조로, 30대부터 들이는 재물 자산의 총량이 말년 곡선의 기울기를 결정합니다.',
  ]),
];

final List<_Frag> _wealthStrength = [
  _Frag((f) => f.fired('P-06') || f.nodeZ('nose') >= 1.0, [
    '@{mount_c}이 @{strong_adj} 자리잡은 구조는 \'중년발복(中年發福)\'이라 하여 30대 후반에서 40대 사이에 재물의 꼭짓점이 오는 기질을 @{intense} 암시합니다.',
    '준두의 결이 살아 있는 상은 관상학에서 재운의 중심 축을 이루며, 사업·투자에서 결정적 기회의 문이 열리는 주기가 규칙적으로 돌아오는 신호로 읽힙니다.',
  ]),
  _Frag((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 힘차게 받쳐주는 구조는 사람을 부려 돈을 만드는 기질이며, 순수 근로보다 운영·관리·조직으로 부를 키우는 길이 더 잘 맞습니다.',
  ]),
  _Frag((f) => f.fired('Z-04') || f.nodeZ('chin') >= 1.0, [
    '@{mount_n}이 @{strong_adj} 두터운 구조는 \'말년재운\'을 상징하며, 50대 이후에도 재물의 뿌리가 마르지 않고 오히려 @{deep} 깊어지는 후복(後福)의 기질을 담고 있습니다.',
  ]),
  _Frag((f) => f.fired('Z-11'), [
    '중정의 기운이 @{intense} 열린 상은 중년 집중 발복의 신호로, 가장 큰 결실이 인생의 중간에 집결되는 리듬을 뜻합니다.',
  ]),
  _Frag((f) => f.fired('O-NM1') || f.fired('O-NM2'), [
    '코와 입의 결이 함께 살아 있는 구조는 \'수입과 지출을 모두 통제하는 상\'으로, 들어오는 흐름뿐 아니라 새는 구멍도 스스로 관리하는 @{rare} 기질을 뒷받침합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 재물 곡선은 단기보다 장기에서 진가가 드러나는 @{structure}이며, 5년 단위로 돌아보는 습관이 붙을 때 가장 크게 늘어납니다.',
  ]),
];

final List<_Frag> _wealthShadow = [
  _Frag(_lowOf(Attribute.wealth), [
    '다만 정직하게 직시할 지점이 있습니다. 당신의 @{structure}는 돈이 들어오는 문은 열려 있지만 나가는 문도 함께 열린 형국이어서, 의식적 장치 없이 흐름에 몸을 맡기면 손에 남는 것이 기대보다 적어지기 쉽습니다. 관상학에서 \'입은 있되 곳간이 작은 상\'이라 표현하며, 수입을 늘리는 노력보다 새어나가는 구멍을 먼저 막는 설계가 훨씬 큰 효과를 만듭니다.',
    '다만 담는 그릇의 설계가 동반되지 않으면 잃는 속도가 버는 속도를 따라잡습니다. 새는 자리를 먼저 찾아 막는 것이 관상이 알려주는 첫 과제입니다.',
  ]),
  _Frag((f) => f.fired('Z-09') || f.bandOf(Attribute.emotionality) == _Band.high, [
    '다만 당신의 재물 판단에는 감정이 먼저 덧씌워지는 위험이 따릅니다. 관계나 분위기에 휩쓸려 \'안 해도 될 지출\'이나 \'무리한 보증·투자\'에 발을 들이기 쉬운 구조로, 머리로는 답을 알면서 @{heart}이 먼저 움직여 뒤늦게 후회하는 패턴이 반복되기 쉽습니다.',
    '다만 감정의 파도가 금전 결정 위에 얹힐 때 판단의 결이 흐트러집니다. 큰 결정은 반드시 하루 이상 묵혀야 관상이 예고한 위험의 상당 부분이 사라집니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 재물운은 리듬이 @{subtle} 불규칙한 편입니다. 들어올 때와 빠져나갈 때의 낙차가 상대적으로 큰 구조라, 좋을 때의 확장을 나쁠 때의 완충으로 얼마나 잘 바꾸어 두었는지가 평생 재산의 크기를 결정합니다.',
    '다만 당신의 @{structure}에는 \'갑작스러운 유혹\'에 취약한 구간이 주기적으로 돌아옵니다. 호황기에 들뜨지 않고 현금 흐름을 그대로 쌓아두는 훈련이 재물운의 상한을 결정합니다.',
  ]),
];

final List<_Frag> _wealthAdvice = [
  _Frag((f) => true, [
    '재물운을 극대화하는 @{path_word}은 셋입니다. 첫째, 현금의 흐름이 아니라 자산의 구조에 집중하십시오. 월급의 크기보다 매달 시스템으로 빠져나가 자동으로 쌓이는 액수가 진짜 재물의 크기를 결정합니다. 둘째, 남의 돈을 다루는 훈련을 일찍 시작하십시오. 혼자 버는 것보다 남을 통해 증식하는 기질이 강한 @{structure}이기 때문입니다. 셋째, 감정이 크게 출렁이는 날의 금전 결정은 반드시 하루 미루십시오. 당신의 재물운은 머리가 차가울 때 가장 크게 열립니다.',
    '재물의 상한은 세 지점에서 결정됩니다. 고정 저축의 자동화, 남의 돈·남의 시간을 다루는 경험, 감정 과잉 시점의 결정 보류. 이 셋을 지키면 관상이 약속한 @{palace_wealth}의 잠재력이 순서대로 열립니다.',
  ]),
];

final List<_BeatPool> _wealthBeats = [
  _wealthOpening,
  _wealthStrength,
  _wealthShadow,
  _wealthAdvice,
];

// ═══ 3. 대인관계 ═══

final List<_Frag> _socialOpening = [
  _Frag(_highPair(Attribute.sociability, Attribute.trustworthiness), [
    '당신의 얼굴에는 사람을 여는 호방함과 한결같은 믿음이 함께 깃들어 있습니다. @{palace_social}과 @{palace_servant}이 동시에 발달한 @{rare} 상으로, 처음 만난 자리에서 당신의 친화력에 끌리고 오래 지나서는 당신의 의리에 남게 되는 이중 매력이 동시에 작동합니다.',
    '친화와 신의가 한 얼굴에 겹쳐 있는 @{rare} @{structure}입니다. 짧은 관계와 긴 관계 양쪽에서 강점을 발휘하는 전천후형이며, \'이 사람과 오래 가고 싶다\'는 평이 사람들 입에서 자연스럽게 나오는 결을 가졌습니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '당신의 얼굴에는 사람을 끌어당기는 기운이 @{intense} 흐릅니다. @{palace_social}이 @{open_wide} 열리고 입매가 유연한 상으로, 처음 보는 자리에서도 긴장을 풀어놓는 친화력이 타고났습니다.',
    '당신이 들어서는 공간은 @{intense} 온도가 올라가는 결을 가졌습니다. 낯선 사람들이 당신을 매개로 서로 이어지는 허브 역할을 자연스럽게 맡게 되는 기질입니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 얼굴에는 @{strong_adj} 믿음이 @{deep} 자리합니다. @{palace_home}과 @{palace_servant}이 두텁게 자리한 상으로, 말이 많지 않아도 함께 있으면 든든해지고 한 번 맺은 관계를 오래 이어가는 성정이 @{intense} 드러납니다.',
    '화려한 사교성보다 \'배신하지 않는 사람\'이라는 무언의 신호가 사람들을 당신 곁에 머물게 합니다. 관상학에서 전택궁의 안정이 가장 귀하게 평가되는 결이며, 이 결은 중년 이후 더욱 @{intense} 빛납니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '당신의 대인관계는 감정의 공명에서 시작됩니다. 눈매가 @{subtle} 촉촉하고 표정이 살아 있는 상으로, 남의 마음을 세심하게 읽어주는 기질이 관계의 진입로를 열어줍니다.',
    '공적 관계보다 \'속 얘기를 나누는 깊은 관계\'에서 당신의 진가가 드러나는 유형입니다. 소수 정예의 우정을 평생 가져가는 결이며, 관계의 폭보다 깊이가 당신의 자산입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 대인관계는 \'선택과 집중\' 방식으로 흘러갑니다. @{palace_social}이 @{subtle} 중용의 결을 가진 상으로, 넓은 네트워크보다 꼭 필요한 소수와의 단단한 연결을 우선하는 기질입니다.',
    '당신은 모든 관계를 공평히 관리하기보다 정해둔 소수에게 에너지를 몰아주는 선택적 관계의 설계자에 가깝습니다.',
  ]),
];

final List<_Frag> _socialStrength = [
  _Frag((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입과 눈의 표현이 살아 있어 대화의 리듬감이 좋은 편이며, 상대가 \'이 사람과 있을 때 내 편이 된 것 같다\'는 인상을 받기 쉽습니다.',
  ]),
  _Frag((f) => f.fired('L-AQ'), [
    '측면의 매부리형 코는 결정적 순간에 자기 주장을 또렷하게 내세우는 기질이며, 관계가 한쪽으로 끌려가지 않는 자기 중심축이 있음을 보여줍니다.',
  ]),
  _Frag((f) => f.fired('L-SN'), [
    '들창코의 결은 관상학에서 \'사교의 기(氣)\'가 열려 있다고 보는 신호로, 낯선 자리에 섞여드는 속도가 남다르게 빠른 기질입니다.',
  ]),
  _Frag((f) => f.nodeZ('mouth') >= 0.8, [
    '입의 결이 @{intense} 살아 있는 상은 대화의 완급을 자유롭게 조절하는 기질이며, 협상·설득·중재 자리에서 유독 강한 존재감을 냅니다.',
  ]),
  _Frag((f) => true, [
    '당신의 관계는 \'오래가는 소수\'와 \'스치듯 지나가는 다수\' 사이의 분리가 또렷한 구조로, 시간이 지날수록 핵심 그룹의 밀도가 @{deep} 짙어지는 결을 가졌습니다.',
  ]),
];

final List<_Frag> _socialShadow = [
  _Frag((f) => f.bandOf(Attribute.sociability) == _Band.low && f.bandOf(Attribute.trustworthiness) == _Band.low, [
    '다만 직시할 지점이 있습니다. 당신의 @{structure}는 먼저 다가가는 문도, 오래 품는 문도 좁은 편이어서, 가만히 두면 관계가 자연스럽게 줄어드는 방향으로 흐르기 쉽습니다. 관상학에서 \'고립상(孤立相)\'이 살짝 드러나는 유형에 해당하며, 혼자 있는 시간이 편해서가 아니라 관계 유지 루틴이 약해 결과적으로 고립되는 패턴이 반복될 수 있습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sociability) == _Band.high && f.bandOf(Attribute.trustworthiness) != _Band.high, [
    '다만 당신의 사교성에는 그림자가 있습니다. 새 관계의 열기가 식으면 같은 사람을 꾸준히 챙기는 동력은 @{subtle} 약한 편이라, \'처음엔 친했는데 어느 순간 멀어진\' 관계가 누적되기 쉽습니다. 관계의 수는 많지만 깊이를 나눌 사람이 부족하다는 공허감이 어느 시점에 찾아오는 유형입니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '다만 당신은 관계에서 거리를 조절하는 폭이 @{subtle} 좁은 편입니다. 가까워지면 너무 깊이 들어가고, 한 번 실망하면 단번에 멀어져버리는 \'0 아니면 100\'의 패턴이 반복되기 쉬우며, 한 번의 실망이 관계 전체를 끝내버리는 극단으로 이어질 수 있습니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 관계는 에너지 배분이 불균형해지기 쉽습니다. 중요한 사람에게 과하게 몰아주고 나머지는 방치하는 패턴이 반복되면, 결정적 순간에 \'주변에 사람이 너무 없다\'는 느낌이 드는 구간이 찾아오기 쉽습니다.',
  ]),
];

final List<_Frag> _socialAdvice = [
  _Frag((f) => true, [
    '대인관계의 운을 키우는 @{path_word}은 셋입니다. 첫째, 관계의 \'가운데 온도\'를 익히십시오. 뜨거웠다 차가워지는 것보다 미지근한 온도를 오래 유지하는 사람이 결국 가장 멀리 갑니다. 둘째, 한 달에 한 번이라도 당신을 찾아오지 않는 사람에게 먼저 안부를 건네는 루틴을 만드십시오. 셋째, 모든 사람을 당신 편으로 만들려 하지 마십시오. 기질에 맞지 않는 사람까지 품으려 할 때 정작 꼭 지켜야 할 사람을 놓칩니다.',
  ]),
];

final List<_BeatPool> _socialBeats = [
  _socialOpening,
  _socialStrength,
  _socialShadow,
  _socialAdvice,
];

// ═══ 4. 연애운 ═══

final List<_Frag> _romanceOpening = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.sociability), [
    '당신의 연애는 \'불러오는 연애\'에 가깝습니다. @{palace_social}과 @{palace_mate}이 함께 열린 상으로, 먼저 고백하기보다 여러 방향에서 들어오는 호감 중에 고르는 자리가 자연스럽게 주어지는 구도입니다. 첫 데이트의 분위기를 당신이 설계하는 편이고, 상대가 다음 약속을 당신의 스케줄부터 묻게 되는 구조가 반복됩니다.',
    '이성의 시선이 @{intense} 먼저 당신에게 기우는 @{structure}입니다. 후보의 폭이 넓다는 이점이 있는 대신, 비교의 습관이 오래 남아 정착 시점의 결정을 @{subtle} 늦추기 쉬운 구도이기도 합니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.attractiveness) != _Band.high, [
    '당신의 연애는 \'친구에서 연인으로\' 넘어가는 형태가 가장 자연스럽습니다. 눈매에 정(情)의 결이 @{deep} 자리한 상으로, 화려한 첫인상으로 한 번에 끌어당기기보다 여러 번 겹친 만남 속에서 상대가 어느 순간 \'이 사람\'을 발견하게 되는 경로가 반복됩니다.',
    '호감이 우정의 언어에서 연애의 언어로 번역되는 전환점에 당신이 @{intense} 각인되며, 이 전환의 기억이 관계의 접착제가 됩니다. 단기보다 장기에서 @{intense} 빛나는 결입니다.',
  ]),
  _Frag(_highOf(Attribute.sociability), [
    '당신의 연애는 \'넓은 풀에서 비교하며 고르는\' 형태입니다. 만남의 기회 자체가 풍부한 구조라 소개·모임·취미 공동체 어디든 반경이 자연스럽게 넓어지며, 여러 사람과의 대화에서 상대의 결을 가늠하는 감각이 @{intense} 발달한 편입니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '당신의 연애는 \'오래 지켜보고 한 번에 정하는\' 직선형입니다. @{palace_mate}이 단정하고 @{mount_n}이 @{strong_adj} 자리한 상으로, 썸을 길게 끌지 않고 상대에 대한 확신이 서는 순간 방향을 확정해버리는 기질입니다. 한 번 시작된 관계는 결혼이라는 종착점까지 직선으로 달려가는 경향이 강합니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 연애는 \'믿음의 신호가 누적된 뒤에야 문이 열리는\' 형태입니다. 분위기에 휩쓸려 시작하는 관계에는 좀처럼 마음이 기울지 않으며, 상대의 말과 행동이 일치하는지 @{deep} 관찰한 뒤 비로소 진지한 단계로 진입하는 결입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 \'시작은 느리되 시작한 뒤로는 @{deep} 들어가는\' 형태입니다. 첫 만남에서 즉시 불이 붙기보다 같은 자리에 두세 번 마주친 뒤 관심의 불씨가 번져가는 기질이며, 결혼으로 이어지는 관계에서 특히 진가가 드러납니다.',
  ]),
];

final List<_Frag> _romanceStrength = [
  _Frag((f) => f.fired('P-08'), [
    '@{palace_sex} 아래 누당의 윤기가 살아 있는 구조는 도화기(桃花期)가 규칙적으로 돌아오는 기질을 의미하며, 한 해에 한두 번 의미 있는 인연의 문이 열리는 주기성이 있습니다.',
  ]),
  _Frag((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 또렷한 구조는 자기 의사를 명확히 전하는 결이라, 애매한 썸에 오래 머무르지 않고 관계의 성격을 빠르게 정리하려는 성향이 있어 \'끌려다니는 연애\'로 가지 않습니다.',
  ]),
  _Frag((f) => f.fired('L-EL'), [
    '측면에서 입술선이 앞으로 도톰하게 드러나는 상은 관상학에서 \'도화의 기색\'으로 읽히며, 상대의 시선이 당신의 입매에 오래 머무는 @{subtle} 매력을 만듭니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 관계의 \'양\'보다 \'질\'이 우선이며, 맞는 사람 한 명을 만났을 때의 밀도가 평균을 크게 뛰어넘는 결을 가졌습니다.',
  ]),
];

final List<_Frag> _romanceShadow = [
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 당신의 연애에는 \'설렘의 유통기한\' 문제가 되풀이됩니다. 시작점의 스파크가 강한 만큼 관계가 일상의 단계로 접어드는 6개월에서 1년 사이 권태가 먼저 찾아오며, 권태 해결 설계가 부족할 때 새로운 자극 쪽으로 시선이 흘러 좋은 사람을 놓치는 패턴이 쌓일 수 있습니다. 관상학에서 \'화력은 강하되 근력이 약한 상\'의 전형적 경고입니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.trustworthiness) != _Band.high, [
    '다만 당신의 연애는 \'혼자 앞서 나가는\' 위험을 안고 있습니다. 상대의 신호를 깊게 해석하는 감수성이 때로는 신호가 아닌 것까지 신호로 읽어내어, 상대가 아직 정리하지 못한 감정을 당신이 먼저 미래로 번역해버리는 일이 생깁니다. 속도의 낙차가 상대에겐 부담으로 돌아오기 쉽습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) != _Band.high, [
    '다만 당신의 연애는 \'고르는 풀 자체가 좁다\'는 한계에 부딪히기 쉽습니다. 상대를 신중히 검증하는 기질이 강점인 동시에 새 사람을 만나는 자리에 잘 들어서지 않는 기질로 이어지며, 좋은 인연이 지나가는 시기에도 모르고 지나칠 수 있습니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 연애는 \'결정적 장면에서 머뭇거리는\' 약점이 따릅니다. 상대의 신호를 감지한 상태에서도 \'조금 더 확신이 들면\' 하며 움직이지 않다가 다른 적극적 경쟁자에게 자리를 넘기는 시나리오가 되풀이되기 쉽습니다.',
  ]),
];

final List<_Frag> _romanceAdvice = [
  _Frag((f) => true, [
    '연애운을 살리는 @{path_word}은 셋입니다. 첫째, \'끌리는 상대\'와 \'일상에 맞는 상대\'가 다를 수 있음을 인정하십시오. 매력 축과 적합도 축을 따로 평가하는 훈련이 평생 연애의 질을 결정합니다. 둘째, 권태 구간을 피하려 하지 말고 통과할 설계를 준비하십시오. 공동 프로젝트·여행·신체 리듬 변화를 한 분기에 하나씩 배치하는 것만으로 구간의 풍경이 달라집니다. 셋째, 이별의 방식을 다듬으십시오. 관상학에서도 이별의 품격이 다음 @{fate_word}의 결을 결정합니다.',
  ]),
];

final List<_BeatPool> _romanceBeats = [
  _romanceOpening,
  _romanceStrength,
  _romanceShadow,
  _romanceAdvice,
];

// ═══ 5. 바람기 ═══

final List<_Frag> _philanOpening = [
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.stability) == _Band.low, [
    '당신은 관상학이 가장 주의 깊게 지목하는 \'경계 넘기 쉬운\' 유형에 가깝습니다. 한 사람과의 관계가 안정기에 접어든 뒤에도 낯선 결의 이성이 시야에 들어올 때 관심의 축이 @{intense} 쉽게 옮겨 가는 구조입니다. 현재 파트너를 향한 @{heart}이 진심인 상태에서도 다른 가능성이 열린 자리에 서면 \'잠깐이라면 괜찮을 것\' 같은 합리화가 먼저 작동합니다.',
    '@{palace_mate}의 문이 한 방향으로 닫혀 있지 않은 @{structure}입니다. 단순한 호기심이 아니라 기질 자체의 예민함이며, 직장 내 지속적 접촉·옛 인연의 재등장·장기 출장처럼 \'거리와 반복\' 조건이 갖추어지는 시기에 @{intense} 흔들립니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '당신은 \'유혹은 자주 들어오지만 외도까지는 가지 않는\' 유형입니다. @{peach}의 기운과 신의(信義)의 골격이 한 얼굴에 공존하는 @{rare} @{structure}로, 당신을 흔들려는 사람이 끊이지 않아도 @{heart} 속에 그어둔 선이 단단해 결국 상대를 돌아가게 만듭니다.',
    '주변에서 \'저 사람이면 당연히 바람피울 것 같은데 의외로 안 피운다\'는 평이 따라붙는 @{structure}이며, 이 평가 자체가 직업·사회 자본의 신뢰도를 누적해 주는 의외의 자산이 됩니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '당신의 외도 위험은 감정이나 정서보다 \'에너지의 과잉\'에서 비롯됩니다. @{palace_sex}의 열기가 평소에도 누르기 힘든 상으로, 한 사람과의 관계에서 얻는 만족의 총량보다 몸 안에 남은 에너지의 총량이 더 많은 유형입니다. 이 과잉이 일·운동·창작으로 흘러갈 때는 아무 일도 일어나지 않지만, 출구가 막히는 시기에는 가장 가까운 위험한 선택지로 방향을 틀기 쉽습니다.',
  ]),
  _Frag(_highPair(Attribute.stability, Attribute.trustworthiness), [
    '당신의 얼굴에는 외도의 기색이 @{faint} 옅은 편입니다. @{mount_n}이 단정하고 @{palace_mate}이 고요한 상으로, 한 번 맺은 관계에 뿌리를 내리면 옆을 돌아보지 않는 정절의 기질이 @{deep} 박혀 있습니다. 복잡한 삼각관계가 벌어져도 당신이 먼저 자리를 정리하고 본래 관계로 돌아서는 사람이 됩니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '당신의 외도 경로는 \'몸보다 먼저 감정이 새는\' 정서 주도형입니다. 눈매에 정(情)이 쉽게 어리는 상으로, 현재 파트너에게 이해받지 못한다고 느끼는 시기에 자기 이야기를 들어주는 다른 이성 앞에서 관계의 경계가 @{subtle} 녹아내리는 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag((f) => true, [
    '당신의 바람기는 평소엔 잠들어 있다가 \'특정 조합이 겹칠 때\'만 깨어나는 상황 의존형입니다. @{peach}가 얼굴 전반에 퍼져 있지 않고 국소적으로만 서린 상으로, 평범한 일상에서는 모범적 파트너로 보이지만 피로·외로움·술자리·장기 출장이 겹치는 시기에 평소와 다른 판단을 내리기 쉽습니다.',
  ]),
];

final List<_Frag> _philanStrength = [
  _Frag((f) => f.fired('O-EM') && f.bandOf(Attribute.stability) != _Band.high, [
    '표정 변화가 풍부한 @{structure}는 외도 상황에서 \'숨기는 연기\'가 약한 결로 읽히며, 실제 경계를 넘었을 때 파트너에게 일찍 들키는 발각 패턴으로 이어지기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '관상학이 당신의 정절을 신뢰하는 이유는 외부의 유혹이 없어서가 아니라, 유혹을 인지한 뒤 스스로 걸음을 멈추는 @{heart}의 장치가 @{intense} 훈련되어 있기 때문입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 외도 기질이 작동하려면 감정·상황·에너지 세 축이 동시에 어긋나야 하며, 그 조합이 언제 찾아오는지를 아는 것이 바람기를 관리하는 첫 출발점입니다.',
  ]),
];

final List<_Frag> _philanShadow = [
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high || f.bandOf(Attribute.libido) == _Band.high, [
    '다만 이 기질이 방치될 때 치러야 할 대가는 관상학이 가장 엄중히 경고하는 지점입니다. 한 번의 경계 넘기가 남기는 죄책감은 배우자와의 일상 전체에 그늘을 드리우고, 그 그늘을 덮기 위한 또 다른 거짓이 쌓이는 이중생활의 피로가 본인의 건강과 일의 집중력을 먼저 갉아먹기 시작합니다. 외도의 비용은 관계의 붕괴로 끝나지 않으며, 자녀가 있으면 세대를 건너 감정의 상처가 전이된다는 것이 이 상을 보수적으로 해석하는 이유입니다.',
    '다만 외도 경험이 반복되면 관상 자체에 \'탁기(濁氣)\'가 서서히 끼기 시작해 다른 영역의 운까지 함께 흐려지는 연쇄가 관찰됩니다. 관상학은 외도를 도덕이 아니라 \'기운의 누수\'로 설명합니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 지나치게 강한 절제는 관계 안에서 \'결을 잃는\' 또 다른 위험을 낳습니다. 외부 유혹에 흔들리지 않는 만큼 현재 파트너와의 관계 안에서도 새로운 자극을 만드는 노력이 함께 약해지면, 지킴만 있고 결이 없는 관계가 오히려 상대 쪽에 외도의 빌미를 만들 수 있습니다.',
  ]),
  _Frag((f) => true, [
    '다만 \'상황형 바람기\'는 당사자가 가장 방심한 시점에 찾아옵니다. 이성의 경계가 아니라 상황의 경계를 설계해 두지 않으면, \'원래 이런 사람 아닌데\'로 시작된 한 번의 실수가 회복 불가능한 파장을 남기기 쉽습니다.',
  ]),
];

final List<_Frag> _philanAdvice = [
  _Frag((f) => true, [
    '바람기를 다루는 @{path_word}은 셋입니다. 첫째, 자신의 기질을 정직하게 인정하십시오. \'나는 절대 안 그런다\'는 부정이 가장 큰 사고의 전조이며, 위험 지대를 아는 사람만이 그 지대를 비껴 지나갈 수 있습니다. 둘째, 유혹 자체를 이기려 하지 말고 \'유혹이 들어올 자리\'를 구조적으로 줄이십시오. 둘이 되기 쉬운 출장·술자리·늦은 동선을 셋 이상의 구조로 바꾸는 것만으로 사고의 대부분이 사라집니다. 셋째, 현재 관계의 \'살아 있는 결\'을 유지하는 투자를 외도 방지의 비용으로 환산하십시오. 관계 안에서 채워져 있는 사람은 바깥에서 채우려 하지 않습니다.',
  ]),
];

final List<_BeatPool> _philanBeats = [
  _philanOpening,
  _philanStrength,
  _philanShadow,
  _philanAdvice,
];

// ═══ 6. 색기 ═══

final List<_Frag> _sensualOpening = [
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '당신의 색기는 관상학이 \'양귀비상(楊貴妃相)\'으로 분류하는 농염한 유형입니다. 누당(淚堂)에 물기가 차고 입술에 붉은 기색이 도는 상으로, 화려한 대낮보다 한 단계 낮은 실내 조명 아래에서 색의 농도가 가장 @{intense} 드러납니다. 여러 사람에게 평등하게 퍼지지 않고 당신이 마음을 내준 특정 시선 안에서만 순식간에 짙어지는 선택적 발산 구조입니다.',
    '@{peach}가 @{deep} 배어 있는 @{structure}입니다. 잔을 내려놓는 속도, 목걸이를 만지작거리는 손끝, 문장 사이의 침묵 같은 사소한 행동 하나에 색향이 실려 있어 당신을 오래 지켜본 사람일수록 오히려 더 @{intense} 매료되는 지속형 색기입니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.attractiveness) == _Band.high, [
    '당신의 색기는 관상학에서 \'여우상(狐相)\'의 결에 가까운 @{subtle} 유형입니다. 눈꼬리가 살짝 올라가고 입꼬리의 움직임이 풍부한 구조로, 직접적인 신호 대신 암시와 여백으로 상대를 흔드는 방식의 색기입니다.',
    '시선을 정면으로 주지 않고 잠깐 비껴주는 각도, 말을 멈추고 웃음 끝을 흘리는 간격, 고개를 살짝 기울일 때 드러나는 목선의 선택된 노출에 색기의 본체가 숨어 있으며, 상대는 당신이 아무 말도 하지 않았는데도 혼자 상상 속에서 먼 길을 다녀오게 됩니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.attractiveness) != _Band.high, [
    '당신의 색기는 \'해당화상(海棠花相)\'에 가까운 직선적이고 원색적인 유형입니다. @{palace_sex}의 기색이 감추어지지 않는 상으로, 우회와 암시 없이 당신의 존재 자체가 상대에게 @{intense} 즉각적인 온도로 전달되는 구조입니다. 기교 없는 직진성이 오히려 색기의 진정성을 만드는 결입니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.sensuality) != _Band.high, [
    '당신의 색기는 \'월궁상(月宮相)\'에 가까운 기품 중심의 결입니다. 골격의 비례와 오관의 조화가 먼저 눈에 들어오는 상으로, 색 자체가 강하기보다 정돈된 기품 안에 @{faint} 스며 있는 농도가 색기의 성격을 결정합니다. 가까이 다가갈수록 오히려 넘지 말아야 할 선이 먼저 느껴지며, 그 거리감이 색기의 본체로 작동합니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '당신의 색기는 \'정화상(情花相)\'에 가까운 감정 기반의 결입니다. 눈매에 정(情)이 어리는 상으로, 외형의 화려함이 아니라 감정의 깊이에서 피어오르는 색향이 상대의 마음을 붙잡는 유형입니다. 상대가 당신에게 끌리는 결정적 순간은 대개 당신이 울컥하거나 웃음을 참는 감정의 경계에서 발생합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 색기는 관상학이 \'암도화상(暗桃花相)\'이라 부르는 숨은 결의 유형입니다. 얼굴 전체에 색이 퍼져 있지 않고 특정 각도, 특정 빛, 특정 상대 앞에서만 순간적으로 피어나는 구조이며, 평소에는 색기의 기색이 거의 느껴지지 않다가 어느 저녁의 무방비한 한 장면에서 상대의 기억에 불로 새겨지는 종류입니다.',
  ]),
];

final List<_Frag> _sensualStrength = [
  _Frag((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입의 윤곽과 인중의 결이 살아 있는 구조는 관상학에서 \'수분기(水分氣)\'가 풍부한 상으로, 목소리의 울림과 발음의 리듬이 색기의 또 다른 경로로 작동하는 유형임을 의미합니다.',
  ]),
  _Frag((f) => f.fired('L-EL'), [
    '측면에서 입술선이 앞으로 도톰하게 드러나는 구조는 정면보다 프로필 각도에서 색의 농도가 @{intense} 진하게 기록되는 기질을 뜻합니다.',
  ]),
  _Frag((f) => f.nodeZ('eye') >= 0.8, [
    '눈의 결이 또렷하게 살아 있는 상은 시선 하나로 상대에게 온도를 전달하는 힘이 강하며, 사진·영상 같은 기록 매체에서 특히 색기의 잔상이 강하게 남습니다.',
  ]),
  _Frag((f) => true, [
    '당신의 색기는 얼굴의 한 부위에 집중되지 않고 전체의 리듬으로 작동하는 @{structure}이며, 움직일 때 가장 @{intense} 드러납니다.',
  ]),
];

final List<_Frag> _sensualShadow = [
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high || f.bandOf(Attribute.sensuality) == _Band.high, [
    '다만 당신의 색기는 \'희소성의 원칙\'을 지키지 않으면 품격이 @{intense} 빠르게 깎입니다. 넓게 풀릴수록 한 사람 앞에서의 농도가 얇아지는 구조이며, 관상학에서 \'도화 과다\'는 매력의 총량이 늘어나는 것처럼 보이지만 실제로는 기의 누수로 읽힙니다.',
    '다만 색기의 진폭이 큰 사람일수록 \'침착함의 훈련\'이 함께 따라오지 않으면 자기 매력에 스스로 취해버리는 함정에 빠지기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.attractiveness), [
    '다만 기품 중심의 색기는 \'다가올 수 없는 사람\'이라는 거리감이 관계의 진입 장벽을 @{intense} 높이기도 합니다. 당신에게 매력을 느낀 상대가 고백 직전에 \'내가 감당할 수 없을 것 같다\'며 물러서는 장면이 반복되기 쉬운 유형입니다.',
  ]),
  _Frag((f) => true, [
    '다만 \'숨은 결\'의 색기는 당사자의 자각 부족이 가장 큰 약점이 됩니다. 상대가 이미 기울어져 있는 순간에도 \'내가 무슨\' 하며 한 발 물러서면, 결정적 장면에서 색기가 활용되지 못한 채 흘러가버립니다.',
  ]),
];

final List<_Frag> _sensualAdvice = [
  _Frag((f) => true, [
    '색기를 품격 있게 쓰는 @{path_word}은 셋입니다. 첫째, 색이 가장 진해지는 환경의 구성 요소를 파악해 두십시오. 조명의 색온도, 음악의 템포, 옷감의 질감, 향의 계열까지 구체적으로 아는 사람만이 색기를 원하는 순간에 원하는 농도로 꺼낼 수 있습니다. 둘째, 색기는 절제와 방출의 대비에서 가장 @{intense} 작동합니다. 드러낼 자리와 덮을 자리를 구분하는 리듬을 당신이 먼저 설계하십시오. 셋째, 색기는 나이가 들수록 \'농도\'에서 \'깊이\'로 성격이 바뀝니다. 젊을 때의 색은 강도가 전부이지만, 연륜이 쌓인 색은 같은 농도라도 @{intense} 오래 남는 여운을 만들어냅니다.',
  ]),
];

final List<_BeatPool> _sensualBeats = [
  _sensualOpening,
  _sensualStrength,
  _sensualShadow,
  _sensualAdvice,
];

// ═══ 7. 건강과 수명 ═══

final List<_Frag> _healthOpening = [
  _Frag(_highOf(Attribute.stability), [
    '당신의 얼굴에는 건강의 뿌리가 @{deep} 박혀 있습니다. @{palace_health}이 막힘 없이 열리고 @{mount_n}이 @{strong_adj} 받쳐주는 상으로, 큰 병에 쉽게 흔들리지 않는 체질의 기본기가 골상 자체에 새겨져 있습니다. 결정적 위기가 찾아와도 회복의 탄성이 남들보다 한 단계 @{strong_adj} 작동하는 @{structure}입니다.',
    '@{palace_health}의 깊이와 턱의 묵직함이 함께 살아 있는 얼굴입니다. 잔병을 안 겪는다는 뜻이 아니라, 큰 파고 앞에서 중심이 무너지지 않는 탄성이 타고났다는 의미이며, 수명의 길이보다 삶의 밀도 측면에서 @{intense} 강점을 발휘합니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.stability) == _Band.mid, [
    '당신의 건강운은 중간에서 단단한 결을 유지하는 유형입니다. @{palace_health}과 턱의 균형이 극단적이지 않고 안정적으로 자리한 상으로, 치명적 기울어짐은 없지만 생활 습관의 축적이 고스란히 몸에 누적되는 정직한 구조입니다.',
    '잘 관리하면 평균 이상, 방치하면 평균 이하로 떨어지는 양면성을 가진 @{structure}이며, 30대부터 들이는 건강 자산의 총량이 말년 곡선의 기울기를 결정합니다.',
  ]),
  _Frag(_lowOf(Attribute.stability), [
    '당신의 건강운은 세심한 관리가 전제될 때 @{intense} 길어지는 @{structure}입니다. @{palace_health}이 @{subtle} 약하거나 턱의 받침이 가볍게 드러나는 상은 체질의 저점이 남들보다 낮은 구간에 자주 들어간다는 뜻이며, 이는 \'약하다\'가 아니라 \'예민하다\'에 가깝습니다.',
    '예민한 몸은 신호를 일찍 보내주기에, 그 신호를 잘 읽고 관리하면 둔감한 사람보다 @{deep} 오래 건강을 유지할 수 있는 역설적 유형입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 건강 곡선은 평균의 결을 따르되, 특정 구간에서 한 번의 큰 점검이 전체를 좌우하는 @{structure}입니다.',
  ]),
];

final List<_Frag> _healthStrength = [
  _Frag((f) => f.fired('P-07') || f.nodeAZ('nose') >= 1.2, [
    '@{mount_c}의 구조가 @{intense} 드러나는 상은 관상학에서 40대 전후의 \'중년 건강 관문\'을 강조하는 신호로 읽히며, 호흡기·순환기 쪽을 미리 점검해 두는 것이 큰 도움이 됩니다.',
  ]),
  _Frag((f) => f.fired('Z-09'), [
    '상정의 기운이 @{intense} 강한 상은 머리를 많이 쓰는 기질을 의미하며, 수면의 질이 전체 건강의 다른 어떤 요소보다 먼저 흔들리기 쉬운 유형입니다.',
  ]),
  _Frag((f) => f.fired('O-CH') || f.nodeZ('chin') >= 0.8, [
    '@{mount_n}이 듬직한 구조는 관상학에서 \'말년 강건\'의 상징으로, 50대 이후의 체력이 오히려 동년배보다 떨어지지 않는 기질을 뒷받침합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 체질은 \'평균의 결\'을 갖추되, 한 가지 약한 고리가 있으며 그 고리를 일찍 발견한 사람만이 관상이 약속한 상한에 도달합니다.',
  ]),
];

final List<_Frag> _healthShadow = [
  _Frag(_lowOf(Attribute.stability), [
    '다만 직시해야 할 지점이 있습니다. 당신의 @{structure}는 과로와 감정 소모에 @{intense} 취약하며, 일상의 작은 신호를 무시하고 밀어붙이는 시기가 길어지면 특정 장기에 부담이 집중적으로 쌓이는 패턴이 반복되기 쉽습니다. \'남들이 버티는 강도를 동일하게 버티려 하면 안 된다\'는 경고의 의미를 담은 유형입니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '다만 당신은 \'건강에 자신이 있다\'는 그 자신감이 가장 큰 위험 요인이 될 수 있습니다. 타고난 기본기가 좋기에 몸의 경고 신호를 쉽게 묵살하고 밀어붙이다 어느 시점에 한 번에 무너지는 패턴이 종종 나타나며, 조기 검진과 정기 관리를 오히려 @{intense} 꼼꼼히 해야 타고난 수명의 상한까지 안전하게 갈 수 있습니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 수명은 육체의 과로보다 해소되지 않은 감정의 누적으로 더 많이 갉아먹히는 유형이며, 감정의 배수로 설계가 건강 관리의 숨은 중심축입니다.',
  ]),
];

final List<_Frag> _healthAdvice = [
  _Frag((f) => true, [
    '건강을 지키는 @{path_word}은 셋입니다. 첫째, 수면·식사·운동 중 가장 약한 한 가지를 먼저 표준화하십시오. 세 가지를 동시에 잡으려 하면 어느 하나도 자리 잡지 못합니다. 둘째, 몸이 보내는 \'이상 없음\' 신호를 맹신하지 마십시오. 자각 증상이 없을 때 미리 점검하는 습관이 있을 때에만 관상의 수명 상한에 도달합니다. 셋째, 감정의 피로가 몸의 피로로 옮겨 가는 통로를 스스로 알아두십시오. 당신의 수명을 가장 많이 갉아먹는 요인은 육체 과로가 아니라 해소되지 않은 감정의 누적인 경우가 많습니다.',
  ]),
];

final List<_BeatPool> _healthBeats = [
  _healthOpening,
  _healthStrength,
  _healthShadow,
  _healthAdvice,
];

// ═══ 8. 종합 조언 ═══

// archetype 레이블은 _resolveText Step 0 에서 runtime features 로 치환된다.
final List<_Frag> _concludeOpening = [
  _Frag((f) => f.specialArchetype != null, [
    "지금까지 겹쳐본 여러 영역을 한 장으로 보면, 당신의 관상은 '@__PRIMARY_ARCHETYPE__' 위에 '@__SECONDARY_ARCHETYPE__'의 결이 겹쳐 흐르는 @{structure}입니다. 특히 얼굴에 '@__SPECIAL_ARCHETYPE__'이 함께 서려 있어, 평균적 해석의 범위를 넘어서는 결정적 국면을 인생 중·후반에 한 번 이상 통과하게 될 가능성이 높습니다.",
  ]),
  _Frag((f) => true, [
    "지금까지 겹쳐본 여러 영역을 한 장으로 보면, 당신의 관상은 '@__PRIMARY_ARCHETYPE__'의 골격 위에 '@__SECONDARY_ARCHETYPE__'의 결이 함께 흐르는 @{structure}입니다. 겉으로 먼저 드러나는 것은 '@__PRIMARY_ARCHETYPE__'이지만, 인생 중반을 실질적으로 움직이는 동력은 오히려 '@__SECONDARY_ARCHETYPE__' 쪽에 더 많이 담겨 있습니다.",
    "당신의 얼굴에는 '@__PRIMARY_ARCHETYPE__'과 '@__SECONDARY_ARCHETYPE__'이 한 몸에 겹쳐 있어, 단일 방향으로 힘을 쏟는 전형보다 상황에 따라 두 얼굴을 번갈아 쓸 수 있는 @{rare} 결을 지녔습니다.",
  ]),
];

// 연령대별 배타 predicate — 가장 구체적 band 가 단독으로 매칭되도록.
final List<_Frag> _concludeStage = [
  _Frag((f) => f.age.isOver50, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'덜어내는 기술\'입니다. 쌓아 올리는 시기는 이미 상당 부분 지나왔고, 지금부터는 남길 것과 흘려보낼 것을 가르는 판단이 말년의 빛깔을 결정합니다. 오랜 세월이 빚어낸 깊이가 관상을 @{intense} 풍성하게 만드는 시기이며, 타고난 골격의 좋은 기운은 오히려 지금 @{intense} 드러납니다.',
  ]),
  _Frag((f) => f.age.isOver30 && !f.age.isOver50, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'축적의 설계\'입니다. 초기의 재능이 드러난 시기이고, 지금부터 10년은 그 재능을 어떤 시스템 위에 올려놓느냐가 평생 곡선의 기울기를 결정합니다. \'중년 발복\'의 기반이 만들어지는 구간이기에, 작은 선택들이 복리처럼 쌓여 5~7년 뒤 전혀 다른 풍경을 만들어냅니다.',
  ]),
  _Frag((f) => f.age.isOver20 && !f.age.isOver30, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'결을 세우는 일\'입니다. 재능의 윤곽은 드러났지만 아직 주변에 맞추어 깎이기 쉬운 시기이며, 이때 결을 또렷이 세우지 못하면 이후 10년의 선택이 계속 흔들립니다. 지금 필요한 것은 답을 서둘러 찾는 일보다 당신 자신의 질문을 또렷이 세우는 일입니다.',
  ]),
  _Frag((f) => !f.age.isOver20, [
    '당신의 현재 단계에서 관상이 강조하는 지점은 \'가능성의 확장\'입니다. 아직 어떤 방향으로도 굳어 있지 않은 시기이기에, 경험의 폭이 그대로 나중의 얼굴에 새겨집니다. 지금의 다양성이 이후 관상의 깊이를 결정합니다.',
  ]),
];

final List<_Frag> _concludeAdvice = [
  _Frag((f) => true, [
    '마지막으로, 관상은 예언이 아니라 지도입니다. 타고난 골격과 기색이 길 위의 지형을 보여주지만, 그 위에서 어떤 속도로 어떤 방향으로 걷느냐는 오늘의 당신이 결정합니다. 같은 관상이라도 누군가는 타고난 장점을 20%밖에 열지 못하고 지나가고, 다른 누군가는 타고난 약점까지 무기로 바꾸며 80%를 열어냅니다. 분석이 제시한 강점은 더 @{deep} 밀어붙이고, 그림자는 먼저 알아차리는 쪽에 서십시오. 관상이 약속한 가장 좋은 풍경은 \'알고 선택한 사람\'에게만 열립니다.',
  ]),
];

final List<_BeatPool> _conclusionBeats = [
  _concludeOpening,
  _concludeStage,
  _concludeAdvice,
];

