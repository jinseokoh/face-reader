/// 五行 5×5 matrix + secondary-overlay blend.
///
/// §2.4 relation matrix + §2.5 blend 공식. L1 `elementScore` 산출.
library;

import 'five_element.dart';

/// 5×5 base matrix. row = my primary, col = album primary.
/// §2.4 와 1:1 동일. `比和` 대각은 element 별로 다름 (木/火/土/金/水 = 50/45/55/48/42).
const Map<FiveElement, Map<FiveElement, double>> _matrix = {
  FiveElement.wood: {
    FiveElement.wood: 50,
    FiveElement.fire: 70,
    FiveElement.earth: 28,
    FiveElement.metal: 32,
    FiveElement.water: 65,
  },
  FiveElement.fire: {
    FiveElement.wood: 65,
    FiveElement.fire: 45,
    FiveElement.earth: 72,
    FiveElement.metal: 30,
    FiveElement.water: 25,
  },
  FiveElement.earth: {
    FiveElement.wood: 28,
    FiveElement.fire: 68,
    FiveElement.earth: 55,
    FiveElement.metal: 72,
    FiveElement.water: 32,
  },
  FiveElement.metal: {
    FiveElement.wood: 30,
    FiveElement.fire: 25,
    FiveElement.earth: 70,
    FiveElement.metal: 48,
    FiveElement.water: 72,
  },
  FiveElement.water: {
    FiveElement.wood: 68,
    FiveElement.fire: 25,
    FiveElement.earth: 28,
    FiveElement.metal: 72,
    FiveElement.water: 42,
  },
};

/// base matrix lookup. 테스트 invariant 용 export.
double matrixScore(FiveElement myPrimary, FiveElement albumPrimary) {
  return _matrix[myPrimary]![albumPrimary]!;
}

/// my primary 기준의 상생/상극 관계 kind.
ElementRelationKind relationKind(FiveElement my, FiveElement album) {
  if (my == album) return ElementRelationKind.identity;
  // 상생 고리: 木→火→土→金→水→木
  const generates = {
    FiveElement.wood: FiveElement.fire,
    FiveElement.fire: FiveElement.earth,
    FiveElement.earth: FiveElement.metal,
    FiveElement.metal: FiveElement.water,
    FiveElement.water: FiveElement.wood,
  };
  // 상극 대각: 木克土·土克水·水克火·火克金·金克木
  const overcomes = {
    FiveElement.wood: FiveElement.earth,
    FiveElement.earth: FiveElement.water,
    FiveElement.water: FiveElement.fire,
    FiveElement.fire: FiveElement.metal,
    FiveElement.metal: FiveElement.wood,
  };
  if (generates[my] == album) return ElementRelationKind.generating;
  if (generates[album] == my) return ElementRelationKind.generated;
  if (overcomes[my] == album) return ElementRelationKind.overcoming;
  if (overcomes[album] == my) return ElementRelationKind.overcome;
  // 5×5 에서 위 4 케이스 + identity 로 전부 커버 — 도달 불가.
  return ElementRelationKind.identity;
}

/// §2.5 blend — primary × primary 중심, secondary overlay 반영.
///
/// 겸형(confidence < 0.08) 일 때 secondary weight 를 0.15 → 0.20 으로 상향.
ElementRelation elementRelationScore({
  required FiveElements my,
  required FiveElements album,
}) {
  final wSec = (my.isHybrid || album.isHybrid) ? 0.20 : 0.15;
  // secondary×secondary 의 weight 는 남는 비율 일부. wPP + 2*wSec + wSS = 1.
  // base 레시피(0.70/0.15/0.15/0.05) 를 겸형 때도 동일 ratio 로 스케일.
  const wSS = 0.05;
  final wPP = 1.0 - 2 * wSec - wSS;

  final blended = wPP * _matrix[my.primary]![album.primary]! +
      wSec * _matrix[my.primary]![album.secondary]! +
      wSec * _matrix[my.secondary]![album.primary]! +
      wSS * (_matrix[my.secondary]![album.secondary]! - 50);

  final clamped = blended.clamp(5.0, 99.0);
  final kind = relationKind(my.primary, album.primary);
  return ElementRelation(my: my, album: album, score: clamped, kind: kind);
}
