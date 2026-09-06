// 첫인상 엔진 — 세 층의 정합성, 백분위 보간, 실측 분포, 두 얼굴 지표.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/constants/impression_quantiles.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/impression_features.dart';

import 'support/aaf_faces.dart';

void main() {
  final ids = metricInfoList.map((m) => m.id).toList();

  group('세 층 정합성', () {
    test('1층의 feature 는 전부 2층에 정의돼 있다', () {
      final defined = {
        for (final s in impressionFeatureSpecs) s.id,
        averagenessFeatureId,
      };
      for (final link in impressionEvidence) {
        expect(defined, contains(link.feature),
            reason: '${link.axis.name} → ${link.feature}');
      }
    });

    test('2층의 계측은 전부 referenceData 가 있는 26개 안에 있다', () {
      for (final s in impressionFeatureSpecs) {
        expect(ids, contains(s.metric), reason: s.id);
      }
    });

    test('모든 축에 주(primary) 근거가 하나 이상 있고 출처가 붙어 있다', () {
      for (final a in ImpressionAxis.values) {
        final links = impressionEvidence.where((l) => l.axis == a);
        expect(links.any((l) => l.tier == EvidenceTier.primary), isTrue,
            reason: a.name);
        for (final l in links) {
          expect(l.sources, isNotEmpty, reason: '${a.name}/${l.feature}');
        }
      }
    });

    test('분위표는 성별 × 4축 × 21점이고 단조 증가한다', () {
      for (final g in Gender.values) {
        for (final a in ImpressionAxis.values) {
          final q = impressionQuantiles[g]![a]!;
          expect(q.length, 21, reason: '${g.name}/${a.name}');
          for (var i = 1; i < q.length; i++) {
            expect(q[i], greaterThanOrEqualTo(q[i - 1]));
          }
        }
      }
    });
  });

  group('백분위 보간', () {
    final q = [for (var i = 0; i <= 20; i++) i.toDouble()];
    test('구간 끝점과 중간', () {
      expect(percentileFromQuantiles(-1, q), 0);
      expect(percentileFromQuantiles(0, q), 0);
      expect(percentileFromQuantiles(10, q), closeTo(50, 1e-9));
      expect(percentileFromQuantiles(10.5, q), closeTo(52.5, 1e-9));
      expect(percentileFromQuantiles(20, q), 100);
      expect(percentileFromQuantiles(99, q), 100);
    });
  });

  group('AAF 실측 분포', () {
    final faces = loadAafFaces();
    for (final g in Gender.values) {
      test('${g.name}: 축별 백분위 중앙값이 50 근처, 10~90 이 고르게 채워진다',
          () {
        final byAxis = <ImpressionAxis, List<double>>{
          for (final a in ImpressionAxis.values) a: <double>[],
        };
        for (final f in faces.where((f) => f.gender == g)) {
          final p = computeFirstImpression(f.z,
              gender: g, referenceMetricIds: ids);
          for (final a in ImpressionAxis.values) {
            byAxis[a]!.add(p[a]);
          }
        }
        for (final a in ImpressionAxis.values) {
          final s = byAxis[a]!..sort();
          final median = s[s.length ~/ 2];
          expect(median, closeTo(50, 3), reason: '${g.name}/${a.name}');
          final p10 = s[(s.length * 0.1).floor()];
          final p90 = s[(s.length * 0.9).floor()];
          expect(p10, closeTo(10, 3), reason: '${g.name}/${a.name} p10');
          expect(p90, closeTo(90, 3), reason: '${g.name}/${a.name} p90');
        }
      });
    }

    test('무작위 쌍의 닮은 정도 중앙값이 50 근처', () {
      final sims = <double>[];
      for (var i = 0; i + 1 < faces.length && i < 4000; i += 2) {
        sims.add(
            computeGeometrySimilarity(faces[i].z, faces[i + 1].z, ids).overall);
      }
      sims.sort();
      expect(sims[sims.length ~/ 2], closeTo(50, 4));
    });
  });

  group('두 얼굴 지표', () {
    final faces = loadAafFaces();
    final a = faces[0];
    final b = faces[1];
    final pa = computeFirstImpression(a.z, gender: a.gender, referenceMetricIds: ids);
    final pb = computeFirstImpression(b.z, gender: b.gender, referenceMetricIds: ids);

    test('같은 얼굴: 닮음 100 · 유사도 100 · 보완 0 · 조화 = 축 평균', () {
      final r = analyzePair(
          zA: a.z, profileA: pa, zB: a.z, profileB: pa, referenceMetricIds: ids);
      expect(r.similarity.overall, closeTo(100, 1e-9));
      for (final v in r.similarity.byRegion.values) {
        expect(v, closeTo(100, 1e-9));
      }
      expect(r.impressionSimilarity, closeTo(100, 1e-9));
      expect(r.complementarity, closeTo(0, 1e-9));
      final mean = pairAxes.map((ax) => pa[ax]).reduce((x, y) => x + y) /
          pairAxes.length;
      expect(r.harmony, closeTo(mean, 1e-9));
      expect(r.chemistry, closeTo(r.harmony + 100, 1e-9));
    });

    test('다른 얼굴: 범위와 합 관계, 매력 축은 두 얼굴 지표에 안 들어간다', () {
      final r = analyzePair(
          zA: a.z, profileA: pa, zB: b.z, profileB: pb, referenceMetricIds: ids);
      expect(r.similarity.overall, inInclusiveRange(0, 100));
      expect(r.impressionSimilarity, inInclusiveRange(0, 100));
      expect(r.harmony, inInclusiveRange(0, 100));
      expect(r.complementarity, inInclusiveRange(0, 100));
      expect(r.impressionSimilarity + r.complementarity, closeTo(100, 1e-9));
      expect(r.chemistry,
          closeTo(r.harmony + r.complementarity + r.similarity.overall, 1e-9));
      expect(pairAxes, isNot(contains(ImpressionAxis.attractive)));
    });

    test('영역 분할은 26개 계측을 정확히 한 번씩 덮는다', () {
      final all = geometryRegions.values.expand((e) => e).toList();
      expect(all.toSet().length, all.length);
      expect(all.toSet(), ids.toSet());
    });
  });
}
