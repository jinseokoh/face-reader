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
///   globalThis.runBattle(battleJson)         → battle result payload
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
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/battle.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/five_element.dart';
import 'package:face_engine/domain/services/compat/modern_vocab.dart';
import 'package:face_engine/domain/services/face_metrics_web.dart';

@JS('runEngine')
external set _setRunEngine(JSFunction fn);

@JS('runCompat')
external set _setRunCompat(JSFunction fn);

@JS('runMetrics')
external set _setRunMetrics(JSFunction fn);

@JS('runBattle')
external set _setRunBattle(JSFunction fn);

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

  // 웹 티저 — MediaPipe 468 landmarks([[x,y],...] JSON) → 26 정면 raw 메트릭.
  // 측면·z-score 는 안 함(report 로 감싸 runCompat/runEngine 이 처리).
  _setRunMetrics = ((String landmarksJson) {
    final raw = jsonDecode(landmarksJson) as List;
    final pts = [
      for (final p in raw)
        [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];
    return jsonEncode(WebFaceMetrics(pts).computeAll());
  }).toJS;

  // Chemistry Battle — chemistry_snapshot 기반 배틀 집계 (rev2 §3 payload 계약).
  // 입력: {"roomKind":"match"|"all","players":[{"slot":1,"name":"지은",
  //   "gender":"female","body":{…metrics body…}}, …]} — roomKind 누락 시 'all'.
  // 출력: {"players":[…],"pairs":[…],"best":{…}} — pairs 정렬 = 순위.
  // roomKind=='match' 면 이성 쌍만 pairs 에 담긴다(matchOnly).
  _setRunBattle = ((String battleJson) {
    final raw = jsonDecode(battleJson) as Map<String, dynamic>;
    final matchOnly = raw['roomKind'] == 'match';
    final players = [
      for (final p in raw['players'] as List)
        BattlePlayer(
          slot: (p['slot'] as num).toInt(),
          name: p['name'] as String,
          gender: p['gender'] as String,
          report: FaceReadingReport.fromJsonString(jsonEncode(p['body'])),
        ),
    ];
    return jsonEncode(computeBattle(players, matchOnly: matchOnly).toPayload());
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
    'genderKo': report.gender.labelKo,
    'ageGroupKo': report.ageGroup.labelKo,
    'ethnicityKo': report.ethnicity.labelKo,
    'faceShapeKo': report.faceShape.korean,
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
    // 새 디자인은 user thumbnail avatar 를 우선 사용 (share.tsx 가 별도 URL
    // 전달). portraitUrl 은 archetype fallback / legacy 호환용으로 유지.
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

  final relation = '${report.myElement.displayKorean} × '
      '${report.albumElement.displayKorean}  ·  '
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
    // demographic 은 sub-line 으로 ageGroup + gender + secondary 기질.
    // 메인 label 은 archetype.primaryLabel (CompatSide 가 표시).
    // e.g. "40대 남성 신의형기질" (sub) + "기업가형" (main).
    'demographic':
        '${r.ageGroup.labelKo} ${r.gender.labelKo} ${r.archetype.secondaryLabel}기질',
    'primaryLabel': r.archetype.primaryLabel,
    'secondaryLabel': r.archetype.secondaryLabel,
  };
}

String _labelTagline(CompatLabel l) => switch (l) {
      CompatLabel.cheonjakjihap => '하늘이 맺어 준 드문 자리',
      CompatLabel.geumseulsanghwa => '서로 잘 어우러져 화목한 자리',
      CompatLabel.mahapgaseong => '다듬으며 이루어 가는 자리',
      CompatLabel.hyeonggeuknanjo => '서로를 조심히 지켜 줘야 하는 자리',
    };

/// SSOT — Flutter 앱의 `ElementRelationKindModernVocab.modernKo` 와 동일
/// 모던·구어체 라벨에 위임. 이전엔 격식체 ("내가 상대를 살리는 상생" 등) 를
/// 별도로 갖고 있었으나 두 채널 (web/app) 라벨 통일 위해 폐기.
String _relationKindKo(ElementRelationKind k) => k.modernKo;
