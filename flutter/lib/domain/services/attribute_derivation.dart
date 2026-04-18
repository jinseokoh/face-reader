/// Phase 3 attribute derivation — tree node 기반 10 속성 점수 산출.
///
/// 입력: Phase 2 `scoreTree()` 결과(`NodeScore`) + context(gender, 50+, lateral flags).
/// 출력: `Map<Attribute, double>` raw 점수. normalize(v9) 는 호출측에서 수행.
///
/// 5-stage pipeline:
///   1. base linear (node-weighted)
///   1b. distinctiveness (abs-z 가산)
///   2. zone rules (삼정 조화·불균형)
///   3. organ rules (오관 쌍)
///   4. palace rules (십이궁 overlay)
///   5. gender delta + age(50+) + lateral flags
///
/// 설계 근거: `docs/engine/ATTRIBUTES.md` v0.2
library;

import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

// ───────────────────────── Types ─────────────────────────

/// 한 node 의 attribute 기여 정의.
/// 기여량 = `weight × polarity × signedScore(node)`.
/// `useProximity=true` 면 `signedScore` 대신 `(2-|z|)×z` 적용 — 평균 근접 시 부호 유지하며 크기 증폭.
class _NodeWeight {
  final String nodeId;
  final double weight;
  final int polarity;
  final bool useProximity;
  const _NodeWeight(this.nodeId, this.weight, this.polarity,
      {this.useProximity = false});
}

class _GenderDelta {
  final double male;
  final double female;
  const _GenderDelta(this.male, this.female);
}

/// 한 stage 에서 발동된 규칙.
class TriggeredRule {
  final String id;
  final Map<Attribute, double> effects;
  const TriggeredRule(this.id, this.effects);
}

typedef _TreeCondition = bool Function(NodeScore tree);

class _TreeRule {
  final String id;
  final _TreeCondition condition;
  final Map<Attribute, double> effects;
  const _TreeRule(this.id, this.condition, this.effects);
}

typedef _LateralFlagCondition = bool Function(
    NodeScore tree, Map<String, bool> flags);

class _LateralFlagRule {
  final String id;
  final _LateralFlagCondition condition;
  final Map<Attribute, double> effects;
  const _LateralFlagRule(this.id, this.condition, this.effects);
}

/// Stage 별 기여 분해. 디버깅 + UI top-3 근거 표시에 사용.
class AttributeBreakdown {
  /// attribute → nodeId → base linear 기여.
  final Map<Attribute, Map<String, double>> basePerNode;

  /// attribute → stage1b distinctiveness 보정.
  final Map<Attribute, double> distinctiveness;

  final List<TriggeredRule> zoneRules;
  final List<TriggeredRule> organRules;
  final List<TriggeredRule> palaceRules;
  final List<TriggeredRule> ageRules;
  final List<TriggeredRule> lateralRules;

  /// attribute → 최종 raw 점수. normalize 이전 값.
  final Map<Attribute, double> total;

  const AttributeBreakdown({
    required this.basePerNode,
    required this.distinctiveness,
    required this.zoneRules,
    required this.organRules,
    required this.palaceRules,
    required this.ageRules,
    required this.lateralRules,
    required this.total,
  });
}

/// UI 용 "왜 이 점수?" top-N 기여 요인 (절댓값 큰 순).
/// key 예: `node:nose`, `Z-03`, `O-NM1`, `distinctiveness`.
extension AttributeBreakdownContributors on AttributeBreakdown {
  List<MapEntry<String, double>> topContributors(Attribute attr, {int n = 3}) {
    final bag = <String, double>{};
    final base = basePerNode[attr] ?? const <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
    final d = distinctiveness[attr] ?? 0.0;
    if (d.abs() > 0.05) bag['distinctiveness'] = d;
    for (final r in zoneRules) {
      final v = r.effects[attr];
      if (v != null) bag[r.id] = v;
    }
    for (final r in organRules) {
      final v = r.effects[attr];
      if (v != null) bag[r.id] = v;
    }
    for (final r in palaceRules) {
      final v = r.effects[attr];
      if (v != null) bag[r.id] = v;
    }
    for (final r in ageRules) {
      final v = r.effects[attr];
      if (v != null) bag[r.id] = v;
    }
    for (final r in lateralRules) {
      final v = r.effects[attr];
      if (v != null) bag[r.id] = v;
    }
    final sorted = bag.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return sorted.take(n).toList();
  }
}

// ──────────────────── §2.2 Weight Matrix ────────────────────
//
// 각 row 합 = 1.00. 숫자 근거는 `docs/engine/ATTRIBUTES.md` §2.2 · §12.

const _weightMatrix = <Attribute, List<_NodeWeight>>{
  Attribute.wealth: [
    _NodeWeight('face', 0.15, 1, useProximity: true),
    _NodeWeight('nose', 0.50, 1),
    _NodeWeight('cheekbone', 0.20, 1),
    _NodeWeight('mouth', 0.05, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
  Attribute.leadership: [
    _NodeWeight('face', 0.05, 1, useProximity: true),
    _NodeWeight('forehead', 0.40, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.25, 1),
    _NodeWeight('chin', 0.20, 1),
  ],
  Attribute.intelligence: [
    _NodeWeight('face', 0.10, 1),
    _NodeWeight('forehead', 0.20, 1),
    _NodeWeight('eyebrow', 0.25, 1),
    _NodeWeight('eye', 0.40, 1),
    _NodeWeight('nose', 0.05, 1),
  ],
  Attribute.sociability: [
    _NodeWeight('face', 0.05, 1),
    _NodeWeight('cheekbone', 0.40, 1),
    _NodeWeight('philtrum', 0.10, 1),
    _NodeWeight('mouth', 0.25, 1),
    _NodeWeight('chin', 0.20, 1),
  ],
  Attribute.emotionality: [
    _NodeWeight('face', 0.05, 1),
    _NodeWeight('eyebrow', 0.20, 1),
    _NodeWeight('eye', 0.45, 1),
    _NodeWeight('mouth', 0.20, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
  Attribute.stability: [
    _NodeWeight('face', 0.12, 1, useProximity: true),
    _NodeWeight('forehead', 0.20, 1),
    _NodeWeight('nose', 0.20, 1),
    _NodeWeight('cheekbone', 0.08, 1),
    _NodeWeight('chin', 0.40, 1),
  ],
  Attribute.sensuality: [
    _NodeWeight('eyebrow', 0.15, 1),
    _NodeWeight('eye', 0.40, 1),
    _NodeWeight('cheekbone', 0.20, 1),
    _NodeWeight('mouth', 0.25, 1),
  ],
  Attribute.trustworthiness: [
    _NodeWeight('forehead', 0.25, 1),
    _NodeWeight('eyebrow', 0.20, 1),
    _NodeWeight('nose', 0.35, 1),
    _NodeWeight('mouth', 0.20, 1),
  ],
  Attribute.attractiveness: [
    _NodeWeight('face', 0.25, 1, useProximity: true),
    _NodeWeight('eyebrow', 0.10, 1),
    _NodeWeight('eye', 0.35, 1),
    _NodeWeight('nose', 0.15, 1),
    _NodeWeight('mouth', 0.15, 1),
  ],
  Attribute.libido: [
    _NodeWeight('eye', 0.25, 1),
    _NodeWeight('philtrum', 0.40, -1),
    _NodeWeight('mouth', 0.15, 1),
    _NodeWeight('chin', 0.20, 1),
  ],
};

// ──────────────────── §5.1 Gender Delta ────────────────────
//
// base weight 에 합산 (재정규화 없음 — row 합이 1.00 근방 유지).

const _genderDelta = <Attribute, Map<String, _GenderDelta>>{
  Attribute.wealth: {
    'nose': _GenderDelta(0.05, -0.05),
    'mouth': _GenderDelta(-0.05, 0.05),
  },
  Attribute.leadership: {
    'chin': _GenderDelta(0.05, -0.05),
    'eye': _GenderDelta(-0.05, 0.05),
  },
  Attribute.sensuality: {
    'mouth': _GenderDelta(-0.05, 0.05),
    'eye': _GenderDelta(0.05, -0.05),
  },
  Attribute.libido: {
    'nose': _GenderDelta(0.05, -0.05),
    'mouth': _GenderDelta(-0.05, 0.05),
  },
  Attribute.attractiveness: {
    'face': _GenderDelta(-0.05, 0.05),
    'chin': _GenderDelta(0.05, 0.0),
  },
};

double _effectiveWeight(_NodeWeight w, Attribute attr, Gender gender) {
  final delta = _genderDelta[attr]?[w.nodeId];
  if (delta == null) return w.weight;
  return w.weight + (gender == Gender.male ? delta.male : delta.female);
}

// ──────────────────── Helpers: Node 접근 ────────────────────

/// leaf / root node 의 signed score (own metric 평균 z). 값 없으면 0.
double _nodeSignedZ(NodeScore? node) => node?.ownMeanZ ?? 0.0;

/// leaf / root node 의 |z| 평균. 값 없으면 0.
double _nodeAbsZ(NodeScore? node) => node?.ownMeanAbsZ ?? 0.0;

/// zone node 의 roll-up signed score (own 없음 → 자식 집계). 값 없으면 0.
double _zoneSignedZ(NodeScore tree, String zoneId) =>
    tree.descendantById(zoneId)?.rollUpMeanZ ?? 0.0;

double _zoneAbsZ(NodeScore tree, String zoneId) =>
    tree.descendantById(zoneId)?.rollUpMeanAbsZ ?? 0.0;

double _leafZ(NodeScore tree, String id) =>
    _nodeSignedZ(tree.descendantById(id));

double _leafAbsZ(NodeScore tree, String id) =>
    _nodeAbsZ(tree.descendantById(id));

NodeScore? _nodeByWeight(NodeScore tree, _NodeWeight w) =>
    w.nodeId == 'face' ? tree : tree.descendantById(w.nodeId);

/// proximity: 평균(z=0)에서 부호 유지하며 크기 증폭, 극단에서 감쇠.
/// `(2 - |z|) × z` — 법선 범위 [-3.5, 3.5] 에서 최대 값은 z=±1 부근.
double _proximityScore(double z) => (2.0 - z.abs()) * z;

// ──────────────────── Stage 1 — base linear (per node) ────────────────────

Map<Attribute, Map<String, double>> _stage1BasePerNode(
    NodeScore tree, Gender gender) {
  final out = <Attribute, Map<String, double>>{
    for (final a in Attribute.values) a: <String, double>{},
  };
  for (final attr in Attribute.values) {
    for (final w in _weightMatrix[attr]!) {
      final node = _nodeByWeight(tree, w);
      if (node == null) continue;
      final s = _nodeSignedZ(node);
      final ew = _effectiveWeight(w, attr, gender);
      final contrib =
          (w.useProximity ? _proximityScore(s) : s) * ew * w.polarity;
      out[attr]![w.nodeId] = contrib;
    }
  }
  return out;
}

// ──────────────────── Stage 1b — distinctiveness (§2.3) ────────────────────

Map<Attribute, double> _stage1bDistinctiveness(NodeScore tree) {
  final out = <Attribute, double>{for (final a in Attribute.values) a: 0.0};

  // attractiveness: face.rollUpMeanAbsZ — negative linear (극단 = 이질감)
  final faceAbs = tree.rollUpMeanAbsZ ?? 0.0;
  out[Attribute.attractiveness] = -0.3 * faceAbs.clamp(0.0, 1.5);

  // intelligence: 상정 distinctiveness → 지적 인상
  final upperAbs = _zoneAbsZ(tree, 'upper');
  out[Attribute.intelligence] = 0.2 * (upperAbs - 0.5).clamp(0.0, 1.5);

  // emotionality: 하정 distinctiveness → 감정 풍부
  final lowerAbs = _zoneAbsZ(tree, 'lower');
  out[Attribute.emotionality] = 0.3 * (lowerAbs - 0.5).clamp(0.0, 1.5);

  return out;
}

// ──────────────────── Stage 2 — Zone Rules (§4.1, 10) ────────────────────

final _zoneRules = <_TreeRule>[
  // Z-01 삼정 균형
  _TreeRule('Z-01', (t) {
    return _zoneSignedZ(t, 'upper').abs() < 0.5 &&
        _zoneSignedZ(t, 'middle').abs() < 0.5 &&
        _zoneSignedZ(t, 'lower').abs() < 0.5;
  }, const {
    Attribute.stability: 1.5,
    Attribute.trustworthiness: 1.0,
    Attribute.attractiveness: 0.5,
  }),

  // Z-02 상정 우세
  _TreeRule('Z-02', (t) {
    return _zoneSignedZ(t, 'upper') >= 1.0 &&
        _zoneSignedZ(t, 'middle') <= 0.5 &&
        _zoneSignedZ(t, 'lower') <= 0.5;
  }, const {Attribute.intelligence: 2.0, Attribute.leadership: 0.5}),

  // Z-03 중정 우세
  _TreeRule('Z-03', (t) {
    return _zoneSignedZ(t, 'middle') >= 1.0 &&
        _zoneSignedZ(t, 'upper') <= 0.5 &&
        _zoneSignedZ(t, 'lower') <= 0.5;
  }, const {Attribute.wealth: 1.5, Attribute.libido: 1.0}),

  // Z-04 하정 우세
  _TreeRule('Z-04', (t) {
    return _zoneSignedZ(t, 'lower') >= 1.0 &&
        _zoneSignedZ(t, 'upper') <= 0.5 &&
        _zoneSignedZ(t, 'middle') <= 0.5;
  }, const {
    Attribute.sensuality: 1.5,
    Attribute.libido: 1.5,
    Attribute.stability: -0.5,
  }),

  // Z-05 상-하 대립
  _TreeRule(
      'Z-05',
      (t) =>
          _zoneSignedZ(t, 'upper') >= 1.0 &&
          _zoneSignedZ(t, 'lower') <= -1.0,
      const {Attribute.intelligence: 1.0, Attribute.emotionality: -1.0}),

  // Z-06 하-상 대립
  _TreeRule(
      'Z-06',
      (t) =>
          _zoneSignedZ(t, 'lower') >= 1.0 &&
          _zoneSignedZ(t, 'upper') <= -1.0,
      const {Attribute.emotionality: 1.5, Attribute.trustworthiness: -0.5}),

  // Z-07 전면 강세
  _TreeRule('Z-07', (t) {
    return _zoneSignedZ(t, 'upper') >= 1.0 &&
        _zoneSignedZ(t, 'middle') >= 1.0 &&
        _zoneSignedZ(t, 'lower') >= 1.0;
  }, const {Attribute.leadership: 2.0, Attribute.attractiveness: 1.0}),

  // Z-08 전면 약세
  _TreeRule('Z-08', (t) {
    return _zoneSignedZ(t, 'upper') <= -1.0 &&
        _zoneSignedZ(t, 'middle') <= -1.0 &&
        _zoneSignedZ(t, 'lower') <= -1.0;
  }, const {
    Attribute.wealth: -0.5,
    Attribute.leadership: -0.5,
    Attribute.intelligence: -0.5,
    Attribute.sociability: -0.5,
    Attribute.stability: -0.5,
    Attribute.trustworthiness: -0.5,
    Attribute.attractiveness: -0.5,
  }),

  // Z-09 상정 distinctive
  _TreeRule('Z-09', (t) => _zoneAbsZ(t, 'upper') >= 1.5,
      const {Attribute.intelligence: 0.5, Attribute.attractiveness: -0.3}),

  // Z-10 하정 distinctive
  _TreeRule('Z-10', (t) => _zoneAbsZ(t, 'lower') >= 1.5,
      const {Attribute.sensuality: 1.0, Attribute.emotionality: 0.5}),
];

// ──────────────────── Stage 3 — Organ Rules (§4.2, 14) ────────────────────

final _organRules = <_TreeRule>[
  // O-EB1 눈-눈썹 동조 강
  _TreeRule(
      'O-EB1',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'eyebrow') >= 1.0,
      const {Attribute.leadership: 1.5, Attribute.trustworthiness: 1.0}),

  // O-EB2 눈 강·눈썹 약
  _TreeRule(
      'O-EB2',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'eyebrow') <= -1.0,
      const {Attribute.intelligence: 1.0, Attribute.emotionality: 1.0}),

  // O-EB3 눈썹 강·눈 약
  _TreeRule(
      'O-EB3',
      (t) => _leafZ(t, 'eyebrow') >= 1.0 && _leafZ(t, 'eye') <= -1.0,
      const {Attribute.leadership: 0.5, Attribute.trustworthiness: -0.5}),

  // O-NM1 코-입 동조
  _TreeRule(
      'O-NM1',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.wealth: 2.0, Attribute.sociability: 1.0}),

  // O-NM2 코 강·입 약
  _TreeRule(
      'O-NM2',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'mouth') <= -1.0,
      const {Attribute.wealth: 0.5, Attribute.sociability: -1.0}),

  // O-NM3 코 약·입 강
  _TreeRule(
      'O-NM3',
      (t) => _leafZ(t, 'nose') <= -1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.sociability: 1.5, Attribute.wealth: -0.5}),

  // O-NC 코-턱 결합 (숭산+항산)
  _TreeRule(
      'O-NC',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'chin') >= 1.0,
      const {
        Attribute.wealth: 1.0,
        Attribute.leadership: 1.0,
        Attribute.stability: 0.5,
      }),

  // O-EM 눈-입 결합
  _TreeRule(
      'O-EM',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.attractiveness: 1.5, Attribute.sociability: 1.0}),

  // O-FB 이마-눈썹 결합
  _TreeRule(
      'O-FB',
      (t) => _leafZ(t, 'forehead') >= 1.0 && _leafZ(t, 'eyebrow') >= 1.0,
      const {Attribute.leadership: 1.0, Attribute.intelligence: 0.5}),

  // O-CK 광대 강
  _TreeRule('O-CK', (t) => _leafZ(t, 'cheekbone') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.attractiveness: -0.2}),

  // O-CB 광대 약
  _TreeRule('O-CB', (t) => _leafZ(t, 'cheekbone') <= -1.0,
      const {Attribute.leadership: -0.5, Attribute.attractiveness: 0.3}),

  // O-PH1 인중 짧음
  _TreeRule('O-PH1', (t) => _leafZ(t, 'philtrum') <= -1.0,
      const {Attribute.libido: 1.5, Attribute.sensuality: 1.0}),

  // O-PH2 인중 긺
  _TreeRule('O-PH2', (t) => _leafZ(t, 'philtrum') >= 1.0,
      const {Attribute.stability: 0.5, Attribute.trustworthiness: 0.5}),

  // O-CH 턱 강
  _TreeRule('O-CH', (t) => _leafZ(t, 'chin') >= 1.0,
      const {Attribute.leadership: 1.0, Attribute.stability: 1.0}),
];

// ──────────────────── Stage 4 — Palace Overlay (§4.3, 8) ────────────────────

final _palaceRules = <_TreeRule>[
  // P-01 재백궁 + 전택궁 (코 + 눈)
  _TreeRule(
      'P-01',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'eye') >= 1.0,
      const {Attribute.wealth: 1.0, Attribute.stability: 1.0}),

  // P-02 관록궁 + 천이궁 (둘 다 이마)
  _TreeRule('P-02', (t) => _leafZ(t, 'forehead') >= 1.5,
      const {Attribute.leadership: 1.5, Attribute.intelligence: 1.0}),

  // P-03 복덕궁 cross — 전체 roll-up 긍정 + 삼정 모두 ≥ 0
  _TreeRule('P-03', (t) {
    final root = t.rollUpMeanZ ?? 0.0;
    return root >= 0.8 &&
        _zoneSignedZ(t, 'upper') >= 0.0 &&
        _zoneSignedZ(t, 'middle') >= 0.0 &&
        _zoneSignedZ(t, 'lower') >= 0.0;
  }, const {Attribute.attractiveness: 1.5, Attribute.trustworthiness: 0.5}),

  // P-04 형제궁 — 눈썹 강 + distinctive
  _TreeRule(
      'P-04',
      (t) => _leafZ(t, 'eyebrow') >= 1.0 && _leafAbsZ(t, 'eyebrow') >= 1.5,
      const {Attribute.sociability: 0.5, Attribute.trustworthiness: 1.0}),

  // P-05 남녀궁 — 눈 아래, 하정과 조합
  _TreeRule(
      'P-05',
      (t) => _leafZ(t, 'eye') >= 1.0 && _zoneSignedZ(t, 'lower') >= 0.0,
      const {
        Attribute.libido: 1.0,
        Attribute.emotionality: 0.5,
        Attribute.sociability: 0.3,
      }),

  // P-06 처첩궁 — 눈꼬리 tilt
  _TreeRule('P-06', (t) {
    final eye = t.descendantById('eye');
    if (eye == null) return false;
    final abs = eye.ownMeanAbsZ ?? 0.0;
    final tiltZ = eye.ownZ['eyeCanthalTilt'] ?? 0.0;
    return abs >= 1.0 && tiltZ >= 1.0;
  }, const {
    Attribute.sensuality: 1.0,
    Attribute.attractiveness: 0.5,
    Attribute.emotionality: 0.3,
  }),

  // P-07 질액궁 — 산근(코) 극단 → 체질 부조화
  _TreeRule('P-07', (t) => _leafAbsZ(t, 'nose') >= 1.5,
      const {Attribute.stability: -0.5}),

  // P-08 천이궁 — 이마 + face distinctive
  _TreeRule('P-08', (t) {
    return _leafZ(t, 'forehead') >= 1.0 && (t.rollUpMeanAbsZ ?? 0.0) >= 0.5;
  }, const {
    Attribute.leadership: 0.5,
    Attribute.stability: 0.5,
    Attribute.intelligence: 0.5,
  }),

  // P-09 명궁 — glabella metric 공백으로 현재 항상 미발동. Phase 4 에서 활성.
];

// ──────────────────── Stage 5 — Age (50+) Rules (§5.2, 4) ────────────────────

final _ageRules = <_TreeRule>[
  // A-01 하정 약화 보정 (노화 normal)
  _TreeRule('A-01', (t) => _zoneSignedZ(t, 'lower') <= -1.0,
      const {Attribute.libido: -1.0, Attribute.sensuality: -0.5}),

  // A-02 상정 유지 우수
  _TreeRule('A-02', (t) => _zoneSignedZ(t, 'upper') >= 0.5,
      const {Attribute.intelligence: 1.0, Attribute.stability: 0.5}),

  // A-03 입꼬리 유지
  _TreeRule('A-03', (t) => _leafZ(t, 'mouth') >= 0.5,
      const {Attribute.attractiveness: 1.5, Attribute.stability: 1.0}),

  // A-04 전반 이완
  _TreeRule('A-04', (t) => (t.rollUpMeanZ ?? 0.0) <= -1.0,
      const {Attribute.emotionality: 0.5, Attribute.attractiveness: -1.0}),
];

// ──────────────────── Stage 5 — Lateral Flag Rules (§5.3, 3) ────────────────────

final _lateralFlagRules = <_LateralFlagRule>[
  // L-AQ 매부리코
  _LateralFlagRule('L-AQ', (t, f) => f['aquilineNose'] ?? false, const {
    Attribute.leadership: 1.5,
    Attribute.wealth: 0.5,
    Attribute.stability: -0.3,
  }),

  // L-SN 들창코
  _LateralFlagRule('L-SN', (t, f) => f['snubNose'] ?? false,
      const {Attribute.sociability: 1.0, Attribute.attractiveness: 0.5}),

  // L-EL E-line 전돌 — mouth.ownZ 의 lateral metric 직접 확인
  _LateralFlagRule('L-EL', (t, f) {
    final mouth = t.descendantById('mouth');
    if (mouth == null) return false;
    final upper = mouth.ownZ['upperLipEline'] ?? 0.0;
    final lower = mouth.ownZ['lowerLipEline'] ?? 0.0;
    return upper >= 1.0 && lower >= 1.0;
  }, const {Attribute.sensuality: 0.5, Attribute.libido: 0.5}),
];

// ──────────────────── Orchestrator ────────────────────

/// 신규 진입점. tree + context → 10 attribute raw 점수.
/// normalize(v9) 호출은 이 결과를 받아서 별도로 수행.
Map<Attribute, double> deriveAttributeScores({
  required NodeScore tree,
  required Gender gender,
  required bool isOver50,
  required bool hasLateral,
  Map<String, bool> lateralFlags = const {},
}) {
  return deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: isOver50,
    hasLateral: hasLateral,
    lateralFlags: lateralFlags,
  ).total;
}

/// 디버그 경로 — 각 stage 의 기여를 분해해서 반환.
/// UI top-3 근거 표시, 테스트, calibration 분포 관측에 사용.
AttributeBreakdown deriveAttributeScoresDetailed({
  required NodeScore tree,
  required Gender gender,
  required bool isOver50,
  required bool hasLateral,
  Map<String, bool> lateralFlags = const {},
}) {
  final basePerNode = _stage1BasePerNode(tree, gender);
  final distinct = _stage1bDistinctiveness(tree);

  final zoneTriggered = _evalRules(tree, _zoneRules);
  final organTriggered = _evalRules(tree, _organRules);
  final palaceTriggered = _evalRules(tree, _palaceRules);
  final ageTriggered =
      isOver50 ? _evalRules(tree, _ageRules) : const <TriggeredRule>[];
  final lateralTriggered = hasLateral
      ? _evalLateralFlagRules(tree, lateralFlags)
      : const <TriggeredRule>[];

  final total = <Attribute, double>{for (final a in Attribute.values) a: 0.0};

  // base per-node 합산
  for (final attr in Attribute.values) {
    final perNode = basePerNode[attr]!;
    double sum = 0.0;
    for (final v in perNode.values) {
      sum += v;
    }
    total[attr] = sum;
  }

  // distinctiveness
  distinct.forEach((a, v) => total[a] = (total[a] ?? 0.0) + v);

  // rules
  void apply(List<TriggeredRule> rules) {
    for (final r in rules) {
      r.effects.forEach((a, v) => total[a] = (total[a] ?? 0.0) + v);
    }
  }

  apply(zoneTriggered);
  apply(organTriggered);
  apply(palaceTriggered);
  apply(ageTriggered);
  apply(lateralTriggered);

  return AttributeBreakdown(
    basePerNode: basePerNode,
    distinctiveness: distinct,
    zoneRules: zoneTriggered,
    organRules: organTriggered,
    palaceRules: palaceTriggered,
    ageRules: ageTriggered,
    lateralRules: lateralTriggered,
    total: total,
  );
}

List<TriggeredRule> _evalRules(NodeScore tree, List<_TreeRule> rules) {
  final out = <TriggeredRule>[];
  for (final r in rules) {
    if (r.condition(tree)) out.add(TriggeredRule(r.id, r.effects));
  }
  return out;
}

List<TriggeredRule> _evalLateralFlagRules(
    NodeScore tree, Map<String, bool> flags) {
  final out = <TriggeredRule>[];
  for (final r in _lateralFlagRules) {
    if (r.condition(tree, flags)) out.add(TriggeredRule(r.id, r.effects));
  }
  return out;
}
