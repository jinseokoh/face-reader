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
import 'compat_phrase_pool.dart';
import 'compat_pipeline.dart';
import 'five_element.dart';

/// 5-섹션 최종 출력.
///
/// `intimacyChapter` 는 30~50대 이성 페어 전용 optional 섹션. gate 미통과
/// 시 null. 기본 `sectionsInOrder` 에는 포함시키지 않아 기존 구조(5 섹션)의
/// 계약이 깨지지 않는다 — UI/export 쪽에서 별도로 렌더한다.
class CompatNarrative {
  final String summary;
  final String corePoints;
  final String conflictScenarios;
  final String strategy;
  final String scoreReason;
  final String? intimacyChapter;

  const CompatNarrative({
    required this.summary,
    required this.corePoints,
    required this.conflictScenarios,
    required this.strategy,
    required this.scoreReason,
    this.intimacyChapter,
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
//
// 3부 구조로 농후함 확보:
//   (1) 섹션 도입 — label 별 갈등 전반 성격
//   (2) 각 시나리오 — 관상 근거 + 실제 궤적 + 폭발 지점(domain pool)
//   (3) 섹션 마무리 — 세 갈등의 공통분모

String _conflictSection(
    CompatibilityReport r, List<CompatFinding> findings, int pairSeed) {
  final neg = findings.where((f) => f.delta < 0 && f.scenario != null).toList();
  neg.sort((a, b) => a.delta.compareTo(b.delta));
  final pick = neg.take(3).toList();

  if (pick.isEmpty) {
    return '두 분 사이에서 눈에 띄게 터질 지점은 읽히지 않습니다. '
        '어른의 관계는 갈등이 없는 게 아니라 예측 가능한 쪽에 속하므로, '
        '평소 기본 관리만 해 주시면 크게 흔들릴 일이 드문 조합입니다. '
        '단, 예측 가능해 보이는 평온을 권태로 읽는 순간부터 숨은 마찰이 튀어나오니 그 경계를 놓치지 마시기 바랍니다.';
  }

  final buf = StringBuffer();

  // (1) 섹션 도입 — label 별.
  final introPool = conflictIntroByLabel[r.label] ?? const <String>[];
  final intro = _pickVariant(introPool, pairSeed);
  if (intro.isNotEmpty) {
    buf.writeln(intro);
    buf.writeln();
  }

  // (2) 각 시나리오 — 근거·궤적·폭발.
  for (int i = 0; i < pick.length; i++) {
    final f = pick[i];
    buf.writeln('시나리오 ${i + 1} — ${f.title} (${f.domain})');
    buf.writeln('관상 근거: ${f.meaning}');
    buf.writeln('실제 궤적: ${f.scenario!}');
    final escPool = conflictEscalationByDomain[f.domain] ??
        conflictEscalationByDomain['_default']!;
    final esc = _pickVariant(escPool, pairSeed + f.id.hashCode + i);
    buf.writeln('폭발 지점: $esc');
    if (i != pick.length - 1) buf.writeln();
  }

  // (3) 섹션 마무리 — 공통분모.
  final outroPool = conflictOutroByLabel[r.label] ?? const <String>[];
  final outro = _pickVariant(outroPool, pairSeed + 0x11D3);
  if (outro.isNotEmpty) {
    buf.writeln();
    buf.write(outro);
  }

  return buf.toString().trimRight();
}

// ─────────────── section 4 — 관계 운영 전략 ───────────────
//
// 3부 구조:
//   (1) 섹션 도입 — label 별 전략 방향
//   (2) 각 action — 근거 + 실행 디테일(domain pool) + 실패 패턴(domain pool)
//   (3) 섹션 마무리 — 실행 우선순위 힌트

/// 전략 1 항목 = (action 문장, 근거 도메인, 원본 finding).
/// label-specific action 은 finding 이 없어 rationale 이 label 기반.
class _StrategyItem {
  final String action;
  final String? domain; // domain null → label-level
  final String rationale;
  const _StrategyItem({
    required this.action,
    required this.domain,
    required this.rationale,
  });
}

String _strategySection(
    CompatibilityReport r, List<CompatFinding> findings, int pairSeed) {
  final items = <_StrategyItem>[];

  // 라벨별 기본 전략 1 개 — rationale 은 label 자체.
  switch (r.label) {
    case CompatLabel.cheonjakjihap:
      items.add(const _StrategyItem(
        action:
            '궁합이 좋다고 방심하지 말 것. 일상적인 연락·기념일·생활습관 같은 기본기를 놓치는 순간 우위가 빠르게 줄어듭니다.',
        domain: null,
        rationale: '이 관계는 이미 유리한 기본값을 갖고 있어, 전략의 핵심은 "유지"입니다.',
      ));
      break;
    case CompatLabel.sangkyeongyeobin:
      items.add(const _StrategyItem(
        action:
            '예의를 지키다 오히려 벽이 생기기 쉬운 관계이니, 한 달에 한 번 정도는 형식을 깨는 솔직한 대화나 둘만의 여행을 의도적으로 만들어 두시기 바랍니다.',
        domain: null,
        rationale: '격과 신뢰가 살아 있는 페어는 "언제 격을 내릴지" 합의가 관계 온도를 결정합니다.',
      ));
      break;
    case CompatLabel.mahapgaseong:
      items.add(const _StrategyItem(
        action:
            '서로 맞춰 가는 단계를 초반 1~2년으로 잡고, 그 사이에는 "누가 옳은가"보다 "어떻게 맞춰 갈 것인가"를 대화의 기준으로 삼아야 합니다.',
        domain: null,
        rationale: '속도 차이가 기본값인 페어는 결론 프레임을 과정 프레임으로 바꿔야 갈등이 줄어듭니다.',
      ));
      break;
    case CompatLabel.hyeonggeuknanjo:
      items.add(const _StrategyItem(
        action:
            '감정으로 풀려 하지 말고, 돈·가사·시간 사용처럼 갈등이 잦은 영역은 규칙을 종이에 적어 두고 주기적으로 점검하는 구조로 바꿔야 합니다.',
        domain: null,
        rationale: '충돌이 기본값인 페어는 개별 대화보다 합의된 규칙이 관계를 지탱합니다.',
      ));
      break;
  }

  // 부정 발견 상위 2 개 — 실제 finding.action + rationale = finding.meaning.
  final negFindings = findings
      .where((f) => f.delta < 0 && f.action != null)
      .toList()
    ..sort((a, b) => a.delta.compareTo(b.delta));
  for (final f in negFindings.take(2)) {
    items.add(_StrategyItem(
      action: f.action!,
      domain: f.domain,
      rationale: f.meaning,
    ));
  }

  // 긍정 발견 상위 1 개 — 강점을 놓치지 않기.
  final posFindings = findings
      .where((f) => f.delta > 0 && f.action != null)
      .toList()
    ..sort((a, b) => b.delta.compareTo(a.delta));
  if (posFindings.isNotEmpty) {
    final f = posFindings.first;
    items.add(_StrategyItem(
      action: f.action!,
      domain: f.domain,
      rationale: f.meaning,
    ));
  }

  final buf = StringBuffer();

  // (1) 섹션 도입.
  final introPool = strategyIntroByLabel[r.label] ?? const <String>[];
  final intro = _pickVariant(introPool, pairSeed + 0x2A);
  if (intro.isNotEmpty) {
    buf.writeln(intro);
    buf.writeln();
  }

  // (2) 각 item — action·근거·실행·실패.
  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final domainKey = item.domain ?? '_default';
    final howPool = strategyHowByDomain[domainKey] ??
        strategyHowByDomain['_default']!;
    final failPool = strategyFailureByDomain[domainKey] ??
        strategyFailureByDomain['_default']!;
    final how = _pickVariant(howPool, pairSeed + i * 37 + 13);
    final fail = _pickVariant(failPool, pairSeed + i * 41 + 29);

    buf.writeln('${i + 1}. ${item.action}');
    buf.writeln('   근거: ${item.rationale}');
    buf.writeln('   실행 디테일: $how');
    buf.writeln('   실패 패턴: $fail');
    if (i != items.length - 1) buf.writeln();
  }

  // (3) 섹션 마무리.
  final outroPool = strategyOutroByLabel[r.label] ?? const <String>[];
  final outro = _pickVariant(outroPool, pairSeed + 0x4E2);
  if (outro.isNotEmpty) {
    buf.writeln();
    buf.write(outro);
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

// ─────────────── intimacy chapter (30~50 이성 gate) ───────────────
//
// 성숙한 연령의 이성 관계를 관상학적 근거·실생활 관찰·bucket 별 조언의
// 3부 구조로 다루는 optional 섹션. intimacy.gateActive == false 면 null.
//
// bucket 분류:
//   - high (≥ 65): 기회 인식·관리 권유
//   - mid  (45~65): 실험·조율
//   - low  (< 45):  경계·속도 조절
//
// pair-seed 로 deterministic 하게 variant 선택. axis 문단은 cause →
// observation → bucket별 advice 3 문장으로 구성돼 근거와 농후함을 확보.

String _intimacyBucket(double sub) {
  if (sub >= 65) return 'high';
  if (sub >= 45) return 'mid';
  return 'low';
}

String? _intimacyChapter(CompatibilityReport r, int pairSeed) {
  if (!r.intimacy.gateActive) return null;

  final bucket = _intimacyBucket(r.sub.intimacyScore);
  final subInt = r.sub.intimacyScore.round().toString();

  final buf = StringBuffer();

  // Opener — bucket 별 pool, pair-seed 로 variant 선택. {X} 치환.
  final openerPool = intimacyOpenerByBucket[bucket] ?? const <String>[];
  final opener = _pickVariant(openerPool, pairSeed).replaceAll('{X}', subInt);
  if (opener.isNotEmpty) {
    buf.writeln(opener);
  }

  // Axis 문단 — cause + observation + bucket별 advice 3 문장으로 농후.
  for (final comp in r.intimacy.components) {
    final sign = _intimacySign(comp.value);
    final key = '${comp.id}-$sign';
    final detail = intimacyAxisDetails[key];
    if (detail == null) continue;

    final advice = bucket == 'high'
        ? detail.adviceHigh
        : bucket == 'low'
            ? detail.adviceLow
            // mid bucket 은 high/low 조언 중 더 중립적인 쪽 선택 — pair-seed 로
            // 분기시키되, 낮은 점수에서 들이대는 문제가 재발하지 않도록
            // low 쪽에 약간 기울여 둔다 (seed even → low, odd → high).
            : (((pairSeed + comp.id.hashCode) & 1) == 0
                ? detail.adviceLow
                : detail.adviceHigh);

    buf.writeln();
    buf.writeln('[${_axisLabel(comp.id)}]');
    buf.writeln(detail.cause);
    buf.writeln(detail.observation);
    buf.writeln(advice);
  }

  // Closing — bucket 별 pool.
  final closingPool = intimacyClosingByBucket[bucket] ?? const <String>[];
  final closing = _pickVariant(closingPool, pairSeed + 0x1F49C);
  if (closing.isNotEmpty) {
    buf.writeln();
    buf.write(closing);
  }

  return buf.toString().trim();
}

/// axis id → 본문 header. 한자는 괄호 풀이로만 허용.
String _axisLabel(String axisId) {
  switch (axisId) {
    case 'mwGong':
      return '남녀궁 — 눈 아래 와잠';
    case 'spouse':
      return '부부궁 — 눈꼬리 바깥';
    case 'lip':
      return '입 — 입술과 입꼬리';
    case 'eye':
      return '눈 — 시선의 결';
    default:
      return axisId;
  }
}

/// axis value → {pos, neu, neg}. axis 마다 range 가 달라(±10~±18) 일괄
/// ±3 컷오프를 쓰되, 실제 발동 패턴은 intimacy.dart 의 flag 조합이 극단
/// delta 를 만들어 내므로 대부분 neg/pos 로 깔끔하게 떨어진다.
String _intimacySign(double v) {
  if (v >= 3) return 'pos';
  if (v <= -3) return 'neg';
  return 'neu';
}

String _pickVariant(List<String> variants, int seed) {
  if (variants.isEmpty) return '';
  final idx = seed.abs() % variants.length;
  return variants[idx];
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
    conflictScenarios: _conflictSection(report, findings, pairSeed),
    strategy: _strategySection(report, findings, pairSeed),
    scoreReason: _scoreSection(report),
    intimacyChapter: _intimacyChapter(report, pairSeed),
  );
}

