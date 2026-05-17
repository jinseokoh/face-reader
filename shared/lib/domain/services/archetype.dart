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

/// Archetype 별 gender prior — 한국 관상학 canon 의 archetype 본래 gender
/// 함의를 분류 단계에 반영한다. 정규화된 attribute score (5~10) 에 곱해
/// *분류 ranking 용* 만으로 사용 — 원 score (attributes[].normalizedScore) 는
/// 건드리지 않는다.
///
/// 값 범위 0.90 ~ 1.10. neutral = 1.00. 분류 swap 위험 최소화 (top-1 ↔ top-2
/// 격차가 ~5% 이내일 때만 swap 가능).
///
/// 근거:
/// - 한국 관상 전통 archetype 의 gender 본 매핑 (장군·왕상·군자 등 → 남성,
///   도화·미인·현처 등 → 여성)
/// - 우리 archetype 라벨 본문이 이미 gender 분기되어 있다는 점 (의도적 redundancy)
const _genderPriors = <Attribute, _GenderPrior>{
  // 사업가형 — 재백궁(코) 약한 male-lean (transactional canon)
  Attribute.wealth: _GenderPrior(1.05, 0.95),
  // 리더형 — 장군·왕상 강한 male canon
  Attribute.leadership: _GenderPrior(1.10, 0.90),
  // 학자형 — 학사·군자 약한 male-lean (modern soft)
  Attribute.intelligence: _GenderPrior(1.05, 0.95),
  // 외교형 — gender-neutral
  Attribute.sociability: _GenderPrior(1.00, 1.00),
  // 예술가형 — 재인 양면. neutral
  Attribute.emotionality: _GenderPrior(1.00, 1.00),
  // 현자형 — 군자·현자 약한 male-lean
  Attribute.stability: _GenderPrior(1.05, 0.95),
  // 연예인형 — 도화·미색 강한 female-lean
  Attribute.sensuality: _GenderPrior(0.90, 1.10),
  // 신의형 — gender-neutral
  Attribute.trustworthiness: _GenderPrior(1.00, 1.00),
  // 호감형 — 미인 약한 female-lean
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
/// (분류 ranking only). attribute 본 score 는 건드리지 않는다.
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
        return '행운형';
      }
      if (hit(Attribute.trustworthiness, Attribute.attractiveness)) {
        return '귀인형';
      }
      if (hit(Attribute.wealth, Attribute.stability)) {
        return '복덕형';
      }
      break;
    case FaceShape.oblong:
      // 세로로 긴 얼굴형 — 이지·감성
      if (hit(Attribute.intelligence, Attribute.trustworthiness)) {
        return '큰 학자형';
      }
      if (hit(Attribute.intelligence, Attribute.emotionality)) {
        return '문인형';
      }
      if (hit(Attribute.emotionality, Attribute.trustworthiness)) {
        return '군자형';
      }
      break;
    case FaceShape.round:
      // 둥근 얼굴형 — 식복·원만
      if (hit(Attribute.wealth, Attribute.sociability)) {
        return '복 많은 형';
      }
      if (hit(Attribute.wealth, Attribute.stability)) {
        return '부자형';
      }
      if (hit(Attribute.sociability, Attribute.emotionality)) {
        return '온화한 형';
      }
      break;
    case FaceShape.square:
      // 각진 얼굴형 — 우직·실행
      if (hit(Attribute.leadership, Attribute.stability)) {
        return '대들보형';
      }
      if (hit(Attribute.stability, Attribute.trustworthiness)) {
        return '반석형';
      }
      if (hit(Attribute.leadership, Attribute.wealth)) {
        return '장군형';
      }
      break;
    case FaceShape.heart:
      // 하트형 — 총명·예술
      if (hit(Attribute.intelligence, Attribute.emotionality)) {
        return '예인형';
      }
      if (hit(Attribute.attractiveness, Attribute.sensuality)) {
        return '매혹형';
      }
      if (hit(Attribute.intelligence, Attribute.attractiveness)) {
        return '재능형';
      }
      break;
    case FaceShape.unknown:
      break;
  }
  return null;
}

String? _checkSpecial(Map<Attribute, double> s) {
  // SP-1: 제왕형 — 재물·리더십 둘 다 높음
  if (s[Attribute.wealth]! >= 7.5 && s[Attribute.leadership]! >= 7.0) {
    return '제왕형';
  }
  // SP-2: 매력형 — 관능·매력 둘 다 매우 높음
  if (s[Attribute.sensuality]! >= 7.5 && s[Attribute.attractiveness]! >= 7.5) {
    return '매력형';
  }
  // SP-3: 책사형 — 통찰·안정 둘 다 높음
  if (s[Attribute.intelligence]! >= 7.5 && s[Attribute.stability]! >= 7.0) {
    return '책사형';
  }
  // SP-4: 스타형 — 사교·매력 둘 다 높음
  if (s[Attribute.sociability]! >= 7.5 && s[Attribute.attractiveness]! >= 7.0) {
    return '스타형';
  }
  // SP-5: 복덕형 — 재물·신뢰 둘 다 높음
  if (s[Attribute.wealth]! >= 7.0 && s[Attribute.trustworthiness]! >= 7.0) {
    return '복덕형';
  }
  // SP-6: 큰그릇형 — 리더십·안정·신뢰 셋 다 높음
  if (s[Attribute.leadership]! >= 7.0 &&
      s[Attribute.stability]! >= 7.0 &&
      s[Attribute.trustworthiness]! >= 7.0) {
    return '큰그릇형';
  }
  // SP-7: 풍류형 — 정열·관능 둘 다 높음
  if (s[Attribute.libido]! >= 7.5 && s[Attribute.sensuality]! >= 7.0) {
    return '풍류형';
  }
  // SP-8: 천재형 — 통찰·감성 둘 다 높음
  if (s[Attribute.intelligence]! >= 7.0 && s[Attribute.emotionality]! >= 7.0) {
    return '천재형';
  }
  // SP-9: 광인형 — 안정 낮고 감성 매우 높음
  if (s[Attribute.stability]! <= 3.0 && s[Attribute.emotionality]! >= 7.5) {
    return '광인형';
  }
  // SP-10: 사기꾼형 — 신뢰 낮고 사교 높음
  if (s[Attribute.trustworthiness]! <= 3.0 && s[Attribute.sociability]! >= 7.0) {
    return '사기꾼형';
  }
  return null;
}
