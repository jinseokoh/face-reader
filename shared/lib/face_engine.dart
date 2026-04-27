/// face_engine — single entry point for the shared physiognomy engine.
///
/// Compile (run from react/ via `pnpm build:shared`):
///   dart compile js -O2 lib/face_engine.dart
///     -o ../react/app/lib/shared/face_engine.js
///
/// Output exposes a global `runEngine(metricsJson: string): string` that:
///   1. parses metrics_json (FaceReadingReport.toJsonString v3 capture-only)
///   2. recomputes z / age-adjusted z / scoreTree / attribute pipeline /
///      archetype via the same Dart engine Flutter uses
///   3. returns a minimal share-ready JSON string
///        { score: int, archetype: string, highlights: [{title, detail}*3] }
///
/// Flutter (refine) consumes the Dart classes directly via
/// `package:face_engine/...` (path: ../shared in pubspec).
library face_engine;

import 'dart:convert';
import 'dart:js_interop';

import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';

@JS('runEngine')
external set _setRunEngine(JSFunction fn);

void main() {
  _setRunEngine = ((String metricsJson) {
    final report = FaceReadingReport.fromJsonString(metricsJson);
    final out = _composeShareOutput(report);
    return jsonEncode(out);
  }).toJS;
}

Map<String, dynamic> _composeShareOutput(FaceReadingReport report) {
  final scores = report.attributeScores;
  final primary = scores[report.archetype.primary] ?? 5.0;
  final secondary = scores[report.archetype.secondary] ?? 5.0;
  // Top-2 평균 (5.0~10.0 normalized) → 0~100 정수 점수.
  final score = (((primary + secondary) / 2) * 10).round().clamp(0, 99);

  final label = report.archetype.specialArchetype ?? report.archetype.primaryLabel;

  // attributes 의 모든 contributor 를 |value| 로 정렬 → top 3.
  final contributors = <_FlatContributor>[];
  for (final entry in report.attributes.entries) {
    for (final c in entry.value.contributors) {
      contributors.add(_FlatContributor(entry.key, c.id, c.value));
    }
  }
  contributors.sort((a, b) => b.absValue.compareTo(a.absValue));
  final top = contributors.take(3).toList();

  return {
    'score': score,
    'archetype': label,
    'highlights': top.map((c) => {
          'title': '${_attrKo(c.attribute)} — ${c.id}',
          'detail': c.value >= 0 ? '강점 +${c.value.toStringAsFixed(1)}' : '약점 ${c.value.toStringAsFixed(1)}',
        }).toList(),
  };
}

class _FlatContributor {
  final Attribute attribute;
  final String id;
  final double value;
  _FlatContributor(this.attribute, this.id, this.value);
  double get absValue => value < 0 ? -value : value;
}

String _attrKo(Attribute a) => switch (a) {
      Attribute.wealth => '재물',
      Attribute.leadership => '리더십',
      Attribute.intelligence => '지성',
      Attribute.sociability => '사교',
      Attribute.emotionality => '감성',
      Attribute.stability => '안정',
      Attribute.sensuality => '감각',
      Attribute.trustworthiness => '신뢰',
      Attribute.attractiveness => '매력',
      Attribute.libido => '정열',
    };
