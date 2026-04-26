/// 五行 (Five Elements) — 궁합 엔진 L1 층의 데이터 타입.
///
/// 전통 관상학(麻衣相法 相法賦·五形, 神相全編 五形形格)의 五形 을
/// 체형 metric 기반으로 재현한다. primary/secondary 2 축과 confidence 로
/// 겸형(兼形) 여부까지 담는다.
///
/// 설계 SSOT: `docs/compat/FRAMEWORK.md` §2.
library;

/// 五行. 木火土金水 + `unknown` (classifier fallback).
enum FiveElement {
  /// 木形 — 길쭉·骨格 선명, 상정 길고 중·하정 얇음. 木主仁.
  wood,

  /// 火形 — 三角·顴骨 突, 아래 뾰족. 火主禮.
  fire,

  /// 土形 — 두툼·방정·厚重. 土主信.
  earth,

  /// 金形 — 方形·각진·骨硬. 金主義.
  metal,

  /// 水形 — 둥글·살집·부드러움, 하정 풍부. 水主智.
  water,
}

extension FiveElementLabel on FiveElement {
  String get hanja {
    switch (this) {
      case FiveElement.wood:
        return '木';
      case FiveElement.fire:
        return '火';
      case FiveElement.earth:
        return '土';
      case FiveElement.metal:
        return '金';
      case FiveElement.water:
        return '水';
    }
  }

  String get korean {
    switch (this) {
      case FiveElement.wood:
        return '목형';
      case FiveElement.fire:
        return '화형';
      case FiveElement.earth:
        return '토형';
      case FiveElement.metal:
        return '금형';
      case FiveElement.water:
        return '수형';
    }
  }
}

/// 체형 분류 결과 — primary/secondary + confidence + 정규화 score map.
class FiveElements {
  /// 가장 우세한 五形 (top-1).
  final FiveElement primary;

  /// 두 번째로 우세한 五形 (top-2).
  final FiveElement secondary;

  /// (top1 - top2) / top1. 0 에 가까우면 겸형(兼形).
  /// narrative 에서 confidence < 0.08 이면 "겸형" 표현 사용.
  final double confidence;

  /// 5 형 각각의 정규화 score (0~100, 합은 not-fixed).
  /// 디버깅/테스트 invariant 용.
  final Map<FiveElement, double> scores;

  const FiveElements({
    required this.primary,
    required this.secondary,
    required this.confidence,
    required this.scores,
  });

  /// 겸형(兼形) 여부. confidence < 0.08.
  bool get isHybrid => confidence < 0.08;
}

/// 5×5 관계 분류. 자기 자신은 `identity`, 상생 고리는 `generating`/`generated`,
/// 상극 대각은 `overcoming`/`overcome`.
enum ElementRelationKind {
  /// 比和 — 같은 五形 (e.g. 木×木).
  identity,

  /// 生(출력) — 내가 상대를 낳음 (e.g. 木→火).
  generating,

  /// 被生 — 상대가 나를 낳음 (e.g. 水→木).
  generated,

  /// 剋(출력) — 내가 상대를 극함 (e.g. 木→土).
  overcoming,

  /// 被剋 — 상대가 나를 극함 (e.g. 金→木).
  overcome,
}

extension ElementRelationKindLabel on ElementRelationKind {
  /// 한자 라벨 (괄호 보조용).
  String get hanja {
    switch (this) {
      case ElementRelationKind.identity:
        return '比和';
      case ElementRelationKind.generating:
        return '相生';
      case ElementRelationKind.generated:
        return '被生';
      case ElementRelationKind.overcoming:
        return '相剋';
      case ElementRelationKind.overcome:
        return '被剋';
    }
  }

  /// 한국어 설명 한 줄. 해설 본문에서 우선 쓴다.
  String get koreanLabel {
    switch (this) {
      case ElementRelationKind.identity:
        return '같은 형끼리의 공명';
      case ElementRelationKind.generating:
        return '내가 상대를 낳아 주는 상생';
      case ElementRelationKind.generated:
        return '상대가 나를 받쳐 주는 상생';
      case ElementRelationKind.overcoming:
        return '내가 상대를 다스리는 상극';
      case ElementRelationKind.overcome:
        return '상대가 나를 누르는 상극';
    }
  }
}

extension FiveElementTraits on FiveElement {
  /// 체형·성정의 한 문장 묘사. 해설 본문 "나의 형"·"상대의 형" 소개에 쓴다.
  String get traitKo {
    switch (this) {
      case FiveElement.wood:
        return '길쭉한 골격에 상정이 높아 곧게 자라는 나무의 결';
      case FiveElement.fire:
        return '광대가 솟고 아래로 좁아지는 불꽃의 결, 예의를 중히 여기는 성정';
      case FiveElement.earth:
        return '두툼하고 방정한 땅의 결, 신의를 지키는 성정';
      case FiveElement.metal:
        return '각진 뼈대가 단단한 금속의 결, 의리를 우선하는 성정';
      case FiveElement.water:
        return '둥글고 살집 있는 물의 결, 지혜와 수용을 품은 성정';
    }
  }
}

/// L1 최종 산출물 — `ElementRelation`.
///
/// 두 `FiveElements` (my·album) 의 primary 와 secondary 를 모두 고려한
/// blended 점수 + 상생·상극 kind 라벨.
class ElementRelation {
  final FiveElements my;
  final FiveElements album;

  /// §2.5 blend 공식 결과. 5~99 clamp.
  final double score;

  /// my.primary × album.primary 의 관계 kind (narrative 에서 라벨 근거).
  final ElementRelationKind kind;

  const ElementRelation({
    required this.my,
    required this.album,
    required this.score,
    required this.kind,
  });
}
