import 'dart:math';

import 'package:face_engine/domain/services/compat/compat_pipeline.dart';
import 'package:face_engine/domain/services/compat/compat_sub_display.dart';
import 'package:face_engine/domain/services/compat/five_element.dart';

/// 공유 카드 chip 톤. warm = 장점, cool = 단점.
enum CompatChipTone { warm, cool }

class CompatChip {
  final String label;
  final CompatChipTone tone;
  const CompatChip({required this.label, required this.tone});
}

/// total 점수 → (장점 갯수, 단점 갯수). 합 6.
/// label 경계(90/78/56, `compat_label.dart`) 와 정렬:
///  - 천작지합(≥90)   → 5/1   장점 압도
///  - 상경여빈(≥78)   → 4/2   장점 우세
///  - 마합가성(≥56)   → 3/3   균형
///  - 형극난조(<56)   → 2/4 또는 1/5 — 단점이 반드시 더 많이 노출
({int warm, int cool}) _ratioForTotal(double total) {
  if (total >= 90) return (warm: 5, cool: 1);
  if (total >= 78) return (warm: 4, cool: 2);
  if (total >= 56) return (warm: 3, cool: 3);
  if (total >= 35) return (warm: 2, cool: 4);
  return (warm: 1, cool: 5);
}

const _generalWarm = <String>[
  '#케미폭발',
  '#찰떡호흡',
  '#편안한사이',
  '#대화잘통함',
  '#든든함',
  '#서로의빛',
  '#운명적',
  '#티격태격해도결국찐',
  '#서로보완',
  '#안정감',
];

const _generalCool = <String>[
  '#속도차이주의',
  '#오해주의',
  '#서로배려필요',
  '#각자공간',
  '#기다림필요',
  '#표현차이',
  '#충돌주의',
  '#시간이답',
  '#예민포인트',
  '#감정조절',
];

CompatChip? _subChip(double? score, String highTag, String lowTag) {
  if (score == null) return null;
  if (score >= 65) return CompatChip(label: highTag, tone: CompatChipTone.warm);
  if (score <= 40) return CompatChip(label: lowTag, tone: CompatChipTone.cool);
  return null;
}

CompatChip _relationChip(ElementRelationKind k) {
  switch (k) {
    case ElementRelationKind.identity:
      return const CompatChip(label: '#닮은꼴', tone: CompatChipTone.warm);
    case ElementRelationKind.generating:
      return const CompatChip(
          label: '#키워주는관계', tone: CompatChipTone.warm);
    case ElementRelationKind.generated:
      return const CompatChip(
          label: '#기대고싶은상대', tone: CompatChipTone.warm);
    case ElementRelationKind.overcoming:
      return const CompatChip(
          label: '#내가리드해야', tone: CompatChipTone.cool);
    case ElementRelationKind.overcome:
      return const CompatChip(
          label: '#내가맞춰야', tone: CompatChipTone.cool);
  }
}

/// CompatibilityReport → 공유 카드용 hashtag chip list.
/// 점수 비례로 장점·단점 갯수 결정. seed 는 total 점수 기반(결정적).
List<CompatChip> chipsForCompat(CompatibilityReport r) {
  final warmList = <CompatChip>[];
  final coolList = <CompatChip>[];

  final el = subScoreToDisplay(CompatSubKind.element, r.sub.elementScore);
  final pa = subScoreToDisplay(CompatSubKind.palace, r.sub.palaceScore);
  final qi = subScoreToDisplay(CompatSubKind.qi, r.sub.qiScore);
  final it = subScoreToDisplay(
    CompatSubKind.intimacy,
    r.sub.intimacyScore,
    gateOff: !r.intimacy.gateActive,
  );

  final dataChips = <CompatChip>[
    _relationChip(r.elementRelation.kind),
    ?_subChip(el, '#오행상생', '#오행충돌'),
    ?_subChip(pa, '#궁위찰떡', '#궁위어긋남'),
    ?_subChip(qi, '#기질찰떡', '#기질충돌'),
    ?_subChip(it, '#친밀로맨틱', '#친밀과제'),
  ];
  for (final c in dataChips) {
    if (c.tone == CompatChipTone.warm) {
      warmList.add(c);
    } else {
      coolList.add(c);
    }
  }

  final ratio = _ratioForTotal(r.total);
  final rng = Random(r.total.round());
  final fillerWarm = [..._generalWarm]..shuffle(rng);
  final fillerCool = [..._generalCool]..shuffle(rng);

  while (warmList.length < ratio.warm && fillerWarm.isNotEmpty) {
    final tag = fillerWarm.removeLast();
    if (!warmList.any((c) => c.label == tag)) {
      warmList.add(CompatChip(label: tag, tone: CompatChipTone.warm));
    }
  }
  while (coolList.length < ratio.cool && fillerCool.isNotEmpty) {
    final tag = fillerCool.removeLast();
    if (!coolList.any((c) => c.label == tag)) {
      coolList.add(CompatChip(label: tag, tone: CompatChipTone.cool));
    }
  }

  return [
    ...warmList.take(ratio.warm),
    ...coolList.take(ratio.cool),
  ];
}

/// warm·cool 분리 결과 (UI에서 두 줄로 그릴 때).
({List<CompatChip> warm, List<CompatChip> cool}) splitChips(
    List<CompatChip> chips) {
  return (
    warm: chips.where((c) => c.tone == CompatChipTone.warm).toList(),
    cool: chips.where((c) => c.tone == CompatChipTone.cool).toList(),
  );
}
