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

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/physiognomy_tree.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

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

// ──────────────────── §2.2 Weight Matrix (9 노드) ────────────────────
//
// face(root) · ear 제외. row 합 = 1.00.
// 최대 per-node weight 0.40 상한, 단일 metric 노드(glabella·cheekbone·philtrum)
// 는 per-attr weight 0.25 상한. 의미론 구멍(eye→sociab/trust, chin→매력도,
// 하정 3노드→관능) 메움.

const _weightMatrix = <Attribute, List<_NodeWeight>>{
  Attribute.wealth: [
    _NodeWeight('forehead', 0.05, 1),
    _NodeWeight('glabella', 0.05, 1),
    _NodeWeight('eye', 0.05, 1),
    _NodeWeight('nose', 0.35, 1),
    _NodeWeight('cheekbone', 0.15, 1),
    _NodeWeight('mouth', 0.15, 1),
    _NodeWeight('chin', 0.20, 1),
  ],
  Attribute.leadership: [
    _NodeWeight('forehead', 0.25, 1),
    _NodeWeight('glabella', 0.05, 1),
    _NodeWeight('eyebrow', 0.15, 1),
    _NodeWeight('eye', 0.05, 1),
    _NodeWeight('nose', 0.15, 1),
    _NodeWeight('cheekbone', 0.15, 1),
    _NodeWeight('mouth', 0.05, 1),
    _NodeWeight('chin', 0.15, 1),
  ],
  Attribute.intelligence: [
    _NodeWeight('forehead', 0.25, 1),
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.25, 1),
    _NodeWeight('eye', 0.30, 1),
    _NodeWeight('nose', 0.05, 1),
    _NodeWeight('chin', 0.05, 1),
  ],
  Attribute.sociability: [
    _NodeWeight('eyebrow', 0.05, 1),
    _NodeWeight('eye', 0.20, 1),
    _NodeWeight('nose', 0.05, 1),
    _NodeWeight('cheekbone', 0.15, 1),
    _NodeWeight('philtrum', 0.05, 1),
    _NodeWeight('mouth', 0.30, 1),
    _NodeWeight('chin', 0.20, 1),
  ],
  Attribute.emotionality: [
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.20, 1),
    _NodeWeight('eye', 0.35, 1),
    _NodeWeight('philtrum', 0.05, 1),
    _NodeWeight('mouth', 0.20, 1),
    _NodeWeight('chin', 0.10, 1),
  ],
  Attribute.stability: [
    _NodeWeight('forehead', 0.20, 1),
    _NodeWeight('glabella', 0.10, 1),
    _NodeWeight('eyebrow', 0.05, 1),
    _NodeWeight('eye', 0.05, 1),
    _NodeWeight('nose', 0.15, 1),
    _NodeWeight('cheekbone', 0.05, 1),
    _NodeWeight('philtrum', 0.05, 1),
    _NodeWeight('chin', 0.35, 1),
  ],
  Attribute.sensuality: [
    _NodeWeight('eyebrow', 0.10, 1),
    _NodeWeight('eye', 0.25, 1),
    _NodeWeight('nose', 0.05, 1),
    _NodeWeight('cheekbone', 0.10, 1),
    _NodeWeight('philtrum', 0.10, 1),
    _NodeWeight('mouth', 0.25, 1),
    _NodeWeight('chin', 0.15, 1),
  ],
  Attribute.trustworthiness: [
    _NodeWeight('forehead', 0.20, 1),
    _NodeWeight('glabella', 0.05, 1),
    _NodeWeight('eyebrow', 0.15, 1),
    _NodeWeight('eye', 0.20, 1),
    _NodeWeight('nose', 0.20, 1),
    _NodeWeight('cheekbone', 0.05, 1),
    _NodeWeight('philtrum', 0.05, 1),
    _NodeWeight('mouth', 0.05, 1),
    _NodeWeight('chin', 0.05, 1),
  ],
  Attribute.attractiveness: [
    _NodeWeight('forehead', 0.05, 1),
    _NodeWeight('eyebrow', 0.10, 1),
    _NodeWeight('eye', 0.30, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.05, 1),
    _NodeWeight('philtrum', 0.05, 1),
    _NodeWeight('mouth', 0.20, 1),
    _NodeWeight('chin', 0.15, 1),
  ],
  Attribute.libido: [
    _NodeWeight('eyebrow', 0.05, 1),
    _NodeWeight('eye', 0.25, 1),
    _NodeWeight('nose', 0.10, 1),
    _NodeWeight('cheekbone', 0.05, 1),
    _NodeWeight('philtrum', 0.20, -1),
    _NodeWeight('mouth', 0.15, 1),
    _NodeWeight('chin', 0.20, 1),
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

// ──────────────────── Stage 0 — Face-Shape Preset (Layer A) ────────────────────
//
// ML 분류기 결과(FaceShape enum) 를 공동 bias 로 주입. shapeConfidence 로
// 스케일 → ML 확신도 낮으면 효과도 작음. calibration 시 shape 분포 반영.

const _shapePresetDelta = <FaceShape, Map<Attribute, double>>{
  FaceShape.oval: {
    Attribute.attractiveness: 0.30,
    Attribute.sociability: 0.20,
    Attribute.stability: 0.15,
    Attribute.trustworthiness: 0.10,
  },
  FaceShape.oblong: {
    Attribute.intelligence: 0.30,
    Attribute.emotionality: 0.20,
    Attribute.trustworthiness: 0.10,
    Attribute.sociability: -0.15,
    Attribute.sensuality: -0.10,
  },
  FaceShape.round: {
    Attribute.wealth: 0.25,
    Attribute.sociability: 0.25,
    Attribute.emotionality: 0.15,
    Attribute.leadership: -0.15,
    Attribute.stability: -0.10,
  },
  FaceShape.square: {
    Attribute.leadership: 0.30,
    Attribute.stability: 0.25,
    Attribute.trustworthiness: 0.15,
    Attribute.attractiveness: -0.15,
    Attribute.sensuality: -0.10,
  },
  FaceShape.heart: {
    Attribute.intelligence: 0.25,
    Attribute.sensuality: 0.20,
    Attribute.attractiveness: 0.15,
    Attribute.stability: -0.20,
    Attribute.wealth: -0.10,
  },
  FaceShape.unknown: {},
};

Map<Attribute, double> _stage0ShapePreset(
    FaceShape shape, double confidence) {
  assert(confidence >= 0.0 && confidence <= 1.0,
      'shapeConfidence must be in [0, 1], got $confidence');
  final out = <Attribute, double>{for (final a in Attribute.values) a: 0.0};
  final delta = _shapePresetDelta[shape];
  if (delta == null) return out;
  final scale = confidence.clamp(0.0, 1.0);
  delta.forEach((a, v) => out[a] = v * scale);
  return out;
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

  // attractiveness: metric 없으면 판단 보류(0). 있으면 평균 근접(faceAbs≈0.7)
  // 에서 +0.20 피크, 극단에서 −0.25 감점. clamp(-0.25, +0.20).
  final faceAbs = tree.rollUpMeanAbsZ;
  if (faceAbs != null) {
    final diff = (faceAbs - 0.7).abs();
    out[Attribute.attractiveness] = (0.20 - 0.5 * diff).clamp(-0.25, 0.20);
  }

  // intelligence: 상정 distinctiveness → 지적 인상
  final upperAbs = _zoneAbsZ(tree, 'upper');
  out[Attribute.intelligence] = 0.2 * (upperAbs - 0.5).clamp(0.0, 1.5);

  // emotionality: 하정 distinctiveness → 감정 풍부
  final lowerAbs = _zoneAbsZ(tree, 'lower');
  out[Attribute.emotionality] = 0.3 * (lowerAbs - 0.5).clamp(0.0, 1.5);

  return out;
}

// ──────────────────── Stage 2 — Zone Rules ────────────────────

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

  // Z-11 중정 비율 큼 — root own `midFaceRatio` ≥ 1.0
  _TreeRule('Z-11', (t) => (t.ownZ['midFaceRatio'] ?? 0.0) >= 1.0,
      const {Attribute.wealth: 0.5, Attribute.sociability: 0.3}),

  // Z-12 하정 비율 큼 — chin 의 lowerFaceRatio z ≥ 1.0
  _TreeRule(
      'Z-12',
      (t) => (t.descendantById('chin')?.ownZ['lowerFaceRatio'] ?? 0.0) >= 1.0,
      const {Attribute.stability: 0.5, Attribute.trustworthiness: 0.3}),

  // Z-13 하정 비율 작음
  _TreeRule(
      'Z-13',
      (t) => (t.descendantById('chin')?.ownZ['lowerFaceRatio'] ?? 0.0) <= -1.0,
      const {Attribute.emotionality: 0.3, Attribute.stability: -0.3}),
];

// ──────────────────── Stage 3 — Organ Rules ────────────────────

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

  // O-NC 코-턱 결합
  _TreeRule(
      'O-NC',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'chin') >= 1.0,
      const {
        Attribute.wealth: 1.0,
        Attribute.leadership: 1.0,
        Attribute.stability: 0.5,
      }),

  // O-EM 눈-입 결합 — Opt-B: 임계 1.0 → 0.5 로 완화(매력도 기여 발동률 ↑).
  _TreeRule(
      'O-EM',
      (t) => _leafZ(t, 'eye') >= 0.5 && _leafZ(t, 'mouth') >= 0.5,
      const {Attribute.attractiveness: 1.5, Attribute.sociability: 1.0}),

  // O-FB 이마-눈썹 결합
  _TreeRule(
      'O-FB',
      (t) => _leafZ(t, 'forehead') >= 1.0 && _leafZ(t, 'eyebrow') >= 1.0,
      const {Attribute.leadership: 1.0, Attribute.intelligence: 0.5}),

  // O-CK 광대 강 — Opt-B: 매력도 감점 삭제(문화적 과잉).
  _TreeRule('O-CK', (t) => _leafZ(t, 'cheekbone') >= 1.0, const {
    Attribute.leadership: 0.8,
    Attribute.wealth: 0.3,
  }),

  // O-CB 광대 약
  _TreeRule('O-CB', (t) => _leafZ(t, 'cheekbone') <= -1.0, const {
    Attribute.leadership: -0.5,
    Attribute.sociability: 0.3,
    Attribute.attractiveness: 0.3,
  }),

  // O-CKN 광대+코 동반 강
  _TreeRule(
      'O-CKN',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'nose') >= 1.0,
      const {Attribute.wealth: 0.8, Attribute.leadership: 0.5}),

  // O-CKC 광대+턱 동반 강
  _TreeRule(
      'O-CKC',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'chin') >= 1.0,
      const {Attribute.leadership: 0.8, Attribute.stability: 0.5}),

  // O-CKF 광대+이마 동반 강
  _TreeRule(
      'O-CKF',
      (t) => _leafZ(t, 'cheekbone') >= 1.0 && _leafZ(t, 'forehead') >= 1.0,
      const {Attribute.leadership: 0.5, Attribute.intelligence: 0.5}),

  // O-PH1 인중 짧음
  _TreeRule('O-PH1', (t) => _leafZ(t, 'philtrum') <= -1.0,
      const {Attribute.libido: 1.5, Attribute.sensuality: 1.0}),

  // O-PH2 인중 긺
  _TreeRule('O-PH2', (t) => _leafZ(t, 'philtrum') >= 1.0,
      const {Attribute.stability: 0.5, Attribute.trustworthiness: 0.5}),

  // O-CH 턱 강
  _TreeRule('O-CH', (t) => _leafZ(t, 'chin') >= 1.0,
      const {Attribute.leadership: 1.0, Attribute.stability: 1.0}),

  // O-DC1 코 등선 살짝/중간 볼록
  _TreeRule('O-DC1', (t) {
    final nose = t.descendantById('nose');
    if (nose == null) return false;
    final dc = nose.ownZ['dorsalConvexity'] ?? 0.0;
    return dc >= 1.5 && dc < 3.0;
  }, const {Attribute.leadership: 0.7, Attribute.wealth: 0.3}),

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
];

// ──────────────────── Stage 4 — Palace Overlay ────────────────────

final _palaceRules = <_TreeRule>[
  // P-01 재백궁 + 전택궁
  _TreeRule(
      'P-01',
      (t) => _leafZ(t, 'nose') >= 1.0 && _leafZ(t, 'eye') >= 1.0,
      const {Attribute.wealth: 1.0, Attribute.stability: 1.0}),

  // P-02 관록궁 + 천이궁
  _TreeRule('P-02', (t) => _leafZ(t, 'forehead') >= 1.5,
      const {Attribute.leadership: 1.5, Attribute.intelligence: 1.0}),

  // P-03 복덕궁 — Opt-B: 임계 root≥0.8 → 0.3 로 완화(매력도 positive 발동률 ↑).
  _TreeRule('P-03', (t) {
    final root = t.rollUpMeanZ ?? 0.0;
    return root >= 0.3 &&
        _zoneSignedZ(t, 'upper') >= 0.0 &&
        _zoneSignedZ(t, 'middle') >= 0.0 &&
        _zoneSignedZ(t, 'lower') >= 0.0;
  }, const {Attribute.attractiveness: 1.5, Attribute.trustworthiness: 0.5}),

  // P-04 형제궁
  _TreeRule(
      'P-04',
      (t) => _leafZ(t, 'eyebrow') >= 1.0 && _leafAbsZ(t, 'eyebrow') >= 1.5,
      const {Attribute.sociability: 0.5, Attribute.trustworthiness: 1.0}),

  // P-05 남녀궁
  _TreeRule(
      'P-05',
      (t) => _leafZ(t, 'eye') >= 1.0 && _zoneSignedZ(t, 'lower') >= 0.0,
      const {
        Attribute.libido: 1.0,
        Attribute.emotionality: 0.5,
        Attribute.sociability: 0.3,
      }),

  // P-06 처첩궁
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

  // P-07 질액궁
  _TreeRule('P-07', (t) => _leafAbsZ(t, 'nose') >= 1.5,
      const {Attribute.stability: -0.5}),

  // P-08 천이궁
  _TreeRule('P-08', (t) {
    return _leafZ(t, 'forehead') >= 1.0 && (t.rollUpMeanAbsZ ?? 0.0) >= 0.5;
  }, const {
    Attribute.leadership: 0.5,
    Attribute.stability: 0.5,
    Attribute.intelligence: 0.5,
  }),

  // P-09 명궁 넓음
  _TreeRule('P-09', (t) => _leafZ(t, 'glabella') >= 1.0, const {
    Attribute.wealth: 0.5,
    Attribute.stability: 0.5,
    Attribute.leadership: 0.3,
  }),

  // P-09B 명궁 좁음
  _TreeRule('P-09B', (t) => _leafZ(t, 'glabella') <= -1.0, const {
    Attribute.emotionality: 0.5,
    Attribute.intelligence: 0.3,
    Attribute.stability: -0.3,
  }),
];

// ──────────────────── Stage 5 — Age (50+) Rules ────────────────────

final _ageRules = <_TreeRule>[
  _TreeRule('A-01', (t) => _zoneSignedZ(t, 'lower') <= -1.0,
      const {Attribute.libido: -1.0, Attribute.sensuality: -0.5}),

  _TreeRule('A-02', (t) => _zoneSignedZ(t, 'upper') >= 0.5,
      const {Attribute.intelligence: 1.0, Attribute.stability: 0.5}),

  _TreeRule('A-03', (t) => _leafZ(t, 'mouth') >= 0.5,
      const {Attribute.attractiveness: 1.5, Attribute.stability: 1.0}),

  _TreeRule('A-04', (t) => (t.rollUpMeanZ ?? 0.0) <= -1.0,
      const {Attribute.emotionality: 0.5, Attribute.attractiveness: -1.0}),
];

// ──────────────────── Stage 5 — Lateral Flag Rules ────────────────────

final _lateralFlagRules = <_LateralFlagRule>[
  _LateralFlagRule('L-AQ', (t, f) => f['aquilineNose'] ?? false, const {
    Attribute.leadership: 1.5,
    Attribute.wealth: 0.5,
    Attribute.stability: -0.3,
  }),

  _LateralFlagRule('L-SN', (t, f) => f['snubNose'] ?? false,
      const {Attribute.sociability: 1.0, Attribute.attractiveness: 0.5}),

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
  final shapePreset = _stage0ShapePreset(faceShape, shapeConfidence);
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

  // stage 0 preset
  shapePreset.forEach((a, v) => total[a] = (total[a] ?? 0.0) + v);

  // base per-node
  for (final attr in Attribute.values) {
    final perNode = basePerNode[attr]!;
    double sum = 0.0;
    for (final v in perNode.values) {
      sum += v;
    }
    total[attr] = (total[attr] ?? 0.0) + sum;
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

@visibleForTesting
List<String> weightedNodeIds(Attribute attr) =>
    _weightMatrix[attr]!.map((w) => w.nodeId).toList(growable: false);
