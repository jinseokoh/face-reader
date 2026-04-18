import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

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
    MapEntry('재물운', _buildSection(f, _wealthBeats, 20)),
    MapEntry('대인관계', _buildSection(f, _socialBeats, 30)),
    MapEntry('연애운', _buildSection(
        f, f.isMale ? _romanceBeatsMale : _romanceBeatsFemale, 40)),
  ];
  if (f.age.isOver20) {
    parts.add(MapEntry('바람기', _buildSection(
        f, f.isMale ? _philanBeatsMale : _philanBeatsFemale, 50)));
  }
  if (f.age.isOver30) {
    parts.add(MapEntry('관능도', _buildSection(
        f, f.isMale ? _sensualBeatsMale : _sensualBeatsFemale, 60)));
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
  final String strongestNodeKo;
  final String secondStrongestNodeKo;
  final String dominantPalace;
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
    required this.strongestNodeKo,
    required this.secondStrongestNodeKo,
    required this.dominantPalace,
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
    strongestNodeKo: _nodeKoLabels[strongest] ?? strongest,
    secondStrongestNodeKo: _nodeKoLabels[second2nd] ?? second2nd,
    dominantPalace: _nodeDominantPalaceKo[strongest] ?? '명궁',
    specialArchetype: r.archetype.specialArchetype,
    primaryArchetype: r.archetype.primaryLabel,
    secondaryArchetype: r.archetype.secondaryLabel,
    seed: _computeSeed(r),
  );
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

String _genderedKey(String key, _Features f) {
  // _m / _f / _g 접미 pool 자동 선택
  if (_slotPools.containsKey('${key}_g')) {
    return f.isMale ? '${key}_m' : '${key}_f';
  }
  return key;
}

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
    '@{noble} 지략과 통솔이 겹쳐 흐르는 상입니다. 관상학에서 @{palace_destiny}이 @{clear_adj} 열리고 @{palace_career}이 @{strong_adj} 자리한 상으로, 문(文)과 무(武)의 경계를 넘나드는 @{rare} 기질이 얼굴의 중심축을 이룹니다.',
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
    '@{noble} 통솔의 기운이 @{intense} 서린 얼굴입니다. @{palace_career}의 위엄과 턱의 무게가 함께 살아 있어, 회의실의 침묵을 깨는 결단이나 흔들리는 팀을 한 방향으로 정렬시키는 호령이 당신 @{talent_word}의 중심이 됩니다.',
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
    '당신의 @{talent_word}은 지구력과 뚝심에 있습니다. @{mount_n}이 @{strong_adj} 받치고 @{zone_down}이 @{open_wide} 자리한 상으로, 한 우물을 끝까지 파서 결실로 만드는 @{noble} 기질이 골상에 박혀 있습니다.',
    '@{strong_adj} 근성이 @{intense} 서린 얼굴입니다. 화려하진 않되 중도에 꺾이지 않는 결을 타고났기에, 시간을 편으로 돌려세우는 종목에서 평균을 뛰어넘는 결과를 만들어냅니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 @{talent_word}은 \'믿음을 주는 힘\'에 있습니다. @{palace_home}과 @{palace_servant}이 @{strong_adj} 자리한 상으로, 말과 행동이 일치하는 결이 얼굴에 먼저 새겨져 있습니다.',
    '@{noble} 신의(信義)가 @{intense} 드러나는 얼굴입니다. 화려한 말재주가 아니라 한결같은 성품으로 사람을 움직이는 유형이며, 이는 관리직·중개·참모 역할에서 @{intense} 빛납니다.',
  ]),
  _Frag((f) => true, [
    '당신의 @{talent_word}은 한 방향으로 편중되지 않고 여러 영역에 고루 잠재된 형태입니다. 삼정(三停)이 균형을 이루고 극단적으로 치우치지 않은 상으로, 어떤 자리에 들어가도 그 자리의 언어를 @{intense} 흡수해 맞춰가는 적응력이 @{talent_word}의 본체입니다.',
    '겉보기엔 @{subtle} 평범해 보이지만, 오래 지켜본 사람일수록 진가를 알아보는 \'늦게 피는 꽃\'의 기질입니다. 중용의 결이 @{deep} 박혀 있어, 시기가 무르익을수록 @{intense} 드러나는 @{talent_word}을 가졌습니다.',
    '당신의 @{talent_word}은 @__STRONGEST_NODE__의 결을 중심축으로 삼아 자라납니다. @__DOMINANT_PALACE__의 신호가 얼굴에서 가장 @{intense} 읽히는 구조라, 이 부위가 관여하는 영역에서 또래보다 반 걸음 앞서는 감각이 붙어 있습니다.',
    '당신의 @{talent_word}은 한 가지 무기가 튀어나오기보다 @__STRONGEST_NODE__·@__SECOND_NODE__ 두 축이 함께 작동할 때 가장 @{intense} 드러나는 결합형입니다. 단독 무대보다 두 요소를 엮어야 하는 자리에서 진가가 나옵니다.',
    '당신의 @{talent_word}은 \'결을 타고 쌓이는\' 축적형입니다. 한 번의 스파크보다 3년·5년·10년의 결이 겹칠 때 진짜 모습이 드러나며, 같은 일을 다른 각도로 반복할수록 깊이가 @{intense} 붙는 유형입니다.',
  ]),
];

final List<_Frag> _talentStrength = [
  _Frag((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 @{intense} 자리잡은 당신은 @{organ_brow}이 @{strong_adj} 살아 있는 상이라, 새 지식을 익히는 초기 속도가 또래보다 한 발 빠르고 @{heart}이 중간에 꺾이지 않는 @{noble} 집요함까지 갖추었습니다.',
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
    '광대가 힘차게 자리한 구조는 @{noble} 호령의 기운을 담고 있어, 순수 전문가보다 리더·관리자의 자리에서 진가가 @{intense} 드러납니다.',
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
    '@__STRONGEST_NODE__의 결이 당신 @{talent_word}의 기폭제 역할을 합니다. 이 부위가 활성화될 때(표정·시선·말 한 조각이라도) 주변 공기가 당신 쪽으로 기울어지는 결을 가졌습니다.',
    '당신의 강점은 \'첫 만남의 인상\'보다 \'세 번째 만남 이후 자리잡는 신뢰\'에서 나오는 유형입니다. 초면의 화력보다 축적된 시간이 자산이라는 @{structure}의 특성이 @{deep} 박혀 있습니다.',
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
    '다만 @__STRONGEST_NODE__에 기운이 @{deep} 실린 만큼 그 부위가 \'편중\'의 축이 되기도 합니다. 이 부위에만 의지하면 다른 영역의 근력이 따라오지 못해 전체 균형이 깨질 수 있으니, 의식적으로 반대축을 훈련해야 합니다.',
    '다만 당신의 @{talent_word}은 \'보여주는 기술\'이 약한 편입니다. 실력은 있는데 세상에 드러내는 통로가 좁아 실제 기여보다 덜 평가되는 패턴이 반복되기 쉬우며, 의도적 노출 루틴이 이 결점의 유일한 해법입니다.',
  ]),
];

final List<_Frag> _talentAdvice = [
  _Frag((f) => true, [
    '@{talent_word}을 살리는 @{path_word}은 셋입니다. 첫째, 당신의 강점 영역을 최소 3년 이상 한 줄기로 밀어붙일 무대를 일찍 확보하십시오. 둘째, 맞지 않는 일은 조건이 좋아 보여도 과감히 덜어내는 용기가 필요합니다. 셋째, 혼자 잘하는 것으로 끝내지 말고 반드시 결과물을 세상에 내놓는 출구 하나를 확보하십시오.',
    '@{talent_word}의 상한을 열려면 세 가지를 동시에 맞춰야 합니다. 하나, 당신의 기질이 가장 @{intense} 작동하는 환경을 일찍 알아두는 것. 둘, 자기 속도를 남의 속도와 비교하지 않는 @{heart}의 훈련. 셋, 결과물을 어떤 형태로든 외부에 노출하는 정기 루틴의 확보. 이 셋이 맞물릴 때 관상이 약속한 @{talent_word}의 천장이 열립니다.',
    '관상이 예고한 @{talent_word}의 상한에 닿으려면, 맞는 자리를 고르는 눈, 자기 리듬을 지키는 @{heart}, 결과를 바깥에 내놓는 용기 — 이 세 축이 함께 움직여야 합니다. 하나라도 무너지면 타고난 결이 절반만 열린 채 평생이 흐르는 유형입니다.',
    '@{talent_word}을 꽃피우는 @{path_word}은 @__STRONGEST_NODE__ 의 결을 중심에 두고 세 겹으로 쌓는 것입니다. 첫째, 이 부위가 가장 @{intense} 작동하는 환경을 선택. 둘째, 단기 평가에 흔들리지 않는 @{heart}의 중심. 셋째, 주기적 리뷰로 방향 보정. 3년마다 한 번씩 점검하는 루틴이 평생 궤적을 결정합니다.',
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

// ═══ 4. 연애운 — 남/여 분리 pool ═══
//
// 관상학에서 남녀 연애 해석이 가장 크게 갈리는 지점: 주도권 / 매력 출처 /
// 타이밍 / 리스크 / 전통 용어. 각 성별 pool 은 opening·strength·shadow·
// advice 4 beat 구조로 공통 인터페이스 유지.

// ─── 4-M. 연애운 (남) ─────────────────────────────────────────────────

final List<_Frag> _romanceOpeningMale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.sociability), [
    '당신의 연애는 \'먼저 다가서는 쪽\'의 역학입니다. @{palace_mate}이 열리고 @{mount_c}의 기운이 받치는 상으로, 관심이 서면 머뭇거리지 않고 다음 장을 여는 장부의 기질이 또렷합니다. 상대의 속도보다 당신의 속도가 반 걸음 빠른 편이라, 추격의 리듬이 연애의 색을 결정합니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '당신의 연애는 \'기상(氣象) 주도형\'입니다. 말투·자세·말문의 템포로 상대를 끌어당기는 결이어서, 정적인 미소보다 움직이는 장면에서 매력이 @{intense} 드러납니다. 한 자리에 조용히 앉은 상대보다 함께 움직이는 상대와 합이 @{deep} 맞습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '당신의 연애는 \'확신 한 번에 방향을 정하는\' 직선형입니다. @{mount_n}이 단정한 상으로, 썸을 길게 끌지 않고 상대의 결이 자기 결과 맞다 판단되면 바로 관계의 이름을 정해버리는 장부의 기질입니다. 한 번 시작된 관계는 결혼이라는 종착점까지 직선으로 달려갑니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 연애는 \'믿음의 신호가 누적된 뒤에야 문이 열리는\' 결입니다. 분위기에 휩쓸려 시작하는 관계에는 좀처럼 마음이 기울지 않으며, 상대의 말과 행동이 일치하는지 지켜본 뒤 비로소 진지한 단계로 진입하는 사내의 신중함이 배어 있습니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 \'다가서는 자\'의 결이 기본입니다. 같은 공간에 끌리는 사람이 있으면 시선을 피하지 않고 먼저 말을 건네는 기질이어서, 관계의 출발점을 설계하는 쪽이 대개 당신이며 이 주도성이 연애의 색을 결정합니다.',
  ]),
];

final List<_Frag> _romanceStrengthMale = [
  _Frag((f) => f.fired('O-EB1') || f.fired('O-EB2'), [
    '눈썹이 또렷한 구조는 자기 의사를 흐리지 않는 결이라, 애매한 썸에 오래 머무르지 않고 관계의 성격을 일찍 정리합니다. 상대가 \'끌려다닌다\'는 느낌 없이 당신의 속도를 따라오게 만드는 장부의 결단이 강점입니다.',
  ]),
  _Frag((f) => f.fired('O-CK') || f.nodeZ('cheekbone') >= 0.8, [
    '@{mount_e}·@{mount_w}이 받쳐주는 구조는 \'기백(氣魄)\'이 실린 결로, 당신이 들어서는 순간 공기의 중심이 옮겨 가는 결이 연애의 출발점에서 @{intense} 작동합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 순간의 분위기보다 누적된 기백에서 힘을 얻는 결이어서, 한 번에 타오르기보다 여러 장면을 겹쳐 당신의 결을 각인시키는 장기전에서 유리합니다.',
  ]),
];

final List<_Frag> _romanceShadowMale = [
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 \'설렘의 유통기한\' 문제가 되풀이됩니다. 시작의 화력이 강한 만큼 일상 단계로 넘어가는 6개월에서 1년 사이 권태가 먼저 찾아오며, 그 공백을 새 자극으로 메우려 할 때 좋은 사람을 놓치는 패턴이 쌓이기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.leadership), [
    '다만 주도성이 강한 만큼 \'내가 정한 속도\'를 상대에게 강요하기 쉽습니다. 상대의 결이 따라오지 못할 때 관심이 식는 속도도 빠른 편이라, 기다릴 수 있는 인내가 연애 수명의 핵심이 됩니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.stability) == _Band.high && f.bandOf(Attribute.sociability) != _Band.high, [
    '다만 \'만날 자리 자체가 좁다\'는 한계에 부딪히기 쉽습니다. 검증의 기질이 강점이지만, 동시에 새 사람과의 접점에 잘 들어서지 않는 결로 이어져 좋은 인연이 지나가는 시기를 모르고 보낼 수 있습니다.',
  ]),
  _Frag((f) => true, [
    '다만 \'한 사람에 집중되면 주변이 흐려지는\' 기질이 있어, 연애가 가장 뜨거운 시기일수록 생활의 축 — 일·친구·건강 — 을 의식적으로 유지하지 않으면 중요한 자리를 같이 놓치기 쉽습니다.',
  ]),
];

final List<_Frag> _romanceAdviceMale = [
  _Frag((f) => true, [
    '연애운을 살리는 @{path_word}은 셋입니다. 첫째, \'끌리는 상대\'와 \'일상에 맞는 상대\'를 구분하는 훈련 — 매력 축과 적합도 축을 따로 평가하는 눈이 평생 연애의 질을 결정합니다. 둘째, 권태 구간을 피하지 말고 통과할 설계로 두십시오. 공동 프로젝트·여행·신체 리듬 변화를 분기에 하나씩 배치하는 것만으로 구간의 풍경이 달라집니다. 셋째, 이별의 품격이 다음 @{fate_word}의 결을 결정합니다. 마지막 장면이 가장 오래 기억되는 것이 남성 연애의 숨은 자산입니다.',
  ]),
];

final List<_BeatPool> _romanceBeatsMale = [
  _romanceOpeningMale,
  _romanceStrengthMale,
  _romanceShadowMale,
  _romanceAdviceMale,
];

// ─── 4-F. 연애운 (여) ─────────────────────────────────────────────────

final List<_Frag> _romanceOpeningFemale = [
  _Frag(_highPair(Attribute.attractiveness, Attribute.sociability), [
    '당신의 연애는 \'불러오는 자리\'의 역학입니다. @{palace_mate}이 열리고 누당(淚堂)에 은은한 윤기가 도는 상으로, 먼저 고백하기보다 여러 방향에서 들어오는 호감 중에 고르는 자리가 자연스럽게 주어지는 결입니다. 후보의 폭이 넓은 대신 비교의 습관이 정착 시점을 @{subtle} 늦추기 쉽습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.attractiveness) != _Band.high, [
    '당신의 연애는 \'우정에서 연인으로\' 넘어가는 전환에 강합니다. 첫인상의 스파크보다 여러 번 겹쳐진 대화 속에서 상대가 어느 순간 \'이 사람\'을 발견하게 되는 경로이며, 깊은 관계를 길게 이어가는 여중군자의 결이 자리합니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '당신의 연애는 \'오래 지켜보고 한 번에 고르는\' 신중형입니다. @{palace_mate}이 단정하고 눈꼬리의 결이 차분해, 썸을 길게 끌지 않고 상대에 대한 확신이 서는 순간 방향을 확정해 버립니다.',
  ]),
  _Frag(_highOf(Attribute.trustworthiness), [
    '당신의 연애는 \'믿음의 신호가 누적된 뒤에 문이 열리는\' 형태입니다. 분위기에 휩쓸려 시작하는 관계에는 좀처럼 마음이 기울지 않으며, 상대의 말과 행동이 일치하는지 지켜본 뒤에 비로소 진지한 단계로 들어섭니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 \'시작은 느리되 시작한 뒤로는 깊이 들어가는\' 결입니다. 첫 만남에서 즉시 불이 붙기보다 같은 자리에 두세 번 마주친 뒤 관심의 불씨가 번져가는 유형이며, 결혼으로 이어지는 관계에서 특히 진가가 드러납니다.',
  ]),
];

final List<_Frag> _romanceStrengthFemale = [
  _Frag((f) => f.fired('P-08'), [
    '@{palace_sex} 아래 누당의 윤기가 살아 있는 구조는 도화기(桃花期)가 규칙적으로 돌아오는 결로, 한 해에 한두 번 의미 있는 인연의 문이 열리는 주기성이 있습니다.',
  ]),
  _Frag((f) => f.fired('L-EL'), [
    '측면에서 입술선이 도톰하게 드러나는 상은 관상학에서 \'도화의 기색\'이며, 상대의 시선이 당신의 입매에 오래 머무는 @{subtle} 매력을 만듭니다.',
  ]),
  _Frag((f) => true, [
    '당신의 연애는 관계의 \'양\'보다 \'질\'이 우선이며, 맞는 사람 한 명을 만났을 때의 밀도가 평균을 크게 뛰어넘는 결을 가졌습니다.',
  ]),
];

final List<_Frag> _romanceShadowFemale = [
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 \'설렘의 유통기한\' 문제가 따릅니다. 시작의 화력이 강한 만큼 권태가 먼저 찾아오기 쉬우며, 그 공백을 덮으려 다음 상대를 미리 떠올리는 결이 들어서면 좋은 인연을 놓치는 패턴이 쌓일 수 있습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.trustworthiness) != _Band.high, [
    '다만 \'혼자 앞서 나가는\' 위험이 있습니다. 상대의 신호를 깊게 해석하는 감수성이 때로는 신호가 아닌 것까지 신호로 읽어, 상대가 아직 정리하지 못한 감정을 당신이 먼저 미래로 번역해 속도의 낙차를 만들기 쉽습니다.',
  ]),
  _Frag((f) => true, [
    '다만 당신의 연애는 \'결정 지연\'의 그림자가 있습니다. 상대의 신호를 감지한 상태에서도 조금만 더 확인하려다 적극적 경쟁자에게 자리를 넘기는 시나리오가 되풀이되기 쉬우며, 완벽한 증거는 결혼 뒤에도 오지 않습니다.',
  ]),
];

final List<_Frag> _romanceAdviceFemale = [
  _Frag((f) => true, [
    '연애운을 살리는 @{path_word}은 셋입니다. 첫째, \'끌리는 사람\'과 \'일상에 맞는 사람\'이 다를 수 있음을 인정하십시오. 상대의 화려함과 꾸준함을 별개로 저울질하는 훈련이 평생 연애의 질을 결정합니다. 둘째, 비교의 습관이 결정 타이밍을 놓치게 하지 않도록 스스로 \'선택 기한\'을 두십시오. 셋째, 이별의 방식이 다음 @{fate_word}의 결을 결정합니다. 품위 있는 마무리가 여성 관상의 가장 큰 자산이며, 남는 사람은 그 마지막 장면으로 당신을 기억합니다.',
  ]),
];

final List<_BeatPool> _romanceBeatsFemale = [
  _romanceOpeningFemale,
  _romanceStrengthFemale,
  _romanceShadowFemale,
  _romanceAdviceFemale,
];

// ═══ 5. 바람기 — 남/여 분리 pool ═══
//
// 남성: 외부 자극·에너지 과잉·상황형. 발현 조건 = 거리와 반복.
// 여성: 감정 결핍·공감 부족·정서형. 발현 조건 = 일상의 공백.

// ─── 5-M. 바람기 (남) ─────────────────────────────────────────────────

final List<_Frag> _philanOpeningMale = [
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.stability) == _Band.low, [
    '당신은 관상학이 \'외부 자극에 열린 상\'으로 지목하는 유형에 가깝습니다. 관계가 안정기에 접어든 뒤에도 낯선 결의 이성이 시야에 들어올 때 관심의 축이 옮겨 가는 결이며, 직장 내 지속적 접촉·옛 인연의 재등장·장기 출장처럼 \'거리와 반복\' 조건이 겹치는 시기에 @{intense} 흔들립니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '당신은 \'유혹은 자주 들어오지만 외도까지는 가지 않는\' 유형입니다. @{peach}의 기운과 신의(信義)의 골격이 한 얼굴에 공존하는 @{rare} 결로, 흔들려는 사람이 끊이지 않아도 스스로 그어둔 선이 단단해 결국 상대를 돌아가게 만듭니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '당신의 외도 위험은 감정보다 \'에너지의 과잉\'에서 옵니다. 한 관계에서 얻는 만족 총량보다 몸 안에 남은 에너지 총량이 많은 결이어서, 출구가 막히는 시기엔 가장 가까운 위험한 선택지로 방향을 틀기 쉬운 구조입니다.',
  ]),
  _Frag(_highPair(Attribute.stability, Attribute.trustworthiness), [
    '당신의 얼굴에는 외도의 기색이 @{faint} 옅습니다. @{mount_n}이 단정하고 @{palace_mate}이 고요한 상으로, 한 번 맺은 관계에 뿌리를 내리면 옆을 돌아보지 않는 정절의 기질이 @{deep} 박혀 있습니다.',
  ]),
  _Frag((f) => true, [
    '당신의 바람기는 평소엔 잠들어 있다가 \'특정 조합이 겹칠 때\'만 깨어나는 상황 의존형입니다. 평범한 일상에선 모범적 파트너로 보이지만 피로·외로움·술자리·장기 출장이 겹치는 시기엔 평소와 다른 판단을 내리기 쉬운 결입니다.',
  ]),
];

final List<_Frag> _philanStrengthMale = [
  _Frag((f) => f.fired('O-EM') && f.bandOf(Attribute.stability) != _Band.high, [
    '표정 변화가 풍부한 구조는 외도 상황에서 \'숨기는 연기\'가 약한 결로 읽히며, 경계를 넘었을 때 파트너에게 일찍 들키는 발각 패턴으로 이어지기 쉽습니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '관상학이 당신의 정절을 신뢰하는 이유는 유혹이 없어서가 아니라, 유혹을 인지한 뒤 스스로 걸음을 멈추는 @{heart}의 장치가 @{intense} 훈련되어 있기 때문입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 외도 기질이 작동하려면 감정·상황·에너지 세 축이 동시에 어긋나야 하며, 그 조합이 언제 찾아오는지 아는 것이 관리의 첫 출발점입니다.',
  ]),
];

final List<_Frag> _philanShadowMale = [
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high || f.bandOf(Attribute.libido) == _Band.high, [
    '다만 경계를 한 번 넘으면 치러야 할 대가는 관상학이 가장 엄중히 경고합니다. 한 번의 실수가 남기는 죄책감은 배우자와의 일상 전체에 그늘을 드리우고, 그 그늘을 덮기 위한 또 다른 거짓이 이중생활의 피로로 누적되어 건강과 일의 집중력을 먼저 갉아먹습니다.',
  ]),
  _Frag((f) => true, [
    '다만 \'상황형 바람기\'는 당사자가 가장 방심한 시점에 찾아옵니다. 이성의 경계가 아니라 상황의 경계를 설계해 두지 않으면 \'원래 이런 사람 아닌데\'로 시작된 한 번의 실수가 회복 불가능한 파장을 남기기 쉽습니다.',
  ]),
];

final List<_Frag> _philanAdviceMale = [
  _Frag((f) => true, [
    '바람기를 다루는 @{path_word}은 셋입니다. 첫째, 자신의 기질을 정직하게 인정하십시오. \'나는 절대 안 그런다\'는 부정이 사고의 전조이며, 위험 지대를 아는 사람만이 그 지대를 비껴 지나갈 수 있습니다. 둘째, 유혹을 이기려 하지 말고 \'유혹이 들어올 자리\'를 구조적으로 줄이십시오 — 둘만 되기 쉬운 출장·술자리·늦은 동선을 셋 이상의 구조로 바꾸는 것만으로 사고의 대부분이 사라집니다. 셋째, 관계 안의 결을 유지하는 투자를 외도 방지의 비용으로 환산하십시오.',
  ]),
];

final List<_BeatPool> _philanBeatsMale = [
  _philanOpeningMale,
  _philanStrengthMale,
  _philanShadowMale,
  _philanAdviceMale,
];

// ─── 5-F. 바람기 (여) ─────────────────────────────────────────────────

final List<_Frag> _philanOpeningFemale = [
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '당신의 외도 경로는 \'몸보다 감정이 먼저 새는\' 정서 주도형입니다. 눈매에 정(情)이 쉽게 어리는 상으로, 현재 파트너에게 이해받지 못한다고 느끼는 시기에 자기 이야기를 들어주는 다른 이성 앞에서 관계의 경계가 @{subtle} 녹아내리는 패턴이 반복되기 쉽습니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.trustworthiness) == _Band.high, [
    '당신은 \'유혹은 있지만 선을 지키는\' 유형입니다. @{peach}의 기운과 신의(信義)가 한 얼굴에 공존하는 결로, 흔들리는 마음을 느끼면서도 이를 정리하여 본래 자리로 돌아오는 @{heart}의 중심이 단단합니다.',
  ]),
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '당신은 관상학이 주의 깊게 지목하는 \'감정 결핍에 열린 상\'에 가깝습니다. 일상의 권태와 공감 부족이 쌓이는 시기에 낯선 이성의 경청 앞에서 관계의 경계가 @{subtle} 녹아내리기 쉬운 결입니다.',
  ]),
  _Frag(_highPair(Attribute.stability, Attribute.trustworthiness), [
    '당신의 얼굴에는 외도의 기색이 @{faint} 옅습니다. @{palace_mate}이 고요하고 눈매가 단정한 상으로, 한 번 맺은 관계에 정(情)을 깊이 두면 옆을 돌아보지 않는 숙덕(淑德)의 결이 박혀 있습니다.',
  ]),
  _Frag((f) => true, [
    '당신의 바람기는 \'감정의 공백\'이 쌓일 때만 깨어나는 정서 이중형입니다. 파트너와의 대화가 줄고 일상이 반복되는 시기에 새 공감 제공자에게 이끌리는 흐름이 반복되기 쉬운 결입니다.',
  ]),
];

final List<_Frag> _philanStrengthFemale = [
  _Frag(_highOf(Attribute.emotionality), [
    '감정의 결을 @{deep} 읽는 기질은 파트너와의 소통에서 가장 큰 자산이며, 관계 안에서 감정의 출구를 먼저 만들 때 외도 경로 자체가 닫힙니다.',
  ]),
  _Frag(_highOf(Attribute.stability), [
    '당신의 정절은 기질이 아니라 \'정이 두터워서\' 지켜지는 결입니다. 한 번 준 마음을 거두지 않는 여중군자의 결이 외부 결박보다 @{deep} 단단합니다.',
  ]),
  _Frag((f) => true, [
    '당신의 외도 경로는 몸이 아니라 마음에서 시작됩니다. 감정의 채움이 어디서 오는지를 아는 것이 관계의 경계를 지키는 첫 설계입니다.',
  ]),
];

final List<_Frag> _philanShadowFemale = [
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high || f.bandOf(Attribute.libido) == _Band.high, [
    '다만 감정이 한 번 옮겨 가면 \'관계의 이중화\'로 치닫는 속도가 빠릅니다. 남성의 상황형 바람기와 달리 여성의 정서형 바람기는 끊어내는 과정이 더 고통스럽고, 주변 관계 전반(자녀·가족·친구)의 결까지 함께 흔들기 쉽습니다.',
  ]),
  _Frag((f) => true, [
    '다만 \'감정의 배수로\'가 부족하면 외부 제공자에게 과하게 의존하게 되어, 작은 관심 하나에도 선을 넘어서는 판단이 들어서기 쉽습니다. 감정의 출구를 관계 안과 밖에 균형 있게 두는 설계가 관건입니다.',
  ]),
];

final List<_Frag> _philanAdviceFemale = [
  _Frag((f) => true, [
    '바람기를 다루는 @{path_word}은 셋입니다. 첫째, 관계 안의 감정 대화를 의식적으로 보충하십시오. 여성 관상에서 외도는 몸이 아니라 감정의 공백에서 시작되므로 \'말하지 않는 시간\'이 길어지면 위험 구간이 열립니다. 둘째, 둘만의 정서 공유가 쉽게 만들어지는 자리 — 반복되는 1:1 만남·늦은 통화·개인 메신저 — 를 구조적으로 줄이십시오. 셋째, 관계 밖에서 감정을 풀 수 있는 우정·취미·상담의 출구를 여러 갈래로 열어 두십시오.',
  ]),
];

final List<_BeatPool> _philanBeatsFemale = [
  _philanOpeningFemale,
  _philanStrengthFemale,
  _philanShadowFemale,
  _philanAdviceFemale,
];

// ═══ 6. 관능도 — 남/여 분리 pool ═══
//
// (구 '색기' 섹션명을 attribute.dart::labelKo 와 일치시켜 '관능도' 로 변경.)
// 오랜 관계에서 몸에 새겨지는 농밀한 결, 음주·파티의 기(氣) 누수 경고,
// 만족의 선이 그어질 때까지 지속되는 욕구 — 관상학 전통의 엄중한 진단 + 실질 조언.

// ─── 6-M. 관능도 (남) — 7개 아키타입 + 침실 묘사 ─────────────────────────────

final List<_Frag> _sensualOpeningMale = [
  // 1. 양기 농밀 + 침실의 농도
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '당신의 관능은 관상학이 \'양기(陽氣) 농밀상\'으로 분류하는 지속형입니다. 오랜 세월 한 자리에서 쌓인 농밀한 기억이 몸에 새겨져, 해를 거듭할수록 욕구의 결이 오히려 @{intense} 짙어지는 유형입니다. 밤이 길어지는 계절에 숨결이 먼저 달아오르고, 어깨선·손끝·허리의 무게가 상대의 피부 위에 오래 남는 결이며, 근육의 밀도와 체온의 언어로 발산되는 침묵 주도형 관능입니다.',
    '관상학이 \'양기 농밀상\'으로 꼽는 지속형입니다. @__DOMINANT_PALACE__의 기운이 @{intense} 실린 결로, 침대 위에서의 시간 감각이 일상과 완전히 분리되는 유형이며, 상대의 숨결이 리듬을 바꿀 때마다 당신의 몸이 그에 맞춰 즉각적으로 반응합니다. 만족의 선이 그어질 때까지는 호흡이 가라앉지 않는 결이 @{deep} 박혀 있습니다.',
  ]),
  // 2. 호기심·탐험형 — 한 상대에 만족 못 하는 결
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high || f.bandOf(Attribute.sensuality) == _Band.high, [
    '당신의 관능은 \'다층 도화상(多層桃花相)\'의 탐험형입니다. 한 상대·한 패턴의 반복만으로는 내부의 갈증이 가라앉지 않아, 낯선 각도·다른 결·미지의 온도를 계속 탐색하려는 기질이 골상에 박혀 있습니다. 낮의 단정함 뒤에서 상상이 계속 다음 장면을 그리는 결이며, 이 호기심이 관계 안에서 창의적 탐험으로 풀릴 때 가장 건강하게 소화됩니다.',
    '\'유혹을 상상하는\' 결이 유난히 발달한 상입니다. 눈으로 본 장면이 머릿속에서 즉시 다음 장면으로 확장되고, 스쳐간 실루엣 하나가 며칠 동안 몽상의 씨앗으로 남는 유형이며, 상상의 해상도가 현실보다 먼저 완성되어 실제 관계에서 선명한 인도자가 되는 결을 가졌습니다.',
  ]),
  // 3. 상상·감각 발달형
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high, [
    '당신의 관능은 \'오감이 먼저 반응하는 감각상(感覺相)\'입니다. 상대의 목소리 낮은 울림·호흡 사이 0.5초 멈춤·손등에 닿는 체온의 온도차 하나하나가 몸 안에서 작은 회로를 연쇄적으로 켜는 유형이며, 침실의 빛·음악·향·시트의 촉감 모두를 의식적으로 고르는 설계자의 결입니다. 감각의 섬세함이 최대 자산이자 가장 긴 지속성의 뿌리입니다.',
  ]),
  // 4. 풍채 주도형 (high lib + high attr)
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.attractiveness) == _Band.high, [
    '당신의 관능은 \'풍채 주도형\'입니다. 어깨선·등의 결·준두의 기운이 받치는 상으로, 외형의 단정함이 아니라 존재 전체에서 뿜어져 나오는 밀도가 상대를 끌어당깁니다. 말수가 줄어드는 순간, 상대의 허리를 감는 손의 각도, 밤의 체온이 올라가는 속도에서 농도가 @{intense} 짙어지는 결로, 조용한 정복의 결이 본체입니다.',
  ]),
  // 5. 직선·본능형
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.attractiveness) != _Band.high, [
    '당신의 관능은 직선적이고 원초적인 \'해당화상(海棠花相)\'의 결입니다. @{palace_sex}의 기색이 감추어지지 않는 상으로, 처음 만난 자리에서도 눈빛·호흡·손끝의 압력만으로 의도가 전달되는 유형이며, 기교 없는 직진성이 오히려 압도적인 밀착감을 만듭니다. 밤의 초반보다 중반 이후 진짜 결이 드러나는 체력형입니다.',
  ]),
  // 6. 절제·기품형
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.libido) != _Band.high, [
    '당신의 관능은 \'절제된 기품상\'의 결입니다. 농도 자체는 강하지 않되 정돈된 기품 안에 @{faint} 스며 있는 밀도가 성격을 결정하며, 침대 위에서조차 흐트러지지 않는 결이 오히려 가장 강렬한 매력으로 작동합니다. 상대에게 \'이 사람을 어디까지 흐트러뜨릴 수 있을까\' 라는 상상을 계속 만들어내는 유형입니다.',
  ]),
  // 7. 잠재·열쇠형 (fallback)
  _Frag((f) => true, [
    '당신의 관능은 \'잠재 농밀상\'의 결입니다. 평소엔 드러나지 않다가 신뢰한 상대 앞에서만 깊이 열리는 유형으로, 문이 열리는 그 한 장면의 밀도가 상대의 기억에 오래 새겨지는 집중형입니다. 침대 시트의 온도·속옷의 결·숨결 사이의 멈춤 같은 소소한 디테일에 집중력을 쏟는 기질이며, \'이 사람과의 밤은 다르다\' 는 인상을 남기는 결입니다.',
    '당신의 관능은 \'침묵 주도형\'의 결입니다. 언어보다 몸의 무게·손의 각도·눈빛의 온도로 이야기하는 유형이며, 상대가 스스로 해석해 들어오게 만드는 여백이 매력의 핵심입니다. 밤이 깊어질수록 오히려 존재감이 뚜렷해지는 역설적 구조를 가졌습니다.',
  ]),
];

final List<_Frag> _sensualStrengthMale = [
  _Frag((f) => f.fired('O-PH1'), [
    '인중이 @{strong_adj} 자리잡은 구조는 관상학에서 \'수분기(水分氣)\'가 충만한 상으로, 오랜 관계에서 몸으로 쌓인 기억이 밤마다의 결을 @{intense} 진하게 되살리는 기질을 뒷받침합니다. 상대의 작은 숨소리 하나에서 이전의 밤이 통째로 되살아나는 기억력이 유지력의 뿌리입니다.',
    '인중의 결이 살아 있는 구조는 \'지속형 관능\'의 물리적 증거입니다. 한 번의 만족이 다음 만족의 문을 여는 결이며, 시간의 흐름이 당신의 관능을 소모시키기보다 오히려 농축시키는 드문 기질을 가졌습니다.',
  ]),
  _Frag((f) => f.nodeZ('nose') >= 0.8, [
    '@{mount_c}의 기운이 살아 있는 구조는 원초적 집중력의 증거입니다. 만족의 선이 스스로 그어지기 전엔 멈추지 않는 지속형 욕구가 이 골상에 @{deep} 박혀 있으며, 한 상대 앞에서 시간 감각이 사라지는 종류의 몰입이 일어나는 유형입니다.',
  ]),
  _Frag((f) => true, [
    '당신의 관능은 단발로 끝나지 않습니다. 만족의 선이 분명히 그어질 때까지 몇 차례 물결처럼 이어지는 결로, 속도가 아니라 밀도가 만족의 기준이 되며 밤이 깊어질수록 감각이 더 또렷해지는 역설적 기질이 본체입니다.',
    '상대의 몸에서 미세한 변화를 읽어내는 감각이 @{deep} 살아 있는 결입니다. 호흡의 진폭·피부의 온도 변화·근육의 긴장도 같은 신호를 즉각 포착해 다음 동작을 조정하는 능력이 관능의 수명을 늘립니다.',
    '\'같은 상대와도 다른 밤을 만들 수 있는\' 창의력이 당신 관능의 핵심입니다. 속도 · 각도 · 조명 · 리듬 어느 하나를 바꾸면 전혀 새로운 농도가 만들어진다는 것을 본능적으로 아는 유형입니다.',
  ]),
];

final List<_Frag> _sensualShadowMale = [
  // 1. 상상 과잉형 — 현실이 상상을 못 따라가는 그림자
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high, [
    '다만 당신의 관능은 \'내부 상상의 양이 외부 실현의 양보다 훨씬 큰\' 결입니다. 머릿속에서 펼쳐지는 장면이 실제 관계보다 풍부해지면, 현실의 상대가 그 해상도를 따라오지 못한다고 느끼는 순간이 반복되기 쉬우며, 관상학에서는 이를 \'환영(幻影)의 함정\' 이라 부릅니다. 실제 관계 안에서 구체적 탐험으로 풀어내지 않으면 내부 갈증이 계속 누적됩니다.',
  ]),
  // 2. 호기심 확산형 — 탐험이 바깥으로 새는 그림자
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high, [
    '다만 한 상대로 만족하지 못하는 호기심이 외부로 새면 관계의 뿌리가 흔들립니다. 관상학에서는 이 기질이 \'도화(桃花)가 흩어진 상\' 으로 번질 수 있다고 경고하며, 호기심을 \'같은 상대와의 다른 각도\' 로 돌리지 않으면 파트너의 신뢰가 서서히 깎이는 연쇄가 시작됩니다.',
  ]),
  // 3. 기품 거리감형 — 절제가 관능을 가두는 그림자
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.libido) != _Band.high, [
    '다만 \'기품의 거리감\' 이 관능의 활력을 가두는 장벽이 되기도 합니다. 상대가 가까이 다가오는 시도를 무의식적으로 막는 결이 있어 침실에서도 먼저 무장을 내려놓는 연습이 필요하며, 흐트러지는 것 자체가 매력이 될 수 있다는 것을 받아들이는 훈련이 평생 과제입니다.',
  ]),
  // 4. 과잉 방출형 — 전형적 리듬 실패
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 당신의 관능은 \'과잉 방출\' 에 취약합니다. 짧은 시기에 집중적으로 쏟으면 낮의 집중력과 판단력까지 흔들리는 연쇄로 이어지며, 속도보다 주기 설계가 관능 수명을 결정합니다. 쌓는 시간과 쏟는 시간을 분리해서 관리해야 장기 밀도가 유지됩니다.',
  ]),
  // 5. 침묵·전달 부족 (fallback)
  _Frag((f) => true, [
    '다만 \'침묵 주도\' 의 결이 상대에게는 해석 부담이 되기도 합니다. 원하는 것을 말 없이 전달하려는 기질이 오래되면 상대가 \'내가 잘 맞추고 있는 건가\' 라는 불안을 느끼기 쉬우며, 핵심 장면에서는 간결한 언어가 침묵보다 더 깊은 만족을 만듭니다.',
    '다만 당신의 관능은 한 방향 쏠림이 심합니다. 주도의 결이 강한 만큼 상대의 속도에 자신을 맞추는 연습이 약해지면 관계 안의 온도차가 벌어지며, \'받는 밤\' 의 풍경을 의식적으로 만들어야 균형이 잡힙니다.',
  ]),
];

final List<_Frag> _sensualAdviceMale = [
  _Frag((f) => true, [
    '관능의 결을 깊게 가꾸는 @{path_word}은 셋입니다. 첫째, 상상의 해상도만큼 현실의 해상도를 높이십시오 — 침실의 조명·음악·향·촉감 모든 요소를 의식적으로 고르면 머릿속 장면이 외부로 번지기 시작합니다. 둘째, 호기심을 \'새 상대\' 가 아니라 \'같은 상대와의 다른 각도\' 로 돌리십시오 — 같은 사람을 다른 시간·다른 문장·다른 몸짓으로 만나는 연습이 평생의 밀도를 결정합니다. 셋째, 받는 순간보다 주는 순간에 관능이 @{intense} 완성되는 유형이므로 상대의 만족을 읽는 눈을 길러야 합니다.',
    '관능의 축을 꾸준히 가꾸는 @{path_word} — 첫째, 침실을 \'감각의 무대\' 로 설계하십시오. 빛의 각도 하나, 시트의 촉감 하나가 밤의 질을 결정합니다. 둘째, 상상과 현실의 경계를 명료히 — 꿈은 꿈으로 남기고, 현재의 상대에게 \'지금\' 의 밤을 열어주는 집중이 관능의 건강함입니다. 셋째, 원하는 것을 언어로 전하는 용기를 기르십시오 — 남성의 침묵은 관계 안에서 오해로 번지기 쉽습니다.',
    '관능이 오래 가는 @{path_word}은 \'리듬의 설계\'입니다. 첫째, 쌓는 시간과 쏟는 시간을 분리해 관리하십시오 — 밤의 폭발이 다음 밤의 깊이가 되려면 사이의 여백이 필요합니다. 둘째, 같은 몸짓을 반복하지 말고 매번 하나씩만 바꾸십시오 — 각도·속도·조명·호흡 중 한 가지. 셋째, 상대의 만족 신호를 언어로 확인하는 루틴을 넣으십시오 — 해석의 부담을 줄여야 당신의 집중도 깊어집니다.',
  ]),
];

final List<_BeatPool> _sensualBeatsMale = [
  _sensualOpeningMale,
  _sensualStrengthMale,
  _sensualShadowMale,
  _sensualAdviceMale,
];

// ─── 6-F. 관능도 (여) — 7개 아키타입 + 침실 묘사 ─────────────────────────────

final List<_Frag> _sensualOpeningFemale = [
  // 1. 음기 농밀 + 침실의 깊이
  _Frag(_highPair(Attribute.libido, Attribute.sensuality), [
    '당신의 관능은 관상학이 \'음기(陰氣) 농밀상\'으로 지목하는 지속형입니다. 오랜 시간 동안 함께 쌓인 침실의 기억이 온몸에 스며, 해를 거듭할수록 바라는 결이 @{intense} 짙어지는 유형입니다. 숨결이 낮아질 때·손끝이 먼저 더듬을 때·어깨가 상대의 가슴에 닿는 각도에서 온도가 올라가는 결로, 감정과 몸이 겹쳐 반응하는 @{rare} 구조입니다.',
    '관상학이 \'음기 농밀상\'으로 평하는 지속형입니다. 밤이 깊어질수록 결이 또렷해지는 유형이며, @__DOMINANT_PALACE__의 기운이 받치는 상이라 상대의 숨결 하나의 리듬 변화에 몸이 즉각 공명합니다. 서두르는 관계보다 시간을 충분히 쓰는 관계에서 진짜 밀도가 드러나는 결입니다.',
  ]),
  // 2. 호기심·다양성 — 한 남자로 만족 못하는 탐색형
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high || f.bandOf(Attribute.sensuality) == _Band.high, [
    '당신의 관능은 \'호기심 자체가 연료가 되는 탐색형\'입니다. 한 번의 만족으로 잠들기보다 다음 장면을 먼저 떠올리는 기질로, 같은 상대 안에서도 다른 온도·다른 각도·다른 속도를 찾아내려는 결이 몸 깊이 박혀 있습니다. 관상학에서는 이를 \'다층 도화상(多層桃花相)\' 이라 부르며, 창의적 관계 설계에서 최대 강점이 됩니다.',
    '\'상상이 먼저 달아오르는\' 결이 유난히 발달한 상입니다. 한 장면이 머릿속에서 여러 번 재생되며 매번 다른 디테일이 붙는 유형이며, 몽상과 현실 사이의 경계가 얇은 만큼 상대와 공유하는 순간 관능의 농도가 비약적으로 올라가는 결입니다. 단조로움을 가장 견디지 못하는 기질이기도 합니다.',
  ]),
  // 3. 상상·감각 발달형
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high, [
    '당신의 관능은 \'감각의 해상도\'가 유난히 높은 결입니다. 상대의 손이 닿는 면적·목소리의 낮은 떨림·호흡 사이 0.5초 멈춤 하나하나가 몸 안에서 파동을 일으키는 유형이며, 이 예민함이 상상 속에서 먼저 장면을 완성시킵니다. 혼자의 밤에도 머릿속 시나리오가 @{deep} 구체화되는 결은 실제 관계에서 섬세한 인도자가 되는 자산입니다.',
  ]),
  // 4. 암시·여우형
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high && f.bandOf(Attribute.attractiveness) == _Band.high, [
    '당신의 관능은 암시와 여백으로 작동하는 \'여우상(狐相)\'의 결입니다. 정면 시선 대신 비껴주는 각도, 말 끝의 멈춤, 살짝 기울인 고개에 드러나는 목선에 관능의 본체가 숨어 있으며, 상대는 당신이 말하지 않은 부분에서 혼자 먼 길을 다녀오게 됩니다. 침실에서도 드러냄보다 감춤의 리듬을 쥐고 흔드는 유형입니다.',
  ]),
  // 5. 직선·원색형
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high && f.bandOf(Attribute.attractiveness) != _Band.high, [
    '당신의 관능은 직선적 원색의 \'해당화상(海棠花相)\'의 결입니다. @{palace_sex}의 기색이 감추어지지 않는 상으로, 원하는 것을 몸으로 먼저 표현하는 솔직한 유형입니다. 우회와 암시 없이 존재 자체가 상대에게 @{intense} 즉각적인 온도로 전달되며, 이 솔직함이 오히려 가장 매혹적인 결로 작동합니다.',
  ]),
  // 6. 정돈·월궁형
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.libido) != _Band.high, [
    '당신의 관능은 정돈된 기품 중심의 \'월궁상(月宮相)\'의 결입니다. 색의 강도가 아니라 골격과 오관의 균형 안에 @{faint} 스며 있는 농도가 성격을 결정하며, 가까워질수록 넘지 말아야 할 선이 먼저 느껴지는 거리감이 오히려 매력의 축으로 작동합니다. 침실에서조차 흐트러지지 않는 결이 상대를 더 깊이 빨아들이는 유형입니다.',
  ]),
  // 7. 감정·정화형
  _Frag(_highOf(Attribute.emotionality), [
    '당신의 관능은 감정 기반의 \'정화상(情花相)\'의 결입니다. 눈매에 정(情)이 어리는 상으로, 감정의 깊이에서 피어오르는 밀도가 상대의 마음을 붙잡으며, 울컥하거나 웃음을 참는 감정의 경계에서 결정적 농도가 발생합니다. 관계의 깊이와 관능의 농도가 평행하게 자라는 드문 결입니다.',
  ]),
  // 8. 암도화 (fallback) — 비밀스러운 섬광형
  _Frag((f) => true, [
    '당신의 관능은 \'암도화상(暗桃花相)\'의 결입니다. 얼굴 전체에 색이 퍼져 있지 않고 특정 각도·특정 빛·특정 상대 앞에서만 순간적으로 피어나는 구조이며, 평소에는 거의 느껴지지 않다가 무방비한 한 장면에서 상대의 기억에 불로 새겨집니다. 스치듯 드러나는 섬광이 오래 남는 잔상을 만드는 유형입니다.',
    '당신의 관능은 \'이중 감각형\' 입니다. 겉으로 드러나는 차분함과 몸 안에서 일어나는 작은 파동의 간극이 큰 결이며, 상대가 이 간극을 처음 발견하는 순간이 관계의 전환점이 됩니다. 보이는 것보다 느끼는 것이 훨씬 풍부한 유형입니다.',
  ]),
];

final List<_Frag> _sensualStrengthFemale = [
  _Frag((f) => f.fired('O-EM') || f.fired('O-PH2'), [
    '입의 윤곽과 인중의 결이 살아 있는 구조는 \'수분기(水分氣)\'가 풍부한 상으로, 목소리의 낮은 울림·숨결의 간격·발음의 리듬이 관능의 또 다른 경로로 작동합니다. 귓가에 닿는 한 마디가 손끝의 접촉보다 먼저 불을 붙이는 유형입니다.',
    '입·인중의 결이 살아 있는 구조는 언어와 숨이 관능의 도구가 되는 결이며, 상대가 당신의 목소리만으로도 밤의 장면을 미리 상상하게 만드는 힘을 가집니다.',
  ]),
  _Frag(_highOf(Attribute.emotionality), [
    '감정의 공명이 몸의 반응으로 이어지는 결이어서, 감정적 결합이 깊을수록 관능의 농도가 오히려 @{intense} 올라가는 비약적 구조를 가졌습니다. 마음이 먼저 열려야 몸이 따라오는 유형이며, 이 순서가 지켜질 때 농도의 상한이 가장 높아집니다.',
  ]),
  _Frag((f) => true, [
    '당신의 관능은 만족의 선이 서기 전엔 가라앉지 않는 결입니다. 서두르는 상대와 만나면 허기감이 누적되지만, 기다릴 줄 아는 상대 앞에선 물결처럼 반복되는 농도로 보답하는 유형이며, 여러 번의 작은 파동이 하나의 큰 만족으로 수렴하는 구조입니다.',
    '당신의 관능은 \'디테일에 불이 붙는\' 결입니다. 침대 시트의 감촉·조명의 각도·상대의 체온 변화 같은 미세한 요소 하나하나가 장면의 색을 결정하며, 이 섬세함을 공유할 수 있는 상대 앞에서 진짜 농도가 드러납니다.',
    '\'같은 상대와도 매번 다른 결\' 을 만들어낼 수 있는 창의력이 핵심 자산입니다. 속도를 바꾸거나 각도 하나를 틀면 다른 밤이 되는 결이어서, 단조로움에 빠질 위험이 구조적으로 낮습니다.',
  ]),
];

final List<_Frag> _sensualShadowFemale = [
  // 1. 상상 과잉 — 현실이 못 따라오는 그림자
  _Frag((f) => f.bandOf(Attribute.sensuality) == _Band.high, [
    '다만 당신의 관능은 내부에서 끊임없이 새로운 장면을 만들어내는 결이어서, 현실의 관계가 그 상상의 풍부함을 따라오지 못할 때 좌절감이 누적됩니다. 관상학에서는 이를 \'환영의 갈증\' 이라 부르며, 실제 상대와의 구체적 대화와 요청 없이는 평생 채워지지 않는 구조입니다.',
  ]),
  // 2. 호기심 외부 유출
  _Frag((f) => f.bandOf(Attribute.libido) == _Band.high, [
    '다만 한 상대로 만족하지 못하는 호기심이 외부로 새면 관계의 뿌리가 흔들립니다. 여성의 다층 도화상은 \'창의적 재사용\' 의 기질이어서, 탐색의 에너지를 \'현재 상대와의 새로운 각도\' 로 돌릴 때 최고 농도가 나옵니다. 외부로 새는 순간 결이 얇아집니다.',
  ]),
  // 3. 감정 공백 — 가장 위험한 구간
  _Frag((f) => f.bandOf(Attribute.emotionality) == _Band.high && f.bandOf(Attribute.stability) != _Band.high, [
    '다만 감정의 파고가 관능의 방향을 결정하는 결이어서, 감정적 결핍이 쌓이는 시기엔 관능이 관계 밖으로 틀어지기 쉽습니다. 여성 관상에서 가장 위험한 구간은 침실의 권태가 아니라 감정 대화의 공백이며, 그 공백이 탐색의 방향을 관계 밖으로 돌립니다.',
  ]),
  // 4. 기품 거리감
  _Frag((f) => f.bandOf(Attribute.attractiveness) == _Band.high && f.bandOf(Attribute.libido) != _Band.high, [
    '다만 \'기품의 거리감\' 이 관능의 활력을 억제하기도 합니다. 먼저 다가오지 못하게 만드는 결이 유혹의 긴장감이 되기도 하지만, 침실에서조차 무장을 유지하면 상대가 \'내가 여기까지 와도 되는지\' 망설이는 순간이 반복되며, 흐트러짐 자체가 매혹이 될 수 있다는 점을 받아들이는 훈련이 필요합니다.',
  ]),
  // 5. 언어 부재 (fallback)
  _Frag((f) => true, [
    '다만 관능의 기질이 언어화되지 않으면 상대가 당신이 원하는 것을 읽어내지 못합니다. 암시의 우아함이 강점이지만, 결정적 순간에는 직접적 요청이 더 깊은 만족을 만드는 결이므로 말의 용기가 평생의 자산입니다.',
    '다만 \'몸의 주기\' 와 \'감정의 주기\' 가 어긋나는 날이 쌓이면 관능의 결도 함께 둔해집니다. 두 리듬을 스스로 읽는 기록 습관 없이는 관능이 상황에 휘둘리기 쉬운 유형입니다.',
  ]),
];

final List<_Frag> _sensualAdviceFemale = [
  _Frag((f) => true, [
    '관능의 깊이를 오래 가꾸는 @{path_word}은 셋입니다. 첫째, 침실의 풍경을 당신이 설계하십시오 — 빛·향·촉감의 작은 요소가 밤의 밀도를 결정합니다. 둘째, \'원하는 것을 말하는 언어\' 를 기르십시오. 만족의 선이 서기 전에는 욕구가 가라앉지 않는 결이므로, 침묵보다 섬세한 요청이 평생의 관능 수명을 결정합니다. 셋째, 호기심의 에너지를 \'같은 상대와의 다른 각도\' 로 돌릴 때 가장 오래 타는 밀도가 만들어집니다.',
    '관능을 품격 있게 유지하는 @{path_word} — 첫째, 감정의 대화와 몸의 대화를 나란히 가꾸십시오. 여성 관상에서는 감정 공백이 관능을 가장 먼저 식게 만듭니다. 둘째, 상상과 현실을 분리하기보다 엮어내십시오 — 당신이 상상한 장면을 관계 안에서 실제로 만들어가는 용기가 필요합니다. 셋째, 몸의 주기와 감정의 주기를 스스로 기록하는 습관이 관능의 롱런을 만듭니다.',
    '관능의 결을 꾸준히 기르는 @{path_word}은 \'감각의 디렉터\' 가 되는 것입니다. 첫째, 당신의 몸이 가장 @{intense} 반응하는 조건(조명·온도·향·음악) 을 명확히 아는 것. 둘째, 관계의 리듬을 당신이 리드하는 쪽으로 재설정 — 받기만 하는 결에서 벗어나 원하는 장면을 제안하는 것. 셋째, 상대의 만족 신호를 읽어 응답하는 섬세한 순환 구조를 만들 때, 관능은 시간이 지날수록 오히려 깊어집니다.',
  ]),
];

final List<_BeatPool> _sensualBeatsFemale = [
  _sensualOpeningFemale,
  _sensualStrengthFemale,
  _sensualShadowFemale,
  _sensualAdviceFemale,
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

