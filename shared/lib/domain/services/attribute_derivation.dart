/// Attribute derivation — tree node + face-shape overlay 로 10 속성 raw 산출.
///
/// 입력: `scoreTree()` 결과(`NodeScore`) + context(gender, 50+, lateral flags,
/// FaceShape preset).
/// 출력: `Map<Attribute, double>` raw. normalize 는 호출측 책임.
///
/// Pipeline:
///   0. face-shape preset delta (Layer A)                    // 전체 얼굴형 bias
///   1. base linear per-node (9 노드, face/ear 제외)
///   1b. distinctiveness (매력도 symmetric bell + upper/lower positive)
///   2. zone rules Z-##
///   3. organ rules O-##
///   4. palace rules P-##
///   5. age A-## (50+) + lateral L-## (3/4-view) + gender delta
library;

import 'package:meta/meta.dart';

import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/physiognomy_tree.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';

// ───────────────────────── Types ─────────────────────────

/// 한 노드의 attribute 기여 정의. 기여량 = `weight × polarity × node.signedZ`.
class _NodeWeight {
  final String nodeId;
  final double weight;
  final int polarity;
  const _NodeWeight(this.nodeId, this.weight, this.polarity);
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

  /// attribute → stage 0 face-shape preset 기여.
  final Map<Attribute, double> shapePreset;

  /// attribute → stage 1b distinctiveness 보정.
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
    required this.shapePreset,
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
/// key 예: `node:nose`, `shape`, `distinctiveness`, `Z-03`, `O-NM1`, `P-06`, `L-AQ`.
extension AttributeBreakdownContributors on AttributeBreakdown {
  List<MapEntry<String, double>> topContributors(Attribute attr, {int n = 3}) {
    final bag = <String, double>{};
    final base = basePerNode[attr] ?? const <String, double>{};
    for (final e in base.entries) {
      if (e.value.abs() > 0.05) bag['node:${e.key}'] = e.value;
    }
    final sh = shapePreset[attr] ?? 0.0;
    if (sh.abs() > 0.05) bag['shape'] = sh;
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

// ──────────────────── §2.2 Weight Matrix v2.7 (9 노드) ────────────────────
//
// face(root) · ear 제외. 불변식 5 개:
//   1. row 합 = 1.00
//   2. zone 합 ∈ [0.25, 0.40]  — 상/중/하정 편향 근절
//   3. per-node ≤ 0.25         — 단일 노드 독점 방지
//   4. per-metric max/min ≤ 3.5× — 단일 metric 과적재 band
//   5. row cosine similarity < 0.92 — attribute 간 프로파일 decorrelation
//
// v2.7 도입 배경 (2026-04-19):
//   v2.6 까지 charm cluster (sociability · emotionality · sensuality ·
//   attractiveness · libido) 다섯 속성이 eye + eyebrow + mouth 3 node 에
//   공통 dominant 로 쏠려 있어, 임의의 얼굴이 항상 외교형/예술가형/미인형
//   cluster 로 top-2 가 고정되는 편향 발생. 각 속성마다 고유 dominant node
//   를 배정하여 cos-sim 을 내려뜨림 ("학자형 편향 → 외교형 편향" 의 근본
//   원인 해소).
//
// Dominant node map (row 최댓값 기준):
//   wealth         nose      0.20
//   leadership     chin      0.18
//   intelligence   forehead  0.18
//   sociability    mouth     0.20
//   emotionality   eye       0.20
//   stability      chin      0.18  (leadership 와 공유 but 나머지 분포 다름)
//   sensuality     eye·mouth·philtrum  tri-dominant
//   trustworthiness  forehead·eye·chin balanced
//   attractiveness eye·mouth tied
//   libido         eyebrow   0.17  (philtrum 0.15 neg polarity)

const _weightMatrix = <Attribute, List<_NodeWeight>>{
  Attribute.wealth: [
    _NodeWeight('forehead', 0.12, 1),
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.08, 1),
    _NodeWeight('eye', 0.08, 1),
    _NodeWeight('nose', 0.20, 1),
    _NodeWeight('cheekbone', 0.10, 1),
    _NodeWeight('philtrum', 0.07, 1),
    _NodeWeight('mouth', 0.10, 1),
    _NodeWeight('chin', 0.15, 1),
  ],
  Attribute.leadership: [
    _NodeWeight('forehead', 0.13, 1),
    _NodeWeight('glabella', 0.08, 1),
    _NodeWeight('eyebrow', 0.15, 1),
    _NodeWeight('eye', 0.10, 1),
    _NodeWeight('nose', 0.15, 1),
    _NodeWeight('cheekbone', 0.10, 1),
    _NodeWeight('philtrum', 0.03, 1),
    _NodeWeight('mouth', 0.08, 1),
    _NodeWeight('chin', 0.18, 1),
  ],
  Attribute.intelligence: [
    _NodeWeight('forehead', 0.18, 1),
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.10, 1),
    _NodeWeight('eye', 0.15, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.08, 1),
    _NodeWeight('philtrum', 0.09, 1),
    _NodeWeight('mouth', 0.10, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
  Attribute.sociability: [
    _NodeWeight('forehead', 0.08, 1),
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.10, 1),
    _NodeWeight('eye', 0.12, 1),
    _NodeWeight('nose', 0.08, 1),
    _NodeWeight('cheekbone', 0.12, 1),
    _NodeWeight('philtrum', 0.07, 1),
    _NodeWeight('mouth', 0.20, 1),
    _NodeWeight('chin', 0.13, 1),
  ],
  Attribute.emotionality: [
    _NodeWeight('forehead', 0.06, 1),
    _NodeWeight('glabella', 0.13, 1),
    _NodeWeight('eyebrow', 0.12, 1),
    _NodeWeight('eye', 0.20, 1),
    _NodeWeight('nose', 0.08, 1),
    _NodeWeight('cheekbone', 0.08, 1),
    _NodeWeight('philtrum', 0.10, 1),
    _NodeWeight('mouth', 0.13, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
  Attribute.stability: [
    _NodeWeight('forehead', 0.12, 1),
    _NodeWeight('glabella', 0.15, 1),
    _NodeWeight('eyebrow', 0.08, 1),
    _NodeWeight('eye', 0.08, 1),
    _NodeWeight('nose', 0.13, 1),
    _NodeWeight('cheekbone', 0.10, 1),
    _NodeWeight('philtrum', 0.08, 1),
    _NodeWeight('mouth', 0.08, 1),
    _NodeWeight('chin', 0.18, 1),
  ],
  Attribute.sensuality: [
    _NodeWeight('forehead', 0.05, 1),
    _NodeWeight('glabella', 0.08, 1),
    _NodeWeight('eyebrow', 0.13, 1),
    _NodeWeight('eye', 0.17, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.08, 1),
    _NodeWeight('philtrum', 0.15, 1),
    _NodeWeight('mouth', 0.17, 1),
    _NodeWeight('chin', 0.07, 1),
  ],
  Attribute.trustworthiness: [
    _NodeWeight('forehead', 0.15, 1),
    _NodeWeight('glabella', 0.12, 1),
    _NodeWeight('eyebrow', 0.06, 1),
    _NodeWeight('eye', 0.15, 1),
    _NodeWeight('nose', 0.13, 1),
    _NodeWeight('cheekbone', 0.07, 1),
    _NodeWeight('philtrum', 0.07, 1),
    _NodeWeight('mouth', 0.10, 1),
    _NodeWeight('chin', 0.15, 1),
  ],
  Attribute.attractiveness: [
    _NodeWeight('forehead', 0.07, 1),
    _NodeWeight('glabella', 0.07, 1),
    _NodeWeight('eyebrow', 0.13, 1),
    _NodeWeight('eye', 0.17, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.13, 1),
    _NodeWeight('philtrum', 0.07, 1),
    _NodeWeight('mouth', 0.17, 1),
    _NodeWeight('chin', 0.09, 1),
  ],
  Attribute.libido: [
    _NodeWeight('forehead', 0.05, 1),
    _NodeWeight('glabella', 0.08, 1),
    _NodeWeight('eyebrow', 0.17, 1),
    _NodeWeight('eye', 0.13, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.10, 1),
    _NodeWeight('philtrum', 0.15, -1),
    _NodeWeight('mouth', 0.12, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
};

// ──────────────────── §5.1 Gender Delta ────────────────────
//
// base weight 에 합산 (재정규화 없음 — row 합이 1.00 근방 유지).
// face 제외. 매력도 델타는 "남성=chin / 여성=eye" 로 재배치.

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
    'chin': _GenderDelta(0.05, -0.05),
    'eye': _GenderDelta(-0.05, 0.05),
  },
};

double _effectiveWeight(_NodeWeight w, Attribute attr, Gender gender) {
  final delta = _genderDelta[attr]?[w.nodeId];
  if (delta == null) return w.weight;
  return w.weight + (gender == Gender.male ? delta.male : delta.female);
}

// ──────────────────── Shape Overlay — RETIRED FROM SCORE PIPELINE ────────────────────
//
// v2.2 (2026-04-18): 얼굴형 preset 이 raw score 에 주는 영향을 완전 제거.
// "계란형 → 학자형" 같은 얼굴형별 archetype 수렴 패턴의 근원이 preset 이
// calibration p50 와 production raw 사이 attribute-specific 편향을 만든 데
// 있음이 확인됨. v2.1 의 halve + gate 로도 편향 잔존.
//
// FaceShape 는 raw score 에서 완전히 빠지고, 다음 두 곳에만 남는다:
//   (A) archetype shape-gated overlay (classifyArchetype) — 라벨 변주만.
//   (B) narrative Layer B (life_question_narrative) — 서술 variation.
//
// preset 파라미터는 시그너처 호환 위해 남기되 no-op. _stage0ShapePreset 은
// 항상 모든 속성에 0.0 을 반환. AttributeBreakdown.shapePreset 도 전부 0.

Map<Attribute, double> _stage0ShapePreset(
    FaceShape shape, double confidence, Map<Attribute, double> baseline) {
  assert(confidence >= 0.0 && confidence <= 1.0,
      'shapeConfidence must be in [0, 1], got $confidence');
  // v2.2: preset 철수. 모든 속성 0 기여.
  return <Attribute, double>{for (final a in Attribute.values) a: 0.0};
}

// ──────────────────── Helpers: Node 접근 ────────────────────

double _nodeSignedZ(NodeScore? node) => node?.ownMeanZ ?? 0.0;

double _zoneSignedZ(NodeScore tree, String zoneId) =>
    tree.descendantById(zoneId)?.rollUpMeanZ ?? 0.0;

double _zoneAbsZ(NodeScore tree, String zoneId) =>
    tree.descendantById(zoneId)?.rollUpMeanAbsZ ?? 0.0;

double _leafZ(NodeScore tree, String id) =>
    _nodeSignedZ(tree.descendantById(id));

double _leafAbsZ(NodeScore tree, String id) =>
    tree.descendantById(id)?.ownMeanAbsZ ?? 0.0;

NodeScore? _nodeByWeight(NodeScore tree, _NodeWeight w) =>
    tree.descendantById(w.nodeId);

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
      out[attr]![w.nodeId] = s * ew * w.polarity;
    }
  }
  return out;
}

// ──────────────────── Stage 1b — distinctiveness ────────────────────
//
// 매력도: symmetric bell — 평균 근접(faceAbs≈0.7) 에서 최대 +0.20,
// 양극단(faceAbs<0.2 또는 ≥1.6) 에서 최대 −0.25. 기존 monotonic penalty 대체.
// upper/lower 강세는 기존 positive-only 유지.

Map<Attribute, double> _stage1bDistinctiveness(NodeScore tree) {
  final out = <Attribute, double>{for (final a in Attribute.values) a: 0.0};

  // v2.2 (2026-04-18): attractiveness distinctiveness 완전 철수.
  //   — monotonic penalty(v1) → symmetric bell(v2) → 철수(v2.2).
  //   calibration p50 을 0.6+ 로 부풀려 production 실제 raw 와 mismatch 를
  //   만든 주범이었음. "oval → 학자형" 패턴의 뿌리. attr 는 node weight + rule
  //   로만 결정.

  // intelligence: 상정 distinctiveness → 지적 인상. positive-only, 작음.
  //   upper_abs > 0.5 에서만 발동. 평균 얼굴엔 0.
  final upperAbs = _zoneAbsZ(tree, 'upper');
  out[Attribute.intelligence] = 0.2 * (upperAbs - 0.5).clamp(0.0, 1.5);

  // emotionality: 하정 distinctiveness → 감정 풍부. positive-only.
  final lowerAbs = _zoneAbsZ(tree, 'lower');
  out[Attribute.emotionality] = 0.3 * (lowerAbs - 0.5).clamp(0.0, 1.5);

  return out;
}

// ──────────────────── Stage 2 — Zone Rules ────────────────────

final _zoneRules = <_TreeRule>[
  // Z-01 삼정 균형 — 공통 발동 rule. v2.9: attr 0.1→0.05 (v2.8), wealth 제거.
  // 균형 얼굴이 attractiveness 로 과집중되던 구조적 편향 해소.
  // wealth 0.03 은 threshold(0.05) 미만으로 contributor 필터에 걸려 제거.
  _TreeRule('Z-01', (t) {
    return _zoneSignedZ(t, 'upper').abs() < 0.5 &&
        _zoneSignedZ(t, 'middle').abs() < 0.5 &&
        _zoneSignedZ(t, 'lower').abs() < 0.5;
  }, const {
    Attribute.stability: 0.1,
    Attribute.trustworthiness: 0.05,
    Attribute.attractiveness: 0.05,
  }),

  // Z-02 상정 우세. v2.6 cap: intel 2.0→0.5, lead 0.5→0.13.
  _TreeRule('Z-02', (t) {
    return _zoneSignedZ(t, 'upper') >= 1.0 &&
        _zoneSignedZ(t, 'middle') <= 0.5 &&
        _zoneSignedZ(t, 'lower') <= 0.5;
  }, const {Attribute.intelligence: 0.5, Attribute.leadership: 0.13}),

  // Z-03 중정 우세. v2.6 cap: wealth 1.5→0.5, libido 1.0→0.33.
  _TreeRule('Z-03', (t) {
    return _zoneSignedZ(t, 'middle') >= 1.0 &&
        _zoneSignedZ(t, 'upper') <= 0.5 &&
        _zoneSignedZ(t, 'lower') <= 0.5;
  }, const {Attribute.wealth: 0.5, Attribute.libido: 0.33}),

  // Z-04 하정 우세. v2.6 cap: sens/libido 1.5→0.5, stab -0.5→-0.17.
  _TreeRule('Z-04', (t) {
    return _zoneSignedZ(t, 'lower') >= 1.0 &&
        _zoneSignedZ(t, 'upper') <= 0.5 &&
        _zoneSignedZ(t, 'middle') <= 0.5;
  }, const {
    Attribute.sensuality: 0.5,
    Attribute.libido: 0.5,
    Attribute.stability: -0.17,
  }),

  // Z-05 상-하 대립. v2.6 cap: 1.0→0.5.
  _TreeRule(
      'Z-05',
      (t) =>
          _zoneSignedZ(t, 'upper') >= 1.0 &&
          _zoneSignedZ(t, 'lower') <= -1.0,
      const {Attribute.intelligence: 0.5, Attribute.emotionality: -0.5}),

  // Z-06 하-상 대립. v2.6 cap: emot 1.5→0.5, trust -0.5→-0.17.
  _TreeRule(
      'Z-06',
      (t) =>
          _zoneSignedZ(t, 'lower') >= 1.0 &&
          _zoneSignedZ(t, 'upper') <= -1.0,
      const {Attribute.emotionality: 0.5, Attribute.trustworthiness: -0.17}),

  // Z-07 전면 강세 — 三停俱足 = 권위. 매력 분리 (v2.9: Z-NG 五官端正 으로 이관).
  //   원형 麻衣相法 "三停俱足者, 富貴雙全" 은 富貴(권력) 명제이지 美 명제 아님.
  _TreeRule('Z-07', (t) {
    return _zoneSignedZ(t, 'upper') >= 1.0 &&
        _zoneSignedZ(t, 'middle') >= 1.0 &&
        _zoneSignedZ(t, 'lower') >= 1.0;
  }, const {Attribute.leadership: 0.5}),

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

  // Z-09 상정 distinctive — 매력 음수는 O-EZ (눈 자체 부조화) 로 정확화 (v2.9).
  _TreeRule('Z-09', (t) => _zoneAbsZ(t, 'upper') >= 1.5,
      const {Attribute.intelligence: 0.5}),

  // Z-10 하정 distinctive. v2.6 cap: sens 1.0→0.5, emot 0.5→0.25.
  _TreeRule('Z-10', (t) => _zoneAbsZ(t, 'lower') >= 1.5,
      const {Attribute.sensuality: 0.5, Attribute.emotionality: 0.25}),

  // Z-11 중정 비율 큼 — root own `midFaceRatio` ≥ 1.0
  _TreeRule('Z-11', (t) => (t.ownZ['midFaceRatio'] ?? 0.0) >= 1.0,
      const {Attribute.wealth: 0.5, Attribute.sociability: 0.3}),

  // Z-12 하정 비율 큼 — chin 의 lowerFaceRatio z ≥ 1.0. v2.4 mag 축소.
  _TreeRule(
      'Z-12',
      (t) => (t.descendantById('chin')?.ownZ['lowerFaceRatio'] ?? 0.0) >= 1.0,
      const {Attribute.stability: 0.2, Attribute.trustworthiness: 0.1}),

  // Z-13 하정 비율 작음
  _TreeRule(
      'Z-13',
      (t) => (t.descendantById('chin')?.ownZ['lowerFaceRatio'] ?? 0.0) <= -1.0,
      const {Attribute.emotionality: 0.3, Attribute.stability: -0.3}),

  // Z-FH 이마 강세 — forehead ownMeanZ ≥ 0.7 → 지성·신뢰 신호.
  // v2.9 신규: 이마 두드러진 얼굴이 intelligence 로 분류되도록.
  _TreeRule(
      'Z-FH',
      (t) => _leafZ(t, 'forehead') >= 0.7,
      const {Attribute.intelligence: 0.20, Attribute.trustworthiness: 0.10}),

  // Z-IC 눈 사이 넓음 — intercanthalRatio z ≥ 0.5 → 카리스마·리더십.
  // v2.9 신규: 눈 사이 넓은 open-set 인상이 leadership 로.
  _TreeRule(
      'Z-IC',
      (t) => (t.descendantById('eye')?.ownZ['intercanthalRatio'] ?? 0.0) >= 0.5,
      const {Attribute.leadership: 0.20, Attribute.wealth: 0.08}),

  // Z-LFR 풍만한 입술 — sociability 전용. 매력은 O-RL (朱唇小口) 로 narrowing (v2.9).
  _TreeRule('Z-LFR', (t) {
    final mouth = t.descendantById('mouth');
    if (mouth == null) return false;
    final lfr = mouth.ownZ['lipFullnessRatio'] ?? 0.0;
    final mwr = mouth.ownZ['mouthWidthRatio'] ?? 0.0;
    return lfr >= 0.8 && mwr < 1.5;
  }, const {Attribute.sociability: 0.25}),

  // Z-FAR 세로로 긴 얼굴 — faceAspectRatio z ≥ 1.2 → 부유·리더 인상.
  // v2.9 신규: oblong/long face 가 wealth 로 분류되도록.
  _TreeRule(
      'Z-FAR',
      (t) => (t.ownZ['faceAspectRatio'] ?? 0.0) >= 1.2,
      const {Attribute.wealth: 0.25, Attribute.leadership: 0.10}),

  // Z-EBT 눈썹 하향 틸트 — eyebrowTiltDirection z ≤ −1.0 → 관능도 신호.
  // 처진 눈썹(팔자미인) 은 한국 관상에서 관능·감성형 인상. v2.9 신규.
  _TreeRule(
      'Z-EBT',
      (t) {
        final eb = t.descendantById('eyebrow');
        if (eb == null) return false;
        return (eb.ownZ['eyebrowTiltDirection'] ?? 0.0) <= -1.0;
      },
      const {Attribute.sensuality: 0.20, Attribute.emotionality: 0.10}),

  // Z-NG 五官端正 — 三停 모두 abs < 0.7 AND root rollUp ≥ 0.3.
  //   神相全編 "五官端正, 必爲美相". 균형형 美 — 강세가 아닌 조화의 매력.
  //   Z-01 (abs < 0.5 + 음수 zone 허용) 보다 우상향 / 더 narrow.
  //   v2.9 신규: Z-07 의 attractiveness 부분 대체.
  _TreeRule('Z-NG', (t) {
    return _zoneAbsZ(t, 'upper') < 0.7 &&
        _zoneAbsZ(t, 'middle') < 0.7 &&
        _zoneAbsZ(t, 'lower') < 0.7 &&
        (t.rollUpMeanZ ?? 0.0) >= 0.3;
  }, const {Attribute.attractiveness: 0.3}),
];

// ──────────────────── Stage 3 — Organ Rules ────────────────────

final _organRules = <_TreeRule>[
  // O-EB1 눈-눈썹 동조 강. v2.6 cap: lead 1.5→0.5, trust 0.3→0.1.
  _TreeRule(
      'O-EB1',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'eyebrow') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.trustworthiness: 0.1}),

  // O-EB2 눈 강·눈썹 약. v2.6 cap: 1.0→0.5.
  _TreeRule(
      'O-EB2',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'eyebrow') <= -1.0,
      const {Attribute.intelligence: 0.5, Attribute.emotionality: 0.5}),

  // O-EB3 눈썹 강·눈 약
  _TreeRule(
      'O-EB3',
      (t) => _leafZ(t, 'eyebrow') >= 1.0 && _leafZ(t, 'eye') <= -1.0,
      const {Attribute.leadership: 0.5, Attribute.trustworthiness: -0.5}),

  // O-NM1 코-입 동조. v2.6 cap: wealth 2.0→0.5, soc 1.0→0.25.
  _TreeRule(
      'O-NM1',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.wealth: 0.5, Attribute.sociability: 0.25}),

  // O-NM2 코 강·입 약. v2.6 cap: soc -1.0→-0.5, wealth 0.5→0.25.
  _TreeRule(
      'O-NM2',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'mouth') <= -1.0,
      const {Attribute.wealth: 0.25, Attribute.sociability: -0.5}),

  // O-NM3 코 약·입 강. v2.6 cap: soc 1.5→0.5, wealth -0.5→-0.17.
  _TreeRule(
      'O-NM3',
      (t) => _leafZ(t, 'nose') <= -1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.sociability: 0.5, Attribute.wealth: -0.17}),

  // O-NC 코-턱 결합. v2.6 cap: 1.0→0.5, stab 0.5→0.25.
  _TreeRule(
      'O-NC',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'chin') >= 1.0,
      const {
        Attribute.wealth: 0.5,
        Attribute.leadership: 0.5,
        Attribute.stability: 0.25,
      }),

  // O-EM 눈-입 결합 — sociability 전용으로 축소. 매력은 O-MM/O-EM2 로 분리 (v2.9).
  //   임계 0.5 → 1.0 으로 통일 (다른 organ pair rule 과 일치).
  _TreeRule(
      'O-EM',
      (t) => _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'mouth') >= 1.0,
      const {Attribute.sociability: 0.33}),

  // O-FB 이마-눈썹 결합. v2.6 cap: lead 1.0→0.5, intel 0.5→0.25.
  _TreeRule(
      'O-FB',
      (t) => _leafZ(t, 'forehead') >= 1.0 && _leafZ(t, 'eyebrow') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.intelligence: 0.25}),

  // O-CK 광대 강. v2.6 cap: lead 0.8→0.5, wealth 0.3→0.19.
  _TreeRule('O-CK', (t) => _leafZ(t, 'cheekbone') >= 1.0, const {
    Attribute.leadership: 0.5,
    Attribute.wealth: 0.19,
  }),

  // O-CB 광대 약
  _TreeRule('O-CB', (t) => _leafZ(t, 'cheekbone') <= -1.0, const {
    Attribute.leadership: -0.5,
    Attribute.sociability: 0.3,
    Attribute.attractiveness: 0.3,
  }),

  // O-CKN 광대+코 동반 강. v2.6 cap: wealth 0.8→0.5, lead 0.5→0.31.
  _TreeRule(
      'O-CKN',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'nose') >= 1.0,
      const {Attribute.wealth: 0.5, Attribute.leadership: 0.31}),

  // O-CKC 광대+턱 동반 강. v2.6 cap: lead 0.8→0.5, stab 0.5→0.31.
  _TreeRule(
      'O-CKC',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'chin') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.stability: 0.31}),

  // O-CKF 광대+이마 동반 강
  _TreeRule(
      'O-CKF',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'forehead') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.intelligence: 0.5}),

  // O-PH1 인중 짧음. v2.6 cap: libido 1.5→0.5, sens 1.0→0.33.
  _TreeRule('O-PH1', (t) => _leafZ(t, 'philtrum') <= -1.0,
      const {Attribute.libido: 0.5, Attribute.sensuality: 0.33}),

  // O-PH2 인중 긺. v2.9: stability 0.5→0.25 — 인중 긴 얼굴이 stability 로만 수렴하던
  // 패턴 해소. trustworthiness 는 유지해 philtrum 이 신뢰 신호로 작동.
  _TreeRule('O-PH2', (t) => _leafZ(t, 'philtrum') >= 1.0,
      const {Attribute.stability: 0.25, Attribute.trustworthiness: 0.5}),

  // O-CH 턱 강. v2.6 cap: lead 1.0→0.5, stab 0.3→0.15.
  _TreeRule('O-CH', (t) => _leafZ(t, 'chin') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.stability: 0.15}),

  // O-DC1 코 등선 살짝/중간 볼록. v2.6 cap: lead 0.7→0.5, wealth 0.3→0.21.
  _TreeRule('O-DC1', (t) {
    final nose = t.descendantById('nose');
    if (nose == null) return false;
    final dc = nose.ownZ['dorsalConvexity'] ?? 0.0;
    return dc >= 1.5 && dc < 3.0;
  }, const {Attribute.leadership: 0.5, Attribute.wealth: 0.21}),

  // O-DC2 코 등선 살짝 오목
  _TreeRule('O-DC2', (t) {
    final nose = t.descendantById('nose');
    if (nose == null) return false;
    final dc = nose.ownZ['dorsalConvexity'] ?? 0.0;
    return dc <= -1.5 && dc > -3.0;
  }, const {Attribute.sensuality: 0.5, Attribute.emotionality: 0.3}),

  // O-NF1 비전두각 크다
  _TreeRule('O-NF1', (t) {
    final nose = t.descendantById('nose');
    if (nose == null) return false;
    final nf = nose.ownZ['nasofrontalAngle'] ?? 0.0;
    return nf >= 1.5;
  }, const {Attribute.intelligence: 0.5, Attribute.trustworthiness: 0.5}),

  // O-NF2 비전두각 작다
  _TreeRule('O-NF2', (t) {
    final nose = t.descendantById('nose');
    if (nose == null) return false;
    final nf = nose.ownZ['nasofrontalAngle'] ?? 0.0;
    return nf <= -1.5;
  }, const {Attribute.leadership: 0.5, Attribute.stability: -0.3}),

  // ─── 美人相 organ rule set (v2.9) ───
  // 麻衣相法·神相全編 美貌 명제 기반. attractiveness 전용 narrow rule.
  // 기존 lax/stacking source (O-EM 임계 0.5, Z-07/P-03 자동 stacking) 대체.

  // O-MM 美目流盼 — eye z≥1.0 AND eyeCanthalTilt z ∈ [0.3, 2.0].
  //   麻衣相法 "目如秋水, 媚生於目". 잘 발달한 눈 + 살짝 올라간 눈매 = 매력.
  //   P-06 처첩궁(eye absZ≥1 + tilt≥1)과 차별: P-06 은 sensuality 강조,
  //   O-MM 은 attractiveness 전용. 둘 다 발동 가능 (강한 매력+관능 동시).
  _TreeRule('O-MM', (t) {
    final eye = t.descendantById('eye');
    if (eye == null) return false;
    final tilt = eye.ownZ['eyeCanthalTilt'] ?? 0.0;
    return _leafZ(t, 'eye') >= 1.0 && tilt >= 0.3 && tilt <= 2.0;
  }, const {Attribute.attractiveness: 0.4}),

  // O-EM2 眉目清秀 — eye z≥1.0 AND eyebrow z≥0.5 AND eyebrowTilt ≥ -0.5.
  //   神相全編 "眉清目秀, 萬人之上". 눈 잘생기고 눈썹 단정 (처지지 않음).
  //   기존 O-EM (눈+입 lax) 의 attractiveness 부분 대체.
  _TreeRule('O-EM2', (t) {
    final eb = t.descendantById('eyebrow');
    if (eb == null) return false;
    final ebTilt = eb.ownZ['eyebrowTiltDirection'] ?? 0.0;
    return _leafZ(t, 'eye') >= 1.0 && _leafZ(t, 'eyebrow') >= 0.5 && ebTilt >= -0.5;
  }, const {Attribute.attractiveness: 0.3}),

  // O-RL 朱唇小口 — lipFullnessRatio z≥0.8 AND mouthWidthRatio z ∈ [-1.0, 0.3].
  //   麻衣相法 "唇如塗朱, 口如櫻桃". 도톰한 입술 + 작거나 보통 입.
  //   넓은 입 (mwr > 0.3) 은 sociability 신호로 분리 (Z-LFR).
  _TreeRule('O-RL', (t) {
    final mouth = t.descendantById('mouth');
    if (mouth == null) return false;
    final lfr = mouth.ownZ['lipFullnessRatio'] ?? 0.0;
    final mwr = mouth.ownZ['mouthWidthRatio'] ?? 0.0;
    return lfr >= 0.8 && mwr >= -1.0 && mwr <= 0.3;
  }, const {Attribute.attractiveness: 0.3}),

  // O-CKE 顴骨突過 — cheekbone z≥1.5. 광대 너무 솟음 = 인상 거침.
  //   麻衣相法 "顴骨高聳露骨, 神色不和".
  _TreeRule('O-CKE', (t) => _leafZ(t, 'cheekbone') >= 1.5,
      const {Attribute.attractiveness: -0.3}),

  // O-EZ 目偏不正 — eye absZ≥1.5 AND signed≤-0.5. 눈 부조화 (편차 큼 + 약함).
  //   神相全編 "目陷偏者, 形不和, 神不全". Z-09 (상정 abs) 보다 정확.
  _TreeRule('O-EZ', (t) {
    final eye = t.descendantById('eye');
    if (eye == null) return false;
    return (eye.ownMeanAbsZ ?? 0.0) >= 1.5 && _leafZ(t, 'eye') <= -0.5;
  }, const {Attribute.attractiveness: -0.3}),
];

// ──────────────────── Stage 4 — Palace Overlay ────────────────────

final _palaceRules = <_TreeRule>[
  // P-01 재백궁 + 전택궁. v2.6 cap: wealth 1.0→0.5, stab 0.3→0.15.
  _TreeRule(
      'P-01',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'eye') >= 1.0,
      const {Attribute.wealth: 0.5, Attribute.stability: 0.15}),

  // P-02 관록궁 + 천이궁. v2.6 cap: lead 1.5→0.5, intel 1.0→0.33.
  _TreeRule('P-02', (t) => _leafZ(t, 'forehead') >= 1.5,
      const {Attribute.leadership: 0.5, Attribute.intelligence: 0.33}),

  // P-03 복덕궁 — trust cross-zone 신호 전용. 매력은 P-MJ (印堂明潤) 로 narrowing (v2.9).
  //   福德宮은 본래 福·德 (안정·신뢰) 평가이지 美貌 자체 아님.
  _TreeRule('P-03', (t) {
    final root = t.rollUpMeanZ ?? 0.0;
    return root >= 0.3 &&
        _zoneSignedZ(t, 'upper') >= 0.0 &&
        _zoneSignedZ(t, 'middle') >= 0.0 &&
        _zoneSignedZ(t, 'lower') >= 0.0;
  }, const {Attribute.trustworthiness: 0.17}),

  // P-04 형제궁. v2.3 trust 1.0→0.3.
  _TreeRule(
      'P-04',
      (t) => _leafZ(t, 'eyebrow') >= 1.0 && _leafAbsZ(t, 'eyebrow') >= 1.5,
      const {Attribute.sociability: 0.5, Attribute.trustworthiness: 0.3}),

  // P-05 남녀궁. v2.6 cap: libido 1.0→0.5, emot 0.5→0.25, soc 0.3→0.15.
  _TreeRule(
      'P-05',
      (t) => _leafZ(t, 'eye') >= 1.0 && _zoneSignedZ(t, 'lower') >= 0.0,
      const {
        Attribute.libido: 0.5,
        Attribute.emotionality: 0.25,
        Attribute.sociability: 0.15,
      }),

  // P-06 처첩궁. v2.6 cap: sens 1.0→0.5, attr 0.5→0.25, emot 0.3→0.15.
  _TreeRule('P-06', (t) {
    final eye = t.descendantById('eye');
    if (eye == null) return false;
    final abs = eye.ownMeanAbsZ ?? 0.0;
    final tiltZ = eye.ownZ['eyeCanthalTilt'] ?? 0.0;
    return abs >= 1.0 && tiltZ >= 1.0;
  }, const {
    Attribute.sensuality: 0.5,
    Attribute.attractiveness: 0.25,
    Attribute.emotionality: 0.15,
  }),

  // P-07 질액궁
  _TreeRule('P-07', (t) => _leafAbsZ(t, 'nose') >= 1.5,
      const {Attribute.stability: -0.5}),

  // P-08 천이궁. v2.3 stability 0.5→0.2.
  _TreeRule('P-08', (t) {
    return _leafZ(t, 'forehead') >= 1.0 && (t.rollUpMeanAbsZ ?? 0.0) >= 0.5;
  }, const {
    Attribute.leadership: 0.5,
    Attribute.stability: 0.2,
    Attribute.intelligence: 0.5,
  }),

  // P-09 명궁 넓음. v2.4 stability 0.5→0.2.
  _TreeRule('P-09', (t) => _leafZ(t, 'glabella') >= 1.0, const {
    Attribute.wealth: 0.5,
    Attribute.stability: 0.2,
    Attribute.leadership: 0.3,
  }),

  // P-09B 명궁 좁음
  _TreeRule('P-09B', (t) => _leafZ(t, 'glabella') <= -1.0, const {
    Attribute.emotionality: 0.5,
    Attribute.intelligence: 0.3,
    Attribute.stability: -0.3,
  }),

  // P-MJ 印堂明潤 — glabella ownMeanZ ≥ 0.7.
  //   印堂 (명궁) 은 一身之主. 명궁 명윤하면 神氣 발현 → 美 신호.
  //   P-03 복덕궁의 attractiveness 부분 narrowing (cross-zone → single node).
  //   v2.9 신규.
  _TreeRule('P-MJ', (t) => _leafZ(t, 'glabella') >= 0.7,
      const {Attribute.attractiveness: 0.3}),
];

// ──────────────────── Stage 5 — Age (50+) Rules ────────────────────

final _ageRules = <_TreeRule>[
  // v2.6 cap: libido -1.0→-0.5, sens -0.5→-0.25.
  _TreeRule('A-01', (t) => _zoneSignedZ(t, 'lower') <= -1.0,
      const {Attribute.libido: -0.5, Attribute.sensuality: -0.25}),

  // v2.6 cap: intel 1.0→0.5, stab 0.5→0.25.
  _TreeRule('A-02', (t) => _zoneSignedZ(t, 'upper') >= 0.5,
      const {Attribute.intelligence: 0.5, Attribute.stability: 0.25}),

  // v2.6 cap: attr 1.5→0.5, stab 1.0→0.33.
  _TreeRule('A-03', (t) => _leafZ(t, 'mouth') >= 0.5,
      const {Attribute.attractiveness: 0.5, Attribute.stability: 0.33}),

  // v2.6 cap: attr -1.0→-0.5, emot 0.5→0.25.
  _TreeRule('A-04', (t) => (t.rollUpMeanZ ?? 0.0) <= -1.0,
      const {Attribute.emotionality: 0.25, Attribute.attractiveness: -0.5}),
];

// ──────────────────── Stage 5 — Lateral Flag Rules ────────────────────

final _lateralFlagRules = <_LateralFlagRule>[
  // v2.6 cap: lead 1.5→0.5, wealth 0.5→0.17, stab -0.3→-0.10.
  _LateralFlagRule('L-AQ', (t, f) => f['aquilineNose'] ?? false, const {
    Attribute.leadership: 0.5,
    Attribute.wealth: 0.17,
    Attribute.stability: -0.10,
  }),

  // v2.6 cap: soc 1.0→0.5, attr 0.5→0.25.
  _LateralFlagRule('L-SN', (t, f) => f['snubNose'] ?? false,
      const {Attribute.sociability: 0.5, Attribute.attractiveness: 0.25}),

  _LateralFlagRule('L-EL', (t, f) {
    final mouth = t.descendantById('mouth');
    if (mouth == null) return false;
    final upper = mouth.ownZ['upperLipEline'] ?? 0.0;
    final lower = mouth.ownZ['lowerLipEline'] ?? 0.0;
    return upper >= 1.0 && lower >= 1.0;
  }, const {Attribute.sensuality: 0.5, Attribute.libido: 0.5}),
];

// ──────────────────── Orchestrator ────────────────────

Map<Attribute, double> deriveAttributeScores({
  required NodeScore tree,
  required Gender gender,
  required bool isOver50,
  required bool hasLateral,
  Map<String, bool> lateralFlags = const {},
  FaceShape faceShape = FaceShape.unknown,
  double shapeConfidence = 0.0,
}) {
  return deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: isOver50,
    hasLateral: hasLateral,
    lateralFlags: lateralFlags,
    faceShape: faceShape,
    shapeConfidence: shapeConfidence,
  ).total;
}

AttributeBreakdown deriveAttributeScoresDetailed({
  required NodeScore tree,
  required Gender gender,
  required bool isOver50,
  required bool hasLateral,
  Map<String, bool> lateralFlags = const {},
  FaceShape faceShape = FaceShape.unknown,
  double shapeConfidence = 0.0,
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

  // Stage 1: base per-node
  for (final attr in Attribute.values) {
    final perNode = basePerNode[attr]!;
    double sum = 0.0;
    for (final v in perNode.values) {
      sum += v;
    }
    total[attr] = (total[attr] ?? 0.0) + sum;
  }

  // Stage 1b: distinctiveness
  distinct.forEach((a, v) => total[a] = (total[a] ?? 0.0) + v);

  // Stage 2-5: rules
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

  // Shape overlay (applied LAST) — baseline-gated. total 에 이미 쌓인 signal 을
  // gate 입력으로 써서 평균 얼굴엔 약하게, 뚜렷 얼굴엔 전체로 증폭.
  final shapePreset = _stage0ShapePreset(faceShape, shapeConfidence, total);
  shapePreset.forEach((a, v) => total[a] = (total[a] ?? 0.0) + v);

  return AttributeBreakdown(
    basePerNode: basePerNode,
    shapePreset: shapePreset,
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

// ──────────────────── Sanity helpers (testing) ────────────────────

/// per-metric 총 영향력 = Σ_attr(노드 weight ÷ 노드 내 metric 수).
/// sanity test 에서 "단일 metric 과적재 / 고아 metric" 회귀 차단.
@visibleForTesting
Map<String, double> perMetricInfluence() {
  final out = <String, double>{};
  for (final attr in Attribute.values) {
    for (final w in _weightMatrix[attr]!) {
      final node = nodeById[w.nodeId];
      if (node == null || node.metricIds.isEmpty) continue;
      final share = w.weight / node.metricIds.length;
      for (final m in node.metricIds) {
        out[m] = (out[m] ?? 0.0) + share;
      }
    }
  }
  return out;
}

@visibleForTesting
Map<Attribute, double> attributeRowSums() => {
      for (final entry in _weightMatrix.entries)
        entry.key: entry.value.fold<double>(0.0, (s, w) => s + w.weight),
    };

@visibleForTesting
Map<Attribute, Set<Zone>> attributeZoneCoverage() => {
      for (final entry in _weightMatrix.entries)
        entry.key: entry.value
            .map((w) => nodeById[w.nodeId]?.zone)
            .whereType<Zone>()
            .toSet(),
    };

/// Per-attribute zone weight sum. v2.6 불변식: 모든 값 ∈ [0.25, 0.40].
@visibleForTesting
Map<Attribute, Map<Zone, double>> attributeZoneWeightSums() {
  final out = <Attribute, Map<Zone, double>>{
    for (final a in Attribute.values)
      a: {for (final z in Zone.values) z: 0.0},
  };
  for (final entry in _weightMatrix.entries) {
    for (final w in entry.value) {
      final zone = nodeById[w.nodeId]?.zone;
      if (zone == null) continue;
      out[entry.key]![zone] =
          (out[entry.key]![zone] ?? 0.0) + w.weight.abs();
    }
  }
  return out;
}

@visibleForTesting
List<String> weightedNodeIds(Attribute attr) =>
    _weightMatrix[attr]!.map((w) => w.nodeId).toList(growable: false);
