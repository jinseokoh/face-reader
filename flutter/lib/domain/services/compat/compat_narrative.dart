/// 궁합 서술 — 분석가 리포트 5섹션.
///
/// 출력 구조 (고정):
///   1. 한줄 요약 — 이 관계의 본질
///   2. 핵심 궁합 3가지 — 각 항목마다 (의미 / 실제 모습 / 장점 / 주의할 점)
///   3. 현실 갈등 시나리오 2~3개 — 구체적 상황
///   4. 관계 운영 전략 — 실제 행동 지침
///   5. 궁합 점수 + 이유
///
/// 원칙:
///   - 본문 text 에 한자 쓰지 않는다 (용어는 괄호 안에 보조로만).
///   - 추상 표현("기운이 흐른다") 금지. 실제 행동·상황으로 설명.
///   - 분석가 톤, 직설적으로, 감성팔이 금지.
library;

import 'compat_finding.dart';
import 'compat_label.dart';
import 'compat_pipeline.dart';
import 'five_element.dart';

/// 5-섹션 최종 출력.
class CompatNarrative {
  final String summary;
  final String corePoints;
  final String conflictScenarios;
  final String strategy;
  final String scoreReason;

  const CompatNarrative({
    required this.summary,
    required this.corePoints,
    required this.conflictScenarios,
    required this.strategy,
    required this.scoreReason,
  });

  List<String> get sectionsInOrder => [
        summary,
        corePoints,
        conflictScenarios,
        strategy,
        scoreReason,
      ];
}

/// pair-hash seed — 현재 구조에서는 decorative. 인터페이스 유지를 위해 남김.
int computePairSeed(String myReportId, String albumReportId) {
  int h(String s) {
    var x = 0x811c9dc5;
    for (final c in s.codeUnits) {
      x = ((x ^ c) * 0x01000193) & 0x7fffffff;
    }
    return x;
  }

  return (h(myReportId) * 31 + h(albumReportId)) & 0x7fffffff;
}

// ─────────────── 공통 라벨 ───────────────

String _labelHeadline(CompatLabel l) {
  switch (l) {
    case CompatLabel.cheonjakjihap:
      return '얼굴로 읽으면 흔치 않게 궁합이 잘 맞는 관계';
    case CompatLabel.sangkyeongyeobin:
      return '서로 예의를 지키며 안정적으로 오래갈 관계';
    case CompatLabel.mahapgaseong:
      return '노력해서 맞춰 가야 완성되는 관계';
    case CompatLabel.hyeonggeuknanjo:
      return '자주 부딪힐 소지가 크니 조심해서 지켜야 하는 관계';
  }
}

// ─────────────── finding 수집 ───────────────

List<CompatFinding> _gatherFindings(CompatibilityReport r) {
  final list = <CompatFinding>[];

  for (final e in r.palacePair.evidence) {
    list.add(CompatFinding.fromPalace(e));
  }
  for (final e in r.organPair.evidence) {
    list.add(CompatFinding.fromOrgan(e));
  }
  for (final e in r.zoneHarmony.evidence) {
    list.add(CompatFinding.fromZone(e));
  }
  // yinyang 은 단일 pattern.
  list.add(CompatFinding.fromYinYang(r.yinYangMatch));

  // 오행 관계는 방향성 자체가 관계의 본질이라 반드시 포함.
  list.add(CompatFinding.fromElement(r.myElement, r.albumElement, r.elementRelation));

  // 중요도 = |delta| * priority.
  list.sort((a, b) => b.priority.compareTo(a.priority));
  return list;
}

// ─────────────── section 1 — 한줄 요약 ───────────────

String _summarySection(CompatibilityReport r, List<CompatFinding> findings) {
  final total = r.total.toStringAsFixed(0);
  final headline = _labelHeadline(r.label);

  final myEl = r.myElement.primary.korean;
  final alEl = r.albumElement.primary.korean;
  final dir = _relationShort(r.elementRelation.kind);

  return '$headline입니다. '
      '$total점으로 ${r.label.korean}(네 등급 중 ${_labelTier(r.label)}번째)에 해당하고, '
      '얼굴 전체의 기본 성향은 $myEl과 $alEl이 만나 $dir 구도를 이룹니다.';
}

int _labelTier(CompatLabel l) {
  switch (l) {
    case CompatLabel.cheonjakjihap:
      return 1;
    case CompatLabel.sangkyeongyeobin:
      return 2;
    case CompatLabel.mahapgaseong:
      return 3;
    case CompatLabel.hyeonggeuknanjo:
      return 4;
  }
}

String _relationShort(ElementRelationKind k) {
  switch (k) {
    case ElementRelationKind.generating:
      return '내가 상대를 북돋우는';
    case ElementRelationKind.generated:
      return '상대가 나를 받쳐 주는';
    case ElementRelationKind.overcoming:
      return '내가 상대를 누르는';
    case ElementRelationKind.overcome:
      return '상대가 나를 누르는';
    case ElementRelationKind.identity:
      return '비슷한 결끼리 만나는';
  }
}

// ─────────────── section 2 — 핵심 궁합 3가지 ───────────────

String _coreSection(List<CompatFinding> findings) {
  final top = findings.take(3).toList();
  if (top.isEmpty) {
    return '특별히 도드라지는 패턴이 없습니다. 일상이 큰 기복 없이 평탄하게 흘러갈 조합입니다.';
  }

  final buf = StringBuffer();
  for (int i = 0; i < top.length; i++) {
    final f = top[i];
    buf.writeln('${i + 1}. ${f.title} (${f.domain})');
    buf.writeln('   - 의미: ${f.meaning}');
    buf.writeln('   - 실제 모습: ${f.observation}');
    buf.writeln('   - 장점: ${f.strength}');
    buf.writeln('   - 주의할 점: ${f.caution}');
    if (i != top.length - 1) buf.writeln();
  }
  return buf.toString().trimRight();
}

// ─────────────── section 3 — 갈등 시나리오 ───────────────

String _conflictSection(
    CompatibilityReport r, List<CompatFinding> findings) {
  final neg = findings.where((f) => f.delta < 0 && f.scenario != null).toList();
  neg.sort((a, b) => a.delta.compareTo(b.delta));
  final pick = neg.take(3).toList();

  if (pick.isEmpty) {
    return '두 분 사이에서 크게 문제될 지점은 특별히 읽히지 않습니다. '
        '평소 관계 관리를 기본 수준으로 해 주시면 큰 갈등 없이 흘러갈 조합입니다.';
  }

  final buf = StringBuffer();
  for (int i = 0; i < pick.length; i++) {
    final f = pick[i];
    buf.writeln('시나리오 ${i + 1} (${f.domain})');
    buf.writeln(f.scenario!);
    if (i != pick.length - 1) buf.writeln();
  }
  return buf.toString().trimRight();
}

// ─────────────── section 4 — 관계 운영 전략 ───────────────

String _strategySection(
    CompatibilityReport r, List<CompatFinding> findings) {
  final actions = <String>[];

  // 라벨별 기본 전략 1 개.
  switch (r.label) {
    case CompatLabel.cheonjakjihap:
      actions.add('궁합이 좋다고 방심하지 말 것. 일상적인 연락·기념일·생활습관 같은 기본기를 놓치는 순간 우위가 빠르게 줄어듭니다.');
      break;
    case CompatLabel.sangkyeongyeobin:
      actions.add('예의를 지키다 오히려 벽이 생기기 쉬운 관계이니, 한 달에 한 번 정도는 형식을 깨는 솔직한 대화나 둘만의 여행을 의도적으로 만들어 두시기 바랍니다.');
      break;
    case CompatLabel.mahapgaseong:
      actions.add('서로 맞춰 가는 단계를 초반 1~2년으로 잡고, 그 사이에는 "누가 옳은가"보다 "어떻게 맞춰 갈 것인가"를 대화의 기준으로 삼아야 합니다.');
      break;
    case CompatLabel.hyeonggeuknanjo:
      actions.add('감정으로 풀려 하지 말고, 돈·가사·시간 사용처럼 갈등이 잦은 영역은 규칙을 종이에 적어 두고 주기적으로 점검하는 구조로 바꿔야 합니다.');
      break;
  }

  // 부정 발견 상위 2 개에서 구체 행동 뽑기.
  final negActions = findings
      .where((f) => f.delta < 0 && f.action != null)
      .toList()
    ..sort((a, b) => a.delta.compareTo(b.delta));
  for (final f in negActions.take(2)) {
    actions.add(f.action!);
  }

  // 긍정 발견 상위 1 개 — 강점을 일부러 자주 꺼내라는 안내.
  final posActions = findings
      .where((f) => f.delta > 0 && f.action != null)
      .toList()
    ..sort((a, b) => b.delta.compareTo(a.delta));
  if (posActions.isNotEmpty) {
    actions.add(posActions.first.action!);
  }

  final buf = StringBuffer();
  for (int i = 0; i < actions.length; i++) {
    buf.writeln('${i + 1}. ${actions[i]}');
  }
  return buf.toString().trimRight();
}

// ─────────────── section 5 — 점수 + 이유 ───────────────

String _scoreSection(CompatibilityReport r) {
  final total = r.total.toStringAsFixed(0);
  final el = r.sub.elementScore.toStringAsFixed(0);
  final pa = r.sub.palaceScore.toStringAsFixed(0);
  final qi = r.sub.qiScore.toStringAsFixed(0);
  final it = r.intimacy.gateActive
      ? r.sub.intimacyScore.toStringAsFixed(0)
      : null;

  final strongest = _strongestLayer(r);
  final weakest = _weakestLayer(r);

  final buf = StringBuffer();
  buf.writeln('종합 점수: $total점 / 99점 만점 기준');
  buf.writeln();
  buf.writeln('세부 점수:');
  buf.writeln('- 오행(얼굴형 기본 성향): $el점');
  buf.writeln('- 궁위(결혼·가족·재물 등 12개 영역): $pa점');
  buf.writeln('- 기질(눈·코·입·삼정·음양의 짝): $qi점');
  if (it != null) {
    buf.writeln('- 친밀(부부·친밀감 영역, 30~50대 이성 기준): $it점');
  } else {
    buf.writeln('- 친밀: 이번 조합에서는 따로 계산하지 않음');
  }
  buf.writeln();
  buf.writeln('이 점수가 나온 이유:');
  buf.writeln('- 가장 강한 축은 "$strongest" 영역이라, 여기가 이 관계를 지탱합니다.');
  buf.writeln('- 가장 약한 축은 "$weakest" 영역이라, 갈등은 여기서 먼저 터집니다.');
  buf.write('- 등급상 네 단계 중 ${_labelTier(r.label)}번째(${r.label.korean})로, ${_labelHeadline(r.label)}에 해당합니다.');
  return buf.toString();
}

String _strongestLayer(CompatibilityReport r) {
  final pairs = <MapEntry<String, double>>[
    MapEntry('오행(기본 성향)', r.sub.elementScore),
    MapEntry('궁위(12개 생활 영역)', r.sub.palaceScore),
    MapEntry('기질(얼굴 세부 짝)', r.sub.qiScore),
    if (r.intimacy.gateActive)
      MapEntry('친밀(부부·친밀 영역)', r.sub.intimacyScore),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return pairs.first.key;
}

String _weakestLayer(CompatibilityReport r) {
  final pairs = <MapEntry<String, double>>[
    MapEntry('오행(기본 성향)', r.sub.elementScore),
    MapEntry('궁위(12개 생활 영역)', r.sub.palaceScore),
    MapEntry('기질(얼굴 세부 짝)', r.sub.qiScore),
    if (r.intimacy.gateActive)
      MapEntry('친밀(부부·친밀 영역)', r.sub.intimacyScore),
  ]..sort((a, b) => a.value.compareTo(b.value));
  return pairs.first.key;
}

// ─────────────── top-level builder ───────────────

CompatNarrative buildCompatNarrative({
  required CompatibilityReport report,
  required int pairSeed,
}) {
  final findings = _gatherFindings(report);
  return CompatNarrative(
    summary: _summarySection(report, findings),
    corePoints: _coreSection(findings),
    conflictScenarios: _conflictSection(report, findings),
    strategy: _strategySection(report, findings),
    scoreReason: _scoreSection(report),
  );
}

