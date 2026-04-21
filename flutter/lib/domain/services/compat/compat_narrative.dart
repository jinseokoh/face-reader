/// Compat narrative 6-section assembler — §11.
///
/// Input: CompatibilityReport + pair seed (deterministic variant 선택).
/// Output: CompatNarrative — 6 섹션 Korean 본문.
///
/// 구성:
///   1. 총평 (overview)        — label opener + 4 sub-score snapshot
///   2. 五形相配                 — element relation kind + primary/secondary
///   3. 宮位照應                 — top 3 PP rule evidence
///   4. 氣質合章                 — top 1~2 organ + zone dominant + yinyang
///   5. 情性之合 (nullable)       — intimacy.gateActive 때만
///   6. 長久之道                 — label 기반 advice
library;

import 'dart:math';

import 'compat_label.dart';
import 'compat_phrase_pool.dart';
import 'compat_pipeline.dart';
import 'five_element.dart';
import 'organ_pair_rules.dart';
import 'palace.dart';
import 'yinyang_matcher.dart';

/// 6-section 최종 출력.
class CompatNarrative {
  final String overview;
  final String elementSection;
  final String palaceSection;
  final String qiSection;

  /// 30~50대 opposite-gender gate 미통과 시 null.
  final String? intimacySection;
  final String longTermSection;

  const CompatNarrative({
    required this.overview,
    required this.elementSection,
    required this.palaceSection,
    required this.qiSection,
    required this.intimacySection,
    required this.longTermSection,
  });

  List<String> get sectionsInOrder => [
        overview,
        elementSection,
        palaceSection,
        qiSection,
        if (intimacySection != null) intimacySection!,
        longTermSection,
      ];
}

/// pair-hash seed 로 variant 선택. §11 variant seed 계산.
int computePairSeed(String myReportId, String albumReportId) {
  // 단순 FNV-ish. report id 가 UUID 든 임시 id 든 안정적 int 로 매핑.
  int h(String s) {
    var x = 0x811c9dc5;
    for (final c in s.codeUnits) {
      x = ((x ^ c) * 0x01000193) & 0x7fffffff;
    }
    return x;
  }

  return (h(myReportId) * 31 + h(albumReportId)) & 0x7fffffff;
}

String _pick(List<String> pool, Random rng) =>
    pool.isEmpty ? '' : pool[rng.nextInt(pool.length)];

String _sign(double d) => d > 0.1 ? 'pos' : (d < -0.1 ? 'neg' : 'neu');

/// section 1 — 총평.
String _overviewSection(
    CompatibilityReport r, Random rng, CompatLabel label) {
  final opener = _pick(labelOverviewPhrases[label] ?? const [], rng);
  final el = r.sub.elementScore.toStringAsFixed(0);
  final pa = r.sub.palaceScore.toStringAsFixed(0);
  final qi = r.sub.qiScore.toStringAsFixed(0);
  final it = r.intimacy.gateActive
      ? r.sub.intimacyScore.toStringAsFixed(0)
      : '—';
  final total = r.total.toStringAsFixed(0);
  return '$opener\n\n'
      '총점 $total — 四柱로 보면 五形 $el · 宮位 $pa · 氣質 $qi · 情性 $it의 결이 쌓여 이 자리에 이릅니다. '
      '각 층의 울림이 서로 다르게 ${label.korean}의 괘를 만듭니다.';
}

/// section 2 — 五形相配.
String _elementSection(
    CompatibilityReport r, Random rng) {
  final kind = r.elementRelation.kind;
  var base = _pick(elementRelationPhrases[kind] ?? const [], rng);
  base = base
      .replaceAll('{my}', r.myElement.primary.hanja)
      .replaceAll('{album}', r.albumElement.primary.hanja);

  final myHybrid = r.myElement.isHybrid
      ? ' (나의 형은 ${r.myElement.primary.korean}에 ${r.myElement.secondary.korean}이 섞인 겸형)'
      : '';
  final albumHybrid = r.albumElement.isHybrid
      ? ' (상대의 형은 ${r.albumElement.primary.korean}에 ${r.albumElement.secondary.korean}이 섞인 겸형)'
      : '';

  return '$base\n\n'
      '내 얼굴은 ${r.myElement.primary.hanja}形${myHybrid}, '
      '상대는 ${r.albumElement.primary.hanja}形${albumHybrid}으로 읽힙니다. '
      '${kind.hanja}의 자리라 두 형의 기(氣)가 ${_relationDirection(kind)} 흐릅니다.';
}

String _relationDirection(ElementRelationKind kind) {
  switch (kind) {
    case ElementRelationKind.generating:
      return '내 쪽에서 상대로';
    case ElementRelationKind.generated:
      return '상대에서 내 쪽으로';
    case ElementRelationKind.overcoming:
      return '내 쪽이 상대를 누르는 방향으로';
    case ElementRelationKind.overcome:
      return '상대가 내 쪽을 누르는 방향으로';
    case ElementRelationKind.identity:
      return '같은 결로 나란히';
  }
}

/// section 3 — 宮位照應. top 3 PP rule by |delta|.
String _palaceSection(CompatibilityReport r, Random rng) {
  if (r.palacePair.evidence.isEmpty) {
    return '宮位照應 — 12 궁 모두 중용에 가까워 특별한 발동이 없습니다. '
        '큰 결의 차이 없이 흘러가는 조합.';
  }
  final sorted = [...r.palacePair.evidence]
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  final top = sorted.take(3).toList();
  final lines = <String>[];
  for (final e in top) {
    lines.add('• ${e.palace.hanja}: ${e.verdict}');
  }
  return '宮位照應 — 十二宮 중 가장 뚜렷이 울린 세 궁.\n\n'
      '${lines.join('\n')}\n\n'
      '이 세 결이 결혼 가중치의 중심축(妻妾 0.28 · 男女 0.22 · 命 0.15)에 '
      '얼마나 걸쳐 있느냐가 ${r.label.korean}의 괘를 결정했습니다.';
}

/// section 4 — 氣質合章. organ top 1~2 + zone dominant + yinyang.
String _qiSection(CompatibilityReport r, Random rng) {
  final organSorted = [...r.organPair.evidence]
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  final topOrgans = organSorted.take(2).toList();

  final yyPhrase = _pick(yinYangPhrases[r.yinYangMatch.kind] ?? const [], rng);

  final zoneLines = <String>[];
  final zoneSorted = [...r.zoneHarmony.evidence]
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  for (final p in zoneSorted.take(2)) {
    zoneLines.add('• ${p.verdict}');
  }

  final organLines = topOrgans.isEmpty
      ? '• 五官 특이 패턴은 잠잠, 중용의 조합.'
      : topOrgans
          .map((e) => '• ${e.organ.hanja}: ${e.verdict}')
          .join('\n');

  final zoneText = zoneLines.isEmpty ? '• 三停 특이 패턴 없음.' : zoneLines.join('\n');

  return '氣質合章 — 五官·三停·陰陽 세 축의 울림.\n\n'
      '[五官]\n$organLines\n\n'
      '[三停]\n$zoneText\n\n'
      '[陰陽] $yyPhrase';
}

/// section 5 — 情性之合. gate off 이면 null.
String? _intimacySection(CompatibilityReport r, Random rng) {
  if (!r.intimacy.gateActive) return null;
  final lines = <String>[];
  for (final c in r.intimacy.components) {
    final sign = _sign(c.value);
    final pool = intimacyAxisPhrases['${c.id}-$sign'] ?? const [];
    if (pool.isEmpty) continue;
    lines.add('• ${_pick(pool, rng)}');
  }
  if (lines.isEmpty) {
    lines.add('• 情性 네 축이 모두 중용 — 무난한 친밀 결합.');
  }
  final sub = r.sub.intimacyScore.toStringAsFixed(0);
  return '情性之合 — 男女宮 · 妻妾宮 · 입술 · 눈빛 네 축에서 읽은 친밀의 결.\n\n'
      '${lines.join('\n')}\n\n'
      '종합 情性 점수 $sub — 30~50대 이성 게이트 통과분.';
}

/// section 6 — 長久之道. label 기반 조언.
String _longTermSection(
    CompatibilityReport r, Random rng, CompatLabel label) {
  final advice = _pick(longTermAdvicePhrases[label] ?? const [], rng);
  return '長久之道 — 오래가기 위해 지켜야 할 결.\n\n$advice';
}

CompatNarrative buildCompatNarrative({
  required CompatibilityReport report,
  required int pairSeed,
}) {
  // 각 섹션은 같은 Random 에서 순차 추출 — pairSeed 고정이면 출력도 고정.
  final rng = Random(pairSeed);
  final label = report.label;
  return CompatNarrative(
    overview: _overviewSection(report, rng, label),
    elementSection: _elementSection(report, rng),
    palaceSection: _palaceSection(report, rng),
    qiSection: _qiSection(report, rng),
    intimacySection: _intimacySection(report, rng),
    longTermSection: _longTermSection(report, rng, label),
  );
}
