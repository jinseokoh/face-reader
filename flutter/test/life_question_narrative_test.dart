// 인생 질문 서술 스모크 테스트.
// 각 섹션이 목표 평균 600자 내외로 생성되는지, 나이 게이팅이 올바르게 동작하는지
// fixture 몇 개를 돌려 확인한다. (최소 450자 기준으로 본문 누락 감지)

import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/life_question_narrative.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void _walkNodes(NodeScore ns, Map<String, NodeEvidence> out) {
  out[ns.nodeId] = NodeEvidence(
    nodeId: ns.nodeId,
    ownMeanZ: ns.ownMeanZ ?? 0.0,
    ownMeanAbsZ: ns.ownMeanAbsZ ?? 0.0,
    rollUpMeanZ: ns.rollUpMeanZ ?? 0.0,
    rollUpMeanAbsZ: ns.rollUpMeanAbsZ ?? 0.0,
  );
  for (final c in ns.children) {
    _walkNodes(c, out);
  }
}

/// "재물·권력 중정 강세" fixture — evidence_snapshot_test 와 동일.
const _fixtureZ = <String, double>{
  'nasalHeightRatio': 1.5,
  'nasalWidthRatio': -0.5,
  'mouthWidthRatio': 1.3,
  'lipFullnessRatio': 1.2,
  'cheekboneWidth': 1.5,
  'chinAngle': 1.2,
  'gonialAngle': 1.0,
  'midFaceRatio': 1.2,
  'lowerFaceRatio': 1.2,
  'philtrumLength': -1.2,
  'browSpacing': 1.5,
  'eyeFissureRatio': 1.1,
  'eyebrowThickness': 1.0,
  'foreheadWidth': 1.0,
  'upperFaceRatio': 0.8,
  'faceAspectRatio': 0.3,
  'faceTaperRatio': 0.5,
};

FaceReadingReport _buildReport({
  required Gender gender,
  required AgeGroup age,
}) {
  final tree = scoreTree(_fixtureZ);
  final detail = deriveAttributeScoresDetailed(
    tree: tree,
    gender: gender,
    isOver50: age.isOver50,
    hasLateral: false,
  );
  final normalized = normalizeAllScores(detail.total, gender);

  final attributes = <Attribute, AttributeEvidence>{
    for (final a in Attribute.values)
      a: AttributeEvidence(
        rawTotal: detail.total[a] ?? 0.0,
        normalizedScore: normalized[a] ?? 7.0,
        basePerNode: const {},
        distinctiveness: 0.0,
        contributors: const [],
      ),
  };

  final allRules = [
    ...detail.zoneRules,
    ...detail.organRules,
    ...detail.palaceRules,
    ...detail.ageRules,
    ...detail.lateralRules,
  ];
  final rules = allRules
      .map((r) => RuleEvidence(id: r.id, stage: 'mixed', effects: const {}))
      .toList();

  final nodeScores = <String, NodeEvidence>{};
  _walkNodes(tree, nodeScores);

  final sorted = normalized.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final primary = sorted[0].key;
  final secondary = sorted[1].key;

  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: gender,
    ageGroup: age,
    timestamp: DateTime(2026, 4, 18),
    source: AnalysisSource.album,
    metrics: const {},
    nodeScores: nodeScores,
    attributes: attributes,
    rules: rules,
    archetype: ArchetypeResult(
      primary: primary,
      secondary: secondary,
      primaryLabel: '사업가형',
      secondaryLabel: '리더형',
      specialArchetype: null,
    ),
  );
}

int _countSections(String full) {
  return RegExp(r'(^|\n)## ').allMatches(full).length;
}

List<String> _sectionBodies(String full) {
  final parts = full.split(RegExp(r'\n?## [^\n]+\n'));
  return parts.where((p) => p.trim().isNotEmpty).toList();
}

void main() {
  group('life question narrative', () {
    test('30대 남성: 7개 섹션 전부 생성, 각 섹션 300자 이상', () {
      final report =
          _buildReport(gender: Gender.male, age: AgeGroup.thirties);
      final full = assembleLifeQuestions(report);

      // v3 섹션: 재능·건강·재물·대인·연애·관능도·조언 = 7.
      // 바람기 섹션은 연애운 Shadow 의 1-line 특징으로 통합됨.
      expect(_countSections(full), 7,
          reason: '30대 이상은 관능도 포함 7개 섹션');
      expect(full.contains('## 바람기'), isFalse,
          reason: '바람기는 더 이상 독립 섹션이 아님');
      expect(full.contains('## 관능도'), isTrue);

      final bodies = _sectionBodies(full);
      for (var i = 0; i < bodies.length; i++) {
        expect(bodies[i].length, greaterThanOrEqualTo(300),
            reason: 'section $i too short: ${bodies[i].length} chars');
      }
    });

    test('20대 여성: 관능도 제외 6개 섹션', () {
      final report =
          _buildReport(gender: Gender.female, age: AgeGroup.twenties);
      final full = assembleLifeQuestions(report);

      expect(_countSections(full), 6,
          reason: '20대는 관능도·바람기 모두 제외, 연애운 안에서 바람기 한 줄 평 처리');
      expect(full.contains('## 바람기'), isFalse);
      expect(full.contains('## 관능도'), isFalse);
      expect(full.contains('## 연애운'), isTrue);
    });

    test('10대: 관능도 제외 6개 섹션', () {
      final report = _buildReport(gender: Gender.male, age: AgeGroup.teens);
      final full = assembleLifeQuestions(report);

      expect(_countSections(full), 6);
      expect(full.contains('## 바람기'), isFalse);
      expect(full.contains('## 관능도'), isFalse);
    });

    test('50대 이상: 7개 섹션 + 종합 조언에 덜어내기 맥락', () {
      final report =
          _buildReport(gender: Gender.female, age: AgeGroup.fifties);
      final full = assembleLifeQuestions(report);

      expect(_countSections(full), 7);
      expect(full.contains('덜어내는'), isTrue,
          reason: '50+ 라면 종합 조언이 \'덜어내는 기술\' 맥락으로 분기되어야 한다');
    });
  });
}
