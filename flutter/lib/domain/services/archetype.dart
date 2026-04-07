import 'package:face_reader/data/enums/attribute.dart';

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
  Attribute.attractiveness: '미인형',
  Attribute.libido: '정열형',
};

ArchetypeResult classifyArchetype(Map<Attribute, double> scores) {
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final primary = sorted[0].key;
  final secondary = sorted[1].key;

  return ArchetypeResult(
    primary: primary,
    secondary: secondary,
    primaryLabel: _archetypeLabels[primary]!,
    secondaryLabel: _archetypeLabels[secondary]!,
    specialArchetype: _checkSpecial(scores),
  );
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
