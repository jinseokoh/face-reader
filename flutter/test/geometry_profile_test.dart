// 기하학 프로필(§7) — 영역별 "평균에 가까운 정도" 와 닮은 정도 문구(§25).
// 분위표가 AAF 실측이므로 같은 얼굴들에서 중앙값 50 이 재현되어야 한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/geometry_profile.dart';

import 'support/aaf_faces.dart';

void main() {
  final ids = metricInfoList.map((m) => m.id).toList();

  test('평균 얼굴(z=0)·완전 대칭은 모든 영역 100', () {
    final p = computeGeometryProfile(
      zByMetric: {for (final id in ids) id: 0.0},
      gender: Gender.male,
      symmetry: const {'symOverall': 0.0},
    );
    expect(p.keys, containsAll(geometryProfileIds));
    for (final v in p.values) {
      expect(v, closeTo(100, 1e-9));
    }
  });

  test('계측·대칭이 없으면 해당 항목이 빠진다', () {
    final p = computeGeometryProfile(zByMetric: const {}, gender: Gender.female);
    expect(p, isEmpty);
  });

  for (final g in Gender.values) {
    test('AAF ${g.name}: 영역별 점수 중앙값이 50 근처', () {
      final faces = loadAafFaces().where((f) => f.gender == g).toList();
      for (final region in geometryRegions.keys) {
        final s = [
          for (final f in faces)
            computeGeometryProfile(zByMetric: f.z, gender: g)[region]!,
        ]..sort();
        expect(s[s.length ~/ 2], closeTo(50, 3), reason: '${g.name} $region');
      }
    });
  }

  test('닮은 정도 문구 — 사분위 경계에서 단조', () {
    expect(similarityBandOf('overall', 100), SimilarityBand.verySimilar);
    expect(similarityBandOf('overall', 50.2), SimilarityBand.similar);
    expect(similarityBandOf('overall', 45), SimilarityBand.different);
    expect(similarityBandOf('overall', 0), SimilarityBand.veryDifferent);
    expect(SimilarityBand.similar.isSimilar, isTrue);
    expect(SimilarityBand.different.isSimilar, isFalse);
  });
}
