/// Adapter — FaceReadingReport → CompatPersonInput.
///
/// pipeline 을 model 계층(FaceReadingReport) 에 decouple 해 두기 위해 이
/// 파일로 분리. 테스트·UI 양쪽에서 동일 adapter 사용.
library;

import '../../models/face_reading_report.dart';
import 'compat_narrative.dart';
import 'compat_pipeline.dart';

CompatPersonInput reportToCompatInput(FaceReadingReport report) {
  final zMap = <String, double>{};
  for (final e in report.metrics.entries) {
    zMap[e.key] = e.value.zAdjusted;
  }
  if (report.lateralMetrics != null) {
    for (final e in report.lateralMetrics!.entries) {
      zMap[e.key] = e.value.zAdjusted;
    }
  }
  final nodeZ = <String, double>{
    for (final e in report.nodeScores.entries) e.key: e.value.ownMeanZ,
  };
  return CompatPersonInput(
    zMap: zMap,
    nodeZ: nodeZ,
    lateralFlags: report.lateralFlags ?? const {},
    faceShape: report.faceShape,
    shapeConfidence: report.faceShapeConfidence ?? 0.0,
    gender: report.gender,
    ageGroup: report.ageGroup,
  );
}

/// End-to-end 편의 — 두 리포트 → report + narrative 번들.
class CompatibilityBundle {
  final CompatibilityReport report;
  final CompatNarrative narrative;

  const CompatibilityBundle({
    required this.report,
    required this.narrative,
  });
}

CompatibilityBundle analyzeCompatibilityFromReports({
  required FaceReadingReport my,
  required FaceReadingReport album,
}) {
  final myInput = reportToCompatInput(my);
  final albumInput = reportToCompatInput(album);
  final report = analyzeCompatibility(my: myInput, album: albumInput);
  final seed = computePairSeed(
    my.supabaseId ?? my.timestamp.toIso8601String(),
    album.supabaseId ?? album.timestamp.toIso8601String(),
  );
  final narrative = buildCompatNarrative(report: report, pairSeed: seed);
  return CompatibilityBundle(report: report, narrative: narrative);
}
