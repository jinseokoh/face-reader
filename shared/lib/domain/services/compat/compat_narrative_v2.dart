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

/// 등급의 전통 귀속 — 네 등급 이름은 우리가 지어낸 것이 아니라 관상·명리
/// 전통이 쓰던 말이다. 어느 자리를 보고 그렇게 불렀는지까지 한 줄로 밝힌다.
///
/// 48개 문장에 각각 귀속을 넣지 않고 빌더가 한 줄을 앞에 붙이는 방식이다.
/// 문장 풀은 seed 로 하나를 뽑으므로 개별 문장에 넣으면 귀속이 나왔다
/// 안 나왔다 한다. 근거는 조합마다 반드시 보여야 한다.
String _labelTraditionV2(CompatLabel l) {
  switch (l) {
    case CompatLabel.cheonjakjihap:
      return '전통 관상은 이런 짝을 천생연분이라 불렀습니다. '
          '두 얼굴의 오행이 서로를 살리고 열두 자리가 고르게 맞물릴 때 쓰던 말이에요.';
    case CompatLabel.geumseulsanghwa:
      return '전통 관상은 이런 짝을 금슬화합이라 불렀습니다. '
          '거문고와 비파가 음을 맞추듯 두 얼굴의 결이 어긋나지 않는다는 뜻이에요.';
    case CompatLabel.mahapgaseong:
      return '전통 관상은 이런 짝을 상부상조라 불렀습니다. '
          '한쪽이 모자란 자리를 다른 쪽이 채우는 구도로 보았다는 뜻이에요.';
    case CompatLabel.hyeonggeuknanjo:
      return '전통 관상은 이런 짝을 형극난조라 불렀습니다. '
          '오행이 서로를 누르는 자리가 있어 고르기가 쉽지 않다고 본 구도예요.';
  }
}

/// 판단의 층위를 밝히는 마무리 — 우리가 무엇을 근거로 말했는지.
/// 섹션마다 다르게 쓰되, 문장의 주어는 항상 우리(측정) 아니면 전통이다.
const String _v2Basis = '이 해석은 두 얼굴의 계측값과 전통 관상의 읽는 법을 '
    '겹쳐 놓은 것입니다. 두 사람의 앞일을 맞히려는 것이 아닙니다.';

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
    return '특별히 도드라지는 특징이 없습니다. 큰 기복 없이 흘러갈 조합이에요. '
        '다만 평탄함이 지루함으로 바뀌지 않도록 작은 변화를 의식적으로 만들어 가세요.';
  }

  // v1 은 의미·실제 모습·장점·주의할 점 네 칸을 모두 찍었는데, 템플릿에서
  // 네 칸이 같은 내용을 다르게 적은 것이라 읽을 때 같은 말을 네 번 듣게 된다.
  // 구체적인 장면(observation)과 경계(caution 첫 문장)만 남긴다.
  final buf = StringBuffer();
  buf.writeln('전통 관상은 두 사람을 볼 때 총점을 매기지 않고 '
      '열두 자리 가운데 어디가 맞물리는지를 따로 봤습니다. '
      '아래 세 가지가 이 두 얼굴에서 가장 크게 맞물린 자리입니다.');
  for (int i = 0; i < top.length; i++) {
    final f = top[i];
    buf.writeln();
    buf.writeln('${i + 1}. ${f.title} (${f.domain})');
    buf.writeln(f.observation.isNotEmpty ? f.observation : f.meaning);
    final caution = _firstSentence(f.caution);
    if (caution.isNotEmpty) buf.writeln('다만 $caution');
  }
  return buf.toString().trimRight();
}

/// 첫 문장만. 뒤 문장은 대개 앞 문장을 바꿔 말한 것이라 잘라도 뜻이 남는다.
String _firstSentence(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  final i = t.indexOf('. ');
  return i < 0 ? t : t.substring(0, i + 1);
}

// ─────────────── §3 현실 갈등 시나리오 ───────────────

String _conflictSectionV2(
    CompatibilityReport r, List<CompatFinding> findings, int pairSeed) {
  final neg = findings.where((f) => f.delta < 0 && f.scenario != null).toList();
  neg.sort((a, b) => a.delta.compareTo(b.delta));
  final pick = neg.take(2).toList();

  if (pick.isEmpty) {
    return '눈에 띄게 터질 지점은 읽히지 않습니다. 갈등이 없다는 뜻은 아니고, '
        '예측 가능한 범위 안에 있다는 뜻이에요. '
        '다만 그 평온을 권태로 읽는 순간부터 숨은 마찰이 나옵니다.';
  }

  // 라벨(근거·실제로 나타나는 모습·확대 양상)을 걷어냈다. 근거는 §2 에서
  // 이미 말했고, 여기서 읽고 싶은 것은 "그래서 무슨 장면이 벌어지는가" 다.
  final buf = StringBuffer();
  buf.writeln(_labelTraditionV2(r.label));

  for (int i = 0; i < pick.length; i++) {
    final f = pick[i];
    buf.writeln();
    buf.writeln('${i + 1}. ${f.title} (${f.domain})');
    buf.writeln(f.scenario!);
    final escPool = conflictEscalationByDomainV2[f.domain] ??
        conflictEscalationByDomainV2['_default']!;
    buf.writeln(_firstSentence(
        _pickVariant(escPool, pairSeed + f.id.hashCode + i)));
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
  final items = _strategyItems(r, findings).take(3).toList();

  // rationale 은 §2 의 meaning 과 같은 문장이라 뺐다. 실행 방법과 실패
  // 패턴도 둘 다 붙이면 조언 하나에 네 줄이 달린다. 하나만 쓴다.
  final buf = StringBuffer();
  buf.writeln('전통 관상은 맞지 않는 자리를 두고 사람을 바꾸라 하지 않았습니다. '
      '그 자리를 어떻게 다룰지를 말했어요.');

  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final domainKey = item.domain ?? '_default';
    final even = ((pairSeed + i) & 1) == 0;
    final pool = even
        ? (strategyHowByDomainV2[domainKey] ??
            strategyHowByDomainV2['_default']!)
        : (strategyFailureByDomainV2[domainKey] ??
            strategyFailureByDomainV2['_default']!);
    buf.writeln();
    buf.writeln('${i + 1}. ${_firstSentence(item.action)}');
    buf.writeln(_firstSentence(_pickVariant(pool, pairSeed + i * 37 + 13)));
  }

  final outroPool = strategyOutroByLabelV2[r.label] ?? const <String>[];
  final outro = _pickVariant(outroPool, pairSeed + 0x4E2);
  if (outro.isNotEmpty) {
    buf.writeln();
    buf.writeln(outro);
  }
  buf.writeln();
  buf.write(_v2Basis);
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
  if (opener.isNotEmpty) buf.writeln(opener);

  final axisDetails = (tone == IntimacyTone.spicy
          ? intimacySpicyAxisDetailsByGenderV2[r.myGender]
          : intimacyAxisDetailsByGenderV2[r.myGender]) ??
      const <String, IntimacyAxisDetail>{};

  // v1 은 네 축을 모두, 축마다 근거·관찰·조언 세 문장씩 찍었다. 열두 문장이
  // 이어지면 어느 것이 이 두 사람 이야기인지 묻히므로, 값이 큰 두 축만
  // 남기고 근거와 관찰을 한 문단으로 합친다.
  final ranked = [...r.intimacy.components]
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  for (final comp in ranked.take(2)) {
    final detail = axisDetails['${comp.id}-${_intimacySign(comp.value)}'];
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
    buf.writeln('${detail.cause} ${_firstSentence(detail.observation)}');
    buf.writeln(_firstSentence(advice));
  }

  final closingPool = closingByBucket[bucket] ?? const <String>[];
  final closing = _pickVariant(closingPool, pairSeed + 0x1F49C);
  if (closing.isNotEmpty) {
    buf.writeln();
    buf.write(_firstSentence(closing));
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
