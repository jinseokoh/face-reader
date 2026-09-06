// 모델 버전·재현성 (APPLE.md §58·§59·§75 회귀).
//
// 같은 랜드마크 → 같은 계측·대칭·첫인상 (엔진에 난수 없음). 아래 고정값은
// geometry 1.0.0 의 산출이다 — 값이 바뀌면 의도한 변경인지 확인하고
// `kGeometryModelVersion` 을 올린다.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/model_version.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/symmetry_metrics.dart';
import 'package:facely/domain/services/face_metrics.dart';

import 'support/fake_report.dart';

/// 결정적 합성 얼굴 468점 (face_metrics_isotropy_test 와 같은 식).
List<List<double>> _face() => [
      for (var i = 0; i < 468; i++)
        [
          (80.0 + (i * 2654435761) % 1000 / 1000.0 * 240.0) / 400,
          (40.0 + (i * 40503) % 997 / 997.0 * 320.0) / 400,
        ],
    ];

List<FaceMeshLandmark> _landmarks() =>
    [for (final p in _face()) FaceMeshLandmark(x: p[0], y: p[1], z: 0.0)];

void main() {
  final ids = metricInfoList.map((m) => m.id).toList();

  test('§59 재현성 — 같은 입력이면 계측·대칭·첫인상이 완전히 같다', () {
    final m1 = FaceMetrics(_landmarks()).computeAll();
    final m2 = FaceMetrics(_landmarks()).computeAll();
    expect(m1, equals(m2));
    expect(computeSymmetry(_face()), equals(computeSymmetry(_face())));
    final z = {for (final id in ids) id: sin(ids.indexOf(id).toDouble())};
    final p1 = computeFirstImpression(z,
        gender: Gender.male, referenceMetricIds: ids, symmetryZ: 0.3);
    final p2 = computeFirstImpression(z,
        gender: Gender.male, referenceMetricIds: ids, symmetryZ: 0.3);
    expect(p1.percentile, equals(p2.percentile));
  });

  test('§75 회귀 — geometry $kGeometryModelVersion 고정값', () {
    final m = FaceMetrics(_landmarks()).computeAll();
    final s = computeSymmetry(_face());
    expect(m['faceAspectRatio'], closeTo(1.2921179590458014, 1e-9));
    expect(m['mouthCornerAngle'], closeTo(-4.354416762560152, 1e-9));
    expect(m['eyeAspect'], closeTo(1.4165584161327898, 1e-9));
    expect(s['symOverall'], closeTo(1.698136894608505, 1e-9));
  });

  test('§58 리포트 — modelVersion 왕복 보존, 기록 전 카드는 null', () {
    final r = fakeReport(Random(5), gender: Gender.male, age: AgeGroup.values[1]);
    expect(r.modelVersion, isNull);
    final json = FaceReadingReport.fromJsonString(r.toBodyJson());
    expect(json.modelVersion, isNull);

    final stamped = FaceReadingReport.fromJsonString(
      r.toBodyJson().replaceFirst(
          '"schemaVersion"',
          '"modelVersion":{"geometry":"1.0.0","impression":"1.0.0","pair":"1.0.0"},'
          '"schemaVersion"'),
    );
    expect(stamped.modelVersion, equals(currentModelVersions()));
    expect(FaceReadingReport.fromJsonString(stamped.toJsonString()).modelVersion,
        equals(currentModelVersions()));
  });
}
