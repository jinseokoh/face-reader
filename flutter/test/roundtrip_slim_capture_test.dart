// Hive capture round-trip regression test.
// 첫 load → 재serialize → 다시 load 가 동일한 결과를 내야 한다. pull-to-refresh
// 를 여러 번 해도 분석기록이 사라지지 않음을 보증.

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slim-capture round-trip: 3 generations parse OK', () {
    final refs = referenceData[Ethnicity.eastAsian]![Gender.female]!;
    final metrics = <String, MetricResult>{};
    for (final info in metricInfoList) {
      final ref = refs[info.id]!;
      metrics[info.id] = MetricResult(
        id: info.id,
        rawValue: ref.mean,
        zScore: 0.0,
        zAdjusted: 0.0,
        metricScore: 0,
      );
    }

    final original = FaceReadingReport(
      ethnicity: Ethnicity.eastAsian,
      gender: Gender.female,
      ageGroup: AgeGroup.thirties,
      timestamp: DateTime(2026, 4, 19),
      source: AnalysisSource.album,
      supabaseId: 'test-uuid',
      metrics: metrics,
      nodeScores: const {},
      attributes: const {},
      rules: const [],
      archetype: const ArchetypeResult(
        primary: Attribute.wealth,
        secondary: Attribute.leadership,
        primaryLabel: '사업가형',
        secondaryLabel: '리더형',
      ),
      faceShape: FaceShape.oval,
    );

    final json1 = original.toJsonString();
    final gen1 = FaceReadingReport.fromJsonString(json1);
    expect(gen1.metrics.length, metricInfoList.length);

    final json2 = gen1.toJsonString();
    final gen2 = FaceReadingReport.fromJsonString(json2);
    expect(gen2.metrics.length, metricInfoList.length);

    final json3 = gen2.toJsonString();
    final gen3 = FaceReadingReport.fromJsonString(json3);
    expect(gen3.metrics.length, metricInfoList.length);

    expect(gen3.supabaseId, 'test-uuid');
    expect(gen3.faceShape, FaceShape.oval);
  });
}
