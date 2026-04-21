/// 三停 (삼정) — 상정/중정/하정 zone harmony pair.
///
/// §5 spec:
/// - zone state: 각 zone 의 z 평균 |z|≥0.4 → strong/weak, 그 외 balanced.
///   (docs 원문은 0.6 였지만 3 metric 평균 → std 가 좁아 spread 확보 위해 0.4).
/// - pattern 매칭: 9+ pattern 조합에 delta. mirror / complement / one-strong
///   같은 구조적 pattern 을 더해 narrative 풍부하게.
///
/// 산출: `zoneDelta = clamp(Σ patternDelta, -24, +30)`.
library;

enum FaceZone { upper, middle, lower }

enum ZoneLevel { weak, balanced, strong }

class ZoneState {
  final FaceZone zone;
  final ZoneLevel level;
  final double zMean;

  const ZoneState({required this.zone, required this.level, required this.zMean});

  bool get isStrong => level == ZoneLevel.strong;
  bool get isWeak => level == ZoneLevel.weak;
}

class ZonePatternEvidence {
  final String patternId;
  final double delta;
  final String verdict;

  const ZonePatternEvidence({
    required this.patternId,
    required this.delta,
    required this.verdict,
  });
}

class ZoneHarmony {
  /// -24 ~ +30. qi sub-score 에 주입.
  final double delta;
  final List<ZonePatternEvidence> evidence;
  final Map<FaceZone, ZoneState> my;
  final Map<FaceZone, ZoneState> album;

  const ZoneHarmony({
    required this.delta,
    required this.evidence,
    required this.my,
    required this.album,
  });
}

const double _zoneThreshold = 0.4;

/// zone 별 metric 구성. ratio metric 외에 node-proxy 는 각각 metric 에 포함.
const Map<FaceZone, List<String>> _zoneMetrics = {
  FaceZone.upper: ['upperFaceRatio', 'foreheadWidth', 'browEyeDistance'],
  FaceZone.middle: ['midFaceRatio', 'nasalHeightRatio', 'cheekboneWidth', 'eyeFissureRatio'],
  FaceZone.lower: ['lowerFaceRatio', 'lipFullnessRatio', 'lowerFaceFullness'],
};

Map<FaceZone, ZoneState> computeZoneStates(Map<String, double> zMap) {
  final out = <FaceZone, ZoneState>{};
  for (final zone in FaceZone.values) {
    final ids = _zoneMetrics[zone]!;
    double sum = 0.0;
    int count = 0;
    for (final id in ids) {
      sum += zMap[id] ?? 0.0;
      count++;
    }
    final mean = count == 0 ? 0.0 : sum / count;
    final level = mean >= _zoneThreshold
        ? ZoneLevel.strong
        : mean <= -_zoneThreshold
            ? ZoneLevel.weak
            : ZoneLevel.balanced;
    out[zone] = ZoneState(zone: zone, level: level, zMean: mean);
  }
  return out;
}

// ────────── pattern ──────────

const double _zoneCapMin = -24.0;
const double _zoneCapMax = 30.0;

bool _bothStrong(ZoneState a, ZoneState b) => a.isStrong && b.isStrong;
bool _bothWeak(ZoneState a, ZoneState b) => a.isWeak && b.isWeak;
bool _oneStrongOneWeak(ZoneState a, ZoneState b) =>
    (a.isStrong && b.isWeak) || (a.isWeak && b.isStrong);
bool _oneStrongOneBal(ZoneState a, ZoneState b) =>
    (a.isStrong && b.level == ZoneLevel.balanced) ||
    (b.isStrong && a.level == ZoneLevel.balanced);
bool _mirror(ZoneState a, ZoneState b) => a.level == b.level;

ZoneHarmony matchZoneHarmony({
  required Map<FaceZone, ZoneState> my,
  required Map<FaceZone, ZoneState> album,
}) {
  final evidence = <ZonePatternEvidence>[];
  double total = 0.0;

  void add(String id, double delta, String verdict) {
    evidence.add(
        ZonePatternEvidence(patternId: id, delta: delta, verdict: verdict));
    total += delta;
  }

  final mu = my[FaceZone.upper]!;
  final au = album[FaceZone.upper]!;
  final mm = my[FaceZone.middle]!;
  final am = album[FaceZone.middle]!;
  final ml = my[FaceZone.lower]!;
  final al = album[FaceZone.lower]!;

  // ── 상정 ──
  if (_bothStrong(mu, au)) {
    add('ZP-UP-BOTH-STRONG', 6,
        '上停雙聳 — 사상과 학문의 대화가 공명하는 관계.');
  } else if (_bothWeak(mu, au)) {
    add('ZP-UP-BOTH-WEAK', -12, '上停雙薄 — 큰 그림을 함께 그리기 어려운 조합.');
  } else if (_oneStrongOneBal(mu, au)) {
    add('ZP-UP-ONE-STRONG', 3, '上停一聳 — 한 쪽의 이상이 관계를 이끕니다.');
  } else if (_oneStrongOneWeak(mu, au)) {
    add('ZP-UP-CROSS', 0, '上停高低 — 사상 격차가 서로에게 자극이 됩니다.');
  }

  // ── 중정 (의지) ──
  if (_bothStrong(mm, am)) {
    add('ZP-MID-BOTH-STRONG', -6,
        '中停雙峻 — 의지끼리 부딪혀 주도권 다툼이 생기기 쉽습니다.');
  } else if (_bothWeak(mm, am)) {
    add('ZP-MID-BOTH-WEAK', -10, '中停雙薄 — 일 추진력이 함께 느슨해지는 경향.');
  } else if (_oneStrongOneBal(mm, am)) {
    add('ZP-MID-ONE-STRONG', 6,
        '中停一主 — 한 쪽이 의지의 축이 되어 실행의 바퀴가 구릅니다.');
  } else if (_oneStrongOneWeak(mm, am)) {
    add('ZP-MID-CROSS', 2, '中停高低 — 의지 격차가 역할 분담을 자연스럽게 만듭니다.');
  }

  // ── 하정 (정·애정) ──
  if (_bothStrong(ml, al)) {
    add('ZP-LO-BOTH-STRONG', 8,
        '下停雙厚 — 정과 애정이 공명해 가정의 온기가 깊어집니다.');
  } else if (_bothWeak(ml, al)) {
    add('ZP-LO-BOTH-WEAK', -18, '下停雙薄 — 애정 표현이 함께 수줍은 조합.');
  } else if (_oneStrongOneBal(ml, al)) {
    add('ZP-LO-ONE-STRONG', 4, '下停一厚 — 한 쪽의 따뜻함이 둘 사이를 채웁니다.');
  } else if (_oneStrongOneWeak(ml, al)) {
    add('ZP-LO-CROSS', 0, '下停互補 — 정의 농도가 달라 배움이 생깁니다.');
  }

  // ── 교차 구조 pattern (상정×하정 대각) ──
  // 한 명 上 우세 × 한 명 下 우세 — 이상·현실 상호보완.
  final crossDiag1 = mu.isStrong && al.isStrong && !mm.isStrong && !am.isStrong;
  final crossDiag2 = au.isStrong && ml.isStrong && !mm.isStrong && !am.isStrong;
  if (crossDiag1 || crossDiag2) {
    add('ZP-XC-UP-DOWN', 8,
        '上下交暉 — 한 쪽의 이상과 다른 쪽의 정이 드라마틱하게 맞물립니다.');
  }

  // ── 전 zone mirror / complement ──
  final allMirror = _mirror(mu, au) && _mirror(mm, am) && _mirror(ml, al);
  if (allMirror && (mu.isStrong || mu.isWeak)) {
    add('ZP-MIRROR-ALL', 6, '三停相映 — 사상·의지·정이 모두 닮아 빠르게 통합니다.');
  }

  final allComplement = (mu.level != au.level) &&
      (mm.level != am.level) &&
      (ml.level != al.level);
  if (allComplement) {
    add('ZP-COMPLEMENT-ALL', 6,
        '三停互補 — 세 zone 이 서로 정반대라 드라마틱한 상보 관계.');
  }

  // cap.
  final delta = total.clamp(_zoneCapMin, _zoneCapMax);
  return ZoneHarmony(delta: delta, evidence: evidence, my: my, album: album);
}
