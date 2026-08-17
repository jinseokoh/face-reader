part of 'compat_narrative.dart';

// ═══════════════════════════════════════════════════════════════════════
// 궁합 서술 v2 — 섹션 6개의 v1 짝.
//
// v1 의 섹션 하나하나에 여기 짝이 있다. 내용이 아직 v1 과 같은 섹션도
// 별칭이 아니라 실물 함수로 둔다 — 별칭이면 "같기로 결정한 것"과 "아직
// 안 고친 것"이 코드에서 구분되지 않는다.
//
// 짝을 강제하는 장치는 `buildCompatNarrative` 의 version switch 다.
// 섹션이 늘면 두 분기를 모두 채워야 컴파일된다.
//
// v2 톤 규칙 — `narrative_corpus_v2.dart` 와 같은 기준.
//   사진 속 상대의 성격·행동을 단정하지 않는다.
//     금지: "이 남자는 확신이 서면 분명하게 다가오는 관상입니다"
//   사용자가 무슨 생각을 했는지 맞혔다고 주장하지 않는다.
//     금지: "아무 생각도 스치지 않았다면 이 점수는 나오지 않습니다"
//   미래를 말하지 않는다.
//   판단의 주어는 우리(측정) 아니면 전통이다.
//
// 궁합 상대는 **동의하지 않은 제3자**다. 그 사람의 성격과 앞으로의 행동을
// 단정하는 문장이 v1 에 47개 있다. v2 가 존재하는 가장 큰 이유가 이것이다.
// ═══════════════════════════════════════════════════════════════════════

/// 톤별 opener pool 매핑 — v2.
Map<Gender, Map<String, List<String>>> _openerPoolForToneV2(IntimacyTone tone) {
  switch (tone) {
    case IntimacyTone.pure:
      return intimacyPureOpenerByBucketByGenderV2;
    case IntimacyTone.flirty:
      return intimacyFlirtyOpenerByBucketByGenderV2;
    case IntimacyTone.spicy:
      return intimacySpicyOpenerByBucketByGenderV2;
  }
}

/// 톤별 closing pool 매핑 — v2.
Map<Gender, Map<String, List<String>>> _closingPoolForToneV2(
    IntimacyTone tone) {
  switch (tone) {
    case IntimacyTone.pure:
      return intimacyPureClosingByBucketByGenderV2;
    case IntimacyTone.flirty:
      return intimacyFlirtyClosingByBucketByGenderV2;
    case IntimacyTone.spicy:
      return intimacySpicyClosingByBucketByGenderV2;
  }
}

// ─────────────── §1 한줄 요약 ───────────────

String _summarySectionV2(CompatibilityReport r, List<CompatFinding> findings) {
  final total = r.total.toStringAsFixed(0);
  final headline = _labelHeadline(r.label);
  final myEl = r.myElement.displayKorean;
  final alEl = r.albumElement.displayKorean;

  return '${_oneLiner(r.elementRelation.kind)} '
      '$headline입니다. '
      '$total점, ${r.label.korean}(네 등급 중 ${_labelTier(r.label)}번째). '
      '얼굴 전체의 기본 성향은 $myEl × $alEl 구도예요.';
}

// ─────────────── §2 핵심 궁합 3가지 ───────────────

String _coreSectionV2(List<CompatFinding> findings) {
  final top = findings.take(3).toList();
  if (top.isEmpty) {
    return '특별히 도드라지는 특징이 없습니다. '
        '일상이 큰 기복 없이 평탄하게 흘러갈 조합이에요. '
        '다만 평탄함이 지루함으로 바뀌지 않도록, 작은 변화를 의식적으로 만들어 가세요.';
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

// ─────────────── §3 현실 갈등 시나리오 ───────────────

String _conflictSectionV2(
    CompatibilityReport r, List<CompatFinding> findings, int pairSeed) {
  final neg = findings.where((f) => f.delta < 0 && f.scenario != null).toList();
  neg.sort((a, b) => a.delta.compareTo(b.delta));
  final pick = neg.take(3).toList();

  if (pick.isEmpty) {
    return '두 분 사이에서 눈에 띄게 터질 지점은 읽히지 않습니다. '
        '어른의 관계에서 갈등이 없다는 건 불가능하지만, 이 조합은 예측 가능한 범위 안에 있어요. '
        '평소 기본 관리만 해 주시면 크게 흔들릴 일이 드문 조합입니다. '
        '단, 예측 가능해 보이는 평온을 권태로 읽는 순간부터 숨은 마찰이 튀어나오니 그 경계를 놓치지 마세요.';
  }

  final buf = StringBuffer();

  final introPool = conflictIntroByLabelV2[r.label] ?? const <String>[];
  final intro = _pickVariant(introPool, pairSeed);
  if (intro.isNotEmpty) {
    buf.writeln(intro);
    buf.writeln();
  }

  for (int i = 0; i < pick.length; i++) {
    final f = pick[i];
    buf.writeln('시나리오 ${i + 1} — ${f.title} (${f.domain})');
    buf.writeln('근거: ${f.meaning}');
    buf.writeln('실제로 나타나는 모습: ${f.scenario!}');
    final escPool = conflictEscalationByDomainV2[f.domain] ??
        conflictEscalationByDomainV2['_default']!;
    final esc = _pickVariant(escPool, pairSeed + f.id.hashCode + i);
    buf.writeln('확대 양상: $esc');
    if (i != pick.length - 1) buf.writeln();
  }

  final outroPool = conflictOutroByLabelV2[r.label] ?? const <String>[];
  final outro = _pickVariant(outroPool, pairSeed + 0x11D3);
  if (outro.isNotEmpty) {
    buf.writeln();
    buf.write(outro);
  }

  return buf.toString().trimRight();
}

// ─────────────── §4 관계 운영 전략 ───────────────

String _strategySectionV2(
    CompatibilityReport r, List<CompatFinding> findings, int pairSeed) {
  final items = _strategyItems(r, findings);

  final buf = StringBuffer();

  final introPool = strategyIntroByLabelV2[r.label] ?? const <String>[];
  final intro = _pickVariant(introPool, pairSeed + 0x2A);
  if (intro.isNotEmpty) {
    buf.writeln(intro);
    buf.writeln();
  }

  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final domainKey = item.domain ?? '_default';
    final howPool =
        strategyHowByDomainV2[domainKey] ?? strategyHowByDomainV2['_default']!;
    final failPool = strategyFailureByDomainV2[domainKey] ??
        strategyFailureByDomainV2['_default']!;
    final how = _pickVariant(howPool, pairSeed + i * 37 + 13);
    final fail = _pickVariant(failPool, pairSeed + i * 41 + 29);

    buf.writeln('${i + 1}. ${item.action}');
    buf.writeln('   근거: ${item.rationale}');
    buf.writeln('   실행 방법: $how');
    buf.writeln('   실패하는 경우: $fail');
    if (i != items.length - 1) buf.writeln();
  }

  final outroPool = strategyOutroByLabelV2[r.label] ?? const <String>[];
  final outro = _pickVariant(outroPool, pairSeed + 0x4E2);
  if (outro.isNotEmpty) {
    buf.writeln();
    buf.write(outro);
  }

  return buf.toString().trimRight();
}

// ─────────────── §5 이성적 끌림의 결 ───────────────

String _intimacyChapterV2(CompatibilityReport r, int pairSeed) {
  final tone = r.intimacy.tone;
  final bucket = _intimacyBucket(r.sub.intimacyScore);
  final subInt = r.sub.intimacyScore.round().toString();

  final openerByBucket = _openerPoolForToneV2(tone)[r.myGender] ??
      const <String, List<String>>{};
  final closingByBucket = _closingPoolForToneV2(tone)[r.myGender] ??
      const <String, List<String>>{};

  final buf = StringBuffer();

  final openerPool = openerByBucket[bucket] ?? const <String>[];
  final opener = _pickVariant(openerPool, pairSeed).replaceAll('{X}', subInt);
  if (opener.isNotEmpty) {
    buf.writeln(opener);
  }

  final axisDetails = (tone == IntimacyTone.spicy
          ? intimacySpicyAxisDetailsByGenderV2[r.myGender]
          : intimacyAxisDetailsByGenderV2[r.myGender]) ??
      const <String, IntimacyAxisDetail>{};
  for (final comp in r.intimacy.components) {
    final sign = _intimacySign(comp.value);
    final detail = axisDetails['${comp.id}-$sign'];
    if (detail == null) continue;

    final advice = bucket == 'high'
        ? detail.adviceHigh
        : bucket == 'low'
            ? detail.adviceLow
            : (((pairSeed + comp.id.hashCode) & 1) == 0
                ? detail.adviceLow
                : detail.adviceHigh);

    buf.writeln();
    buf.writeln('[${_axisLabel(comp.id)}]');
    buf.writeln(detail.cause);
    buf.writeln(detail.observation);
    buf.writeln(advice);
  }

  final closingPool = closingByBucket[bucket] ?? const <String>[];
  final closing = _pickVariant(closingPool, pairSeed + 0x1F49C);
  if (closing.isNotEmpty) {
    buf.writeln();
    buf.write(closing);
  }

  return buf.toString().trim();
}

// ─────────────── §6 궁합 점수와 이유 ───────────────

String _scoreSectionV2(CompatibilityReport r) {
  final total = r.total.toStringAsFixed(0);
  final el = subScoreToDisplay(CompatSubKind.element, r.sub.elementScore)!
      .toStringAsFixed(0);
  final pa = subScoreToDisplay(CompatSubKind.palace, r.sub.palaceScore)!
      .toStringAsFixed(0);
  final qi =
      subScoreToDisplay(CompatSubKind.qi, r.sub.qiScore)!.toStringAsFixed(0);
  final it = subScoreToDisplay(CompatSubKind.intimacy, r.sub.intimacyScore)!
      .toStringAsFixed(0);

  final strongest = _strongestLayer(r);
  final weakest = _weakestLayer(r);

  final buf = StringBuffer();
  buf.writeln('종합 점수: $total점 / 100점 만점 기준');
  buf.writeln();
  buf.writeln('세부 점수:');
  buf.writeln('- 가치관(얼굴형 기본 성향): $el점');
  buf.writeln('- 관심사(결혼·가족·재물 등 12개 영역): $pa점');
  buf.writeln('- 소통 스타일(눈·코·입·얼굴 3 구역·에너지 균형의 짝): $qi점');
  buf.writeln('- 이성적 끌림(밀착도·끌림 영역): $it점');
  buf.writeln();
  buf.writeln('이 점수가 나온 이유:');
  buf.writeln('- 가장 강한 축은 "$strongest" 영역이에요. 여기가 이 관계를 지탱합니다.');
  buf.writeln('- 가장 약한 축은 "$weakest" 영역이에요. 갈등은 여기서 먼저 터집니다.');
  buf.write('- 등급상 네 단계 중 ${_labelTier(r.label)}번째(${r.label.korean})로, '
      '${_labelHeadline(r.label)}에 해당합니다.');
  return buf.toString();
}
