/// 관상 tree node scoring — Phase 2.
///
/// input:  metric id → z-score (from existing analyzeFaceReading pipeline)
/// output: PhysiognomyNode tree mirror with own-stats + roll-up stats per node
///
/// 평균 scheme: 등가중(equal weight) signed mean 과 mean-abs (magnitude).
/// Phase 3 에서 per-metric weight 도입 시 확장 지점을 여기에 둔다.
library;

import 'package:face_engine/domain/models/physiognomy_tree.dart';

/// 한 노드의 점수 스냅샷. 불변.
class NodeScore {
  /// 원본 tree 노드 id (`'face'`, `'forehead'`, ...).
  final String nodeId;

  /// 한글 표시명.
  final String nameKo;

  /// 삼정 소속 (루트는 null).
  final Zone? zone;

  /// 이 노드의 **own metric** z-score 맵. 입력에 없던 metric 은 제외.
  /// 자식 노드의 metric 은 포함하지 않음(roll-up 에서만).
  final Map<String, double> ownZ;

  /// 자식 노드 점수. 같은 방식으로 재귀 구성.
  final List<NodeScore> children;

  const NodeScore({
    required this.nodeId,
    required this.nameKo,
    required this.zone,
    required this.ownZ,
    required this.children,
  });

  // ─── own stats (이 노드의 metric 만) ───

  int get ownMetricCount => ownZ.length;

  /// 부호 보존 평균 (방향 정보). 메트릭이 없으면 null.
  double? get ownMeanZ {
    if (ownZ.isEmpty) return null;
    final s = ownZ.values.fold<double>(0, (a, b) => a + b);
    return s / ownZ.length;
  }

  /// |z| 평균 (distinctiveness / 편차 강도).
  double? get ownMeanAbsZ {
    if (ownZ.isEmpty) return null;
    final s = ownZ.values.fold<double>(0, (a, b) => a + b.abs());
    return s / ownZ.length;
  }

  // ─── roll-up stats (자신 + 모든 하위) ───

  /// own + descendants 의 z 전체. 재귀.
  Map<String, double> get rollUpZ {
    final out = <String, double>{...ownZ};
    for (final c in children) {
      out.addAll(c.rollUpZ);
    }
    return out;
  }

  int get rollUpMetricCount => rollUpZ.length;

  double? get rollUpMeanZ {
    final zs = rollUpZ.values;
    if (zs.isEmpty) return null;
    return zs.fold<double>(0, (a, b) => a + b) / zs.length;
  }

  double? get rollUpMeanAbsZ {
    final zs = rollUpZ.values;
    if (zs.isEmpty) return null;
    return zs.fold<double>(0, (a, b) => a + b.abs()) / zs.length;
  }

  // ─── 룩업 헬퍼 ───

  /// 하위 트리(자신 제외)에서 id 로 노드 찾기. 없으면 null.
  NodeScore? descendantById(String id) {
    for (final c in children) {
      if (c.nodeId == id) return c;
      final grand = c.descendantById(id);
      if (grand != null) return grand;
    }
    return null;
  }
}

/// 단일 노드 점수화. 재귀적으로 자식도 함께 점수화.
NodeScore scoreNode(PhysiognomyNode node, Map<String, double> zByMetric) {
  final own = <String, double>{};
  for (final m in node.metricIds) {
    final z = zByMetric[m];
    if (z != null) own[m] = z;
  }
  return NodeScore(
    nodeId: node.id,
    nameKo: node.nameKo,
    zone: node.zone,
    ownZ: Map.unmodifiable(own),
    children: List.unmodifiable(
      node.children.map((c) => scoreNode(c, zByMetric)),
    ),
  );
}

/// 최상위 편의 함수 — 전체 tree 점수화.
NodeScore scoreTree(Map<String, double> zByMetric) =>
    scoreNode(faceTree, zByMetric);
