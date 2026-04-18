// Rich evidence snapshot — Contributor / RuleEvidence 스키마와 파이프라인
// 결합 거동을 얼어붙힌다. 고정 z-map 하나로 scoreTree → derive → normalize
// 까지 돌려 "어떤 rule 이 발동하고, 어떤 contributor 가 상위로 오고, 정규화
// 후 몇 점인가" 를 한 개의 snapshot 문자열로 고정. A1~A4 + Step 5 재보정
// 이후의 안정 상태.
//
// 재생성: `flutter test test/evidence_snapshot_test.dart -r expanded` 로 로컬
// 실행 후 failing snapshot 의 actual 을 expected 에 복사. 재보정/룰 추가는
// 이 파일의 goldenSnapshot 교체를 항상 동반한다.

import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// "재물·권력 중정 강세" 프로파일.
/// - 코·광대·입·턱 강 → O-NM1, O-CK, O-CKN, O-CKC, O-CH 기대 발동
/// - 명궁 넓음, 인중 짧음 → P-09, O-PH1 기대 발동
/// - 중정·하정 비율 큼 → Z-11, Z-12 기대 발동
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

String _summarize() {
  final tree = scoreTree(_fixtureZ);
  final detail = deriveAttributeScoresDetailed(
    tree: tree,
    gender: Gender.male,
    isOver50: false,
    hasLateral: false,
  );

  final normalized = normalizeAllScores(detail.total, Gender.male);

  final ruleIds = <String>[
    ...detail.zoneRules.map((r) => 'Z:${r.id}'),
    ...detail.organRules.map((r) => 'O:${r.id}'),
    ...detail.palaceRules.map((r) => 'P:${r.id}'),
    ...detail.ageRules.map((r) => 'A:${r.id}'),
    ...detail.lateralRules.map((r) => 'L:${r.id}'),
  ]..sort();

  final scoreLines = Attribute.values.map((a) {
    final n = normalized[a]!.toStringAsFixed(1);
    return '${a.name.padRight(16)} $n';
  }).join('\n');

  final wealthTop3 = detail
      .topContributors(Attribute.wealth, n: 3)
      .map((c) => '${c.key}=${c.value.toStringAsFixed(2)}')
      .join(', ');

  final leadershipTop3 = detail
      .topContributors(Attribute.leadership, n: 3)
      .map((c) => '${c.key}=${c.value.toStringAsFixed(2)}')
      .join(', ');

  return '''
== rules (sorted) ==
${ruleIds.join(', ')}

== normalized scores ==
$scoreLines

== wealth top-3 contributors ==
$wealthTop3

== leadership top-3 contributors ==
$leadershipTop3
''';
}

void main() {
  test('evidence snapshot — 재물·권력 중정 강세 프로파일 (male, 정면-only)', () {
    // 2026-04-18 재조정(face/ear 제외, 9-node) + Opt-A distinctiveness + Opt-B
    // rule tuning + Opt-F rank/global 0.40/0.60 + 상관 MC quantile 반영 후 고정값.
    // ignore: prefer_const_declarations
    final goldenSnapshot = '''
== rules (sorted) ==
O:O-CH, O:O-CK, O:O-CKC, O:O-EB1, O:O-EM, O:O-PH1, P:P-03, P:P-05, P:P-09, Z:Z-11, Z:Z-12

== normalized scores ==
wealth           8.3
leadership       8.6
intelligence     7.8
sociability      9.3
emotionality     9.5
stability        8.1
sensuality       9.0
trustworthiness  8.8
attractiveness   9.7
libido           10.0

== wealth top-3 contributors ==
Z-11=0.50, P-09=0.50, O-CK=0.30

== leadership top-3 contributors ==
O-EB1=1.50, O-CH=1.00, O-CK=0.80
''';

    final actual = _summarize();
    expect(actual, goldenSnapshot);
  });
}
