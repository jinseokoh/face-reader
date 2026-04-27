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
/// "AI 관상가 평가" / "궁합 분석" 카드가 렌더하는 것 (line-by-line copy).
/// 친밀 챕터 / 갈등 시나리오 본문은 ⛔룰 #3 위반 — 외부 노출 금지.
library face_engine;

import 'dart:convert';
import 'dart:js_interop';

import 'package:face_engine/data/constants/archetype_catchphrase.dart';
import 'package:face_engine/data/enums/attribute.dart';
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

  return {
    // ⛔룰 #3: conflictScenarios·intimacyChapter·strategy·corePoints 본문은
    // share host 응답에 포함하지 않는다. summary + scoreReason 만 share-safe.
    'total': report.total,
    'label': report.label.name,
    'labelKo': report.label.korean,
    'labelHanja': report.label.hanja,
    'summary': narrative.summary,
    'scoreReason': narrative.scoreReason,
    'subScores': {
      'element': report.sub.elementScore,
      'palace': report.sub.palaceScore,
      'qi': report.sub.qiScore,
      'intimacy': report.sub.intimacyScore,
    },
    'elementRelationKind': report.elementRelation.kind.name,
    'a': {
      'gender': a.gender.name,
      'primaryAttribute': a.archetype.primary.name,
      'primaryLabel': a.archetype.primaryLabel,
      'fiveElement': report.myElement.primary.name,
      'portraitUrl':
          'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/images/archetypes/${a.gender.name}.${a.archetype.primary.name}.png',
    },
    'b': {
      'gender': b.gender.name,
      'primaryAttribute': b.archetype.primary.name,
      'primaryLabel': b.archetype.primaryLabel,
      'fiveElement': report.albumElement.primary.name,
      'portraitUrl':
          'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/images/archetypes/${b.gender.name}.${b.archetype.primary.name}.png',
    },
  };
}
