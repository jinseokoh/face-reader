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

  // ── 상정 (이마·사상·배움) ──
  if (_bothStrong(mu, au)) {
    add('ZP-UP-BOTH-STRONG', 6,
        '두 분 다 이마가 훤히 트여, 책·뉴스·관심 분야 대화가 자연스럽게 오가는 관계입니다.');
  } else if (_bothWeak(mu, au)) {
    add('ZP-UP-BOTH-WEAK', -12,
        '두 분 다 이마가 얇아, 장기 계획이나 큰 그림을 함께 세우는 데 서툰 편입니다.');
  } else if (_oneStrongOneBal(mu, au)) {
    add('ZP-UP-ONE-STRONG', 3,
        '한 분의 이마가 유독 트여 있어, 그 쪽이 관계의 방향과 이상을 이끌어 가는 모양입니다.');
  } else if (_oneStrongOneWeak(mu, au)) {
    add('ZP-UP-CROSS', 0,
        '이마 발달 정도 차이가 커, 가치관과 배움의 속도 차이가 서로에게 자극이 됩니다.');
  }

  // ── 중정 (광대·코·의지·추진력) ──
  if (_bothStrong(mm, am)) {
    add('ZP-MID-BOTH-STRONG', -6,
        '두 분 다 얼굴 중간이 강해, 의지끼리 부딪혀 주도권 다툼이 자주 생기는 조합입니다.');
  } else if (_bothWeak(mm, am)) {
    add('ZP-MID-BOTH-WEAK', -10,
        '두 분 다 중간 얼굴이 약해, 일 추진력이 함께 느슨해져 결정이 자꾸 미뤄지는 경향이 있습니다.');
  } else if (_oneStrongOneBal(mm, am)) {
    add('ZP-MID-ONE-STRONG', 6,
        '한 분이 뚜렷한 추진력을 쥐고 있어, 실행의 축을 잡아 주는 구도입니다.');
  } else if (_oneStrongOneWeak(mm, am)) {
    add('ZP-MID-CROSS', 2,
        '추진력 격차가 커서, 자연스럽게 리드와 서포트 역할이 나뉘는 관계입니다.');
  }

  // ── 하정 (턱·입·정·애정) ──
  if (_bothStrong(ml, al)) {
    add('ZP-LO-BOTH-STRONG', 8,
        '두 분 다 턱이 두텁고 단단해, 가족·자녀·가까운 이에 대한 정이 함께 깊은 조합입니다.');
  } else if (_bothWeak(ml, al)) {
    add('ZP-LO-BOTH-WEAK', -18,
        '두 분 다 턱이 얇아, 애정 표현과 감정 나눔이 함께 수줍어 오해가 쌓이기 쉬운 조합입니다.');
  } else if (_oneStrongOneBal(ml, al)) {
    add('ZP-LO-ONE-STRONG', 4,
        '한 분의 턱이 두터워, 그 쪽의 따뜻함이 둘 사이의 정을 채워 주는 모양입니다.');
  } else if (_oneStrongOneWeak(ml, al)) {
    add('ZP-LO-CROSS', 0,
        '정의 농도가 서로 달라, 오히려 애정 표현 방식을 서로에게서 배우게 됩니다.');
  }

  // ── 교차 구조 pattern (상정×하정 대각) ──
  // 한 명 上 우세 × 한 명 下 우세 — 이상·현실 상호보완.
  final crossDiag1 = mu.isStrong && al.isStrong && !mm.isStrong && !am.isStrong;
  final crossDiag2 = au.isStrong && ml.isStrong && !mm.isStrong && !am.isStrong;
  if (crossDiag1 || crossDiag2) {
    add('ZP-XC-UP-DOWN', 8,
        '한 분은 이마(이상), 다른 분은 턱(정)이 강해, 큰 그림과 살림 감각이 정확히 맞물리는 구도입니다.');
  }

  // ── 전 zone mirror / complement ──
  final allMirror = _mirror(mu, au) && _mirror(mm, am) && _mirror(ml, al);
  if (allMirror && (mu.isStrong || mu.isWeak)) {
    add('ZP-MIRROR-ALL', 6,
        '이마·중간·턱 세 구획이 모두 닮아, 말하지 않아도 통하는 순간이 자주 만들어집니다.');
  }

  final allComplement = (mu.level != au.level) &&
      (mm.level != am.level) &&
      (ml.level != al.level);
  if (allComplement) {
    add('ZP-COMPLEMENT-ALL', 6,
        '세 구획이 모두 서로 정반대라, 한 사람의 약점을 다른 사람이 정확히 채워 주는 상보 관계입니다.');
  }

  // cap.
  final delta = total.clamp(_zoneCapMin, _zoneCapMax);
  return ZoneHarmony(delta: delta, evidence: evidence, my: my, album: album);
}
