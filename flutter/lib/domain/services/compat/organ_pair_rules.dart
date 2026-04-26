/// 五官 (organ) 1:1 pair matcher — 眉·目·鼻·口.
///
/// §4 spec: 각 organ 마다 pattern → delta + verdict. 한 pair 에서 organ
/// 별로 여러 pattern 이 match 가능 (eyebrow 는 상호 배타지만 mouth/nose 는
/// 중첩 허용 — cap ±28 로 막음). 耳 는 현 metric 부재 → skip.
///
/// 산출:
/// ```
/// organSubScore = 50
///   + Σ_organ clamp(Σ ruleDelta_organ, -28, +28) * organWeight
/// // organWeight: eye 0.34, mouth 0.26, nose 0.24, brow 0.16
/// // clamp 5~99
/// ```
library;

enum CompatOrgan { eyebrow, eye, nose, mouth }

extension CompatOrganLabel on CompatOrgan {
  String get hanja {
    switch (this) {
      case CompatOrgan.eyebrow:
        return '眉';
      case CompatOrgan.eye:
        return '目';
      case CompatOrgan.nose:
        return '鼻';
      case CompatOrgan.mouth:
        return '口';
    }
  }

  /// 한국어 이름. 해설문에서 이걸 우선 쓴다.
  String get korean {
    switch (this) {
      case CompatOrgan.eyebrow:
        return '눈썹';
      case CompatOrgan.eye:
        return '눈';
      case CompatOrgan.nose:
        return '코';
      case CompatOrgan.mouth:
        return '입';
    }
  }
}

class OrganPairEvidence {
  final String ruleId;
  final CompatOrgan organ;
  final double delta;
  final String verdict;

  const OrganPairEvidence({
    required this.ruleId,
    required this.organ,
    required this.delta,
    required this.verdict,
  });
}

class OrganPairResult {
  final double subScore; // 5~99
  final List<OrganPairEvidence> evidence;

  const OrganPairResult({required this.subScore, required this.evidence});
}

/// organ 별 sub-score 기여 weight (§4.5).
const Map<CompatOrgan, double> _organWeight = {
  CompatOrgan.eye: 0.34,
  CompatOrgan.mouth: 0.26,
  CompatOrgan.nose: 0.24,
  CompatOrgan.eyebrow: 0.16,
};

const double _organBaseline = 50.0;
const double _organCap = 28.0;

/// rule 정의. matcher 는 두 zMap + two lateralFlag map 을 받아 boolean 반환.
typedef OrganMatcher = bool Function(
  Map<String, double> myZ,
  Map<String, double> albumZ,
  Map<String, bool> myFlags,
  Map<String, bool> albumFlags,
);

class OrganRule {
  final String id;
  final CompatOrgan organ;
  final OrganMatcher matcher;
  final double delta;
  final String verdict;

  const OrganRule({
    required this.id,
    required this.organ,
    required this.matcher,
    required this.delta,
    required this.verdict,
  });
}

// ────────── helper ──────────
double _z(Map<String, double> m, String id) => m[id] ?? 0.0;
bool _flag(Map<String, bool> m, String id) => m[id] ?? false;

bool _bothAbove(Map<String, double> a, Map<String, double> b, String id, double th) =>
    _z(a, id) >= th && _z(b, id) >= th;
bool _bothBelow(Map<String, double> a, Map<String, double> b, String id, double th) =>
    _z(a, id) <= th && _z(b, id) <= th;
bool _oneAboveOneBelow(
        Map<String, double> a, Map<String, double> b, String id, double hi, double lo) =>
    (_z(a, id) >= hi && _z(b, id) <= lo) || (_z(b, id) >= hi && _z(a, id) <= lo);

// ────────── 眉 (eyebrow) matcher ──────────

bool _brBothThick(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'eyebrowThickness', 0.7);
bool _brThickThin(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _oneAboveOneBelow(a, b, 'eyebrowThickness', 0.6, -0.6);
bool _brBothThinBright(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothBelow(a, b, 'eyebrowThickness', -0.4) &&
    _bothAbove(a, b, 'browEyeDistance', 0.3);
bool _brBothBalanced(Map<String, double> a, Map<String, double> b,
    Map<String, bool> af, Map<String, bool> bf) {
  final aa = _z(a, 'eyebrowThickness');
  final bb = _z(b, 'eyebrowThickness');
  return aa.abs() < 0.4 && bb.abs() < 0.4;
}

// ────────── 目 (eye) matcher ──────────

bool _eyeFenghuangTaohua(Map<String, double> a, Map<String, double> b,
    Map<String, bool> af, Map<String, bool> bf) {
  // 鳳眼(tilt 강) × 桃花眼 (lipFullness 강) — 한 명 tilt, 다른 명 촉촉.
  final aTilt = _z(a, 'eyeCanthalTilt');
  final bTilt = _z(b, 'eyeCanthalTilt');
  final aLip = _z(a, 'lipFullnessRatio');
  final bLip = _z(b, 'lipFullnessRatio');
  return (aTilt >= 0.8 && bLip >= 0.8) || (bTilt >= 0.8 && aLip >= 0.8);
}

bool _eyeBothDragon(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'eyeFissureRatio', 0.5) &&
    _z(a, 'eyeCanthalTilt').abs() < 0.7 &&
    _z(b, 'eyeCanthalTilt').abs() < 0.7;

bool _eyeBothPeach(Map<String, double> a, Map<String, double> b,
    Map<String, bool> af, Map<String, bool> bf) {
  final lipA = _z(a, 'lipFullnessRatio');
  final lipB = _z(b, 'lipFullnessRatio');
  final tiltA = _z(a, 'eyeCanthalTilt');
  final tiltB = _z(b, 'eyeCanthalTilt');
  return lipA >= 0.8 && lipB >= 0.8 && tiltA >= 0.3 && tiltB >= 0.3;
}

bool _eyeDroopingBoth(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothBelow(a, b, 'eyeCanthalTilt', -0.6);

bool _eyeSharpSoft(Map<String, double> a, Map<String, double> b,
    Map<String, bool> af, Map<String, bool> bf) {
  final aSharp = _z(a, 'eyeCanthalTilt') >= 0.7 && _z(a, 'eyeFissureRatio') <= -0.2;
  final bSoft = _z(b, 'eyeCanthalTilt') <= -0.2 && _z(b, 'eyeFissureRatio') >= 0.3;
  final bSharp = _z(b, 'eyeCanthalTilt') >= 0.7 && _z(b, 'eyeFissureRatio') <= -0.2;
  final aSoft = _z(a, 'eyeCanthalTilt') <= -0.2 && _z(a, 'eyeFissureRatio') >= 0.3;
  return (aSharp && bSoft) || (bSharp && aSoft);
}

// ────────── 鼻 (nose) matcher ──────────

bool _noseBothHighBridge(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'nasalHeightRatio', 0.7);
bool _noseHighVsModest(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _oneAboveOneBelow(a, b, 'nasalHeightRatio', 0.6, -0.4);
bool _noseBothAquiline(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _flag(af, 'aquilineNose') && _flag(bf, 'aquilineNose');
bool _noseAquilineSnub(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    (_flag(af, 'aquilineNose') && _flag(bf, 'snubNose')) ||
    (_flag(bf, 'aquilineNose') && _flag(af, 'snubNose'));
bool _noseGarlicBoth(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'nasalWidthRatio', 0.7);
bool _noseThinBoth(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothBelow(a, b, 'nasalWidthRatio', -0.7);

// ────────── 口 (mouth) matcher ──────────

bool _mouthBothFullLip(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'lipFullnessRatio', 0.7);
bool _mouthBigVsSmall(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    (_z(a, 'mouthWidthRatio') - _z(b, 'mouthWidthRatio')).abs() >= 1.2;
bool _mouthBothWideSmile(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothAbove(a, b, 'mouthCornerAngle', 0.4);
bool _mouthBothCornerDown(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothBelow(a, b, 'mouthCornerAngle', -0.4);
bool _mouthCherrySmallBoth(Map<String, double> a, Map<String, double> b,
        Map<String, bool> af, Map<String, bool> bf) =>
    _bothBelow(a, b, 'mouthWidthRatio', -0.5) &&
    _bothBelow(a, b, 'lipFullnessRatio', -0.3);

// ────────── 전체 rule 카탈로그 ──────────

const List<OrganRule> organRules = [
  // ──── 眉 (eyebrow) — weight 0.16 ─────────────────────────────────
  OrganRule(
    id: 'OP-BR-BOTH-THICK',
    organ: CompatOrgan.eyebrow,
    matcher: _brBothThick,
    delta: -8,
    verdict: '두 분 모두 눈썹(眉)이 짙고 굵어 의지가 강한 쪽끼리 만난 모양입니다. 서로 자기 뜻을 꺾지 않으려 해 작은 일에서도 불꽃이 자주 일 수 있으니, 한 박자 쉬고 듣는 연습이 관계를 지켜 줍니다.',
  ),
  OrganRule(
    id: 'OP-BR-THICK-THIN',
    organ: CompatOrgan.eyebrow,
    matcher: _brThickThin,
    delta: 14,
    verdict: '한 분은 짙은 눈썹, 다른 분은 맑고 가는 눈썹입니다. 이끄는 이와 따라가는 이의 결이 자연스럽게 나뉘어 역할 분담이 편안하게 맞물리는 조합입니다.',
  ),
  OrganRule(
    id: 'OP-BR-BOTH-BALANCED',
    organ: CompatOrgan.eyebrow,
    matcher: _brBothBalanced,
    delta: 6,
    verdict: '두 분의 눈썹이 모두 적당한 농도로 단정합니다. 감정이 한쪽 극단으로 치우치지 않아 일상이 잔잔히 흐르기 좋은 상(相)입니다.',
  ),
  OrganRule(
    id: 'OP-BR-BOTH-BRIGHT',
    organ: CompatOrgan.eyebrow,
    matcher: _brBothThinBright,
    delta: 10,
    verdict: '두 분 모두 눈썹이 맑고 눈썹과 눈 사이(田宅宮 언저리)가 넓게 트였습니다. 고전에서는 이 모양을 이성적 판단이 나란히 빛나는 조용한 궁합으로 읽습니다.',
  ),

  // ──── 目 (eye) — weight 0.34 ─────────────────────────────────────
  OrganRule(
    id: 'OP-EY-FENG-TAOHUA',
    organ: CompatOrgan.eye,
    matcher: _eyeFenghuangTaohua,
    delta: 24,
    verdict: '한 분은 눈꼬리가 살짝 올라간 봉황눈(鳳眼)의 기운이 강하고, 다른 분은 입술이 도톰해 도화(桃花)의 결을 갖추셨습니다. 전통 관상학에서 가장 잘 어울린다고 꼽는 이상적인 조합으로, 단단함과 촉촉함이 한 짝으로 맞물립니다.',
  ),
  OrganRule(
    id: 'OP-EY-BOTH-DRAGON',
    organ: CompatOrgan.eye,
    matcher: _eyeBothDragon,
    delta: 10,
    verdict: '두 분 모두 눈이 크면서도 흘러내리지 않는 용안(龍眼)의 기세를 갖추셨습니다. 기개 있는 눈끼리 만나 서로의 세계를 깎아내리지 않고 존중하는 모양입니다.',
  ),
  OrganRule(
    id: 'OP-EY-BOTH-PEACH',
    organ: CompatOrgan.eye,
    matcher: _eyeBothPeach,
    delta: -4,
    verdict: '두 분 모두 입술이 도톰하고 눈꼬리가 살짝 올라간 도화(桃花)의 결을 갖추셨습니다. 초반의 끌림은 유난히 강하지만 시선이 각각 다른 곳으로 향할 수 있어, 서로만 바라보겠다는 의식적 다짐이 필요합니다.',
  ),
  OrganRule(
    id: 'OP-EY-DROOPING-BOTH',
    organ: CompatOrgan.eye,
    matcher: _eyeDroopingBoth,
    delta: -12,
    verdict: '두 분 모두 눈꼬리가 아래로 처져 권태로운 기운(慵眼)이 겹칩니다. 무기력이 함께 가라앉기 쉬운 결이라, 일부러 활력을 불어넣을 일을 만들어야 관계의 온도가 유지됩니다.',
  ),
  OrganRule(
    id: 'OP-EY-SHARP-SOFT',
    organ: CompatOrgan.eye,
    matcher: _eyeSharpSoft,
    delta: 18,
    verdict: '한 분의 눈은 날카롭게 위로 뻗고 다른 분의 눈은 크고 둥글게 부드럽습니다. 강(剛)과 유(柔)가 서로의 빈자리를 정확히 메우는 조합이라, 고전에서는 이 짝을 오래가는 결합으로 봅니다.',
  ),

  // ──── 鼻 (nose) — weight 0.24 ────────────────────────────────────
  OrganRule(
    id: 'OP-NS-BOTH-HIGH',
    organ: CompatOrgan.nose,
    matcher: _noseBothHighBridge,
    delta: -6,
    verdict: '두 분 모두 콧대가 높아 재운(財運)은 나란히 강합니다. 다만 주도권과 자존심이 비슷한 높이라 돈·일의 결정을 두고 부딪힐 여지가 있으니, 영역을 미리 나누어 두는 편이 좋습니다.',
  ),
  OrganRule(
    id: 'OP-NS-HIGH-MODEST',
    organ: CompatOrgan.nose,
    matcher: _noseHighVsModest,
    delta: 10,
    verdict: '한 분의 콧대는 높고 다른 분의 콧대는 낮은 편입니다. 경제 주도권이 자연스럽게 한쪽으로 기울고 다른 쪽이 살림의 결을 다듬는 구도라, 돈 문제로 다툴 일이 적은 조합입니다.',
  ),
  OrganRule(
    id: 'OP-NS-BOTH-AQUILINE',
    organ: CompatOrgan.nose,
    matcher: _noseBothAquiline,
    delta: -14,
    verdict: '두 분 모두 코에 매부리(鉤) 기운이 있어 자존심과 이익 계산이 날카롭게 섭니다. 같은 성향끼리 부딪히면 사소한 손익 문제에도 예민해지기 쉬우니, 한 쪽이 먼저 양보하는 신호를 미리 정해 두시면 좋습니다.',
  ),
  OrganRule(
    id: 'OP-NS-AQUI-SNUB',
    organ: CompatOrgan.nose,
    matcher: _noseAquilineSnub,
    delta: 12,
    verdict: '한 분의 코는 야심 어린 매부리 결, 다른 분의 코는 귀염성 있는 들창의 결입니다. 야망과 애교가 의외로 잘 어울리는 한 쌍으로, 서로의 부족한 부분을 정확히 메워 줍니다.',
  ),
  OrganRule(
    id: 'OP-NS-GARLIC-BOTH',
    organ: CompatOrgan.nose,
    matcher: _noseGarlicBoth,
    delta: 16,
    verdict: '두 분 모두 콧방울이 풍성한 복스러운 모양(蒜頭)입니다. 화려함보다 끈기 있는 재물의 결이라, 함께 알뜰히 쌓아 올리는 살림에 유리한 조합입니다.',
  ),
  OrganRule(
    id: 'OP-NS-THIN-BOTH',
    organ: CompatOrgan.nose,
    matcher: _noseThinBoth,
    delta: -10,
    verdict: '두 분 모두 콧대가 칼처럼 가늘고 예민합니다. 계산이 날카로운 기운이 겹쳐 작은 돈 문제에도 날이 설 수 있으니, 지출 원칙을 미리 합의해 두는 편이 관계를 지켜 줍니다.',
  ),

  // ──── 口 (mouth) — weight 0.26 ───────────────────────────────────
  OrganRule(
    id: 'OP-MO-BOTH-FULL',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothFullLip,
    delta: 12,
    verdict: '두 분의 입술이 모두 도톰하고 윤기가 돕니다. 감각적으로 쉽게 공명해 대화가 메마르지 않고 부드럽게 흐르는 조합입니다.',
  ),
  OrganRule(
    id: 'OP-MO-BIG-SMALL',
    organ: CompatOrgan.mouth,
    matcher: _mouthBigVsSmall,
    delta: 10,
    verdict: '한 분의 입은 크고 다른 분의 입은 작아 말의 양이 자연스럽게 나뉘는 결입니다. 말하는 이와 듣는 이의 역할이 억지 없이 맞아 들어가는 조합입니다.',
  ),
  OrganRule(
    id: 'OP-MO-WIDE-SMILE',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothWideSmile,
    delta: 10,
    verdict: '두 분 모두 입꼬리가 위로 올라가 웃음기가 자주 맺히는 상입니다. 나란히 웃는 집안은 복이 스스로 찾아든다고 하니, 이 조합의 일상 행복 지수가 높습니다.',
  ),
  OrganRule(
    id: 'OP-MO-CORNER-DOWN',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothCornerDown,
    delta: -14,
    verdict: '두 분 모두 입꼬리가 아래로 처져 있어 침묵이 쉽게 깔리는 조합입니다. 말로 풀지 않으면 벽이 금방 단단해지니, 사소한 감정도 소리 내어 전하는 습관이 필요합니다.',
  ),
  OrganRule(
    id: 'OP-MO-CHERRY-SMALL',
    organ: CompatOrgan.mouth,
    matcher: _mouthCherrySmallBoth,
    delta: -6,
    verdict: '두 분 모두 입이 작고 얇아 표현이 조심스러운 결입니다. 같이 있으면 마음이 움츠러들기 쉬우니, 편지·메모처럼 부담이 적은 창구로라도 감정을 자주 내어 보이셔야 합니다.',
  ),
];

/// sub-score 계산.
OrganPairResult organPairScore({
  required Map<String, double> myZ,
  required Map<String, double> albumZ,
  required Map<String, bool> myFlags,
  required Map<String, bool> albumFlags,
}) {
  final evidence = <OrganPairEvidence>[];
  final perOrganDelta = <CompatOrgan, double>{
    for (final o in CompatOrgan.values) o: 0.0,
  };

  for (final rule in organRules) {
    if (rule.matcher(myZ, albumZ, myFlags, albumFlags)) {
      perOrganDelta[rule.organ] = (perOrganDelta[rule.organ] ?? 0) + rule.delta;
      evidence.add(OrganPairEvidence(
        ruleId: rule.id,
        organ: rule.organ,
        delta: rule.delta,
        verdict: rule.verdict,
      ));
    }
  }

  double total = _organBaseline;
  for (final o in CompatOrgan.values) {
    final capped = (perOrganDelta[o] ?? 0.0).clamp(-_organCap, _organCap);
    total += capped * (_organWeight[o] ?? 0.0);
  }

  final sub = total.clamp(5.0, 99.0);
  return OrganPairResult(subScore: sub, evidence: evidence);
}
