/// face_engine — single entry point for the shared physiognomy + compat engine.
///
/// Compile (run from react/ via `pnpm build:shared`):
///   dart compile js -O1 lib/face_engine.dart
///     -o ../react/app/lib/shared/face_engine.js
///
/// **`-O1` 강제** — `-O2` 의 type elimination + class minification 이 vite/rollup
/// ESM 번들 + workerd 실행 단계에서 RTI subtype check 깨뜨린다.
///
/// Output:
///   globalThis.runEngine(metricsJson)        → solo share card payload
///   globalThis.runCompat(metricsJsonA, B)    → compat share card payload
///
/// Both functions return JSON strings carrying the same fields the Flutter
/// hero card 가 렌더하는 것 (line-by-line copy).
/// 친밀 챕터 / 갈등 시나리오 본문은 ⛔룰 #3 위반 — 외부 노출 금지.
library face_engine;

import 'dart:convert';
import 'dart:js_interop';

import 'package:face_engine/data/constants/archetype_catchphrase.dart';
import 'package:face_engine/data/constants/compat_hashtags.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/five_element.dart';

@JS('runEngine')
external set _setRunEngine(JSFunction fn);

@JS('runCompat')
external set _setRunCompat(JSFunction fn);

void main() {
  _setRunEngine = ((String metricsJson) {
    final report = FaceReadingReport.fromJsonString(metricsJson);
    return jsonEncode(_composeShareOutput(report));
  }).toJS;

  _setRunCompat = ((String metricsJsonA, String metricsJsonB) {
    final a = FaceReadingReport.fromJsonString(metricsJsonA);
    final b = FaceReadingReport.fromJsonString(metricsJsonB);
    final bundle = analyzeCompatibilityFromReports(my: a, album: b);
    return jsonEncode(_composeCompatOutput(a, b, bundle));
  }).toJS;
}

Map<String, dynamic> _composeShareOutput(FaceReadingReport report) {
  final arch = report.archetype;
  final sorted = report.attributeScores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top3 = sorted.take(3).toList();
  final weakest = sorted.last;

  final catchphrase = archetypeCatchphrase[arch.primary] ?? '';
  final strengthLine = attributeStrengthLine[top3.first.key] ?? '';
  final shadowLine = attributeShadowLine[weakest.key] ?? '';

  final chips = <Map<String, String>>[
    for (final e in top3)
      {
        'label': attributeChipHigh[e.key] ?? '#${e.key.labelKo}',
        'tone': 'warm',
      },
    {
      'label': attributeChipLow[weakest.key] ?? '#${weakest.key.labelKo}',
      'tone': 'cool',
    },
  ];

  final topRanks = [
    for (final e in top3)
      {
        'key': e.key.name,
        'labelKo': e.key.labelKo,
        'score': e.value,
      },
  ];

  return {
    'gender': report.gender.name,
    'primaryAttribute': arch.primary.name,
    'primaryLabel': arch.primaryLabel,
    'secondaryLabel': arch.secondaryLabel,
    'specialArchetype': arch.specialArchetype,
    'catchphrase': catchphrase,
    'strengthLine': strengthLine,
    'shadowLine': shadowLine,
    'chips': chips,
    'top3': topRanks,
    // archetype 별 supabase storage portrait — Flutter 와 동일 URL.
    'portraitUrl':
        'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/images/archetypes/${report.gender.name}.${arch.primary.name}.png',
  };
}

Map<String, dynamic> _composeCompatOutput(
  FaceReadingReport a,
  FaceReadingReport b,
  CompatibilityBundle bundle,
) {
  final report = bundle.report;
  final narrative = bundle.narrative;
  final label = report.label;

  final relation = '${report.myElement.primary.korean} × '
      '${report.albumElement.primary.korean}  ·  '
      '${_relationKindKo(report.elementRelation.kind)}';

  final chips = chipsForCompat(report)
      .map((c) => {
            'label': c.label,
            'tone': c.tone == CompatChipTone.warm ? 'warm' : 'cool',
          })
      .toList();

  return {
    // ⛔룰 #3: conflictScenarios·intimacyChapter·strategy·corePoints 본문은
    // share host 응답에 포함하지 않는다. summary + scoreReason 만 share-safe.
    'total': report.total,
    'label': label.name,
    'labelKo': label.korean,
    'labelHanja': label.hanja,
    'labelTagline': _labelTagline(label),
    'summary': narrative.summary,
    'scoreReason': narrative.scoreReason,
    'subScores': {
      'element': report.sub.elementScore,
      'palace': report.sub.palaceScore,
      'qi': report.sub.qiScore,
      'intimacy': report.sub.intimacyScore,
    },
    'elementRelationKind': report.elementRelation.kind.name,
    'relation': relation,
    'chips': chips,
    'a': _personSummary(a, report.myElement.primary),
    'b': _personSummary(b, report.albumElement.primary),
  };
}

Map<String, dynamic> _personSummary(FaceReadingReport r, FiveElement el) {
  return {
    'gender': r.gender.name,
    'genderKo': r.gender.labelKo,
    'ageGroupKo': r.ageGroup.labelKo,
    'faceShapeKo': r.faceShape.korean,
    'fiveElement': el.name,
    'fiveElementKo': el.korean,
    'demographic':
        '${r.gender.labelKo} · ${r.ageGroup.labelKo} · ${r.faceShape.korean}',
    'primaryLabel': r.archetype.primaryLabel,
  };
}

String _labelTagline(CompatLabel l) => switch (l) {
      CompatLabel.cheonjakjihap => '하늘이 맺어 준 드문 자리',
      CompatLabel.sangkyeongyeobin => '예를 지키며 오래가는 자리',
      CompatLabel.mahapgaseong => '다듬으며 이루어 가는 자리',
      CompatLabel.hyeonggeuknanjo => '서로를 조심히 지켜 줘야 하는 자리',
    };

String _relationKindKo(ElementRelationKind k) => switch (k) {
      ElementRelationKind.identity => '비슷한 결끼리 만나는 구도',
      ElementRelationKind.generating => '내가 상대를 살리는 상생',
      ElementRelationKind.generated => '상대가 나를 받쳐 주는 상생',
      ElementRelationKind.overcoming => '내가 상대를 다스리는 상극',
      ElementRelationKind.overcome => '상대가 나를 누르는 상극',
    };
