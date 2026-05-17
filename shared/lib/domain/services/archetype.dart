import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';

class ArchetypeResult {
  final Attribute primary;
  final Attribute secondary;
  final String primaryLabel;
  final String secondaryLabel;
  final String? specialArchetype;

  const ArchetypeResult({
    required this.primary,
    required this.secondary,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.specialArchetype,
  });
}

const _archetypeLabels = <Attribute, String>{
  Attribute.wealth: '사업가형',
  Attribute.leadership: '리더형',
  Attribute.intelligence: '학자형',
  Attribute.sociability: '외교형',
  Attribute.emotionality: '예술가형',
  Attribute.stability: '현자형',
  Attribute.sensuality: '연예인형',
  Attribute.trustworthiness: '신의형',
  Attribute.attractiveness: '호감형',
  Attribute.libido: '정열형',
};

class _GenderPrior {
  final double male;
  final double female;
  const _GenderPrior(this.male, this.female);
}

/// Archetype 별 gender prior — 麻衣相法 canon 의 archetype 본래 gender 함의를
/// 분류 단계에 반영한다. 정규화된 attribute score (5~10) 에 곱해 *분류 ranking
/// 용* 만으로 사용 — 원 score (attributes[].normalizedScore) 는 건드리지 않는다.
///
/// 값 범위 0.90 ~ 1.10. neutral = 1.00. 분류 swap 위험 최소화 (top-1 ↔ top-2
/// 격차가 ~5% 이내일 때만 swap 가능).
///
/// 근거:
/// - 麻衣相法·神相全編 archetype 의 gender 본 매핑 (將軍·王相·君子 vs 桃花·美人·賢妻)
/// - 우리 archetype 라벨 본문이 이미 gender 분기되어 있다는 점 (의도적 redundancy)
const _genderPriors = <Attribute, _GenderPrior>{
  // 사업가형 — 鼻=재백궁, 약한 male-lean (transactional canon)
  Attribute.wealth: _GenderPrior(1.05, 0.95),
  // 리더형 — 將軍·王相 강한 male canon
  Attribute.leadership: _GenderPrior(1.10, 0.90),
  // 학자형 — 學士·君子 약한 male-lean (modern soft)
  Attribute.intelligence: _GenderPrior(1.05, 0.95),
  // 외교형 — gender-neutral
  Attribute.sociability: _GenderPrior(1.00, 1.00),
  // 예술가형 — 才子·才女 양면. neutral
  Attribute.emotionality: _GenderPrior(1.00, 1.00),
  // 현자형 — 君子·賢者 약한 male-lean
  Attribute.stability: _GenderPrior(1.05, 0.95),
  // 연예인형 — 桃花·美色 강한 female-lean
  Attribute.sensuality: _GenderPrior(0.90, 1.10),
  // 신의형 — gender-neutral
  Attribute.trustworthiness: _GenderPrior(1.00, 1.00),
  // 호감형 — 美人 약한 female-lean
  Attribute.attractiveness: _GenderPrior(0.95, 1.05),
  // 정열형 — 의지·정력 약한 male-lean (sexual dimorphism canon)
  Attribute.libido: _GenderPrior(1.05, 0.95),
};

double _priorOf(Attribute attr, Gender gender) {
  final p = _genderPriors[attr];
  if (p == null) return 1.0;
  return gender == Gender.male ? p.male : p.female;
}

/// scores → top-2 + special + shape-gated overlay.
///
/// [gender] 는 archetype 라벨의 canon-natural 매칭을 위한 prior 가중에 사용
/// (分類 ranking only). attribute 본 score 는 건드리지 않는다.
///
/// shape overlay 는 _checkSpecial 보다 우선 — shape 특수 상에 걸리면 그걸 반환.
ArchetypeResult classifyArchetype(
  Map<Attribute, double> scores,
  Gender gender, {
  FaceShape shape = FaceShape.unknown,
}) {
  // Gender-adjusted view of scores — ranking·special-check 용 한정.
  final adjusted = <Attribute, double>{
    for (final e in scores.entries) e.key: e.value * _priorOf(e.key, gender),
  };

  final sorted = adjusted.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final primary = sorted[0].key;
  final secondary = sorted[1].key;
  final topSet = {primary, secondary};

  return ArchetypeResult(
    primary: primary,
    secondary: secondary,
    primaryLabel: _archetypeLabels[primary]!,
    secondaryLabel: _archetypeLabels[secondary]!,
    specialArchetype:
        _checkShapeSpecial(shape, adjusted, topSet) ?? _checkSpecial(adjusted),
  );
}

/// Layer C — 얼굴형 × top-2 조합으로 발동되는 shape-gated special archetype.
/// 일반 special 보다 우선 검사 — 매치되면 그대로 반환.
///
/// 각 얼굴형당 2~3 개 distinctive 조합을 커버. 미매치는 `_checkSpecial` 의
/// 일반 special 로 fall-through.
String? _checkShapeSpecial(
  FaceShape shape,
  Map<Attribute, double> s,
  Set<Attribute> top2,
) {
  bool hit(Attribute a, Attribute b) => top2.containsAll({a, b});

  switch (shape) {
    case FaceShape.oval:
      // 달걀형 — 조화·복덕
      if (hit(Attribute.attractiveness, Attribute.sociability)) {
        return '행운상 (幸運相)';
      }
      if (hit(Attribute.trustworthiness, Attribute.attractiveness)) {
        return '귀인상 (貴人相)';
      }
      if (hit(Attribute.wealth, Attribute.stability)) {
        return '복록상 (福祿相)';
      }
      break;
    case FaceShape.oblong:
      // 세로로 긴 얼굴형 — 이지·감성
      if (hit(Attribute.intelligence, Attribute.trustworthiness)) {
        return '대학자상 (大學者相)';
      }
      if (hit(Attribute.intelligence, Attribute.emotionality)) {
        return '문인상 (文人相)';
      }
      if (hit(Attribute.emotionality, Attribute.trustworthiness)) {
        return '군자상 (君子相)';
      }
      break;
    case FaceShape.round:
      // 둥근 얼굴형 — 식복·원만
      if (hit(Attribute.wealth, Attribute.sociability)) {
        return '복덕상 (福德相)';
      }
      if (hit(Attribute.wealth, Attribute.stability)) {
        return '부자상 (富者相)';
      }
      if (hit(Attribute.sociability, Attribute.emotionality)) {
        return '온화상 (溫和相)';
      }
      break;
    case FaceShape.square:
      // 각진 얼굴형 — 우직·실행
      if (hit(Attribute.leadership, Attribute.stability)) {
        return '대들보상 (棟樑相)';
      }
      if (hit(Attribute.stability, Attribute.trustworthiness)) {
        return '반석상 (盤石相)';
      }
      if (hit(Attribute.leadership, Attribute.wealth)) {
        return '장수상 (將帥相)';
      }
      break;
    case FaceShape.heart:
      // 하트형 — 총명·예술
      if (hit(Attribute.intelligence, Attribute.emotionality)) {
        return '예인상 (藝人相)';
      }
      if (hit(Attribute.attractiveness, Attribute.sensuality)) {
        return '매혹상 (魅惑相)';
      }
      if (hit(Attribute.intelligence, Attribute.attractiveness)) {
        return '재자상 (才子相)';
      }
      break;
    case FaceShape.unknown:
      break;
  }
  return null;
}

String? _checkSpecial(Map<Attribute, double> s) {
  // SP-1: 제왕상
  if (s[Attribute.wealth]! >= 7.5 && s[Attribute.leadership]! >= 7.0) {
    return '제왕상 (帝王相)';
  }
  // SP-2: 도화상
  if (s[Attribute.sensuality]! >= 7.5 && s[Attribute.attractiveness]! >= 7.5) {
    return '도화상 (桃花相)';
  }
  // SP-3: 군사상
  if (s[Attribute.intelligence]! >= 7.5 && s[Attribute.stability]! >= 7.0) {
    return '군사상 (軍師相)';
  }
  // SP-4: 연예인상
  if (s[Attribute.sociability]! >= 7.5 && s[Attribute.attractiveness]! >= 7.0) {
    return '연예인상 (演藝人相)';
  }
  // SP-5: 복덕상
  if (s[Attribute.wealth]! >= 7.0 && s[Attribute.trustworthiness]! >= 7.0) {
    return '복덕상 (福德相)';
  }
  // SP-6: 대인상
  if (s[Attribute.leadership]! >= 7.0 &&
      s[Attribute.stability]! >= 7.0 &&
      s[Attribute.trustworthiness]! >= 7.0) {
    return '대인상 (大人相)';
  }
  // SP-7: 풍류상
  if (s[Attribute.libido]! >= 7.5 && s[Attribute.sensuality]! >= 7.0) {
    return '풍류상 (風流相)';
  }
  // SP-8: 천재상
  if (s[Attribute.intelligence]! >= 7.0 && s[Attribute.emotionality]! >= 7.0) {
    return '천재상 (天才相)';
  }
  // SP-9: 광인상
  if (s[Attribute.stability]! <= 3.0 && s[Attribute.emotionality]! >= 7.5) {
    return '광인상 (狂人相)';
  }
  // SP-10: 사기상
  if (s[Attribute.trustworthiness]! <= 3.0 && s[Attribute.sociability]! >= 7.0) {
    return '사기상 (詐欺相)';
  }
  return null;
}
