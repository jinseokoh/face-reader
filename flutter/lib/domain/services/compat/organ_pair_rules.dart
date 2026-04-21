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
    verdict: '雙濃相對 — 의지 둘이 맞부딪혀 불꽃이 잦습니다.',
  ),
  OrganRule(
    id: 'OP-BR-THICK-THIN',
    organ: CompatOrgan.eyebrow,
    matcher: _brThickThin,
    delta: 14,
    verdict: '一濃一淡 — 이끄는 이와 따르는 이의 호흡이 자연스럽습니다.',
  ),
  OrganRule(
    id: 'OP-BR-BOTH-BALANCED',
    organ: CompatOrgan.eyebrow,
    matcher: _brBothBalanced,
    delta: 6,
    verdict: '眉宇調和 — 감정이 극단으로 치우치지 않는 조합.',
  ),
  OrganRule(
    id: 'OP-BR-BOTH-BRIGHT',
    organ: CompatOrgan.eyebrow,
    matcher: _brBothThinBright,
    delta: 10,
    verdict: '眉淸宇開 — 이성적 판단이 나란히 빛나는 조용한 궁합.',
  ),

  // ──── 目 (eye) — weight 0.34 ─────────────────────────────────────
  OrganRule(
    id: 'OP-EY-FENG-TAOHUA',
    organ: CompatOrgan.eye,
    matcher: _eyeFenghuangTaohua,
    delta: 24,
    verdict: '鳳配桃花 宜室宜家 — 단단한 눈매와 촉촉한 입술이 가장 조화로운 조합.',
  ),
  OrganRule(
    id: 'OP-EY-BOTH-DRAGON',
    organ: CompatOrgan.eye,
    matcher: _eyeBothDragon,
    delta: 10,
    verdict: '雙龍相對 — 기개 있는 눈끼리 서로의 세계를 인정합니다.',
  ),
  OrganRule(
    id: 'OP-EY-BOTH-PEACH',
    organ: CompatOrgan.eye,
    matcher: _eyeBothPeach,
    delta: -4,
    verdict: '雙桃相映 — 초반 끌림은 강하나 시선이 서로를 벗어나기 쉽습니다.',
  ),
  OrganRule(
    id: 'OP-EY-DROOPING-BOTH',
    organ: CompatOrgan.eye,
    matcher: _eyeDroopingBoth,
    delta: -12,
    verdict: '雙慵眼 — 무기력이 겹쳐 관계 온도가 식어갑니다.',
  ),
  OrganRule(
    id: 'OP-EY-SHARP-SOFT',
    organ: CompatOrgan.eye,
    matcher: _eyeSharpSoft,
    delta: 18,
    verdict: '剛柔相濟 — 날카로움과 부드러움이 한 짝으로 물립니다.',
  ),

  // ──── 鼻 (nose) — weight 0.24 ────────────────────────────────────
  OrganRule(
    id: 'OP-NS-BOTH-HIGH',
    organ: CompatOrgan.nose,
    matcher: _noseBothHighBridge,
    delta: -6,
    verdict: '雙峰對峙 — 재운은 강하나 주도권이 비슷해 충돌 여지가 큽니다.',
  ),
  OrganRule(
    id: 'OP-NS-HIGH-MODEST',
    organ: CompatOrgan.nose,
    matcher: _noseHighVsModest,
    delta: 10,
    verdict: '一高一平 — 경제 주도가 자연스럽게 갈라집니다.',
  ),
  OrganRule(
    id: 'OP-NS-BOTH-AQUILINE',
    organ: CompatOrgan.nose,
    matcher: _noseBothAquiline,
    delta: -14,
    verdict: '雙鉤相擊 — 자존심·이익 계산이 사사건건 부딪힙니다.',
  ),
  OrganRule(
    id: 'OP-NS-AQUI-SNUB',
    organ: CompatOrgan.nose,
    matcher: _noseAquilineSnub,
    delta: 12,
    verdict: '鉤鼻配獅鼻 — 야심과 애교가 의외로 어울립니다.',
  ),
  OrganRule(
    id: 'OP-NS-GARLIC-BOTH',
    organ: CompatOrgan.nose,
    matcher: _noseGarlicBoth,
    delta: 16,
    verdict: '雙蒜齊立 — 소박하고 끈기 있는 재물 궁합.',
  ),
  OrganRule(
    id: 'OP-NS-THIN-BOTH',
    organ: CompatOrgan.nose,
    matcher: _noseThinBoth,
    delta: -10,
    verdict: '雙刀鼻 — 계산적 강박이 겹쳐 날 서게 다툽니다.',
  ),

  // ──── 口 (mouth) — weight 0.26 ───────────────────────────────────
  OrganRule(
    id: 'OP-MO-BOTH-FULL',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothFullLip,
    delta: 12,
    verdict: '雙唇豊艶 — 감각적 공명이 대화의 결을 부드럽게 합니다.',
  ),
  OrganRule(
    id: 'OP-MO-BIG-SMALL',
    organ: CompatOrgan.mouth,
    matcher: _mouthBigVsSmall,
    delta: 10,
    verdict: '一大一小 — 말하는 이와 듣는 이의 역할이 자연스럽습니다.',
  ),
  OrganRule(
    id: 'OP-MO-WIDE-SMILE',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothWideSmile,
    delta: 10,
    verdict: '雙笑迎門 — 일상의 행복 지수가 함께 오릅니다.',
  ),
  OrganRule(
    id: 'OP-MO-CORNER-DOWN',
    organ: CompatOrgan.mouth,
    matcher: _mouthBothCornerDown,
    delta: -14,
    verdict: '雙角下垂 — 침묵의 벽이 쉽게 세워지는 조합.',
  ),
  OrganRule(
    id: 'OP-MO-CHERRY-SMALL',
    organ: CompatOrgan.mouth,
    matcher: _mouthCherrySmallBoth,
    delta: -6,
    verdict: '雙櫻口小 — 표현이 함께 움츠러드는 경향.',
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
